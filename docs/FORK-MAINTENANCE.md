# Fork maintenance

This fork follows stable releases from
[`Gentleman-Programming/engram`](https://github.com/Gentleman-Programming/engram)
through a review-only candidate workflow. It does not mirror upstream tags or
publish upstream artifacts.

## Trust boundaries

- `.github/**`, `fork/**`, and this document are fork-owned protected paths.
  Candidate snapshots restore them from the fork base before any candidate code
  runs. `fork/upstream.json` is the only protected file updated by the trusted
  preparation shell.
- Upstream releases must be non-draft, non-prerelease strict semantic versions.
  Their tags are fetched into namespaced remote refs, never local tags, resolved
  to full commits, and required to be reachable from upstream `main`.
- Preparation may push only the versioned candidate branch
  `ci/upstream-vX.Y.Z`. It never pushes `main`, tags, releases, packages, or
  images. Rebuilding an existing same-version branch uses an exact
  `--force-with-lease`.
- Inherited release, container-image, and npm publishing jobs are guarded so
  they run only in `Gentleman-Programming/engram`, not in this fork.

`fork/upstream.json` records the upstream source snapshot reviewed by the fork.
It is not a statement about an installed binary, a published artifact, or
runtime provenance.

## Candidate validation and review

The validation job has read-only repository access and checks out the exact
candidate commit without persisted credentials. Before executing candidate
code, it verifies that protected fork content matches the fork base except for
`fork/upstream.json`. The protected validator then runs:

1. `go mod verify`
2. unit tests
3. server end-to-end tests
4. a version-stamped `./cmd/engram` build
5. `doctor --json` with an isolated `ENGRAM_DATA_DIR`
6. a newline-delimited JSON-RPC `initialize` request through
   `mcp --tools=agent`

Only successful validation may create or update a draft pull request. A human
must review the source diff, confirm the checks, and apply the `type:chore`
label manually. The workflow never approves or merges a pull request.

When the workflow creates a new draft pull request, it sends a plain-text
Telegram notification containing the release tag and pull request URL. After
Telegram confirms the expected chat and optional topic, the workflow adds a
hidden delivery marker to the pull request body. Updating an existing candidate
does not send another notification while that marker is present.

Telegram delivery is fail-closed: a missing credential, rejected request, or
mismatched destination fails the workflow after the pull request has been
created. Rerunning the workflow retries delivery while the marker is absent.
This provides at-least-once delivery. A timeout after Telegram accepts a message
can still produce a duplicate because the Bot API has no idempotency key.

Configure the following repository settings:

- Actions secret `TELEGRAM_BOT_TOKEN`: BotFather token for the sending bot.
- Actions secret `TELEGRAM_CHAT_ID`: numeric destination chat identifier.
- Actions variable `TELEGRAM_MESSAGE_THREAD_ID`: optional positive topic
  identifier for a forum destination.

Repository settings must allow GitHub Actions to create pull requests for the
`GITHUB_TOKEN` used here. GitHub also restricts workflow chaining and approvals
originating from `GITHUB_TOKEN`; do not treat the automation's PR authorship as
approval, and manually confirm any branch-protection checks that are not
triggered automatically. Workflows for `opened` or `synchronize` events on a PR
created by `GITHUB_TOKEN` require approval; a maintainer must approve those
workflow runs.

## Explicit promotion and rollback

Merging a candidate updates source only. Current clients remain on their
installed binary until an operator explicitly promotes a reviewed build.

Before promotion:

1. Stop writes and make a consistent SQLite backup, including any WAL state.
2. Rehearse the upgrade against a copy of that backup and run the same doctor
   and smoke checks used for the candidate.
3. Record the previous binary and database backup as one rollback point.
4. Promote the reviewed binary explicitly; do not infer promotion from the
   upstream tag or `fork/upstream.json`.

Rollback must restore the previous binary and its matching database backup
together. Do not run an older binary against a database already migrated by a
newer version unless that downgrade path has been explicitly verified.
