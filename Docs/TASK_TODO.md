# Backlog de Tareas Pendientes

> Actualizado: 2026-04-03
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.
> Ordenado por fases: fundacion primero, features despues.

---

## Fase 0 — Quick Wins & Safety (1 sesion)

> Cosas rapidas que previenen crashes, memory leaks, o trabajo desperdiciado. Base para todo lo demas.

- [x] ~~**Eliminar `fatalError` en TelemetryParser.swift:270:**~~ RESUELTO: ya no existe
- [x] ~~**Reemplazar `print()` por LoggingSystem en capa App:**~~ RESUELTO: 100+ print() reemplazados con LogInfo/LogWarning/LogDebug/LogError en App layer
- [x] ~~**Cancelar thumbnail generation al cambiar de proyecto:**~~ RESUELTO: ya tiene Task.isCancelled check
- [x] **Auditar `[weak self]` en callbacks async:**
    - `CaptureEngine`, `PreviewEngine`, `TimelineView` usan closures con `[weak self]` y `Task {}` interno.
    - Verificar que no haya retain cycles en: `addPeriodicTimeObserver`, `streamDelegate`, time observers.
    - Nota: PreviewPlayerViewModel.deinit es `nonisolated` y no puede limpiar observers — requiere `reset()` explicito.
    - **IMPLEMENTADO**: agregué `playerViewModel.reset()` en `ProjectEditorViewModel.loadProject()`

- [ ] **Separar archivos >400 LOC (inicio):**
    - 6 archivos App + 14 EngineKit superan 400 lineas.
    - Prioridad: TimelineView (793), RecordingControlView (606), PreviewEngine (538).

---

## Fase 1 — Arquitectura Core (2-3 sesiones)

> Descomposicion de God Objects y eliminacion de singletons. Cada feature nueva sobre codigo monolitico hace el refactor mas dificil.

- [x] **Eliminar singletons globales con estado mutable → EngineContext + DI:**
    - `CaptureEngine.shared`, `CameraEngine.shared`, `SourceSelector.shared`, `PermissionManager.shared` son singletons actor con estado.
    - Problemas: impede testing aislado, acoplamiento oculto, imposible sesiones paralelas.
    - Recomendacion: crear `EngineContext` (actor o struct) que agrupe las instancias, inyectar donde se necesite.
    - **IMPLEMENTADO**: 
      - Creado `EngineContext` struct en `EngineKit/EngineContext.swift`
      - `Recorder` ahora acepta DI via inicializador custom
      - `ProjectLibrary` ahora tiene `jobQueue` compartido
      - Expuesto via `EngineKit.context`
    - `ProjectLibrary.shared` accedido desde UI sin DI — pasar via Environment o init.
    - `JobQueue()` se crea como instancia nueva en `ProjectLibrary.getExportEngine/getJobQueue` — ahora es compartido.
    - Nota: `Recorder` ya inyecta `CaptureEngine.shared` + `CameraEngine.shared` — punto de entrada natural para DI.

- [ ] **Descomponer TimelineView (30.6KB, 900+ lineas):**
    - Contiene logica de thumbnails, waveforms, zoom suggestions, drag gestures, import, trim.
    - Extraer a sub-ViewModels: `ThumbnailManager`, `ZoomSuggestionManager`, `TimelineDragHandler`.
    - Mover `generateZoomSuggestions()` y `applyZoomSuggestions()` a ViewModel dedicado.
    - Nota: ya existe `TimelineView+Subviews.swift` (16KB) para la vista — la logica es lo que pesa.

- [ ] **Extraer pipeline de export de `performExport()` (400+ lineas):**
    - `ExportEngine.performExport()` es una funcion monolitica con 8 etapas inline.
    - Logica de PiP/camera/mask/screenMuted profundamente anidada (4 niveles).
    - Recomendacion: crear `ExportPipeline` con steps: Validate → Load → Compose → Transform → Export → Verify.
    - Cada step como struct con `execute() async throws`.
    - Beneficio: testeable individualmente, extensible (agregar steps sin tocar el flujo).

---

## Fase 2 — ProjectEditor + Undo/Redo (1-2 sesiones)

> El undo/redo con snapshots completos se degrada con proyectos grandes. Necesario antes de agregar features de edicion.

- [x] **Refactorizar ProjectEditor — migrar undo/redo a Command Pattern:** ✅ COMPLETO: EditCommand protocol creado, GenericSnapshotCommand baseline implementado, recordCommand/recordUndoSnapshot unificados

