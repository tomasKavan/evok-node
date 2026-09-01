# Testing

There are 3 services to be regulary, properly and thoroughly tested:

- `evok-node` service - this is the core of testing,
- helper simulator services and
- rig control service.

Simulator services and rig control service is tested only by first tier - unit tests. These components are made only to enable E2E testing of the `evok-node`. 

## How to test

3 tiers of testing are unit, simulator and hardware test rig. 

### Tier 1: Unit testing

Unit testing uses vite framework and it's run by `vitest run` or rather `npm run test`. Watch mode can be enabled by `vitest` or rather `npm run test:watch`.

[R ??] **Unit testing**
Each component of `evok-node`, simulators or rig control service must have it's own testing module. Using `src/**/*.test.ts` convention. Unit tests should include boundary scenarios and test of module's basic functionality.

[R ??] **Unit test focus**
Unit test must allways test at least codecs, data types, data conversions, address computaitons, transport framing, timeouts, counters and similar.

[G ??] **Design unit test before coding**
Read design docu before making the test design to understand what is tested module materiality. Before you start coding, design unit tests validating desired behavior.

[R ??] **Unit tests are fast**
The total battery of tests finishes under 2 minutes. 
[/]

Unit test should be performed on every save or at least before every commit. Unit tests are run by CI in Github on PR.

### Tier 2: Simulator testing

