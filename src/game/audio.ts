let ctx: AudioContext | null = null;

function context(): AudioContext | null {
  const AC =
    window.AudioContext ||
    (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!AC) return null;
  if (!ctx) ctx = new AC();
  if (ctx.state === "suspended") void ctx.resume();
  return ctx;
}

function tone(from: number, to: number, dur: number, gainPeak: number) {
  const audio = context();
  if (!audio) return;
  const t = audio.currentTime;
  const osc = audio.createOscillator();
  const gain = audio.createGain();
  osc.type = "triangle";
  osc.frequency.setValueAtTime(from, t);
  osc.frequency.exponentialRampToValueAtTime(Math.max(40, to), t + dur * 0.7);
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(gainPeak, t + 0.02);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  osc.connect(gain);
  gain.connect(audio.destination);
  osc.start(t);
  osc.stop(t + dur + 0.02);
}

export function chirp(muted: boolean) {
  if (muted) return;
  tone(480 + Math.random() * 140, 860 + Math.random() * 180, 0.14, 0.06);
}

export function gleam(muted: boolean) {
  if (muted) return;
  tone(660, 1320, 0.22, 0.07);
}
