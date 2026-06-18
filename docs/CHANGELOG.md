# Changelog

All notable changes to Cameraman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Nota (2026-04-18):** Las versiones fueron renumeradas hacia abajo para reflejar el estado real del producto (aún incompleto). El mapeo aplicado:
> `0.8.0 → 0.5.0` · `0.7.0 → 0.4.1` · `0.6.0 → 0.4.0` · `0.5.0 → 0.3.1` · `0.4.0 → 0.3.0` · `0.3.1 → 0.2.1` · `0.3.0 → 0.2.0` · `0.2.0 → 0.1.1` · `0.1.0 → 0.1.0`.
> Las fechas y el contenido técnico se preservaron.

## [Unreleased]

Foco: efectos extensibles en el timeline y un servidor MCP para automatización.

### Added
- **Efectos / ajustes en el timeline** — sistema extensible y no destructivo de
  *adjustments* por clip, apuntables a una **capa** (`frame` / `screen` /
  `camera` / `background` / `audio`) sobre un rango opcional. Así se puede, p. ej.,
  poner la **cámara en sepia** y el **fondo en blanco y negro** en el mismo bloque.
  Filtros de video vía CoreImage (sepia, monocromo/B&N, brillo, contraste,
  saturación, vibrance, hue, invertir, viñeta, desenfoque; cualquier `CIFilter`
  por nombre como fallback) y audio (`audioPitch` para voz grave/aguda vía
  `MTAudioProcessingTap` + `AUNewTimePitch`). Aplicado en preview **y** export.
- **Servidor MCP** (`MCPServer/`, binario `cameraman-mcp`) — expone los proyectos
  a clientes MCP (Claude Desktop/Code) por stdio JSON-RPC, reutilizando EngineKit:
  listar/ver proyectos, **grabar** (crear proyecto vacío, start/stop recording),
  **cortar/split**, **mute** de audio/video (pista y clip), **agregar** items
  (imagen/video/audio/color/texto) en un tiempo dado, y aplicar **efectos**.

## [0.6.4] - 2026-06-10

Foco: edición con clips importados, merge de proyectos y navegación del timeline.

### Added
- **Merge de proyectos** — clic derecho → *Merge Into New Project…*: crea un proyecto nuevo con el timeline de A seguido del de B (medios copiados, capítulos/overlays desplazados; los originales no se tocan). Aviso cuando los canvas tienen forma distinta.
- **Importar video al timeline** — el botón Import acepta videos (mp4/mov/m4v); cada import vive en su propia fila con color propio, **con su audio**. Chips editables: arrastrar con *snap magnético* a bordes de otros clips/playhead, recorte por bordes, **split** (⌘B o menú), posición PiP (grid 3×3, tamaños S/M/L, fullscreen), menú de orden (colocar tras la fila de arriba, mover fila arriba/abajo) y mute por fila.
- **Proyectos vacíos** — menú "+" → *New Empty Project*: canvas 16:9 en blanco para editar solo con imports; preview y export funcionan sin grabación. Se puede grabar encima después (Take 1).
- **Regla de tiempo** sobre el timeline (marcas adaptativas de 1s a 10min, clic/arrastre para mover el playhead) y **zoom recalibrado**: 100% = proyecto completo visible, +/− duplican/reducen, botón *Fit*.
- **Columna de etiquetas fija** — los nombres de las pistas ya no se desplazan con el scroll.
- Nombres por defecto distinguibles: "Jun 10 · Falcon" en vez de "Untitled Recording".
- *Check for Updates…* en el menú Help.
- **Export/Import de proyectos** — clic derecho → *Export Bundle…* genera una carpeta `.cameramanproject` portátil (solo lo esencial); "+" → *Import Project…* la trae de vuelta como proyecto nuevo. Para compartir proyectos entre equipos.
- **Control de calidad en export** — selector *Smaller file / Standard / Higher quality* y estimación de peso en vivo.

### Fixed
- **Rename/tags fallaba siempre** — el alert reseteaba el campo antes de que el guardado asíncrono lo leyera; además un editor abierto revertía el nombre vía autosave.
- **Proyectos merged con resoluciones mezcladas** — la sección con otra resolución se veía diminuta en una esquina; ahora cada frame se reajusta (pantalla y cámara PiP), en preview y export.
- El ojo de una fila de video silenciaba todas las filas; ahora cada una persiste su propio estado.
- "Show in Finder" tras exportar no abría nada (sandbox); ahora selecciona el archivo exportado.
- **El bitrate de los presets de export era decorativo** — la sesión siempre usaba HighestQuality (8 min → ~950MB) y los presets HEVC exportaban H.264. Ahora el codec y el bitrate objetivo se aplican de verdad, y la estimación de tamaño coincide con el resultado.
- Tras un split, mover la mitad nueva "estiraba" en vez de mover — los handles de recorte ahora solo aparecen en el clip seleccionado.
- Auditoría de los toggles bajo el preview: solo Zoom funcionaba — Cursor/Clicks/Keys quedaron conectados de verdad (overlay de telemetría) y los muertos se retiraron; todo agrupado en el menú **View** del timeline.

