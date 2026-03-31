# Backlog de Tareas Pendientes

> Actualizado: 2026-03-31
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.

---

## 0. Bugs Conocidos (Prioridad Alta)

- [x] ~~**Export no incluye cambios de PiP editados**~~ RESUELTO: save before export + MaskedVideoCompositor en export

- [x] ~~**Sidebar overflow al abrir Background/Zoom/Overlays**~~ RESUELTO: layout compacto vertical, controles redimensionados

- [x] ~~**Timeline no funcional**~~ RESUELTO: playhead sync bidireccional, split/delete/trim conectados, import de assets

- [x] ~~**Track mute toggles no afectan playback**~~ RESUELTO: AVMutableAudioMix para audio + video composition rebuild para video. Funciona en preview y export.

- [ ] **Mic audio no se graba a veces:**
    - Primera grabacion puede no tener mic audio ("No mic audio track available").
    - Posible race condition en Recorder al iniciar mic audio recording.

- [ ] **"Publishing changes from within view updates" residual:**
    - Aparece al cargar proyectos. GeometryReader fix aplicado (Task defer) pero el warning persiste en otros sitios. No bloquea.

---

## 1. Motores Reales (Prioridad Alta)

- [ ] **Integracion Whisper.cpp real:**
    - `TranscriptionEngine` actualmente devuelve texto simulado.
    - Integrar `whisper.cpp` (o SwiftWhisper) para transcripcion offline real.

- [ ] **Preview de grabacion en vivo:**
    - Selector de fuentes muestra capturas estaticas.
    - Implementar stream ligero de ScreenCaptureKit para vista previa en movimiento.

- [ ] **Audio drift detection:**
    - Comparar duracion de pistas audio vs video durante export.
    - Alertar si drift > 100ms.

## 2. Calidad y Estabilidad (Prioridad Media)

- [ ] **Concurrencia estricta (Swift 6):**
    - Refactorizar para `@MainActor` y `Sendable` estricto en EngineKit.

- [x] ~~**Reparacion de tests unitarios**~~ RESUELTO: tests actualizados para nueva API de Project init + mediaItems.

- [x] ~~**Optimizacion de recursos criticos (pre-release):**~~ RESUELTO: Task leaks, observer leaks, thumbnail LRU, waveform Canvas, project cache, deferred generation

- [ ] **Validacion de performance (larga duracion):**
    - No probado con videos > 1 hora.

- [ ] **SHA256 real para source files:**
    - `ProjectStore` usa valores placeholder.

- [ ] **Fix errores `onChange(of:initial:_:)` en App:**
    - 16 errores por API de macOS 14.0+ usada con target macOS 13.

## 3. Features del Editor — Prioridad Alta (Next Up)

- [ ] **Auto-zoom desde cursor telemetry:**
    - Detectar "dwell" del cursor (>450ms quieto) y sugerir puntos de zoom automaticos.
    - Ya tenemos infraestructura: `TelemetryRecorder` graba posiciones, `ZoomConfiguration` con keyframes existe en el modelo.
    - Portar algoritmo de dwell detection (~60 lineas, inspirado en OpenScreen).
    - UI de "sugerencias de zoom" en el timeline (badges o markers).
    - Boton "Apply" que crea `ZoomConfiguration` keyframes automaticamente.
    - Referencia: `openscreen/src/components/video-editor/timeline/zoomSuggestionUtils.ts`

- [ ] **GIF export:**
    - Exportar a GIF animado con opciones de frame rate, tamano, y loop.
    - Usar `CGImageDestination` con `kUTTypeGIF` o biblioteca como `SwiftGif`.
    - Opciones: fps (10/15/24), tamano (original/small/medium), loop on/off.
    - Agregar como preset adicional en ExportView.

- [ ] **Posicion de camara por segmento (split → reposicionar PiP):**
    - Al hacer split de un segmento, cada segmento resultante tiene su propia posicion de camara PiP.
    - Permite: "salir a la izquierda" en segmento 1, luego "salir arriba" en segmento 2.
    - Modelo: agregar `cameraPosition` (o `pipLayout`) override por segmento en `Project.Timeline.Segment`.
    - UI: al seleccionar un segmento, los controles de PiP/layout en el sidebar aplican solo a ese segmento.
    - Compositor: leer `segment.cameraPosition ?? project.canvas.layout` como fallback.

## 3b. Features del Editor — Prioridad Media

- [ ] **Drag para reposicionar media items en timeline:**
    - Actualmente se insertan al playhead; falta drag para moverlos.
- [ ] **Image overlays visibles en preview/export:**
    - MediaItem tipo image se importa pero no se renderiza aun (necesita CALayer + animationTool).
- [ ] **Reordenar segmentos en timeline (v1.1)**
- [ ] **Speed presets en timeline (v1.1):** UI para cambiar velocidad por segmento (`segment.speed` ya existe en modelo)
- [ ] **Background blur (v1.1)**
- [ ] **Captions visibles en preview (mejorar)**
- [ ] **Duplicar proyecto**
- [ ] **Export formato `.txt` para transcript**
- [ ] **Thumbnails al hover en scrubber del preview**
- [x] ~~**Volume slider por track (en vez de solo mute on/off)**~~ RESUELTO: sliders compactos en label del timeline, rango 0–3x, mute icono speaker/eye por tipo de track

## 3c. Features del Editor — Inspirados en OpenScreen (Polish Visual)

- [ ] **Border radius + shadow en video:**
    - Esquinas redondeadas (0–16px) y drop-shadow configurable en el contenido de video dentro del canvas.
    - Slider de corner radius + slider de shadow intensity en sidebar.
    - Aplicar via `CALayer.cornerRadius` y `NSShadow` en `MaskedVideoCompositor`.
- [ ] **Background gradients:**
    - Agregar tab "Gradient" en `BackgroundControlsView` con 7–10 presets.
    - Renderizar con `CGGradient` en el compositor.
    - Mantener wallpapers/solid como opciones existentes.
- [ ] **Motion blur en zoom transitions:**
    - Blur proporcional a la velocidad de movimiento durante zoom in/out.
    - Implementar via `CIMotionBlur` filter o Metal shader.
    - Aplicar en `MaskedVideoCompositor` / `PreviewComposition` durante zooms.
- [ ] **Padding configurable:**
    - Slider 0–100% para espacio entre video y bordes del canvas.
    - El video se escala dentro del padding, background visible en los bordes.
- [ ] **Crop interactivo con aspect ratio presets:**
    - Dialog visual con drag + inputs numericos + lock de aspect ratio (16:9, 9:16, 4:3, 1:1, 21:9).
    - Aplica crop region al source video antes de layout.

## 4. Infraestructura y Distribucion (Prioridad Baja)

- [ ] **Permisos y Entitlements para distribucion**
- [ ] **Tests automatizados de UI**
- [ ] **Export preset 4K HEVC (v1.1)**
- [ ] **Auto-generar proxies al crear proyecto**
- [ ] **Regenerar proxies al cambiar sync offsets**
- [ ] **Estimacion de tamano y tiempo de export**

## 5. Experimentos IA (Prioridad P2 / Labs)

- [ ] **Cloud provider para generacion de assets**
- [ ] **Estilo frame-a-frame (experimental)**
- [ ] **Auto-cortes por silencios (Fase 5 PRD)**
- [ ] **Capitulos/titulos desde transcript (Fase 5 PRD)**
