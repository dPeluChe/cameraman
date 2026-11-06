# Background music

Instrumental music composed from code and rendered on the Mac, placed as an ordinary audio clip on the `Music`
track. Claude writes no audio itself: it picks a style or writes a score, and Web Audio renders it. Nothing leaves
the machine and there is no third-party licence to track. It suits ambient, lo-fi and electronic beds; it is not a
recorded orchestra.

## Pipeline

```
add_music (MCP, in-app server only)
  → a style from ScoreKit+Styles or custom code
  → MusicRenderer: off-screen page + OfflineAudioContext (48 kHz stereo) → AAC .m4a   (project assets/)
  → MusicSource saved as assets/music-x.json beside the audio
  → EditorModel.importAudioClip(volume:) → Music track
```

10 minutes of `lofi` render in about 30 s. The limit is 600 s per clip; use a second clip for longer videos. The same
score and seed give the same music.

## Reusable pieces

| Piece | Use |
|---|---|
| `HeadlessPage` | Off-screen page driven step by step with deadlines, for any renderer built on a web page |
| `RenderSource` | Sidecar storage for anything rendered from a source; `MotionSource` and `MusicSource` conform |
| `RenderedAssets` | `render(source, in:)` runs a render into assets and saves its source; also names, exact matching and cleanup. Add a `Kind` for a new type of render |
| `MusicSource` | A score plus its options, the one value to validate, store and render. Any UI can use it directly |
| `ScoreKit` | The JS library below; every style is written against the same API a custom score uses |

A new style is a function in `ScoreKit+Styles.swift` plus a case in `MusicStyle`.

## Writing a score

`code` is the body of `function (m, options)`. `options` has `duration`, `seed`, `intensity`, and `bpm` and `key` when
they were passed. `Math.random` is seeded, so it is safe to use. Times are in seconds.

```js
m.tempo(84).key('D dorian');
const keys = m.bus({ gain: 0.8, lowpass: 2500, reverb: 0.3 });
const low = m.bus({ lowpass: 300 });
m.bars((t, bar) => {
  const degree = [0, 3, 5, 4][bar % 4];
  m.voiced(m.triad(degree, 4, 4)).forEach(note => m.keys(note, t, m.bar * 0.8, { vel: 0.4, bus: keys }));
  if (m.active(t, 0.3)) m.bass(m.degree(degree, 2), t, m.beat * 2, { bus: low });
});
```

Start from a style and add to it: `Score.styles.lofi(m, options); m.impact(12);`

| Group | API |
|---|---|
| Time | `m.tempo(bpm)`, `m.beat`, `m.bar`, `m.duration`, `m.bars(fn(t, i), every)`, `m.steps(t, count, beats, fn(time, i), swing)`, `m.backbeat(t, opts)`, `m.euclid(hits, steps)` |
| Arrangement | `m.energy(t)` (0-1, the arc of the piece), `m.active(t, level)` (does a layer entering at `level` play now, given the arc and intensity) |
| Chance | `m.pick(list)`, `m.chance(p)`, `m.vary(value, amount)`, `m.random()` |
| Pitch | `m.key('A minor')`, `m.degree(d, octave)`, `m.triad(degree, octave, size)`, `m.chord('Fmaj7', octave)`, `m.voiced(chord)`, `m.midi('A3')` |
| Scales | major, minor, dorian, mixolydian, lydian, pentatonic, minorPentatonic |
| Routing | `m.bus({ gain, pan, lowpass, highpass, reverb, delay })`, used through `{ bus }` on every instrument |
| Sustained | `m.pad(chord, t, dur, opts)`, `m.strings(chord, t, dur, opts)`, `m.keys(pitch, t, dur, opts)`, `m.bass(pitch, t, dur, opts)`, `m.vinyl(t, dur, opts)`, `m.riser(t, dur, opts)` |
| Struck | `m.pluck(pitch, t, opts)`, `m.bell(pitch, t, opts)`, `m.kick(t, opts)`, `m.snare(t, opts)`, `m.hat(t, opts)`, `m.shaker(t, opts)`, `m.impact(t, opts)` |

Every instrument takes `vel` and `bus`. Keep pitches around octave 4, not 2-3: most laptop speakers lose what is
below 120 Hz. Output is levelled to the same loudness, so `volume` on the clip means the same for every score.

## Limits

No vocals. No ducking yet: lower the clip's `volume` to sit under a voice. WKWebView needs a window server, so like
motion graphics this runs only when the app hosts the MCP server.
