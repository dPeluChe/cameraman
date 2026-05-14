# Skills Baseline Review — 2026-05-14

> **Branch:** `review/skills-baseline-2605`
> **Skills aplicados:** `swiftui-expert` (AvdLee), `swiftui-performance-audit`, `swift-concurrency-expert`, `swiftui-view-refactor` (patrickserrano).
> **Modo:** read-only. Sin cambios de código en esta branch — solo este reporte. Decide qué aplicar y se hace en commits separados.
> **Toolchain:** Swift 6.2.4 / `swift-tools-version: 5.9` / `-strict-concurrency=complete` (declarado en CLAUDE.md).

## Resumen ejecutivo

Se auditaron 6 archivos representativos (3 UI + 3 EngineKit/concurrency) contra los checklists de ambos skills. **15 hallazgos**, ninguno crítico. La mayoría son optimizaciones puntuales y consolidaciones de pattern; **un solo bug real** (signposts mal emparejados en `LoggingSystem`). Varios hallazgos ya están registrados en `TASK_TODO.md` — los marco para evitar trabajo duplicado.

**Distribución:**
- 🐛 Bug real: 1
- ⚠️ Correctness / fragilidad: 3
- 🚀 Performance: 4
- 🧹 Simplificación / DRY: 4
- 📚 APIs deprecadas: 2
- ✅ Ya tracked en TASK_TODO: 4

---

## 🐛 Bug real

### 1. `LoggingSystem.swift:263-291` — signposts no se emparejan en Instruments
`beginSignpost` / `endSignpost` / `emitSignpost` crean un `OSSignpostID` local pero **nunca lo pasan a `os_signpost`**. Sin ID, Instruments no puede emparejar `begin` con `end`, así que los intervalos aparecen rotos o vacíos en el SwiftUI / Time Profiler template.

**Fix mínimo:** pasar el ID al macro y persistir el ID begin→end por `name+id` (map `[String: OSSignpostID]` en el actor) o cambiar la API para que el llamador construya y reutilice el `OSSignpostID`.

```swift
os_signpost(.begin, log: signpostLog, name: name, signpostID: signpostID, "%{public}s", message ?? "")
```

Impacto: el item del TASK_TODO Fase 3 que dice "implementar signposts" está marcado como resuelto, pero **no funcionan**. Sale del skill `native-app-profiling` indirectamente.

---

## ⚠️ Correctness / fragilidad

### 2. `ThumbnailCache.swift:92,119` — claves `TimeInterval` (Double) en diccionario
Lookup por igualdad de `Double` es frágil. Si quien llama pasa `5.0` y se cacheó `5.000000001`, miss. Quantizar a milisegundos (`Int(time * 1000)`) o ms-buckets evita ghost-misses.

### 3. `CaptureEngine.swift:70-160` — `RecordingSession` expone estado mutable cross-actor sin Sendable
`RecordingSession` es `public final class` con `private(set) var` mutables, devuelta por `startRecording()` desde un actor a callers no-isolated. Los getters (`isRecording`, `duration`, `error`) los puede leer cualquiera en cualquier thread → potencial data race. Hoy compila porque la clase no declara `Sendable`, lo cual hace que Swift 6.2 lo trate como no-Sendable y dispare warnings si activas `strict-concurrency=complete` con default actor isolation.

**Recomendación:** convertir las propiedades observables (`isRecording`, `duration`, `error`) en un snapshot `Sendable` que se devuelva on-demand:
```swift
public struct SessionState: Sendable {
    let isRecording: Bool
    let duration: TimeInterval
    let error: SendableError?
}
public func sessionState() async -> SessionState { ... }
```

### 4. `CaptureEngine.swift:366,377` — finishWriting no maneja `.failed`
Solo se entra al branch si `status == .writing`. Si el writer transicionó a `.failed` (caso reportado en TASK_TODO B1 / bloqueante de ultrawide 3440x1440), no se loguea `writer.error` antes de finalizar y el archivo queda corrupto silenciosamente.

**Conecta con TASK_TODO Bloqueante B1** — al implementar la detección de `.failed` durante captura, también auditar el path de teardown aquí.

---

## 🚀 Performance

### 5. `TimelineView.swift:73,302` — trabajo en `body`
`TimelineTrackBuilder.tracks(for: project)` se llama en cada redraw. Si los tracks cambian solo cuando cambian `project.timeline.tracks` o `project.timeline.segments`, vale la pena cachearlo con un wrapper o moverlo a un computed con memoization (o un `@State`/`@StateObject` derivado). Igual `Self.computeOverlayRows(overlays:)` en `:306`.

### 6. `TimelineView.swift:308` — `ForEach(..., id: \.offset)` en overlay rows
Identidad inestable: si la lista de rows cambia (overlays añadidos/eliminados), todos los rows después del cambio reinicializan estado. Usar `.id(overlayRows[i].first?.id ?? UUID())` o agrupar overlays en un struct identificable.