### Changed
- **Auto-zoom desactivado por defecto** (flag oculta `feature.autoZoom`) — generaba zooms inesperados al abrir proyectos; el zoom manual por segmento sigue disponible.
- Alturas mínimas: el timeline crece con sus filas, el preview no baja de 240pt y la ventana tiene piso de 1080×720.

## [0.6.3] - 2026-06-09

Foco: experiencia de permisos, robustez de grabación y pulido del selector/UX.

### Added
- **Paso 0: gate de permisos** en la ventana de grabación — exige Grabación de pantalla + Cámara + Micrófono antes de poder elegir fuente, con instrucciones por permiso, botón **Grant Permissions** (pide los 3 en secuencia) y **Quit & Reopen** de un clic. Cámara/micro al final no requieren reinicio; Screen Recording sí (regla de macOS).
- **Identidad de build Debug distinta** — `dev.dpeluche.CameramanApp.debug`, nombre "Cameraman (Debug)" e ícono con badge naranja "DEV", para coexistir con el release.

### Fixed
- **Permiso de grabación se solicita de verdad** vía `CGRequestScreenCaptureAccess` (antes solo `SCShareableContent`, que no registraba la app en Ajustes ni re-preguntaba).
- **"Open Settings" de Cámara/Micrófono** ahora abre el panel correcto cuando el permiso está denegado.
- **Grabación fallida ya no entrega un `.mov` corrupto** — si el encoder falla a media grabación se reporta error claro en vez de "Cannot Open" en el editor.
- **Buscador del sidebar** ya no se corta (ancho mínimo + placeholder "Search").

### Changed
- Email de soporte a `support@dpeluche.dev`; "Contact Support" abre una ventana con opciones en vez de lanzar Mail directo.
- Centralizado el manejo de paneles de Ajustes en `PermissionManager`.

---

## [0.6.2] - 2026-06-03

Foco de la versión: fixes del selector de fuentes de grabación y empaque para distribución directa (Developer ID + notarización).

### Fixed
- **Tabs Windows/Apps del selector ahora funcionan** — `loadSources` no actualizaba `selectedTab`, así que los botones de tab cargaban los datos pero la lista y el resaltado se quedaban en "Display".
- **Lista de ventanas limpia** — se excluyen ventanas del escritorio, offscreen, sin título y de la propia app. Antes mezclaba capas del sistema y ventanas no visibles.
- **Lista de apps limpia** — solo aparecen apps con al menos una ventana real visible (antes se colaban daemons/agents con nombre vacío).
- **Captura de app robusta** — se elige la ventana visible más grande en lugar de la primera (que podía ser offscreen y no grababa nada).
- **`MACOSX_DEPLOYMENT_TARGET` 15.7 → 13.0** — el target exigía macOS Sequoia, bloqueando la instalación en la mayoría de Macs.

### Added
- **Preview real de la fuente** — miniatura en vivo de ventana/display (vía `SCScreenshotManager`, macOS 14+) para confirmar la fuente antes de grabar.
- **`scripts/notarize-dmg.sh`** — submit a Apple notary + staple del DMG; `build-dmg.sh` acepta `APP_PATH` para empaquetar un `.app` notarizado.

---

## [0.6.1] - 2026-05-19

Foco de la versión: security audit pre-publicación y limpieza para abrir el repo al público.

### Security
- **AppUpdater valida la URL de release** — antes de pasar `html_url` del API de GitHub a `NSWorkspace.open`, se valida que sea `https://github.com/*`. Protege contra una payload comprometida que intente colar `javascript:`, `file://` u otro dominio.
- **OSLog marcado `privacy: .private`** — `LoggingSystem.swift` redacta paths y nombres de proyecto del usuario para procesos externos que lean Console.app. Solo visible en debug con el dispositivo adjunto.
- **Entitlement `files.downloads.read-write` removido** — no se usa en código. El acceso a Downloads en navegadores externos no requiere este permiso en la app.
- **`scripts/code_sign.sh` sin paths personales** — deriva `REPO_ROOT` automáticamente, acepta `APP_PATH` override y lee el `CameramanApp.entitlements` real (antes inlineaba una copia divergente que omitía `device.camera` y `downloads.read-write`).
- **`.claude/settings.local.json` untrackeado** — config local de Claude Code con paths absolutos del usuario sale del tree y entra a `.gitignore`.

