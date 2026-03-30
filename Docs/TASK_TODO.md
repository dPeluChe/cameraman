# Backlog de Tareas Pendientes

> Actualizado: 2026-03-30
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

## 3. Features del Editor (Prioridad Media)

- [ ] **Drag para reposicionar media items en timeline:**
    - Actualmente se insertan al playhead; falta drag para moverlos.
- [ ] **Image overlays visibles en preview/export:**
    - MediaItem tipo image se importa pero no se renderiza aun (necesita CALayer + animationTool).
- [ ] **Reordenar segmentos en timeline (v1.1)**
- [ ] **Speed presets en timeline (v1.1):** UI para cambiar velocidad por segmento
- [ ] **Background blur (v1.1)**
- [ ] **Captions visibles en preview (mejorar)**
- [ ] **Duplicar proyecto**
- [ ] **Export formato `.txt` para transcript**
- [ ] **Thumbnails al hover en scrubber del preview**
- [x] ~~**Volume slider por track (en vez de solo mute on/off)**~~ RESUELTO: sliders compactos en label del timeline, rango 0–3x, mute icono speaker/eye por tipo de track

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
