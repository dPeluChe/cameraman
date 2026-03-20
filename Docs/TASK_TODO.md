# Backlog de Tareas Pendientes

> Actualizado: 2026-03-20
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.

---

## 0. Bugs Criticos de Integracion UI-Engine (Prioridad Inmediata)

> Descubiertos durante testing 2026-03-20. Requieren debugging profundo con Xcode breakpoints.

- [ ] **Camera PiP no visible en preview:**
    - Camera track carga exitosamente (`Camera segment 1: OK`), 2 layer instructions creadas.
    - El video de camara no se renderiza en el preview (PiP invisible).
    - Probable: transform del camera layer instruction incorrecto (posicion/escala).
    - Debugging: verificar `cameraLayerInstruction.setTransform()` values vs render size.

- [ ] **Track mute toggles no afectan playback:**
    - Los toggles cambian opacidad visual en timeline pero no modifican la composicion AVPlayer.
    - Necesita: reconstruir composicion cuando cambia mute state, o usar AVMutableAudioMix para audio mute.

- [ ] **Player controls lentos (play/pause/seek):**
    - El actor isolation de PreviewEngine causa delays.
    - Necesita: evaluar si AVPlayer debe vivir en @MainActor wrapper en vez de actor.

- [ ] **Cursor/click overlays no visibles en preview:**
    - PreviewRenderer tiene logica de overlays pero no esta conectado al player view.
    - Necesita: integrar overlay rendering como capa sobre el AVPlayerLayer.

- [ ] **"Publishing changes from within view updates" repetitivo:**
    - ProjectLibrary() se instancia multiples veces (cada ViewModel crea uno nuevo).
    - Necesita: singleton compartido o inyeccion de dependencias.

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
