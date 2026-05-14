# Backlog de Tareas Pendientes

> Actualizado: 2026-05-12
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.
> Ordenado por fases: fundacion primero, features despues.

---

## 🔴 Bloqueantes (detectados en pruebas reales — 2026-04-18)

- [ ] **Recording: AVAssetWriter falla temprano y deja `screen.mov` corrupto**
    - Síntoma observado en log de prueba: writer pasa a `status: 3` (failed) ~frame 73 con error `-10877`; todos los frames siguientes fallan silenciosamente ("Failed to append video frame N. Writer status: 3").
    - Resultado: archivo de 221KB para 30s de grabación → `PreviewEngine.PreviewError error 1` al abrir el proyecto y "Failed to build composition: Cannot Open" al cargar.
    - Contexto: display ultrawide 3440x1440 (SCDisplay id=3). Cámara sí grabó OK (901 frames). Mic y system audio OK.
    - Precedente: mensaje `GetPropertyData background replacement pixel buffer size invalid or not available` + `CMIOObjectGetPropertyData Error: 2003332927` justo antes del fallo — posible colisión con efectos de sistema (Stickers/VFX de Messages visibles en el log).
    - Acciones mínimas:
      1. Detectar `writer.status == .failed` y abortar la grabación con error al usuario (no seguir acumulando 1700 frames perdidos).
      2. Loguear `writer.error` al transicionar a failed (hoy solo se imprime el texto genérico).
      3. Validar resolución/alignment antes de iniciar el writer (ultrawide puede requerir pixel format o dimensiones específicas).
      4. Reproducir aislando efectos VFX de Messages para confirmar causa raíz.

---

## 🟠 UX Polish — backlog del PR #5 (2026-05-12)

> Items detectados durante el review de UI/UX en la branch `feat/ui-refinements-macos13-compat`. Ninguno bloqueante.

- [ ] **Race condition latente en `startNewTake()`** — `ProjectEditorLeftPanel.swift:103-107` asigna `recViewModel.targetProjectId` antes de postear `.openRecordingWindow`. Hoy el flujo es síncrono y funciona, pero si el observer de la notificación pasa a async (Task, scheduled), el window puede leer `nil`. Pasar el `projectId` en `userInfo` del Notification y leerlo en el observer hace el contrato explícito.
- [ ] **Badge de cantidad en `ProjectAssetsBar` colapsada** — al estar colapsada (38pt) no hay indicador de cuántos takes/segmentos hay. Sumar `(\(count))` al lado del título "Project Assets" cuando esté colapsado.
- [ ] **`AssetChip` ancho fijo trunca nombres largos** — `frame(width: 118)` corta takes con nombres descriptivos. Cambiar a `minWidth: 100, maxWidth: 180` con `fixedSize(horizontal: false)`.
- [ ] **Preset picker perdió contexto visual** — pasó de `.segmented` a `.menu` (necesario por el ancho del panel), pero el menu colapsado oculta opciones. Evaluar `Picker` con `Label` + ícono por opción (HEVC, GIF, H264) para mantener affordance.
- [ ] **Atajos de teclado faltantes**:
    - `⌘E` abrir panel de export
    - `⌘⇧E` re-ejecutar último export
    - `⌘R` abrir ventana de recording
- [ ] **Skeletons en `ProjectAssetsBar`** — cuando `editor.project.takes` está cargando no se distingue entre vacío y loading.
- [ ] **Filename ghost-extension en `ExportView`** — el field muestra "name" y debajo "name.mp4" como label separado. Mostrar la extensión inline en el field (placeholder o sufijo gris) es más obvio.

---

## 🟢 UX — propuestas grandes (roadmap)

> Cambios de diseño más invasivos que valen conversación antes de implementar.

- [ ] **Recent Exports** — recordar últimas 3-5 carpetas de export y ofrecerlas como sugerencias rápidas (patrón Final Cut / Premiere).
- [ ] **Inspector tabs en panel derecho** — hoy es un `ScrollView` con todos los `ConfigGroup` apilados (Background, PiP, Zoom, Overlays). Tabs en la cabecera reducen el scroll y dan foco a una sección a la vez.
- [ ] **Hover preview en `LayoutSelectorView`** — los thumbnails de presets son pequeños; mostrar preview del layout aplicado al video actual en hover ayuda a elegir.
- [ ] **Asset bar position configurable** (top/left/right) en Settings → Layout. Algunos usuarios pueden preferir el sidebar vertical original.
- [ ] **Empty state del editor recién abierto** — onboarding inline ("Drag a take from the bar above to start editing") con flecha animada al timeline vacío.
- [ ] **Curva de zoom visible en timeline** — los markers de suggestions están pero no muestran intensidad. Un mini-gráfico de altura proporcional al zoom level hace la curva legible.

---

## 🛠️ Tooling — Claude Code Skills (2026-05-14)

