const SUFFIXES = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud"];

export function formatFlock(n: number): string {
  if (!Number.isFinite(n)) return "—";
  const sign = n < 0 ? "−" : "";
  const abs = Math.abs(n);
  if (abs < 1000) {
    if (abs > 0 && abs < 10) {
      const rounded = Math.round(abs * 10) / 10;
      return sign + (Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1));
    }
    return sign + Math.floor(abs).toLocaleString("en-US");
  }
  const tier = Math.min(SUFFIXES.length - 1, Math.floor(Math.log10(abs) / 3));
  const scaled = abs / 10 ** (tier * 3);
  const digits = scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2;
  const text = scaled.toFixed(digits).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1");
  return sign + text + (SUFFIXES[tier] ?? "");
}

export function formatDuration(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  const h = Math.floor(m / 60);
  if (h < 48) return `${h}h ${m % 60}m`;
  const d = Math.floor(h / 24);
  return `${d}d ${h % 24}h`;
}
