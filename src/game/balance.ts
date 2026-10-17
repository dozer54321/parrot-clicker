export const COST_GROWTH = 1.15;

export type BuildingId =
  | "seed"
  | "perch"
  | "aviary"
  | "canopy"
  | "galleon"
  | "glass"
  | "cay"
  | "stars"
  | "migration"
  | "empire";

export type BuildingDef = {
  id: BuildingId;
  name: string;
  flavor: string;
  baseCost: number;
  pps: number;
};

export const BUILDINGS: BuildingDef[] = [
  {
    id: "seed",
    name: "Seed Dish",
    flavor: "A cracked bowl. The first bird never leaves.",
    baseCost: 15,
    pps: 0.1,
  },
  {
    id: "perch",
    name: "Wooden Perch",
    flavor: "One stick, one opinion, billed hourly.",
    baseCost: 100,
    pps: 1,
  },
  {
    id: "aviary",
    name: "Backyard Aviary",
    flavor: "Shade cloth, gossip, and a padlock they ignore.",
    baseCost: 1_100,
    pps: 8,
  },
  {
    id: "canopy",
    name: "Canopy Roost",
    flavor: "The neighborhood trees voted to unionize.",
    baseCost: 12_000,
    pps: 47,
  },
  {
    id: "galleon",
    name: "Pirate Galleon",
    flavor: "Parrots who pay no tax and steal the compass.",
    baseCost: 130_000,
    pps: 260,
  },
  {
    id: "glass",
    name: "Glass Conservatory",
    flavor: "Humidity you can hear. Orchids used as perches.",
    baseCost: 1_400_000,
    pps: 1_400,
  },
  {
    id: "cay",
    name: "Island Cay",
    flavor: "A whole speck of land, leased by the flock.",
    baseCost: 20_000_000,
    pps: 7_800,
  },
  {
    id: "stars",
    name: "Star Perch",
    flavor: "They navigate by crumbs of light.",
    baseCost: 330_000_000,
    pps: 44_000,
  },
  {
    id: "migration",
    name: "Migratory Flock",
    flavor: "Seasons are a suggestion. They invoice anyway.",
    baseCost: 5_100_000_000,
    pps: 260_000,
  },
  {
    id: "empire",
    name: "Parrot Empire",
    flavor: "The crown is a sunflower. The law is loud.",
    baseCost: 75_000_000_000,
    pps: 1_600_000,
  },
];

export type UpgradeEffect =
  | { kind: "click"; mult: number }
  | { kind: "clickPct"; pct: number }
  | { kind: "building"; id: BuildingId; mult: number }
  | { kind: "global"; mult: number };

export type UpgradeDef = {
  id: string;
  name: string;
  blurb: string;
  cost: number;
  effect: UpgradeEffect;
  need?: {
    building?: { id: BuildingId; count: number };
    lifetime?: number;
    clicks?: number;
    totalBuildings?: number;
  };
};

export const UPGRADES: UpgradeDef[] = [
  {
    id: "beak-eager",
    name: "Eager Beak",
    blurb: "Squawks are twice as rude, and twice as profitable.",
    cost: 100,
    effect: { kind: "click", mult: 2 },
    need: { clicks: 25 },
  },
  {
    id: "beak-hook",
    name: "Hooked Beak",
    blurb: "Cracks a seed like it owes rent.",
    cost: 500,
    effect: { kind: "click", mult: 2 },
    need: { clicks: 100 },
  },
  {
    id: "beak-cracker",
    name: "Cracker Beak",
    blurb: "The good crackers. The expensive ones.",
    cost: 10_000,
    effect: { kind: "click", mult: 2 },
    need: { lifetime: 5_000 },
  },
  {
    id: "beak-macaw",
    name: "Macaw Beak",
    blurb: "A beak with a reputation.",
    cost: 100_000,
    effect: { kind: "click", mult: 2 },
    need: { lifetime: 50_000 },
  },
  {
    id: "echo-1",
    name: "Echo Squawk",
    blurb: "Each tap also shakes loose 1% of the flock's output.",
    cost: 50_000,
    effect: { kind: "clickPct", pct: 0.01 },
    need: { totalBuildings: 10 },
  },
  {
    id: "echo-2",
    name: "Chorus Squawk",
    blurb: "Another 4% of output rides along with every tap.",
    cost: 1_000_000,
    effect: { kind: "clickPct", pct: 0.04 },
    need: { totalBuildings: 40 },
  },
  {
    id: "echo-3",
    name: "Thunder Squawk",
    blurb: "10% of the whole flock answers when you tap.",
    cost: 100_000_000,
    effect: { kind: "clickPct", pct: 0.1 },
    need: { totalBuildings: 100 },
  },
  {
    id: "dawn",
    name: "Dawn Chorus",
    blurb: "Everyone talks at once. Output doubles.",
    cost: 250_000,
    effect: { kind: "global", mult: 2 },
    need: { totalBuildings: 25 },
  },
  {
    id: "trades",
    name: "Trade Winds",
    blurb: "Seeds arrive on schedule. Output doubles again.",
    cost: 5_000_000,
    effect: { kind: "global", mult: 2 },
    need: { lifetime: 1_000_000 },
  },
  {
    id: "royal",
    name: "Royal Flock",
    blurb: "A court, a banner, a very loud anthem. Output ×3.",
    cost: 1_000_000_000,
    effect: { kind: "global", mult: 3 },
    need: { lifetime: 1_000_000_000 },
  },
  ...BUILDINGS.map(
    (b): UpgradeDef => ({
      id: `double-${b.id}`,
      name: `${b.name} Union`,
      blurb: `The ${b.name.toLowerCase()} crew clocks twice the parrots.`,
      cost: Math.ceil(b.baseCost * 80),
      effect: { kind: "building", id: b.id, mult: 2 },
      need: { building: { id: b.id, count: 10 } },
    }),
  ),
];

