# Tech Spec — Engine/Project Model/API
Este documento describe una implementación recomendada para un producto **mac-first**, con un motor (engine) en Swift desacoplado de la UI.

## 1) Arquitectura por capas
### 1.1 Módulos
- **EngineKit (Swift Package / Framework)**
  - `CaptureEngine`: captura pantalla (Display/Window/App) + audio system/mic
  - `CameraEngine`: captura cámara (track separada)
  - `TelemetryRecorder`: cursor/clicks con timestamps
  - `ProjectStore`: crea/abre/guarda proyectos (carpetas + `project.json`)
  - `PreviewEngine`: reproduce con edits (no destructivo)
  - `ExportEngine`: render/export asíncrono (jobs)
  - `TranscriptionEngine`: STT offline vía **Whisper.cpp** (job)
  - `OverlayEngine`: primitives vectoriales (flecha, rect, línea, texto)
  - `JobQueue`: jobs con progreso/cancelación/logs

- **App UI**
  - Implementación inicial: SwiftUI.
  - Futuro: Web UI en `WKWebView` usando un bridge o IPC.

### 1.2 Principio clave
La UI **NO** manipula buffers; solo:
- inicia/detiene grabación
- edita un modelo (`project.json`) vía APIs / patches
- muestra preview y controla export/transcribe jobs

---

## 2) Desacople UI ↔ Engine (para frontends futuros)
### 2.1 Contrato de API (alto nivel)
**Recording**
- `startRecording(config) -> RecordingSession`
- `pauseRecording(sessionId)`
- `resumeRecording(sessionId)`
- `stopRecording(sessionId) -> RecordingResult`

**Projects**
- `createProject(from: RecordingResult, name: String?, tags: [String]?) -> ProjectId`
- `listProjects(filter/sort) -> [ProjectSummary]`
- `getProject(projectId) -> Project`
- `updateProject(projectId, patch) -> Project`
- `renameProject(projectId, name)`
- `setTags(projectId, tags)`

**Preview**
- `openPreview(projectId) -> PreviewSession`
- `seek(previewSession, time)`
- `play/pause(previewSession)`
- `subscribePreviewEvents(previewSession) -> AsyncStream<Event>`

**Jobs**
- `startExport(projectId, preset) -> JobId`
- `startTranscription(projectId, options) -> JobId`
- `getJob(jobId) -> JobStatus`
- `cancelJob(jobId)`
- `subscribeJobEvents(jobId) -> AsyncStream<JobEvent>`

### 2.2 Bridge (si se usa Web UI)
- Variante simple: `WKWebView` + `WKScriptMessageHandler`
  - JS → Swift: comandos
  - Swift → JS: eventos (job progress, preview state)
- Variante robusta (v2): XPC/IPC para UI externa

---

## 3) Estructura de proyecto (carpetas)
Ruta base sugerida: `~/Library/Application Support/ProjectStudio/Projects/`

Por proyecto (UUID):
```
Projects/<project_id>/
  project.json
  sources/
    screen.mov          # Resolución nativa (ej. 2880x1800 Retina)
    camera.mov          # 720p o 1080p
    system_audio.m4a
    mic_audio.m4a
  telemetry/
    cursor.jsonl        # Movimientos y clicks
    keys.jsonl          # Keystrokes (opt-in)
  cache/
    thumbnails/
    waveforms/
  proxies/              # Videos de baja resolución para preview fluido
    screen_proxy.mov    # ~720p para preview rápido
    camera_proxy.mov
  renders/
    export_YYYYMMDD_HHMM.mp4
  transcript/
    transcript.json
    captions.srt
    captions.vtt
```

### 3.1 Metadatos de proyecto
Se derivan de `project.json` (y se indexan en DB ligera opcional):
- `name`
- `created_at`
- `updated_at`
- `tags`
- `duration`
- `thumbnail_path`

---

