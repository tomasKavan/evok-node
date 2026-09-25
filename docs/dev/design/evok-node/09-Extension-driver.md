# 09 — Extension driver

## 1. Scope

Unipi extensions and accessories over RS-485, plus a third-party Modbus device sharing the same bus — one driver instance per line, never per device. The line, not the unit, is the thing this driver owns: everything else in this file — addressing, the shared-bus budget, failure isolation — follows from that, because a line is a single serialised resource several units contend for, and only the line's own owner can arbitrate it. The transport itself is `07`'s `ModbusTransportConfig`, so `kind: 'modbus-tcp'` is legal here too (01 §11 calls this driver "the transport driver for one RS-485/TCP extension line") — a gateway exposing extensions over TCP, say — but everything below assumes RTU unless said otherwise, since that's every case the corpus actually documents.

This driver owns transport lifecycle (`open`/`close`) and unit/line topology only. Binding — turning a resolved definition into live `driver-kit` devices — is [`hw-modbus-kit`](07a-Hw-modbus-kit.md)'s job, exactly as it is for `08`: this file calls `handshake()` then `bindDefinition()` (07a §9, §12) once per configured unit, and never touches `driver-kit` or a register address directly. Its own DAG entry is `['messaging', 'modbus', 'hw-definitions']` (07a §11) — `hw-definitions` stays direct only for id/config resolution.

**Must not depend on:** any api, `main`, another driver, `driver-kit` directly.

## 2. Configuration

No autogen path exists for this driver at all — `13 §1`: `type: extension` is "always declared; autogen is not allowed." A line's units are never discovered, only declared:

```ts
interface ExtensionConfig {
  transport: ModbusTransportConfig;                 // 07 §4 — modbus-rtu, ordinarily
  rates?: Record<string, number>;                   // named rate -> ms; overrides this driver's own defaults, §9
  devices: { unit: number; definition: string }[];   // never optional, never autogen-supplied — always present, possibly empty
}
```

```yaml
drivers:
  EXT:
    type: extension
    transport: { kind: modbus-rtu, path: /dev/ttyNS0, baud: 19200, parity: none }
    rates: { fast: 200, slow: 5000 }
    devices:
      - { unit: 1, definition: modbus/unipi/xs11 }
      - { unit: 7, definition: custom/modbus/acme/wm-3f }
```

Rules, checked at config-parse time, needing no handshake — the same class as `08 §2`'s:

