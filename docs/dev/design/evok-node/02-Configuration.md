# 02 — Configuration

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** how one config file becomes a running set of module instances, and how it changes without a
restart.

**Covers**

- **Structure.** What is global, what is per-instance, and what a module owns outright. Instance
  identity — the thing reload compares on — is decided here.
- **The parse pipeline:** read → shape-validate (zod) → semantic-validate → resolve → hand each module
  its own slice. Which failures are fatal, which degrade, and what a partially valid config runs as.
- **Typing.** Schemas are the single source and types are derived from them, never the reverse
  (RCD-10). How a driver or API contributes its own schema **without `main` statically importing it** —
  manifest-loaded modules make this non-trivial, and it is the interesting part.
- **Reload.** What is diffed and how instances are compared; what is stopped, what is restarted, what
  survives untouched. Ordering, and the window in which old and new instances coexist. What each
  module is told, and what it must guarantee across the event.
- **Resource reservation.** Serial lines, TCP ports, unix sockets, definition files, 1-Wire buses:
  declared before start, checked for conflict, held for the instance's life. A conflict is a config
  error, not a runtime surprise.
- **EVOK config compatibility — and the boundary.** G-1's migration clause says the **daemon has no
  knowledge of EVOK's config or alias formats**; that knowledge lives in the one-shot migration tool
  alone. So this section says what the daemon consumes *after* migration and nothing about EVOK's
  format. **The migration tool itself has no dev doc yet** — see the gap noted in
  [`README.md`](README.md).

**Inputs:** research/03 · research/13 · to_revision/0006, 0014 (0007 was superseded by 0014 before the
set was dissolved)

**Open:** reload granularity — per-instance restart versus in-place reconfiguration, and whether the
module or `main` decides which it gets.


From GOALS.md - to review

4. **G-5 — Four kinds of data, four lifecycles.** Conflating the first two is where EVOK's alias handling failed (finding 3.9).

   | | Contents | Written by | Where |
   |---|---|---|---|
   | Config | Operator intent: buses, ports, scan rates, enabled APIs, auth, compat flags | A human by hand, or the migration tool at install — **never the daemon** | `/etc/evok-node/config.yaml` |
   | User data | Aliases, groups, ordering, labels, layout drawings, rules, plugin settings | Users, through the API at runtime | `/var/lib/evok-node/` — durable store |
   | Platform facts | What the hardware *is*: our hardware definitions, our generated inventory | **Us alone** — our package ships the definitions, our generator writes the inventory; never a human by hand, never the daemon | `<pkg>/definitions/`, `/etc/evok-node/hw_definitions/custom/`, `/etc/evok-node/autogen.yaml` |
   | Readings | Current values, health, counters | The scan loop | Memory only, never persisted |

   Platform facts are descriptions of hardware, not intent. **Frozen per load, not once per process**:
   immutable and `readonly` while loaded (RCD-4), and reloaded when hardware change is detected.
