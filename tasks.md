# Task List — Implementación (Dev Backlog)
Este backlog está organizado por épicas y por orden recomendado.

> Convención sugerida:
> - **P0**: necesario para MVP
> - **P1**: después del MVP inmediato
> - **P2**: "Labs" / experimentos

---

## Épica A — Repo & Fundaciones
- [x] (P0) Crear repo + módulos: `EngineKit` (Swift Package) + `App` (SwiftUI)
- [x] (P0) Definir `project.json` schema v1 y migración simple por `schema_version`
- [x] (P0) Implementar `ProjectStore`: crear carpeta por proyecto, guardar/leer `project.json`, actualizar `updated_at`
- [x] (P0) Implementar `ProjectLibrary`: listProjects (orden por `updated_at`), renameProject, setTags (multi‑tag)
- [x] (P0) Implementar `JobQueue`: run/export/transcribe, progreso + cancelación + logs

---

## Épica B — Recording Studio (Screen + Audio + Camera)
- [x] (P0) Selector de fuente: list displays, list windows, list apps
- [x] (P0) Permisos y "health checks": screen recording permission, mic permission, camera permission
- [x] (P0) `CaptureEngine`: stream de video pantalla (resolución nativa, 60fps), system audio vía `SCStreamConfiguration.capturesAudio` (macOS 13+), timestamps consistentes (sync reference)
- [x] (P0) `CameraEngine`: captura cámara como pista separada (720p/1080p @ 30fps), sync offset configurable respecto a screen
- [x] (P0) `Recorder`: escribir `screen.mov` (resolución nativa), escribir `camera.mov`, escribir `system_audio.m4a` y `mic_audio.m4a`, registrar sync offsets en metadata
- [x] (P0) Hotkeys start/stop/pause + UI mínima

---

## Épica C — Telemetría cursor/clicks/keys
- [x] (P0) `TelemetryRecorder`: move throttled (30-60 Hz), down/up (clicks), scroll opcional
- [x] (P0) Guardar `telemetry/cursor.jsonl`
- [x] (P1) Sincronización y validación: alineación con timeline (debug overlay)
- [x] (P1) Captura de keystrokes (opt-in): registrar teclas/shortcuts presionados, guardar en `telemetry/keys.jsonl`, útil para tutoriales. **Nota:** requiere permiso de Accessibility

---

## Épica D — Editor MVP (Timeline + Canvas)
> **Dependencia:** Esta épica debe desarrollarse en paralelo con **Épica F (Preview Engine)**. Sin preview funcional, el editor es difícil de desarrollar y probar.

- [x] (P0) `EditorModel` no destructivo: trim in/out, cut segments (modelo basado en segments, no edits)
- [x] (P0) Timeline UI simple: selección de rango, split/delete
- [x] (P0) Canvas layout presets: PiP, side‑by‑side
- [x] (P0) Background: solid color, image background (fit/fill)
- [x] (P0) Formato: 16:9 y 9:16

---

## Épica E — Overlays (flechas, líneas, rectángulos, texto)
- [x] (P0) Definir `overlays[]` en `project.json` + helpers CRUD
- [x] (P0) Canvas overlay editing: drag + resize handles, inspector de estilo (stroke width, color, shadow)
- [x] (P0) Render de overlays en preview
- [x] (P0) Soporte de timing start/end por overlay
- [ ] (P1) Animaciones: fade in/out, "draw-on" (opcional)

---

## Épica F — Preview Engine
> **Nota:** Iniciar en paralelo con Épica D. El preview es esencial para desarrollar y probar el editor.

- [x] (P0) `PreviewEngine`: playback con edits aplicados, seek/play/pause
- [x] (P0) Generación de proxies (para archivos grandes): proxy de baja resolución para preview fluido, usar original solo en export
- [ ] (P1) Cache de thumbnails / waveform (mejora UX)

---

## Épica G — Transcripción & Captions (offline)
- [x] (P0) `TranscriptionEngine` job: extraer audio a formato STT, ejecutar STT offline (Whisper.cpp), generar `transcript.json` + `.srt` + `.vtt`
- [ ] (P1) Captions overlay en preview
- [ ] (P1) Burn‑in captions en export

---

## Épica H — Export Engine
- [x] (P0) `ExportEngine` job: render final con trims/cuts/layouts/overlays, downscale de resolución nativa a 1080p, preset `web_1080_h264`
- [ ] (P0) Progreso + cancelación + logs estructurados
- [x] (P1) Presets adicionales: HEVC, calidad alta (4K)
- [ ] (P1) Export GIF (si se decide)

---

## Épica I — Cursor Zoom (auto-zoom por clicks)
- [ ] (P1) Parser de telemetría: detectar clicks "importantes", agrupar eventos por ventanas temporales
- [ ] (P1) Generador de "zoom plan": keyframes con easing, límites (no marear; min/max zoom)
- [ ] (P1) Render de zoom en preview/export
- [ ] (P1) Controles: intensidad / on/off por sección

---

## Épica J — Library/UX polish
- [ ] (P1) Biblioteca de proyectos: búsqueda por nombre/tags, ordenamiento
- [ ] (P1) Autosave consistente (actualiza `updated_at`)
- [ ] (P1) Atajos globales, menubar status (opcional)
- [ ] (P1) Reportes de crash / logging

---

## Épica K — IA preparada (Feature flags)
- [ ] (P1) Definir interfaz `AIService` + `Suggestion` + `AssetRef`
- [ ] (P1) Local "smart edits": sugerir cortes por silencios, capítulos desde transcript
- [ ] (P2) Cloud provider: generar background asset por prompt, aplicar a canvas como asset
- [ ] (P2) Labs: estilo frame‑a‑frame (experimental), reemplazo de fondo en cámara (experimental)

---

## Épica L — Testing & QA
> **Nota:** Estas tasks deben ejecutarse en paralelo con el desarrollo de cada épica correspondiente.

- [ ] (P0) Tests de integración para `CaptureEngine`: verificar captura de pantalla + audio, verificar sync entre pistas
- [ ] (P0) Tests de `ProjectStore`: crear/leer/actualizar proyectos, migración de schema
- [ ] (P0) Tests de export: verificar audio sync en output, verificar aplicación de trims/cuts, verificar overlays renderizados
- [ ] (P1) Tests de `PreviewEngine`: seek accuracy, playback con edits aplicados
- [ ] (P1) Tests de `TranscriptionEngine`: accuracy básica de transcripción, formato correcto de SRT/VTT
- [ ] (P1) Test de regresión de audio drift: grabación de 10+ minutos sin drift

---