- **`unit` is unique per line.** Two configured units on the same `EXT` instance naming the same `unit` is fatal at config-parse — never a precedence question, never a silent last-write-wins. This is `06 §3`'s duplicate-address lesson (R04-2) applied one level up, before any wire traffic, rather than discovered as a wrong-relay bug on hardware.
- **`devices: []` is legal.** A line with nothing configured on it yet is a normal, not incomplete, configuration — no different from `08 §7`'s "zero onboard sections is legal."
- **Every `definition` must resolve**, the same fatal-at-`configure()` check `08 §6` already states for onboard: a `devices:` entry naming an id with no matching file anywhere (shipped or custom, `13 §1`'s two namespaces) rejects `configure()` outright, before any transport opens.

## 3. Addressing

A unit's address lives on the physical module, set by DIP switches or a software register — this driver never assigns one, only expects one. The precedence is a real trap worth stating plainly rather than assuming an installer already knows it (research/02 §5): the module reads its DIP switches once, at its own startup; if **any** switch is ON, the DIP address wins, at **even** parity; if **all** are OFF, the factory software default applies instead — address **15**, **no** parity. Moving a module between the two silently changes its parity, not just its address. This driver has no way to observe which mode a given module is in — the config's `unit` is a claim about what a client will find there, checked only at handshake (§5), never derived or corrected by this file.

Units are declared, never discovered. There is no bus-scan mode, deliberately: a full 1–254 sweep on top of every already-configured unit's own scan traffic is exactly the kind of bus-time cost `§4` exists to keep visible and bounded, for a capability (auto-discovery) `13 §1` doesn't offer in the first place. Two failure shapes fall out of this, both already covered by existing machinery rather than needing new vocabulary:

- **A collision** — two configured units claiming the same `unit` — is `§2`'s config-parse check; it never reaches a handshake attempt.
- **A silent unit** — a configured `unit` nothing answers, or something else entirely answers at census/hardware-ID level — is a handshake failure (§5), and `§8` states what this driver does about it: never fatal, never mistaken for a healthy unit reading zero.

## 4. Serial timing and the shared-bus budget

Wire time dominates here in a way it never does for `08`'s Modbus-TCP-to-loopback case, and that difference is this driver's own to manage, not `07`'s or `07a`'s. Per research/08: a 10-register block at the Unipi default of 19200 baud, 8N1 costs ~17 ms of wire time plus t3.5's own ~2 ms of mandatory inter-frame silence — already handled by `07`'s `ModbusTransport`, never reimplemented here. What `07`'s per-line mutex does *not* do is add up: with M units sharing one line, `cycle time ≈ Σ (transaction + t3.5)` over every scanned block on that line — four `xS11`s at 19200 baud round-robin to ~77 ms; eight to ~154 ms.

That sum is this driver's own responsibility to compute and report, because only it can see every unit configured on its own line at once. At `configure()`, once every configured unit's `definition` has resolved (§2) — before any handshake, since block layout is a static fact of the resolved definition, never something that needs a live read — this driver sums each bound block's per-rate transaction cost across every unit on the line, and reports the resulting per-line cycle time at startup. The reason this matters beyond a diagnostic number: the factory-default section master watchdog timeout is 2500 ms (research/06 §2.8), and a bus saturated by scanning starves a healthy unit's own MWD refresh into firing — issue #123's own failure, quantified. Following research/08 §6's target, this driver warns (or, past a harder threshold, refuses `configure()`) when the computed cycle time exceeds 25% of the shortest MWD timeout assumed across the line's configured units — "assumed" because the driver knows only each definition's factory-default `timeoutMs`, never a live device's currently-configured one; a value changed at runtime through `unipi.sectionWatchdog.timeoutMs` (07a §10.2) can invalidate this check silently, and that residual gap is left as an operational note, the same tier `08 §7` leaves its own single-client question at.

Raising the baud rate past 19200 is the single biggest lever available (research/08 §3: up to 4.2× at 115200) but is a site decision, never something this driver negotiates or auto-tunes — `transport.baud` is a plain config value, and the KB's own advice (lowest baud adequate for the EMC environment) is the installer's call, not this file's to second-guess.

Built-in `RateTable` defaults here are `{ fast: 200, slow: 5000 }` — two tiers, not `08`'s three, because research/08 §5's own split is exactly this: a fast bitmap/state block, and a slow block for counters and configuration, where "fast" already has to budget for one wire transaction's real cost rather than TCP-loopback's near-zero one. `rates:` (§2) overrides by name; an unresolved rate name at bind time is fatal, same as `08 §2`.

## 5. Model identification and handshake

Unchanged in mechanism from `08 §5`, applied per unit on a shared bus instead of per PLC section: `handshake()` then `bindDefinition()` (07a §9, §12) once per configured unit, before anything is bound for it. What's new to this driver, not to the mechanism, is `07a §9`'s own pluggability: a unit's `definition` names its own `handshake` — `'unipi.handshake'` by default, the identity/census/firmware-variant check every shipped Unipi definition already implies, or `none` for a bring-your-own device with no known identity block (§7). Nothing here re-derives that dispatch; this section only narrates it from a line's own vantage point.

## 6. Extensions versus accessories

One driver, one config shape, one handshake/bind path for both — the model never forks in code. The only real difference is which built-in kind a definition declares: an extension's channels bind through `07a §10.1`/`§10.2`'s per-channel and section-wide kinds (`unipi.di`, `unipi.do`, `unipi.sectionWatchdog`, …), an accessory's through `§10.3`'s single-`@` sensor kinds (`unipi.temp`, `unipi.humidity`, …) — and an accessory never binds `unipi.sectionWatchdog` at all, since nothing in the corpus gives one a master watchdog.

`xG18` is the case worth naming rather than leaving implicit: physically it's an extension — its own RS-485 unit id, its register map filed alongside the other extensions (`docs/modbus-reg-map/extensions/`) — but it binds purely accessory-shaped kinds, eight `unipi.temp` instances and nothing else (`07a §10.3`). Nothing about this driver treats it specially; it's an ordinary configured unit whose definition happens to declare sensor kinds instead of I/O kinds. `EMO-R8`'s eight relays are the opposite gap: a real extension, still blocked on binding anything at all, because no register map exists yet anywhere (`07a §10.3`, §11) — not a limitation of this driver, a gap in the corpus.

## 7. Bring-your-own definition

The practical path for a device this driver's own authors never heard of, and its limits. Namespace: `custom/modbus/<vendor>/<device>.yaml` (`13 §1`) — `acme`'s `wm-3f` sharing a line with ordinary Unipi units (§2's example) is the concrete shape. Past the definition file itself, three things a custom device may need, each already covered by `07a`'s own mechanism rather than anything specific to this driver:

- **An unknown `kind`.** Resolved the same way as any other — `resolveDeviceKind` (05a §3.5) — whether that kind is a plain, already-real `DeviceType` a third-party package ships, or an alias bound through a `ModbusKindBinder` whose `targetKind` is a real kind underneath (`07a §7`'s `acme.wm-relay` → `unipi.ro` example is exactly this case). Either way the type itself must already exist and be resolvable — a binder never fabricates one.
- **A register layout the generic walk can't express.** The same `ModbusKindBinder`, registered either directly (a driver-extension bundle statically depending on `acme`'s package, full typing, no manifest involved) or as a `kind: "modbus-kind-binder"` manifest entry resolved lazily the first time this line's `configure()` needs it (`07a §7`).
- **An identity check that isn't Unipi's.** A `handshake` name registered the identical two ways (`07a §9`) — direct `registerHandshake()`, or a `kind: "modbus-handshake"` manifest entry — or `none` when the device has no identity block to check at all.

The limit worth being honest about: none of this is a YAML-only extension point. A genuinely new kind or handshake is code — a package with its own `evokNodePlugin` manifest entry, or a build-time dependency — never something expressible purely inside the definition file itself. What the definition file *does* fully control is which already-registered kind, binder, and handshake name a given unit uses.

## 8. Failure modes

Same two-class split `08 §6` already establishes, restated at the level a shared bus adds one real consequence to:

**Startup-fatal: a `definition`, `handshake`, or custom `kind`/binder that doesn't resolve.** Checked at `configure()`, before any transport opens — a broken install, a typo'd id, or a plugin package genuinely missing. This instance never starts; no partial bind, no degraded unit.

**Runtime-degraded, never fatal: a handshake that fails against live hardware.** A census/hardware-ID mismatch, or the unit simply not answering — either way the unit's device(s) stay registered and answer the generic `unreachable` kind (03 §7), and handshake retries in the background, forever, exactly as `08 §6` states for onboard. The consequence specific to a shared line: `bindDefinition()` — and therefore that unit's own scan loop — never runs until handshake succeeds, so a degraded unit consumes no cycle-time budget on the bus at all (§4) while it's down. This falls out of the existing mechanism for free; it isn't a separate quarantine this file has to implement.

## 9. Binding and rates

Delegated entirely to `hw-modbus-kit`, identically to `08 §8`: this driver opens one `ModbusTransport` per instance, calls `handshake()` then `bindDefinition(def, rates)` once per unit (§5), and holds whatever `BoundDefinition` comes back until `stop()`. The built-in `RateTable` defaults are §4's `{ fast: 200, slow: 5000 }`; config's `rates:` (§2) overrides only the names it names.

## 10. Testing

Tier 1 (`design/basics/03-Testing.md`), against the simulator — no hardware:

- Config parse: two `devices:` entries sharing one `unit` on the same line is rejected, naming both; `devices: []` is accepted; an `autogen` key anywhere on a `type: extension` instance is rejected as a parse error, not silently ignored.
- Definition-resolution fatal: an unresolvable `definition`, `handshake` name, or custom `kind`/binder is rejected at `configure()`, before any transport call, naming which one.
- Cycle-time budget: a fixture line with several units' worth of fixture blocks computes the expected cycle time; a fixture whose sum exceeds 25% of the shortest fixture unit's factory-default MWD timeout warns (or refuses, past the harder threshold) at `configure()`, before any handshake runs.
- Runtime-degraded isolation: one fixture unit whose simulator handshake fails never starts a scan loop and never contributes to the line's cycle time, while a sibling unit on the same line handshakes and binds normally, unaffected.
- Extensions vs accessories: a fixture accessory-shaped definition (sensor kinds only) binds with no `unipi.sectionWatchdog` present; a fixture `xG18`-shaped definition (extension unit, accessory kinds) binds identically to any other accessory.
- Bring-your-own, end to end: a fixture custom unit using a manifest-declared `ModbusKindBinder` aliasing to a real fixture kind, and a manifest-declared `HandshakeFn`, handshakes and binds correctly, and a `GET`/`SET` round-trip reaches the real, aliased kind's own handlers.
- One full run against two simulated units on one line, of different kinds, end to end: `configure()` → per-unit `handshake()` → `bindDefinition()` → a `GET`/`SET` round-trip against at least one channel on each.
