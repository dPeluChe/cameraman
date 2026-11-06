//
//  ScoreKit.swift
//  EngineKit
//
//  The music library a score is written against, in JS because it renders through Web Audio.
//  No dependencies: the page has no base URL to load one from. API in docs/FEATURES/MUSIC.md.
//

enum ScoreKit {
    static let script = engine + "\n" + styles

    private static let engine = #"""
    (() => {
    const NOTES = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
    const SCALES = {
      major: [0, 2, 4, 5, 7, 9, 11], minor: [0, 2, 3, 5, 7, 8, 10], dorian: [0, 2, 3, 5, 7, 9, 10],
      mixolydian: [0, 2, 4, 5, 7, 9, 10], lydian: [0, 2, 4, 6, 7, 9, 11],
      pentatonic: [0, 2, 4, 7, 9], minorPentatonic: [0, 3, 5, 7, 10],
    };
    const CHORDS = { '': [0, 4, 7], m: [0, 3, 7], 7: [0, 4, 7, 10], m7: [0, 3, 7, 10], maj7: [0, 4, 7, 11], sus2: [0, 2, 7], sus4: [0, 5, 7], add9: [0, 4, 7, 14], madd9: [0, 3, 7, 14] };
    const hz = midi => 440 * 2 ** ((midi - 69) / 12);

    function seeded(seed) {
      let a = seed >>> 0;
      return () => {
        a = (a + 0x6D2B79F5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
      };
    }

    class Kit {
      constructor(ctx, options) {
        this.ctx = ctx;
        this.duration = options.duration;
        this.intensity = options.intensity ?? 0.5;
        this.random = seeded(options.seed ?? 1);
        this.queue = [];
        this.live = [];
        this.plucks = new Map();
        this.previous = null;

        const fadeOut = Math.min(3, this.duration * 0.1);
        const fade = ctx.createGain();
        fade.gain.setValueAtTime(0, 0);
        fade.gain.linearRampToValueAtTime(1, Math.min(0.8, this.duration * 0.1));
        fade.gain.setValueAtTime(1, this.duration - fadeOut);
        fade.gain.linearRampToValueAtTime(0, this.duration);
        const limiter = ctx.createDynamicsCompressor();
        limiter.threshold.value = -14;
        limiter.ratio.value = 4;
        limiter.attack.value = 0.01;
        limiter.release.value = 0.25;
        this.master = ctx.createGain();
        this.master.connect(limiter).connect(fade).connect(ctx.destination);

        this.noiseBuffer = this.buffer(2, 1, data => { for (let i = 0; i < data.length; i++) data[i] = this.random() * 2 - 1; });
        this.reverbSend = ctx.createConvolver();
        this.reverbSend.normalize = true;
        this.reverbSend.buffer = this.impulse(3.2);
        this.reverbSend.connect(this.master);
        this.delaySend = ctx.createDelay(2);
        const feedback = ctx.createGain();
        feedback.gain.value = 0.32;
        this.delaySend.connect(feedback).connect(this.delaySend);
        this.delaySend.connect(this.master);
        this.mix = this.bus();
        this.tempo(90);
        this.key('A minor');
      }

      // Time and arrangement

      tempo(bpm) { this.beat = 60 / bpm; this.bar = this.beat * 4; this.delaySend.delayTime.value = this.beat * 0.75; return this; }

      /** Calls fn(t, index) at the start of every bar that fits. */
      bars(fn, every = 1) { for (let i = 0, t = 0; t < this.duration; i += every, t = i * this.bar) fn(t, i); }

      /** Calls fn(time, index) on `count` steps of `beats` from t. `swing` delays the off steps, 0-0.5. */
      steps(t, count, beats, fn, swing = 0) {
        for (let i = 0; i < count; i++) fn(t + (i + (i % 2 ? swing : 0)) * beats * this.beat, i);
      }

      /** Snares on beats 2 and 4 of the bar starting at t. */
      backbeat(t, options) { this.snare(t + this.beat, options); this.snare(t + this.beat * 3, options); }

      /** `hits` onsets spread evenly over `steps`, as booleans. */
      euclid(hits, steps) { return Array.from({ length: steps }, (_, i) => (i * hits) % steps < hits); }

      /** The arc of the piece at time t, 0-1: builds from the start and settles at the end. */
      energy(t) {
        const edge = Math.min(8, this.duration * 0.15);
        const ends = Math.min(1, Math.min(t, this.duration - t) / edge);
        return ends * (0.72 + 0.28 * Math.sin(Math.PI * t / this.duration));
      }

      /** True when the arc and the intensity allow a layer that enters at `level`, 0-1. */
      active(t, level) { return this.energy(t) * (0.55 + 0.9 * this.intensity) >= level; }

      pick(list) { return list[Math.floor(this.random() * list.length)]; }
      chance(p) { return this.random() < p; }
      vary(value, amount = 0.1) { return value * (1 + (this.random() * 2 - 1) * amount); }

      // Pitch

      key(name) {
        const [root, scale = 'minor'] = name.trim().split(/\s+/);
        if (!(root in NOTES) || !SCALES[scale]) throw new Error(`Unknown key '${name}'`);
        this.root = NOTES[root];
        this.scale = SCALES[scale];
        return this;
      }

      /** 'A3' to a MIDI number; numbers pass through. */
      midi(pitch) {
        if (typeof pitch === 'number') return pitch;
        const match = /^([A-G][#b]?)(-?\d)$/.exec(pitch);
        if (!match) throw new Error(`Unknown note '${pitch}'`);
        return NOTES[match[1]] + (Number(match[2]) + 1) * 12;
      }

      /** Scale degree from 0, in the current key. Runs past the octave and below 0. */
      degree(degree, octave = 4) {
        const size = this.scale.length;
        const wrapped = ((degree % size) + size) % size;
        return 12 * (octave + 1 + Math.floor(degree / size)) + this.root + this.scale[wrapped];
      }

      /** Chord stacked in thirds on a scale degree, so it stays in key. */
      triad(degree, octave = 3, size = 3) {
        return Array.from({ length: size }, (_, i) => this.degree(degree + i * 2, octave));
      }

      /** A chord by name: 'Am7', 'Fmaj7', 'Csus2'. */
      chord(name, octave = 3) {
        const match = /^([A-G][#b]?)(.*)$/.exec(name);
        if (!match || !(match[2] in CHORDS)) throw new Error(`Unknown chord '${name}'`);
        return CHORDS[match[2]].map(step => 12 * (octave + 1) + NOTES[match[1]] + step);
      }

      /** This chord in the inversion closest to the last one, so voices move as little as possible. */
      voiced(chord) {
        let best = chord;
        if (this.previous) {
          const center = this.previous.reduce((a, b) => a + b) / this.previous.length;
          let lowest = Infinity;
          for (let octave = -2; octave <= 2; octave++) {
            for (let turn = 0; turn < chord.length; turn++) {
              const candidate = chord.map((note, i) => note + 12 * (octave + (i < turn ? 1 : 0)));
              const distance = Math.abs(candidate.reduce((a, b) => a + b) / candidate.length - center);
              if (distance < lowest) { lowest = distance; best = candidate; }
            }
          }
        }
        this.previous = best;
        return best;
      }

      // Routing

      /** A mix channel. gain, pan -1..1, lowpass and highpass in Hz, reverb and delay sends 0-1. */
      bus({ gain = 1, pan = 0, lowpass, highpass, reverb = 0, delay = 0 } = {}) {
        const ctx = this.ctx;
        const input = ctx.createGain();
        input.gain.value = gain;
        let tail = input;
        if (highpass) tail = tail.connect(this.filter('highpass', highpass));
        if (lowpass) tail = tail.connect(this.filter('lowpass', lowpass));
        const panner = ctx.createStereoPanner();
        panner.pan.value = pan;
        tail.connect(panner).connect(this.master);
        const send = (amount, target) => {
          if (amount <= 0) return;
          const level = ctx.createGain();
          level.gain.value = amount;
          tail.connect(level).connect(target);
        };
        send(reverb, this.reverbSend);
        send(delay, this.delaySend);
        return input;
      }

      /** A bus input offset in the stereo field, for one voice. */
      panned(bus, pan, end) {
        if (!pan) return bus;
        const node = this.ctx.createStereoPanner();
        node.pan.value = pan;
        node.connect(bus);
        this.retire(end, node);
        return node;
      }

      filter(type, frequency, q = 0.7) {
        const node = this.ctx.createBiquadFilter();
        node.type = type;
        node.frequency.value = frequency;
        node.Q.value = q;
        return node;
      }

      // Instruments: pitch is 'A3' or a MIDI number, a chord an array of them. All take { vel, bus }.

      pad(chord, t, dur, { vel = 0.5, bus = this.mix, attack = 1.6, release = 2.4, cutoff = 900, wave = 'sawtooth' } = {}) {
        this.later(t, () => {
          const end = t + dur + release;
          const amp = this.envelope(t, attack, 0, 1, dur, release, vel / Math.sqrt(chord.length) * 0.5);
          amp.connect(bus);
          for (const [cents, pan] of [[-7, -0.6], [0, 0], [7, 0.6]]) {
            const filter = this.filter('lowpass', cutoff, 0.5);
            filter.frequency.setValueAtTime(cutoff * 0.6, t);
            filter.frequency.linearRampToValueAtTime(cutoff, t + dur * 0.6);
            filter.frequency.linearRampToValueAtTime(cutoff * 0.7, end);
            filter.connect(this.panned(amp, pan, end));
            for (const pitch of chord) this.oscillator(wave, hz(this.midi(pitch)), t, end, cents).connect(filter);
            this.retire(end, filter);
          }
          this.retire(end, amp);
        });
      }

      strings(chord, t, dur, { vel = 0.5, bus = this.mix, attack = 0.7, release = 1.6, cutoff = 2200 } = {}) {
        this.later(t, () => {
          const end = t + dur + release;
          const filter = this.filter('lowpass', cutoff, 0.4);
          const amp = this.envelope(t, attack, 0, 1, dur, release, vel / Math.sqrt(chord.length) * 0.4);
          filter.connect(amp).connect(bus);
          const lfo = this.oscillator('sine', 4.6, t, end);
          const depth = this.ctx.createGain();
          depth.gain.value = 5;
          lfo.connect(depth);
          for (const pitch of chord) {
            for (const cents of [-11, -4, 4, 11]) {
              const voice = this.oscillator('sawtooth', hz(this.midi(pitch)), t, end, cents);
              depth.connect(voice.detune);
              voice.connect(filter);
            }
          }
          this.retire(end, filter, amp, depth);
        });
      }

      /** Electric piano: two FM pairs, a soft body and a short bright tine. */
      keys(pitch, t, dur, { vel = 0.5, bus = this.mix, decay = 1.8, pan = 0 } = {}) {
        this.later(t, () => {
          const frequency = hz(this.midi(pitch));
          const end = t + dur + 0.3;
          const amp = this.envelope(t, 0.004, decay, 0.15, dur, 0.3, vel * 0.42);
          amp.connect(this.panned(bus, pan, end));
          const fm = (ratio, index, fall, level) => {
            const carrier = this.oscillator('sine', frequency, t, end);
            const modulator = this.oscillator('sine', frequency * ratio, t, end);
            const depth = this.ctx.createGain();
            depth.gain.setValueAtTime(frequency * index, t);
            depth.gain.exponentialRampToValueAtTime(Math.max(0.01, frequency * index * 0.02), t + fall);
            const gain = this.ctx.createGain();
            gain.gain.value = level;
            modulator.connect(depth).connect(carrier.frequency);
            carrier.connect(gain).connect(amp);
            this.retire(end, depth, gain);
          };
          fm(1, 0.9, 0.9, 1);
          fm(14, 0.5, 0.12, 0.22);
          this.retire(end, amp);
        });
      }

      /** Plucked string (Karplus-Strong): guitar or harp depending on the register. */
      pluck(pitch, t, { vel = 0.5, bus = this.mix, damping = 0.5, pan = 0 } = {}) {
        this.later(t, () => {
          const midi = Math.round(this.midi(pitch));
          const source = this.ctx.createBufferSource();
          source.buffer = this.pluckBuffer(midi, damping);
          const gain = this.ctx.createGain();
          gain.gain.value = vel * 1.1;
          const end = t + source.buffer.duration;
          source.connect(gain).connect(this.panned(bus, pan, end));
          source.start(t);
          this.retire(end, source, gain);
        });
      }

      bass(pitch, t, dur, { vel = 0.5, bus = this.mix, cutoff = 420 } = {}) {
        this.later(t, () => {
          const frequency = hz(this.midi(pitch));
          const end = t + dur + 0.08;
          const filter = this.filter('lowpass', cutoff);
          const amp = this.envelope(t, 0.008, 0.2, 0.75, dur, 0.08, vel * 0.32);
          filter.connect(amp).connect(bus);
          this.oscillator('triangle', frequency, t, end).connect(filter);
          this.oscillator('sine', frequency, t, end).connect(filter);
          this.retire(end, filter, amp);
        });
      }

      bell(pitch, t, { vel = 0.5, bus = this.mix, decay = 3 } = {}) {
        this.later(t, () => {
          const frequency = hz(this.midi(pitch));
          const end = t + decay;
          const amp = this.decay(t, end, vel * 0.16, 0.0001, 0.004);
          const carrier = this.oscillator('sine', frequency, t, end);
          const modulator = this.oscillator('sine', frequency * 3.01, t, end);
          const depth = this.ctx.createGain();
          depth.gain.setValueAtTime(frequency * 1.4, t);
          depth.gain.exponentialRampToValueAtTime(1, t + decay * 0.5);
          modulator.connect(depth).connect(carrier.frequency);
          carrier.connect(amp).connect(bus);
          this.retire(end, amp, depth);
        });
      }

      kick(t, { vel = 0.8, bus = this.mix, low = 54 } = {}) {
        this.later(t, () => {
          const end = t + 0.34;
          const voice = this.oscillator('sine', 130, t, end);
          voice.frequency.exponentialRampToValueAtTime(low, t + 0.1);
          const amp = this.decay(t, end, vel * 0.5);
          voice.connect(amp).connect(bus);
          this.burst(t, 0.012, this.filter('bandpass', 2600, 0.7), vel * 0.18, bus);
          this.retire(end, amp);
        });
      }

      snare(t, { vel = 0.5, bus = this.mix, tone = 1700 } = {}) {
        this.later(t, () => {
          this.burst(t, 0.18, this.filter('bandpass', tone, 0.8), vel * 0.8, bus);
          const end = t + 0.1;
          const amp = this.decay(t, end, vel * 0.3);
          this.oscillator('triangle', 190, t, end).connect(amp).connect(bus);
          this.retire(end, amp);
        });
      }

      hat(t, { vel = 0.3, bus = this.mix, open = false } = {}) {
        this.later(t, () => this.burst(t, open ? 0.22 : 0.05, this.filter('highpass', 7500), vel * 0.5, bus));
      }

      shaker(t, { vel = 0.3, bus = this.mix } = {}) {
        this.later(t, () => this.burst(t, 0.07, this.filter('bandpass', 5200, 1.2), vel * 0.5, bus, 0.018));
      }

      /** A low hit to mark a moment. */
      impact(t, { vel = 0.8, bus = this.mix } = {}) {
        this.later(t, () => {
          const end = t + 2.2;
          const voice = this.oscillator('sine', 72, t, end);
          voice.frequency.exponentialRampToValueAtTime(34, t + 1.1);
          const amp = this.decay(t, end, vel * 0.8);
          voice.connect(amp).connect(bus);
          this.burst(t, 0.5, this.filter('lowpass', 900), vel * 0.4, bus);
          this.retire(end, amp);
        });
      }

      /** Filtered noise that swells over `dur`, to lead into a section. */
      riser(t, dur, { vel = 0.3, bus = this.mix } = {}) {
        this.later(t, () => {
          const end = t + dur;
          const filter = this.filter('bandpass', 300, 1.5);
          filter.frequency.exponentialRampToValueAtTime(6000, end);
          const amp = this.ctx.createGain();
          amp.gain.setValueAtTime(0.0001, t);
          amp.gain.exponentialRampToValueAtTime(vel * 0.5, end - 0.05);
          amp.gain.linearRampToValueAtTime(0, end);
          this.noiseSource(t, end).connect(filter).connect(amp).connect(bus);
          this.retire(end, filter, amp);
        });
      }

      /** Vinyl surface: hiss with optional `crackle` clicks, over a whole span. */
      vinyl(t, dur, { vel = 0.5, bus = this.mix, crackle = 0 } = {}) {
        this.later(t, () => {
          const end = t + dur;
          const source = this.ctx.createBufferSource();
          source.buffer = this.buffer(6, 2, data => {
            for (let i = 0; i < data.length; i++) {
              const click = this.random() < 0.00012 * crackle ? (this.random() - 0.5) * 3 : 0;
              data[i] = (this.random() - 0.5) * 0.012 + click;
            }
          });
          source.loop = true;
          const filter = this.filter('bandpass', 2400, 0.4);
          const gain = this.ctx.createGain();
          gain.gain.value = vel * 0.25;
          source.connect(filter).connect(gain).connect(bus);
          source.start(t);
          source.stop(end);
          this.retire(end, source, filter, gain);
        });
      }

      // Building blocks

      oscillator(type, frequency, start, stop, cents = 0) {
        const node = this.ctx.createOscillator();
        node.type = type;
        node.frequency.value = frequency;
        node.detune.value = cents;
        node.start(start);
        node.stop(stop);
        this.retire(stop, node);
        return node;
      }

      envelope(t, attack, decay, sustain, hold, release, peak) {
        const node = this.ctx.createGain();
        node.gain.setValueAtTime(0, t);
        node.gain.linearRampToValueAtTime(peak, t + attack);
        if (decay > 0) node.gain.setTargetAtTime(peak * sustain, t + attack, decay / 3);
        node.gain.setValueAtTime(peak * sustain, Math.max(t + attack, t + hold));
        node.gain.linearRampToValueAtTime(0, t + hold + release);
        return node;
      }

      decay(t, end, peak, floor = 0.001, attack = 0) {
        const node = this.ctx.createGain();
        node.gain.setValueAtTime(attack ? 0 : peak, t);
        if (attack) node.gain.linearRampToValueAtTime(peak, t + attack);
        node.gain.exponentialRampToValueAtTime(floor, end);
        return node;
      }

      noiseSource(start, stop) {
        const node = this.ctx.createBufferSource();
        node.buffer = this.noiseBuffer;
        node.loop = true;
        node.start(start, this.random() * 1.5);
        node.stop(stop);
        this.retire(stop, node);
        return node;
      }

      burst(t, length, filter, level, bus, attack = 0) {
        const end = t + length;
        const amp = this.ctx.createGain();
        amp.gain.setValueAtTime(attack ? 0.0001 : level, t);
        if (attack) amp.gain.linearRampToValueAtTime(level, t + attack);
        amp.gain.exponentialRampToValueAtTime(0.001, end);
        this.noiseSource(t, end).connect(filter).connect(amp).connect(bus);
        this.retire(end, filter, amp);
      }

      buffer(seconds, channels, fill) {
        const buffer = this.ctx.createBuffer(channels, Math.round(seconds * this.ctx.sampleRate), this.ctx.sampleRate);
        for (let c = 0; c < channels; c++) fill(buffer.getChannelData(c), c);
        return buffer;
      }

      impulse(seconds) {
        const rate = this.ctx.sampleRate;
        return this.buffer(seconds, 2, data => {
          let low = 0;
          for (let i = 0; i < data.length; i++) {
            const time = i / rate;
            low += ((this.random() * 2 - 1) - low) * Math.max(0.08, 0.5 * Math.exp(-time * 1.4));
            data[i] = low * Math.exp(-time * 6.9 / seconds) * Math.min(1, time / 0.012);
          }
        });
      }

      pluckBuffer(midi, damping) {
        const id = `${midi}/${damping}`;
        if (this.plucks.has(id)) return this.plucks.get(id);
        const rate = this.ctx.sampleRate;
        const period = Math.max(2, Math.round(rate / hz(midi)));
        const ring = new Float32Array(period);
        let last = 0;
        for (let i = 0; i < period; i++) { last += ((this.random() * 2 - 1) - last) * 0.6; ring[i] = last; }
        const loss = 0.5 * (1 - 0.0016 * (1 - damping) - 0.008 * damping);
        const seconds = Math.min(3.5, 1.2 + 110 / hz(midi) * 4);
        const buffer = this.buffer(seconds, 1, data => {
          for (let i = 0; i < data.length; i++) {
            const at = i % period, next = (at + 1) % period;
            data[i] = ring[at] * Math.min(1, (data.length - i) / (rate * 0.05));
            ring[at] = (ring[at] + ring[next]) * loss * (1 + 0.0005);
          }
        });
        this.plucks.set(id, buffer);
        return buffer;
      }

      // Scheduling: thousands of idle nodes slow every render quantum, so a voice exists only near its time.

      later(t, build) { if (t < this.duration) this.queue.push({ t, build }); }

      retire(end, ...nodes) { for (const node of nodes) this.live.push({ end, node }); }

      flush(now, until) {
        this.queue = this.queue.filter(event => (event.t < until ? (event.build(), false) : true));
        this.live = this.live.filter(voice => (voice.end < now ? (voice.node.disconnect(), false) : true));
      }
    }

    const WINDOW = 4;

    async function render({ code, style, options, sampleRate }) {
      const ctx = new OfflineAudioContext(2, Math.round(options.duration * sampleRate), sampleRate);
      const kit = new Kit(ctx, options);
      Math.random = kit.random;
      if (style) {
        if (!Score.styles[style]) throw new Error(`Unknown style '${style}'`);
        Score.styles[style](kit, options);
      } else {
        new Function('m', 'options', code)(kit, options);
      }
      kit.queue.sort((a, b) => a.t - b.t);
      kit.flush(0, WINDOW * 2);
      for (let at = WINDOW; at < options.duration - 0.1; at += WINDOW) {
        ctx.suspend(at).then(() => { kit.flush(at, at + WINDOW * 2); ctx.resume(); });
      }
      const rendered = await ctx.startRendering();
      const left = rendered.getChannelData(0), right = rendered.getChannelData(1);
      let peak = 0, power = 0;
      for (let i = 0; i < left.length; i++) {
        peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
        power += left[i] * left[i] + right[i] * right[i];
      }
      if (!isFinite(power)) throw new Error('The score produced invalid audio.');
      if (peak <= 0.0005) throw new Error('The score made no sound.');
      const loudness = Math.sqrt(power / (2 * left.length));
      // Same level across scores, so one clip volume suits them all.
      const scale = Math.min(0.89 / peak, 0.16 / loudness);
      for (let i = 0; i < left.length; i++) { left[i] *= scale; right[i] *= scale; }
      Score.channels = [left, right];
      return left.length;
    }

    /** One stretch of the rendered audio as base64: left samples then right, Float32. */
    function chunk(start, count) {
      const [left, right] = Score.channels;
      const samples = new Float32Array(count * 2);
      samples.set(left.subarray(start, start + count), 0);
      samples.set(right.subarray(start, start + count), count);
      const bytes = new Uint8Array(samples.buffer);
      let binary = '';
      for (let i = 0; i < bytes.length; i += 32768) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
      return btoa(binary);
    }

    window.Score = { render, chunk, styles: {} };
    })();
    """#
}
