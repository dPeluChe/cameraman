# Backlog de Deuda Técnica y Mejoras (Post-MVP)

Este documento lista las tareas pendientes para llevar el proyecto de "MVP Funcional" a "Producto Final Pulido". Estas tareas no bloquearon la recuperación de la UI, pero son necesarias para la experiencia de usuario final.

## 1. Motores Reales (Prioridad Alta)
- [ ] **Integración Whisper.cpp (AI):**
    - Actualmente `TranscriptionEngine` devuelve un texto simulado ("Welcome to this video tutorial...").
    - **Tarea:** Integrar la librería `whisper.cpp` (o SwiftWhisper) en `EngineKit` para realizar transcripción offline real de los archivos de audio extraídos.
- [ ] **Preview de Grabación en Vivo:**
    - Actualmente el selector de fuentes muestra capturas estáticas (`CGDisplayCreateImage`).
    - **Tarea:** Implementar un stream ligero de `ScreenCaptureKit` en `RecordingSourceSelectorView` para que el usuario vea una vista previa en movimiento de la ventana/pantalla que va a grabar.

## 2. Calidad y Estabilidad (Prioridad Media)
- [ ] **Concurrencia Estricta (Swift 6):**
    - Se arreglaron los crashes principales, pero el código aún genera warnings de aislamiento de actores.
    - **Tarea:** Realizar una pasada de refactorización para adherirse estrictamente a `@MainActor` y `Sendable` en todo `EngineKit`.
- [ ] **Validación de Performance:**
    - No se ha probado con proyectos de larga duración.
    - **Tarea:** Grabar y editar un video de >1 hora para verificar que el Timeline y el Preview no degraden su rendimiento (FPS).
- [ ] **Reparación de Tests Unitarios:**
    - Tras el renombrado de `App` a `Cameraman` y los cambios en la API (inicializadores de `Project`), los tests unitarios actuales no compilan.
    - **Tarea:** Actualizar imports, corregir mocks de `Project` y `ProjectEditor`, y asegurar que `swift test` pase exitosamente.

## 3. Infraestructura y Distribución (Prioridad Baja/Final)
- [ ] **Permisos y Entitlements:**
    - Para que la cámara y el micrófono funcionen fuera de Xcode, se necesitan los `entitlements` de macOS correctos.
    - **Tarea:** Configurar `hardened runtime` y los keys de `Info.plist` para Screen Recording, Camera y Microphone.
- [ ] **Tests Automatizados:**
    - Aunque hay tests unitarios, faltan tests de integración UI automáticos.
