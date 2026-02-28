# repoProtection

A collection of bash scripts for managing GitHub repositories using the GitHub CLI (`gh`):

- **repoProtection.sh** — Apply branch protection rules to a repository's default branch
- **repoList.sh** — List repositories with sorting/filtering and manage GNU GPL v3 licenses

## Why This Matters

By default, GitHub repositories have no branch protection on their default branch. This means anyone with write access can push directly to `main`, rewrite history, or delete the branch entirely — with no review process and no way to recover.

This is especially risky for public repositories, where collaborators may be added over time and mistakes (or malicious actions) can go unnoticed.

### What can go wrong without branch protection?

- **Unreviewed code in production** — A collaborator pushes buggy or malicious code directly to `main` with no pull request or review. There's no safety net to catch issues before they're merged.
- **Rewritten history via force push** — Someone runs `git push --force` to `main`, overwriting the entire commit history. Previous work is lost and cannot be recovered from the remote.
- **Deleted default branch** — A collaborator (accidentally or intentionally) deletes the `main` branch, disrupting the entire project.
- **Stale approvals hiding new changes** — A pull request gets approved, then the author pushes additional unreviewed commits before merging. Without stale review dismissal, those new changes slip in without anyone looking at them.
- **Bypassed review process** — Even with a team agreement to "always use PRs," nothing actually enforces it. Without branch protection, the review process is optional and easily skipped.

This script applies a baseline set of protections that prevent all of the above while still allowing repo admins to bypass the rules in an emergency.

## What It Does

Protects the default branch (e.g. `main` or `master`) with the following rules:

- **Require pull request before merging** — no direct pushes allowed
- **Require 1 approval** before merging
- **Dismiss stale reviews** — previous approvals are invalidated when new commits are pushed
- **No force pushes** — history cannot be rewritten
- **No branch deletion** — default branch cannot be deleted
- **Admin bypass allowed** — repo admins can still push directly if needed

## Prerequisites

### GitHub CLI (`gh`)

The script requires the [GitHub CLI](https://cli.github.com/). Install it for your platform:

| Platform | Command |
|----------|---------|
| macOS (Homebrew) | `brew install gh` |
| Fedora/RHEL (dnf) | `sudo dnf install gh` |
| Debian/Ubuntu (apt) | `sudo apt install gh` |

For other platforms, see the [official installation guide](https://github.com/cli/cli#installation).

### jq

The script uses [jq](https://jqlang.github.io/jq/) to parse JSON responses from the GitHub API.

| Platform | Command |
|----------|---------|
| macOS (Homebrew) | `brew install jq` |
| Fedora/RHEL (dnf) | `sudo dnf install jq` |
| Debian/Ubuntu (apt) | `sudo apt install jq` |

### Authentication

After installing, authenticate with GitHub:

```bash
gh auth login
```

### Repository Visibility

The target repository must be **public**. Branch protection is not available on GitHub's free plan for private repos.

## Usage

```bash
./repoProtection.sh <repo-name>
./repoProtection.sh <owner/repo-name>
```

If no owner is specified, it defaults to the authenticated GitHub user.

### Examples

```bash
# Protect a repo you own
./repoProtection.sh myRepo

# Protect a repo with explicit owner
./repoProtection.sh myorg/myRepo
```

### Pre-flight Checks

The script validates the following before applying any changes:

1. **`gh` is installed** — if not, it prints install instructions for macOS, Fedora/RHEL, and Debian/Ubuntu
2. **`jq` is installed** — if not, it prints install instructions for macOS, Fedora/RHEL, and Debian/Ubuntu
3. **`gh` is authenticated** — if not, it prompts you to run `gh auth login`
4. **Repository exists** — verifies the repo and its default branch are accessible
5. **Existing protection** — if rules already exist, the script displays a side-by-side comparison of current vs. new settings and presents three options:
   - **Merge** — keeps existing settings and only adds missing protections (never weakens security)
   - **Overwrite** — replaces all settings with the script's defaults
   - **Abort** — makes no changes

If existing protection already matches the script's defaults, it reports that no changes are needed and exits.

## Installation

```bash
git clone git@github.com:iamteedoh/repoProtection.git
chmod +x repoProtection/repoProtection.sh
```

Then run it directly or add it to your `$PATH`.

## Notes

- The script auto-detects the repository's default branch
- Only applies to a single repository per invocation
- No sensitive data is stored in the script — authentication is handled by `gh`

---

## repoList.sh

List all your GitHub repositories with sorting and filtering, check for GNU GPL v3 licenses, and interactively add the license to repos that are missing it.

### Why This Matters

Open-source repositories without a license are technically "all rights reserved" — no one can legally use, modify, or distribute the code. Adding a GPL-3.0 license ensures your public repos are properly licensed and that downstream users must share their modifications under the same terms.

### What It Does

- **List repos** — display all your repos in a formatted table with visibility, stars, license, and last updated date
- **Sort** — by latest activity, star count, name, or visibility (public first)
- **Filter** — show all, public-only, or private-only repos
- **License check** — categorize repos by license status (GPL-3.0 / other / none)
- **License add** — interactively add GPL-3.0 to repos missing it, with warnings before replacing existing licenses

### Usage

#### List repositories

```bash
# List all repos (sorted by latest activity)
./repoList.sh list

# List public repos sorted by stars
./repoList.sh list --sort stars --filter public

# List private repos sorted by name (max 50)
./repoList.sh list --filter private --sort name --limit 50

# List all repos grouped by visibility
./repoList.sh list --sort visibility
```

#### Check licenses

```bash
# Check which public repos lack GPL-3.0
./repoList.sh license --check

# Check license status across all repos
./repoList.sh license --check --filter all

# Interactively add GPL-3.0 to public repos missing it
./repoList.sh license --add
```

### List Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--sort` | `latest`, `stars`, `name`, `visibility` | `latest` | Sort method |
| `--filter` | `all`, `public`, `private` | `all` | Visibility filter |
| `--limit` | any positive integer | `100` | Max repos to display |

### License Options

| Option | Description |
|--------|-------------|
| `--check` | Show license status summary (default action) |
| `--add` | Interactively add GPL-3.0 to repos missing it |
| `--filter` | Visibility filter (default: `public` for license subcommand) |

### Interactive License Flow

When using `--add`, the script presents three options:

- **[a] Add to all** — adds GPL-3.0 to every eligible repo (prompts before replacing existing non-GPL licenses)
- **[s] Select individual** — step through each repo one by one
- **[q] Quit** — make no changes

Archived and empty repos are automatically excluded from the candidates list.
