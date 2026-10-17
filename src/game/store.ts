import { create } from "zustand";
import { persist } from "zustand/middleware";
import {
  BUILDINGS,
  PRESTIGE,
  type BuildingId,
  type FlockSnapshot,
  UPGRADES,
  bulkCost,
  clickValue,
  feathersFromEarned,
  goldenDelayScale,
  maxAffordable,
  nestEgg,
  productionPerSec,
  requirementMet,
  starterSeeds,
} from "./balance";
import { formatFlock } from "./format";

export const SAVE_KEY = "parrot-clicker-v1";

export type BuyQty = 1 | 10 | 100 | "max";

export type Buff = {
  prod: number;
  click: number;
  until: number;
  label: string;
};

export type Golden = { id: number; until: number };

export type Away = { amount: number; seconds: number };

type Data = {
  parrots: number;
  lifetime: number;
  handmade: number;
  clicks: number;
  buildings: Record<string, number>;
  upgrades: string[];
  cheatProd: number;
  cheatClick: number;
  buff: Buff | null;
  golden: Golden | null;
  nextGoldenAt: number;
  lastTick: number;
  muted: boolean;
  buyQty: BuyQty;
  startedAt: number;
  goldenClicks: number;
  cheatsUsed: number;
  /** Parrots actually produced this run. Cheats and the nest egg do not count. */
  runEarned: number;
  feathers: number;
  molts: number;
  prestige: Record<string, number>;
};

type Live = {
  appliedOffline: boolean;
  away: Away | null;
};

type Actions = {
  applyOffline: () => void;
  tick: (now: number) => void;
  squawk: () => number;
  buyBuilding: (id: BuildingId) => void;
  buyUpgrade: (id: string) => void;
  setBuyQty: (qty: BuyQty) => void;
  toggleMute: () => void;
  dismissAway: () => void;
  grant: (amount: number) => void;
  setCheatProd: (mult: number) => void;
  setCheatClick: (mult: number) => void;
  giftBuildings: (n: number) => void;
  giftUpgrades: () => void;
  summonGolden: () => void;
  claimGolden: () => string | null;
  /** Wipe the run. Keeps feathers. Pays nothing. */
  reset: () => void;
  /** Pay feathers for a permanent rank. */
  buyPrestige: (id: string) => void;
  /** Reset a clean run and bank feathers. Returns feathers gained, or 0. */
  molt: () => number;
};

export type GameState = Data & Live & Actions;

const OFFLINE_CAP = 7 * 24 * 60 * 60;
const GOLDEN_LIFE = 13_000;

function emptyBuildings(): Record<string, number> {
  const buildings: Record<string, number> = {};
  for (const b of BUILDINGS) buildings[b.id] = 0;
  return buildings;
}

function emptyPrestige(): Record<string, number> {
  const levels: Record<string, number> = {};
  for (const u of PRESTIGE) levels[u.id] = 0;
  return levels;
}

function freshData(now = Date.now()): Data {
  return {
    parrots: 0,
    lifetime: 0,
    handmade: 0,
    clicks: 0,
    buildings: emptyBuildings(),
    upgrades: [],
    cheatProd: 1,
    cheatClick: 1,
    buff: null,
    golden: null,
    nextGoldenAt: scheduleGolden(now, {}),
    lastTick: now,
    muted: false,
    buyQty: 1,
    startedAt: now,
    goldenClicks: 0,
    cheatsUsed: 0,
    runEarned: 0,
    feathers: 0,
    molts: 0,
    prestige: emptyPrestige(),
  };
}

type Kept = {
  muted: boolean;
  feathers: number;
  molts: number;
  prestige: Record<string, number>;
};

function beginRun(kept: Kept, now = Date.now()): Data {
  const data = freshData(now);
  const buildings = emptyBuildings();
  const seeds = starterSeeds(kept.prestige.seeds ?? 0);
  if (seeds > 0) buildings.seed = seeds;
  return {
    ...data,
    parrots: nestEgg(kept.prestige.egg ?? 0),
    buildings,
    muted: kept.muted,
    feathers: kept.feathers,
    molts: kept.molts,
    prestige: { ...emptyPrestige(), ...kept.prestige },
    nextGoldenAt: scheduleGolden(now, kept.prestige),
  };
}

function snap(data: Data): FlockSnapshot {
  return {
    buildings: data.buildings,
    upgrades: data.upgrades,
    cheatProd: data.cheatProd,
    cheatClick: data.cheatClick,
    buff: data.buff,
    prestige: data.prestige,
  };
}

function rollBuff(now: number): { kind: "prod" | "click" | "windfall" | "both"; buff: Buff | null; note: string } {
  const roll = Math.random();
  if (roll < 0.4) {
    return {
      kind: "prod",
      buff: { prod: 7, click: 1, until: now + 30_000, label: "Flock frenzy ×7" },
      note: "Flock frenzy — roosts run at ×7 for 30 seconds.",
    };
  }
  if (roll < 0.65) {
    return {
      kind: "click",
      buff: { prod: 1, click: 77, until: now + 13_000, label: "Beak frenzy ×77" },
      note: "Beak frenzy — taps hit ×77 for 13 seconds.",
    };
  }
  if (roll < 0.9) {
    return { kind: "windfall", buff: null, note: "Windfall" };
  }
  return {
    kind: "both",
    buff: { prod: 7, click: 7, until: now + 20_000, label: "Double frenzy ×7" },
    note: "Double frenzy — taps and roosts ×7 for 20 seconds.",
  };
}

