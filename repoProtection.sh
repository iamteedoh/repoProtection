#!/usr/bin/env bash
#
# Apply branch protection rules to a GitHub repository's default branch.
#
# Usage:
#   ./repoProtection.sh <repo-name>
#   ./repoProtection.sh <owner/repo-name>
#
# Examples:
#   ./repoProtection.sh nvidiaInstaller
#   ./repoProtection.sh iamteedoh/nvidiaInstaller
#
# Requirements: gh (GitHub CLI) must be authenticated.
#
# If not authenticated, you will see:
#   "To get started with GitHub CLI, please run: gh auth login"
#
# To authenticate, run:
#   gh auth login

set -euo pipefail

# Check if gh CLI is installed
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo ""
    echo "Install it using one of the following:"
    echo "  macOS (Homebrew):    brew install gh"
    echo "  Fedora/RHEL (dnf):   sudo dnf install gh"
    echo "  Debian/Ubuntu (apt): sudo apt install gh"
    echo ""
    echo "For other platforms: https://github.com/cli/cli#installation"
    exit 1
fi

# Check if gh CLI is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: GitHub CLI is not authenticated."
    echo "To get started, run: gh auth login"
    exit 1
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <repo-name>"
    echo "       $0 <owner/repo-name>"
    exit 1
fi

REPO="$1"

# If no owner specified, get the authenticated user
if [[ "$REPO" != *"/"* ]]; then
    OWNER=$(gh api user --jq '.login')
    REPO="${OWNER}/${REPO}"
fi

# Verify the repo exists and get its default branch
DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo "Error: Could not find repo '$REPO' or determine its default branch."
    exit 1
fi

echo "Repo:   $REPO"
echo "Branch: $DEFAULT_BRANCH"

# Check if protection already exists
EXISTING=$(gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection" 2>/dev/null || true)
if [[ -n "$EXISTING" && "$EXISTING" != *'"message"'* ]]; then
    echo "Warning: Branch protection already exists on '$DEFAULT_BRANCH'."
    read -rp "Overwrite? (y/N): " CONFIRM
    if [[ "${CONFIRM,,}" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Apply branch protection
echo "Applying branch protection..."
gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection" \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    --input - <<'EOF'
{
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "enforce_admins": false,
  "required_status_checks": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

if [[ $? -eq 0 ]]; then
    echo "Done. Branch protection applied to '${DEFAULT_BRANCH}' on '${REPO}'."
    echo ""
    echo "Rules applied:"
    echo "  - Require pull request before merging"
    echo "  - Require 1 approval"
    echo "  - Dismiss stale reviews on new commits"
    echo "  - No force pushes"
    echo "  - No branch deletion"
    echo "  - Admin bypass allowed"
else
    echo "Error: Failed to apply branch protection. Is the repo public?"
    exit 1
fi
