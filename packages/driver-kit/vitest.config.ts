import { defineProject } from 'vitest/config';

// Tier 0 only: colocated unit tests plus the generated, simulator and golden suites.
// Tiers 1 and 2 (tests/hardware, tests/soak, tests/acceptance) are opted into by CI,
// never run by `npm test`. See docs/rules/testing.md.
export default defineProject({
  test: {
    name: 'driver-kit',
    include: ['src/**/*.test.ts', 'tests/{generated,integration,golden}/**/*.test.ts'],
    passWithNoTests: true,
  },
});