function scheduleGolden(now: number, prestige: Record<string, number> = {}): number {
  const wait = Math.floor((45_000 + Math.floor(Math.random() * 90_000)) * goldenDelayScale(prestige));
  return now + Math.max(8_000, wait);
}

export function runIsClean(state: Pick<Data, "cheatsUsed" | "cheatProd" | "cheatClick">): boolean {
  return state.cheatsUsed === 0 && state.cheatProd === 1 && state.cheatClick === 1;
}

export function quoteFor(state: Data, id: BuildingId): { qty: number; cost: number } {
  const building = BUILDINGS.find((b) => b.id === id);
  if (!building) return { qty: 0, cost: 0 };
  const owned = state.buildings[id] ?? 0;
  const qty =
    state.buyQty === "max"
      ? maxAffordable(building.baseCost, owned, state.parrots)
      : state.buyQty;
  return { qty, cost: bulkCost(building.baseCost, owned, qty) };
}

export const useGame = create<GameState>()(
  persist(
    (set, get) => ({
      ...freshData(),
      appliedOffline: false,
      away: null,

      applyOffline: () => {
        const s = get();
        if (s.appliedOffline) return;
        const now = Date.now();
        const elapsed = Math.max(0, (now - s.lastTick) / 1000);
        const grantSec = Math.min(elapsed, OFFLINE_CAP);
        const buff = s.buff && s.buff.until > now ? s.buff : null;
        let amount = 0;
        if (grantSec > 8) {
          amount = productionPerSec({ ...snap(s), buff }, now) * grantSec;
        }
        set({
          appliedOffline: true,
          parrots: s.parrots + amount,
          lifetime: s.lifetime + amount,
          runEarned: s.runEarned + amount,
          lastTick: now,
          buff,
          golden: s.golden && s.golden.until > now ? s.golden : null,
          nextGoldenAt: s.nextGoldenAt > now ? s.nextGoldenAt : scheduleGolden(now, s.prestige),
          away: amount > 1 ? { amount, seconds: grantSec } : null,
        });
      },

      tick: (now: number) => {
        const s = get();
        if (!s.appliedOffline) return;
        let buff = s.buff;
        if (buff && buff.until <= now) buff = null;
        let golden = s.golden;
        let nextGoldenAt = s.nextGoldenAt;
        if (golden && golden.until <= now) {
          golden = null;
          nextGoldenAt = scheduleGolden(now, s.prestige);
        }
        if (!golden && now >= nextGoldenAt) {
          golden = { id: now, until: now + GOLDEN_LIFE };
        }
        const dt = (now - s.lastTick) / 1000;
        const idle =
          dt < 0.1 && buff === s.buff && golden === s.golden && nextGoldenAt === s.nextGoldenAt;
        if (idle) return;
        const step = Math.min(Math.max(dt, 0), OFFLINE_CAP);
        const gain = productionPerSec({ ...snap(s), buff }, now) * step;
        set({
          parrots: s.parrots + gain,
          lifetime: s.lifetime + gain,
          runEarned: s.runEarned + gain,
          lastTick: now,
          buff,
          golden,
          nextGoldenAt,
          away: step > 90 && gain > 1 ? { amount: gain, seconds: step } : s.away,
        });
      },

      squawk: () => {
        const s = get();
        const gain = clickValue(snap(s));
        set({
          parrots: s.parrots + gain,
          lifetime: s.lifetime + gain,
          handmade: s.handmade + gain,
          clicks: s.clicks + 1,
          runEarned: s.runEarned + gain,
        });
        return gain;
      },

      buyBuilding: (id: BuildingId) => {
        const s = get();
        const building = BUILDINGS.find((b) => b.id === id);
        if (!building) return;
        const owned = s.buildings[id] ?? 0;
        const qty =
          s.buyQty === "max" ? maxAffordable(building.baseCost, owned, s.parrots) : s.buyQty;
        if (qty <= 0) return;
        const cost = bulkCost(building.baseCost, owned, qty);
        if (s.parrots < cost) return;
        set({
          parrots: s.parrots - cost,
          buildings: { ...s.buildings, [id]: owned + qty },
        });
      },

      buyUpgrade: (id: string) => {
        const s = get();
        const upgrade = UPGRADES.find((u) => u.id === id);
        if (!upgrade || s.upgrades.includes(id)) return;
        if (!requirementMet(upgrade, s.buildings, s.lifetime, s.clicks)) return;
        if (s.parrots < upgrade.cost) return;
        set({
          parrots: s.parrots - upgrade.cost,
          upgrades: [...s.upgrades, id],
        });
      },

      setBuyQty: (qty: BuyQty) => set({ buyQty: qty }),
      toggleMute: () => set({ muted: !get().muted }),
      dismissAway: () => set({ away: null }),

      grant: (amount: number) => {
        if (!Number.isFinite(amount) || amount <= 0 || amount > 1e30) return;
        const s = get();
        set({
          parrots: s.parrots + amount,
          lifetime: s.lifetime + amount,
          cheatsUsed: s.cheatsUsed + 1,
        });
      },

      setCheatProd: (mult: number) => {
        const s = get();
        if (s.cheatProd === mult) return;
        set({
          cheatProd: mult,
          cheatsUsed: mult === 1 ? s.cheatsUsed : s.cheatsUsed + 1,
        });
      },

      setCheatClick: (mult: number) => {
        const s = get();
        if (s.cheatClick === mult) return;
        set({
          cheatClick: mult,
          cheatsUsed: mult === 1 ? s.cheatsUsed : s.cheatsUsed + 1,
        });
      },

      giftBuildings: (n: number) => {
        if (n <= 0) return;
        const s = get();
        const buildings = { ...s.buildings };
        for (const b of BUILDINGS) buildings[b.id] = (buildings[b.id] ?? 0) + n;
        set({ buildings, cheatsUsed: s.cheatsUsed + 1 });
      },

      giftUpgrades: () => {
        const s = get();
        set({
          upgrades: UPGRADES.map((u) => u.id),
          cheatsUsed: s.cheatsUsed + 1,
        });
      },

      summonGolden: () => {
        const now = Date.now();
        const s = get();
        set({
          golden: { id: now, until: now + GOLDEN_LIFE },
          cheatsUsed: s.cheatsUsed + 1,
        });
      },

      claimGolden: () => {
        const s = get();
        if (!s.golden) return null;
        const now = Date.now();
        const rolled = rollBuff(now);
        let note = rolled.note;
        let parrots = s.parrots;
        let lifetime = s.lifetime;
        let runEarned = s.runEarned;
        let buff: Buff | null = rolled.buff ?? (s.buff && s.buff.until > now ? s.buff : null);
        if (rolled.kind === "windfall") {
          const pile = Math.max(100, clickValue(snap(s)) * 13 + productionPerSec(snap(s)) * 900);
          parrots += pile;
          lifetime += pile;
          runEarned += pile;
          note = `Windfall — ${formatFlock(pile)} parrots hit the perch.`;
          buff = s.buff && s.buff.until > now ? s.buff : null;
        }
        set({
          parrots,
          lifetime,
          runEarned,
          buff,
          golden: null,
          nextGoldenAt: scheduleGolden(now, s.prestige),
          goldenClicks: s.goldenClicks + 1,
        });
        return note;
      },

      reset: () => {
        const s = get();
        set({
          ...beginRun(
            { muted: s.muted, feathers: s.feathers, molts: s.molts, prestige: s.prestige },
            Date.now(),
          ),
          appliedOffline: true,
          away: null,
        });
      },

      buyPrestige: (id: string) => {
        const def = PRESTIGE.find((u) => u.id === id);
        if (!def) return;
        const s = get();
        const level = s.prestige[id] ?? 0;
        if (level >= def.max) return;
        const cost = def.cost(level);
        if (s.feathers < cost) return;
        set({
          feathers: s.feathers - cost,
          prestige: { ...s.prestige, [id]: level + 1 },
        });
      },

      molt: () => {
        const s = get();
        if (!runIsClean(s)) return 0;
        const gain = feathersFromEarned(s.runEarned);
        if (gain < 1) return 0;
        set({
          ...beginRun(
            {
              muted: s.muted,
              feathers: s.feathers + gain,
              molts: s.molts + 1,
              prestige: s.prestige,
            },
            Date.now(),
          ),
          appliedOffline: true,
          away: null,
        });
        return gain;
      },
    }),
    {
      name: SAVE_KEY,
      version: 2,
      skipHydration: true,
      migrate: (persisted, version) => {
        const data = persisted as Data;
        if (version < 2) {
          return {
            ...data,
            feathers: 0,
            molts: 0,
            prestige: emptyPrestige(),
            runEarned: typeof data.lifetime === "number" ? data.lifetime : 0,
          };
        }
        return data;
      },
      partialize: (state) => ({
        parrots: state.parrots,
        lifetime: state.lifetime,
        handmade: state.handmade,
        clicks: state.clicks,
        buildings: state.buildings,
        upgrades: state.upgrades,
        cheatProd: state.cheatProd,
        cheatClick: state.cheatClick,
        buff: state.buff,
        golden: state.golden,
        nextGoldenAt: state.nextGoldenAt,
        lastTick: state.lastTick,
        muted: state.muted,
        buyQty: state.buyQty,
        startedAt: state.startedAt,
        goldenClicks: state.goldenClicks,
        cheatsUsed: state.cheatsUsed,
        runEarned: state.runEarned,
        feathers: state.feathers,
        molts: state.molts,
        prestige: state.prestige,
      }),
    },
  ),
);
