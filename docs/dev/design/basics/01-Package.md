# Repository and packages

Design of this repository, artifacts and toolchain to generate them.

## Repository structure

This is a monolith repository containing all:

- Documentation (development and user),
- Source code,
- Source code to testing tools,
- Tooling scripts and supporting files to create artifacts,
- Testing fixtures,
- Plan and
- Agentic work supporting files.

All documentation is in [`/docs/dev`](/docs/dev/README.md) or [`/docs/user`](/docs/user/README.md). Follow there to learn more.

To organize source code and logic modules npm workspaces are used. All source code is in [`/packages`](/packages) directory. All packages lives under `@evok-node/` namespace and are buildable independedly. 

### Package list

Relevant to the tool:
- **[`main`](/packages/main/)** - the daemon: config, validation, spawn, supervise, reload. Documented in this file, in [01-Achitecture](/docs/dev/design/evok-node/01-System-architecture.md) and in [02-Configuration.md](/docs/dev/design/evok-node/02-Configuration.md).
- **[`messaging`](/packages/messaging)** - the internal driver↔API contract: envelopes, introspection. Documented in [03-Internal-messaging](/docs/dev/design/evok-node/03-Internal-messaging.md).
- **[`modbus`](/packages/modbus)** - modbus transport layer: framing, correlation, timing, circuit breakers.
- **[`hw-definitions`](/packages/hw-definitions)** - unipi hardware definitions. Relevant mostly for `driver-onboard` and `driver-extension`.
- **[`driver-kit`](/packages/driver-kit)** - shared driver runtime: scan loop, reading state, handshake, introspection. See [06-Driver.md](/docs/dev/design/evok-node/06-Drivers.md).
- **[`driver-onboard`](packages/driver-onboard)** - the controller's own I/O sections, over Modbus TCP. Documented in [08-Onboard-driver.md](/docs/dev/design/evok-node/08-Onboard-driver.md).
- **[`driver-extension`](packages/driver-extension)** - Unipi RTU extensions, one instance per RS-485 line. For docu see [09-Extension-driver.md](/docs/dev/design/evok-node/09-Extension-driver.md).
- **[`api-nextgen`](packages/api-nextgen)** - Our new WebSocket + HTTP API/surface. Owns its public schema. Documented in [15-Nextgen-API.md](/docs/dev/design/evok-node/15-Nextgen-API.md).
- **[`api-compat`](packages/api-compat)** - the EVOK 3.x surface. See in [14-Compat-API.md](/docs/dev/design/evok-node/14-Compat-API.md).
- **[`ui`](packages/ui)** - the web SPA, over the nextgen API. Described in [16-Inspector-UI.md](/docs/dev/design/evok-node/16-Inspector-UI.md).

Supporting, testing and other:
- **[`simulator`](packages/simulator)** - Tool to simulate modbus slave based on given static map and configurable event reaction. See [`design/simulator`](/docs/dev/design/simulator/README.md).
- **[`rig`](packages/rig)** - hardware-rig control service. Private, low level access to devices. No sharing code with main tool. Documented in [`design/test-rig](/docs/dev/design/test-rig/README.md). Rig is private package.
- **[`client`](packages/client)** - Nextgen API TypeScript client. Based on [user docu](/docs/user/README.md), TBD: deployed to npm `@evok-node/nextgen-cli-ts.
- **[`evok-migration`](packages/evok-migration)** - Migration tool to convert classic evok config to `evok-node` format. See in [Rplacing classic evok](#replacing-classic-evok).

## Toolchain

Every package is buildable by `tsc -b`. All together are buildable by same command run from the repo root. Cleaning si done by `tsc -b --clean`. NPM shortcuts are `npm run build` and `npm run clean`

Linting is done on the repo root by `eslint .` and `eslint . --fix`. Use NPM shortcuts `npm run lint` and `npm run lint:fix`.

Integrated [dependency cruiser DAG](/.dependency-cruiser.cjs) enforcing proper dependecy imports between packages. Run by `depcruise packages --config .dependency-cruiser.cjs --output-type err-long` or simple by `npm run layering`.

Test bach is performed by `vitest run` (`npm run test`) or interactively by `vitest` (`npm test:watch`). Coverage could be generated and checked by `vitest run --coverage` (`npm run coverage`)

[R ??] **Use NPM shortcuts instead of direct script calls**
When using toolchain it's desired to use shortcuts defined in package.json instead of calling directly. 

## Packaging and Installation

Tool is installed with Debian packages onto [Unipi Base OS](https://kb.unipi.technology/en:files:software:os-images:00-start) (Debian arm Linux). Supported versions are Debian 12 and Debian 13. 

There are two packages `evok-node` and `evok-node-data`.

### `evok-node-data`

Holds configuration files for supported Unipi devices and `autogen` script used by (plugged to) `unipi-os-configurator` to configure specific device.

Package lives in [`/packages/hw-definitions`](/packages/hw-definitions/README.md). 

Package contains set of yaml files using Modbus transport description format defined at [07-Modbus-driver](/docs/dev/design/evok-node/07-Modbus-driver.md). Each file describes endpoints reacheable using Modbus (TCP or RTU) connected to Unipi device. Modbus driver uses these files to read/write/configure endpoints using Modbus commands.

Package also contains [autogen script](/packages/hw-definitions/src/autogen.py). This script is plugged into `unipi-os-configurator` and called after installation and when any HW changes. It creates `autogen.yaml` file in `/etc/evok-node/`. It can be used to configure `evok-node` daemon. See [`02-Configureation.md`](/docs/dev/design/evok-node/02-Configuration.md) and respective "configuration" sections of [08-Onboard-driver.md](/docs/dev/design/evok-node/08-Onboard-driver.md) and [10-Onewire-driver.md](/docs/dev/design/evok-node/10-Onewire-driver.md).

Autogen script is installed to `/opt/unipi/os-configurator/run.d/61-evok-node-autogen.sh`. To run autogen after installation postinst script contains
```
dpkg-trigger os-configurator-force
```
in configure case.

Script greatly inspired by [autogen script](https://github.com/UnipiTechnology/evok-unipi-data/blob/main/evok-autogen.py) in `evok-unipi-data` package.

Notes:
- `Recommends: unipi-os-configurator`
- All yaml files with hw definitions are installed to `/etc/evok-node/hw_definitions`. Files are considered as conffiles and should be listed in controlfile.

### `evok-node`

TBD

### Replacing classic evok

`evok` and `evok-node` are in conflict. Can't be installed on one system at the same time. (Occupying same port and openning same serial files). `evok-unipi-data` and `evok-node-data` is ok to have on one system simultaneously.

To replace `evok` with `evok-node` with preserving configuration it's necessary:
1. Uninstall `evok` ! but not purge !
2. Install `evok-node`
3. Run migration tool
4. Optionally purge 

## Config migration script

`evok-node` has `evok` configuration [migration tool](/packages/evok-migration). Migration tool understands 
