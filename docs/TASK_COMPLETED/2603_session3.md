# Tareas Completadas — Marzo 2026 (Sesion 3)

> Fecha: 2026-03-25
> Fixes de grabacion, UX del selector de area, volume sliders, timeline fill.

---

## B1: Fixes de Grabacion

- [x] **Mic audio error -50 (paramErr)**: `AVAudioFile` settings alineados con el formato nativo del input node (`recordingFormat.channelCount` / `recordingFormat.sampleRate`). Forzar 2ch/48kHz causaba mismatch con el tap.
- [x] **Ventana duplicada al abrir proyecto**: `WindowGroup` crea instancias nuevas en cada `openWindow(id:)`. Cambiado a `Window` (single-instance) en `CameramanApp.swift` para el editor principal.
- [x] **Proyecto no auto-seleccionado tras grabacion**: Race condition por `Task.yield()` antes de `selectedItem`. Fijado asignando `viewModel.selectedItem = .project(projectId)` sincrono antes del `Task { loadProjects() }`.
- [x] **Microfono muy bajo**: Default `micAudioVolume` subido de 1.0x a 2.5x en `AudioMixBuilder.TrackMuteState`.

## B2: Area Selector UX

- [x] **NSPanel no podia ser key window**: Creado `KeyablePanel: NSPanel` con `override var canBecomeKey: Bool { true }`. Habilita keyboard shortcuts (Esc para cancelar) en el overlay.
- [x] **Confirmar con doble click**: Reemplazado boton "Confirm" por `.onTapGesture(count: 2)`. Instruction bar cambia de texto ("Drag to select" → "Double-click to confirm") segun haya seleccion.
- [x] **Linea roja visible en video grabado**: `AreaHighlightController` (NSWindow overlay) no tenia `sharingType = .none`. ScreenCaptureKit lo capturaba. Fijado.
- [x] **Highlight persistia al detener grabacion**: `AreaHighlightController.shared.hide()` nunca se llamaba al detener. Ahora se llama al inicio de `stopAndCleanup()`.
- [x] **Llamada redundante a hide()**: `captureAreaRow` llamaba `hide()` antes de `show()`, pero `show()` ya llama `hide()` internamente. Eliminada la llamada redundante.

## B3: Playback Improvements

- [x] **Velocidad de reproduccion no se aplicaba en vivo**: `@Published var playbackRate` no tenia `didSet`. Agregado `avPlayer?.rate = Float(playbackRate.rawValue)` en `didSet` con guard `isPlaying`.
- [x] **Volume sliders por track (system audio + mic audio)**:
    - `PreviewPlayerViewModel`: `systemAudioVolume` y `micAudioVolume` como `@Published var` con `didSet { reapplyAudioMix() }`.
    - `applyTrackMutes` pasa los volumenes actuales a `AudioMixBuilder.TrackMuteState`.
    - `reapplyAudioMix()` reconstruye el estado desde `lastMuteState` (solo audio, sin llamar `applyVideoMutes`).
    - `TimelineTrackRow`: parametro `volumeBinding: Binding<Float>?`. Slider compacto (`.controlSize(.mini)`, 48px, rango 0–3x) en el label area para tracks de audio.
    - Iconos diferenciados: `speaker.wave.2`/`speaker.slash` para audio, `eye`/`eye.slash` para video.
    - `labelWidth` 120 → 160 para acomodar el slider.

## B4: Timeline Fill

- [x] **Segmentos no llenaban el espacio disponible**: `pixelsPerSecond` era fijo (40). Ahora se calcula `basePPS = max(40, (availableWidth - labelWidth) / duration)` en `body`, usando `@State var availableWidth` medido con `GeometryReader` en background del ScrollView.
- [x] **Warning "Publishing changes within view updates"**: `onAppear` del GeometryReader wrappea el set de estado en `Task { @MainActor in ... }` para diferir fuera del render pass.

## B5: Refactors / Simplify

- [x] `WindowID` enum extraido a `RecordingControlView.swift` — elimina string literals "main-editor" y "recording-controls" dispersos.
- [x] `isAudioTrack: Bool` extraido como computed property en `TimelineTrackKind` — elimina `self == .systemAudio || self == .micAudio` inline en 3 sitios.
- [x] `lastMutedTracks` eliminado de `PreviewPlayerViewModel` — era redundante con `lastMuteState`. `reapplyAudioMix()` ahora reconstruye desde `lastMuteState` y aplica solo audio, evitando llamadas innecesarias a `applyVideoMutes` al mover sliders de volumen.