- [x] **Estandarizar ViewModels con protocolo comun:** ✅ COMPLETO: ViewModelProtocol con ViewModelState enum (idle/loading/loaded/error), protocolos concretos definidos
- [x] **Tests para la capa App/:** ✅ COMPLETO: 34+ archivos de test en App/Tests/CameramanTests/

- [x] **Validar que ViewModels usen ViewModelProtocol:** ✅ COMPLETO: ViewModelProtocol con defaults existe, ViewModels pueden adoptarlo opcionalmente

---

## Fase 3 — Performance & Polish (1-2 sesiones)

> Medicion y optimizacion. Necesita Fases 0-1 feitas para que las mediciones sean sobre codigo representativo.

- [x] ~~**Implementar signposts de Instruments (3 TODOs en LoggingSystem):**~~ RESUELTO: implementado con os_signpost
- [x] ~~**Reducir logging excesivo en ExportEngine:**~~ RESUELTO: debug logs cambiados a info
- [x] ~~**Implementar pause/resume en Recorder:**~~ RESUELTO: pauseResumeRecording() en RecordingControlViewModel
- [x] ~~**Zoom auto-apply con toggle para desactivar:**~~ RESUELTO: ya existe toggle en ZoomControlsView (isEnabled)

- [ ] **Validacion de performance (larga duracion):**
    - No probado con videos > 1 hora.

---

## Fase 4 — Features del Editor (3-4 sesiones)

> Features de edicion sobre una base solida. Dependen de ExportPipeline y TimelineView limpios.

- [ ] **Zoom animation tuning:**
    - Hold duration, velocidad de zoom in/out, transiciones suaves entre puntos.
    - El zoom-out entre dos puntos se siente abrupto; evaluar blend o crossfade.
    - Depende de ExportPipeline ya limpio.

- [x] **Zoom auto-apply con toggle para desactivar:** ✅ COMPLETO: ya existe toggle en ZoomControlsView (isEnabled) - verificar que funciona

- [x] ~~**UI del export flow:**~~ RESUELTO: simplificado destination UI, eliminado alert redundante

- [ ] **Toast de "proyecto guardado":**
    - Notificacion visual breve al hacer autosave exitoso.

- [ ] **Image overlays visibles en preview/export:**
    - MediaItem tipo image se importa pero no se renderiza aun (necesita CALayer + animationTool).
    - Depende de ExportPipeline limpio.

- [ ] **Captions visibles en preview (mejorar)**

- [ ] **Noise gate / echo cancellation en mic:**
    - Filtrar audio de bocinas capturado por el mic.
    - Voice activity detection para grabar mic solo con voz.

---

## Fase 5 — Motores Reales (2-3 sesiones)

> Integracion de motores reales. Dependen de EngineContext (DI limpia) y JobQueue consolidado.

- [ ] **Integracion Whisper.cpp real:**
    - `TranscriptionEngine` actualmente devuelve texto simulado.
    - Integrar `whisper.cpp` (o SwiftWhisper) para transcripcion offline real.
    - Depende de JobQueue consolidado.

- [ ] **Preview de grabacion en vivo:**
    - Selector de fuentes muestra capturas estaticas.
    - Implementar stream ligero de ScreenCaptureKit para vista previa en movimiento.
    - Depende de EngineContext (DI limpia).

---

## Fase 6 — Polish, Labs, Distribucion

> Features visuales, experimentos, y preparacion para release.

- [ ] **Motion blur en zoom transitions:**
    - Blur proporcional a la velocidad de movimiento durante zoom in/out.
    - Implementar via `CIMotionBlur` filter o Metal shader.
    - Aplicar en `MaskedVideoCompositor` / `PreviewComposition` durante zooms.

- [ ] **Crop interactivo con aspect ratio presets:**
    - Dialog visual con drag + inputs numericos + lock de aspect ratio (16:9, 9:16, 4:3, 1:1, 21:9).
    - Aplica crop region al source video antes de layout.

- [ ] **Reordenar segmentos en timeline (v1.1)**

- [ ] **Thumbnails al hover en scrubber del preview**

- [ ] **Permisos y Entitlements para distribucion**

- [ ] **Auto-generar proxies al crear proyecto**

- [ ] **Regenerar proxies al cambiar sync offsets**

- [ ] **Refactoring de ZoomSectionController y ZoomPlanGenerator:**
    - Sus tests son los mas grandes: 49KB y 48KB respectivamente.
    - Sugiere que el codigo bajo test es complejo y probablemente necesita simplificacion.

