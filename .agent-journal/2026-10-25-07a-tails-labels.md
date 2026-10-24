# 2026-10-25 — 07a: tails, labels, typeInfo

Role: system designer & architect. Docs only.

## Decisions (Tomas)

- Tail grammar `<unit>.<kind>.<nn>` for every feature; kind verbatim with its dots — one grammar for 08 and 09, sections no longer collide.
- Index never dropped, also for `count: 1` and unit-level kinds (`2.unipi.pwmOpt.01`) — one rule, no per-kind flag.
- Index counts per kind across all features of that kind in one definition, YAML order — avoids EVOK #209-style renumbering.
- Every definition kind contains a dot; dot-free segment after `<unit>.` reserved for driver-level devices.
- Label = name printed on hardware, templated in the definition (`RO{unit}.{n}` or `labels: [...]`), carried as introspection metadata (`BindOptions.label` → `DeviceRef.label`), not a field — a primitive `@` can't take siblings, and definitions are section-local.
- `<unit>.typeInfo` (kind `modbus.typeInfo`, renamed from `unipi.unitType` — not Unipi-specific), bound by 08 and 09. Plain `reading()`, the one non-`polled()` reading.
- Alias binders (`targetKind`) dropped for now — no concrete case; moved to 07a §14 with vendor-neutral kinds.

## Edited

05a §3.5/§4/tests, 07a §1/§2/§3/§3a (new)/§4/§7/§10/§12/§13/§14, 08 §8/tests, 09 §3a/§7/§9/tests, 03 §1 example, 12a examples, 12c-04 §3.10.

## Left

- research/13 §4 YAML and research/matter still use old syntax/tails (`kind: DI`, `reg:`, `EXT:7.type`) — researcher's to update.
- 05a §3.3 `DIDevice` example is stale against 07a §10.1 (kind, `polled`, `directSwitch` shape).
- Label variable for extensions: whether printed names contain the Modbus address is unverified.
