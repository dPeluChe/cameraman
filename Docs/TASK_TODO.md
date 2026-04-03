# Backlog de Tareas Pendientes

> Actualizado: 2026-04-02
> Solo features y mejoras NO implementadas. Para trabajo completado ver `TASK_COMPLETED/`.

---

## 0. Bugs Conocidos (Prioridad Alta)

- [x] ~~**Export no incluye cambios de PiP editados**~~ RESUELTO: save before export + MaskedVideoCompositor en export

- [x] ~~**Sidebar overflow al abrir Background/Zoom/Overlays**~~ RESUELTO: layout compacto vertical, controles redimensionados

- [x] ~~**Timeline no funcional**~~ RESUELTO: playhead sync bidireccional, split/delete/trim conectados, import de assets

- [x] ~~**Track mute toggles no afectan playback**~~ RESUELTO: AVMutableAudioMix para audio + video composition rebuild para video. Funciona en preview y export.

- [x] ~~**Mic audio no se graba a veces:**~~ RESUELTO: MicAudioRecorder valida formato (sampleRate/channelCount > 0) antes de iniciar; retry automatico con 300ms delay si formato invalido.

- [x] ~~**"Publishing changes from within view updates" residual:**~~ RESUELTO: BackgroundControlsView.updateSelectedColor() wrapeado con Task { @MainActor in }.

---

## 1. Motores Reales (Prioridad Alta)

- [ ] **Integracion Whisper.cpp real:**
    - `TranscriptionEngine` actualmente devuelve texto simulado.
    - Integrar `whisper.cpp` (o SwiftWhisper) para transcripcion offline real.

- [ ] **Preview de grabacion en vivo:**
    - Selector de fuentes muestra capturas estaticas.
    - Implementar stream ligero de ScreenCaptureKit para vista previa en movimiento.

- [x] ~~**Audio drift detection:**~~ RESUELTO: AudioDriftDetector compara duraciones video vs system/mic audio, genera DriftReport con drift en ms y flag hasSignificantDrift (>100ms).

## 2. Calidad y Estabilidad (Prioridad Media)

- [x] ~~**Concurrencia estricta (Swift 6):**~~ RESUELTO: EngineKit compila con `-strict-concurrency=complete` sin warnings.

- [x] ~~**Reparacion de tests unitarios**~~ RESUELTO: tests actualizados para nueva API de Project init + mediaItems.

- [x] ~~**Optimizacion de recursos criticos (pre-release):**~~ RESUELTO: Task leaks, observer leaks, thumbnail LRU, waveform Canvas, project cache, deferred generation

- [ ] **Validacion de performance (larga duracion):**
    - No probado con videos > 1 hora.

- [x] ~~**SHA256 real para source files:**~~ RESUELTO: CryptoKit SHA256 streaming (64KB chunks) + fileSize reales. 8 placeholders eliminados.

- [x] ~~**Fix errores `onChange(of:initial:_:)` en App:**~~ RESUELTO: 12 instancias convertidas de API macOS 14 a macOS 13.

## 3. Features del Editor — Prioridad Alta (Next Up)

- [x] ~~**Auto-zoom desde cursor telemetry:**~~ RESUELTO: DwellDetector + ZoomSuggestionEngine + timeline markers con accept/reject individual + auto-apply zoom plan + rendering en MaskedVideoCompositor. 18 unit tests.

- [x] ~~**GIF export:**~~ RESUELTO: UI de opciones GIF (fps, tamano, loop) en ExportView; GIFExportOptions conectado al GIFExportSession existente.

- [x] ~~**Posicion de camara por segmento (split → reposicionar PiP):**~~ RESUELTO: auto-override al drag, per-segment en preview + export, instrucciones contiguas, autosave.

- [x] ~~**Camera border (color + ancho):**~~ RESUELTO: borderWidth/borderColor en CameraPosition, 10 presets de color, rendering via CGPath en compositor con cache.

- [x] ~~**Per-segment audio (volumen/mute):**~~ RESUELTO: volume/audioMuted en Segment, AudioMixBuilder con setVolumeRamp per-segment, UI en SegmentInspectorBar.

- [x] ~~**Telemetry recording integrado:**~~ RESUELTO: TelemetryRecorder en Recorder start/stop, captureTelemetry=true default, cursor.jsonl movido al proyecto.

- [x] ~~**Autosave:**~~ RESUELTO: scheduleAutosave() con 1s debounce despues de cada edicion via ProjectLibrary.

## 3a. Features del Editor — Pendientes de esta sesion