First level of E2E test is simulator. There is a set of [simulator tools](/packages/simulator/README.md), documented in [`/docu/dev/design/simulator`](/docs/dev/design/simulator/README.md). E2E Test suite (see [End to end (E2E) test suite](#end-to-end-e2e-test-suite)) runs prescribed tests using simulation tools.

[R ??] **Simulator testing**
Tests lives in [`/tests/e2e/sim`](/tests/e2e/sim/). To learn how to write test follow to [End to end (E2E) test suite](#end-to-end-e2e-test-suite).

[R ??] **Simulator testing: Transport** 
Thoroughly test each transport - (`0xFFFF → 0`, ≥200 000 transactions), asserting every response matches its own request. Plus one test per injectable fault, and specifically **stale-frame desync**: timeout, late response, next request to the same unit and function code — the late response must be rejected, never returned as the new answer.

[R ??] **Every fault has a named assertion about observable API behaviour.** "Device marked offline", "error returned with kind `bus_timeout`", "other devices unaffected" — never merely "does not crash".

[R ??] **One test per `evok` research finding**
[`/docu/dev/research/04`](/docs/dev/research/04-known-bugs-and-lessons.md) documents all real production failures with their mechanisms. Each bug should be covered by E2E tests.

The only exemption is a finding dispositioned `construction` in [`/docu/dev/research/14`](/docs/dev/research/14-bug-dispositions.md).
[/]

Tests on simulator can be run by `npm run test:simulate` (real command behind npm call - `vitest --project e2e-sim`). 

Simulator tests should be performed before every push. Simulator tests are run by CI in Github on PR.

#### Coding and testing a simulator

[R ??] **Devices and transports must be backed by simualor for testing**
For all supported devices, like Unipi onboard sections, Unipi extensions and sensors, 3rd party devices connected using Modbus etc., you must code a simulator for testing purposes. Simulator must expose all supported features of simulated device (eg. temperature sensor over Modbus RTU must expose calls to set observed temperature which must translates to respective modbus registers).

Similar for all suported transport layers. Modbus TCP/RTU, Onewire and all other transport layers must have respective simulators. Device simulators use instances of transport simulators.

[R ??] **Simulator validation**
Simulator static behavioar should be validated against generated fixuters with device registers. Validation should be done by unit tests. Fixtures hasn't common format - only device's unit test module must understand it. Usual process is: Obtain documentaiton from device vendor -> Generate fixtures in machine readable format -> Implement fixture reading in unit test module -> Write proper unit test module for device's simulator.

Dynamic behaviour may on be captured by fixtures, but rather implemented directly in unit test module.

### Tier 3: Hardware rig testing

Second level of E2E test is physical hardware test rig. Test rig is set up on maintainer premisess and only maintainer can run tests on it. 

Test rig is controlled by [test rig service](/packages/rig/README.md), documented in [`/docu/dev/design/test-rig`](/docs/dev/design/test-rig/README.md). E2E Test Suite (see [End to end (E2E) test suite](#end-to-end-e2e-test-suite)) runs prescribed tests using test rig client library.

[R ??] **Test rig tests scope**
Tests lives in [`/tests/e2e/rig`](/tests/e2e/rig/). Test rig should run the same tests as simulator does. Some simulator tests might be explicitly ommited due to a lack of HW or Test rig cappabilities - in this case allways explain in the sim test comments. 

Might add some additional test suitable only for HW rig.
[/]

Tests on rig can be run by `npm run test:rig` (real command behind npm call - `vitest --project e2e-rig`).

Test rig tests should be performed before every release of a new version by maintainer.

[R ??] **Simluator and HW rig test batteries are disjointed**
To keep things simple it was decided to have simulator and HW rig tests defined separately. The divergence risk is accepted and it might be addressed in the future.

### Other and common testing rules

[R ??] **No wall-clock sleeps.** 
Fake timers or an injected clock. A test that sleeps is a test that goes flaky on the CI runner.

[R ??] **Tests are independent and order-free.** 
No shared mutable module state.

[R ??] **No mocking our own code in E2E tests** 
If you need to mock there - use the simulator. Mocks assert what we believe; the simulator asserts what the maps say.

## End to end (E2E) test suite

Vitest based test suite to perform e2e tests. It lives in [`/tests/e2e`]. 

### Architecture

```
tests/e2e/
  vitest.config.ts
  harness/
    context.ts      // test context 
    define.ts       // definitions, platform getters, config factory, test factory
    platform-sim.ts // simulator specific factory - uses `simulators` 
    platform-rig.ts // rig specific factory - uses `test-rig`. Init and deploy to test rig, controlling rig over `test-rig`
    global-setup.ts // setup for vitests
  sim/
    sim01-di-edge-to-ws.test.ts
  rig/
    rig01-di-edge-to-ws.test.ts

```

### Test definition

Example of rig test (inspiration only, calls might be different):
```ts
// /tests/e2e/rig/01-di-edge-to-ws.test.ts

import { expect } from 'vitest'
import { platform, e2e, makeConfig } from '../harness/define.js`
import { race, setExTimeout } from '../harness/helpers.js'

const HARD_TIMEOUT_MS = 1000
const BUDGET_MS = 600

const config = makeConfig({
  id: 'di-edge-to-ws'
  title: 'DI rising edge arrives as nextgen WS diff',
  description: 'DI test on HW rig'
})

e2e(config, (test) => {
  test(config.title, async ({ ctx }) => {

    // init HW rig
    const rig = await platform.getRig()

    // get first controllable DI and set it to false
    const device = rig.getDevice(platform.Rig.M527)
    const dis = device.controllableDis()
    expect(dis.length).toBeGreatherThan(0)
    const di = dis[0]
    await device.set(dis, false)

    // get nextegn cli and check if DI is false
    const cli = await platform.openNextgenCli(device)
    await expect.poll(() => cli.get(di)).toBe(false)

    // subscribe
    const onEvent = await cli.subscribe(di)

    // set DI to 1 and wait for event
    const t0 = ctx.stopwatch.mark()
    await device.set(dsi, true)
    race(setExTimeout(1000), () => { 
      const diff = await t0.next()
      expect(diff).toMatchObject({ address: di.address, value: true })
      expect(ctx.stopwatch.since(t0)).toBeLessThan(BUDGET_MS)
    })    
  })
})
```

## Fixtures

```
fixtures/
  generated/    anything generated by script from another static document. Like modbus register map from Unipi documentation.
  captured/     recorded from real hardware. Immutable.
  handwritten/  small hand-built cases. Editable, must say why in a comment.
```

[R ??] **Never edit `generated/` or `captured/` fixtures.** 
If a test fails against a fixture, the code is wrong.

[G ??] **`handwritten/` fixtures are editable by humans or on human's request.** 
Don't tweak with handwritten fixtures, unless you are asked to do it.
[/]

### TODO - describe each fixture we have, how it's build and where it's used