### 7. `ThumbnailCache.swift:64-66` — LRU `O(N)` por insert
`thumbnailAccessOrder.removeAll { $0 == time }` recorre la lista entera en cada `insertThumbnail`. Para `maxThumbnailCount=500` cada miss es 500 comparaciones. Usar:
- `OrderedDictionary` de `swift-collections`, o
- mantener un `Set<TimeInterval>` para presencia + lista solo append, eliminar al evict.

### 8. `LoggingSystem.swift:127` — `ISO8601DateFormatter()` por log call
Cuando `logToConsole == true`, se asigna un nuevo formatter en **cada** llamada a `log`. Los formatters son caros (~100µs cada uno). Mantener una instancia estática.

```swift
private static let consoleDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()
```

---

## 🧹 Simplificación / DRY

### 9. `ProjectEditor.swift:65-110` — patrón duplicado en 6 métodos
`trimIn`, `trimOut`, `split`, `addSegment`, `delete`, `deleteRange` repiten:
```swift
let previousProject = project
let result = await editorModel.<op>(...)
updatePublishedProject(from: result, previousProject: previousProject)
return result
```
Un helper genérico simplifica:
```swift
private func performEdit<T>(_ op: (EditorModel) async -> EditorResult) async -> EditorResult { ... }
```
Riesgo: bajo (signaturas distintas requieren wrappers ligeros).

### 10. `ProjectEditor.swift:319-321` — `recordCommand` huérfano
Solo se referencia desde sí mismo (Edit pattern preparado pero no usado). Si no se va a migrar pronto, eliminarlo y dejar el TODO documentado en `EditCommand` protocol. (Si va pronto al Command pattern, dejarlo.)

### 11. `PreviewPlayerViewModel.swift:146-155, 186-193` — `await MainActor.run` redundante
La clase es `@MainActor`. Un `Task { ... }` lanzado desde un método `@MainActor` **hereda** el contexto del actor por default (Swift 5.9+). El `await MainActor.run { ... }` dentro está hop-eando innecesariamente. Simplificar:
```swift
Task {
    do {
        try await engine.loadProject(project, projectDirectory: ...)
        let player = await engine.player
        self.previewEngine = engine    // ya estamos en MainActor
        ...
    }
}
```

### 12. `PreviewPlayerViewModel.swift:293-310` — `Task { @MainActor }` dentro de `queue: .main`
`addPeriodicTimeObserver(forInterval:queue:.main)` y `addObserver(forName:queue:.main)` ya ejecutan el closure en main queue. El inner `Task { @MainActor [weak self] in }` solo introduce una hop extra. Capturar `[weak self]` directamente y asignar es suficiente.

---

## 📚 APIs deprecadas (no rompen pero conviene)

### 13. `ThumbnailCache.swift:259,270` — APIs deprecadas en macOS 13+
- `AVAsset(url:)` → `AVURLAsset(url:)`.
- `AVAssetImageGenerator.copyCGImage(at:actualTime:)` síncrono → `image(at:)` async (macOS 13+).

El async variant también permite cancelación, importante con `Task.isCancelled` que ya manejan.

### 14. `TimelineView.swift:91,94` — `onChangeCompat`
Wrapper para macOS 13. Cuando se suba el deployment target a macOS 14, eliminar wrapper y usar `.onChange(of:initial:_:)` nativo. (No urgente; nota para upgrade futuro.)

---

## ✅ Ya tracked en TASK_TODO (no duplicar trabajo)

| Hallazgo | Archivo | TASK_TODO |
|---|---|---|
| Singletons `.shared` (CaptureEngine, ProjectLibrary, etc.) | `CaptureEngine.swift:229`, `ProjectEditor.swift:41` | Fase 1 ✅ parcial (EngineContext) |
| Undo/redo Command pattern migration | `ProjectEditor.swift:319` | Fase 2 ✅ baseline |
| LoggingSystem actor vs nonisolated | `LoggingSystem.swift:14` | Fase 6 — sigue pendiente |
| Refactor ZoomSectionController (test 49KB) | — | Fase 6 — sigue pendiente |
| `nonisolated deinit` no puede limpiar observers | `PreviewPlayerViewModel.swift:407` | Fase 0 ✅ |

---

## Recomendación de orden de aplicación

Si decides aplicar todo, este orden minimiza riesgo y maximiza valor:

