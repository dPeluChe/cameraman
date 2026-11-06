# Motion graphics

Code-built animations (a name card, a stat that counts up, a bar chart) rendered to a transparent video and laid
over the footage as an ordinary clip. The agent reads the transcript (`get_captions`), picks the moments and calls
`add_motion`; the result is a clip on the `Motion` track, so every existing edit (`edit_clip`, `delete_clip`,
opacity, adjustments, position) works on it. `update_motion` changes one in place and `preview_frame` shows the result.

## Pipeline

```
add_motion (MCP, in-app server only)
  → MotionTemplate.html(...) or custom html
  → MotionRenderer: WKWebView off screen, seek(t) → snapshot → HEVC with alpha .mov   (project assets/)
  → MotionSource saved as assets/motion-x.json beside the video
  → EditorModel.importVideoClip(position:)  → video overlay track, under the camera
  → MaskedVideoCompositor composites it source-over (alpha respected) in preview and export
```

No engine change was needed for compositing: imported video overlay tracks already existed and blend with
`CIImage.composited(over:)`. `MotionRendererTests.testMotionIsBlendedOverFootageOnExport` proves it end to end
(render, import, export, read the pixels).

## The page contract

Time is driven from outside so the same page gives the same frames (the idea is HeyGen's HyperFrames, Apache 2.0,
`window.__hf`; a GSAP timeline in `window.__timelines` also works unchanged):

```js
window.__hf = { duration: 4, seek(t) { /* set the whole scene for time t */ } }
```

Without `__hf`, `MotionAdapter` builds one: it seeks GSAP timelines and pauses every CSS/WAAPI animation at `t`;
the duration is the longest finite animation. The page background must stay transparent. Rules for authors: no
`Date.now`, no unseeded `Math.random`, no network, text in `vh`/`vw`. The page is loaded from a string with no base
URL, so it cannot reference local files yet (see the vendored-runtime item in `TASK_TODO.md`).

## Templates (`MotionTemplate`)

| template | needs | notes |
|---|---|---|
| `lower_third` | title, subtitle? | name card, bottom left |
| `title` | title, subtitle? | centered |
| `stat` | value (`42`, `42%`, `$1.2M`), title? | counts up through `__hf` |
| `bar_chart` | labels[] + values[] (same length, ≤ 12), title? | bars grow staggered |

All take `color` (#RRGGBB) and `duration` (default 4 s, minimum 1.5 s); they animate in, hold and animate out,
ending exactly at `duration`. Text is HTML-escaped, colors are validated, `stat` values go into the page as JSON strings.

## Working on a motion

- **Tracks:** motions share one `Motion` track. A second one opens only when two overlap.
- **Placement:** `add_motion` replies with `visibleArea`, where the motion draws as canvas fractions (`VideoContentShape`
  samples 12 frames). Change it with `edit_clip` x/y/w/h, or drag it on the preview: the outline follows what is drawn,
  not the transparent frame, and it may slide partly off canvas.
- **Checking:** `preview_frame` returns the composited timeline as a JPEG, without zoom and cursor effects.
- **Editing:** `update_motion` merges the fields it gets into the saved `MotionSource` and re-renders, keeping time and
  placement. Motions made before sidecars existed need the full `html` or a `template`.
- **Files:** deleting or updating a clip keeps the old video so undo works. `RenderedAssets.removeUnused` clears videos no
  clip uses when a project first opens, once they are an hour old. Only names shaped `motion-<8 hex>.mov` qualify:
  imported files keep their names.

## Cost (M-series, debug build)

4 s at 30 fps: 720p ≈ 1.3 s, 1080p ≈ 1.9 s (about 16 ms per frame), ~250 KB per clip. Output is capped at 1440p; a simple scene at 2560×1068 took 12% longer than 1920×800.
`takeSnapshot` takes its width in points: asking for the pixel width returned 2x frames on a retina Mac and cost
3.7x the time (58 ms per frame), so the width is divided by the window's backing scale.

## Limits

- Each step (load, seek, paint) has 15 s (`stepTimeout`); a stuck page fails the render and its web process goes with it.
- A duration that is not finite, or past 3600 frames, is rejected.
- Only the in-app MCP server renders (it needs a window server). The standalone `cameraman-mcp` does not list
  `add_motion`. Clients must connect to the in-app server (Settings → Developer).
- `MotionRenderer` is `@MainActor` and uses WebKit: an exception to "engine code is UI-free".
- A baked clip is not re-editable as code. To change the text, delete the clip and add it again.
- Embedded `<video>`/`<audio>`/canvas libraries that own their clock are not seekable (same limit as HyperFrames).