- [ ] **Zoom animation tuning:**
    - Hold duration, velocidad de zoom in/out, transiciones suaves entre puntos.
    - El zoom-out entre dos puntos se siente abrupto; evaluar blend o crossfade.
- [ ] **Toast de "proyecto guardado":**
    - Notificacion visual breve al hacer autosave exitoso.
- [ ] **UI del export flow:**
    - Ventana de opciones se descuadra.
    - Doble seleccion de path para guardar.
    - Alert innecesario despues del export.
- [ ] **Separar archivos >400 LOC:**
    - 6 archivos App + 14 EngineKit superan 400 lineas.
    - Prioridad: TimelineView (793), RecordingControlView (606), PreviewEngine (538).
- [ ] **Noise gate / echo cancellation en mic:**
    - Filtrar audio de bocinas capturado por el mic.
    - Voice activity detection para grabar mic solo con voz.
- [ ] **Zoom auto-apply con toggle para desactivar:**
    - Actualmente auto-aplica; agregar toggle en Zoom controls para desactivar globalmente.

## 3b. Features del Editor — Prioridad Media

- [x] ~~**Drag para reposicionar media items en timeline:**~~ RESUELTO: DragGesture con feedback visual en vivo; actualiza timelineIn al soltar.
- [ ] **Image overlays visibles en preview/export:**
    - MediaItem tipo image se importa pero no se renderiza aun (necesita CALayer + animationTool).
- [ ] **Reordenar segmentos en timeline (v1.1)**
- [x] ~~**Speed presets en timeline (v1.1):**~~ RESUELTO: SegmentInspectorBar con picker (0.25x-4x), speed badge en segmentos, updateSegmentSpeed() en editor.
- [x] ~~**Background blur (v1.1)**~~ RESUELTO: Compositor aplica CIGaussianBlur al screen como fondo cuando backgroundType == "blur".
- [ ] **Captions visibles en preview (mejorar)**
- [x] ~~**Duplicar proyecto**~~ RESUELTO: deep copy con nuevo ID + "(Copy)" en nombre. Context menu en sidebar.
- [x] ~~**Export formato `.txt` para transcript**~~ RESUELTO: exportCaptions() soporta SRT/VTT/TXT con NSSavePanel.
- [ ] **Thumbnails al hover en scrubber del preview**
- [x] ~~**Volume slider por track (en vez de solo mute on/off)**~~ RESUELTO: sliders compactos en label del timeline, rango 0–3x, mute icono speaker/eye por tipo de track

## 3c. Features del Editor — Inspirados en OpenScreen (Polish Visual)

- [x] ~~**Border radius + shadow en video:**~~ RESUELTO: modelo + UI + compositor (CIBlendWithMask para corner radius, padding scale+translate).
- [x] ~~**Background gradients:**~~ RESUELTO: modelo + UI + compositor (CILinearGradient rendering).
- [ ] **Motion blur en zoom transitions:**
    - Blur proporcional a la velocidad de movimiento durante zoom in/out.
    - Implementar via `CIMotionBlur` filter o Metal shader.
    - Aplicar en `MaskedVideoCompositor` / `PreviewComposition` durante zooms.
- [x] ~~**Padding configurable:**~~ RESUELTO: modelo + UI + compositor (scale down + translate center).
- [ ] **Crop interactivo con aspect ratio presets:**
    - Dialog visual con drag + inputs numericos + lock de aspect ratio (16:9, 9:16, 4:3, 1:1, 21:9).
    - Aplica crop region al source video antes de layout.

## 4. Infraestructura y Distribucion (Prioridad Baja)

- [ ] **Permisos y Entitlements para distribucion**
- [ ] **Tests automatizados de UI**
- [x] ~~**Export preset 4K HEVC (v1.1)**~~ RESUELTO: ExportPreset.ultra4kHevc (3840x2160, 60fps, 30Mbps HEVC)
- [ ] **Auto-generar proxies al crear proyecto**
- [ ] **Regenerar proxies al cambiar sync offsets**
- [x] ~~**Estimacion de tamano y tiempo de export**~~ Ya existia: estimatedFileSize + estimatedTimeRemaining en ExportViewModel

## 5. Experimentos IA (Prioridad P2 / Labs)

- [ ] **Cloud provider para generacion de assets**
- [ ] **Estilo frame-a-frame (experimental)**
- [ ] **Auto-cortes por silencios (Fase 5 PRD)**
- [ ] **Capitulos/titulos desde transcript (Fase 5 PRD)**