## 4) `project.json` (modelo no destructivo)
### 4.1 Esquema (borrador)
```json
{
  "schema_version": 1,
  "project_id": "UUID",
  "name": "My Recording",
  "tags": ["client:acme", "demo"],
  "created_at": "2026-01-18T00:00:00Z",
  "updated_at": "2026-01-18T00:00:00Z",
  "sources": {
    "sync_reference": "screen",
    "screen": {
      "path": "sources/screen.mov",
      "fps": 60,
      "size": {"w": 2880, "h": 1800},
      "sha256": "abc123...",
      "size_bytes": 524288000
    },
    "camera": {
      "path": "sources/camera.mov",
      "fps": 30,
      "size": {"w": 1280, "h": 720},
      "sync_offset_ms": 0,
      "sha256": "def456...",
      "size_bytes": 104857600
    },
    "audio": {
      "system": {
        "path": "sources/system_audio.m4a",
        "sync_offset_ms": 0,
        "sha256": "ghi789...",
        "size_bytes": 10485760
      },
      "mic": {
        "path": "sources/mic_audio.m4a",
        "sync_offset_ms": 0,
        "sha256": "jkl012...",
        "size_bytes": 10485760
      }
    },
    "telemetry": {
      "cursor": {"path": "telemetry/cursor.jsonl"},
      "keys": {"path": "telemetry/keys.jsonl"}
    }
  },
  "timeline": {
    "duration": 95.5,
    "tracks": [
      {
        "id": "00000000-0000-0000-0000-000000000001",
        "name": "Recording",
        "type": "primary",
        "isMuted": false,
        "isLocked": false,
        "volume": 1.0,
        "opacity": 1.0,
        "clips": [
          {
            "id": "clip-1",
            "timelineIn": 0,
            "content": {
              "recording": {
                "takeId": "take-uuid",
                "sourceIn": 0.8,
                "sourceOut": 35.2
              }
            },
            "speed": 1.0
          },
          {
            "id": "clip-2",
            "timelineIn": 34.4,
            "content": {
              "image": { "path": "assets/slide1.png", "duration": 5.0 }
            },
            "speed": 1.0,
            "opacity": 1.0,
            "position": { "x": 0, "y": 0, "w": 1, "h": 1 }
          },
          {
            "id": "clip-3",
            "timelineIn": 39.4,
            "content": {
              "recording": {
                "takeId": "take-uuid",
                "sourceIn": 39.9,
                "sourceOut": 95.9
              }
            },
            "speed": 1.0
          }
        ]
      },
      {
        "id": "audio-track-uuid",
        "name": "Background Music",
        "type": "audio",
        "isMuted": false,
        "isLocked": false,
        "volume": 0.3,
        "opacity": 1.0,
        "clips": [
          {
            "id": "music-1",
            "timelineIn": 0,
            "content": {
              "audio": { "path": "assets/music.mp3", "duration": 95.5, "sourceIn": 0 }
            },
            "speed": 1.0,
            "volume": 0.3
          }
        ]
      }
    ]
  },
  "canvas": {
    "format": {"aspect": "16:9", "w": 1920, "h": 1080},
    "background": {"type": "solid", "value": "#0B0B0D"},
    "layout": {
      "type": "pip",
      "camera": {"x": 0.74, "y": 0.72, "w": 0.22, "h": 0.22, "cornerRadius": 18}
    }
  },
  "overlays": [
    {
      "id": "UUID",
      "type": "arrow",
      "start": 12.4,
      "end": 16.8,
      "transform": {"x": 0.35, "y": 0.42, "scale": 1.0, "rotation": 0},
      "style": {"stroke": "#FFFFFF", "strokeWidth": 6, "shadow": true}
    },
    {
      "id": "UUID",
      "type": "text",
      "start": 12.4,
      "end": 18.0,
      "transform": {"x": 0.38, "y": 0.48, "scale": 1.0, "rotation": 0},
      "style": {"font": "SF Pro", "size": 36, "color": "#FFFFFF", "bg": "rgba(0,0,0,0.4)" },
      "text": "Click aquí"
    }
  ],
  "captions": {
    "language": "es",
    "srt_path": "transcript/captions.srt",
    "vtt_path": "transcript/captions.vtt"
  }
}
```

### 4.2 Patches
Recomendado: aplicar cambios como JSON Patch (RFC6902) o comandos atómicos equivalentes:
- renombrar, añadir overlay, cambiar layout, etc.

---

## 5) Telemetría de cursor/clicks
Formato recomendado: **JSONL** (una línea por evento) para streaming y fácil debug.

Ejemplos:
```json
{"t":0.033,"type":"move","x":1023,"y":812}
{"t":0.512,"type":"down","button":0,"x":1104,"y":790}
{"t":0.602,"type":"up","button":0,"x":1104,"y":790}
{"t":0.620,"type":"scroll","dx":0,"dy":-1.2}
```

Notas:
- `t` = tiempo desde inicio de grabación, en segundos.
- `move` debe ir **throttled** (ej. 30–60 Hz) para tamaño razonable.
- Guardar también `display_id` o `space` si es multi‑monitor (opcional v1.1).

---

## 6) Overlays (anotaciones)
### 6.1 Tipos (MVP)
- `arrow`
- `rect`
- `line`
- `text`

### 6.2 Render
- Vectorial preferente (CoreGraphics/Metal) para escalar a 4K sin pérdida.
- Animaciones simples (fade in/out) se pueden describir en modelo.

---

## 7) JobQueue (export/transcribe/AI)
Requisitos:
- Progreso (0..1), estado (queued/running/success/fail/canceled)
- Cancelación segura
- Persistencia mínima (reanudar cola tras reinicio opcional)
- Logs por job para debug

