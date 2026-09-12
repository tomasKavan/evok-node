# 12 — Driver plugins

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** writing a driver that is not ours, and having it work as well as ours.

**Covers**

- **The minimum surface:** what you implement, and what the driver kit gives you for free.
- **Writing introspection.** Describing endpoints, kinds, units and capabilities so that an API which
  has never heard of you can present them correctly. This is the hard part and the bulk of the file.
- **Adding data types to internal messaging:** what is extensible, what is closed, and what happens
  when two plugins add the same thing under different names.
- **Manifest, discovery, versioning**, and compatibility across evok-node versions.
- **Dos and don'ts, concrete:** do not block · do not throw across the boundary · do not share state ·
  do not import other packages' internals · do not assume you are in-thread.
- **Logging standards** for plugin authors.
- A **worked minimal example** — small enough to read in one sitting.

**Inputs:** 03 · 05 · [`rules/packages/drivers.md`](../rules/packages/drivers.md) · to_revision/0003

**Open:** the plugin isolation model is **deliberately deferred** (recorded in
[`STATUS.md`](../plan/STATUS.md)), and G-1's one-process-for-now means the message boundary is all
that keeps the options open. So say what a plugin must not rely on, in order that isolation can
arrive later without breaking it.
