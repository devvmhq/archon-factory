# archon-base-config

The factory pack: [Archon](https://archon.diy) workflows that take one dex task from design to a local commit, the same way in every project. Each AI step does one job, and the checks between the steps are shell commands, so a step that skips the protocol fails the run. A human approves the design and the finished change, and nothing is ever pushed.

## The workflows

**`feature`** builds a feature in a worktree of its own:

1. **Design** (Opus, read-only) from the dex task, then a wait for your approval. Your comment goes to the builder, and a rejection ends the run.
2. **Tests first** (Sonnet): the tests the design names. A shell check then fails the run if no test file changed or if the suite already passes.
3. **Implement** and **self-review** (Sonnet), in the same session as the tests.
4. **Adversarial review** (Opus, read-only), at most 3 rounds. Each round, a fresh reviewer gets the diff and returns `ship` with findings, and a fixer (Sonnet) acts on them when it's `false`. A run that reaches the cap fails for you to judge.
5. **The gate:** `mise run fmt && mise run lint && mise run test`.
6. **The commit message** (Sonnet), written from the final diff to the project's AGENTS.md rules.
7. **Your review:** the diff's stat, the commit message and the last review, then a wait for your approval.
8. **Commit and fast-forward:** one commit on the run's branch, then local `main` (or whichever branch the project's checkout is on) is fast-forwarded to it, and the dex task is completed with the commit. If the fast-forward can't happen, the run says so and you merge by hand.

**`fix`** fixes a bug the same way, without the design step or your approvals. It writes a test that reproduces the bug and checks that it fails, fixes the bug, runs at most 2 review rounds, passes the gate and commits.

## Lanes

Each run records its task's lane in the project's `.dex/lanes.json`, keyed by the dex task ID, with the run ID and the time. The lanes are `design`, `design-approval`, `build`, `review`, `gate`, `human-review` and `done` for `feature`, and `reproduce`, `build`, `review`, `gate` and `done` for `fix`. A run that fails leaves its task in the lane where it stopped. The lanes live beside dex's own file because dex drops metadata it doesn't know the next time it writes a task.

## Installing

You need Archon with the Claude provider (`brew install coleam00/archon/archon`, then `archon provider add claude`), dex, `jq`, and [mise](https://mise.jdx.dev). Then run:

```sh
./install.sh
```

It symlinks `workflows/`, `commands/` and `scripts/` into `~/.archon/<kind>/factory`, and `bin/factory` into `~/.local/bin`, so every project sees the workflows and edits to this repo apply at once. `archon workflow list` in any git repo then shows `feature` and `fix`.

## Using it in a project

A project needs:

- **A git remote.** Archon creates each run's worktree only in a repo with one; it's never pushed to.
- **`mise.toml` with `fmt`, `lint` and `test` tasks**, which make up the gate.
- **`AGENTS.md`** with the project's conventions, commits included. Every step reads it.
- **`.dex/` in `.gitignore`**, and the tasks created in the project with `dex create`.

Then, from the project's checkout:

```sh
factory feature <dex-id>     # or: factory fix <dex-id>
```

`factory` starts the run in the background from the branch you're on, unpushed commits included, and prints its run ID. To follow and answer it:

```sh
archon workflow attention                       # what's waiting for you
archon workflow approve <run> "comment"         # or: archon workflow reject <run> "reason"
archon workflow logs <run> --follow
archon workflow get <run> --json                # state; .status, not the exit code
```

`archon workflow approve` continues the run in the terminal you ran it in. `archon workflow wait` exits 0 even when the run fails, so read `status` from `archon workflow get --json` instead, and a run's cost from `archon workflow get <run> --verbose`.

A finished run leaves its worktree under `~/.archon/workspaces/<project>/worktrees/`, along with its branch. Archon's bundled `archon-worktree-cleanup` workflow looks like the way to remove them, but the pack hasn't tried it yet.

## Layout

| Path | What |
| --- | --- |
| `workflows/` | `feature.yaml` and `fix.yaml` |
| `commands/` | the prompt for each role, `factory-*.md` |
| `scripts/lib.sh` | the bash nodes' helpers: dex, lanes, the red check, the gate, the commit |
| `bin/factory` | starts a run for a dex task |
| `install.sh` | the symlinks |
