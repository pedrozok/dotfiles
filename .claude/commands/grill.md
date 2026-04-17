---
description: Adversarial code review — find every problem before I do, don't hold back
---

Review current changes as a skeptical senior engineer. Attack from every angle:

- **Bugs**: logic errors, race conditions, null/undefined edge cases
- **Security**: injection, unvalidated input, unsafe deserialization
- **Performance**: N+1, memory leaks, blocking ops
- **Types**: weak typing, incorrect generics, missing narrowing
- **Error handling**: unhandled rejections, silent failures
- **Architecture**: coupling, SRP violations, leaky abstractions
- **Over-engineering**: more complex than it needs to be?
  Be brutal. Format findings as: blocker / suggestion / nitpick.
  Do NOT approve until you've genuinely challenged every decision.
