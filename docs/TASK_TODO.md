# Backlog de Tareas Pendientes

> Actualizado: 2026-05-14
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

## 🔬 Hallazgos del test session 2026-05-14

> Prueba real de grabar + exportar sobre branch `review/skills-baseline-2605` en display ultrawide 3440x1440 (el mismo del bloqueante B1). Recording 14.5s → export web_1080_h264 6.3s, 15.4MB. **Funcionó end-to-end** — el writer terminó OK esta vez. Hallazgos del log + observación del usuario:

- [ ] **🐛 Regresión: PiP camera overlay drag-to-reposition no funciona durante playback**
    - Solo permite reposicionar cuando el preview está en pausa; antes funcionaba durante playback.
    - Ningún commit del review tocó el gesture de PiP (`ProjectEditorPiPView` + `editor.updateCameraPosition`) directamente.
    - Sospechosos por proximidad: commit `b7b2ebf` (PreviewPlayerViewModel sin `MainActor.run` redundante) cambió cómo se programan algunos updates desde la VM; también la regla `transaction.animation = nil` en `ConfigGroup` introducida en PR #5 puede estar interfiriendo con `DragGesture` durante playback.
    - Acciones: bisect entre `main` y la branch para localizar el commit; si es nuestro, ajustar; si es pre-existente, investigar el gesture handler directamente.

- [ ] **📋 Refine B1: instrumentar `-10877` + CMIO background replacement aunque no fallen**
    - El log mostró los mismos precursores del bloqueante B1 (`throwing -10877` x2, `CMIO_DAL_CMIOExtension_Stream:GetPropertyData background replacement pixel buffer size invalid`, `CMIOHardware.cpp:331 Error: 2003332927`) pero esta vez el writer **no** falló (status=2 completed).
    - Confirma la hipótesis del B1: el ruido viene de VFX de Messages (`__vfx_script_confetti/thumbsup/balloons/fireworks/hearts/lasers/rain` cargándose durante captura). En este run fueron benignos; en B1 escalaron a writer.failed.
    - Acción: loguear cuántos `-10877` ocurren por sesión + correlacionar con `writer.status` para tener telemetría que confirme la causa raíz antes de invertir en mitigación.

- [ ] **📋 Audio: `HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload`**
    - Aparece 2x en el log (una durante grabación, otra durante preview). Indica saturación del proxy de audio del sistema — puede causar audio drift en sesiones largas.
    - Acción: instrumentar duración de cada cycle de audio en `MicAudioRecorder` + `SystemAudioRecorder`. Si en sesiones >5min se ven >N overloads, evaluar bajar sample rate, simplificar el procesamiento, o usar `AVAudioEngine` en lugar de `AudioQueue`.
    - Conecta con TASK 'Validación de performance (larga duración)' de Fase 3.

- [ ] **📋 UI debug: `Attempting to update all DD element frames, but bounds W:0 H:0`**
    - Aparece 1x en preview. Probablemente Drag & Drop interno del sistema o RealityKit (DD = Drag & Drop o Display Devices), no necesariamente nuestro código.
    - Acción: low priority. Reproducir con view debugger activo si vuelve a aparecer, identificar qué view está midiendo cero. Si es nuestro, fix; si es del sistema, ignorar.

- [ ] **🧹 Limpieza de logs ruidosos antes de release**
    - Los logs reales contienen mucho ruido del sistema (entity remap warnings de Messages VFX, `MLE5Engine disabled`, `ViewBridge to RemoteViewService Terminated`, `AddInstanceForFactory: No factory registered`, `AudioQueueObject Error -4 getting reporterIDs`). No son nuestros pero ahogan los logs útiles.
    - Acción: revisar qué logs en `LoggingSystem` (categoría capture/preview/export) están en nivel `info`/`notice` cuando deberían estar en `debug`. Reducir verbosidad sin perder señal de errores reales.

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

## Fase 3 — Performance & Polish

> Medicion y optimizacion sobre código ya estable.

- [ ] **Validación de performance (larga duración):**
    - No probado con videos > 1 hora.

---

## Fase 4 — Features del Editor (3-4 sesiones)

> Features de edición sobre una base sólida. Dependen de ExportPipeline y TimelineView limpios.

- [ ] **Zoom animation tuning:**
    - Hold duration, velocidad de zoom in/out, transiciones suaves entre puntos.
    - El zoom-out entre dos puntos se siente abrupto; evaluar blend o crossfade.

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
    - Nota: `attackCoef` removido de `AudioProcessing.swift` por warning de unused — el gate hoy salta a 1.0 sin smoothing en el attack. Si se implementa noise gate completo, restaurar attack coef con la fórmula original.

---

## Fase 5 — Motores Reales (2-3 sesiones)

> Integración de motores reales. Dependen de EngineContext (DI limpia) y JobQueue consolidado.

