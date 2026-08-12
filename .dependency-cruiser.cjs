/**
 * M0/T0.3. The load-bearing guard.
 *
 * We chose npm workspaces, whose flat `node_modules` resolves an import a package
 * never declared. `tsc -b` does not close this: a cross-package import with no
 * project reference builds green as long as the target's `dist/` exists, which it
 * always does after any earlier build — verified empirically, see the PR that added
 * this file. So nothing but this file stops `core` importing `server`.
 *
 * Rules that CLAUDE.md states as inviolable are rules 1 (core never imports api,
 * server or inspector) and 2 (rig imports no workspace package and no Modbus
 * client). The rest of the DAG comes from CLAUDE.md §Layout and each package's README.
 */

/**
 * The layering DAG, as workspace dependencies. One entry per package; the value is
 * the complete set of workspace packages it may import. Everything absent is
 * forbidden, and every rule below is generated from this table, so the DAG is stated
 * once.
 *
 * - `protocol` is the root: schemas only, so it depends on nothing of ours.
 * - `core` gets protocol, modbus and hw-definitions, and never api/server/inspector
 *   (RC-10). The core↔API contract is serialisable messages, so `server`
 *   depends on `core` and never the reverse.
 * - `simulator` deliberately excludes `modbus`: the instrument must not share a
 *   framer with the code it stands in for. See ADR-0007, which states the cost.
 * - `rig` imports nothing of ours at all (RC-11).
 * - `inspector` is over the public API only: no core, no server, no transport.
 */
const WORKSPACE_DEPS = {
  protocol: [],
  modbus: ['protocol'],
  'hw-definitions': ['protocol'],
  core: ['protocol', 'modbus', 'hw-definitions'],
  server: ['protocol', 'core'],
  client: ['protocol'],
  simulator: ['protocol', 'hw-definitions'],
  inspector: ['protocol'],
  rig: [],
};

/**
 * Edges that are neither allowed nor forbidden yet, and are therefore left unruled
 * rather than decided by omission. `inspector → client` is open question 5b in
 * docs/plan/STATUS.md: T0.3 says inspector depends only on protocol, but the obvious
 * implementation of inspector is a consumer of our own client. Encoding it as
 * forbidden would settle that question silently, so this list exempts it — and only
 * it — from the generated rule.
 */
const UNDECIDED_DEPS = {
  inspector: ['client'],
};

const PACKAGES = Object.keys(WORKSPACE_DEPS);

/**
 * Matches the source tree of the named packages *and* their node_modules aliases.
 * A workspace import resolves through the `@evok-node/*` symlink, and whether the
 * resolver reports the link or its target depends on options we would rather not
 * depend on, so both spellings are matched.
 */
function workspacePath(names) {
  return `(^|/)(packages|node_modules/@evok-node)/(${names.join('|')})(/|$)`;
}

/**
 * The table above says which edges may exist; each package.json says which edges npm
 * will install. They have to agree, and nothing else checks that they do: a
 * workspace import resolves as `aliased-workspace`, never as an undeclared npm
 * dependency, so an allowed-but-undeclared edge cruises clean here and breaks only
 * once the package is published. Cheapest place to catch it is at config load.
 */
function assertManifestsMatchTable() {
  const problems = [];

  for (const pkg of PACKAGES) {
    const declared = Object.keys(require(`./packages/${pkg}/package.json`).dependencies ?? {})
      .filter((name) => name.startsWith('@evok-node/'))
      .map((name) => name.slice('@evok-node/'.length));

    const permitted = new Set([...WORKSPACE_DEPS[pkg], ...(UNDECIDED_DEPS[pkg] ?? [])]);

    for (const dep of declared) {
      if (!permitted.has(dep)) {
        problems.push(`packages/${pkg}/package.json declares @evok-node/${dep}, which the DAG forbids`);
      }
    }
    for (const dep of WORKSPACE_DEPS[pkg]) {
      if (!declared.includes(dep)) {
        problems.push(`packages/${pkg}/package.json does not declare @evok-node/${dep}, which the DAG allows`);
      }
    }
  }

  if (problems.length > 0) {
    throw new Error(
      `The layering DAG and the package manifests disagree:\n  - ${problems.join('\n  - ')}\n` +
        'Change both, or neither. .dependency-cruiser.cjs is the DAG.',
    );
  }
}

