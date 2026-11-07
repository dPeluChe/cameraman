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

10 minutes of `lofi` render in about 30 s. The limit is 600 s per render. Longer music is split into equal pieces within it (`MusicSource.sections(of:)`), rendered with consecutive seeds (`MusicRenderer.renderChain`) and placed back to back on one Music track as a single edit, so a 25-minute video gets three 8:20 pieces. The same
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
| Sustained | `m.pad(chord, t, dur, opts)`, `m.strings(chord, t, dur, opts)`, `m.keys(pitch, t, dur, opts)`, `m.bass(pitch, t, dur, opts)`, `m.vinyl(t, dur, opts)` (hiss; `crackle: 1` adds clicks), `m.riser(t, dur, opts)` |
| Struck | `m.pluck(pitch, t, opts)`, `m.bell(pitch, t, opts)`, `m.kick(t, opts)`, `m.snare(t, opts)`, `m.hat(t, opts)`, `m.shaker(t, opts)`, `m.impact(t, opts)` |

Every instrument takes `vel` and `bus`. Keep pitches around octave 4, not 2-3: most laptop speakers lose what is
below 120 Hz. Output is levelled to the same loudness, so `volume` on the clip means the same for every score.

## In the app

The Music tool in the right panel composes a piece from a style and an intensity. A piece made there or by an agent can
be changed from either side, because both call the same engine code and read the same sidecar: style, intensity,
another variation (next seed: tempo and melodic figure step with it, so neighbours sound apart), fit to the video, volume and how far it drops under the voice. Scores written in code
show as "Custom score"; picking a style replaces them. Music runs to the end of the picture; past 10 minutes it is several pieces, each edited on its own. Fit to Video stops at the next piece on its track.

Replacing a piece keeps the one before it: **Use Previous** in the panel, or `usePrevious` on `update_music`, swaps the
two without rendering, and doing it again returns. The link is `previous` in the sidecar, so the project format does not
change. Cleanup keeps that one file for each clip; anything older goes when the project next opens.

Each style tile has a play button for a 12-second sample (`MusicRenderer.sample(of:)`), rendered once into
`Caches/MusicSamples` and named with a hash of ScoreKit, so editing the styles renders fresh samples and drops the old ones.
**Import Audio File…** copies a song into the project's assets and places it like generated music (Music track, default
volume and ducking), cut to the picture (`RenderedMusic.importSong`, also `add_music` with `file`). It has no sidecar, so the panel treats it as plain audio. Selecting a generated
piece on the timeline shows **Edit Music** in the clip bar, which opens the tool on it.

## Ducking

A Music track drops under speech, to half its volume by default. `duckingLevel` on the track is the only thing stored:
`AudioDucking` turns the transcript into a volume envelope each time a composition is built, so preview and export
agree and it follows cuts, splits and moves. Pauses under 1.2 s stay low so the music does not pump between phrases.
Without a transcript nothing drops; `add_music` says so in `speechDucking`. Speech is read from unmuted recording clips
of the first take on the primary track, so it needs `transcribe_project` on the recording, and imported video with
speech does not count. Only audio tracks duck. Export always reads the current transcript; an open preview picks a new
one up on its next edit. Bundles keep `transcript.json`; merged projects start without one, so transcribe them again.

## Limits

No vocals. WKWebView needs a window server, so like
motion graphics this runs only when the app hosts the MCP server.
