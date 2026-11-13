# Release Tools

This project contains, or should contain, all of the configuration and automation to maintain, build, and release Openubl projects.

Check out the [config.yaml](./pkg/config/config.yaml) to see:

1. The repositories we are managing
1. The Labels we are configuring in repositories
1. The milestones we are configuring in repositories

This allows us to have a single source of truth to make sure that, as we create
enhancments, issues, and pull requests, they can be tracked properly.

You can find our reusable GitHub Workflows in [./.github/workflows](./.github/workflows).

## Reusable Workflows

### [auto-merge-dependabot](./.github/workflows/auto-merge-dependabot.yaml)

Approves Dependabot PRs with the openubl bot and enables GitHub auto-merge on them. The PR is
merged only after the repository's **required status checks** pass, so CI stays the gate.

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
