# Code Style

- Follow the project's existing patterns and conventions
- Keep functions focused and small
- Prefer explicit over implicit
- Write self-documenting code — add comments only where logic isn't self-evident
- UI state lives in `PeepholeStore` (`@MainActor`, `@Observable`); views stay declarative.
- System calls (`log show`, `Process`) are confined to the non-UI files (`UsageMonitor`).
- Detection is best-effort and read-only — Peephole never blocks or kills anything; it only observes and reports.
