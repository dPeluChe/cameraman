# Motion graphics

Code-built animations (a name card, a stat that counts up, a bar chart) rendered to a transparent video and laid
over the footage as an ordinary clip. The agent reads the transcript (`get_captions`), picks the moments and calls
`add_motion`; the result is a clip on its own `Motion` track, so every existing edit (`edit_clip`, `delete_clip`,
opacity, adjustments, position) works on it.

## Pipeline

```
add_motion (MCP, in-app server only)
  → MotionTemplate.html(...) or custom html
  → MotionRenderer: WKWebView off screen, seek(t) → snapshot → HEVC with alpha .mov   (project assets/)
  → EditorModel.importVideoClip(position:)  → video overlay track
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
the duration is the longest finite animation (or `<meta name="motion-duration" content="4">`). The page background
must stay transparent. Rules for authors: no `Date.now`, no unseeded `Math.random`, no network, text in `vh`/`vw`.
Relative assets need `MotionRenderOptions.assetsDirectory` (the page is then loaded from a file URL).

## Templates (`MotionTemplate`)

| template | needs | notes |
|---|---|---|
| `lower_third` | title, subtitle? | name card, bottom left |
| `title` | title, subtitle? | centered |
| `stat` | value (`42`, `42%`, `$1.2M`), title? | counts up through `__hf` |
| `bar_chart` | labels[] + values[] (same length, ≤ 12), title? | bars grow staggered |

All take `color` (#RRGGBB) and `duration` (default 4 s); they animate in, hold and animate out, ending exactly at
`duration`. Text is HTML-escaped, colors are validated, `stat` values go into the page as JSON strings.

## Cost (M-series, debug build)

4 s at 30 fps: 720p ≈ 3.5 s, 1080p ≈ 7 s (about 58 ms per frame), ~250 KB per clip. Output is capped at 1080p.

## Limits

- Only the in-app MCP server renders (it needs a window server). The standalone `cameraman-mcp` answers with an
  explanation. Clients must connect to the in-app server (Preferences → Integrations).
- `MotionRenderer` is `@MainActor` and uses WebKit: an exception to "engine code is UI-free".
- A baked clip is not re-editable as code. To change the text, delete the clip and add it again.
- Embedded `<video>`/`<audio>`/canvas libraries that own their clock are not seekable (same limit as HyperFrames).