export type FlockSnapshot = {
  buildings: Record<string, number>;
  upgrades: string[];
  cheatProd: number;
  cheatClick: number;
  buff: { prod: number; click: number; until: number } | null;
  prestige: Record<string, number>;
};

export function totalBuildings(buildings: Record<string, number>): number {
  let n = 0;
  for (const b of BUILDINGS) n += buildings[b.id] ?? 0;
  return n;
}

export function unitCost(base: number, owned: number): number {
  return Math.ceil(base * COST_GROWTH ** owned);
}

export function bulkCost(base: number, owned: number, qty: number): number {
  if (qty <= 0) return 0;
  if (qty === 1) return unitCost(base, owned);
  const r = COST_GROWTH;
  const exact = base * r ** owned * ((r ** qty - 1) / (r - 1));
  return Math.ceil(exact);
}

export function maxAffordable(base: number, owned: number, money: number): number {
  if (!(money > 0) || money < unitCost(base, owned)) return 0;
  const r = COST_GROWTH;
  const start = base * r ** owned;
  const raw = Math.log((money * (r - 1)) / start + 1) / Math.log(r);
  let qty = Math.max(0, Math.floor(raw));
  if (qty > 100_000) qty = 100_000;
  while (qty > 0 && bulkCost(base, owned, qty) > money) qty -= 1;
  while (qty < 100_000 && bulkCost(base, owned, qty + 1) <= money) qty += 1;
  return qty;
}

export function upgradeOwned(upgrades: string[], id: string): boolean {
  return upgrades.includes(id);
}

export function requirementMet(
  upgrade: UpgradeDef,
  buildings: Record<string, number>,
  lifetime: number,
  clicks: number,
): boolean {
  const need = upgrade.need;
  if (!need) return true;
  if (need.building && (buildings[need.building.id] ?? 0) < need.building.count) return false;
  if (need.lifetime != null && lifetime < need.lifetime) return false;
  if (need.clicks != null && clicks < need.clicks) return false;
  if (need.totalBuildings != null && totalBuildings(buildings) < need.totalBuildings) return false;
  return true;
}

export function requirementLabel(upgrade: UpgradeDef): string {
  const need = upgrade.need;
  if (!need) return "";
  if (need.building) {
    const b = BUILDINGS.find((x) => x.id === need.building?.id);
    return `Own ${need.building.count} ${b?.name ?? "roosts"}`;
  }
  if (need.clicks != null) return `Squawk ${need.clicks} times`;
  if (need.totalBuildings != null) return `Own ${need.totalBuildings} roosts`;
  if (need.lifetime != null) return `Gather ${need.lifetime.toLocaleString("en-US")} lifetime parrots`;
  return "";
}

function buildingSpecificMult(id: string, upgrades: string[]): number {
  let m = 1;
  for (const u of UPGRADES) {
    if (u.effect.kind === "building" && u.effect.id === id && upgrades.includes(u.id)) {
      m *= u.effect.mult;
    }
  }
  return m;
}

function globalMult(upgrades: string[]): number {
  let m = 1;
  for (const u of UPGRADES) {
    if (u.effect.kind === "global" && upgrades.includes(u.id)) m *= u.effect.mult;
  }
  return m;
}

export function clickMult(upgrades: string[]): number {
  let m = 1;
  for (const u of UPGRADES) {
    if (u.effect.kind === "click" && upgrades.includes(u.id)) m *= u.effect.mult;
  }
  return m;
}

export function clickPct(upgrades: string[]): number {
  let p = 0;
  for (const u of UPGRADES) {
    if (u.effect.kind === "clickPct" && upgrades.includes(u.id)) p += u.effect.pct;
  }
  return p;
}

/** Parrots per second from roosts, cheats, and an optional live buff. */
export function productionPerSec(snap: FlockSnapshot, now = Date.now()): number {
  let sum = 0;
  for (const b of BUILDINGS) {
    const owned = snap.buildings[b.id] ?? 0;
    sum += owned * b.pps * buildingSpecificMult(b.id, snap.upgrades);
  }
  sum *= globalMult(snap.upgrades);
  sum *= prestigeProdMult(snap.prestige);
  sum *= snap.cheatProd > 0 ? snap.cheatProd : 1;
  const buff = snap.buff;
  if (buff && buff.until > now) sum *= buff.prod;
  return sum;
}

