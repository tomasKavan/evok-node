# 21 — Tooling and package

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** everything that ships or supports the daemon without being part of it — the migration tool, the
Debian package, and the repo's own toolchain.

**Covers**

- **The one-shot migration tool.** Reads `/etc/evok/config.yaml` and `/var/lib/evok/alias.yaml` and
  writes ours. A separate binary, never the daemon; a pure function over two file formats, so it is
  fixture-testable. What it warns about when it cannot represent something, and that it leaves
  `/etc/evok` pristine (`GOALS §The drop-in guarantee`).
- **Debian package and installation.** `Conflicts: evok`, `Depends: nginx`, the `:80` site conflict,
  `postinst`, which `run.d` directory to install into, and rollback. Several of these are facts we do
  not have yet — see Open.
- **The repo toolchain**, and why each piece is load-bearing rather than taste: npm workspaces with
  `tsc -b` project references, Node 24, `dependency-cruiser` as the layering guard, `npm run verify`.
  `to_revision/0013` proposes the set; this file decides it.
- **What is deliberately not here:** the test instruments. `dev/19` and `dev/20` own the simulator and
  the rig, and RT-15 keeps them out of the daemon's dependency graph entirely.

**Inputs:** research/03 · research/13 · `GOALS §The drop-in guarantee` · to_revision/0006, 0013 ·
[`STATUS.md`](../plan/STATUS.md) blocked items

**Open:**

- **The licence is undecided** — MIT or Apache-2.0. It blocks nothing until we publish, and it is
  packaging's problem when it lands.
- **Packaging facts pending the capture trip:** evok's systemd unit names, its nginx site file, and
  which of `/usr/lib/unipi/run.d` or `/opt/unipi/os-configurator/run.d` exists and what owns it. All
  cheap to answer on hardware and unanswerable without it; tracked in
  [`STATUS.md`](../plan/STATUS.md).
