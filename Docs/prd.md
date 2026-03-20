# PRD — macOS Local‑First Screen Recorder & Editor
**Nombre clave:** Project Studio  
**Plataforma:** macOS (mac-first)  
**Modelo:** Local‑first (sin nube por defecto)

## 1) Resumen
Construir una aplicación para macOS que permita:
- Grabar pantalla (display/ventana/app) con audio del sistema y micrófono.
- Grabar cámara frontal como pista separada.
- Realizar postproducción ligera (cortes, trims, layouts, fondos, overlays).
- Generar transcripción y subtítulos (offline).
- Exportar a presets comunes (MP4 H.264/HEVC; landscape/portrait).
- (Futuro) Experimentos de IA: sugerencias, assets generados, mejoras visuales opt‑in.

El objetivo es una experiencia cercana a **Screen Studio** (calidad local + edición rápida), con espacio para crecer hacia funciones “AI‑assisted” sin comprometer el MVP.

---

## 2) Usuarios y casos de uso
- **Creadores técnicos:** demos, tutoriales, walkthroughs.
- **Equipos internos:** status updates asíncronos.
- **Soporte/CS:** reproducción de bugs y guías.

Casos de uso principales:
1) “Grabo mi pantalla + cámara + audio del sistema, recorto, pongo subtítulos, exporto.”
2) “Cambio el layout (PiP/side‑by‑side) después de grabar.”
3) “Agrego flechas, recuadros y texto para señalar elementos.”
4) “Exporto versión 16:9 y otra 9:16 del mismo proyecto.”

---

## 3) Flujo de usuario (navegación)

> **Nota para el dev:** No hay wireframes rígidos. Se busca una UI minimalista y propuestas creativas. Este flujo describe la experiencia esperada.

