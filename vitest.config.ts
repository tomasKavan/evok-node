import { defineConfig } from 'vitest/config';

/**
 * Per-module branch-coverage floors from docs/rules/testing.md. Wired here rather
 * than written down in prose so that turning them on is a one-line change instead
 * of a research exercise.
 *
 * Off for M0: there is nothing to cover yet, and a floor that fails on an empty
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
  // protocol codecs and schemas.
  '**/packages/protocol/src/**': { branches: 95 },
  // core device decode and lifecycle.
  '**/packages/core/src/**': { branches: 90 },
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