### Changed
- **Email de contacto consolidado** — `antonio@dpeluche.dev` único en app (`AppLinks.contact`), `CONTRIBUTING.md` (security disclosure) y git config local. Antes había 3 dominios distintos (`dpeluche.dev`/`iteris.tech`/`feedby.ai`).
- **Brand pública = dPeluChe Studios** — `README.md` y `docs/index.html` consolidan créditos bajo dPeluChe Studios. `LICENSE` mantiene Iteris como copyright holder legal.

---

## [0.6.0] - 2026-05-15

Foco de la versión: overlay system unificado, Help menu, donaciones y polish pre-submit.

### Added
- **Overlay system unificado** — drag para reposicionar overlays directamente en el preview; tipo `.image` (PNG/JPG/SVG/GIF animado); fade in/out con duración configurable; LRU cache de assets (16 items); chip en timeline con seek automático al abrir popover
- **Help menu** — Cameraman Help, View on GitHub, Report a Bug, Contact Support, GitHub Sponsors ♥, Donate via PayPal, Check for Updates
- **About Cameraman** — panel nativo macOS con credits clickeables (repo + sponsors)
- **Check for Updates** — verifica GitHub releases, compara semver, alerta con "Download Update / Later"
- **GitHub Sponsors** — `github.com/sponsors/dPeluChe` + `FUNDING.yml` para botón Sponsor en el repo
- **PayPal donations** — `paypal.me/dpeluche`
- **AppLinks** — enum centralizado con todas las URLs externas (fácil de actualizar al lanzar)
- **Settings scene** — `Settings { PreferencesView() }` + `SettingsLink` correcto (fix warning 53493)
- **Report a Bug** → abre `github.com/dPeluChe/cameraman/issues/new`

### Fixed
- Selection box Y-flip en overlay drag (coordenadas SwiftUI vs CG)
- Drag direction invertido en overlay
- Timeline chip desalineado respecto al playhead
- NSCursor push/pop leak en hover continuo
- O(n) LRU bump → `firstIndex(of:)` + `remove(at:)`
- Cache key de overlays no incluía type/imagePath (renders stale)
- Switch no exhaustivo en PreviewEngineTests (faltaba `.image`)

## [0.5.2] - 2026-05-12

Foco de la versión: refinamiento de UI, flujo de export reescrito, compatibilidad macOS 13 y fix de performance en preview.

### Added
- **Atajos de teclado** — `⌘E` abre el modal de Export desde cualquier proyecto cargado. `⌘N` sigue abriendo Recording.
- **Inline filename extension en Export** — el campo de filename muestra `.mp4` / `.gif` como sufijo gris junto al input. Adiós a la línea de caption separada.
- **Project Assets bar horizontal con count badge** — la antigua columna lateral de assets pasó a una barra horizontal colapsable arriba del editor. Cuando está colapsada (38pt) muestra `(n)` con la suma de takes + segmentos. Expandida (82pt) lista chips de Sources, Takes y Layers con scroll horizontal.
- **AssetChip drag affordance** — cursor `openHand` en hover + tooltip "Drag onto the timeline to add this take" para indicar que el chip es arrastrable.
- **Compat shim macOS 13** — `View.onChangeCompat` se mantiene cuando el deployment target sigue en macOS 13 pero usamos APIs de macOS 14+ (onChange de dos parámetros, onKeyPress). Sin warnings de deprecación.

### Changed
- **Export flow reescrito** — el usuario elige nombre + carpeta destino antes de exportar. El render temporal se copia automáticamente al destino final. Ya no aparece un `NSSavePanel` después del render.
  - `outputDirectory` + `outputFilename` son la fuente de verdad en `ExportViewModel`; `outputURL` se recomputa con `didSet`.
  - `finalizeExport` maneja `startAccessingSecurityScopedResource` para sandbox + logs estructurados.
  - `ExportView` envuelta en `ScrollView` con `ViewThatFits` para colapsar filas a stack vertical en ventanas angostas.
  - Botón "Play Video" pasó a `.borderedProminent` con `keyboardShortcut(.defaultAction)`. "Show in Finder" queda como secundario.
  - Path de destino muestra `~/Movies/...` en vez de solo el último componente.
- **Inspector derecho fijo a 300pt** — antes el ancho oscilaba entre 260-360 y el timeline reflowaba con cada cambio de los grids del inspector.
- **Layouts adaptivos en panel derecho** — `HStack` con frames fijos reemplazados por `LazyVGrid` con `GridItem(.adaptive(minimum:maximum:))` en BackgroundControlsView, OverlayInspector, OverlayToolbar, ProjectEditorLayoutViews, ProjectEditorPiPView, ZoomControlsView.
- **ConfigGroup sin animación de expand/collapse** — la animación del DisclosureGroup causaba jitter horizontal cuando los grids reflowaban. Comentario in-place explicando el motivo.
- **Segment labels ordinales** — en la asset bar los segmentos se etiquetan `Segment 1`, `Segment 2`, ... en vez de los primeros 4 chars del UUID.
- **Race-safe new take** — `startNewTake()` pasa `projectId` vía `NotificationCenter.userInfo`; el observer lo asigna antes de abrir la ventana de recording, eliminando la dependencia de orden con la asignación previa a `RecordingStateManager.shared.viewModel.targetProjectId`.

