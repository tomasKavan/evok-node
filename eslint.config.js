import js from '@eslint/js';
import tseslint from 'typescript-eslint';

/**
 * M0/T0.3. The bans this file exists for are listed in docs/plan/milestones/M0-scaffolding.md
 * and justified in docs/rules/code.md: `any`, `as` outside generated code, non-null `!`,
 * floating promises, `Date.now()` outside logging, `process.env` outside the config
 * module, barrel files outside a package entrypoint.
 *
 * Layering is *not* enforced here — see .dependency-cruiser.cjs. eslint cannot see
 * across package boundaries.
 */

// `no-restricted-syntax` does not merge across config objects: a later `files` block
// that sets it replaces the whole list. The bans are therefore assembled from these
// groups so an override can drop one group without silently dropping the rest.

/** Clock reads. Durations and staleness use an injected monotonic source. */
const BAN_WALL_CLOCK = [
  {
    selector: "CallExpression > MemberExpression[object.name='Date'][property.name='now']",
    message:
      'Date.now() is banned outside logging: inject the clock. An NTP step on a box with no RTC would otherwise corrupt staleness. docs/rules/code.md §Time and effects.',
  },
  {
    selector: 'NewExpression[callee.name=Date][arguments.length=0]',
    message:
      'new Date() reads the same wall clock as Date.now(). Inject the clock. docs/rules/code.md §Time and effects.',
  },
];

/** Environment reads, in the three forms that reach `process.env`. */
const BAN_PROCESS_ENV = [
  {
    selector: "MemberExpression[object.name='process'][property.name='env']",
    message:
      'process.env is banned outside the config module. Configuration is parsed once, at one boundary. docs/rules/code.md §Time and effects.',
  },
  {
    selector: "VariableDeclarator[init.name='process'] > ObjectPattern > Property[key.name='env']",
    message: 'Destructuring `env` off `process` is still process.env. docs/rules/code.md.',
  },
  {
    selector:
      "ImportDeclaration[source.value=/^(node:)?process$/] > ImportSpecifier[imported.name='env']",
    message: 'Importing `env` from node:process is still process.env. docs/rules/code.md.',
  },
];

/**
 * Barrels. Read strictly: any re-export is a barrel construct, and the only file
 * allowed to have one is a package entrypoint. Stock eslint cannot express "a file
 * whose every statement is a re-export", and the stricter reading costs nothing —
 * docs/rules/code.md already asks for one exported concept per file, named after it.
 */
const BAN_REEXPORT = [
  {
    selector: 'ExportAllDeclaration',
    message:
      '`export *` is a barrel: it creates import cycles and hides layering violations from review. Only a package entrypoint (packages/*/src/index.ts) may re-export. docs/rules/code.md §Files and naming.',
  },
  {
    selector: 'ExportNamedDeclaration[source]',
    message:
      'Re-exporting from another module is a barrel construct. Import from the defining file, or export it from the package entrypoint. docs/rules/code.md §Files and naming.',
  },
];

export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/coverage/**',
      // Fixtures and the official register maps are measurements and ground truth,
      // not code. CLAUDE.md rule 14.
      'fixtures/generated/**',
      'fixtures/captured/**',
      'docs/modbus-reg-map/**',
    ],
  },

  // Config files at the root are JavaScript and belong to no tsconfig, so they get
  // the untyped ruleset.
  {
    files: ['**/*.js', '**/*.mjs', '**/*.cjs'],
    extends: [js.configs.recommended, tseslint.configs.disableTypeChecked],
    languageOptions: { sourceType: 'module' },
  },
  {
    files: ['**/*.cjs'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: { module: 'writable', require: 'readonly' },
    },
  },

  {
    files: ['**/*.ts'],
    extends: [js.configs.recommended, tseslint.configs.strictTypeChecked],
    languageOptions: {
      parserOptions: {
        // Type-aware linting is the point: no-floating-promises and the no-unsafe-*
        // family need types. `projectService` uses each package's own tsconfig.
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // These four are in strictTypeChecked already. Restated because they are the
      // load-bearing ones: a preset that changes its mind must not quietly relax them.
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-non-null-assertion': 'error',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',

      // `as` at all, not just unsafe `as`. Parse at the boundary and the type is real;
      // an assertion is a claim the compiler cannot check. The one exception is
      // generated code, overridden below.
      '@typescript-eslint/consistent-type-assertions': ['error', { assertionStyle: 'never' }],

      // The other half of the exhaustive-switch guarantee. tsc gives a compile error
      // for a missing case only where the function has a declared return type and no
      // `default` (noImplicitReturns); this catches the statement-position switch too.
      '@typescript-eslint/switch-exhaustiveness-check': 'error',

      'no-restricted-syntax': ['error', ...BAN_WALL_CLOCK, ...BAN_PROCESS_ENV, ...BAN_REEXPORT],
    },
  },

  // Build and test configuration is TypeScript, but the packages' tsconfigs include
  // only `src/**`, so these files belong to no project and cannot be typechecked.
  // Linted without type information rather than left unlinted.
  {
    files: ['vitest.config.ts', 'packages/*/vitest.config.ts'],
    extends: [tseslint.configs.disableTypeChecked],
    languageOptions: { parserOptions: { projectService: false } },
  },

  // A package entrypoint is the one legitimate barrel.
  {
    files: ['packages/*/src/index.ts'],
    rules: {
      'no-restricted-syntax': ['error', ...BAN_WALL_CLOCK, ...BAN_PROCESS_ENV],
    },
  },

  // The config module is the only place that reads the environment. Named by
  // directory rather than by package because which package owns it is not settled:
  // the first real config module must live in a `config/` directory, or this
  // override moves with it.
  {
    files: ['packages/*/src/config/**/*.ts'],
    rules: {
      'no-restricted-syntax': ['error', ...BAN_WALL_CLOCK, ...BAN_REEXPORT],
    },
  },

  // Logging is the only place that may read the wall clock: a log line wants the
  // operator's notion of time, not a monotonic counter.
  {
    files: ['packages/*/src/logging/**/*.ts'],
    rules: {
      'no-restricted-syntax': ['error', ...BAN_PROCESS_ENV, ...BAN_REEXPORT],
    },
  },

  // Generated code is the sole `as` exception T0.3 allows. It is not hand-edited, so
  // an assertion in it is the generator's claim, reviewed once at the generator.
  {
    files: ['**/src/generated/**/*.ts'],
    rules: {
      '@typescript-eslint/consistent-type-assertions': 'off',
    },
  },
);
