# Tareas Completadas — Abril 2026 (Sesion 7: Full-Stack Per-Segment + Auto-Zoom)

> Fecha: 2026-04-02
> Camera border, per-segment camera/audio funcional en preview+export, telemetry recording, autosave, auto-zoom rendering.

---

## R1: Camera Border en PiP

- [x] `CameraPosition.borderWidth` (0-8px) + `borderColor` (hex) con decoder backward-compatible
- [x] Compositor: `renderCameraBorder()` via CGPath stroke (circle/roundedRect/capsule/rectangle)
- [x] Border cache: evita CGContext allocation per frame (~240MB/s savings en 1080p)
- [x] UI: slider + 10 color presets en PiPConfigurationView
- [x] `PiPLayoutHelper` preserva border al move/resize/preset

## R2: Per-Segment Camera — Funcional End-to-End

- [x] Auto-create override al drag (sin boton "Custom" extra)
- [x] `PiPConfigurationView` + `PiPCanvasEditor` segment-aware con routing unificado `updateCamera()`
- [x] `selectedSegmentId` promovido a `ProjectEditorViewModel` (shared timeline ↔ sidebar)
- [x] Indicador visual: naranja "drag to customize" / verde "custom"
- [x] Instrucciones contiguas en compositor (prev.end = next.start) — fix de video negro en splits
- [x] Export usa per-segment instructions con visual effects (era una sola instruccion global)

## R3: Per-Segment Audio

- [x] `Segment.volume: Double?` (0-3x) + `Segment.audioMuted: Bool?` en modelo
- [x] `AudioMixBuilder.applySegmentVolumes()` con `setVolumeRamp(fromStartVolume:toEndVolume:timeRange:)`
- [x] `lastAudioMuteState` preservado en PreviewEngine (no se pierde al rebuild)
- [x] UI: mute button + volume slider + reset en SegmentInspectorBar
- [x] Split propaga volume/audioMuted

## R4: Telemetry Recording

- [x] `TelemetryRecorder` integrado en `Recorder.startRecording()` / `stopRecording()`
- [x] `RecordingConfiguration.captureTelemetry = true` default
- [x] `RecordingResult.telemetryPath` nuevo campo
- [x] `moveRecordingFiles()` copia cursor.jsonl al proyecto con TOCTOU fix
- [x] Habilita "Suggest Zooms" para nuevas grabaciones

## R5: Autosave

- [x] `ProjectEditor.scheduleAutosave()` con 1s debounce
- [x] Llamado desde `mutateSegment()`, `updateCameraPosition()`, `updatePublishedProject()`
- [x] Persiste via `ProjectLibrary.shared.updateProject()`

## R6: Auto-Zoom Rendering

- [x] `MaskedVideoCompositor.activeZoomPlan` (static) — zoom plan accesible al compositor
- [x] Zoom transform per-frame: scale around focus point con Y-flip para CIImage coords
- [x] Auto-show suggestions al abrir proyecto con telemetry
- [x] Auto-apply zoom plan al generar suggestions
- [x] Threshold tuning: minClicksPerWindow 2→1, minMovementDistance 50→20px, includeRightClicks, DwellDetector mas sensible

## R7: Code Quality (Simplify)

- [x] `mutateSegment()` generico reemplaza 4x boilerplate (speed/volume/mute/camera)
- [x] Missing undo en updateSegmentVolume/AudioMuted — ahora todos registran undo
- [x] Border cache evita CGContext per-frame
- [x] `cgColor(from:)` reutiliza `ciColor(from:)` (elimina parsing duplicado)
- [x] TOCTOU fix en telemetry file move
- [x] Repeated `audioMuted ?? false` extraido a local let

## R8: Deprecation + Compatibility Fixes

- [x] 11 `onChange(of:perform:)` migrados a `onChange(of:) { _, newValue in }` (macOS 14+)
- [x] TimelineView body split en sub-views (fix type-checker timeout)
- [x] TeleprompterWindow concurrency fix (Timer closures con Task { @MainActor })
- [x] BackgroundControlsView+Helpers: `.gradient` case agregado
- [x] `importantClicks` → `importantClickCount` (argument label fix)
- [x] `let` → `var` para parseResult/events en zoom generation
