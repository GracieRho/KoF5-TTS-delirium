# Repository Guidelines

## Project Context

- This Korean TTS project supports non-pharmacological interventions for patients experiencing delirium.
- Keep project documentation and user-facing product content in Korean by default; agent instruction files are maintained in English.
- Do not select models, frameworks, or hardware without supporting evidence while the project is in its early stage.

## Repository Workflow

- Follow `docs/repository-layout.md` for directory responsibilities and team handoffs.
- Follow the machine-wide worktree policy: new implementation starts from freshly fetched `origin/main` in a task branch under `.worktrees/<task-slug>/`; an existing worktree owned by the same task may be resumed. Read-only work needs no synchronization or new worktree. Explicitly requested direct work and small documentation-only maintenance use the machine-wide exceptions.
- Use a branch prefix appropriate to the task: `feat/`, `fix/`, `docs/`, `chore/`, or `experiment/`.
- Make frequent, small commits after validating each coherent unit. When a pull request is within the requested delivery scope, record validation results and impacts on data and checkpoints. Push, publish, and deploy only within the requested scope; merge only with explicit user authorization and the required review approval. Do not request again an approval already given for the same operation.
- Resolve PR review conversations and check that generated architecture documentation is current before an authorized merge. Prefer squash merge.
- After a PR merges, `.github/workflows/delete-merged-branch.yml` deletes its remote branch in the same repository. Inspect local worktree and branch state before any separately authorized cleanup; restrict cleanup to the current task.
- Store original WAV files in `data/raw/wav/`, converted FLAC files in `data/interim/flac/`, and training inputs in `data/processed/`.
- Keep reusable code in `src/kof5_tts/`, entry points in `scripts/`, and experiment configuration in `configs/`.
- Store fine-tuning outputs in `checkpoints/finetuned/` and pruned or quantized outputs in `checkpoints/optimized/`.
- Exclude data, execution logs, and checkpoints from Git by default. Track only meaningful checkpoints that meet `checkpoints/README.md` criteria after team review; never force-add the entire checkpoint directory.

## Safety and Data

- Do not commit patient identifiers, actual clinical audio, private research data, or credentials.
- When clinical wording or patient-facing behavior changes, describe its safety impact and whether clinical review is required.
- Treat generated audio, model checkpoints, experiment logs, and converted models as artifacts by default.

## Model Optimization

- Measure baseline model quality and performance before optimization.
- Compare Korean intelligibility and preservation of key messages alongside size, latency, and memory when quantizing or pruning decoder layers.
- Record device-specific optimization decisions in an ADR after the target hardware and runtime are established.

## Changes

- Reuse the existing document structure and project terminology.
- Start with the smallest relevant validation and clearly identify unverified items.
- When the structure of `src/`, `configs/`, or `scripts/` changes, run `python3 scripts/generate_architecture.py` and include the generated files.
- Before completion, run `python3 scripts/generate_architecture.py --check`, `python3 -m unittest scripts/test_generate_architecture.py`, and `git diff --check`.
