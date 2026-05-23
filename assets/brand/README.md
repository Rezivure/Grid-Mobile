# Grid · Brand Kit

End-to-end encrypted location sharing. Open source. Self-hostable.

This kit contains every asset needed to apply the Grid brand to a product, marketing site, App Store listing, or partner integration. Everything is generated from a single set of geometric primitives — there are no proprietary source files. SVGs are the source of truth; PNGs are exported renders.

---

## Folder structure

```
brand-kit/
├── 01-logos/         Symbol — the 3×3 grid with mint pin
├── 02-wordmark/      "grid" wordmark alone
├── 03-lockups/       Symbol + wordmark, horizontal & vertical
├── 04-app-icon/      iOS app icon at every required size
├── 05-favicon/       Browser favicons, 16–512px
├── 06-patterns/      Repeating brand patterns
└── 07-splash/        iOS launch screens
```

---

## The mark

The Grid symbol is a **3×3 dot grid with a single mint pin** in the top-left position.

- Eight neutral grey dots at `radius 2.4u` form a coordinate plane.
- The top-left is replaced by a mint pin — "you" on the grid.
- Pin geometry: bulb at `(12, 11)`, radius `2.4u`, tip at `(12, 14.5)`. Bulb arc joins the tail `15°` below its equator with a soft bezier curve.

Construction is on a 40-unit canvas. Use the SVG as the source of truth — it scales perfectly.

---

## Color

| Name      | Hex        | RGB              | Role                              |
|-----------|------------|------------------|-----------------------------------|
| Mint      | `#1FD9A0`  | `31, 217, 160`   | Primary accent. Pin only.         |
| Ink       | `#0E1115`  | `14, 17, 21`     | Deepest foreground.               |
| Shell     | `#191B1E`  | `25, 27, 30`     | Dark surface. App icon backplate. |
| Paper     | `#FAFAF9`  | `250, 250, 249`  | Light surface.                    |
| Slate     | `#5A6670`  | `90, 102, 112`   | Secondary text.                   |
| Mint Deep | `#0B5840`  | `11, 88, 64`     | Type on mint surfaces.            |

Mint is the only saturated color in the system. Use it sparingly. The brand earns its accent by never overusing it.

---

## Typography

| Use            | Family       | Weight | Notes                                  |
|----------------|--------------|--------|----------------------------------------|
| Wordmark       | Geist        | 600    | Lowercase. Letter-spacing -4%.         |
| Headlines / UI | Geist        | 500–700| Tracking -1% to -3%.                   |
| Body           | Geist        | 400    | 15px base, 1.5 line-height.            |
| Labels / Data  | Geist Mono   | 500    | All caps. Tracking +6–8%.              |
| Code / Crypto  | Geist Mono   | 400–500| Key fingerprints, coordinates.         |

Geist is free and open source: <https://github.com/vercel/geist-font>.

---

## Usage rules

### Do

- Use the symbol on Shell, Paper, or Mint surfaces only.
- Maintain clear space equal to one full grid-dot diameter (4.8u) on all sides.
- Pair the mark with Geist Mono labels for caption-level supporting text.
- Use SVG whenever possible.

### Don't

- Recolor the pin. The pin is always mint.
- Rotate or skew the mark.
- Add stroke, shadow, gradient, or 3D effects.
- Stretch the proportions — keep the symbol square.
- Replace the pin with a different shape (triangle, star, custom icon).
- Use the pin alone — the grid context is required.
- Use the mark below 24px — switch to the wordmark below that scale.

---

## File reference

### Symbol (`01-logos/`)
| File                                    | When to use                          |
|-----------------------------------------|--------------------------------------|
| `grid-symbol-color.svg`                 | Light backgrounds. Default.          |
| `grid-symbol-color-dark.svg`            | Dark backgrounds.                    |
| `grid-symbol-mono-ink.svg`              | Single-color print. Dark surfaces.   |
| `grid-symbol-mono-white.svg`            | Single-color print. Dark surfaces.   |
| `grid-symbol-on-mint.svg`               | When background is mint.             |
| `grid-symbol-color-{64–1024}.png`       | Rasterized at common sizes.          |

