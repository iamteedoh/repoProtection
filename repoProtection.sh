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

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    echo "Error: jq is not installed."
    echo ""
    echo "Install it using one of the following:"
    echo "  macOS (Homebrew):    brew install jq"
    echo "  Fedora/RHEL (dnf):   sudo dnf install jq"
    echo "  Debian/Ubuntu (apt): sudo apt install jq"
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

# Desired protection settings
declare -A DESIRED=(
    ["Require pull request before merging"]="yes"
    ["Required approving reviews"]="1"
    ["Dismiss stale reviews"]="yes"
    ["Enforce admins"]="no"
    ["Allow force pushes"]="no"
    ["Allow deletions"]="no"
)

# Parse existing protection into comparable values
parse_existing() {
    local json="$1"
    declare -gA CURRENT=()

    local has_pr_reviews
    has_pr_reviews=$(echo "$json" | jq -r '.required_pull_request_reviews // empty' 2>/dev/null)
    if [[ -n "$has_pr_reviews" ]]; then
        CURRENT["Require pull request before merging"]="yes"
        CURRENT["Required approving reviews"]=$(echo "$json" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
        CURRENT["Dismiss stale reviews"]=$(echo "$json" | jq -r 'if .required_pull_request_reviews.dismiss_stale_reviews then "yes" else "no" end')
    else
        CURRENT["Require pull request before merging"]="no"
        CURRENT["Required approving reviews"]="0"
        CURRENT["Dismiss stale reviews"]="no"
    fi

    CURRENT["Enforce admins"]=$(echo "$json" | jq -r 'if .enforce_admins.enabled then "yes" else "no" end')
    CURRENT["Allow force pushes"]=$(echo "$json" | jq -r 'if .allow_force_pushes.enabled then "yes" else "no" end')
    CURRENT["Allow deletions"]=$(echo "$json" | jq -r 'if .allow_deletions.enabled then "yes" else "no" end')
}

print_comparison() {
    local has_additions=false
    local has_removals=false
    local has_changes=false

    echo ""
    printf "  %-40s %-12s %-12s\n" "Rule" "Current" "New"
    printf "  %-40s %-12s %-12s\n" "----" "-------" "---"

    for key in "Require pull request before merging" "Required approving reviews" "Dismiss stale reviews" "Enforce admins" "Allow force pushes" "Allow deletions"; do
        local current="${CURRENT[$key]}"
        local desired="${DESIRED[$key]}"
        local marker=""
        if [[ "$current" != "$desired" ]]; then
            marker=" <--"
            has_changes=true
        fi
        printf "  %-40s %-12s %-12s%s\n" "$key" "$current" "$desired" "$marker"
    done

    echo ""
    if [[ "$has_changes" == "true" ]]; then
        echo "  Items marked with <-- will be changed."
        return 0
    else
        echo "  Existing protection already matches. No changes needed."
        return 1
    fi
}

apply_protection() {
    local mode="$1"

    if [[ "$mode" == "merge" ]]; then
        # Merge: keep existing values, only fill in what's missing or weaker
        local pr_reviews="yes"
        local review_count="${CURRENT["Required approving reviews"]}"
        local dismiss_stale="${CURRENT["Dismiss stale reviews"]}"
        local enforce_admins="${CURRENT["Enforce admins"]}"
        local force_pushes="${CURRENT["Allow force pushes"]}"
        local deletions="${CURRENT["Allow deletions"]}"

        # Only upgrade values, never downgrade
        if [[ "$review_count" -lt 1 ]]; then review_count=1; fi
        if [[ "$dismiss_stale" == "no" ]]; then dismiss_stale="yes"; fi
        # For these, "no" is more secure, so only change if currently less secure
        if [[ "$force_pushes" == "yes" ]]; then force_pushes="no"; fi
        if [[ "$deletions" == "yes" ]]; then deletions="no"; fi

        local dismiss_bool="true"
        [[ "$dismiss_stale" == "no" ]] && dismiss_bool="false"
        local enforce_bool="false"
        [[ "$enforce_admins" == "yes" ]] && enforce_bool="true"
        local force_bool="false"
        [[ "$force_pushes" == "yes" ]] && force_bool="true"
        local delete_bool="false"
        [[ "$deletions" == "yes" ]] && delete_bool="true"

        gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection" \
            -X PUT \
            -H "Accept: application/vnd.github+json" \
            --input - <<MERGE_EOF > /dev/null
{
  "required_pull_request_reviews": {
    "required_approving_review_count": ${review_count},
    "dismiss_stale_reviews": ${dismiss_bool}
  },
  "enforce_admins": ${enforce_bool},
  "required_status_checks": null,
  "restrictions": null,
  "allow_force_pushes": ${force_bool},
  "allow_deletions": ${delete_bool}
}
MERGE_EOF
    else
        # Overwrite: apply desired settings as-is
        gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection" \
            -X PUT \
            -H "Accept: application/vnd.github+json" \
            --input - <<'OVERWRITE_EOF' > /dev/null
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
OVERWRITE_EOF
    fi
}

# Check if protection already exists
EXISTING=$(gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection" 2>/dev/null || true)
if [[ -n "$EXISTING" && "$EXISTING" != *'"message"'* ]]; then
    echo ""
    echo "Branch protection already exists on '$DEFAULT_BRANCH'."
    echo ""
    echo "Current protection vs. what this script applies:"

    parse_existing "$EXISTING"

    if print_comparison; then
        echo ""
        echo "Options:"
        echo "  [m] Merge  — keep existing settings, only add missing protections (never weakens security)"
        echo "  [o] Overwrite — replace all settings with this script's defaults"
        echo "  [a] Abort  — make no changes"
        echo ""
        read -rp "Choose [m/o/a]: " CHOICE
        case "${CHOICE,,}" in
            m)
                echo "Merging protection rules..."
                apply_protection "merge"
                ;;
            o)
                echo "Overwriting protection rules..."
                apply_protection "overwrite"
                ;;
            *)
                echo "Aborted."
                exit 0
                ;;
        esac
    else
        exit 0
    fi
else
    echo "Applying branch protection..."
    apply_protection "overwrite"
fi

echo "Done. Branch protection applied to '${DEFAULT_BRANCH}' on '${REPO}'."
echo ""
echo "Rules applied:"
echo "  - Require pull request before merging"
echo "  - Require 1 approval"
echo "  - Dismiss stale reviews on new commits"
echo "  - No force pushes"
echo "  - No branch deletion"
echo "  - Admin bypass allowed"
