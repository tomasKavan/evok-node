# evok-node for developers

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API.

The design puts strong emphasis to full compatibility with EVOK 3 API, while adopting own design strategy to allow high exendability by plugins in various parts of the system, and focusing on high stability by decoupling device drivers from API providing modules. 

One of the goals is to have rich web based tool to inspect, debug and control Unipi device. Allow easy access to logs, history and system configuration over web brings FOSS tooling on Unipi closer to less CLI cappable users.

## 1. Agentic support

This is project of Unipi fan and enthusiastic - tomasKavan. To achieve the broad scope of this project, a heavily utilization of agentic support is in order. While most of the design, structer and pattern is man-made, research and coding is executed mainly by agents. 

All PRs to main are carefully reviewed and tested on broad battery of test including real hardware test on custom made test rig - see [`/docs/design/test-rig`](/docs/design/test-rig/README.md).

Agents are also involved in testing CI/CD and issues intake. Boundaries for each agentic role is set and maintained in [`/AGENTS.md`](/AGENTS.md) and referenced files. 

## 2. Working with this package and repo/git

Users install Debian package from repository - see [User docu](/docs/user/README.md). Devlopers needs to clone this repository. Because of narrow and specific use, `evok-node` is not published to npm. TS client consuming [nextgen API](/docs/dev/design/evok-node/15-Nextgen-API.md) is published.

```bash
npm install
npm run build     # tsc -b across all packages, in reference order
npm run lint      # eslint, type-checked config
npm run layering  # dependency-cruiser: the package DAG. Needs a build first
npm test          # vitest, tier 0 only
```

Before you start, read [`design/basic`](./design/basics/README.md) and where it's leads you to. Get familiar with the repo structure, package structure and with the build, debug and testing process.

The docu describes best practices to use [git](./design/basics/01-Git.md) - branching, commiting and creating PRs. Please follow it.

Official relases are tagged and build from `main` and released by maintainer only.

### 2.1. Plan and current status

[`plan/`](plan/README.md) describes the current status, what is the roadmap and breakdown structure of milestones. When contributing, please follow instruction in the `plan/` and don't forget to update STATUS during each commit. Because of agentic coding, it's important to break milestones to as little chunks as possible. More in `plan/README.md`.

## 3. Architecture, coding basics and rules

Because of agentic coding, the [design documentation](./design/evok-node/README.md) must be completed and approved before coding. Design documentation must be accurate - if you need divert, open an issue and discuss it. If you want to write new, please do the same.

Design documentation is structured and each part has written list of prerequisities. This allows you to get familiar with only the right subset to solve the task.

All general rules, best practise, patterns and anti-patterns are collected in [`design/basics/02-Coding.md`](design/basics/02-Coding.md). These instructions are binding.

Testing is important part of the process and extensively described in [`design/basics/03-Testing.md`](design/basics/03-Testing.md). Some tools used in testing are independed packages - [`design/simulator`](design/simulator/README.md) and [`design/test-rig`](design/test-rig/README.md).

## 4. Documentation 

### 4.1. Documentation layout

1. **[`plan/`](plan/README.md)** — status of work. Roadmap, milestones.
2. **[`design/basic`](./design/basics/README.md)** — How to work with repository and package, coding rules and principles.
3. **[`design/evok-node`](./design/evok-node/README.md)** — The actual architecture and design of the app/daemon.
4. **[`design/simulator`](./design/simulator/README.md)** — Helper to simulate Unipi hardware for testing purposes. TCP and RTU modbus mocks.
5. **[`design/test-rig`](./design/test-rig/README.md)** — Design of real HW test rig.
6. **[`design/tooling`](./design/tooling/README.md)** — Other tooling and misc. (Might not exists until it's really needed).
7. **[`research/`](research/README.md)** — the input `design/evok-node` was written from. Collection of findings. Reference and context, **not design guidelines**.
8. **[`modbus-reg-map/`](modbus-reg-map/README.md)** — official Unipi register maps. Ground truth, read-only, no prose.

All documents in `/docs` and subfolders are numbered (except for READMEs). Double digit folowed by hypen and name. In documents all section are numbered and nested section uses nested numbering. 

Referencing symbol is `A.BB.C(.D)*`; where `A` is directory number from numbered list above, `BB` is document number, `C` is main section number and `D` is nested section number. *Note: README.md files aren't numbered. Use `RD` instead of file number in `BB`.* 

Directories numbers are reserved forever. Always add to the end. If directory is removed, don't fill gaps.

Sections are numbered at headings. Always use correct nesting of heading. Eg:

```
# Document name
## 1. Section 1
### 1.1. Subsection 1.1
## 2. Section 2
```

There is tool to regenerate docu numbering `@/tools/regenerate-docu-numbering.ts`. It's auto called with `TODO decide and add npm script`. 

- **Inserting** section/subsection - use `??` instead of number. 
- **Moving** section/subsection - keep old number. Script will fix it.
- **Removing** section/subsection - don't fix following numbering. Script'll fix it.

Script allways regenerates numbering to have clean sequence from 1.

### 4.2. Rules system

Parts of documentation might be marked as important rules or notes. Severity list:

- **R** - Rule - MUST / MUST NOT
- **G** - Guideline - SHOULD, overridable with a reason
- **C** - Convention - naming, formatting, structure
- **X** - Anti-pattern - explicitly forbidden
- **N** - Note - rationale

Rules are addressable: `[S A.BB.C(.D)*-XX]`; where `S` is severity from list above. `A`, `BB`, `C` and `D` - same meaning as in layout. `XX` is rule number within a section.

Rule in text is starting with `[address] ` followed by name/title. `address` is rule address described above. All following paragraphs until the section/subsection end are rule content. Rule content is also stopped by mark `[/]` or by start of another rule.

- **Inserting** rule - use `??` instead of number/whole address. 
- **Moving** rule - keep old number.
- **Removing** rule - don't fix following numbering.

Script regenerating docu numbering is also regenerating rules addresses and creating [`rule-index.md`](./rule-index.md).

### 4.3. Citing

Use citations as much as possible. It's good practice to use verb from following dictionary before each citation:

- **see** - informational cross-reference
- **per** - this text follows from that rule
- **implements** - code or spec satisfying it
- **verifies** - test covering it
- **violates** - known deviation, needs waiver
- **supersedes** - this rule replaces that one

Citing sections/subsection or rule is easy - just use it's address:

```
see [3.02.1.2](/docs/design/evok-node/02-Configuration.md#1.2)
per [R 3.02.1.2-01](/docs/design/evok-node/02-Configuration.md#R-3.02.1.2-01)
```

Script regenerating docu numbering is also regenerating citations and setting up anchors into source documents.

### 4.4. Style

[G ??] What to document - why, never what

**Document the non-obvious *why*, never the *what*.** The what is in the code and the types.

Do not write:

> `getRegister(count, index)` — gets `count` registers starting at `index`.

Do write:

> Reads from the cache snapshot, not the bus. Returns `null` if the block has never been read —
> "no value yet" and "value 0" are different, and clients depend on the distinction.

[R ??] JSDoc on every exported symbol

One summary line, plus `@param`/`@returns` only where the name isn't self-explanatory. Not required on internal functions; an internal function that needs explanation to be understood should be renamed or split.

[X ??] Marketing tone

This is an industrial control library; the audience wants precision. Marketing or relaxed tone of documentation is undesired.

[/]