# Backlog de Tareas Pendientes

> Actualizado: 2026-03-20
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.

---

## 0. Bugs e Integracion UI-Engine (Prioridad Inmediata)

> Actualizado: 2026-03-20 final de sesion.

- [x] ~~**Camera PiP no visible en preview**~~ RESUELTO
- [x] ~~**Preview playback lento**~~ RESUELTO: AVPlayerLayer nativo
- [x] ~~**ProjectLibrary instancias multiples**~~ RESUELTO: singleton
- [x] ~~**Camera PiP detras del screen**~~ RESUELTO: Z-order de layer instructions
- [x] ~~**Camera PiP no se mueve con drag**~~ RESUELTO: onReceive objectWillChange
- [x] ~~**Dimensiones de camara hardcoded**~~ RESUELTO: usar naturalSize del track

### Pendientes de esta sesion:

- [ ] **Corner radius / mascara circular para camara PiP:**
    - AVFoundation no soporta corner radius en layer instructions nativamente.
    - Opciones: (a) Custom AVVideoCompositing para aplicar mascara por frame, (b) SwiftUI overlay mask encima del AVPlayerView, (c) CoreImage filter en custom compositor.
    - El usuario quiere formas variadas: circulo, estrella, recuadro redondeado.

- [ ] **Layout Side-by-Side no funciona:**
    - El preset "Side-by-Side" debe mostrar screen y camara a 50/50.
    - Actualmente solo cambia el tipo pero no ajusta los transforms correctamente.

- [ ] **Export no incluye cambios de PiP:**
    - Al exportar, el PiP no refleja la posicion/tamano editados.
    - VideoExportSession lee del project pero puede no tener los cambios guardados.

- [ ] **Preview se detiene al actualizar PiP:**
    - Al mover la camara, el rebuild de composicion pausa el playback.
    - Necesita: no pausar durante drag, solo rebuild al soltar (onEnded).

- [ ] **Track mute toggles no afectan playback:**
    - Toggles solo visuales. Necesita: AVMutableAudioMix para mute por track.

- [ ] **"Publishing changes from within view updates" sigue apareciendo:**
    - Singleton redujo la frecuencia pero sigue en algunos flows.

---

## 1. Motores Reales (Prioridad Alta)

- [ ] **Integración Whisper.cpp real:**
    - `TranscriptionEngine` actualmente devuelve texto simulado.
    - Integrar `whisper.cpp` (o SwiftWhisper) para transcripción offline real.
    - Bundlear modelo `base` (~150MB), permitir descarga de `small`/`medium`.

- [ ] **Preview de grabación en vivo:**
    - El selector de fuentes muestra capturas estáticas (`CGDisplayCreateImage`).
    - Implementar stream ligero de ScreenCaptureKit para vista previa en movimiento.

- [ ] **Audio drift detection:**
    - Spec define detección de drift > 100ms entre pistas (tech-spec sección 9.2).
    - Implementar comparación de duración de pistas audio vs video durante export.
    - Alertar al usuario y permitir corrección via `sync_offset_ms`.

## 2. Calidad y Estabilidad (Prioridad Media)

- [ ] **Concurrencia estricta (Swift 6):**
    - El código genera warnings de aislamiento de actores.
    - Refactorizar para `@MainActor` y `Sendable` estricto en EngineKit.

- [ ] **Reparación de tests unitarios:**
    - Tests no compilan tras cambios de API (inicializadores de `Project`, campo `animation` en Overlay).
    - Actualizar imports, mocks, y asegurar `swift test` pase.

- [ ] **Validación de performance (larga duración):**
    - No probado con videos > 1 hora.
    - Verificar que Timeline y Preview no degraden FPS.

- [ ] **SHA256 real para source files:**
    - `ProjectStore` usa valores placeholder para SHA256 y `size_bytes`.
    - Calcular checksums reales al crear proyecto.

- [ ] **Fix errores preexistentes `onChange(of:initial:_:)` en App:**
    - 16 errores por API de macOS 14.0+ usada con target macOS 13.
    - Agregar `#available` checks o subir minimum deployment target.