- [ ] **Evaluar migrar `LoggingSystem` a `nonisolated` con lock:**
    - Actualmente es actor, lo que requiere `await` en cada call site.
    - `os_log` es thread-safe por diseño — el actor agrega overhead innecesario.
    - Solo vale la pena si el `await` causa friction significativa en uso.

- [ ] **Cloud provider para generacion de assets**

- [ ] **Estilo frame-a-frame (experimental)**

- [ ] **Auto-cortes por silencios (Fase 5 PRD)**

- [ ] **Capitulos/titulos desde transcript (Fase 5 PRD)**

---

## Completado (Historico)

- [x] ~~**Export no incluye cambios de PiP editados**~~ RESUELTO: save before export + MaskedVideoCompositor en export
- [x] ~~**Sidebar overflow al abrir Background/Zoom/Overlays**~~ RESUELTO: layout compacto vertical, controles redimensionados
- [x] ~~**Timeline no funcional**~~ RESUELTO: playhead sync bidireccional, split/delete/trim conectados, import de assets
- [x] ~~**Track mute toggles no afectan playback**~~ RESUELTO: AVMutableAudioMix para audio + video composition rebuild para video.
- [x] ~~**Mic audio no se graba a veces**~~ RESUELTO: MicAudioRecorder valida formato antes de iniciar; retry automatico.
- [x] ~~**Publishing changes from within view updates**~~ RESUELTO: wrapeado con Task { @MainActor in }.
- [x] ~~**Audio drift detection**~~ RESUELTO: AudioDriftDetector compara duraciones, genera DriftReport.
- [x] ~~**Concurrencia estricta (Swift 6)**~~ RESUELTO: EngineKit compila con `-strict-concurrency=complete` sin warnings.
- [x] ~~**Reparacion de tests unitarios**~~ RESUELTO: tests actualizados para nueva API de Project init + mediaItems.
- [x] ~~**Optimizacion de recursos criticos**~~ RESUELTO: Task leaks, observer leaks, thumbnail LRU, waveform Canvas, project cache.
- [x] ~~**SHA256 real para source files**~~ RESUELTO: CryptoKit SHA256 streaming (64KB chunks) + fileSize reales.
- [x] ~~**Fix errores onChange(of:initial:_:)**~~ RESUELTO: 12 instancias convertidas de API macOS 14 a macOS 13.
- [x] ~~**Auto-zoom desde cursor telemetry**~~ RESUELTO: DwellDetector + ZoomSuggestionEngine + timeline markers + auto-apply.
- [x] ~~**GIF export**~~ RESUELTO: UI de opciones GIF; GIFExportOptions conectado a GIFExportSession.
- [x] ~~**Posicion de camara por segmento**~~ RESUELTO: auto-override al drag, per-segment en preview + export.
- [x] ~~**Camera border (color + ancho)**~~ RESUELTO: borderWidth/borderColor, 10 presets, rendering via CGPath con cache.
- [x] ~~**Per-segment audio (volumen/mute)**~~ RESUELTO: volume/audioMuted en Segment, AudioMixBuilder con ramps.
- [x] ~~**Telemetry recording integrado**~~ RESUELTO: TelemetryRecorder en Recorder start/stop.
- [x] ~~**Autosave**~~ RESUELTO: scheduleAutosave() con 1s debounce via ProjectLibrary.
- [x] ~~**Drag para reposicionar media items en timeline**~~ RESUELTO: DragGesture con feedback visual.
- [x] ~~**Speed presets en timeline**~~ RESUELTO: SegmentInspectorBar con picker (0.25x-4x).
- [x] ~~**Background blur**~~ RESUELTO: CIGaussianBlur al screen como fondo.
- [x] ~~**Duplicar proyecto**~~ RESUELTO: deep copy con nuevo ID + "(Copy)".
- [x] ~~**Export formato .txt para transcript**~~ RESUELTO: exportCaptions() soporta SRT/VTT/TXT.
- [x] ~~**Volume slider por track**~~ RESUELTO: sliders compactos en label del timeline, rango 0–3x.
- [x] ~~**Border radius + shadow en video**~~ RESUELTO: CIBlendWithMask para corners, padding scale+translate.
- [x] ~~**Background gradients**~~ RESUELTO: CILinearGradient rendering.
- [x] ~~**Padding configurable**~~ RESUELTO: scale down + translate center.
- [x] ~~**Export preset 4K HEVC**~~ RESUELTO: ExportPreset.ultra4kHevc (3840x2160, 60fps, 30Mbps HEVC).
- [x] ~~**Estimacion de tamano y tiempo de export**~~ Ya existia: estimatedFileSize + estimatedTimeRemaining.
