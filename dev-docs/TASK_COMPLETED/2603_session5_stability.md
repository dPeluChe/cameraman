# Tareas Completadas — Marzo 2026 (Sesion 5: Stability + Features)

> Fecha: 2026-03-31
> Bugs, estabilidad, macOS 13 compat, features de editor, polish visual.

---

## S1: Bugs Corregidos

- [x] **B1 — Mic audio race condition**: MicAudioRecorder ahora valida formato AVAudioEngine (sampleRate > 0, channelCount > 0) antes de iniciar. Si invalido, retry automatico con 300ms delay y nueva instancia de AVAudioEngine. Eliminado delay incondicional de 150ms tras /simplify.
- [x] **B2 — "Publishing changes from within view updates"**: BackgroundControlsView.updateSelectedColor() wrapeado con `Task { @MainActor in }` en onAppear y onChange.

## S2: Calidad y Estabilidad

- [x] **Q1 — Swift 6 concurrency**: EngineKit compila con `-strict-concurrency=complete` sin warnings.
- [x] **Q3 — SHA256 real**: CryptoKit SHA256 con streaming (FileHandle + 64KB chunks, memoria constante). `fileSize` real via FileManager attributes. 8 placeholders eliminados en ProjectStore + ProjectStoreHelpers.
- [x] **Q4 — onChange macOS 13**: 12 instancias de API macOS 14 `{ _, newValue in }` convertidas a macOS 13 `{ newValue in }` en 11 archivos.
- [x] **Timer intervals**: Export (0.25s) y KeystrokeRecorder (0.25s) para polling background. Recording elapsed time revertido a 0.1s para UX fluido (/simplify).
- [x] **ExportViewModel timer cleanup**: deinit invalida progressUpdateTimer si view se cierra durante export.
- [x] **Dimensiones reales**: Screen + camera tracks ahora usan `detectVideoDimensions()` en vez de hardcoded 2880x1800 / 1280x720.

## S3: Features del Editor

- [x] **I3 — Export preset 4K HEVC**: `ExportPreset.ultra4kHevc` (3840x2160, 60fps, 30Mbps HEVC, 256kbps audio). Agregado a availablePresets.
- [x] **F8 — Duplicar proyecto**: `ProjectStore.duplicateProject()` deep copy + nuevo ID + nombre "(Copy)". Context menu "Duplicate" en sidebar + auto-seleccion del clon.
- [x] **F9 — Export transcript**: `exportCaptions(format:)` implementado con soporte SRT, VTT, y TXT. NSSavePanel para guardar. Timestamps formateados.

## S4: Polish Visual (Modelo + UI)

- [x] **V1 — Border radius + shadow**: `canvas.videoCornerRadius` (0-16px) y `canvas.videoShadowIntensity` (0-1) agregados al modelo con decoder backward-compatible. `VideoEffectsControlsView` (nuevo) con sliders en sidebar.
- [x] **V2 — Background gradients**: `BackgroundType.gradient` + 8 `GradientPreset`s (Sunset, Ocean, Forest, Midnight, Lavender, Ember, Arctic, Slate) + factory `createGradientBackground()`. Tab "Gradient" en BackgroundControlsView con grid de presets y preview de color.
- [x] **V4 — Padding configurable**: `canvas.padding` (0-0.3 fraccion) con slider en VideoEffectsControlsView.

## S5: Project Thumbnails

- [x] **Thumbnail generation**: `ProjectStore.generateThumbnail()` genera JPEG (320x180) del primer frame del screen video al crear proyecto. `listProjects()` detecta `thumbnail.jpg` existente y pasa path a `ProjectSummary.thumbnailPath`.
- [x] La UI ya existia (`ProjectThumbnailView`) — ahora muestra imagen real en vez de placeholder icon.

## Notas

- V1/V2/V4: modelo y UI listos; rendering en MaskedVideoCompositor pendiente (necesita aplicar cornerRadius/shadow/padding/gradient en el frame de video durante preview y export).
- Strict concurrency ya pasa en EngineKit; App module no verificado (requiere Xcode build).
