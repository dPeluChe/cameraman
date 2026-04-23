# Task List — UI Recovery & Implementation (Dev Backlog)

Este backlog define las tareas para reconstruir la UI de edición que fue removida por incompatibilidad con la API actual del backend.

> **Contexto:**
> - El backend (EngineKit) está 100% completo (Épicas A-L de `tasks.md`)
> - La UI existió en commits anteriores pero usa API obsoleta
> - Código de referencia: `git show bad5940:App/Sources/App/TimelineView.swift`

> Convención:
> - **P0**: necesario para MVP
> - **P1**: después del MVP inmediato
> - **P2**: "Labs" / experimentos

---

## Épica UI-A — Estructura Base de la App

- [x] (P0) Crear `ProjectEditor.swift`: wrapper ObservableObject para `EditorModel` (actor), manejo de llamadas async, estado reactivo
- [x] (P0) Crear `AppNavigation.swift`: NavigationSplitView con sidebar (proyectos) y content (editor/recording)

---

## Épica UI-B — Project Library (Lista de Proyectos)

> **Referencia PRD:** Sección 5.2
> **API Backend:** `ProjectLibrary.listProjects()`, `renameProject()`, `setTags()`, `deleteProject()`

- [x] (P0) Vista de lista/grid de proyectos: thumbnail, nombre, fecha, duración, tags visibles
- [x] (P0) Acciones de proyecto: crear nuevo (→ Recording), abrir existente (→ Editor), renombrar, eliminar con confirmación
- [x] (P0) Editar tags de proyecto (multi-tag)
- [x] (P1) Búsqueda por nombre y filtro por tags
- [x] (P1) Ordenamiento: por fecha, nombre, duración

---

## Épica UI-H — Export UI (Prioridad Alta)

> **Objetivo:** Cerrar el ciclo de producción (Grabar -> Editar -> Exportar).
> **Referencia PRD:** Sección 5.5
> **API Backend:** `ExportEngine.startExport()`, `cancelExport()`, `Job.progress`

- [x] (P0) Modal de export: selector de preset (Web 1080p, HEVC, Portrait), destino con file picker
- [x] (P0) Progreso: progress bar, porcentaje, tiempo estimado, botón Cancel
- [x] (P0) Completado: notificación de éxito, botón "Reveal in Finder"

---

## Épica UI-F — Canvas & Layout Controls

> **Referencia PRD:** Sección 5.3 - Layouts post-grabación
> **API Backend:** `CanvasLayout.setLayout()`, `setCameraPosition()`, `setBackground()`

- [x] (P0) Selector de layout: botones para Full, PiP, Side-by-Side con preview visual
- [x] (P0) Configuración PiP: drag para posicionar cámara, resize handles, corner radius, presets de posición
- [x] (P0) Background: color picker para fondo sólido, selector de imagen, fit mode (fit/fill)
- [x] (P1) Toggle formato 16:9 / 9:16 con preview

---

## Épica UI-G — Overlay Editor

> **Referencia PRD:** Sección 5.3 - Overlays (anotaciones)
> **Código histórico:** `git show 22400cf:App/Sources/App/OverlayEditView.swift` (685 líneas)
> **API Backend:** `EditorModel.addOverlay()`, `updateOverlay()`, `deleteOverlay()`, `OverlayEngine.renderOverlays()`

- [x] (P0) Toolbar de overlays: botones Arrow, Rectangle, Line, Text con selección visual
- [x] (P0) Creación: click + drag para crear overlay en canvas
- [x] (P0) Edición: seleccionar, drag para mover, resize handles, delete con tecla
- [x] (P0) Inspector de estilo: color picker (stroke), stroke width, shadow toggle
- [x] (P0) Para texto: selector de font, size, color
- [x] (P0) Timing: campos start/end time por overlay
- [x] (P1) Animaciones: selector None/Fade In/Fade Out/Draw-on, duration

---

## Épica UI-C — Recording UI (Mejoras)

> **Estado actual:** Funcional pero básico
> **Referencia PRD:** Sección 3.2, 3.3

- [x] (P1) Menú flotante mejorado: selector visual de fuente (display/window/app), preview de captura, toggles audio/cámara
- [x] (P1) Indicador durante grabación: ventana flotante con tiempo, estados (mic/audio/camera), botón Stop, hotkey hints

---

## Épica UI-D — Timeline Editor

> **Referencia PRD:** Sección 5.3 - Editor
> **Código histórico:** `git show bad5940:App/Sources/App/TimelineView.swift` (661 líneas)
> **API Backend:** `EditorModel.trimSegment()`, `splitSegment()`, `deleteSegment()`, `getProject()`