assertManifestsMatchTable();

const layeringRules = PACKAGES.map((pkg) => {
  const allowed = new Set([pkg, ...WORKSPACE_DEPS[pkg], ...(UNDECIDED_DEPS[pkg] ?? [])]);
  const forbidden = PACKAGES.filter((other) => !allowed.has(other));
  const permitted = WORKSPACE_DEPS[pkg].length > 0 ? WORKSPACE_DEPS[pkg].join(', ') : 'nothing of ours';

  return {
    name: `layer-${pkg}`,
    comment: `${pkg} may import ${permitted}. Fix the design, not this rule: the layering DAG lives in CLAUDE.md and in .dependency-cruiser.cjs, and a new edge needs an ADR.`,
    severity: 'error',
    from: { path: `^packages/${pkg}/` },
    to: { path: workspacePath(forbidden) },
  };
});

module.exports = {
  forbidden: [
    ...layeringRules,

    {
      name: 'no-circular',
      comment:
        'A cycle means the two files are one module that has not admitted it. Barrels are the usual cause, which is why eslint bans them outside package entrypoints.',
      severity: 'error',
      from: {},
      to: { circular: true },
    },

    {
      name: 'rig-no-modbus-client',
      comment:
        'RC-11: rig is sysfs only and never speaks Modbus. The instrument must not share code with what it measures — if the rig used our transport, a transport bug would corrupt the measurement that was meant to catch it.',
      severity: 'error',
      from: { path: '^packages/rig/' },
      to: { path: '[Mm]odbus' },
    },

    {
      name: 'not-to-unresolvable',
      comment:
        'An import nothing resolves is either a typo or a dependency nobody declared. Either way it is not a runtime problem we want to discover on the box.',
      severity: 'error',
      from: {},
      to: { couldNotResolve: true },
    },

    {
      name: 'not-to-undeclared-dependency',
      comment:
        'A third-party module resolved out of the flat node_modules that no package.json declares — a transitive dependency being used directly, which breaks the day the package that pulled it in drops it. Note this does not cover workspace imports: those resolve as `aliased-workspace`, never as `npm-no-pkg`, so the layering rules and the manifest check above are what cover them.',
      severity: 'error',
      from: { path: '^packages/' },
      to: { dependencyTypes: ['npm-no-pkg', 'npm-unknown'] },
    },

    {
      name: 'not-to-dev-dep',
      comment:
        'Shipped code importing a devDependency works on our machine and fails on the box, where devDependencies are not installed.',
      severity: 'error',
      from: { path: '^packages/[^/]+/src/', pathNot: '\\.test\\.ts$' },
      to: { dependencyTypes: ['npm-dev'] },
    },
  ],

  options: {
    // Type-only imports are layering violations too, and they are exactly the ones
    // tsc is most willing to accept.
    tsPreCompilationDeps: true,

    // Report the edge into a package, but do not crawl its contents: `dist/` is a
    // copy of `src/` and would double the graph, and third-party trees are not ours
    // to police.
    doNotFollow: { path: '(^|/)(node_modules|dist)/' },

    // Workspaces: a package may legitimately use a dependency declared in the root
    // package.json (vitest, typescript). Without this, every test file is an
    // undeclared import. Workspace cross-imports are still caught — the root
    // declares its packages as workspaces, not as dependencies.
    combinedDependencies: true,

    enhancedResolveOptions: {
      exportsFields: ['exports'],
      conditionNames: ['import', 'require', 'node', 'default', 'types'],
      extensions: ['.ts', '.js', '.mjs', '.cjs', '.json'],
    },
  },
};
