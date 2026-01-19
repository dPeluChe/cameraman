# Task List — Implementación (Dev Backlog)
Este backlog está organizado por épicas y por orden recomendado.

> Convención sugerida:
> - **P0**: necesario para MVP
> - **P1**: después del MVP inmediato
> - **P2**: “Labs” / experimentos

---

## Épica A — Repo & Fundaciones
1. (P0) Crear repo + módulos: `EngineKit` (Swift Package) + `App` (SwiftUI)
2. (P0) Definir `project.json` schema v1 y migración simple por `schema_version`
3. (P0) Implementar `ProjectStore`:
   - crear carpeta por proyecto
   - guardar/leer `project.json`
   - actualizar `updated_at`
4. (P0) Implementar `ProjectLibrary`:
   - listProjects (orden por `updated_at`)
   - renameProject
   - setTags (multi‑tag)
5. (P0) Implementar `JobQueue`:
   - run/export/transcribe
   - progreso + cancelación + logs

---

## Épica B — Recording Studio (Screen + Audio + Camera)
6. (P0) Selector de fuente:
   - list displays
   - list windows
   - list apps
7. (P0) Permisos y "health checks":
   - screen recording permission
   - mic permission
   - camera permission
8. (P0) `CaptureEngine`:
   - stream de video pantalla (resolución nativa, 60fps)
   - system audio vía `SCStreamConfiguration.capturesAudio` (macOS 13+)
   - timestamps consistentes (sync reference)
9. (P0) `CameraEngine`:
   - captura cámara como pista separada (720p/1080p @ 30fps)
   - sync offset configurable respecto a screen
10. (P0) `Recorder`:
    - escribir `screen.mov` (resolución nativa)
    - escribir `camera.mov`
    - escribir `system_audio.m4a`, `mic_audio.m4a`
    - registrar sync offsets en metadata
11. (P0) Hotkeys start/stop/pause + UI mínima

---

## Épica C — Telemetría cursor/clicks/keys
12. (P0) `TelemetryRecorder`:
    - move throttled (30-60 Hz)
    - down/up (clicks)
    - scroll opcional
13. (P0) Guardar `telemetry/cursor.jsonl`
14. (P1) Sincronización y validación: alineación con timeline (debug overlay)
15. (P1) Captura de keystrokes (opt-in):
    - registrar teclas/shortcuts presionados
    - guardar en `telemetry/keys.jsonl`
    - útil para tutoriales que muestran shortcuts en pantalla
    - **Nota:** requiere permiso de Accessibility

---

## Épica D — Editor MVP (Timeline + Canvas)
> **Dependencia:** Esta épica debe desarrollarse en paralelo con **Épica F (Preview Engine)**. Sin preview funcional, el editor es difícil de desarrollar y probar.

16. (P0) `EditorModel` no destructivo:
    - trim in/out
    - cut segments (modelo basado en segments, no edits)
17. (P0) Timeline UI simple:
    - selección de rango
    - split/delete
18. (P0) Canvas layout presets:
    - PiP
    - side‑by‑side
19. (P0) Background:
    - solid color
    - image background (fit/fill)
20. (P0) Formato:
    - 16:9
    - 9:16

---

## Épica E — Overlays (flechas, líneas, rectángulos, texto)
21. (P0) Definir `overlays[]` en `project.json` + helpers CRUD
22. (P0) Canvas overlay editing:
    - drag + resize handles
    - inspector de estilo (stroke width, color, shadow)
23. (P0) Render de overlays en preview
24. (P0) Soporte de timing start/end por overlay
25. (P1) Animaciones: fade in/out, "draw-on" (opcional)

---

## Épica F — Preview Engine
> **Nota:** Iniciar en paralelo con Épica D. El preview es esencial para desarrollar y probar el editor.

26. (P0) `PreviewEngine`:
    - playback con edits aplicados
    - seek/play/pause
27. (P0) Generación de proxies (para archivos grandes):
    - proxy de baja resolución para preview fluido
    - usar original solo en export
28. (P1) Cache de thumbnails / waveform (mejora UX)

---

## Épica G — Transcripción & Captions (offline)
29. (P0) `TranscriptionEngine` job:
    - extraer audio a formato STT
    - ejecutar STT offline (ej. Whisper.cpp)
    - generar `transcript.json` + `.srt` + `.vtt`
30. (P1) Captions overlay en preview
31. (P1) Burn‑in captions en export

---

## Épica H — Export Engine
32. (P0) `ExportEngine` job:
    - render final con trims/cuts/layouts/overlays
    - downscale de resolución nativa a 1080p
    - preset `web_1080_h264`
33. (P0) Progreso + cancelación + logs estructurados
34. (P1) Presets adicionales:
    - HEVC
    - calidad alta (4K)
35. (P1) Export GIF (si se decide)

---

## Épica I — Cursor Zoom (auto-zoom por clicks)
36. (P1) Parser de telemetría:
    - detectar clicks "importantes"
    - agrupar eventos por ventanas temporales
37. (P1) Generador de "zoom plan":
    - keyframes con easing
    - límites (no marear; min/max zoom)
38. (P1) Render de zoom en preview/export
39. (P1) Controles: intensidad / on/off por sección

---

## Épica J — Library/UX polish
40. (P1) Biblioteca de proyectos:
    - búsqueda por nombre/tags
    - ordenamiento
41. (P1) Autosave consistente (actualiza `updated_at`)
42. (P1) Atajos globales, menubar status (opcional)
43. (P1) Reportes de crash / logging

---

## Épica K — IA preparada (Feature flags)
44. (P1) Definir interfaz `AIService` + `Suggestion` + `AssetRef`
45. (P1) Local "smart edits":
    - sugerir cortes por silencios
    - capítulos desde transcript
46. (P2) Cloud provider:
    - generar background asset por prompt
    - aplicar a canvas como asset
47. (P2) Labs:
    - estilo frame‑a‑frame (experimental)
    - reemplazo de fondo en cámara (experimental)

---

## Épica L — Testing & QA
> **Nota:** Estas tasks deben ejecutarse en paralelo con el desarrollo de cada épica correspondiente.

48. (P0) Tests de integración para `CaptureEngine`:
    - verificar captura de pantalla + audio
    - verificar sync entre pistas
49. (P0) Tests de `ProjectStore`:
    - crear/leer/actualizar proyectos
    - migración de schema
50. (P0) Tests de export:
    - verificar audio sync en output
    - verificar aplicación de trims/cuts
    - verificar overlays renderizados
51. (P1) Tests de `PreviewEngine`:
    - seek accuracy
    - playback con edits aplicados
52. (P1) Tests de `TranscriptionEngine`:
    - accuracy básica de transcripción
    - formato correcto de SRT/VTT
53. (P1) Test de regresión de audio drift:
    - grabación de 10+ minutos sin drift

---
