# 20 — UI library for the Inspector SPA

**Research, not design.** Facts behind the UI library of `@kapsle/ui` (16, M3.9). Proposals in §5 are not binding.

Input from Tomas (2026-11-24):

- PrimeVue was the default choice; PrimeVue 5 is no longer MIT.
- Decided: **Nuxt UI v4** on Vue 3 + Vite, without the Nuxt framework.
- The SPA loads nothing from the internet — a node may run on a LAN with no internet.

## 1. PrimeVue 5 license

From PrimeVue 5, PrimeNG 22 and PrimeReact 11, PrimeTek ships under the proprietary **PrimeUI License**. MIT versions stay MIT [V S1]. Also moved: `@primeuix/themes` 3, `@primeuix/styled` 1, `primeicons` 8 [V S4].

| | Community (free) | Commercial |
|---|---|---|
| Who | **All** of: < $1M revenue, < 5 devs, < 10 employees, < $3M funding; or individuals, students, non-profits, **non-commercial** open source [V S1, S2] | everyone else |
| Price | 0, renewed every 12 months by reconfirming eligibility [V S1] | $599/dev to end of 2026, $799 from 2027; updates $399/dev/year [V S1] |
| Key | required; offline check; a missing or expired key shows a license notice [V S2] | same |
| Limits | no redistribution "as a component library or development tool"; an OEM license when "third parties develop with the Software"; no source extraction [V S2] | same |

PrimeVue 4.x: security fixes only, no end date stated [V S3]. OpenVue — MIT fork of PrimeVue 4.5.5, same API, `npx @openvue/migrate`; 1.0, ~400 stars, one named maintainer [V S5].

## 2. Why PrimeVue 5 does not fit kapsle

- `@kapsle/ui` is published to npm and served by every node: the key ships in a public build. Whether a notice appears on deployed nodes after the key expires: [GAP].
- kapsle's own license is not chosen (`LICENSE.md` is empty). "Non-commercial open source" is unclear when installers deploy kapsle commercially [I].
- `inspector-panel` plugins (02b) are third parties developing against the SPA — may need an OEM license [I]. Gazetta has the same open question [V S4].
- Each contributor needs a key; Community covers up to 4 developers [V S2].

## 3. Candidates (all MIT)

| Library | Base | Data table | Note |
|---|---|---|---|
| Nuxt UI v4 | Reka UI + Tailwind v4 + Tailwind Variants [V S6] | `UTable` on TanStack Table [I] | 110+ components, ex-Pro included [V S7]; plain Vue via Vite plugin [V S6] |
| OpenVue | PrimeVue 4.5.5 fork [V S5] | PrimeVue `DataTable` | young project |
| Vuetify 3 | Material | `VDataTableVirtual` [I] | JSON Forms has Vuetify renderers [I] |
| Naive UI | own, TS | virtual table [I] | small team [I] |
| Element Plus | own | `el-table-v2` [I] | admin style |
| shadcn-vue / Reka UI | copy-in | own, on TanStack | most work |

## 4. PrimeVue 5 vs Nuxt UI v4

| Need (16) | PrimeVue 5 | Nuxt UI v4 |
|---|---|---|
| Dense live table | `DataTable`: sort, filter, frozen columns, groups, virtual scroll, cell edit — built in [I] | `UTable`: more own code (filter UI, grouping, edit); virtualization [I] |
| Driver/device tree | `Tree`, `TreeTable` [I] | `UTree`, no tree table [I] |
| Forms from schemas (03a §4) | `@primevue/forms` + resolvers [I] | `UForm`, Standard Schema [I] |
| App shell | own | Dashboard, Sidebar, Panel components [V S7] |
| Charts | Chart in PRO Suite [V S8] | none — own (ECharts, uPlot…) |
| v4 → v5 | no breaking public API; root font 14 → 16 px with compat presets [V S8] | — |

## 5. Open for M3.9 (proposals)

- **Tailwind and plugin panels.** Tailwind builds CSS from scanned sources; an `inspector-panel` built in its own package is not scanned by the host build [I]. Options: a panel ships its own CSS; panels use only Nuxt UI components and props; the host scans installed panels.
- **Offline icons.** Nuxt UI icons go through Iconify; in plain Vue they may be fetched from the Iconify API at runtime unless the icon sets are installed locally [GAP]. The offline rule needs them bundled.
- **`UTable` with live diffs.** Whether it keeps up with every endpoint updating: [GAP] — a spike on that one view.
- **Charts** for trends: library not chosen.

## Sources

- S1 — The Next Chapter of PrimeTek: https://primeui.dev/nextchapter
- S2 — PrimeUI License (primevue 5.0.4): https://unpkg.com/primevue@5.0.4/LICENSE.md
- S3 — PrimeVue SECURITY.md: https://raw.githubusercontent.com/primefaces/primevue/master/SECURITY.md
- S4 — Gazetta issue #1542: https://github.com/gazetta-studio/gazetta-studio/issues/1542
- S5 — OpenVue: https://github.com/openvi-foundation/openvue
- S6 — Nuxt UI v4 README: https://unpkg.com/@nuxt/ui@4.11.0/README.md
- S7 — Nuxt UI v4 announcement: https://nuxt.com/blog/nuxt-ui-v4
- S8 — PrimeVue v5 migration: https://primevue.dev/migration/v5/
