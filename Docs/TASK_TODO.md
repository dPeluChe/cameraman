# Backlog de Tareas Pendientes

> Actualizado: 2026-03-20
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.

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
    - Spec define drag-and-drop de segmentos (prd.md sección 5.3).
    - El modelo lo soporta pero la UI no lo implementa.

- [ ] **Speed presets en timeline (v1.1):**
    - `segment.speed` existe en el modelo y funciona en export/preview.
    - Falta UI para que el usuario cambie la velocidad por segmento.

- [ ] **Background blur (v1.1):**
    - Canvas background soporta `solid` e `image`.
    - Agregar opción `blur` del contenido de pantalla como fondo.

- [ ] **Captions visibles en preview (mejorar):**
    - Captions se renderizan en export (burn-in) pero el overlay de preview puede mejorar.

## 4. Infraestructura y Distribución (Prioridad Baja)

- [ ] **Permisos y Entitlements para distribución:**
    - Configurar `hardened runtime` y keys de `Info.plist`.
    - Screen Recording, Camera, Microphone permissions.

- [ ] **Tests automatizados de UI:**
    - Existen tests unitarios pero faltan tests de integración UI.

- [ ] **Export preset 4K HEVC (v1.1):**
    - Spec define `high_4k_hevc` preset (tech-spec sección 8).
    - Solo falta agregar el preset estático a `ExportPreset`.

## 5. Experimentos IA (Prioridad P2 / Labs)

- [ ] **Cloud provider para generación de assets:**
    - Interfaz `AIService` existe, falta conectar a un provider real.
    - Generar backgrounds por prompt, aplicar a canvas.

- [ ] **Estilo frame-a-frame (experimental):**
    - Reemplazo de fondo en cámara, style transfer.
    - Reservado para fase Labs.
