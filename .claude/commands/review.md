---
description: Conduct a five-axis code review — correctness, readability, architecture, security, performance
---

Invoke the agent-skills:code-review-and-quality skill.

Review the current changes (staged or recent commits) across all five axes:

1. **Correctness** — Does it match the spec? Edge cases handled? Tests adequate?
2. **Readability** — Clear names? Straightforward logic? Well-organized?
3. **Architecture** — Follows existing patterns? Clean boundaries? Right abstraction level?
4. **Security** — Input validated? Secrets and tokens safe (secure storage, nothing sensitive in the binary or logs)? Auth checked? (Use security-and-hardening skill)
5. **Performance** — No N+1 queries? No unbounded ops? Rebuild scope, lazy lists, and UI-isolate work OK? (Use performance-optimization skill)

For Flutter changes, also apply the Flutter Review Lens in the skill (async gaps, disposal, all states, freezed and codegen, layering, both-platform evidence).

Categorize findings as Critical, Important, or Suggestion.
Output a structured review with specific file:line references and fix recommendations.