- [x] (P0) Timeline básico: visualización horizontal de segmentos, múltiples tracks (screen, camera, audio), playhead
- [x] (P0) Navegación: click para posicionar playhead, drag para seleccionar rango, zoom in/out, scroll horizontal
- [x] (P0) Operaciones de edición: split en playhead (Cmd+B), delete segmento, trim con drag de bordes
- [x] (P0) Undo/Redo (Cmd+Z / Cmd+Shift+Z)
- [x] (P1) Thumbnails en track de video (usar `ThumbnailCache` del backend)
- [x] (P1) Waveforms en tracks de audio

---

## Épica UI-E — Preview Player

> **Referencia PRD:** Sección 3.4
> **API Backend:** `PreviewEngine.loadProject()`, `play()`, `pause()`, `seek()`, `getCurrentTime()`

- [x] (P0) Reproductor de video: vista con aspect ratio correcto, mostrar frame actual cuando pausado
- [x] (P0) Controles de playback: play/pause/stop, scrubber sincronizado con timeline, tiempo actual/duración
- [x] (P1) Playback rate selector (0.5x, 1x, 2x)
- [x] (P1) Preview con edits aplicados: overlays en tiempo real, layout (PiP), zoom, captions

---

## Épica UI-I — Transcription UI

> **Referencia PRD:** Sección 5.4
> **API Backend:** `TranscriptionEngine.transcribe()`, `exportSRT()`, `exportVTT()`

- [x] (P1) Generar transcripción: botón con progreso, selector de idioma opcional
- [x] (P1) Vista de transcripción: lista de segmentos con timestamps, click → seek, edición de texto
- [x] (P1) Export captions: botones SRT/VTT, toggle "Burn-in captions" en export

---

## Épica UI-J — Zoom Controls

> **Referencia:** Épica I de tasks.md (backend completo)
> **API Backend:** `ZoomPlanGenerator.generateZoomPlan()`, `ZoomSectionController.setIntensity()`

- [x] (P1) Toggle auto-zoom on/off con slider de intensidad global
- [x] (P2) Controles por sección: vista de secciones detectadas, intensidad individual

---

## Épica UI-K — AI Suggestions (Labs)

> **Referencia:** Épica K de tasks.md (backend completo)
> **API Backend:** `AIService.suggestSilenceEdits()`, `suggestChapters()`

- [x] (P2) Panel de sugerencias: lista con tipo (silence cuts, chapters), botón Apply por sugerencia
- [x] (P2) Capítulos automáticos: mostrar sugeridos, editar títulos, aplicar como markers

---

## Épica UI-L — Settings & Preferences

> **Objetivo:** Configuración global de la aplicación.
> **API Backend:** `HotkeyManager`

- [x] (P1) Ventana de Preferencias: Gestión de configuración general.
- [x] (P1) Hotkeys: Visualización de atajos de teclado registrados y estado.

---

## Épica UI-M — Telemetry & Visuals (Integración)

> **Objetivo:** Exponer las capacidades de telemetría capturadas por el backend.
> **API Backend:** `TelemetrySync` (cursor/clicks), `KeystrokeRecorder` (teclas)

- [x] (P1) Telemetry Visuals: Toggle en editor para mostrar/ocultar cursor y visualización de clicks en el preview.
- [x] (P1) Keystroke Overlay: Toggle para mostrar las teclas presionadas sobre el video (útil para tutoriales).

---

## Notas para el Dev

### Patrón para llamar al backend (EditorModel es actor)

```swift
class ProjectEditor: ObservableObject {
    private let editorModel: EditorModel
    @Published var project: Project

    func splitAtPlayhead() async {
        let result = await editorModel.splitSegment(segmentId: id, at: time)
        await MainActor.run {
            self.project = await editorModel.getProject()
        }
    }
}
```

### Recuperar código de referencia

```bash
git show bad5940:App/Sources/App/TimelineView.swift > reference_TimelineView.swift
git show 22400cf:App/Sources/App/OverlayEditView.swift > reference_OverlayEditView.swift
```

Usar como referencia de UI/UX, NO copiar directamente (API cambió).

---

## Criterios de Aceptación (MVP UI)

> Basado en PRD Sección 10

- [x] Crear proyecto desde grabación con preview funcional
- [x] Editar: trim + split/delete visibles en timeline
- [x] Agregar overlay (flecha + texto) visible en preview
- [x] Cambiar layout (PiP) y ver cambio en preview
- [x] Exportar MP4 1080p con progreso visible
- [x] Biblioteca muestra proyectos con nombre, tags, fecha