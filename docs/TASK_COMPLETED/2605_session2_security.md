# Tareas Completadas — Sesión 2 Mayo 2026 (Security Audit)

> Periodo: 2026-05-18 → 2026-05-19
> Branch: `chore/security-cleanup` (PR #14)
> Foco: auditoría de seguridad pre-publicación + hardening recomendado antes de abrir el repo y subir a App Store.

---

## Contexto

Auditoría completa del repo antes de:
1. Hacer público el código (open source en `github.com/dPeluChe/cameraman`).
2. Submitear a App Store (Apple Developer Program aprobado, pending).

Se revisaron: secretos en git, telemetría network, entitlements, URL safety, dependencias, código que procesa input externo, rutas personales hardcodeadas y readiness open source. Reporte clasificado en 🔴 críticos, 🟡 recomendados, 🟢 verificados.

---

## 🔴 Críticos aplicados (4/4)

### `scripts/code_sign.sh` — sin paths personales (6dcde93)

- [x] `APP_PATH` derivado de `REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"`; acepta override por env var.
- [x] Lee `CameramanApp/CameramanApp.entitlements` real en vez de inlinear una copia divergente.
- [x] Validación de existencia de entitlements + binario antes de firmar.

**Bug latente que esto cierra**: el inline-entitlements omitía `device.camera` y `files.downloads.read-write`. Quien usara el script obtenía un binario con permisos divergentes del bundle real.

### `.claude/settings.local.json` — untrackeado

- [x] `git rm --cached .claude/settings.local.json`.
- [x] Patrón añadido a `.gitignore` para que no vuelva a entrar.
- [x] Decisión consciente de no purgar history (contenido = paths locales + permisos de Claude, severidad baja; el costo de force-push a `main` no compensa).

### Email de contacto consolidado

- [x] `CONTRIBUTING.md:111` — security disclosure → `antonio@dpeluche.dev`.
- [x] `git config user.email antonio@dpeluche.dev` (repo local) para futuros commits.
- [x] Verificado que `AppLinks.contact`, `APP_STORE_METADATA.md` y CONTRIBUTING usan ahora el mismo email.

**Antes**: 3 dominios distintos (`dpeluche.dev` / `iteris.tech` / `feedby.ai`). App Store reviewers + GitHub Security advisories cada uno habría visto un contacto distinto.

### URLs `labs-cameraman` → `cameraman`

- [x] `docs/index.html` footer + repo link.
- [x] Marca pública en `README.md`, `docs/index.html` consolidada a "dPeluChe Studios".
- [x] `LICENSE` mantenido en Iteris (decisión legal explícita; brand pública vs copyright holder).

---

## 🟡 Recomendados aplicados (3/5) (cd27e45)

### AppUpdater valida URL de GitHub antes de open

- [x] Nuevo helper `safeGitHubURL(_:) -> URL?` en `AppUpdater.swift` — exige `scheme == "https"` y `host == "github.com"`.
- [x] Encadenado con `.flatMap` en el parseo de `html_url`. Si la URL no pasa la validación, el botón "Download Update" cae al fallback estático `AppLinks.releases`.

**Riesgo cubierto**: payload de release comprometida que devuelva `javascript:`, `file://`, o un dominio off-target. Probabilidad muy baja (HTTPS + ATS) pero el guard es 4 líneas.

### `LoggingSystem` con `privacy: .private`

- [x] OSLog interpolation en `LoggingSystem.swift:132` cambiada a `"\(formattedMessage, privacy: .private)"`.
- [x] Comentario in-line explicando el motivo (file paths / nombres de proyecto del usuario no deben quedar visibles a otros procesos via Console.app).

**Nota**: en debug con el dispositivo adjunto se siguen viendo. Solo se redactan para procesos externos en el sistema.

### Entitlement `files.downloads.read-write` removido

- [x] `grep -rn "Downloads\|download"` no encontró ningún uso en código.
- [x] Removido de `CameramanApp.entitlements`. App Review pregunta por entitlements no justificados — uno menos.

---

## 🟡 Recomendados diferidos (2/5)

### Team ID en xcconfig (no aplicado, decisión consciente)

- `DEVELOPMENT_TEAM = V2U37KWA8D` se queda en `project.pbxproj`. Razón: no es secreto (aparece en cualquier binario firmado) y mover a `Config.xcconfig` solo aporta si hay contributors externos que firmen con su propia cuenta. Reevaluar cuando lleguen los primeros PRs.

### `copyright` Debug/Release pbxproj

- Audit lo reportó como bug; verificación en repo mostró ambos configs idénticos (`"© 2026 dPeluChe Studios"`). Falso positivo del snapshot que leyó el agente.

---

## 🟢 Verificado limpio

- Sin secretos en working tree ni en git history (grep exhaustivo: `api_key`, `secret`, `token`, AWS/GitHub/Slack tokens, PEM headers).
- Sin telemetría network: `TelemetryRecorder`, `TelemetrySync`, `CrashReporter`, `AIService*` no usan `URLSession`. Único caller es `AppUpdater` → `api.github.com`.
- Grabaciones permanecen locales (app container sandbox + `Application Support/ProjectStudio/CrashReports/`).
- `PrivacyInfo.xcprivacy` declara FileTimestamp + DiskSpace + UserDefaults y coinciden con uso real.
- Usage descriptions en Info.plist (Camera, Microphone, ScreenCapture) presentes.
- Sandbox + hardened runtime habilitados.
- `.gitignore` cubre `.build/`, `xcuserdata/`, `DerivedData/`, `dist/`. `App/.build/` con paths absolutos NO está trackeado.
- Sin `CFBundleURLTypes` (no URL schemes / deeplinks → vector de ataque externo cerrado).
- Sin `Process()` / `NSTask` / shell exec en código.
- `EngineKit/Package.swift` sin dependencias externas (cero supply chain risk).
- `fileImporter` con `allowedContentTypes` restrictivos.

---

## Resultado

- 🔴 4/4 críticos aplicados
- 🟡 3/5 recomendados aplicados, 2 diferidos con justificación
- 🟢 12 áreas verificadas limpias
- 1 PR (#14) abierto en `chore/security-cleanup`, listo para merge antes de abrir el repo al público.

**Pendientes externos** (no son de seguridad):
- Aprobación del Apple Developer Program ($99).
- Compra del dominio `cameraman.dev` + hosting de Privacy Policy.
- Añadir `PrivacyInfo.xcprivacy` al target de Xcode (drag&drop manual).
- Screenshots App Store.
