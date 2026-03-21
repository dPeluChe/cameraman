# Backlog de Tareas Pendientes

> Actualizado: 2026-03-20 (sesion final)
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.

---

## 0. Bugs Conocidos (Prioridad Alta)

- [x] ~~**Export no incluye cambios de PiP editados**~~ RESUELTO: save before export + MaskedVideoCompositor en export

- [ ] **Sidebar overflow al abrir Background/Zoom/Overlays:**
    - Los controles de Background (Solid Color, Image, Blurred Screen + paleta de colores) se salen del panel de 260px.
    - Necesita: redisenar controles para layout compacto vertical.
    - Overlays canvas editor tambien desborda.

- [ ] **Timeline no funcional (PRIORIDAD ALTA):**
    - Split: no genera segmentos separados visualmente ni en el modelo
    - Delete: no elimina segmentos seleccionados
    - Canales: eye toggles son solo visuales, no afectan preview/export
    - No se puede desfasar tracks entre si
    - No se puede agregar assets/tracks adicionales
    - Playhead no sincroniza con preview al hacer click en timeline
    - Necesita: conectar TimelineView actions al EditorModel + CompositionBuilder

- [ ] **Track mute toggles no afectan playback:**
    - Toggles solo visuales en timeline. No silencian audio ni ocultan video.
    - Necesita: AVMutableAudioMix para mute por track de audio.

- [ ] **Mic audio no se graba a veces:**
    - Primera grabacion puede no tener mic audio ("No mic audio track available").
    - Posible race condition en Recorder al iniciar mic audio recording.

- [ ] **"Publishing changes from within view updates" residual:**
    - Aparece 1-2 veces al cambiar de proyecto. No bloquea pero es un warning.

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

- [ ] **Reparacion de tests unitarios:**
    - Tests no compilan tras cambios de API.

- [ ] **Validacion de performance (larga duracion):**
    - No probado con videos > 1 hora.

- [ ] **SHA256 real para source files:**
    - `ProjectStore` usa valores placeholder.

- [ ] **Fix errores `onChange(of:initial:_:)` en App:**
    - 16 errores por API de macOS 14.0+ usada con target macOS 13.

## 3. Features del Editor (Prioridad Media)

- [ ] **Reordenar segmentos en timeline (v1.1)**
- [ ] **Speed presets en timeline (v1.1):** UI para cambiar velocidad por segmento
- [ ] **Background blur (v1.1)**
- [ ] **Captions visibles en preview (mejorar)**
- [ ] **Duplicar proyecto**
- [ ] **Export formato `.txt` para transcript**
- [ ] **Thumbnails al hover en scrubber del preview**

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
