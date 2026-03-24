# Tareas Completadas — Marzo 2026 (Sesion 2)

> Fecha: 2026-03-24
> Timeline funcional, track mute, media items, tests reparados.

---

## A1: Playhead <-> Player Sync Bidireccional

- [x] PreviewPlayerViewModel compartido entre PreviewPlayerView y TimelineView
- [x] Click/drag en timeline posiciona el video (seek frame-accurate)
- [x] Play video mueve el playhead en el timeline en tiempo real
- [x] Scrubbing gestionado: drag pausa, soltar resume playback
- [x] Eliminado playheadTime duplicado de ProjectEditorViewModel

## A2: Track Mute Real (Audio + Video)

- [x] AudioMixBuilder (nuevo archivo EngineKit) — construye AVMutableAudioMix por track
- [x] Mute System Audio / Mic Audio silencia audio en preview via AVMutableAudioMix
- [x] Mute Screen oculta pantalla (opacity 0 o fondo negro en compositor)
- [x] Mute Camera oculta PiP/side-by-side de la camara
- [x] Camera fullscreen cuando screen esta muteado (con mascara si aplica)
- [x] MaskedVideoCompositor soporta screenMuted flag (fondo negro)
- [x] Export respeta mute state: audioMuteState + videoMuteState en ExportOptions
- [x] mutedTracks subido de @State local a @Binding compartido
- [x] Change guard (lastMuteState) para evitar Tasks redundantes

## A3: MediaItem Data Model

- [x] Project+MediaItem.swift (nuevo): MediaItem, MediaItemType, MediaPosition
- [x] Project.mediaItems con backward compat (decodeIfPresent, default [])
- [x] Custom init(from decoder:) en Project para schema migration
- [x] EditorModel CRUD: addMediaItem, removeMediaItem, updateMediaItem
- [x] EditorModelTypes: mediaItemNotFound error, mediaItemAdded result info
- [x] ProjectEditor+Extensions wrappers con undo/redo

## A4: Timeline UI para Assets + Composition

- [x] TimelineTrackKind: nuevos .additionalAudio y .imageOverlay
- [x] TimelineTrack soporta mediaItems ademas de segments
- [x] TimelineTrackBuilder genera tracks para media items importados
- [x] Media items se renderizan como clips con nombre en timeline
- [x] Boton "Import" en toolbar del timeline (fileImporter)
- [x] Import copia archivo a project/assets/, detecta duracion, crea MediaItem
- [x] CompositionBuilder: buildAdditionalAudioTracks() para audio importado
- [x] AudioMixBuilder soporta volume/mute de tracks adicionales
- [x] Import async (no bloquea main thread)

## B: Estabilidad y Tests

- [x] 8 archivos de tests reparados para nueva API de Project init
- [x] OverlayEditViewTests, EditorModelTests, TranscriptionEngineTests, etc.
- [x] Core tests pasan: EditorModel (73), OverlayEdit (42), CanvasLayout (40)

## Simplify / Code Review

- [x] Removido overload muerto de AudioMixBuilder.buildAudioMix
- [x] Removidos 6 debug prints [MUTE-DEBUG]
- [x] Set<String> reemplazado con Set<VideoTrackID> enum (type-safe)
- [x] Dual Tasks combinados en single Task en applyTrackMutes
- [x] File import movido a async Task (no bloquea main thread)
- [x] fileImporter allowed types sincronizados con validacion
- [x] lastMuteState reset en reset() para evitar stale state
- [x] mediaItemNotFound error type (en vez de segmentNotFound)

---

### Archivos nuevos
- `EngineKit/Sources/EngineKit/Models/Project+MediaItem.swift`
- `EngineKit/Sources/EngineKit/Shared/AudioMixBuilder.swift`

### Stats
- 32 archivos modificados, +800 / -319 lineas
