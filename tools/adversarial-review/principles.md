# Principles

Code quality rules for adversarial reviewers. These govern review judgments — challenge work
against these standards. They are not exhaustive rules for the author to cite, but lenses
to identify real problems worth raising.

## Core

**foundational-thinking** — structural decisions optimize for option value; code-level decisions
optimize for simplicity. data structures first. scaffold first. make the right structure before
filling in the details.

**redesign-from-first-principles** — when integrating a change, redesign as if the change had
been a foundational assumption from day one. don't bolt on. no compat shims, no dual paths,
no "for now" hacks that persist.

**subtract-before-you-add** — remove complexity first, then build. deletion before construction.
design for observed usage, not hypothetical future requirements. the right amount of complexity
is the minimum needed for the current task.

**outcome-oriented-execution** — optimize for the intended end state, not smooth intermediate
states. intermediate breakage acceptable when planned and reversible. ask: does this move
toward the goal, or does it just feel like progress?

## Code Quality

**no-comments** — NEVER add comments. exceptions require approval: galaxy-brain hack, novel
algorithm, API docs, crypto. if you need a comment to explain it, simplify the code instead.

**naming** — snake_case fns, UpperCamelCase classes, terse aliases. names should be self-evident.

**poetic-narrative-style** — 6-20 line methods, each tells one coherent story. avoid
over-decomposition into micro-helpers. inline simple operations that are used once and break
narrative flow when extracted.

**no-helper-hell** — NO wrapper classes that just delegate. NO excessive abstraction (validator,
manager, handler, processor, utils). NO _private methods unless truly internal state. NO clever
metaprogramming without approval. helpers that exist for one call site add indirection without value.

**DRY-but-not-WET** — extract when genuine duplication across multiple places. inline when used
once, simple operation, or breaking narrative flow. three similar lines of code is better than
a premature abstraction. balance: poetic readability > theoretical reusability.

**no-slop** — banned words in prose and identifiers: delve, tapestry, landscape, leverage (verb),
robust, streamline, harness. banned structures: negative parallelism ("it's not X — it's Y"),
rhetorical self-answers ("the result? devastating"), dramatic countdowns ("not X. not Y. just Z."),
gerund fragment litanies, back-to-back tricolons. applies to code naming AND prose equally.

**no-over-engineering** — only make changes directly requested or clearly necessary. don't add
features, refactor, or "improve" beyond what was asked. no error handling, fallbacks, or
validation for scenarios that can't happen. no feature flags or backwards-compat shims when
you can just change the code. no docstrings, comments, or type annotations on unchanged code.

**no-backwards-compat** — no renaming unused _vars, no re-exporting types, no "// removed"
comments, no legacy fallback paths. if unused, delete completely. backwards-compat hacks
accumulate into technical debt that nobody ever removes.

## Architecture

**boundary-discipline** — validation at system boundaries only (user input, external APIs, network
responses). trust internal code unconditionally — don't defensively validate what you control.
business logic in pure functions. thin shell + pure logic. responsibility should not leak
between components.

**make-operations-idempotent** — operations converge to correct state regardless of run count.
test: what happens if this runs twice? what if it crashed halfway through? idempotency is not
just for infrastructure — it's a correctness property for any stateful operation.

**serialize-shared-state-mutations** — enforce serialization structurally (lockfiles, sequential
phases, exclusive ownership), not via instructions or conventions. if two code paths can mutate
the same state, the serialization must be in the structure, not the comments.

## Verification

**prove-it-works** — verify by checking the real thing directly, not proxies or self-reports.
"it compiles" is not verification. "the tests pass" is not verification if the tests are weak.
trust artifacts, not self-reports. if something can be tested, note how — don't just assert it works.

**fix-root-causes** — never paper over symptoms. ask "why" until bedrock. if a fix requires
understanding why the bug existed, the fix is incomplete without that understanding. own every
file you touch — a change that fixes a symptom in file A while leaving the root cause in file B
is not a fix.

## Delegation

**cost-aware-delegation** — budget before delegating. count turns per phase. front-load context.
hard-cap scope. delegation that costs more in orchestration overhead than it saves in parallelism
is waste.

**guard-the-context-window** — context window is finite. isolate large payloads to subagents.
don't read what you won't use. loading entire files to find a function that could be grepped
is waste.

## Environment

**python-always-uv** — NEVER use raw python/python3. ALWAYS `uv run`. no exceptions. not even
one-liners. not even in containers. not even in CI.

**no-docstrings-on-unchanged** — no docstrings, comments, or type annotations on code you
didn't change. adding documentation to unchanged code is scope creep that adds noise to diffs.
