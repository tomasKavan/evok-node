import { defineConfig } from 'vitest/config';

/**
 * Per-module branch-coverage floors from docs/rules/testing.md. Wired here rather
 * than written down in prose so that turning them on is a one-line change instead
 * of a research exercise.
 *
 * Off for N0: there is nothing to cover yet, and a floor that fails on an empty
 * repository teaches everyone to pass `--no-coverage`. Flipped on in the PR that
 * lands the first module each glob names, narrowing the glob to that module at the
 * same time.
 */
const ENFORCE_COVERAGE_FLOORS: boolean = false;

const COVERAGE_FLOORS = {
  // hw-definitions address computation: cannot be validated against hardware for
  // the cases that matter most (docs/plan/STATUS.md, known permanent gaps).
  '**/packages/hw-definitions/src/**': { branches: 100 },
  // modbus framing, correlation, timing.
  '**/packages/modbus/src/**': { branches: 95 },
  // messaging: envelope codecs, introspection schemas. Everything crossing the
  // driver↔API boundary is parsed here, and nothing downstream re-checks (RC-12).
  '**/packages/messaging/src/**': { branches: 95 },
  // api-compat's projection table. The one place two vocabularies meet (RC-24), and
  // the place a wrong mapping is silent rather than loud.
  '**/packages/api-compat/src/**': { branches: 95 },
  // driver-kit: the scan loop, reading state and staleness, shared by every driver.
  '**/packages/driver-kit/src/**': { branches: 90 },
  // device decode and lifecycle, per concrete driver.
  '**/packages/driver-onboard/src/**': { branches: 90 },
  '**/packages/driver-extension/src/**': { branches: 90 },
  // main: config parse and resource-exclusivity validation. Its failure modes are
  // exactly finding 2.7's, so the branches that matter are the rejection paths.
  '**/packages/main/src/**': { branches: 90 },
};

export default defineConfig({
  test: {
    // One project per package. Each packages/*/vitest.config.ts names its tiers.
    projects: ['packages/*'],
    passWithNoTests: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['packages/*/src/**/*.ts'],
      exclude: ['**/*.test.ts'],
      ...(ENFORCE_COVERAGE_FLOORS ? { thresholds: COVERAGE_FLOORS } : {}),
    },
  },
});
