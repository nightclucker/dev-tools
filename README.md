# dev-tools

A collection of scripts and tools for automating common setup, maintenance, and workflow tasks across a game or software studio. Built for use by developers, artists, producers, and other roles who need reliable, repeatable tooling without having to learn the underlying systems (e.g. Perforce, build pipelines, etc.) in depth.

## Scripts

### `new-p4-project-setup.sh`

Bootstraps a new Perforce (P4) project: creates the project's stream depot, mainline and release streams, a project group, and the permissions to tie them together.

It creates:
- A stream depot named after the project.
- Mainline streams: `Main`, `ArtSource`, `Tools`.
- Release streams: `Staging`, `Production`, `Live` (parented off `Main`, no merge-down to parent).
- A P4 group containing the given users.
- A `write` protection entry granting that group access to the new depot.

The script is idempotent — re-running it will skip any depot, stream, group, or protection entry that already exists.

#### Requirements

- The [Perforce CLI (`p4`)](https://www.perforce.com/downloads/helix-command-line-client-p4) installed and available on `PATH`.
- An active `p4 login` session.
- The logged-in P4 user must be a member of the `Super` group (required to create depots, streams, and groups).

#### Usage

```bash
./new-p4-project-setup.sh <project_name> <project_users>
```

- `project_name` — Name of the new project. Used as the depot name and group name.
- `project_users` — Comma-separated list of P4 usernames to add to the project group. The **first** user in the list is treated as the project owner/requester.

Example:

```bash
./new-p4-project-setup.sh MyGame alice,bob,carol
```

This creates the `MyGame` depot, its mainline/release streams, a `MyGame` group with `alice`, `bob`, and `carol` as members (owned by `alice`), and grants that group write access to `//MyGame/...`.

Progress and errors are logged to stdout and to the system log (via `logger`, tag `p4-project-setup`).

### `p4-project-bootstrap.sh`

An independent implementation of the same idea as `new-p4-project-setup.sh` (built from [p4-setup-script-design.md](p4-setup-script-design.md)), with a couple of extra conveniences: a dry-run mode, adding missing users to an existing group on re-run, and a creation timestamp/description on every spec it writes.

It creates:
- A stream depot named after the project (`StreamDepth: 2`).
- Mainline streams: `Main`, `ArtSource`, `Tools` (under `dev/`).
- Release streams: `Staging`, `Production`, `Live` (under `release/`), parented off `Main` → `Staging` → `Production` → `Live`. Only `Staging` merges back down to its parent; `Production` and `Live` do not.
- A P4 group containing the given users.
- A `write` protection entry granting that group access to the new depot, inserted ahead of the table's existing rules.

The script is idempotent — re-running it will skip any depot, stream, group, or protection entry that already exists, and will add any new users to an existing group.

#### Requirements

- The [Perforce CLI (`p4`)](https://www.perforce.com/downloads/helix-command-line-client-p4) installed and available on `PATH`.
- An active `p4 login` session.
- The logged-in P4 user must be a member of the `Super` group (required to create depots, streams, and groups).

#### Usage

```bash
./p4-project-bootstrap.sh [-n|--dry-run] <project_name> <project_users>
```

- `project_name` — Name of the new project. Used as the depot name and group name.
- `project_users` — Comma-separated list of P4 usernames to add to the project group. The **first** user in the list is treated as the project owner/requester.
- `-n`, `--dry-run` — Show what would be created without making any changes.

Example:

```bash
./p4-project-bootstrap.sh MyGame alice,bob,carol
```



This creates the `MyGame` depot, its mainline/release streams, a `MyGame` group with `alice`, `bob`, and `carol` as members (owned by `alice`), and grants that group write access to `//MyGame/...`.

Progress and errors are logged to stdout and to the system log (via `logger`, tag `p4-project-bootstrap`).
