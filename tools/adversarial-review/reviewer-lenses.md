# Reviewer Lenses

Three distinct adversarial perspectives. Each reviewer adopts ONE lens exclusively — do not
mix lenses in a single review. The challenge is always whether the work achieves the stated
intent well, NOT whether the intent is correct.

## Architect

Challenge structural fitness. Ask:

- Does the design actually serve the stated goal, or does it serve a goal the author assumed?
- Where are the coupling points that will hurt when requirements shift?
- What boundary violations exist? Where does responsibility leak between components?
- What implicit assumptions about scale, concurrency, or ordering will break first?
- Does the structure make the right operations easy and the wrong operations hard?
- Where is business logic leaking into infrastructure, or vice versa?

Map findings to: foundational-thinking, boundary-discipline, redesign-from-first-principles,
make-operations-idempotent.

## Skeptic

Challenge correctness and completeness. Ask:

- What inputs, states, or sequences will break this?
- What error paths are unhandled or silently swallowed?
- What race conditions or ordering dependencies exist?
- What does the author believe is true that isn't proven?
- Where is "it works on my machine" masquerading as verification?
- What is the failure mode when a dependency is slow, unavailable, or returns unexpected data?
- What happens at the edges: empty collections, zero values, concurrent calls, restarts?

Map findings to: prove-it-works, fix-root-causes, serialize-shared-state-mutations.

## Minimalist

Challenge necessity and complexity. Ask:

- What can be deleted without losing the stated goal?
- Where is the author solving problems they don't have yet?
- What abstractions exist for a single call site?
- Where is configuration or flexibility added without a concrete second use case?
- Is this the simplest possible path to the outcome, or is it the path that felt most thorough?
- What helpers, validators, managers, or handlers exist only to wrap a single operation?
- Where is complexity added in the name of "extensibility" with no actual extension planned?

Map findings to: subtract-before-you-add, no-helper-hell, no-over-engineering, DRY-but-not-WET,
outcome-oriented-execution, cost-aware-delegation.
