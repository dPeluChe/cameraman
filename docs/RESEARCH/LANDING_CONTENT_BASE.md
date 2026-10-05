# Landing content base

> Draft for when the landing is decided (it lives in `cameraman-landing`, currently a one-page React app). Derived from the Smooth Recorder analysis in `COMPETITOR_SMOOTH_RECORDER.md`. Nothing here is validated with keyword volumes or user research: treat keywords as hypotheses to test with a tool.

## Positioning

Do not copy "polish without editing"; that is their ground. Our defensible claims, all true today:

1. **Edit videos by talking to an AI agent.** Cameraman exposes 37 editing tools over MCP (Claude Code, Cursor, Codex). Say what it does: "cut the dead air", "add an arrow at 0:12", "export for Shorts".
2. **Open source, free, local.** MIT, no account, no license key, recordings stay on your Mac.
3. **A real timeline, not a one-shot effect.** Screen, camera and audio stay separate tracks; import your own footage; merge projects; share a `.cameramanproject`.
4. **Phone to Mac.** The iOS companion captures takes that become the same kind of project.

One-line options (pick one, test the others):

- "The open-source screen recorder your AI agent can edit."
- "Record on your Mac. Edit by asking."
- "Screen recording with auto-zoom, on-device captions and an editing API for agents."

## Page structure (copy the *pattern*, not the words)

| URL | Purpose | Target query (hypothesis) |
|---|---|---|
| `/` | Positioning, 3 proof points, install | open source screen recorder mac |
| `/features` | Full feature list grouped like theirs (Capture, Recording, Agents, Library) | screen recorder with auto zoom mac |
| `/mcp` | How agents edit video: tool list, a 60-second demo, config snippet | mcp video editing, edit video with claude |
| `/alternatives/screen-studio` | Honest comparison, 1- and 3-year cost, "where Screen Studio is better" | screen studio alternative |
| `/alternatives/smooth-recorder` | Same format | smooth recorder alternative |
| `/alternatives/{kap,obs,cleanshot-x,loom}` | Same format | loom alternative mac, kap alternative |
| `/blog/...` | Long-tail how-tos (below) | see list |
| `/download`, `/privacy`, `/support` | Trust and conversion | |

Rules from what worked for them: dated sources on every comparison, a visible "we make Cameraman, weigh this accordingly" line, state where the competitor is better, add a FAQ, show cost over 3 years only with sourced prices, keep a "last updated" date and actually update it.

## Comparison table (home page version)

Keep only claims we can show. Candidate rows, with the honest answer for us:

| | Cameraman | Screen Studio | Smooth Recorder |
|---|---|---|---|
| Price | Free, open source | subscription (verify) | $9 early access (verify) |
| Auto-zoom on clicks | yes | yes | yes |
| Smooth cursor | yes | yes | yes |
| On-device captions | yes | verify | yes |
| Edit with AI agents (MCP) | **yes** | no (verify) | no (verify) |
| Open source | **yes** | no | no |
| Multi-track timeline | **yes** | verify | verify |
| Cut by transcript | not yet | verify | **yes** |
| Redact secrets | not yet | verify | **yes** |
| Screenshots | no | no | **yes** |
| iOS companion | **yes** | no | no |

Mark every competitor cell "verify" until checked on their own site, and date the table. Showing our own gaps ("not yet") is what makes the rest credible.

## Blog topics (hypotheses; pattern from their sitemap)

Each: key takeaways at the top, a comparison table, an FAQ, last-updated date.

1. How to zoom in on a screen recording (manual and auto-zoom), our manual zoom keyframes as the example.
2. How to record a bug report video that developers will watch.
3. How to make a product demo video with a screen recorder.
4. Best open-source screen recorders for Mac.
5. Screen Studio alternatives for Mac (2026), with us in it and labelled as ours.
6. How to edit a screen recording with Claude (MCP walkthrough): our unique angle, little competition expected.
7. How to remove silences and filler words from a screen recording (pairs with the cut-by-transcript feature once built).
8. How to record a GIF on Mac for a README.

## Technical SEO checklist for the landing

- [ ] Real URLs for sections that deserve to rank; drop the `#anchor` entries from `sitemap.xml`.
- [ ] Per-page `<title>` (about 50-60 characters), meta description (about 150-155), canonical, Open Graph and **twitter tags that match the page** (their weak spot).
- [ ] 1200x630 `og:image` per page; today it is the 1024x1024 app icon.
- [ ] Prerender or statically generate pages; today it is a client-rendered Vite app.
- [ ] Keep `SoftwareApplication` JSON-LD; add `FAQPage` on pages with a FAQ and `Article` on posts.
- [ ] `lastmod` in the sitemap, and keep it truthful.
- [ ] Submit the sitemap in Google Search Console and Bing Webmaster Tools; read real queries before writing more posts.
- [ ] One source of truth for price and version so pages never disagree (they list two launch prices).

## Open decisions

- Price and license story for the landing (free and open source vs a paid, signed build).
- Whether the Mac App Store build is mentioned (it will not include the MCP helper; the in-app server still works there).
- Who writes and maintains comparison pages, since their value is freshness.
