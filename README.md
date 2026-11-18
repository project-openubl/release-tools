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
   released crate. The app is released separately, with [release-mobile](#releasing-xhandler-mobile).
1. Once the libraries are published, a pull request moves the
   [website](https://github.com/project-openubl/project-openubl.github.io) to the release: its
   `npm run xhandler:set-version` pins the release's `xhandler.wasm` for the playground (from
   `SHA256SUMS`) and updates the versions in the docs. It never moves the website to an older
   version, and lists in the pull request what needs a person (a new Go major version path, the
   alpha notice on the first stable release). It is reviewed and merged by hand.

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

One-time setup:

- **Bot**: the openubl bot App (`OPENUBL_BOT_ID`, `OPENUBL_BOT_KEY`) installed on the five repositories
  and on project-openubl.github.io (contents and pull requests, for the website pull request)
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

## Releasing xhandler-mobile

[`release-mobile`](./.github/workflows/release-mobile.yaml) releases the
[xhandler-mobile](https://github.com/project-openubl/xhandler-mobile) app to Google Play and the App
Store. The app has its own version, with the [VERSIONING.md](./VERSIONING.md) rules: `vX.Y.0-alpha.N`
from `main`, `vX.Y.Z` from `release-X.Y`. Run it from Actions → Release xhandler-mobile with the version
and, for a stable release, the branch.

1. [`preflight.sh`](./hack/preflight.sh) checks xhandler-mobile, as for the libraries.
1. [`create-release`](./create-release/action.yml) tags it and publishes the GitHub release, which
   runs the app's `release.yml`. release-mobile waits for that workflow
   ([`wait-for-release-run.sh`](./hack/wait-for-release-run.sh)).
1. The app's release workflow builds the signed app with the version from the tag and uploads it:

   | Version | Google Play | App Store |
   |---|---|---|
   | `-alpha.N`, `-beta.N`, `-rc.N` | Internal testing | TestFlight |
   | `vX.Y.Z` | Production, staged rollout to 10% of users | TestFlight, then submitted for review |

   Making a stable release public stays a decision in the stores: raise the rollout in Play
   Console and release the approved version in App Store Connect. The signed APK, the AAB and
   their `SHA256SUMS` are attached to the GitHub release.

The store build number comes from the version, so a version is uploaded once. Rerunning
release-mobile with the same version continues and skips the builds the stores already have. The
version code scheme, the store "what's new" texts and the store secrets are in xhandler-mobile's
[docs/STORE.md](https://github.com/project-openubl/xhandler-mobile/blob/main/docs/STORE.md#release-ci).

One-time setup: the openubl bot App installed on xhandler-mobile (contents, pull requests, actions),
required CI checks and auto-merge allowed on its `main` and `release-X.Y` branches, `v*` tags allowed for
the bot, and the store secrets in xhandler-mobile. `_cut-release-branches` doesn't create the app's
`release-X.Y` branches, since its versions are not xhandler's: create them in xhandler-mobile
(`git push origin main:release-X.Y`).

## Releasing xhandler-service

[`release-xhandler-service`](./.github/workflows/release-xhandler-service.yaml) releases
[xhandler-service](https://github.com/project-openubl/xhandler-service), the monorepo of searchpe,
xhandler-service (app and engine), the single UI and the operator that deploys them. It has its own
version, with the [VERSIONING.md](./VERSIONING.md) rules: `vX.Y.0-alpha.N` from `main`, `vX.Y.Z` from
`release-X.Y`. Run it from Actions → Release xhandler-service with the version and, for a stable
release, the branch.

1. [`preflight.sh`](./hack/preflight.sh) checks xhandler-service: the branch exists, CI is required on
   it and passed on its head.
1. [`create-release`](./create-release/action.yml) tags it and publishes the GitHub release, which
   runs xhandler-service's `release.yml`. release-xhandler-service waits for that workflow
   ([`wait-for-release-run.sh`](./hack/wait-for-release-run.sh)), in two rounds of 45 minutes with a
   new token each, since the native builds can take longer than one.
1. xhandler-service's release workflow sets the tag's version (the poms on `main` keep a development
   version) and publishes:
   - the images `searchpe` (native), `searchpe-operator`, `xhandler-service`, `xhandler-engine` and
     `xhandler-ui` under `ghcr.io/project-openubl/xhandler-service/`, for amd64 and arm64, as `vX.Y.Z`.
     `latest` and `vX` move only for the highest stable release (of its major for `vX`).
   - release assets: the searchpe distribution, the OpenAPI schema, the operator bundle (built with
     those images) and `SHA256SUMS`.
1. For a stable release, [`operatorhub-pr.sh`](./hack/operatorhub-pr.sh) opens a pull request with the
   release's bundle (`searchpe-operator`, which manages both `Searchpe` and `XHandler`) to the
   [Kubernetes](https://github.com/k8s-operatorhub/community-operators) and the
   [OpenShift](https://github.com/redhat-openshift-ecosystem/community-operators-prod) catalogs, from
   our forks of them. It sets `spec.replaces` to the catalog's previous version and, for OpenShift,
   `com.redhat.openshift.versions`. The catalogs merge the pull request once their tests pass, since its
   author is a reviewer in the operator's `ci.yaml`. Pre-releases stay out of the catalogs, and so do
   patches of an older line (lower than the catalog's latest version): a channel has a single head.
   While the pull request of an earlier version is open, the catalog's job fails: merge it, then rerun.

Rerunning release-xhandler-service with the same version continues: preflight is skipped since the
release exists, a failed release workflow is dispatched again from `main`, pushed images are kept, the
assets are replaced and a catalog pull request is opened once (none when the catalog has the version).

One-time setup:

- **Bot**: the openubl bot App on xhandler-service with contents (tags and releases) and actions (to
  dispatch a failed release workflow) read and write. `v*` tags allowed for the bot.
- **CI**: required checks on xhandler-service's `main` and `release-X.Y` branches (preflight checks
  them). `_cut-release-branches` doesn't create its `release-X.Y` branches, since its versions are not
  the xhandler libraries': `git push origin main:release-X.Y` in xhandler-service.
- **ghcr.io**: the release workflow pushes with its own `GITHUB_TOKEN`. After the first release, make
  the `xhandler-service/*` container packages of the organization public, if GitHub did not.
- **OperatorHub**: an `OPERATORHUB_TOKEN` secret in release-tools, a classic token (`public_repo`,
  `workflow`) of a user listed in `reviewers` of the operator's `ci.yaml`: GitHub App tokens can't open
  pull requests in repositories outside the organization, and the catalogs only merge by themselves for
  reviewers. The forks
  ([community-operators](https://github.com/project-openubl/community-operators),
  [community-operators-prod](https://github.com/project-openubl/community-operators-prod)) must exist;
  their default branch is reset to the catalog's on every release. The first pull request to the
  OpenShift catalog adds the operator, so its maintainers review that one.

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
