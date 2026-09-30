let ctx: AudioContext | null = null;
let noiseBuf: AudioBuffer | null = null;

function context(): AudioContext | null {
  const AC =
    window.AudioContext ||
    (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!AC) return null;
  if (!ctx) ctx = new AC();
  if (ctx.state === "suspended") void ctx.resume();
  return ctx;
}

/** Brown noise — the rasp in a beak, not a whistle. */
function noise(audio: AudioContext): AudioBuffer {
  if (noiseBuf && noiseBuf.sampleRate === audio.sampleRate) return noiseBuf;
  const len = audio.sampleRate;
  const buf = audio.createBuffer(1, len, audio.sampleRate);
  const data = buf.getChannelData(0);
  let brown = 0;
  for (let i = 0; i < len; i++) {
    const white = Math.random() * 2 - 1;
    brown = brown * 0.97 + white * 0.03;
    data[i] = brown * 6;
  }
  noiseBuf = buf;
  return buf;
}

type Call = "bark" | "cry";

/**
 * Bark = a short SQUAWK. Cry = a long open-throated macaw scream.
 * `dest` is the dry output; the golden call sends that into a canopy echo.
 */
function voice(
  audio: AudioContext,
  t: number,
  pitch: number,
  dur: number,
  peak: number,
  bright: number,
  call: Call,
  dest: AudioNode,
) {
  const osc = audio.createOscillator();
  const over = audio.createOscillator();
  osc.type = "sawtooth";
  over.type = "square";

  const rise = call === "cry" ? Math.min(0.32, dur * 0.2) : 0.035;
  const hold = call === "cry" ? Math.max(rise + 0.08, dur * 0.48) : 0.11;

  if (call === "bark") {
    osc.frequency.setValueAtTime(pitch * 0.8, t);
    osc.frequency.exponentialRampToValueAtTime(pitch * 1.65, t + rise);
    osc.frequency.setValueAtTime(pitch * 0.95, t + 0.07);
    osc.frequency.exponentialRampToValueAtTime(pitch * 1.4, t + hold);
    osc.frequency.exponentialRampToValueAtTime(Math.max(80, pitch * 0.7), t + dur);
    over.frequency.setValueAtTime(pitch * 1.5, t);
    over.frequency.exponentialRampToValueAtTime(pitch * 2.8, t + 0.04);
    over.frequency.exponentialRampToValueAtTime(Math.max(90, pitch * 1.2), t + dur);
  } else {
    osc.frequency.setValueAtTime(Math.max(70, pitch * 0.62), t);
    osc.frequency.exponentialRampToValueAtTime(pitch * 1.28, t + rise);
    osc.frequency.exponentialRampToValueAtTime(pitch * 1.08, t + hold);
    osc.frequency.exponentialRampToValueAtTime(Math.max(60, pitch * 0.48), t + dur);
    over.frequency.setValueAtTime(pitch * 1.1, t);
    over.frequency.exponentialRampToValueAtTime(pitch * 2.15, t + rise);
    over.frequency.exponentialRampToValueAtTime(Math.max(80, pitch * 0.9), t + dur);
  }

  const warble = audio.createOscillator();
  const warbleAmt = audio.createGain();
  warble.frequency.value = call === "cry" ? 4.6 + bright * 0.25 : 16 + bright * 2;
  warbleAmt.gain.value = pitch * (call === "cry" ? 0.028 : 0.045);
  warble.connect(warbleAmt);
  warbleAmt.connect(osc.frequency);

  const formant = audio.createBiquadFilter();
  formant.type = "bandpass";
  formant.Q.value = call === "cry" ? 4.2 : 7;
  formant.frequency.setValueAtTime(call === "cry" ? 560 : 780, t);
  formant.frequency.exponentialRampToValueAtTime((call === "cry" ? 1180 : 1500) + bright * 140, t + rise);
  formant.frequency.exponentialRampToValueAtTime(call === "cry" ? 740 : 980, t + dur);

  const nasal = audio.createBiquadFilter();
  nasal.type = "peaking";
  nasal.frequency.value = (call === "cry" ? 1900 : 2300) + bright * 180;
  nasal.Q.value = call === "cry" ? 2.4 : 3.5;
  nasal.gain.value = call === "cry" ? 6 : 9;

  const grit = audio.createBufferSource();
  grit.buffer = noise(audio);
  grit.loop = true;
  const rasp = audio.createBiquadFilter();
  rasp.type = "bandpass";
  rasp.Q.value = call === "cry" ? 1.4 : 2.4;
  rasp.frequency.setValueAtTime(call === "cry" ? 1400 : 2200, t);
  rasp.frequency.exponentialRampToValueAtTime((call === "cry" ? 2100 : 3200) + bright * 120, t + rise);
  rasp.frequency.exponentialRampToValueAtTime(call === "cry" ? 900 : 1400, t + dur);
  const gritGain = audio.createGain();
  if (call === "bark") {
    gritGain.gain.setValueAtTime(0.85, t);
    gritGain.gain.exponentialRampToValueAtTime(0.28, t + 0.05);
    gritGain.gain.exponentialRampToValueAtTime(0.1, t + dur);
  } else {
    gritGain.gain.setValueAtTime(0.16, t);
    gritGain.gain.exponentialRampToValueAtTime(0.1, t + rise);
    gritGain.gain.exponentialRampToValueAtTime(0.035, t + dur);
  }

  const body = audio.createGain();
  body.gain.value = call === "cry" ? 0.7 : 0.55;
  const harm = audio.createGain();
  harm.gain.value = call === "cry" ? 0.1 : 0.16;

  const vca = audio.createGain();
  vca.gain.setValueAtTime(0.0001, t);
  if (call === "bark") {
    vca.gain.exponentialRampToValueAtTime(peak, t + 0.01);
    vca.gain.exponentialRampToValueAtTime(peak * 0.32, t + 0.05);
    vca.gain.exponentialRampToValueAtTime(peak * 0.92, t + 0.09);
    vca.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  } else {
    vca.gain.exponentialRampToValueAtTime(peak, t + Math.min(0.12, rise));
    vca.gain.setValueAtTime(peak * 0.82, t + hold);
    vca.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  }

  const hip = audio.createBiquadFilter();
  hip.type = "highpass";
  hip.frequency.value = call === "cry" ? 160 : 320;

  osc.connect(body);
  over.connect(harm);
  body.connect(formant);
  harm.connect(formant);
  formant.connect(nasal);
  nasal.connect(vca);
  grit.connect(rasp);
  rasp.connect(gritGain);
  gritGain.connect(vca);
  vca.connect(hip);
  hip.connect(dest);

  const end = t + dur + 0.04;
  osc.start(t);
  over.start(t);
  warble.start(t);
  grit.start(t);
  osc.stop(end);
  over.stop(end);
  warble.stop(end);
  grit.stop(end);
}