### 7.1 Estructura de Job Status
```json
{
  "job_id": "UUID",
  "type": "export|transcribe|proxy_generation",
  "project_id": "UUID",
  "status": "queued|running|success|fail|canceled",
  "progress": 0.75,
  "started_at": "2026-01-18T10:00:00Z",
  "completed_at": null,
  "error": null
}
```

### 7.2 Estructura de errores
```json
{
  "job_id": "UUID",
  "status": "fail",
  "error": {
    "code": "AUDIO_SYNC_DRIFT",
    "message": "Audio drift detected: 150ms at 5:30",
    "details": {
      "drift_ms": 150,
      "timestamp_sec": 330
    },
    "recoverable": true
  }
}
```

Códigos de error comunes:
- `AUDIO_SYNC_DRIFT`: Desincronización de audio detectada
- `SOURCE_FILE_MISSING`: Archivo fuente no encontrado
- `SOURCE_FILE_CORRUPTED`: Checksum no coincide
- `INSUFFICIENT_DISK_SPACE`: Espacio insuficiente para export
- `TRANSCRIPTION_FAILED`: Error en STT
- `EXPORT_ENCODING_ERROR`: Error de codificación de video

---

## 8) Export presets
- `web_1080_h264`
- `high_1080_hevc` (v1.1)
- `high_4k_hevc` (v1.1)
- `portrait_1080_h264`

Cada preset define:
- resolución de salida (downscale desde nativa si es necesario)
- fps
- codec
- bitrate target
- si se queman captions

### 8.1 Ejemplo de preset
```json
{
  "preset_id": "web_1080_h264",
  "name": "Web 1080p (H.264)",
  "output": {
    "width": 1920,
    "height": 1080,
    "fps": 60,
    "codec": "h264",
    "bitrate_mbps": 8,
    "audio_bitrate_kbps": 192
  },
  "options": {
    "burn_captions": false,
    "include_cursor_highlight": true
  }
}
```

---

## 9) Sincronización de pistas

### 9.1 Estrategia de sync
- **Referencia:** La pista `screen` es la referencia de tiempo (sync_reference)
- **Offsets:** Cada pista adicional puede tener un `sync_offset_ms` para ajuste fino
- **Timestamps:** Todos los timestamps en telemetría y edits son relativos al inicio de `screen`

### 9.2 Detección de drift
Durante export, verificar que el audio no se desincronice:
- Comparar duración de pistas de audio vs video
- Alertar si drift > 100ms
- Permitir corrección manual via `sync_offset_ms`

---

## 10) Generación de Proxies

### 10.1 Propósito
Los proxies permiten preview fluido de archivos de alta resolución (Retina/4K) sin saturar GPU/CPU.

### 10.2 Especificaciones
```json
{
  "proxy": {
    "max_width": 1280,
    "max_height": 720,
    "fps": 30,
    "codec": "h264",
    "bitrate_mbps": 2
  }
}
```

### 10.3 Flujo
1. Al crear proyecto, generar proxies como job en background
2. Preview usa proxies si existen
3. Export siempre usa fuentes originales
4. Si el usuario modifica sync offsets, regenerar proxies afectados

---

## 11) Transcripción con Whisper.cpp

### 11.1 Decisión técnica
Usar **Whisper.cpp** para transcripción offline:
- Repo: https://github.com/ggerganov/whisper.cpp
- Swift bindings disponibles
- Modelos recomendados: `base` o `small` (balance velocidad/calidad)
- Ejecución 100% local, sin dependencia de red

### 11.2 Flujo de transcripción
1. Extraer audio del proyecto (preferir pista `mic` si existe)
2. Convertir a formato compatible (16kHz WAV mono)
3. Ejecutar Whisper.cpp como job en background
4. Generar `transcript.json` con timestamps por palabra/segmento
5. Exportar a `.srt` y `.vtt`

### 11.3 Estructura de transcript.json
```json
{
  "language": "es",
  "duration_sec": 120.5,
  "segments": [
    {
      "id": 0,
      "start": 0.0,
      "end": 3.2,
      "text": "Hola, en este video vamos a ver..."
    },
    {
      "id": 1,
      "start": 3.2,
      "end": 6.8,
      "text": "cómo configurar el proyecto desde cero."
    }
  ]
}
```

### 11.4 Modelos incluidos
- Bundlear modelo `base` (~150MB) por defecto
- Permitir descarga opcional de modelos más grandes (`small`, `medium`)

---

## 12) IA "preparada" (no bloquea MVP)
Definir una interfaz:
- `AIService.generateAsset(prompt) -> AssetRef`
- `AIService.suggestEdits(project) -> [Suggestion]`
y dejarlo detrás de feature flags.

Recomendado v1.x (local): autocortes por silencios, capítulos desde transcript.

---