### Fixed
- **🔴 Spurious composition rebuilds** — `PreviewPlayerView` escuchaba `editor.objectWillChange` general, lo que disparaba un rebuild del `AVVideoComposition` por cada cambio de `showAutosaveToast`, `canUndo` o `canRedo` (ninguno afecta el preview). Una sesión corta de clicks generaba 20+ rebuilds. Ahora escucha `editor.$project` con `.removeDuplicates()` — rebuild solo cuando el Project cambia de verdad.
- **Entitlements wipe accidental** — Xcode dejó `CameramanApp.entitlements` como `<dict/>` (probablemente al tocar Signing & Capabilities). Restaurado: `app-sandbox`, `device.camera`, `device.audio-input`, `files.user-selected.read-write`, `files.downloads.read-write`. Sin esto las nuevas grabaciones bajo sandbox no hubieran tenido permisos.

### Removed
- **Dead code en panel izquierdo** — `LeftPanel` y `AssetRow` reemplazados completamente por `ProjectAssetsBar` + `AssetChip`. La barra horizontal cubre el mismo rol con mejor uso de espacio.
- **`NSSavePanel` post-export** y `revealExportInFinder()` automático en el callback de éxito (ahora solo dispara con el botón explícito "Show in Finder").

### Performance
- `DateFormatter` estático en `ProjectAssetsBar` — antes se instanciaba en cada render por take.
- Composition rebuild dedupeado: 1 rebuild por edit cluster (debounce 150ms) en vez de 2-3 spurious por autosave + 1 por undo/redo flip.

### Distribution
- **Tahoe Gatekeeper feedback** — testers en macOS 26.4.1 (Tahoe) reportaron que el `.dmg` no abre aunque tengan "Allow apps from anywhere" activado. Workaround documentado: `xattr -dr com.apple.quarantine /Applications/CameramanApp.app`. Mitigación futura: firma ad-hoc en `build-dmg.sh` (no aplicada todavía).

---

## [0.5.1] - 2026-05-06

### Branch
- `refactor/phase1-architecture` — Fase 1: descomposición de `TimelineView` y extracción del export pipeline.
- `feat/beta-build-pipeline` — pipeline universal de DMG beta + Makefile + branding (icon, wordmark, fondo del DMG).

### Added
- `RecordingSession.videoWriterFailed` / `audioWriterFailed` flags + `markVideoWriterFailed(_:)` / `markAudioWriterFailed(_:)` (idempotentes) para detectar escrituras abortadas sin spam de logs.
- **Pipeline universal de DMG beta** — `make release` ejecuta build + verify + dmg en un solo paso. Produce `dist/Cameraman-beta-X.Y.Z.B.dmg` con binario universal (arm64 + x86_64), background brandeado y drop link a `/Applications`. Targets adicionales: `build`, `build-arm`, `verify`, `dmg`, `clean`, `open-dist`, `help`.
- **Identidad visual** — AppIcon (vintage Mac con capa de Superman + waveform mouth), wordmark horizontal y background del DMG. Source files en `docs/cameraman_designs.pen` (Pencil).
- **`scripts/build-dmg.sh`** con cleanup defensivo (force-unmount de volúmenes huérfanos de runs previos, remoción de DMGs RW intermedios).
- `INFOPLIST_KEY_CFBundleDisplayName = Cameraman` — Dock/Finder muestran "Cameraman" en vez de "CameramanApp".

### Changed
- **TimelineView descompuesto** — `TimelineView.swift` de 864 → 413 LOC. Nuevas extensiones: `TimelineView+Thumbnails.swift` (106 LOC), `TimelineView+DragDrop.swift` (180 LOC), `TimelineView+EditActions.swift` (96 LOC). Métodos de zoom movidos a `TimelineView+ZoomSuggestions.swift`.
- **Export pipeline dividido** — `VideoExportSession.performExport()` de ~480 LOC monolíticas → orquestador de 125 LOC que encadena stages aislados en `VideoExportSession+Stages.swift` (prepare/validate/build/configure/run/verify) y `VideoExportSession+Composition.swift` (rutas fullscreen-camera / standard / per-segment masked separadas).
- **Phase 1 split — 8 archivos >500 LOC divididos** — 14 archivos resultantes, todos bajo 500 LOC:
  - `CompositionBuilder+AudioTracks.swift` (audio track building extraído; CompositionBuilder 678→476)
  - `ExportOverlayRenderer.swift` (image/shape overlay burn-in extraído de ExportCaptionRenderer 669→235)
  - `PreviewEngine+Playback.swift` (playback/time observation/proxy extraídos de PreviewEngine 585→343)
  - `PreviewEngine+Player.swift` (player creation/mutes/audio mix extraídos de PreviewComposition 504→364)
  - `ProjectStore+Create.swift` (createProject overloads y addTake extraídos de ProjectStore 533→277)
  - `ProxyGenerator+Helpers.swift` (sizing/disk/CGContext helpers extraídos de ProxyGenerator 515→401)
  - `TimelineView+MediaMarkers.swift` (waveform/zoom markers/overlay track row extraídos de TimelineView+Subviews 500→336)
