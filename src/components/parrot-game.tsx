import {
  Bird,
  Crown,
  Fence,
  Flower2,
  House,
  RotateCcw,
  ScrollText,
  Ship,
  Sparkles,
  Telescope,
  TreePalm,
  Trees,
  Volume2,
  VolumeX,
  Wheat,
  type LucideIcon,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  BUILDINGS,
  NEWS,
  UPGRADES,
  type BuildingId,
  buildingShare,
  bulkCost,
  clickValue,
  productionPerSec,
  requirementMet,
  totalBuildings,
  unitCost,
} from "@/game/balance";
import { chirp, gleam } from "@/game/audio";
import { formatDuration, formatFlock } from "@/game/format";
import { quoteFor, useGame, type BuyQty } from "@/game/store";

const ICONS: Record<BuildingId, LucideIcon> = {
  seed: Wheat,
  perch: Fence,
  aviary: House,
  canopy: Trees,
  galleon: Ship,
  glass: Flower2,
  cay: TreePalm,
  stars: Telescope,
  migration: Bird,
  empire: Crown,
};

const QTYS: { id: BuyQty; label: string }[] = [
  { id: 1, label: "1" },
  { id: 10, label: "10" },
  { id: 100, label: "100" },
  { id: "max", label: "Max" },
];

const CHEAT_STEPS = [1, 10, 100, 1000];
const GRANTS = [1_000, 1_000_000, 1_000_000_000, 1_000_000_000_000];

