# Competitor: Smooth Recorder

> Source: smoothrecorder.com (home, /features, /alternatives/screen-studio, one blog post, sitemap, robots), read 2026-10-04.
> Everything below about *their* product is what **their site claims**; we have not used the app. Their comparison tables are marketing, self-dated "September 2026". Nothing here comes from Search Console or a keyword tool, so SEO notes are structural, not performance data.

## What it is

A native macOS (15+) recorder in SwiftUI/AppKit that sells "record once, edited when you stop": automatic zooms from clicks, smooth cursor, captions, plus a full screenshot product (editor, scrolling capture, OCR copy-text, redaction). Early access **$9 one time** (first 100 buyers), "$69 at launch" on the home page and "$19 at launch" in a blog post (their own pages disagree). Direct competitor of Screen Studio, positioned on price (Screen Studio $29/mo or $108/yr per their page) and on being native vs Electron.

## Where we overlap

| Capability | Smooth Recorder | Cameraman |
|---|---|---|
| Auto-zoom from clicks, editable | yes (Smooth/Snappy/Drift/Cut styles) | yes, plus manual zoom keyframes |
| Smooth cursor + click ripple | yes (up to 4x size) | yes (synthetic cursor, ripples, hide-cursor) |
| On-device captions | yes, word-by-word highlight | yes (on-device transcription) |
| Camera bubble / split | yes, adjustable after recording | yes (PiP, side-by-side layouts) |
| Annotations | text, arrows, boxes, spotlight, blur | arrow, rect, line, text, image, GIF overlays; `gaussianBlur` exists only as a whole-layer, time-ranged effect (no region) |
| Trim / split / speed | speed up to 8x | trim, split, per-clip speed |
| Backgrounds | 76 wallpapers, padding/corners/shadow | color, image, blur, padding, corners, shadow |
| Export | MP4/MOV, H.264/HEVC, 30/60 fps, GIF | MP4, HEVC, GIF presets, portrait |
| Native, on-device | yes | yes |

## What they have that we do not

1. **Cut by editing the transcript**: delete words or sentences, one-click filler-word and long-pause removal. Their headline differentiator.
2. **Smart Redact**: finds emails, phone/card numbers, API keys, faces, on-device, and blurs them.
3. **Keys on screen** (we have `keys.jsonl` capture, no overlay yet).
4. **Reframe export** to 16:9, 9:16, 1:1, 4:5 from one recording.
5. **3D zoom angles** (Left/Right/Lean/Float) and 3D screenshot tilt.
6. **Screenshots as a product**: one hotkey, editor, frames, social sizes, "Motion" (screenshot to MP4), scrolling capture, OCR copy-text, GIF capture.
7. **Mac integration**: Library in the notch, menu bar/Dock menus, Shortcuts and Siri actions, self-timer.
8. **A price story**: $9 lifetime vs subscriptions, with a worked 3-year cost table.

## What we have that they do not (verify before using in copy)

- **Agent editing over MCP**: 37 tools, an in-app server, the editor freezes while an agent works. Not on their feature list.
- **Open source (MIT)**, auditable, no license key.
- **Multi-track project model**: screen, camera and audio kept as separate tracks, imported media on their own tracks, merge projects, portable `.cameramanproject` bundles.
- **iOS companion** (Cameraman Takes) that feeds the same kind of project. They are Mac only.
- Older macOS floor (13 vs their 15).

## Feature candidates for Cameraman

Ordered by fit with our audience (developers, people making demos) over effort. "Backlog" = already in `TASK_TODO.md`.

| # | Candidate | Why | Effort | Notes |
|---|---|---|---|---|
| 1 | **Cut by transcript + filler removal** | Their strongest hook; we already transcribe and have ripple `delete_range` and silence detection | Medium | Also an MCP tool: an agent can "remove every um". Our edge over a UI-only version |
| 2 | **Smart Redact / blur regions** | Developers record terminals and dashboards full of secrets; regex for keys plus Vision text boxes | Medium | Backlog: "Blur regions in video" phase 2. Raise priority. **Building block exists**: the `gaussianBlur` adjustment (radius, `start`/`end`) on a layer. Missing: a region (x, y, w, h params in `AdjustmentRenderer`) and the detection (Vision text boxes plus regex) that creates time-ranged adjustments |
| 3 | **Keys on screen overlay** | Expected in dev tutorials | Small | Backlog: keystroke overlay; data already captured |
| 4 | **Reframe presets 1:1 and 4:5** (and manual 9:16 crop) | Social export from one recording | Small | Backlog: auto reframe; start with presets |
| 5 | **More backgrounds** (a curated pack) | Cheap perceived polish | Small | Content work, not engine work |
| 6 | **Self-timer and menu bar item** | Basic polish | Small | |
| 7 | **App Intents (Shortcuts)**: start/stop recording | Automation; fits the agent story | Medium | Also helps if we ship a sandboxed build |
| 8 | **OCR "copy text from screen"** | Cheap with Vision, but it is the screenshot product's feature | Small | Only if we widen scope |
| 9 | **3D zoom angles** | Visual novelty | Medium | Low priority |
| - | **Screenshot editor, scrolling capture, Motion** | A different product | Large | Recommend **not** chasing; stay video-first and say so in positioning |

## SEO: what they do (from the pages above)

Strengths worth copying as a *pattern*:

- **31 indexable URLs**, not a single page: home, `/features`, `/alternatives` plus **8 per-competitor pages** (`/alternatives/screen-studio`, `cleanshot-x`, `cap`, `screen-charm`, `focusee`, `tella`, `camtasia`, `loom`), a blog with 4 categories and 11 posts, support, privacy, terms.
- **Intent-matched titles**: "Screen Studio Alternative for Mac (2026): Smooth Recorder vs Screen Studio".
- **Comparison pages with real substance**: price table over 1 and 3 years, "where the competitor is better" (it admits it), "we make Smooth Recorder, weigh this accordingly", dated sources, a FAQ.
- **Blog as long-tail**: how-to posts around their features ("how to zoom in on a screen recording", "how to record a GIF on Mac", "how to record a bug report video"), each with key takeaways, a comparison table, an FAQ and an author/updated note.
- Clean technicals: `canonical` on every page, `robots.txt` allowing all but `/api/` and `/thanks`, a sitemap, Open Graph per page with a generated 1200x630 image, `article` metadata (published time, section, tags), `published_date`.

Weaknesses I could verify:

- **Meta descriptions are long**: home 173, features 181 characters (search results usually truncate near 155-160). Alternatives page is 156.
- **Twitter card tags are not page-specific**: `/features` and `/alternatives/*` reuse the home page's twitter title and description.
- **Inconsistent price claim** ($69 vs $19 at launch) across pages.
- Sitemap has no `lastmod`.
- Not checkable here: structured data (JSON-LD was not exposed by the fetch), Core Web Vitals, backlinks, rankings.

## SEO: how our landing compares (labs-cameraman-landing, current main)

- **One page.** `public/sitemap.xml` lists `https://cameraman.dev/#features`-style anchors; search engines ignore fragments, so those entries add nothing.
- Title (58) and description (146) are within limits; canonical, Open Graph, `SoftwareApplication` JSON-LD and a twitter card exist. Good base.
- `og:image` is the 1024x1024 app icon, not a 1200x630 card.
- A Vite React app: content is rendered client-side. Not fatal, but prerendering or static generation would make crawling more reliable. Not measured.
- No alternatives/comparison pages, no blog, no per-page titles. A comparison table exists inside the home page (vs Screen Studio, Kap, OBS) but is not indexable on its own.

See `LANDING_CONTENT_BASE.md` for what to build.