1. **🐛 (#1) Signposts** — fix puntual de 1 archivo, alta utilidad para profiling futuro. Sin riesgo.
2. **🚀 (#8) Formatter cacheado** — 3 líneas, gana en ruta caliente con `logToConsole=true`.
3. **🧹 (#11, #12) Quitar `MainActor.run` y `Task { @MainActor }` redundantes** — limpia ruido, modesto perf win, fácil de revertir.
4. **🚀 (#5, #6) TimelineView body** — cache de `tracks` + id estable en overlay rows. Requiere prueba manual del timeline (scroll, drag, edición) para no regresionar.
5. **⚠️ (#2) Quantizar `TimeInterval` keys** — pequeño pero protege thumbnails. Test manual: scrub timeline + ver thumbnails.
6. **🚀 (#7) LRU ordering O(N)** — solo si profiling muestra que importa. `OrderedDictionary` añade dependencia (`swift-collections`).
7. **⚠️ (#3, #4) RecordingSession + writer.failed** — conecta con bloqueante B1 del TASK_TODO. Agrupar con esa investigación.
8. **🧹 (#9, #10) DRY ProjectEditor** — refactor estético, dejar para sesión dedicada.
9. **📚 (#13) Modernizar AVAsset APIs** — bajo riesgo pero cambio de superficie; sesión de migration aparte.

---

## Gap conocido

Ningún skill instalado cubre **AVFoundation / ScreenCaptureKit / AVMutableComposition / pipeline de zoom keyframado**, que es el core técnico de cameraman. Esto valida el TODO `Crear skill propio cameraman-engine` agregado en `TASK_TODO.md` el 2026-05-14.

---

## Round 2 — Validación post-commits + warnings (2026-05-14)

Después de aplicar los 8 commits del round 1 se re-validaron los archivos modificados contra los checklists. Resumen:

### Re-lectura de archivos modificados

- **`LoggingSystem.swift`** — signposts emparejados ✅, formatter cacheado ✅. Observación menor: el map `activeSignpostIDs` puede crecer si los callers olvidan llamar `endSignpost`. No bloqueante, dejar como tech debt si se vuelve un problema en profiling real.
- **`PreviewPlayerViewModel.swift`** — `MainActor.run` redundante eliminado ✅. Observación menor: línea 119 mantiene `project.primarySources!.screen.path` con force unwrap tras un guard de nil. Cosmético.
- **`TimelineView.swift`** — ID estable en overlay rows ✅. El opcional follow-up de cachear `TimelineTrackBuilder.tracks` requeriría extraer una sub-view; queda como mejora futura.
- **`ThumbnailCache.swift`** — keys quantizadas + APIs modernizadas ✅. `getCacheStats() -> [String: Any]` sigue untyped (decisión: API de telemetría, no vale la pena tiparla ahora).
- **`ProjectEditor.swift`** — DRY aplicado ✅, `recordCommand` huérfano eliminado ✅. Nota: `applyCanvasUpdate` y `performEdit` son helpers paralelos para canvas vs editor-model. Podrían unificarse pero la diferencia de retorno (`Bool` vs `EditorResult`) lo justifica.

**Veredicto:** ningún hallazgo nuevo significativo. Los cambios del round 1 no introdujeron regresiones detectables vía revisión estática.

### Eliminación de warnings

Build limpio expuso **15 warnings** (más de los 4 que vimos en el reporte original — el cache del build los ocultaba):

| # | Archivo | Tipo | Estado |
|---|---|---|---|
| 1 | `AudioProcessing.swift:74` | unused `attackCoef` | ✅ eliminado (commit 9) |
| 2 | `HotkeyManager.swift:336` | `InstallEventHandler` result discarded | ✅ eliminado con log (commit 9) |
| 3-7 | `LocalAIProvider.swift:259-272` | non-Sendable captures en @Sendable closure | ✅ eliminado vía `UncheckedSendableAVPipeline` (commit 11) |
| 8-12 | `EditCommand.swift` | Sendable struct con stored Project non-Sendable | ✅ eliminado vía `@preconcurrency import EngineKit` (commit 12) |
| 13 | `EditCommand.swift:9` | sugerencia explicíta de `@preconcurrency` | ✅ aplicada (commit 12) |
| 14-15 | `MaskedVideoCompositor.swift:150,155` | Sendable function-type mismatch en AVVideoCompositing protocol | ⚠️ **irreducible** — documentado en commit 10 |

**Resultado:** 13 warnings eliminados, 2 remanentes documentados.

### Sobre los 2 warnings residuales

`AVVideoCompositing` anota `sourcePixelBufferAttributes` y `requiredPixelBufferAttributesForRenderContext` con `NS_SWIFT_SENDABLE` en el lado ObjC. Esto exige que el getter sintetizado por Swift sea `@Sendable`, pero ningún syntax actual permite forzar `@Sendable` en el getter de una stored `let` de tipo `[String: Any]?`. Workarounds intentados que **NO** funcionan:

- `@preconcurrency import AVFoundation` — la anotación NS_SWIFT_SENDABLE bypasses preconcurrency
- `@preconcurrency` en la conformance → "has no effect"
- Computed property `nonisolated public var` backed by `static let` → mismo warning
- Cambiar tipo a `[String: any Sendable]?` → rompe el contrato del protocol

Es un **bug/limitación SDK/compiler** que necesita fix de Apple. Mientras tanto, la forma `nonisolated(unsafe) let` es lo más cercano semánticamente correcto y el warning es informativo (no se promociona a error hasta `swift-tools-version: 6.x`).

### Commits del round 2

| # | Commit | Tipo |
|---|---|---|
| 9 | `chore: limpiar warnings menores en EngineKit` | cleanup |
| 10 | `docs(compositor): documentar warning Sendable irreducible` | docs |
| 11 | `fix(local-ai): wrap captures AVFoundation en Sendable box` | fix |
| 12 | `fix(edit-command): @preconcurrency import EngineKit` | fix |

Total branch: **12 commits de código** + 2 commits de docs (este + el inicial).
