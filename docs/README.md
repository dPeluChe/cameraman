# labs-cameraman — Documentación

> Índice de documentación técnica del proyecto.

## Raíz del proyecto

| Archivo | Contenido |
|---------|-----------|
| [../README.md](../README.md) | Overview público — features, install, build, contributing |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Cómo clonar, buildear, testear y contribuir |
| [../LICENSE](../LICENSE) | MIT |
| [../CLAUDE.md](../CLAUDE.md) | Guía para asistentes AI trabajando en el repo |

## Landing page

La landing vive en un repo separado: [`dPeluChe/cameraman-landing`](https://github.com/dPeluChe/cameraman-landing)
(React + Tailwind + framer-motion, deployada a [cameraman.dev](https://cameraman.dev) via Vercel).
El `index.html` en esta carpeta es el landing legacy de GitHub Pages (superseded, kept for backwards compat).

## Archivos activos en `docs/`

| Archivo | Contenido |
|---------|-----------|
| [DEV_ONBOARDING.md](DEV_ONBOARDING.md) | **Empieza aquí** — arquitectura, setup, patrones clave |
| [CHANGELOG.md](CHANGELOG.md) | Historial de versiones (current: v0.7.0) |
| [TASK_TODO.md](TASK_TODO.md) | Backlog de tareas pendientes |
| [PRD.md](PRD.md) | Product requirements (referencia de diseño inicial) |
| [TECH_SPEC.md](TECH_SPEC.md) | Tech spec inicial (referencia arquitectural) |

## Trabajo completado

Ver [`TASK_COMPLETED/`](TASK_COMPLETED/) para logs de sesiones por mes (formato `YYMM.md` o `YYMM_sessionN.md`).

## Archivado

Ver [`ARCHIVED/`](ARCHIVED/) para documentos históricos obsoletos.

## Branding

Ver [`branding/`](branding/) para los assets de identidad (AppIcon, DMG background, wordmark). El source editable vive en `cameraman_designs.pen` (Pencil).

## Reglas de escritura

1. Solo `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `LICENSE` (y opcionalmente `CHANGELOG.md`) en raíz del proyecto
2. Todo lo demás va en `docs/`
3. Nombres de archivo en `UPPERCASE_SNAKE_CASE.md`
4. No crear docs de feature una vez que la feature está en el código — usar el CHANGELOG y el código mismo como source of truth
5. Archivar (no borrar) — los archivados llevan nota al tope explicando por qué
