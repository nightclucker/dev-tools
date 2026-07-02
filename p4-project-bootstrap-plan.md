# New P4 Project Bootstrap Script (independent implementation)

## Context

`dev-tools` currently has one script, `new-p4-project-setup.sh`, which bootstraps a new Perforce project (depot + streams + group + permissions). A new design doc, `p4-setup-script-design.md`, was added to spec out the same kind of tool but explicitly instructs: **"Don't use the existing `new-p4-project-setup.sh` script for reference!"** — this is meant as an independent, from-scratch implementation exercise, not a rewrite/refactor of the old file. The old script and its README stay untouched, and the new script is added as its own file so both can be compared.

Two naming ambiguities in the design doc were resolved with the user:
- Second mainline stream is **`ArtSource`** (design doc said "ArtTools", which is treated as a typo).
- Third release-flow stream is **`Production`** (design doc's "Production or Release" phrasing resolved to `Production`).

Nice-to-have scope was left to my judgment; given the design doc's explicit "keep it simple" directive, v1 includes only the cheap, high-value ones (dry-run, add-missing-users-on-rerun, creation timestamp/description) and defers the infra-heavy ones (Docker image, email notification, per-stream README files, arbitrary extra streams, hard user validation).

## Deliverables

1. **`p4-project-bootstrap.sh`** (new file, repo root) — the script itself.
2. **`README.md`** — add a new `### \`p4-project-bootstrap.sh\`` section mirroring the existing script's doc section (Requirements / Usage / Example / behavior bullets).

## Script Design

### Structure (`#!/usr/bin/env bash`, `set -euo pipefail`)

- `usage()` — help text; `-h`/`--help` exits 0, argument errors print usage + reason and exit 1.
- `parse_args()` — handles `-n|--dry-run`, `-h|--help`, positional `project_name`, `users_csv`.
- `validate_project_name()` — enforce `^[A-Za-z][A-Za-z0-9_-]{0,63}$` (rejects P4-special chars `@ # * % /` and whitespace, since this name becomes the depot, group, and protections-table entry).
- `validate_users_list()` — split CSV, trim, reject empty/duplicate entries, capture first entry as `OWNER_USER`. Soft-check each user via `p4 user -o <name>` and **warn** (not fail) if one doesn't resolve — full hard validation was explicitly deferred (see Nice-to-haves below).
- `check_prerequisites()` — `command -v p4`; `p4 login -s` for an active session; confirm current user is in the `Super` group (via `p4 info` for the current user, then `p4 groups <user>` grep for `Super`). Any failure exits 1 before anything is created.
- `_log()/log_info()/log_warn()/log_error()` — stdout + `logger -t p4-project-bootstrap`, guarded with `command -v logger` so it degrades gracefully on hosts without syslog (e.g. minimal Jenkins agents).
- Existence checks: `depot_exists()`, `stream_exists()`, `group_exists()`, `protection_exists()` — each a pure query, no mutation, used to drive create-or-skip idempotency.
- Creation functions: `create_depot()`, `create_mainline_stream(name)`, `create_release_stream(name, parent, allow_mergedown)`, `create_group()`, `update_group_members()`, `update_protections_table()`. Every creation function checks `DRY_RUN` first and, if set, logs the action it *would* take instead of calling `p4 ... -i`.
- `main()` orchestrates: parse args → check prerequisites → create depot → create the 3 mainline streams → create the 3 release streams in parent order → create/update group → update protections table.

### Idempotency

Check-then-act, never relying on `p4`'s own upsert behavior (e.g. `p4 depot -i` on an existing depot would silently update it rather than error):

- **Depot:** `p4 depots -e "<Project>"` — empty output means it doesn't exist.
- **Stream:** `p4 streams -F "Stream=//<Project>/<dev|release>/<Name>"` — only lists specs that actually exist (avoids `p4 stream -o`'s "phantom template" ambiguity for non-existent streams).
- **Group:** `p4 groups` output, exact-match grep.
- **Protection:** `p4 protect -o`, grep for an existing line already granting this group access to this depot path.

### Stream topology

Depot: `Type: stream`, `StreamDepth: 2` (paths shaped `//<Project>/<dev|release>/<Name>`).

- **Mainline streams** (`dev` category), one generic `create_mainline_stream(name)` for all three:
  - `//<Project>/dev/Main`, `//<Project>/dev/ArtSource`, `//<Project>/dev/Tools` — `Type: mainline`, no parent, default merge options.
- **Release streams** (`release` category), one generic `create_release_stream(name, parent, allow_mergedown)`:
  - `//<Project>/release/Staging` — `Parent: //<Project>/dev/Main`, `Type: release`, `ParentView: inherit`, `Options: allsubmit unlocked toparent fromparent mergedown` (this is the one exception the design doc calls out: Staging's parent *is* the base Main, so merge-down is allowed).
  - `//<Project>/release/Production` — `Parent: //<Project>/release/Staging`, `Type: release`, `ParentView: noinherit`, `Options: allsubmit unlocked notoparent fromparent mergedown` (no merge back to parent).
  - `//<Project>/release/Live` — `Parent: //<Project>/release/Production`, same `noinherit`/`notoparent` shape as Production.

This reproduces "Main <-> Staging -> Production -> Live, release streams don't inherit except Staging" using P4's `Options:` line (the field that actually governs merge/copy flow) rather than the `Type:` field, which is closer to how Perforce's stream mechanics really work.

### Protections table insertion

Blind-appending a new `write group <Project> * //<Project>/...` line is unsafe because P4 evaluates protection rules in order — a later rule can widen or shadow an earlier one. Algorithm:

1. `p4 protect -o` → parse the `Protections:` block into an ordered list of rule lines (preserve comments/blank lines where possible).
2. Insert the new rule **after** the last rule scoped to a global/broad path (`//...`) and **before** the first pre-existing rule scoped to this same project or a narrower/overlapping path (keeps project-specific rules grouped, and ensures the new grant isn't shadowed by an existing narrower exclude). If the table has no clear structure, append and log a warning to review manually.
3. Reassemble and pipe through `p4 protect -i`.
4. In dry-run mode, print a diff of the intended before/after table without calling `p4 protect -i`.

### Nice-to-haves included in v1

- **Dry-run (`-n`/`--dry-run`):** every mutating call gated behind this flag; logs the action it would take instead.
- **Add-missing-users-on-rerun:** `update_group_members()` diffs the existing group's `Users:` against the parsed CSV and appends only the missing names, leaving `Owners:` and everything else untouched.
- **Creation timestamp + description:** every spec form (depot/stream/group) gets a `Description:` line like `Created by p4-project-bootstrap.sh on <UTC timestamp> for project <Project>.`

### Nice-to-haves deferred (with reasons)

- Per-stream README.md — needs a real P4 client workspace + submit machinery this script otherwise never touches; disproportionate for a cosmetic nicety.
- Docker image — packaging concern; no CI exists in this repo to build/publish one.
- Email/message notification — needs SMTP/webhook config not present anywhere in the repo; better left to the calling Jenkins job reacting to exit code/log output.
- Arbitrary extra streams parameter — not in Main Features; adds parsing/validation complexity for an unrequested use case.
- Hard p4-username validation — implemented as a soft warning only (see `validate_users_list()` above), not a hard failure, since strict validation could block valid but not-yet-synced accounts.

## Verification

No test framework exists in this repo and real execution needs P4 server access, so verification is manual, against a real or disposable sandbox `p4d`:

1. `--dry-run` pass against a non-existent project — confirm logged actions and protections-diff preview look correct, no server mutation.
2. Real run — confirm via `p4 depots -e`, `p4 streams //<Project>/...`, `p4 group -o`, `p4 protect -o` that depot (StreamDepth=2), all 6 streams (correct parent/type/options per §Stream topology), group, and protection entry were created correctly.
3. Re-run identically — confirm every step logs "already exists, skipping" and `p4 protect -o` output is byte-identical before/after.
4. Re-run with an expanded user list — confirm only the new user is appended to the group, owner/others unchanged, no duplicate protection line.
5. Seed the sandbox's protections table with a broad `//...` rule, an exclude rule, and an unrelated project-specific rule first, then run the script — manually inspect `p4 protect -o` to confirm the new rule lands in a sane position (not before the global rule, not shadowed by the unrelated exclude).
6. Failure-path checks — malformed project name, empty user list, non-`Super` user — confirm each fails fast with a clear message and no server-side changes.
7. Confirm stdout logging is readable and (where `logger`/syslog is available) entries appear tagged `p4-project-bootstrap`.