- [ ] **Crear skill propio `cameraman-engine` con `/skill-creator`** (después de probar `AvdLee/swiftui-expert` + `patrickserrano/ios-swift-skills`):
    - Gap detectado en research: ningún skill público cubre AVFoundation / ScreenCaptureKit / AVMutableComposition / pipeline de zoom keyframado, que es el core de cameraman.
    - Empaquetar convenciones internas: `CompositionBuilder`, `MaskedVideoCompositor`, `AudioMixBuilder`, pipeline `DwellDetector → ZoomSuggestionEngine → ZoomPlanGenerator → PreviewRenderer`, separación Engine/UI con actors, reglas de 400-500 LOC/file y zero warnings.
    - Validar contra una tarea real (ej. refactor de `ZoomSectionController` o nuevo overlay type).
    - Decidir si publicarlo público o mantenerlo en `.claude/skills/` local.

---

## Distribución / Gatekeeper

- [ ] **Firma ad-hoc en `build-dmg.sh`** — `codesign --force --deep --sign - CameramanApp.app` antes de empaquetar. No elimina el bloqueo de Gatekeeper en Tahoe pero estabiliza la firma interna y evita errores con frameworks embebidos. Documentado por feedback de testers en Tahoe 26.4.1 (ver `TASK_COMPLETED/2605.md`).
- [ ] **Mac App Store / Developer ID + notarización** — única solución real al warning de Gatekeeper en Tahoe. Requiere subscripción Apple Developer ($99/año), cert `Developer ID Application`, y pipeline de `xcrun notarytool submit` + `stapler staple`.

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

- [x] **Separar archivos >400 LOC (inicio):** ✅ COMPLETO - ~720 LOC extraidos
    - Extraido de TimelineView (827→773): TimelineView+ZoomSuggestions.swift
    - Extraido de RecordingControlView (606→447): RecordingControlView+SourcePicker.swift, RecordingControlView+Configure.swift
    - Extraido de TeleprompterWindow (495→369): TeleprompterViewModel.swift
    - Extraido de PreferencesView+Sections (453→420): PreferencesViewModels.swift
    - Extraido de RecordingSourceSelectorView (408→225): RecordingSourceSelectorView+Rows.swift

- [x] **Toast de "proyecto guardado":** ✅ COMPLETO - ToastView.swift + ProjectEditor integration

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

- [x] **Descomponer TimelineView:** ✅ COMPLETO (v0.5.1, 2026-04-18) — 864 → 413 LOC.
    - Extraído a: `TimelineView+Thumbnails.swift` (thumbnails/waveforms), `TimelineView+DragDrop.swift` (gesture/drop/import/trim), `TimelineView+EditActions.swift` (split/delete/undo/redo/volume), y métodos de zoom movidos a `TimelineView+ZoomSuggestions.swift`.
    - Dead code eliminado: `getThumbnailForTime`, `zoomSuggestionGenerator`.
    - Enfoque: extensiones (mantiene `@State`), bajo riesgo. Follow-up opcional: promover a `@StateObject` sub-ViewModels si queremos testabilidad aislada.

- [x] **Extraer pipeline de export de `performExport()`:** ✅ COMPLETO (v0.5.1, 2026-04-18) — monolítica de ~480 LOC dividida en stages.
    - `VideoExportSession.swift` (125 LOC): orquestador que encadena stages 1-8.
    - `VideoExportSession+Stages.swift` (261 LOC): prepareOutput / validateAssets / buildComposition / configureSession / runSession / verifyOutput.
    - `VideoExportSession+Composition.swift` (277 LOC): buildExportVideoComposition con rutas fullscreen-camera / standard / per-segment-masked separadas.
    - Follow-up opcional: convertir stages en structs con `execute() async throws` si se quiere testear cada uno aisladamente.

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

- [x] **Toast de "proyecto guardado":** ✅ COMPLETO - ToastView.swift implementado

- [ ] **Overlays polish (branches: feature/overlays-timeline, feature/overlay-inspector):**
    - **Timing**: overlays aparecen en rangos incorrectos en el preview — el start/end del overlay no coincide con cuándo se renderiza en el compositor. Debuggear el filtro `currentTime >= overlay.start && currentTime <= overlay.end` en MaskedVideoCompositor.
    - **Edición no se refleja**: cambios de posición/escala/rotación desde el popover no se ven en el preview. Verificar que `rebuildVideoComposition` pase overlays actualizados y que el cache de overlay layer se invalide al cambiar propiedades.
    - **Canvas visual para posicionar**: los presets de 9 posiciones son limitados. Implementar un mini-canvas (como PiP editor) donde se pueda arrastrar el overlay visualmente sobre una miniatura del frame.
    - **Stacking en timeline**: múltiples overlays se empalman en un solo row — necesitan stacking visual o rows separadas.
    - **Overlay rendering quality**: la flecha/rect se ven pero el tamaño y posición no corresponden con lo configurado.
    - Lo que SÍ funciona: track en timeline, drag para mover, popover con controles, rendering básico de shapes en compositor y export.

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

- [ ] **Ocultar iconos del desktop al grabar:**
    - Toggle en RecordingControlView: "Hide desktop icons"
    - Al iniciar grabacion: `defaults write com.apple.finder CreateDesktop -bool false && killall Finder`
    - Al parar grabacion: restaurar `CreateDesktop -bool true && killall Finder`
    - Guardar estado previo por si el usuario ya los tenia ocultos.
    - Nota: requiere que Finder se reinicie (breve flash visual).

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