- **Phase 1 boilerplate — helpers extraídos en archivos 400–490 LOC:**
  - `MicAudioRecorder.swift` (141 LOC nuevo; Recorder.swift 460→322)
  - `mutateSegment()` en `ZoomSectionController` colapsa 4 patrones guard/mutate/save (446→410)
  - `applyCanvasUpdate()` en `ProjectEditor` unifica 7 métodos canvas con undo/autosave (439→332)
  - `zoomState()` en `PreviewRenderer` deduplica focus-point math entre `applyZoom` + `applyZoomTransform` (425→375)
  - Dead code eliminado en `HotkeyManager`: `OptionBits` alias sin uso + `removeEventHandler()` vacío (463→455)
- `CaptureSessionManager` loguea el `NSError` completo (domain/code/userInfo) del writer en el primer fallo en vez de solo `localizedDescription`.
- Al fallar `AVAssetWriter` durante grabación, se para el stream inmediatamente y no se reintentan más frames (evita spam de 1000+ logs por grabación corrupta).
- Preview refresh debounce reducido 500ms → 150ms — overlays y cambios de propiedades se reflejan ~3× más rápido.

### Fixed
- **Versionado reescalado** a 0.5.1 — refleja estado real del producto; historia del CHANGELOG renumerada al esquema más conservador.
- **Telemetría de cursor no llegaba al proyecto** — `TelemetryRecorder` anidaba `telemetry/telemetry/cursor.jsonl` dentro del directorio que ya era `/telemetry/`, el `Recorder` buscaba un nivel arriba y nunca encontraba el archivo; `moveRecordingFiles` fallaba silencioso. Consecuencia: **cero sugerencias de zoom** en cualquier proyecto grabado con el flujo actual.
- **Auto-zoom: sugerencias en timeline pero sin zoom real** — `ZoomPlanGenerator.validateZoomRate` tiraba `zoomRateExceeded` cuando había más sugerencias que el límite por minuto (default 6/min); el `try?` aguas arriba silenciaba el error y nunca se aplicaba el plan. Ahora el generador recorta por score al tope permitido en vez de abortar. `generateZoomSuggestions` también loggea errores que antes se tragaban silenciosamente.
- **Zoom apuntaba a coordenadas equivocadas** — `ZoomSuggestionGenerator` normalizaba eventos de cursor (puntos del display) dividiendo por `canvas.format.w/h` (tamaño de render de salida), y `ZoomPlanGenerator.generateZoomPlan(from clickWindows:)` tenía 1920×1080 hardcoded. Ahora ambos usan las dimensiones reales del video grabado (`primarySources.screen.size`). Caveats pendientes: displays retina (points ≠ pixels) y grabaciones por área (`captureRect`) siguen necesitando schema para mapeo perfecto.
- **Zoom plan obsoleto re-aplicado al cargar proyecto nuevo** — `reset()` en `PreviewEngine` no limpiaba `pendingZoomPlan`; el plan del proyecto anterior se volvía a aplicar en el siguiente. Ahora `reset()` limpia el pending plan.
- **Overlay timing: overlays se creaban en t=0** — `RightPanel` pasaba `.constant(playheadTime)` con tiempo desactualizado; `OverlayEditorView` ahora lee `currentTime` directamente desde `playerViewModel` con un `Binding` live.
- **Edits de overlay no se reflejaban en el frame visible** — `rebuildVideoComposition` reemplaza el `AVVideoComposition` pero AVFoundation no re-renderiza el frame ya mostrado; ahora hace seek al tiempo actual cuando el player está pausado para forzar re-render inmediato.
- **Cache key de overlay incompleta** — `cachedOverlayKey` solo incluía id/x/y/scale/rotation/stroke; cambios en `strokeWidth`, `shadow`, `text`, `fontSize`, `fontColor` y `bgColor` eran ignorados silenciosamente por el cache. Ahora incluye todas las propiedades relevantes para el render.
- **Rebuild excesivo de `videoComposition` al abrir un proyecto** — `PreviewEngine.updateProject` ahora corta temprano si el project es idéntico al ya cargado; `PreviewPlayerView` disparaba 10+ rebuilds en cascada por cambios de state no relacionados con la composición visual.
- Warning "Initialization of immutable value 'oldBackground' was never used" en `ProjectEditor.setBackgroundType` — variable sin uso eliminada.
- Dead code removido: `TimelineView.getThumbnailForTime` y `zoomSuggestionGenerator` (nunca referenciados).

