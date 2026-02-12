# repoProtection

A bash script that applies branch protection rules to a GitHub repository's default branch using the GitHub CLI (`gh`).

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
2. **`gh` is authenticated** — if not, it prompts you to run `gh auth login`
3. **Repository exists** — verifies the repo and its default branch are accessible
4. **Existing protection** — if rules already exist on the branch, it prompts for confirmation before overwriting

## Installation

```bash
git clone git@github.com:<your-username>/repoProtection.git
chmod +x repoProtection/repoProtection.sh
```

Then run it directly or add it to your `$PATH`.

## Notes

- The script auto-detects the repository's default branch
- Only applies to a single repository per invocation
- No sensitive data is stored in the script — authentication is handled by `gh`
