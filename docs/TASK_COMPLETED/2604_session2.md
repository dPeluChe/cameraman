# Tareas Completadas — Abril 2026 (Sesión 2)

> Periodo: 2026-04-22
> Branch: `refactor/phase1-architecture`
> Foco: bugs de overlays/zoom, Phase 1 arquitectura — split de archivos grandes + reducción de boilerplate.

---

## Fix: Overlays — timing, cache y frame refresh (474a4fd)

- [x] **Overlay timing en t=0** — `RightPanel` pasaba `.constant(playheadTime)` con tiempo desactualizado. `OverlayEditorView` ahora lee `currentTime` vía `Binding` live desde `playerViewModel`.
- [x] **Edits no se reflejaban en frame visible** — tras `rebuildVideoComposition`, AVFoundation no re-renderiza el frame actual. Ahora se hace seek al tiempo corriente cuando el player está pausado.
- [x] **Cache key incompleta** — `cachedOverlayKey` ignoraba `strokeWidth`, `shadow`, `text`, `fontSize`, `fontColor`, `bgColor`. Todos incluidos ahora.

---

## Perf: Overlay/Zoom — debounce + stale plan + logs (f6d0844)

- [x] Preview refresh debounce 500ms → 150ms (overlays se ven ~3× más rápido).
- [x] `reset()` en `PreviewEngine` limpia `pendingZoomPlan` — evita que plan de proyecto anterior se aplique al proyecto siguiente.
- [x] Log "no activeZoomPlan" eliminado (ruido en playback normal). Log "applyZoom" detrás de `#if DEBUG` (eliminaba Tasks per-second en release).

---

## Phase 1 — Split archivos >500 LOC (4d8ac63)

8 archivos excedían 500 LOC; divididos en 14 archivos, todos bajo 500 LOC:

- [x] `CompositionBuilder+AudioTracks.swift` — audio track building extraído (CompositionBuilder 678→476)
- [x] `ExportOverlayRenderer.swift` (441 LOC nuevo) — image/shape overlay burn-in extraído de ExportCaptionRenderer (669→235)
- [x] `PreviewEngine+Playback.swift` (190 LOC) — playback control/time observation/proxy extraídos (PreviewEngine 585→343)
- [x] `PreviewEngine+Player.swift` (150 LOC) — player creation/mutes/audio mix extraídos de PreviewComposition (504→364)
- [x] `ProjectStore+Create.swift` (249 LOC) — createProject overloads y addTake extraídos (ProjectStore 533→277)
- [x] `ProxyGenerator+Helpers.swift` (98 LOC) — sizing/disk/CGContext helpers extraídos (ProxyGenerator 515→401)
- [x] `TimelineView+MediaMarkers.swift` (172 LOC) — waveform/zoom markers/overlay track row extraídos de TimelineView+Subviews (500→336)

---

## Phase 1 — Reducción de boilerplate en archivos 400–490 LOC (ac842eb)

- [x] **`MicAudioRecorder.swift`** (141 LOC nuevo) — clase extraída de `Recorder.swift` (460→322). Encapsula AVAudioEngine tap: init, startRecording/attemptStart/startWithEngine, stop/pause/resume.
- [x] **`mutateSegment()` en `ZoomSectionController`** — helper `(inout Segment) -> Void` colapsa 4 métodos con patrón guard/mutate/save idéntico (446→410).
- [x] **`applyCanvasUpdate()` en `ProjectEditor`** — helper `(inout Project) throws -> Void` + `saveAfter:` unifica 7 métodos canvas con undo snapshot + autosave (439→332).
- [x] **`zoomState()` en `PreviewRenderer`** — extrae `(level, focusX, focusY)` deduplicando la math de focus-point entre `applyZoom` y `applyZoomTransform`; `canvasSize` cancela matemáticamente (425→375).
- [x] Dead code en `HotkeyManager`: alias `OptionBits` sin uso + función `removeEventHandler()` vacía eliminados (463→455).

---

## Resultado

- Build: 0 errors, 0 warnings.
- Todos los cambios commiteados en 4 commits sobre `refactor/phase1-architecture`.
- LOC totales extraídos en esta sesión: ~1800 LOC movidos a archivos enfocados.