## [0.5.0] - 2026-04-12

### Added
- **Multi-track timeline architecture** — replaced flat `segments[]` with typed tracks (`primary`/`video`/`audio`) each containing universal clips
- **Universal clip model** — `ClipContent` enum supporting 5 content types: `.recording`, `.image`, `.video`, `.audio`, `.color`; each with its own ref type (`RecordingClipRef`, `ImageClipRef`, `VideoClipRef`, `AudioClipRef`, `ColorClipRef`)
- **Track-level controls** — per-track `isMuted`, `isLocked`, `volume`, `opacity`
- **EditorModel track/clip operations** — `addTrack`, `removeTrack`, `addClip`, `removeClip`, `updateClip`, `moveClip`, `splitClip` (works on any clip type in any track)
- **Static content rendering** — MaskedVideoCompositor renders images and solid colors for non-recording clips in the primary track (with image cache)
- **Audio clip tracks** — CompositionBuilder creates dedicated audio tracks from timeline audio tracks with per-clip volume
- **Schema v2** — `project.json` now uses `tracks[]` format; auto-migration from v1 `segments[]` on load

### Changed
- **Timeline model** — `Project.Timeline` stores `tracks: [TimelineTrack]` instead of flat `segments: [Segment]`
- **CompositionBuilder** — reads clips from primary track; handles recording, imported video, image/color gaps, and audio clip tracks
- **PreviewComposition** — generates per-clip compositor instructions with `staticContent` for image/color rendering
- **Export pipeline** — ExportEngine, VideoExportSession, GIFExportSession, ExportValidator all use tracks/clips model
- **Project schema version** — bumped to 2

### Fixed
- **`deleteRange` partial overlap** — clips partially overlapping the delete range at either edge are now trimmed correctly (not silently ignored)
- **`deleteRange` for spanning clips** — properly splits any clip type using generic `splitContent`, fixes double-counting of offset adjustment
- **Timeline duration with muted tracks** — muted tracks now contribute to duration (muting hides playback, not timeline extent)
- **Legacy segment ops respect `isLocked`** — trimIn, trimOut, split, delete, addSegment, deleteRange now check primary track lock state
- **Camera instructions for mixed clips** — PreviewComposition iterates all primary track clips (not just recording segments) for per-clip camera overrides
- **Hex color alpha support** — MaskedVideoCompositor now parses 8-character hex colors (e.g. `#FF5500AA`)
- **Stable clip ordering** — segments setter uses deterministic sort (by timelineIn, then by id) to prevent ordering flips
- **Audio clip sync** — clips with volume=0 no longer skipped from composition, preserving timeline alignment

## [0.4.1] - 2026-04-02

### Added
- **Camera border** — configurable width (0–8px) and color (10 presets) on PiP camera overlay
- **Per-segment audio** — volume slider (0–300%) and mute toggle per segment in inspector bar
- **Telemetry recording** — cursor/click telemetry always captured during recording (captureTelemetry=true default)
- **Autosave** — 1s debounced save after every edit via ProjectLibrary
- **Auto-zoom rendering** — zoom plan applied per-frame in MaskedVideoCompositor (scale around focus point)
- **Auto-show zoom suggestions** — markers appear automatically when project has telemetry data
- **Auto-apply zoom plan** — zoom effect active immediately without manual "Apply" button
- **Per-segment export** — export now renders per-segment camera positions, visual effects, and audio

### Fixed
- **Black video after splits** — compositor instructions now guaranteed contiguous (prev.end = next.start)
- **Export ignored per-segment edits** — was using single global instruction; now uses per-segment instructions
- **Audio mute state lost on rebuild** — lastAudioMuteState preserved across light composition rebuilds
- **Camera position reset on move/resize/shape** — PiPLayoutHelper now preserves borderWidth/borderColor
- **Missing undo on volume/mute** — all segment mutations now record undo via generic mutateSegment()
- **Auto-create camera override** — dragging camera with segment selected auto-creates override (no "Custom" button needed)

### Changed
- Zoom suggestion thresholds tuned for lighter recordings (minClicksPerWindow: 2→1, minMovementDistance: 50→20px)
- DwellDetector more sensitive (minDwellDuration: 0.45→0.3s, maxDwellDuration: 2.6→4.0s)
- 11 onChange(of:) calls migrated to macOS 14+ API
- TimelineView body split into extracted sub-views (fixes Swift type-checker timeout)

## [0.4.0] - 2026-04-01