type Floater = { id: number; x: number; y: number; text: string };
type Feather = { id: number; x: number; y: number; dx: number; rot: number; tint: string };

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function ParrotGame() {
  const game = useGame();
  const stageRef = useRef<HTMLDivElement>(null);
  const birdRef = useRef<HTMLButtonElement>(null);
  const [floaters, setFloaters] = useState<Floater[]>([]);
  const [feathers, setFeathers] = useState<Feather[]>([]);
  const [tab, setTab] = useState<"roosts" | "tricks" | "ledger" | "cheats">("roosts");
  const [toast, setToast] = useState<string | null>(null);
  const [newsIdx, setNewsIdx] = useState(0);
  const [grantText, setGrantText] = useState("1000000");
  const [confirmReset, setConfirmReset] = useState(false);
  const idRef = useRef(1);

  useEffect(() => {
    let raf = 0;
    let stopped = false;
    const loop = () => {
      if (stopped) return;
      useGame.getState().tick(Date.now());
      raf = requestAnimationFrame(loop);
    };
    const start = () => {
      if (stopped) return;
      useGame.getState().applyOffline();
      raf = requestAnimationFrame(loop);
    };
    const unsub = useGame.persist.onFinishHydration(start);
    void useGame.persist.rehydrate();
    return () => {
      stopped = true;
      cancelAnimationFrame(raf);
      unsub();
    };
  }, []);

  useEffect(() => {
    const id = window.setInterval(() => {
      setNewsIdx((n) => (n + 1) % NEWS.length);
    }, 9000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (!toast) return;
    const id = window.setTimeout(() => setToast(null), 4200);
    return () => window.clearTimeout(id);
  }, [toast]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.repeat) return;
      if (event.key !== "`" && event.key !== "~") return;
      const tag = (event.target as HTMLElement | null)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      setTab("cheats");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const now = Date.now();
  const snap = {
    buildings: game.buildings,
    upgrades: game.upgrades,
    cheatProd: game.cheatProd,
    cheatClick: game.cheatClick,
    buff: game.buff,
  };
  const pps = productionPerSec(snap, now);
  const perTap = clickValue(snap, now);
  const buffLeft = game.buff && game.buff.until > now ? (game.buff.until - now) / 1000 : 0;

  const goldenSpot = useMemo(() => {
    if (!game.golden) return null;
    const rng = mulberry32(game.golden.id);
    return { top: 8 + rng() * 58, left: 6 + rng() * 68 };
  }, [game.golden]);

  function burst(clientX: number, clientY: number, text: string) {
    const stage = stageRef.current;
    if (!stage) return;
    const rect = stage.getBoundingClientRect();
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    const fid = idRef.current++;
    setFloaters((list) => [...list.slice(-14), { id: fid, x, y, text }]);
    const tint = ["bg-scarlet", "bg-sun", "bg-teal", "bg-leaf"][fid % 4] ?? "bg-scarlet";
    const bits: Feather[] = Array.from({ length: 6 }, (_, i) => ({
      id: idRef.current++,
      x,
      y,
      dx: (Math.random() - 0.5) * 90,
      rot: (Math.random() - 0.5) * 80,
      tint: i % 2 === 0 ? tint : "bg-sun",
    }));
    setFeathers((list) => [...list.slice(-24), ...bits]);
    window.setTimeout(() => {
      setFloaters((list) => list.filter((f) => f.id !== fid));
      const ids = new Set(bits.map((b) => b.id));
      setFeathers((list) => list.filter((f) => !ids.has(f.id)));
    }, 700);
  }

  function onSquawk(event: React.MouseEvent<HTMLButtonElement>) {
    const gain = game.squawk();
    chirp(useGame.getState().muted);
    const bird = birdRef.current;
    if (bird) {
      bird.classList.remove("parrot-boop");
      void bird.offsetWidth;
      bird.classList.add("parrot-boop");
    }
    burst(event.clientX, event.clientY, `+${formatFlock(gain)}`);
  }

  function onGolden(event: React.MouseEvent<HTMLButtonElement>) {
    event.stopPropagation();
    const note = game.claimGolden();
    gleam(useGame.getState().muted);
    if (note) setToast(note);
    burst(event.clientX, event.clientY, "!");
  }

  const next = useMemo(() => {
    let best: { name: string; need: number } | null = null;
    for (const b of BUILDINGS) {
      const cost = unitCost(b.baseCost, game.buildings[b.id] ?? 0);
      if (game.parrots >= cost) continue;
      const need = cost - game.parrots;
      if (!best || need < best.need) best = { name: b.name, need };
    }
    return best;
  }, [game.buildings, game.parrots]);

  const tricks = UPGRADES.filter(
    (u) => !game.upgrades.includes(u.id) && requirementMet(u, game.buildings, game.lifetime, game.clicks),
  );
  const knownTricks = UPGRADES.filter((u) => game.upgrades.includes(u.id));

  return (
    <div className="mx-auto flex min-h-dvh w-full max-w-6xl flex-col px-4 pb-10 sm:px-6">
      <header className="sticky top-0 z-30 -mx-4 flex items-center justify-between gap-3 border-b border-line bg-paper/95 px-4 py-3 backdrop-blur-sm sm:-mx-6 sm:px-6">
        <div className="min-w-0">
          <p className="font-display text-xl leading-none font-semibold tracking-tight text-ink sm:text-2xl">
            Parrot Clicker
          </p>
          <p className="mt-1 truncate text-xs text-muted">A flock that pays rent in seeds</p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            onClick={() => game.toggleMute()}
            className="inline-flex size-11 items-center justify-center rounded-full border border-line bg-paper-deep text-ink"
            aria-label={game.muted ? "Unmute chirps" : "Mute chirps"}
          >
            {game.muted ? <VolumeX className="size-5" /> : <Volume2 className="size-5" />}
          </button>
          <button
            type="button"
            onClick={() => setTab("cheats")}
            className="inline-flex h-11 items-center gap-2 rounded-full bg-ink px-4 text-sm font-semibold text-paper"
          >
            <ScrollText className="size-4" />
            Cheats
          </button>
        </div>
      </header>

      {game.away && game.away.amount > 1 ? (
        <div className="mt-4 flex items-start justify-between gap-3 rounded-2xl border border-line bg-paper-deep px-4 py-3">
          <p className="text-sm text-ink-soft">
            While you were away ({formatDuration(game.away.seconds)}) the flock gathered{" "}
            <span className="font-semibold text-ink">{formatFlock(game.away.amount)}</span> parrots.
          </p>
          <button
            type="button"
            onClick={() => game.dismissAway()}
            className="shrink-0 text-sm font-semibold text-leaf"
          >
            Dismiss
          </button>
        </div>
      ) : null}

      {toast ? (
        <p className="mt-4 rounded-2xl border border-sun/50 bg-sun/15 px-4 py-3 text-sm font-semibold text-ink">
          {toast}
        </p>
      ) : null}

      <div className="mt-4 grid flex-1 gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(22rem,28rem)] lg:items-start">
        <section className="relative overflow-hidden rounded-3xl border border-line bg-paper-deep/70 px-4 py-6 sm:px-8">
          <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_18%,rgba(224,161,26,0.16),transparent_42%)]" />
          <div ref={stageRef} className="relative mx-auto flex max-w-md flex-col items-center text-center">
            <p className="font-display text-5xl leading-none font-semibold tracking-tight text-ink tabular-nums sm:text-6xl">
              {formatFlock(game.parrots)}
            </p>
            <p className="mt-2 text-sm font-semibold tracking-wide text-muted uppercase">parrots</p>
            <p className="mt-3 text-base font-semibold text-leaf tabular-nums">
              {formatFlock(pps)} per second
            </p>
            <p className="mt-1 text-sm text-ink-soft tabular-nums">{formatFlock(perTap)} per squawk</p>
            {buffLeft > 0 && game.buff ? (
              <p className="mt-3 rounded-full bg-scarlet px-3 py-1 text-xs font-semibold text-paper">
                {game.buff.label} · {Math.ceil(buffLeft)}s
              </p>
            ) : null}
            {next ? (
              <p className="mt-2 text-xs text-muted">
                {formatFlock(next.need)} to the next {next.name}
              </p>
            ) : (
              <p className="mt-2 text-xs text-muted">Every roost on the board is within reach.</p>
            )}

            <button
              ref={birdRef}
              type="button"
              onClick={onSquawk}
              className="relative mt-4 size-64 rounded-full border border-line bg-paper shadow-md transition-transform active:translate-y-0.5 sm:size-72"
              aria-label="Tap the macaw"
            >
              <img
                src="/game/macaw.jpg"
                alt="Scarlet macaw ready to be tapped"
                width={768}
                height={768}
                className="size-full rounded-full object-cover"
                draggable={false}
              />
            </button>

            {game.golden && goldenSpot ? (
              <button
                type="button"
                onClick={onGolden}
                className="golden-bob absolute z-10 size-16 rounded-full border border-sun bg-paper shadow-md sm:size-20"
                style={{ top: `${goldenSpot.top}%`, left: `${goldenSpot.left}%` }}
                aria-label="Catch the golden parrot"
              >
                <img
                  src="/game/golden-macaw.jpg"
                  alt=""
                  width={256}
                  height={256}
                  className="size-full rounded-full object-cover"
                  draggable={false}
                />
              </button>
            ) : null}

            {floaters.map((f) => (
              <span
                key={f.id}
                className="floater pointer-events-none absolute z-20 text-lg font-semibold text-scarlet"
                style={{ left: f.x, top: f.y }}
              >
                {f.text}
              </span>
            ))}
            {feathers.map((f) => (
              <span
                key={f.id}
                className={`feather pointer-events-none absolute z-10 size-2 rounded-sm ${f.tint}`}
                style={{
                  left: f.x,
                  top: f.y,
                  ["--dx" as string]: `${f.dx}px`,
                  ["--rot" as string]: `${f.rot}deg`,
                }}
              />
            ))}

            <p className="mt-6 min-h-10 max-w-sm text-sm text-ink-soft">{NEWS[newsIdx]}</p>
          </div>
        </section>

        <aside className="rounded-3xl border border-line bg-paper">
          <div className="flex gap-1 border-b border-line p-2" role="tablist" aria-label="Flock desk">
            {(
              [
                ["roosts", "Roosts"],
                ["tricks", "Tricks"],
                ["ledger", "Ledger"],
                ["cheats", "Cheats"],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                type="button"
                role="tab"
                aria-selected={tab === id}
                onClick={() => setTab(id)}
                className={
                  "h-11 flex-1 rounded-full text-sm font-semibold " +
                  (tab === id ? "bg-ink text-paper" : "text-ink-soft")
                }
              >
                {label}
              </button>
            ))}
          </div>

          <div className="p-3 sm:p-4">
            {tab === "roosts" ? (
              <div>
                <div className="mb-3 flex gap-1 rounded-full bg-paper-deep p-1">
                  {QTYS.map((q) => (
                    <button
                      key={String(q.id)}
                      type="button"
                      onClick={() => game.setBuyQty(q.id)}
                      className={
                        "h-10 flex-1 rounded-full text-sm font-semibold " +
                        (game.buyQty === q.id ? "bg-paper text-ink shadow-sm" : "text-ink-soft")
                      }
                    >
                      {q.label}
                    </button>
                  ))}
                </div>
                <ul className="flex flex-col gap-2">
                  {BUILDINGS.map((b) => {
                    const owned = game.buildings[b.id] ?? 0;
                    const quote = quoteFor(game, b.id);
                    const showQty = quote.qty > 0 ? quote.qty : game.buyQty === "max" ? 1 : game.buyQty;
                    const showCost =
                      quote.qty > 0 ? quote.cost : bulkCost(b.baseCost, owned, showQty || 1);
                    const affordable = quote.qty > 0 && game.parrots >= quote.cost;
                    const Icon = ICONS[b.id];
                    const share = buildingShare(b.id, snap, now);
                    return (
                      <li key={b.id}>
                        <button
                          type="button"
                          disabled={!affordable}
                          onClick={() => game.buyBuilding(b.id)}
                          className={
                            "flex w-full items-center gap-3 rounded-2xl border px-3 py-3 text-left " +
                            (affordable
                              ? "border-leaf/40 bg-leaf/10"
                              : "border-line bg-paper-deep/50 opacity-80")
                          }
                        >
                          <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-xl bg-paper text-leaf">
                            <Icon className="size-5" />
                          </span>
                          <span className="min-w-0 flex-1">
                            <span className="flex items-baseline justify-between gap-2">
                              <span className="font-semibold text-ink">{b.name}</span>
                              <span className="shrink-0 text-sm font-semibold text-sun tabular-nums">
                                {formatFlock(showCost)}
                              </span>
                            </span>
                            <span className="mt-0.5 block text-xs text-ink-soft">
                              {owned.toLocaleString("en-US")} owned
                              {showQty > 1 ? ` · buy ${showQty.toLocaleString("en-US")}` : ""} ·{" "}
                              {formatFlock(share)} /s
                            </span>
                            <span className="mt-0.5 block text-xs text-muted">{b.flavor}</span>
                          </span>
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </div>
            ) : null}

            {tab === "tricks" ? (
              <div className="flex flex-col gap-2">
                {tricks.length === 0 ? (
                  <p className="rounded-2xl bg-paper-deep px-4 py-6 text-sm text-ink-soft">
                    Keep squawking. Tricks show up once the flock is big enough to learn them.
                    {knownTricks.length > 0
                      ? ` ${knownTricks.length} already learned.`
                      : ""}
                  </p>
                ) : (
                  tricks.map((u) => {
                    const affordable = game.parrots >= u.cost;
                    return (
                      <button
                        key={u.id}
                        type="button"
                        disabled={!affordable}
                        onClick={() => game.buyUpgrade(u.id)}
                        className={
                          "rounded-2xl border px-4 py-3 text-left " +
                          (affordable ? "border-sun/50 bg-sun/15" : "border-line bg-paper-deep/60")
                        }
                      >
                        <span className="flex items-baseline justify-between gap-3">
                          <span className="font-semibold text-ink">{u.name}</span>
                          <span className="text-sm font-semibold text-sun tabular-nums">
                            {formatFlock(u.cost)}
                          </span>
                        </span>
                        <span className="mt-1 block text-sm text-ink-soft">{u.blurb}</span>
                      </button>
                    );
                  })
                )}
                {knownTricks.length > 0 ? (
                  <p className="px-1 pt-2 text-xs text-muted">
                    Learned: {knownTricks.map((u) => u.name).join(", ")}
                  </p>
                ) : null}
              </div>
            ) : null}

            {tab === "ledger" ? (
              <dl className="grid grid-cols-2 gap-2">
                <Stat label="In the bank" value={formatFlock(game.parrots)} />
                <Stat label="Per second" value={formatFlock(pps)} />
                <Stat label="Lifetime" value={formatFlock(game.lifetime)} />
                <Stat label="By hand" value={formatFlock(game.handmade)} />
                <Stat label="Squawks" value={game.clicks.toLocaleString("en-US")} />
                <Stat label="Roosts" value={totalBuildings(game.buildings).toLocaleString("en-US")} />
                <Stat label="Golden caught" value={String(game.goldenClicks)} />
                <Stat label="Contraband uses" value={String(game.cheatsUsed)} />
                <div className="col-span-2 rounded-2xl bg-paper-deep px-4 py-3">
                  <dt className="text-xs tracking-wide text-muted uppercase">Marks</dt>
                  <dd className="mt-1 text-sm text-ink-soft">
                    {[
                      game.clicks > 0 ? "First squawk" : null,
                      totalBuildings(game.buildings) > 0 ? "Opened a roost" : null,
                      game.lifetime >= 1_000_000 ? "Million-parrot flock" : null,
                      game.goldenClicks > 0 ? "Caught gold" : null,
                      game.cheatsUsed > 0 ? "Opened the drawer" : null,
                    ]
                      .filter(Boolean)
                      .join(" · ") || "Nothing inked yet. Tap the macaw."}
                  </dd>
                </div>
              </dl>
            ) : null}

            {tab === "cheats" ? (
              <div className="flex flex-col gap-4">
                <div>
                  <h2 className="font-display text-lg font-semibold text-ink">Contraband drawer</h2>
                  <p className="mt-1 text-sm text-ink-soft">
                    These change the flock for real. Grants count toward lifetime, so tricks can unlock.
                    Press ` to open this drawer.
                  </p>
                </div>

                <fieldset>
                  <legend className="text-xs font-semibold tracking-wide text-muted uppercase">
                    Roost speed
                  </legend>
                  <div className="mt-2 flex gap-1">
                    {CHEAT_STEPS.map((n) => (
                      <button
                        key={n}
                        type="button"
                        onClick={() => game.setCheatProd(n)}
                        className={
                          "h-11 flex-1 rounded-full text-sm font-semibold " +
                          (game.cheatProd === n ? "bg-scarlet text-paper" : "bg-paper-deep text-ink")
                        }
                      >
                        ×{n}
                      </button>
                    ))}
                  </div>
                </fieldset>

                <fieldset>
                  <legend className="text-xs font-semibold tracking-wide text-muted uppercase">
                    Beak power
                  </legend>
                  <div className="mt-2 flex gap-1">
                    {CHEAT_STEPS.map((n) => (
                      <button
                        key={n}
                        type="button"
                        onClick={() => game.setCheatClick(n)}
                        className={
                          "h-11 flex-1 rounded-full text-sm font-semibold " +
                          (game.cheatClick === n ? "bg-sun text-ink" : "bg-paper-deep text-ink")
                        }
                      >
                        ×{n}
                      </button>
                    ))}
                  </div>
                </fieldset>

                <div>
                  <p className="text-xs font-semibold tracking-wide text-muted uppercase">Pour parrots</p>
                  <div className="mt-2 grid grid-cols-2 gap-2">
                    {GRANTS.map((n) => (
                      <button
                        key={n}
                        type="button"
                        onClick={() => {
                          game.grant(n);
                          setToast(`Poured ${formatFlock(n)} parrots into the bank.`);
                        }}
                        className="h-11 rounded-full bg-paper-deep text-sm font-semibold text-ink"
                      >
                        +{formatFlock(n)}
                      </button>
                    ))}
                  </div>
                  <form
                    className="mt-2 flex gap-2"
                    onSubmit={(event) => {
                      event.preventDefault();
                      const amount = Number(grantText.replace(/,/g, ""));
                      if (!Number.isFinite(amount) || amount <= 0) {
                        setToast("That isn’t a pile of parrots.");
                        return;
                      }
                      game.grant(amount);
                      setToast(`Poured ${formatFlock(amount)} parrots into the bank.`);
                    }}
                  >
                    <input
                      value={grantText}
                      onChange={(event) => setGrantText(event.target.value)}
                      inputMode="decimal"
                      aria-label="Custom parrot amount"
                      className="h-11 min-w-0 flex-1 rounded-full border border-line bg-paper px-4 text-sm text-ink"
                    />
                    <button
                      type="submit"
                      className="h-11 rounded-full bg-ink px-4 text-sm font-semibold text-paper"
                    >
                      Pour
                    </button>
                  </form>
                </div>

                <div className="grid grid-cols-1 gap-2">
                  <button
                    type="button"
                    onClick={() => {
                      game.giftBuildings(1);
                      setToast("Every roost gained one more bird.");
                    }}
                    className="h-11 rounded-full bg-leaf px-4 text-sm font-semibold text-paper"
                  >
                    +1 of every roost
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      game.giftBuildings(10);
                      setToast("Ten birds moved into every roost.");
                    }}
                    className="h-11 rounded-full bg-leaf px-4 text-sm font-semibold text-paper"
                  >
                    +10 of every roost
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      game.giftUpgrades();
                      setToast("Every trick is learned. No tuition.");
                    }}
                    className="inline-flex h-11 items-center justify-center gap-2 rounded-full bg-teal px-4 text-sm font-semibold text-paper"
                  >
                    <Sparkles className="size-4" />
                    Teach every trick
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      game.summonGolden();
                      setToast("A golden parrot just cut across the perch.");
                    }}
                    className="h-11 rounded-full bg-sun px-4 text-sm font-semibold text-ink"
                  >
                    Summon a golden parrot
                  </button>
                </div>

                <div className="border-t border-line pt-3">
                  {confirmReset ? (
                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={() => {
                          game.reset();
                          setConfirmReset(false);
                          setToast("The flock molted. The perch is empty.");
                        }}
                        className="inline-flex h-11 flex-1 items-center justify-center gap-2 rounded-full bg-scarlet text-sm font-semibold text-paper"
                      >
                        <RotateCcw className="size-4" />
                        Really molt
                      </button>
                      <button
                        type="button"
                        onClick={() => setConfirmReset(false)}
                        className="h-11 flex-1 rounded-full border border-line text-sm font-semibold text-ink"
                      >
                        Keep them
                      </button>
                    </div>
                  ) : (
                    <button
                      type="button"
                      onClick={() => setConfirmReset(true)}
                      className="h-11 w-full rounded-full border border-scarlet/40 text-sm font-semibold text-scarlet"
                    >
                      Molt the flock (wipe save)
                    </button>
                  )}
                  <p className="mt-2 text-xs text-muted">
                    Saved in this browser. Molting does not touch anyone else’s flock.
                  </p>
                </div>
              </div>
            ) : null}
          </div>
        </aside>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-paper-deep px-4 py-3">
      <dt className="text-xs tracking-wide text-muted uppercase">{label}</dt>
      <dd className="mt-1 font-display text-xl font-semibold text-ink tabular-nums">{value}</dd>
    </div>
  );
}