export function buildingShare(id: BuildingId, snap: FlockSnapshot, now = Date.now()): number {
  const b = BUILDINGS.find((x) => x.id === id);
  if (!b) return 0;
  const owned = snap.buildings[id] ?? 0;
  let each = b.pps * buildingSpecificMult(id, snap.upgrades) * globalMult(snap.upgrades);
  each *= prestigeProdMult(snap.prestige);
  each *= snap.cheatProd > 0 ? snap.cheatProd : 1;
  const buff = snap.buff;
  if (buff && buff.until > now) each *= buff.prod;
  return owned * each;
}

export function clickValue(snap: FlockSnapshot, now = Date.now()): number {
  const buff = snap.buff && snap.buff.until > now ? snap.buff : null;
  const pps = productionPerSec({ ...snap, buff: null }, now);
  let value = 1 + prestigeClickFlat(snap.prestige);
  value *= clickMult(snap.upgrades);
  value += pps * (clickPct(snap.upgrades) + prestigeClickPct(snap.prestige));
  value *= snap.cheatClick > 0 ? snap.cheatClick : 1;
  if (buff) value *= buff.click;
  return value;
}

export const NEWS = [
  "A macaw just unionized the seed dish.",
  "Local perch rated ‘structurally sincere’ by a skeptical conure.",
  "Pirates report their compass now only points at snacks.",
  "Conservatory orchids file a noise complaint. It is denied.",
  "Astronomers confirm the new constellation is shaped like a cracker.",
  "Trade winds running on time. The flock takes the credit.",
  "Someone taught a parrot the word ‘dividend’.",
  "Island cay available for lease. Tenants included.",
  "Dawn chorus voted loudest hour of the day, again.",
  "A golden parrot was seen. Witnesses became unreliable immediately.",
  "Empire tailors overwhelmed by orders for tiny capes.",
  "Backyard aviary gossip remains the region’s best newspaper.",
  "A clean molt leaves feathers. An opened drawer leaves none.",
];

/** First feather at 1 million parrots gathered this run, then the cube root. */
export const PRESTIGE_SCALE = 1_000_000;

export type PrestigeDef = {
  id: string;
  name: string;
  blurb: string;
  max: number;
  /** Feathers to buy the next rank. `level` is how many ranks are already owned. */
  cost: (level: number) => number;
};

export const PRESTIGE: PrestigeDef[] = [
  {
    id: "memory",
    name: "Flock Memory",
    blurb: "Every roost makes 15% more parrots per rank, this run and the next.",
    max: 20,
    cost: (level) => level + 1,
  },
  {
    id: "beak",
    name: "Remembered Beak",
    blurb: "Taps start one parrot stronger per rank. Tricks multiply that.",
    max: 25,
    cost: (level) => 1 + Math.floor(level / 2),
  },
  {
    id: "echo",
    name: "Old Chorus",
    blurb: "Each tap also pulls 1% of roost output per rank.",
    max: 10,
    cost: (level) => 2 + level,
  },
  {
    id: "seeds",
    name: "Seed Memory",
    blurb: "The next molt begins with one more seed dish. Not this flock.",
    max: 15,
    cost: (level) => 2 + level,
  },
  {
    id: "egg",
    name: "Nest Egg",
    blurb: "The next molt starts with a pile already in the bank. Not this flock.",
    max: 10,
    cost: (level) => 1 + level,
  },
  {
    id: "eye",
    name: "Keen Eye",
    blurb: "Golden parrots visit 8% sooner per rank, down to half the wait.",
    max: 6,
    cost: (level) => 3 + level,
  },
];

export function feathersFromEarned(earned: number): number {
  if (!(earned >= PRESTIGE_SCALE)) return 0;
  return Math.floor(Math.cbrt(earned / PRESTIGE_SCALE));
}

export function nextFeatherAt(earned: number): number {
  const next = feathersFromEarned(earned) + 1;
  return Math.ceil(next ** 3 * PRESTIGE_SCALE);
}

export function prestigeLevel(levels: Record<string, number> | undefined, id: string): number {
  return levels?.[id] ?? 0;
}

export function prestigeProdMult(levels: Record<string, number> | undefined): number {
  return 1 + 0.15 * prestigeLevel(levels, "memory");
}

export function prestigeClickFlat(levels: Record<string, number> | undefined): number {
  return prestigeLevel(levels, "beak");
}

export function prestigeClickPct(levels: Record<string, number> | undefined): number {
  return 0.01 * prestigeLevel(levels, "echo");
}

export function goldenDelayScale(levels: Record<string, number> | undefined): number {
  return Math.max(0.5, 1 - 0.08 * prestigeLevel(levels, "eye"));
}

export function nestEgg(level: number): number {
  if (level <= 0) return 0;
  return Math.floor(100 * 4 ** (level - 1));
}

export function starterSeeds(level: number): number {
  return Math.max(0, level);
}
