# UI Theming, Layout & Components

How color, layout, and shared components work in the Cameraman app, and the rules
to follow when adding or changing UI.

## Color

How color works in the Cameraman app, and the rules to follow when adding or
changing UI. The app defaults to **following the system appearance**, but the user
can force Light or Dark in **Preferences → General → Interface → Appearance**. That
picker writes `@AppStorage(AppAppearance.storageKey)` and applies via
`NSApp.appearance` (see `Theme/AppAppearance.swift`), which covers both SwiftUI
scenes and AppKit windows. Applied at launch from `AppDelegate`. UI must therefore
look correct in **both** modes — never assume one.

## The semantic palette — `AppColor`

Defined in `App/Sources/Cameraman/Theme/AppColor.swift`. Always prefer these over
raw `Color.white` / `Color.black` / hex for **app chrome** (panels, rows, labels,
separators, wells).

| Token | Use for | Backed by |
|---|---|---|
| `windowBackground` | Window / large surface backgrounds | `NSColor.windowBackgroundColor` |
| `controlBackground` | Control surfaces (lists, fields) | `NSColor.controlBackgroundColor` |
| `underPage` | Recessed background behind content | `NSColor.underPageBackgroundColor` |
| `panel` | Elevated panel drawn over content | `Color(light:dark:)` |
| `panelTranslucent` | Floating/custom popover panel | `Color(light:dark:)` |
| `inset` | Subtle inset fill for rows/wells | `Color(light:dark:)` |
| `insetSelected` | Selected row/well fill | `Color(light:dark:)` |
| `textPrimary` | Primary text *(prefer SwiftUI `.primary`)* | `NSColor.labelColor` |
| `textSecondary` | Secondary text *(prefer `.secondary`)* | `NSColor.secondaryLabelColor` |
| `textTertiary` | Tertiary / hint text | `NSColor.tertiaryLabelColor` |
| `separator` | Dividers, hairlines | `NSColor.separatorColor` |
| `border` | Subtle borders | `Color(light:dark:)` |
| `scrim` | Dimming behind modal overlays | `Color(light:dark:)` |

For text, the SwiftUI semantic styles `.primary` / `.secondary` are preferred when
they fit — they already adapt. Use `AppColor.text*` only when you need a `Color`.

`Color(light:dark:)` (also in `AppColor.swift`) resolves at render time against the
active appearance — use it for brand surfaces that have no fitting system color.

## The decision rule — three categories

Before writing a color, classify it:

### 🔴 UI chrome → **semantic** (must adapt)
Panels, rows, labels, separators, wells, anything drawn on the window background.
A hardcoded `Color.black`/`Color.white` here **breaks in the opposite mode**
(e.g. white text on a white panel). Use `AppColor` / `.primary` / `.secondary`.

### 🟡 On-content or colored-surface → **fixed** (correct as-is)
Stays a literal color **by design**, because it sits on something that isn't the
adaptive window background:
- Text/icons on a strongly-colored pill (recording HUD: red/orange pills).
- The black video stage / letterbox behind a preview (convention: always black).
- Selection strokes / trim handles drawn on clips filled with `track.color`.
- Cursor highlight or overlays drawn on top of the video frame.
- The teleprompter surface (intentional dark reading surface).
- Full-screen capture-area scrim drawn over the desktop.

### 🟢 User content → **data, not theme** (never touch)
Colors chosen by the user and persisted as data — leave them. These flow through
`Color(hex:)`:
- Overlay stroke/text/background colors.
- Subtitle/caption colors.
- Canvas / background solid colors and gradients.

## Anti-patterns

- ❌ `Color.black.opacity(0.85)` as a panel background → use `AppColor.panelTranslucent`.
- ❌ `Color.white` for body text on chrome → use `.primary`.
- ❌ Overriding an adaptive control with a fixed color (e.g. `Divider().background(Color.white.opacity(0.2))`) → let it adapt, or use `AppColor.separator`.
- ❌ Converting a 🟡/🟢 color to semantic → this **breaks** the design (white-on-colored becomes invisible).

## Verifying color changes

Toggle **Preferences → General → Interface → Appearance** (or System Settings →
Appearance) between Light and Dark with the app open. Pay attention to: the
**Recording source selector**, the **recording window**, and custom popovers.

---

## Layout scale & components

Defined in `Theme/DesignSystem.swift` and `Theme/UIComponents.swift`. Use these
instead of ad-hoc literals so every window/sheet/section looks the same.

### Scales

| Scale | Values | Use |
|---|---|---|
| `Spacing` | `xs 4` · `sm 8` · `md 12` · `lg 16` · `xl 20` · `xxl 24` | All padding / `VStack(spacing:)` |
| `Radius` | `small 6` · `medium 8` · `large 12` | Buttons → cards → large surfaces |
| `ModalSize` | `small 440×420` · `medium 580×480` · `large 680×560` · `xlarge 760×640` | Sheet/window sizing |

### Components

- **`SettingsSection(_:subtitle:)`** — titled card (header + optional subtitle over
  content, wrapped in `.sectionCard()`). Use for every Preferences/inspector section.
- **`SheetHeader(_:subtitle:)`** — standard left-aligned header bar for sheets/windows
  (`.title3` semibold + caption over `controlBackground`).
- **`EmptyStateView(icon:title:message:action:)`** — icon + title + message + optional
  CTA. The single canonical empty state.
- **`.sectionCard(padding:)`** — `padding + controlBackground + Radius.medium`.
- **`.modalFrame(_:)`** — fixed frame for a `ModalSize`.

### Conventions

- **Headers:** sheets/windows use `SheetHeader`; sections use `SettingsSection`.
- **Buttons:** one `.borderedProminent` (primary) per view; `.bordered` for secondary;
  `.plain` only for genuinely chromeless/navigational controls; `.link` only for URLs.
- **Pickers:** 2–4 visible options → `.segmented`; 5+ → `.menu`; exclusive list → `.radioGroup`.
- **Text:** prefer semantic fonts (`.title3`/`.headline`/`.subheadline`/`.caption`) and
  `.secondary`/`.tertiary` foreground over hardcoded sizes and `.opacity(...)`.

> Migration is incremental: the foundation adds these without rewriting every view at
> once. New/changed UI must use them; old views are migrated group by group.
