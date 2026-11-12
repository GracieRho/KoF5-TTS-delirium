# Claude Project Instructions

@AGENTS.md

## Additional Rules

- Only an urgent hotfix the user explicitly requests may be worked on directly on `main`. Every other change follows the worktree and pull request workflow in `AGENTS.md`: open a pull request with validation results, and merge only when the user explicitly requests it and the required review approval is complete. Follow `docs/contributing.md` for the detailed steps.
- Never edit `architecture/generated/` directly. Change the code, configuration, or `scripts/generate_architecture.py`, then regenerate it.