```
┌─────────────────────────────────────────────────────────────────┐
│                        APP LAUNCH                               │
│                                                                 │
│    ┌──────────────┐              ┌────────────────────────┐    │
│    │ + Nuevo Video│              │   Lista de Proyectos   │    │
│    └──────┬───────┘              │   - Proyecto 1         │    │
│           │                      │   - Proyecto 2         │    │
│           ▼                      │   - ...                │    │
│    ┌──────────────┐              └──────────┬─────────────┘    │
│    │ Menú Flotante│                         │                  │
│    │ de Grabación │                         │                  │
│    └──────┬───────┘                         │                  │
│           │                                 │                  │
│           ▼                                 │                  │
│    ┌──────────────┐                         │                  │
│    │  Grabando... │                         │                  │
│    │  (flotante)  │                         │                  │
│    └──────┬───────┘                         │                  │
│           │                                 │                  │
│           ▼                                 ▼                  │
│    ┌────────────────────────────────────────────────────┐      │
│    │                    EDITOR                          │      │
│    │  ┌─────────────────────────────────────────────┐  │      │
│    │  │              Preview Video                  │  │      │
│    │  └─────────────────────────────────────────────┘  │      │
│    │  ┌─────────────────────────────────────────────┐  │      │
│    │  │              Timeline                       │  │      │
│    │  └─────────────────────────────────────────────┘  │      │
│    │  [Herramientas] [Filtros] [Guardar] [Exportar]    │      │
│    └────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

### 3.1 Pantalla inicial
- Opción prominente: **"+ Nuevo Video"**
- Lista de **proyectos existentes** (ordenados por última modificación)
- Click en proyecto → abre Editor

### 3.2 Menú flotante de grabación
Al iniciar nuevo video, aparece menú flotante con:
- **Fuente de captura:** pantalla completa / ventana / área personalizada
- **Audio:** sistema on/off, micrófono on/off
- **Cámara:** on/off (si está disponible)
- **Botón "Grabar"**

### 3.3 Durante grabación
- **Indicador flotante** (o en menu bar) mostrando:
  - Tiempo transcurrido
  - Estado de audio/cámara
  - **Botón "Detener"**
- Al detener → crea proyecto automáticamente → abre Editor

### 3.4 Editor (post-producción)
- **Preview** del video con controles play/pause/seek
- **Timeline** para navegación y edición
- **Acciones disponibles:**
  - Cortar/eliminar segmentos
  - Aplicar herramientas (overlays, zoom, etc.)
  - Cambiar layout (PiP, side-by-side)
  - Ajustar fondo
- **Guardar proyecto** (para continuar después)
- **Exportar video** (genera MP4 final)

---

## 4) Principios del producto
- **Local por defecto:** archivos permanecen en tu máquina.
- **No destructivo:** la edición se guarda como `project.json` (metadatos), no re‑escribe fuentes.
- **Pistas separadas:** screen, camera, system audio, mic audio y telemetría de cursor/clicks.
- **UI fluida:** "preview first"; export es un job asíncrono.
- **Desacople UI/Engine:** el motor en Swift expone una API estable; el frontend puede evolucionar (SwiftUI hoy; puente WebView/IPC mañana).
- **System audio nativo:** usamos `ScreenCaptureKit` (macOS 13+) para capturar audio del sistema sin necesidad de drivers virtuales externos (BlackHole, Loopback, etc.).

---

## 5) Alcance MVP (v1)
### 5.1 Recording Studio
**Inputs**
- Fuente de captura: **Display / Window / App**
- Audio: **System audio** (vía ScreenCaptureKit nativo, macOS 13+) + **Mic**
- Cámara: FaceTime/external
- Preferencias de calidad:
  - **Captura:** resolución nativa de pantalla (Retina/4K) a 60fps
  - **Cámara:** 720p o 1080p a 30fps (configurable, pista separada)
  - **Export:** downscale a 1080p por defecto, codec H.264 (v1)
  - Nota: grabar en resolución nativa permite reencuadres y zoom sin pérdida

**Durante grabación**
- Preview: mini‑monitor
- PiP básico de cámara (toggle on/off)
- Hotkeys: Start/Stop/Pause
- Indicadores: tiempo, mic on/off, system audio on/off

**Salida de grabación**
- Archivos “raw” por pista (screen, camera, audio tracks)
- Telemetría sincronizada: cursor move (throttled), click down/up, scroll (opcional)

---

### 5.2 Project Library (lista de proyectos)
- Cada proyecto tiene:
  - **Nombre** (editable)
  - **Fecha de creación**
  - **Última actualización** (auto)
  - **Tags** (multi‑tag)
  - Thumbnail / duración
- Acciones: crear desde grabación, renombrar, tags, duplicar, eliminar (con confirmación)
- [x] UI: vista lista/grid con thumbnail, nombre, fecha, duración, tags visibles.
- [x] UI: edición de tags (multi-tag) en biblioteca.
- [x] UI: búsqueda por nombre y filtro por tags.

---

### 5.3 Editor (Timeline + Canvas)
**Edición no destructiva**
- Trim in/out
- Split + delete segment
- Reordenar segmentos (opcional v1.1)
- Speed presets (opcional v1.1)

**Layouts post‑grabación**
- [x] Presets: PiP, side‑by‑side
- Posición/escala cámara en canvas
- Background: color sólido / imagen (v1), blur (v1.1)
- Formatos: 16:9 y 9:16

**Overlays (anotaciones) — MVP**
- Flecha
- Rectángulo/redondeado
- Línea
- Texto / callout
- Timing por overlay (start/end), transform (x,y,scale,rotation), estilo (stroke/fill)

---

### 5.4 Transcript & Captions (offline)
- STT offline (post‑record) con job asíncrono:
  - Transcript con timestamps
  - Export: `.txt`, `.srt`, `.vtt`
- Captions en preview (opcional v1.1)
- Burn‑in captions en export (v1.1)

---

### 5.5 Export
- Presets:
  - MP4 H.264 “Web 1080p”
  - MP4 HEVC “High” (v1.1)
  - Portrait 9:16 (v1)
- Export como **job**:
  - progreso, cancelación, logs
- Output: archivo final + revelar en Finder

---

## 6) Fuera de alcance v1 (explícito)
- Editor avanzado tipo NLE multi‑track complejo.
- Colaboración cloud / links shareables.
- IA generativa frame‑a‑frame (cartoon/style transfer) — se reserva a “Labs”.

---

## 7) Requerimientos no funcionales
- **Compatibilidad:** macOS 13+ (Ventura) — requerido para `SCStreamConfiguration.capturesAudio` (system audio nativo sin drivers externos).
- **Estabilidad:** 10 min 1080p sin drift audio.
- **Performance:** sin dropped frames notable en Apple Silicon (M1+).
- **Privacidad:** no se sube nada sin consentimiento explícito.
- **Recoverability:** si falla export/transcribe, el proyecto no se corrompe.

---

## 8) Fases y entregables
### Fase 0 — Fundaciones
- Repo + módulos (EngineKit, App UI)
- Esquema de proyecto `project.json`
- Job system (export/transcribe)

### Fase 1 — Recording MVP
- Selección Display/Window/App
- Tracks separadas + telemetría

### Fase 2 — Editor MVP
- [x] Timeline: trim/split/delete
- [x] Undo/Redo (Cmd+Z / Cmd+Shift+Z)
- Layout presets + backgrounds
- Overlays básicos

### Fase 3 — Transcript + Export
- STT offline + captions export
- Export presets + progreso/cancelación

### Fase 4 — Pulido
- Hotkeys, UX, biblioteca de proyectos (tags/updated_at)
- Crash logging y métricas básicas

### Fase 5 — Experimentos IA (opt‑in)
- Auto-cortes por silencios
- Capítulos/títulos desde transcript
- Generación de assets (fondos) por prompt (cloud provider)

---

## 9) Documentos relacionados

Este PRD es el documento principal del proyecto. Se acompaña de:

| Documento | Descripción | Cuándo consultarlo |
|-----------|-------------|-------------------|
| **tech-spec.md** | Arquitectura técnica, API del engine, schemas (`project.json`, telemetry), estructura de carpetas, sistema de jobs, sincronización de pistas, proxies, export presets. | Para entender **cómo** implementar cada feature. |
| **tasks.md** | Backlog de desarrollo organizado por épicas (A-L), con priorización P0/P1/P2 y dependencias entre épicas. | Para planificar sprints y ver **qué** construir en cada fase. |

### Flujo de lectura recomendado
1. **PRD (este documento)** — Entender el producto, usuarios y alcance MVP
2. **tech-spec.md** — Profundizar en arquitectura y decisiones técnicas
3. **tasks.md** — Planificar implementación por épicas

---

## 10) Criterios de aceptación (MVP)
- [x] Crear proyecto desde grabación con: screen + camera + mic + system audio (si aplica) + telemetry con fuente visual (display/window/app) y preview de captura.
- [x] Editar: trim + split/delete + overlay (flecha + texto) + background + animación visible en preview con edits aplicados.
- [x] Timeline: navegación (click playhead, drag selección, zoom, scroll).
- [x] Generar transcript offline y exportar `.srt`.
- [x] Exportar MP4 1080p 16:9 y 9:16 con layout post‑grabación aplicado y toggle de formato con preview.
- [x] Biblioteca muestra proyectos con **nombre**, **tags** y **última actualización** correctamente.
- [x] Timeline básico con tracks (screen/camera/audio) y playhead visible.
- [x] Preview: reproductor de video con aspect ratio correcto y frame visible al pausar.
- [x] Preview: controles play/pause/stop con scrubber y tiempo actual.
- [x] Preview: overlays en tiempo real, layout (PiP), zoom, y captions renderizados en el preview.

---