## 3. Features del Editor (Prioridad Media)

- [ ] **Reordenar segmentos en timeline (v1.1):**
    - Spec define drag-and-drop de segmentos (prd.md seccion 5.3).
    - El modelo lo soporta pero la UI no lo implementa.

- [ ] **Speed presets en timeline (v1.1):**
    - `segment.speed` existe en el modelo y funciona en export/preview.
    - Falta UI para que el usuario cambie la velocidad por segmento.

- [ ] **Background blur (v1.1):**
    - Canvas background soporta `solid` e `image`.
    - Agregar opcion `blur` del contenido de pantalla como fondo.

- [ ] **Captions visibles en preview (mejorar):**
    - Captions se renderizan en export (burn-in) pero el overlay de preview puede mejorar.

- [ ] **Duplicar proyecto:**
    - PRD define "duplicar" como accion de biblioteca (seccion 5.2).
    - `ProjectLibrary` no tiene `duplicateProject()` — copiar carpeta + generar nuevo UUID.

- [ ] **Export formato `.txt` para transcript:**
    - PRD define export de transcript en `.txt`, `.srt`, `.vtt` (seccion 5.4).
    - `.srt` y `.vtt` existen, falta `.txt` plano.

- [ ] **Posicion/escala manual de camara en canvas:**
    - PRD seccion 5.3: "Posicion/escala camara en canvas".
    - Hoy los presets (PiP, side-by-side) definen posicion fija.
    - Falta UI para drag/resize libre de la camara en el canvas.

- [ ] **Thumbnails al hover en scrubber del preview:**
    - ARCHIVED_NEW_TASKS menciona preview de thumbnails al hacer hover en scrubber.
    - `ThumbnailCache` y `PreviewFrameExtractor` existen pero no estan conectados al scrubber UI.

## 4. Infraestructura y Distribucion (Prioridad Baja)

- [ ] **Permisos y Entitlements para distribucion:**
    - Configurar `hardened runtime` y keys de `Info.plist`.
    - Screen Recording, Camera, Microphone permissions.

- [ ] **Tests automatizados de UI:**
    - Existen tests unitarios pero faltan tests de integracion UI.

- [ ] **Export preset 4K HEVC (v1.1):**
    - Spec define `high_4k_hevc` preset (tech-spec seccion 8).
    - Solo falta agregar el preset estatico a `ExportPreset`.

- [ ] **Auto-generar proxies al crear proyecto:**
    - Tech-spec seccion 10.3: "Al crear proyecto, generar proxies como job en background".
    - ProxyGenerator existe y esta conectado al preview, pero no se auto-dispara al crear proyecto.

- [ ] **Regenerar proxies al cambiar sync offsets:**
    - Tech-spec seccion 10.3 paso 4: "Si el usuario modifica sync offsets, regenerar proxies".
    - No implementado.

- [ ] **Estimacion de tamano y tiempo de export:**
    - ARCHIVED_NEW_TASKS: "Estimacion de tamano de archivo" y "Estimacion de tiempo de export".
    - ExportView no muestra estimaciones previas al export.

## 5. Experimentos IA (Prioridad P2 / Labs)

- [ ] **Cloud provider para generacion de assets:**
    - Interfaz `AIService` existe, falta conectar a un provider real.
    - Generar backgrounds por prompt, aplicar a canvas.

- [ ] **Estilo frame-a-frame (experimental):**
    - Reemplazo de fondo en camara, style transfer.
    - Reservado para fase Labs.

- [ ] **Auto-cortes por silencios (Fase 5 PRD):**
    - PRD Fase 5: "Auto-cortes por silencios".
    - `AIService.suggestSilenceEdits()` existe en backend.
    - Falta un flujo automatizado que aplique los cortes sugeridos.

- [ ] **Capitulos/titulos desde transcript (Fase 5 PRD):**
    - PRD Fase 5: "Capitulos/titulos desde transcript".
    - `AIService.suggestChapters()` existe en backend.
    - ChapterManagementView existe pero no auto-genera desde transcript.
