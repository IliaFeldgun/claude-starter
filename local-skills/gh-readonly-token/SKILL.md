---
name: gh-readonly-token
description: Use when the user wants to grant Claude read-only GitHub access — PRs, Actions, checks, diffs — via the `gh` CLI. Triggers on "give Claude github access", "read-only github token", "PAT for claude", "grant gh access", "github auth for claude", "let claude see PRs/actions". Walks the user through creating a fine-grained personal access token and wiring it into `gh` via `GH_TOKEN`.
---

# Read-only GitHub access for Claude via `gh`

When the user asks how to grant Claude GitHub access (PRs, Actions, etc.), instruct them to create a **fine-grained personal access token** with the narrowest scopes that fit and register it with the `claude` launcher. Do **not** suggest a classic PAT — its scopes are too coarse to be truly read-only.

The launcher keeps up to three named token slots in the **container's persistent `claude-data` volume** (`~/.config/claude-starter/gh-tokens/<slot>`, mode 600, written by `entrypoint.sh`). At launch, `entrypoint.sh` resolves the chosen slot to `$GH_TOKEN` for that session — the slot is authoritative, so an unregistered slot means no `$GH_TOKEN` at all. The token never touches the host disk or `~/.claude/settings.json` (that file is read into Claude's context, so a token there leaks into the transcript).

- `ro` — read-only (default; used when no slot flag is given)
- `pr` — adds Pull requests: **Write** (for `gh pr comment`, review, merge)
- `issue` — adds Issues: **Write**
- `deploy` — adds Actions: **Write** + Deployments: **Write** (for `gh workflow run`, re-running jobs, deployment statuses)

`gh` is preinstalled in this container and reads `$GH_TOKEN` automatically, so once a slot is registered the user can run `gh pr list` etc.

## What to tell the user

### 1. Create the token

- URL: <https://github.com/settings/personal-access-tokens/new>
- **Resource owner:** the org that owns the repos (e.g. `pinecone-io`). Org-owned tokens usually need an org admin to approve after creation.
- **Repository access:** select only the repos Claude should see.
- **Repository permissions** — all **Read-only**:
  - `Pull requests` — Read
  - `Actions` — Read
  - `Contents` — Read *(needed for `gh pr diff`, fetching files)*
  - `Metadata` — Read *(mandatory, auto-selected)*
  - `Commit statuses` — Read *(for `gh pr checks`)*
  - `Checks` — Read *(for check runs)*
- Leave everything else unset. No write permissions, no account permissions.

### 2. Register the token with the launcher

Run this **on the host** (the `claude` shim → `main.sh`). Use the `:-` form so the token is read from the terminal silently and never lands in shell history. The launcher pipes it (stdin only) into a throwaway container that writes it to the volume:

```bash
claude --gh-token ro:-       # prompts; stores the 'ro' slot in the volume
claude --gh-token pr:-       # only if they want PR write
claude --gh-token issue:-    # only if they want issue write
claude --gh-token deploy:-   # only if they want Actions/Deployments write
```

Inline form (`claude --gh-token ro:github_pat_...`) works too but lands in shell history — prefer `:-`. Registration (and slot resolution) live in `entrypoint.sh`, so they only work after a rebuild (`claude --update`) following any change to that file.

To rotate all slots at once (e.g. after the PATs expire), use:

```bash
claude --gh-token-rotate     # walks ro → deploy → issue → pr in sequence
```

It prompts for each slot hidden; paste the freshly regenerated token, or leave a slot blank to skip it (keeps the current token). Same stdin-only path as `--gh-token` — nothing touches host disk or shell history.

### 3. Launch with the right slot

```bash
claude            # uses the 'ro' slot (default)
claude --pr       # uses the 'pr' slot
claude --issue    # uses the 'issue' slot
claude --deploy   # uses the 'deploy' slot
```

The launcher exports the slot's token as `$GH_TOKEN` and forwards it into the container by name, so `gh` picks it up and it overrides any in-container `gh auth login`. `--pr`/`--issue` error out if that slot isn't registered.

### 4. Verify (inside the container)

```bash
gh auth status     # should show token-based auth (GH_TOKEN)
gh pr list         # should succeed
gh pr comment <n> --body test   # on the 'ro' slot: 403 — confirms read-only
```

## Caveats to mention

- Fine-grained tokens on org-owned repos often **404 until an org admin approves them**. If the user gets 404s on repos they know exist, that's almost always why.
- `gh api` can issue write requests too. Read-only at the token level still protects them, but if they want belt-and-braces at the harness layer they can also add `Bash(gh api:*)` to deny rules — usually overkill.
- Token expiry: fine-grained PATs require an expiration. Remind them they'll need to rotate.

## What NOT to suggest

- Classic PATs (`repo` scope grants write).
- SSH keys / deploy keys (don't help `gh`).
- Adding `gh` allow-rules to Claude's `settings.json` as an alternative — that gates Claude's prompts, not GitHub's permissions. If the user specifically wants the prompt-gating approach, that's a separate question; this skill is for the token path.