### Added
- **Per-segment camera position** — each segment can override the project camera PiP position; "Customize"/"Reset" controls in segment inspector bar
- **Per-segment speed presets** — speed picker (0.25x–4x) in segment inspector bar; orange speed badge on segments
- **Segment inspector bar** — appears below timeline toolbar when a segment is selected; shows speed + camera controls
- **Media item drag to reposition** — drag gesture with live visual feedback; updates timelineIn on drop
- **Audio drift detection** — `AudioDriftDetector` compares video/audio durations, warns if drift >100ms
- **Compositor visual effects rendering** — gradient backgrounds (CILinearGradient), blur backgrounds (CIGaussianBlur), video corner radius (CIBlendWithMask), video padding (scale+translate)
- **Per-segment composition instructions** — PreviewComposition creates separate instructions per segment when camera positions differ

### Fixed
- **Split bug** — `takeId`, `zoom`, and `cameraPosition` now propagate correctly to both segments on split (were lost before)
- **Blur background layer ordering** — blurred screen now renders behind padded/rounded video content (was on top)
- **`contains(where:)` syntax** in AudioDriftDetector

### Technical
- `PreviewEngine.cameraTransform()` extracted as static helper for reuse between preview and export
- `MaskedVideoCompositionInstruction` now carries visual effect properties (cornerRadius, shadow, padding, background)
- 6 new unit tests for split propagation and segment model backward compatibility

## [0.3.1] - 2026-03-31

### Added
- **4K HEVC export preset** (3840x2160, 60fps, 30Mbps) in export options
- **Duplicate project** — deep copy via context menu, auto-opens the clone
- **Export transcript as TXT/SRT/VTT** — full caption export with NSSavePanel
- **Video effects sidebar** — corner radius (0–16px), shadow intensity (0–100%), padding (0–30%) controls
- **Background gradients** — 8 presets (Sunset, Ocean, Forest, Midnight, Lavender, Ember, Arctic, Slate) in new "Gradient" tab
- **Project thumbnails** — auto-generated JPEG from first frame of screen video on project creation; shown in project list

### Fixed
- **Mic audio race condition** — validates AVAudioEngine format before recording; auto-retry with 300ms delay if format invalid (0 Hz / 0 channels)
- **"Publishing changes from within view updates"** — BackgroundControlsView state mutation deferred with Task
- **onChange macOS 13 compatibility** — 12 instances of macOS 14+ API converted to macOS 13 single-parameter syntax
- **SHA256 placeholders** — replaced 8 "placeholder" values with real CryptoKit SHA256 streaming hashes (64KB chunks, constant memory)
- **Hardcoded video dimensions** — screen and camera tracks now use `detectVideoDimensions()` for actual recorded resolution
- **Timer intervals** — export/keystroke polling reduced to 0.25s; recording elapsed display kept at 0.1s for smooth UX
- **ExportViewModel timer leak** — deinit now invalidates progressUpdateTimer if view dismissed during export

### Technical
- EngineKit passes `-strict-concurrency=complete` with zero warnings
- `ProjectStore.sha256(of:)` uses streaming FileHandle (constant memory for 1GB+ files)
- `ProjectStore.generateThumbnail()` uses AVAssetImageGenerator + CGImageDestination (pure CoreGraphics)

## [0.3.0] - 2026-03-31

### Added
- **Auto-zoom from cursor telemetry** — `DwellDetector` detects cursor pauses (>450ms stationary), `ZoomSuggestionEngine` combines click windows + dwell candidates into unified suggestions. Timeline shows yellow markers for each suggestion; click markers to accept/reject individually. "Apply" creates zoom keyframes and persists zoom config on segments.
- **GIF export options** — when "Animated GIF" preset is selected, ExportView shows GIF-specific controls: frame rate (10/15/24 fps), max size (480/800/1200), loop toggle. Options flow through `GIFExportOptions` to the existing `GIFExportSession` engine.
- New EngineKit files: `DwellDetector.swift`, `ZoomSuggestionEngine.swift`
- `PreviewEngine.setZoomPlan()` public setter for external zoom plan application

### Technical
- `ZoomSuggestionEngine` is a stateless enum with static methods (no actor overhead)
- `ZoomSuggestion.toClickWindow()` unifies coordinate conversion in one place
- Individual suggestion accept/reject via `dismissedSuggestionIds` state set

## [0.2.1] - 2026-03-30

### Performance
- **Fix Task leak in CameraEngine/CaptureEngine** — duration timer now stores a cancellable `Task` handle with `!Task.isCancelled` guard; cancelled explicitly on `stopRecording()`
- **Fix AVPlayer observer leak in PreviewEngine** — `stopPeriodicTimeObservation()` now called before nilling player in `unloadProject()`
- **ThumbnailCache LRU eviction** — enforces `maxThumbnailCount` via access-order tracking; evicts oldest entries when limit exceeded
- **Waveform rendering: GeometryReader+Path → Canvas** — renders directly into graphics context, no SwiftUI view tree; uses `ArraySlice` instead of array copy
- **Thumbnail lookup O(n log n) → O(n)** — replaced `sorted()` + `min(by:)` per render with single linear scan
- **Lazy project list loading** — summary cache with file modification date invalidation; skips re-decoding unchanged `project.json` files. `loadProjects()` debounced (500ms)
- **Deferred thumbnail/waveform generation** — initial open generates 15 thumbnails (was 50); remaining thumbnails + waveforms generated at `.utility` priority in background

