# Performance and memory audit (2026-10-05)

Source: code reading only, nothing profiled. Impact is estimated. Paths under `EngineKit/Sources/EngineKit` (EK) and `App/Sources/Cameraman` (App).

| # | Impact | Finding | Fix |
|---|--------|---------|-----|
| 1 | High | `EK/Capture/CaptureSessionManager.swift:178-198` spawns an unbounded `Task` per frame; no `queueDepth`; frames can reorder | Append synchronously on the sample queue, set `queueDepth` 5-6 |
| 2 | High | `EK/Shared/CompositorRenderers.swift:39-57`, `CursorRenderer.swift:33-47`: full-canvas CPU bitmap per frame (about 33 MB at 4K) | Cache mask `CIImage`; draw cursor in a small rect |
| 3 | High | `App/PreviewPlayerViewModel.swift:194`: cursor telemetry re-parsed on every edit | Cache plan by path, mtime, geometry |
| 4 | High | `App/TimelineView+Subviews.swift:96-117`: thumbnail strip not virtualized (about 4,200 views for 10 min zoomed in) | Draw visible range or one `Canvas`; binary-search thumbnails |
| 5 | High | `PreviewPlayerViewModel.swift:315`: `currentTime` at 20 Hz invalidates whole timeline; track builder runs twice per tick | Separate playhead observable; memoize tracks |
| 6 | Med-High | `EK/Export/GIFExportSession.swift:245,294,392`: `CIContext` per frame, all frames in memory | One context, stream frames to the destination |
| 7 | Med-High | `VideoExportSession+Stages.swift:~140-160`: shapes/subtitles possibly drawn by compositor and by a Core Animation tool | Pick one path (unconfirmed) |
| 8 | Med | `MaskedVideoCompositor.swift:419`: background blur at full resolution | Blur a downscaled copy |
| 9 | Med | `PreviewComposition.swift:43`: preview at 60 fps and full canvas | Use source fps, optional lower render size |
| 10 | Med | `PreviewEngine.swift:310-331`: compositor and `CIContext` rebuilt on each edit | Static shared `CIContext` and caches |
| 11 | Med | `ThumbnailCache.swift:268-281`: asset and generator per thumbnail, PNG round-trip, FIFO not LRU | One generator, batch, JPEG/CGImage |
| 12 | Med | `ThumbnailCache.swift:317-343`: waveform assumes 44.1 kHz mono, covers about 45% of the file | Read real format, scale to full duration |
| 13 | Med | `WhisperKitTranscriber.swift:80`: model loaded per job | Cache by model, unload after idle |
| 14 | Low-Med | `ProjectEditor.project` republishes the whole `Project` to about 25 views | Pass slices, split UI flags |
| 15 | Low | Per-frame key strings, `CIFilter` creation, color space mismatch | Precompute, cache, set `CIContext` color spaces |

Fine as is: camera capture append path, export memory (AVAssetExportSession streams), weak self in observers/timers.

Suggested order: 1, 5, 4, 3, 2, then 6 and 13.