### Wordmark (`02-wordmark/`)
| File                              | When to use                                       |
|-----------------------------------|---------------------------------------------------|
| `grid-wordmark-ink.svg`           | Light backgrounds.                                |
| `grid-wordmark-white.svg`         | Dark backgrounds.                                 |
| `grid-wordmark-mint.svg`          | When the mark needs to fully embrace the accent.  |

SVGs reference the Geist font — install it for accurate rendering.

### Lockups (`03-lockups/`)
| File                                          | When to use                       |
|-----------------------------------------------|-----------------------------------|
| `grid-lockup-horizontal-ink.svg`              | Headers, marketing banners.       |
| `grid-lockup-vertical-ink.svg`                | Centered hero treatments.         |
| `*-white.svg`                                 | Dark surfaces.                    |

### App Icon (`04-app-icon/`)
| File                                  | iOS context                            |
|---------------------------------------|----------------------------------------|
| `grid-app-icon-appstore-1024.png`     | App Store. **No rounded corners.**     |
| `grid-app-icon-180.png`               | iPhone @3x · Home screen.              |
| `grid-app-icon-167.png`               | iPad Pro · Home screen.                |
| `grid-app-icon-152.png`               | iPad @2x · Home screen.                |
| `grid-app-icon-120.png`               | iPhone @2x · Home screen.              |
| `grid-app-icon-87.png`                | iPhone @3x · Settings.                 |
| `grid-app-icon-80.png`                | Spotlight @2x.                         |
| `grid-app-icon-76.png`                | iPad @1x · Home screen.                |
| `grid-app-icon-60.png`                | iPhone @3x · Notifications.            |
| `grid-app-icon-58.png`                | iPhone @2x · Settings.                 |
| `grid-app-icon-40.png`                | Spotlight @1x · Settings @2x.          |
| `grid-app-icon-29.png`                | Settings @1x.                          |
| `grid-app-icon-20.png`                | Notifications @1x.                     |

**The App Store icon must not have rounded corners** — Apple applies its own mask. Other sizes are pre-rounded for inline use.

### Favicon (`05-favicon/`)
| File              | Use                            |
|-------------------|--------------------------------|
| `favicon.svg`     | Modern browsers. Vector.       |
| `favicon-16.png`  | Legacy browser tab.            |
| `favicon-32.png`  | Standard tab.                  |
| `favicon-192.png` | Android home screen.           |
| `favicon-512.png` | PWA manifest.                  |

### Patterns (`06-patterns/`)
| File                                | When to use                                  |
|-------------------------------------|----------------------------------------------|
| `grid-pattern-full-color.svg`       | Hero backgrounds, marketing.                 |
| `grid-pattern-low-color.svg`        | Subtle texture, sub-surfaces.                |
| `grid-pattern-dark.svg`             | Dark-mode hero backgrounds.                  |

### Splash (`07-splash/`)
| File                              | Device target                |
|-----------------------------------|------------------------------|
| `grid-splash-1284x2778.png`       | iPhone 14 Pro Max and family |
| `grid-splash-1290x2796.png`       | iPhone 15 Pro Max and family |

---

## Voice

Trustworthy. Utility-first. Like Signal — not like a consumer social app.

- Speak in declarative present tense.
- Mono-caps labels for technical context (`SHARING WITH 2 · E2EE`).
- Avoid emoji in product UI.
- Never write "we" — write "Grid does X."

---

## License

The mark, wordmark, and brand pattern are the trademarks of the Grid project. The brand kit assets in this folder are released to the project's contributors and partners for use in promoting Grid. Source code for the app itself is AGPL-3.0.

---

**Version 1.0** · 2026