- [ ] **Integración Whisper.cpp real:**
    - `TranscriptionEngine` actualmente devuelve texto simulado.
    - Integrar `whisper.cpp` (o SwiftWhisper) para transcripción offline real.
    - Depende de JobQueue consolidado.

- [ ] **Preview de grabación en vivo:**
    - Selector de fuentes muestra capturas estáticas.
    - Implementar stream ligero de ScreenCaptureKit para vista previa en movimiento.
    - Depende de EngineContext (DI limpia).

---

## Fase 6 — Polish, Labs, Distribución

> Features visuales, experimentos, y preparación para release.

- [ ] **Motion blur en zoom transitions:**
    - Blur proporcional a la velocidad de movimiento durante zoom in/out.
    - Implementar via `CIMotionBlur` filter o Metal shader.
    - Aplicar en `MaskedVideoCompositor` / `PreviewComposition` durante zooms.

- [ ] **Ocultar iconos del desktop al grabar:**
    - Toggle en RecordingControlView: "Hide desktop icons"
    - Al iniciar grabación: `defaults write com.apple.finder CreateDesktop -bool false && killall Finder`
    - Al parar grabación: restaurar `CreateDesktop -bool true && killall Finder`
    - Guardar estado previo por si el usuario ya los tenía ocultos.
    - Nota: requiere que Finder se reinicie (breve flash visual).

- [ ] **Crop interactivo con aspect ratio presets:**
    - Dialog visual con drag + inputs numéricos + lock de aspect ratio (16:9, 9:16, 4:3, 1:1, 21:9).
    - Aplica crop region al source video antes de layout.

- [ ] **Reordenar segmentos en timeline (v1.1)**

- [ ] **Thumbnails al hover en scrubber del preview**

- [ ] **Permisos y Entitlements para distribución**

- [ ] **Auto-generar proxies al crear proyecto**

- [ ] **Regenerar proxies al cambiar sync offsets**

- [ ] **Refactoring de ZoomSectionController y ZoomPlanGenerator:**
    - Sus tests son los más grandes: 49KB y 48KB respectivamente.
    - Sugiere que el código bajo test es complejo y probablemente necesita simplificación.

- [ ] **Evaluar migrar `LoggingSystem` a `nonisolated` con lock:**
    - Actualmente es actor, lo que requiere `await` en cada call site.
    - `os_log` es thread-safe por diseño — el actor agrega overhead innecesario.
    - Solo vale la pena si el `await` causa friction significativa en uso.

- [ ] **Cloud provider para generación de assets**

- [ ] **Estilo frame-a-frame (experimental)**

- [ ] **Auto-cortes por silencios (Fase 5 PRD)**

- [ ] **Capítulos/títulos desde transcript (Fase 5 PRD)**

---

## 🔎 Pendientes del Skills Review (branch `review/skills-baseline-2605`, 2026-05-14)

> Hallazgos del review que se decidió **no aplicar** en esa sesión por scope/dependencias. Detalles completos en `docs/RESEARCH/SKILLS_REVIEW_2605.md`.

- [ ] **`RecordingSession` cross-actor Sendable refactor** (review #3)
    - `RecordingSession` es `public final class` con `private(set) var` mutables devuelta por `startRecording()` desde un actor. Los getters (`isRecording`, `duration`, `error`) son leídos desde cualquier thread.
    - Recomendación: cambiar a snapshot `SessionState: Sendable` consultable on-demand.
    - Conecta con la DI de Fase 1 ya parcialmente implementada (EngineContext).

- [ ] **`TimelineView` body memoization** (review #5)
    - `TimelineTrackBuilder.tracks(for: project)` y `Self.computeOverlayRows(...)` se ejecutan en cada body invalidation. Durante playback `currentTime` cambia frecuentemente y dispara recomputaciones innecesarias.
    - Requiere extraer sub-view o `@StateObject` derivado — refactor mayor.

- [ ] **`ThumbnailCache` LRU O(N) → O(log N) o O(1)** (review #7)
    - `thumbnailAccessOrder.removeAll { $0 == key }` es O(N) por insert. Con `maxThumbnailCount=500` cada miss es 500 comparaciones.
    - Necesita añadir dependencia `swift-collections` para `OrderedDictionary` o implementar índice manual.

- [ ] **2 warnings irreducibles en `MaskedVideoCompositor`** (review residual)
    - `sourcePixelBufferAttributes` / `requiredPixelBufferAttributesForRenderContext` no aceptan getter `@Sendable` que el protocolo `AVVideoCompositing` espera vía `NS_SWIFT_SENDABLE`.
    - Workarounds estándar probados sin éxito (`@preconcurrency import`, `@preconcurrency` en conformance, computed `nonisolated` con `static let`, `[String: any Sendable]`).
    - Espera fix de Apple. Documentado in-line.
