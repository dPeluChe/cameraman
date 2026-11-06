//
//  ScoreKit+Styles.swift
//  EngineKit
//
//  Ready-made background scores, written against the same Kit a custom score uses. They sit under
//  a voice: little melody, nothing bright in the speech range. Add a case to MusicStyle with each.
//

extension ScoreKit {
    static let styles = #"""
    (() => {
    const setup = (m, options, bpm, keys, progressions) => {
      m.tempo(options.bpm ?? Math.round(bpm * (0.9 + 0.2 * m.random()))).key(options.key ?? m.pick(keys));
      return m.pick(progressions);
    };

    Score.styles.ambient = (m, options) => {
      const steps = setup(m, options, 60, ['D major', 'F lydian', 'A minor', 'E minor'], [[0, 3, 5, 4], [0, 5, 3, 4], [0, 4, 5, 3]]);
      const pads = m.bus({ gain: 0.9, reverb: 0.55, highpass: 90 });
      const bells = m.bus({ gain: 0.5, reverb: 0.8, delay: 0.35, highpass: 500, lowpass: 3800, pan: 0.15 });
      const low = m.bus({ gain: 0.7, lowpass: 200 });
      m.bars((t, bar) => {
        const degree = steps[(bar / 2) % steps.length];
        const chord = m.voiced(m.triad(degree, 3, 4));
        m.pad(chord, t, m.bar * 2, { vel: 0.5, bus: pads, attack: 3, release: 4, cutoff: 700 + 500 * m.energy(t) });
        if (m.active(t, 0.3)) m.bass(m.degree(degree, 2), t, m.bar * 2, { vel: 0.4, bus: low });
        if (m.active(t, 0.45)) {
          m.steps(t, 8, 1, (at, i) => {
            if (m.chance(0.14)) m.bell(m.degree(m.pick([0, 2, 4, 7, 9]), 5), at, { vel: m.vary(0.35, 0.3), bus: bells, decay: 4 });
          });
        }
      }, 2);
    };

    Score.styles.lofi = (m, options) => {
      const steps = setup(m, options, 74, ['D dorian', 'A minor', 'G dorian', 'F major'], [[0, 3, 5, 4], [1, 4, 0, 5], [0, 5, 3, 4]]);
      const keys = m.bus({ gain: 0.85, lowpass: 2400, highpass: 140, reverb: 0.22, pan: -0.08 });
      const drums = m.bus({ gain: 0.7, lowpass: 5200, reverb: 0.05 });
      const low = m.bus({ gain: 0.8, lowpass: 320 });
      const air = m.bus({ gain: 0.6 });
      m.vinyl(0, m.duration, { vel: 0.5, bus: air });
      const swing = 0.17;
      m.bars((t, bar) => {
        const degree = steps[bar % steps.length];
        const chord = m.voiced(m.triad(degree, 4, 4));
        chord.forEach((note, i) => m.keys(note, t + i * 0.012, m.bar * 0.72, { vel: m.vary(0.42, 0.12), bus: keys, pan: [-0.3, 0.2, -0.1, 0.3][i] }));
        if (bar % 2) chord.slice(1).forEach((note, i) => m.keys(note, t + m.beat * 2.5, m.bar * 0.3, { vel: 0.26, bus: keys, pan: 0.25 - i * 0.25 }));
        if (m.active(t, 0.3)) {
          m.bass(m.degree(degree, 2), t, m.beat * 1.4, { vel: 0.55, bus: low });
          m.bass(m.degree(degree + (bar % 4 === 3 ? 4 : 0), 2), t + m.beat * 2.5, m.beat, { vel: 0.45, bus: low });
        }
        if (m.active(t, 0.4)) {
          m.kick(t, { vel: 0.55, bus: drums });
          m.kick(t + m.beat * 2.5, { vel: 0.42, bus: drums });
          m.backbeat(t, { vel: 0.3, bus: drums, tone: 1300 });
          m.steps(t, 8, 0.5, (at, i) => m.hat(at, { vel: i % 2 ? 0.14 : 0.22, bus: drums }), swing);
        }
      });
    };

    Score.styles.corporate = (m, options) => {
      const steps = setup(m, options, 104, ['C major', 'G major', 'D major', 'F major'], [[0, 4, 5, 3], [5, 3, 0, 4], [0, 3, 5, 4]]);
      const plucks = m.bus({ gain: 0.75, highpass: 200, lowpass: 4200, reverb: 0.25, delay: 0.16, pan: 0.12 });
      const pads = m.bus({ gain: 0.55, reverb: 0.4, highpass: 160 });
      const low = m.bus({ gain: 0.75, lowpass: 340 });
      const drums = m.bus({ gain: 0.55, lowpass: 7000, reverb: 0.06 });
      m.bars((t, bar) => {
        const degree = steps[bar % steps.length];
        const chord = m.voiced(m.triad(degree, 4, 3));
        m.pad(chord, t, m.bar, { vel: 0.34, bus: pads, attack: 0.4, release: 0.9, cutoff: 1800 });
        const line = [...chord, chord[0] + 12, chord[1] + 12];
        m.steps(t, 8, 0.5, (at, i) => m.pluck(line[[0, 2, 1, 3, 2, 4, 3, 2][i]], at, { vel: i % 4 ? 0.34 : 0.48, bus: plucks, pan: i % 2 ? 0.35 : -0.35 }));
        if (m.active(t, 0.3)) m.steps(t, 4, 1, at => m.bass(m.degree(degree, 2), at, m.beat * 0.8, { vel: 0.46, bus: low }));
        if (m.active(t, 0.42)) {
          m.steps(t, 4, 1, at => m.kick(at, { vel: 0.36, bus: drums }));
          m.steps(t, 4, 1, at => m.hat(at + m.beat / 2, { vel: 0.2, bus: drums, open: true }));
          m.backbeat(t, { vel: 0.24, bus: drums, tone: 2200 });
        }
      });
    };

    Score.styles.tech = (m, options) => {
      const steps = setup(m, options, 118, ['A minor', 'E minor', 'F# minor'], [[0, 5, 2, 6], [0, 3, 5, 4], [0, 6, 5, 6]]);
      const pulse = m.bus({ gain: 0.6, highpass: 220, lowpass: 2600, reverb: 0.16, delay: 0.3 });
      const pads = m.bus({ gain: 0.5, reverb: 0.5, highpass: 200 });
      const low = m.bus({ gain: 0.8, lowpass: 300 });
      const drums = m.bus({ gain: 0.62, lowpass: 9000 });
      const hits = m.euclid(5, 16);
      m.bars((t, bar) => {
        const degree = steps[bar % steps.length];
        const chord = m.voiced(m.triad(degree, 4, 3));
        m.pad(chord, t, m.bar, { vel: 0.3, bus: pads, attack: 0.9, release: 1.2, cutoff: 1500, wave: 'square' });
        m.steps(t, 16, 0.25, (at, i) => {
          if (hits[i]) m.keys(chord[i % chord.length] + 12, at, m.beat * 0.2, { vel: 0.3, bus: pulse, decay: 0.3, pan: i % 3 ? 0.3 : -0.3 });
        });
        if (m.active(t, 0.28)) m.steps(t, 8, 0.5, at => m.bass(m.degree(degree, 1) + 12, at, m.beat * 0.4, { vel: 0.5, bus: low }));
        if (m.active(t, 0.42)) {
          m.steps(t, 4, 1, at => m.kick(at, { vel: 0.62, bus: drums, low: 50 }));
          m.steps(t, 8, 0.5, (at, i) => m.hat(at, { vel: i % 2 ? 0.2 : 0.1, bus: drums }));
          m.backbeat(t, { vel: 0.2, bus: drums, tone: 2600 });
        }
        if (bar % 8 === 7 && m.active(t, 0.35)) m.riser(t, m.bar, { vel: 0.2, bus: pads });
      });
    };

    Score.styles.cinematic = (m, options) => {
      const steps = setup(m, options, 66, ['D minor', 'C minor', 'A minor'], [[0, 5, 2, 6], [0, 3, 5, 4], [0, 5, 3, 4]]);
      const strings = m.bus({ gain: 0.85, reverb: 0.5, highpass: 110 });
      const low = m.bus({ gain: 0.8, lowpass: 240, reverb: 0.1 });
      const drums = m.bus({ gain: 0.65, reverb: 0.3, lowpass: 1600 });
      const bells = m.bus({ gain: 0.42, reverb: 0.8, delay: 0.25, lowpass: 3600 });
      m.impact(0.1, { vel: 0.6, bus: drums });
      m.bars((t, bar) => {
        const degree = steps[(bar / 2) % steps.length];
        const chord = m.voiced(m.triad(degree, 3, 3));
        m.strings(chord, t, m.bar * 2, { vel: 0.42 + 0.3 * m.energy(t), bus: strings, attack: 1.4, release: 2 });
        if (m.active(t, 0.3)) m.strings([m.degree(degree, 2)], t, m.bar * 2, { vel: 0.5, bus: low, attack: 0.9 });
        if (m.active(t, 0.42)) {
          m.steps(t, 16, 0.5, (at, i) => m.bass(m.degree(degree, 1) + 12, at, m.beat * 0.34, { vel: i % 4 ? 0.28 : 0.42, bus: low }));
        }
        if (m.active(t, 0.55)) {
          m.steps(t, 8, 1, (at, i) => { if (i % 4 === 0 || i === 3 || i === 7) m.kick(at, { vel: 0.55, bus: drums, low: 42 }); });
          m.steps(t, 4, 2, at => m.bell(m.degree(m.pick([0, 2, 4]), 5), at, { vel: 0.24, bus: bells, decay: 3 }));
        }
      }, 2);
    };

    Score.styles.acoustic = (m, options) => {
      const steps = setup(m, options, 92, ['G major', 'D major', 'A major', 'C major'], [[0, 4, 5, 3], [0, 3, 0, 4], [5, 3, 0, 4]]);
      const guitar = m.bus({ gain: 0.95, highpass: 120, lowpass: 5200, reverb: 0.28 });
      const low = m.bus({ gain: 0.7, lowpass: 300 });
      const hand = m.bus({ gain: 0.5, lowpass: 8000, reverb: 0.12, pan: 0.2 });
      m.bars((t, bar) => {
        const degree = steps[bar % steps.length];
        const chord = m.voiced(m.triad(degree, 4, 3));
        const root = m.degree(degree, 3);
        const line = [root, chord[0], chord[1], chord[2], chord[1] + 12, chord[2], chord[1], chord[0]];
        m.steps(t, 8, 0.5, (at, i) => m.pluck(line[i], at + m.random() * 0.008, { vel: m.vary(i % 4 ? 0.42 : 0.56, 0.12), bus: guitar, damping: 0.35, pan: [-0.25, -0.1, 0.1, 0.3, 0.2, 0, -0.2, -0.3][i] }));
        if (m.active(t, 0.32)) {
          m.bass(root - 12, t, m.beat * 1.8, { vel: 0.4, bus: low });
          m.bass(root - 5, t + m.beat * 2, m.beat * 1.6, { vel: 0.32, bus: low });
        }
        if (m.active(t, 0.42)) m.steps(t, 8, 0.5, (at, i) => m.shaker(at, { vel: i % 2 ? 0.34 : 0.2, bus: hand }), 0.08);
      });
    };
    })();
    """#
}
