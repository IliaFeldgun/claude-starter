---
name: cd-local
description: Ship a focused change from an isolated worktree onto the branch the user is on — branch off their live HEAD, develop+self-verify, commit, send a git show for approval, then rebase-and-fast-forward into their branch with a retry loop because parallel agents keep moving it. Triggers when the user says "cd-local", "cd this", "ship this", "deliver this", "land this", "continuously deliver", "rebase my side branch with this", or otherwise wants a change worked in a worktree and merged into the branch they're currently on.
---

# cd-local

Ship a change from an isolated worktree onto the branch the user is on, while other agents push to that same branch (and to `main`) in parallel. The branch **will** move under you mid-delivery — the flow is built to tolerate that.

Run it foreground, step by step, pausing at the approval gate.

## The model

- The user works on whatever branch is currently checked out — **usually a side branch, sometimes `main`**. Read it live (`git branch --show-current`); never hardcode it.
- Many Claudes commit to that branch concurrently, so its tip advances repeatedly during your delivery.
- You develop on a throwaway branch in a git worktree, then land it onto the user's branch by **rebase + fast-forward** — keeping their branch linear, with no merge commits.
- Always self-verify before showing the change. The worktree lives under the mounted repo at `.claude/worktrees/$slug`, so it's visible on the user's host — **the user can and will test it too**. When they ask how, hand them the commands to run (clip them via the clipboard skill); don't make them figure out the path.

## Steps

### 1. Branch off the user's *live* HEAD into a worktree

```bash
cur=$(git branch --show-current)                       # the user's branch (don't hardcode)
slug=<short-kebab-name>
git worktree add -b "cd/$slug" ".claude/worktrees/$slug" "$cur"
```

Then `EnterWorktree` with `path: .claude/worktrees/$slug` to switch the session in.

> Do **not** rely on `EnterWorktree`'s `name:` shortcut here — its default `worktree.baseRef` is `fresh` (= `origin/<default>`), which is the wrong base. Create the worktree off `$cur` manually as above, then enter by `path`.

`.claude/worktrees/` is git-ignored (registered worktrees aren't tracked), so this leaves the user's status clean.

### 2. Develop and self-verify

Make the change. Then **prove it works yourself** first — don't rely on the user to catch it (they may also test it on their host, but verification is on you).
- Prefer a side-effect-free check. For changes to a wrapper that shells out (e.g. `docker`/`gh`), put a fake binary on `PATH` that echoes its args and exits, so you can assert what *would* run without actually running it.
- `bash -n` for shell syntax; run the real linter/tests when there is one.

### 3. Commit — don't ask

Commit on the work branch without asking for permission (the user has pre-approved committing; they approve at the *git show* gate instead). Use the repo's local git identity. Single-purpose commit, clear message.

### 4. Send a `git show`, then PAUSE

```bash
git --no-pager show "cd/$slug"
```

Show it and stop for approval. (If the user says "clip me" the git show, they mean copy the **command** `git show cd/$slug` to their clipboard via the clipboard skill — not pipe the long diff through `clip`.) Do not integrate until they approve.

### 5. On approval: rebase, then fast-forward — in a loop

The branch has almost certainly moved. Land it with this loop (run from the **main checkout**, since the user's branch is checked out there and the `--ff-only` must happen there):

```bash
cd <main-checkout>                       # where $cur is checked out
for i in $(seq 1 8); do
  if git merge --ff-only "cd/$slug" 2>/dev/null; then echo "landed"; break; fi
  echo "ff blocked; re-rebasing onto $(git rev-parse --short "$cur")"
  ( cd ".claude/worktrees/$slug" && git rebase "$cur" ) || { echo "conflict — resolve manually"; break; }
done
```

- **Rebase runs inside the worktree** (that's where `cd/$slug` is checked out); the **fast-forward runs in the main checkout** (that's where `$cur` is checked out — you can't update a branch from a worktree where it isn't checked out).
- A clean `--ff-only` means linear history, no merge commit.
- If the rebase conflicts (parallel agents touched the same lines — normal, not an error), resolve by **combining both intents**, `git add`, `GIT_EDITOR=true git rebase --continue`, then retry the ff. Repeat until it lands.

### 6. Clean up

```bash
ExitWorktree (keep)        # back to the main checkout
git worktree remove ".claude/worktrees/$slug"
git branch -d "cd/$slug"
```

## Gotchas

- **Your integration target is the user's current branch — usually a side branch, sometimes `main`.** Whenever `main` is or looks like the target — it's the current branch, the worktree was based off it, or the user asks to land there — **pause and prompt the user to confirm** before you fast-forward; landing on `main` is higher-stakes. For a side branch, just land it.
- In a worktree, rebase state lives under `.git/worktrees/<name>/rebase-merge` — so `test -d .git/rebase-merge` from the repo root gives a false negative. Detect an in-progress rebase with `git status` / `git branch` (shows `(no branch, rebasing X)`).
- After resolving a conflict, confirm `grep -c '^<<<<<<<' <file>` is `0` and re-run your self-verification before continuing the rebase — the merged result is new code neither side reviewed.
- This skill lives in `local-skills/`, so it's baked into the image: edits here need `claude --update` to take effect.
