# Tareas Completadas — Marzo 2026 (Sesion 4: Performance)

> Fecha: 2026-03-30
> Review y fix de los 6 issues criticos de recursos/performance pre-release.

---

## P1: Task Leak en Duration Timers

- [x] **CameraEngine + CaptureSessionManager**: `startDurationTimer()` lanzaba un `Task` fire-and-forget sin handle de cancelacion. Si `stopRecording()` fallaba antes de `markStopped()`, el loop de 100ms corria indefinidamente.
- **Fix**: `durationTimerTask: Task<Void, Never>?` almacenado como propiedad. Loop usa `!Task.isCancelled` como condicion adicional. `stopRecording()` cancela y nilea el task explicitamente.

## P2: Observer Leak en PreviewEngine

- [x] **PreviewEngine.unloadProject()** nileaba el `AVPlayer` sin remover primero el `timeObserverToken`. El periodic time observer seguia activo, leaking cada vez que el usuario cambiaba de proyecto.
- **Fix**: `stopPeriodicTimeObservation()` llamado antes de `self.player = nil` en `unloadProject()`.

## P3: ThumbnailCache sin Eviction

- [x] **ThumbnailCache**: `maxThumbnailCount = 100` existia en config pero nunca se aplicaba. En sesiones largas con scrubbing, el cache crecia sin limite (50-100 MB).
- **Fix**: `thumbnailAccessOrder: [TimeInterval]` trackea el orden de acceso. `insertThumbnail()` registra cada entrada y `evictThumbnailsIfNeeded()` remueve las mas antiguas cuando el cache excede el maximo. Todas las funciones de clear tambien limpian el access order.

## P4: Thumbnail Lookup O(n log n)

- [x] **TimelineView+Subviews `findClosestThumbnail()`**: Hacia `thumbnails.keys.sorted()` (O(n log n)) seguido de `min(by:)` (O(n)) en cada render del timeline — con 50+ thumbnails esto era costoso.
- **Fix**: Reemplazado con un linear scan O(n) simple que trackea el minimo directamente. Elimina la alocacion del array sorted.

## P5: Waveform Rendering en Hot Path

- [x] **TimelineWaveformStrip**: `samplesForSegment()` creaba un `Array(...)` copy del slice en cada render, y `GeometryReader + Path` generaba un arbol de SwiftUI views para cada sample.
- **Fix**: Reemplazado `GeometryReader + Path` con `Canvas { context, size in ... }` que renderiza directamente en un graphics context sin crear SwiftUI subviews. Usa `ArraySlice` (sin copy) via `sampleRange()`.

## P6: Project List Carga Eagerly

- [x] **ProjectStore.listProjects()**: Leia y decodificaba TODOS los `project.json` en cada llamada, sin cache ni paginacion. Con 20+ proyectos el startup era lento.
- **Fix**: `summaryCache: [URL: (modDate: Date, summary: ProjectSummary)]` compara el modification date del archivo. Si no cambio, retorna el cache. Entries de proyectos eliminados se purgan. Cache se invalida automaticamente cuando el archivo se modifica.
- [x] **AppNavigationViewModel.loadProjects()**: Multiples llamadas (refresh + notificaciones) se apilaban.
- **Fix**: Debounce de 500ms — ignora llamadas dentro de ese intervalo.

## P7: Thumbnails/Waveforms Generados Eagerly

- [x] **TimelineView.initializeThumbnailCache()**: Generaba 50 thumbnails + waveforms sincrono al abrir proyecto, bloqueando 2-5s.
- **Fix**: Genera 15 thumbnails iniciales (key frames), luego lanza waveforms + los 35 thumbnails restantes en un `Task(priority: .utility)` background. El proyecto se abre inmediatamente con thumbnails parciales que se completan progresivamente.
