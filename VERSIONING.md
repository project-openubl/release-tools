# Versioning and Branching in Openubl

This document outlines how we handle versioning in the Openubl
organization.

Individual projects inside the Openubl organization may have more specific
rules and/or guidelines.

# Overview

Openubl follows [Semantic Versioning](https://semver.org/). This means that
a version is expressed in the format X.Y.Z, where:

- X is the major version, representing significant changes and new features
- Y is the minor version, representing new features and improvements
- Z is the patch version, representing bug fixes and minor improvements

_NOTE_: If the major release is 0, any minor release may contain breaking changes.

# Branching

In order to maintain our guarantees two types of branches will be maintained:
`main` and `release-X.Y`.

- `main` branch is where all of the development happens. It is not guaranteed
  stable and may contain breaking changes.
- `release-X.Y` where X.Y is the minor version for a release is considered
  stable. These branches will receive backport fixes for critical issues, but no
  new features will be added.

# Releases

All releases from the main branch will be marked as pre-release and be of the
form `vX.Y.0-alpha.n`, where `X.Y` represents the next minor release and `n`
follows Semantic Versioning precedence rules for pre-release. For example,
if the next minor release is going to be 2.0, a pre-release from the main
branch might be `v2.0.0-alpha.1` or `v2.0.0-alpha.2`, depending on the number of
pre-releases that have been made so far. By marking releases from the main
branch as pre-release, we aim to clearly indicate that the code may contain
breaking changes and is not yet considered stable.

Releases from `release-X.Y` branches contain stable code and always start with
`vX.Y.0`. For example, the first release on a `release-2.3` branch would be
`v2.3.0` and after critical issues are fixed + backported, the next release on
the same branch would be `v2.3.1`. Marking these as full releases, we aim to
indicate that they are stable, tested, and usable in production settings.

_NOTE_ When we say release, we are referring to a
[GitHub release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
and the associated git tag.

# Pull Request (PR) Process

PR titles must follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope][!]: <description>
```

PRs are squash-merged, so the title becomes the commit on the base branch. It is
checked by [verify-pr-title](./.github/workflows/verify-pr-title.yaml).

| Type       | Use for                                  |
|------------|------------------------------------------|
| `feat`     | New feature                              |
| `fix`      | Bug fix                                  |
| `docs`     | Documentation only                       |
| `refactor` | Code change with no behavior change      |
| `perf`     | Performance improvement                  |
| `test`     | Tests only                               |
| `build`    | Build system or dependencies             |
| `ci`       | CI configuration                         |
| `chore`    | Other maintenance (e.g. Dependabot)      |
| `style`    | Formatting only                          |
| `revert`   | Revert a previous change                 |

Mark breaking changes with `!`, e.g. `feat(api)!: remove v1 endpoints`.

Examples:

```
feat(xml): support credit notes
fix: handle empty response in signer
chore(deps): bump actions/checkout from 4 to 5
```