## [0.2.0] - 2026-03-25

### Added
- **Per-track volume sliders** in timeline label area (system audio + mic audio), range 0–3x, with live preview update
- **Area selector highlight** — persistent dashed overlay shows selected capture area; hidden when recording stops or source changes
- **Area selector UX** — double-click to confirm selection; instruction bar adapts text based on state; Escape cancels

### Fixed
- **Mic audio error -50** — `AVAudioFile` settings now match `AVAudioEngine` input node native format (channel count + sample rate), eliminating `ExtAudioFileWrite paramErr`
- **Duplicate editor window** — changed main editor from `WindowGroup` (multi-instance) to `Window` (single-instance) so `openWindow` brings existing window to front
- **Project not auto-selected after recording** — removed async yield before `selectedItem` assignment, eliminating race condition
- **Playback speed change required stop/play** — `playbackRate` now has `didSet` that updates `avPlayer.rate` immediately when playing
- **Area highlight visible in recorded video** — added `sharingType = .none` to `AreaHighlightController` overlay window
- **Area highlight persisting after recording stops** — `hide()` now called at start of `stopAndCleanup()`
- **NSPanel keyboard shortcuts broken** — `KeyablePanel: NSPanel` subclass with `canBecomeKey = true` enables Escape and other shortcuts in area selector
- **Timeline segments not filling available width** — `pixelsPerSecond` now scales dynamically to fill the ScrollView viewport

### Changed
- **Mic audio default volume** boosted from 1.0x to 2.5x to compensate for lower mic input levels vs system audio
- **Timeline label width** expanded from 120 to 160px to accommodate volume sliders
- **Track mute icons** differentiated: speaker for audio tracks, eye for video tracks

### Technical
- `WindowID` enum centralizes window ID constants (eliminates string literals)
- `TimelineTrackKind.isAudioTrack` computed property replaces inline checks in 3 places
- `reapplyAudioMix()` reconstructs state from `lastMuteState` (audio only), avoiding unnecessary `applyVideoMutes` calls on volume changes
- GeometryReader state writes deferred with `Task { @MainActor in }` to avoid "Publishing during view update" warning

## [0.1.1] - 2026-01-22

### Added
- **Complete export system** with user-selected save location
- **Export presets**: Web 1080p (H.264), High 1080p (HEVC), Portrait 1080p (H.264), Animated GIF
- **Timeline editor** with drag-and-drop clip management
- **Trim and cut operations** for screen and audio tracks
- **Zoom controls** for timeline navigation
- **Progress tracking** with detailed export stages (validation, loading, composition, export, verification)
- **NSSavePanel integration** for user-controlled file destination
- **Play button** to preview exported video within app
- **Hotkey manager** for recording controls (ExportEngine/HotkeyManager)
- **Recording state manager** with Combine support (RecordingStateManager)

### Fixed
- **Sandbox entitlements** - Added `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.downloads.read-write` for file access
- **Export engine errors** - Improved error logging with domain, code, and userInfo details
- **AVAsset deprecation** - Changed `AVAsset(url:)` to `AVURLAsset(url:)` for macOS 15 compatibility
- **Telemetry controls** - Fixed optional unwrapping issues (TelemetryControlsView)
- **Overlay editor** - Changed file-private access to internal for extensions
- **App delegate imports** - Added missing `EngineKit` import for hotkey registration
- **Recording notifications** - Removed duplicate `openRecordingWindow` declaration
- **Recording control view model** - Added missing imports (Combine, AppKit, CoreVideo)
- **Export view model** - Fixed `temporaryExportURL` path construction to use correct project directory
- **Export view** - Fixed cancel button to properly close modal
- **Video export session** - Added detailed directory and file permission verification
- **Save panel** - Ensured .mp4 extension is added to user-selected files
- **Progress monitoring** - Fixed state updates to prevent UI freezing

### Changed
- **Export workflow** - Files are now exported to temporary location within sandbox, then user saves to desired location via save panel
- **Export logging** - Added comprehensive logging with emojis for easier debugging
- **UI behavior** - Export completion now shows "Done" button instead of "Cancel Export"
- **File management** - Improved handling of existing files before export

### Known Issues
- Exported videos may show black bars/letterboxing (aspect ratio issue)
- Frame counter warnings during recording startup (non-critical)

## [0.1.0] - Initial Release

### Added
- Basic screen recording with ScreenCaptureKit
- System audio capture
- Camera video capture
- Microphone audio capture
- Separate track recording (screen, system audio, camera, mic audio)
- Sandbox-compatible file storage