/** Two far reflections, darker each time — a call leaving the canopy. */
function canopy(audio: AudioContext, source: AudioNode) {
  const taps = [
    { time: 0.21, gain: 0.38, cut: 1680 },
    { time: 0.48, gain: 0.2, cut: 980 },
    { time: 0.86, gain: 0.1, cut: 720 },
  ];
  for (const tap of taps) {
    const delay = audio.createDelay(1.5);
    delay.delayTime.value = tap.time;
    const filter = audio.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = tap.cut;
    const wet = audio.createGain();
    wet.gain.value = tap.gain;
    source.connect(delay);
    delay.connect(filter);
    filter.connect(wet);
    wet.connect(audio.destination);
  }
}

/** Ordinary tap: one raspy squawk, pitch wanders a little so it isn't a loop. */
export function squawk(muted: boolean) {
  if (muted) return;
  const audio = context();
  if (!audio) return;
  const pitch = 390 + Math.random() * 110;
  voice(
    audio,
    audio.currentTime,
    pitch,
    0.24 + Math.random() * 0.05,
    0.09,
    Math.random() * 2,
    "bark",
    audio.destination,
  );
}

/** Golden macaw: a long rainforest scream, answered from deeper in the trees. */
export function gleam(muted: boolean) {
  if (muted) return;
  const audio = context();
  if (!audio) return;
  const bus = audio.createGain();
  bus.connect(audio.destination);
  canopy(audio, bus);

  const t = audio.currentTime;
  voice(audio, t, 310, 0.55, 0.055, 0.6, "cry", bus);
  voice(audio, t + 0.38, 470, 1.9, 0.1, 2.4, "cry", bus);
  voice(audio, t + 0.72, 240, 1.65, 0.042, 0.2, "cry", bus);
}
