# Release Tools

This project contains, or should contain, all of the configuration and automation to maintain, build, and release Openubl projects.

Check out the [config.yaml](./pkg/config/config.yaml) to see:

1. The repositories we are managing
1. The Labels we are configuring in repositories
1. The milestones we are configuring in repositories

This allows us to have a single source of truth to make sure that, as we create
enhancments, issues, and pull requests, they can be tracked properly.

You can find our reusable GitHub Workflows in [./.github/workflows](./.github/workflows).

## Releasing xhandler

[`release-xhandler`](./.github/workflows/release-xhandler.yaml) releases
[xhandler-rust](https://github.com/project-openubl/xhandler-rust),
[xhandler-go](https://github.com/project-openubl/xhandler-go),
[xhandler-python](https://github.com/project-openubl/xhandler-python) and
[xhandler-java](https://github.com/project-openubl/xhandler-java) with the same version
([VERSIONING.md](./VERSIONING.md): `vX.Y.0-alpha.n` from `main`, `vX.Y.Z` from `release-X.Y`).
Run it from Actions → Release xhandler with the version, and the branch for a stable release
(empty: each repository's default branch).

1. Before tagging anything, it checks every repository ([`preflight.sh`](./hack/preflight.sh)): the
   bot can reach it, the branch exists, CI is required on it and passed on its head.
1. It tags xhandler-rust with [`create-release`](./create-release/action.yml) and waits for the
   repository's release workflow. That workflow publishes `xhandler` and `xhandler-cli` to crates.io
   and attaches the CLI binaries and the core the libraries use (`xhandler-dist-<version>.tar.gz`,
   `xhandler.wasm`, `SHA256SUMS`).
1. For each library, a pull request syncs that core (`make sync CORE=<version>`) and auto-merges
   once the branch's required checks pass. Then the merge commit is tagged and the library's
   release workflow publishes it.
   A library is only released with the xhandler-rust core of the same version: its release workflow
   checks the core's `VERSION` and the `xhandler.wasm` checksum (`make verify-release`), and
   release-tools checks it before tagging.
1. A pull request moves [xhandler-mobile](https://github.com/project-openubl/xhandler-mobile) to the
   released crate. Its store releases stay manual.

The tag is the version: each release workflow sets it at build time, so the branches keep a
development version (Python's is the version of the core it carries). Versions are `vX.Y.Z` or
`vX.Y.Z-alpha.N`, `-beta.N`, `-rc.N`: the pre-releases every package manager agrees on.

Each repository's `.github/workflows/release.yml` runs on `release: published` and on
`workflow_dispatch` with a `tag` input, has `run-name: Release <tag>` (that is how release-xhandler
finds its run) and skips what is already published, so running it twice is safe.

**When something fails**, fix it and run release-xhandler again with the same version: existing
releases are kept and published packages are skipped. A release workflow that failed is not
re-run, since a re-run uses the workflow file of the tagged commit; it is dispatched from the
default branch instead, so a fix merged there applies to the existing tag. A tag is never moved:
for Go the tag is the publication (the Go module proxy keeps the first commit of a version
forever). Don't create library releases by hand: release-xhandler checks the core before tagging.

The libraries' `hack/core.sh` (`make sync CORE=`, `make verify-core`, `make verify-release`) is a
copy of [`xhandler/core.sh`](./xhandler/core.sh). Change it here first, then copy it to the three
libraries: their CI fails while a copy differs (`make verify-core-script`).

One-time setup:

- **Bot**: the openubl bot App (`OPENUBL_BOT_ID`, `OPENUBL_BOT_KEY`) installed on the five repositories
  with read and write access to contents, pull requests and actions (to rerun a failed release
  workflow). Branch protection or rulesets must let it merge the sync pull requests once CI passes
  (no required review for it) and create `v*` tags.
- **Branches**: an X.Y.Z release needs the `release-X.Y` branch in every repository
  (`_cut-release-branches`).
- **Environments**: `crates-io` in xhandler-rust and `pypi` in xhandler-python. If you restrict
  their deployments, allow the `v*` tags and the default branch (a dispatched release workflow runs
  from it).
- **crates.io**: the first release creates the crates with a `CARGO_REGISTRY_TOKEN` secret (in
  xhandler-rust's `crates-io` environment, or the organization's); its account owns the crates. Then add a trusted publisher to `xhandler` and
  `xhandler-cli` (repository `project-openubl/xhandler-rust`, workflow `release.yml`, environment
  `crates-io`) and delete the secret.
- **PyPI**: a pending trusted publisher for the `xhandler` project (repository
  `project-openubl/xhandler-python`, workflow `release.yml`, environment `pypi`).
- **Maven Central**: xhandler-java's existing secrets (`NEXUS_*`, `GPG_*`).
- **Go**: nothing. The module proxy serves the tag.

## Reusable Workflows

### [auto-merge-dependabot](./.github/workflows/auto-merge-dependabot.yaml)

Approves Dependabot PRs with the openubl bot and enables GitHub auto-merge on them. The PR is
merged only after the repository's **required status checks** pass, so CI stays the gate.

This repository uses it too, via [`_auto-merge-dependabot.yaml`](./.github/workflows/_auto-merge-dependabot.yaml).

To opt in, add `.github/workflows/auto-merge-dependabot.yaml` to your repository:

```yaml
name: Auto-merge Dependabot PRs

on:
  pull_request_target:
    types: [opened, synchronize, reopened]
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-merge:
    uses: project-openubl/release-tools/.github/workflows/auto-merge-dependabot.yaml@main
    secrets: inherit
    # Optional:
    # with:
    #   update-types: "patch,minor"   # default: "patch,minor,major"
    #   merge-method: "squash"        # default: "squash"
```

Requirements:

1. **Org (once):** the bot App (needs Contents, Pull requests and Workflows read/write) is installed
   on the repository, the `OPENUBL_BOT_ID` variable is visible to it, and the `OPENUBL_BOT_KEY`
   secret exists in **both** the Actions and the **Dependabot** secret stores (Dependabot-triggered
   runs can only read Dependabot secrets).
2. **Repository settings:** "Allow auto-merge" is enabled.
3. **Branch protection / ruleset on `main`:** the CI checks are marked as *required*. Without
   required checks, auto-merge merges the PR immediately.
4. **Recommended:** add a `cooldown` (e.g. `default-days: 7`) to `.github/dependabot.yml` so freshly
   published (possibly compromised) releases are not merged right away.

### [verify-pr-title](./.github/workflows/verify-pr-title.yaml)

Fails unless the PR title follows [Conventional Commits](https://www.conventionalcommits.org/)
(see [allowed types](./VERSIONING.md#pull-request-pr-process)). Uses
[amannn/action-semantic-pull-request](https://github.com/amannn/action-semantic-pull-request).

To opt in, add `.github/workflows/verify-pr-title.yaml` to your repository:

```yaml
name: Verify PR title

on:
  pull_request_target:
    types: [opened, edited, synchronize, reopened]

permissions:
  pull-requests: read

jobs:
  verify-pr-title:
    uses: project-openubl/release-tools/.github/workflows/verify-pr-title.yaml@main
    # Optional:
    # with:
    #   scopes: |
    #     api
    #     ui
    #   require-scope: true
    #   ignore-labels: |
    #     skip-title-check
```

Recommended repository settings:

1. **Squash merge** with the default message set to **"Pull request title"**, so the validated title
   lands on `main` (or set `validate-single-commit: true`).
2. **Ruleset on `main`:** require the `verify-pr-title / Verify PR title` check.
3. **Dependabot:** conventional commit messages in `.github/dependabot.yml`:

   ```yaml
   commit-message:
     prefix: "chore"
     include: "scope"   # -> "chore(deps): bump ..."
   ```
