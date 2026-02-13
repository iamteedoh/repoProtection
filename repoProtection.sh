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
    ["Require code owner reviews"]="no"
    ["Require approval of most recent push"]="no"
    ["Require status checks to pass"]="no"
    ["Require branches to be up to date"]="no"
    ["Enforce admins"]="no"
    ["Require linear history"]="no"
    ["Require conversation resolution"]="no"
    ["Require signed commits"]="no"
    ["Lock branch"]="no"
    ["Allow force pushes"]="no"
    ["Allow deletions"]="no"
    ["Block creations"]="no"
    ["Allow fork syncing"]="no"
)

# Display order for comparison table
RULE_ORDER=(
    "Require pull request before merging"
    "Required approving reviews"
    "Dismiss stale reviews"
    "Require code owner reviews"
    "Require approval of most recent push"
    "Require status checks to pass"
    "Require branches to be up to date"
    "Enforce admins"
    "Require linear history"
    "Require conversation resolution"
    "Require signed commits"
    "Lock branch"
    "Allow force pushes"
    "Allow deletions"
    "Block creations"
    "Allow fork syncing"
)

# Parse existing protection into comparable values
parse_existing() {
    local json="$1"
    declare -gA CURRENT=()

    # Pull request reviews
    local has_pr_reviews
    has_pr_reviews=$(echo "$json" | jq -r '.required_pull_request_reviews // empty' 2>/dev/null)
    if [[ -n "$has_pr_reviews" ]]; then
        CURRENT["Require pull request before merging"]="yes"
        CURRENT["Required approving reviews"]=$(echo "$json" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
        CURRENT["Dismiss stale reviews"]=$(echo "$json" | jq -r 'if .required_pull_request_reviews.dismiss_stale_reviews then "yes" else "no" end')
        CURRENT["Require code owner reviews"]=$(echo "$json" | jq -r 'if .required_pull_request_reviews.require_code_owner_reviews then "yes" else "no" end')
        CURRENT["Require approval of most recent push"]=$(echo "$json" | jq -r 'if .required_pull_request_reviews.require_last_push_approval then "yes" else "no" end')
    else
        CURRENT["Require pull request before merging"]="no"
        CURRENT["Required approving reviews"]="0"
        CURRENT["Dismiss stale reviews"]="no"
        CURRENT["Require code owner reviews"]="no"
        CURRENT["Require approval of most recent push"]="no"
    fi

    # Status checks
    local has_status_checks
    has_status_checks=$(echo "$json" | jq -r '.required_status_checks // empty' 2>/dev/null)
    if [[ -n "$has_status_checks" ]]; then
        CURRENT["Require status checks to pass"]="yes"
        CURRENT["Require branches to be up to date"]=$(echo "$json" | jq -r 'if .required_status_checks.strict then "yes" else "no" end')
    else
        CURRENT["Require status checks to pass"]="no"
        CURRENT["Require branches to be up to date"]="no"
    fi

    # Boolean rules
    CURRENT["Enforce admins"]=$(echo "$json" | jq -r 'if .enforce_admins.enabled then "yes" else "no" end')
    CURRENT["Require linear history"]=$(echo "$json" | jq -r 'if .required_linear_history.enabled then "yes" else "no" end')
    CURRENT["Require conversation resolution"]=$(echo "$json" | jq -r 'if .required_conversation_resolution.enabled then "yes" else "no" end')
    CURRENT["Require signed commits"]=$(echo "$json" | jq -r 'if .required_signatures.enabled then "yes" else "no" end')
    CURRENT["Lock branch"]=$(echo "$json" | jq -r 'if .lock_branch.enabled then "yes" else "no" end')
    CURRENT["Allow force pushes"]=$(echo "$json" | jq -r 'if .allow_force_pushes.enabled then "yes" else "no" end')
    CURRENT["Allow deletions"]=$(echo "$json" | jq -r 'if .allow_deletions.enabled then "yes" else "no" end')
    CURRENT["Block creations"]=$(echo "$json" | jq -r 'if .block_creations.enabled then "yes" else "no" end')
    CURRENT["Allow fork syncing"]=$(echo "$json" | jq -r 'if .allow_fork_syncing.enabled then "yes" else "no" end')
}

print_comparison() {
    local has_additions=false
    local has_removals=false
    local has_changes=false

    echo ""
    printf "  %-40s %-12s %-12s\n" "Rule" "Current" "New"
    printf "  %-40s %-12s %-12s\n" "----" "-------" "---"

    for key in "${RULE_ORDER[@]}"; do
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

    # Helper: pick the more secure value between current and desired
    # For "yes is more secure" settings: yes if either is yes
    secure_yes() { [[ "${CURRENT[$1]}" == "yes" || "${DESIRED[$1]}" == "yes" ]] && echo "yes" || echo "no"; }
    # For "no is more secure" settings: no if either is no
    secure_no() { [[ "${CURRENT[$1]}" == "no" || "${DESIRED[$1]}" == "no" ]] && echo "no" || echo "yes"; }

    # Global array to track what was actually applied (for summary output)
    declare -gA APPLIED=()

    if [[ "$mode" == "merge" ]]; then
        # Merge: take the more secure value for each setting
        local review_count="${CURRENT["Required approving reviews"]}"
        if [[ "$review_count" -lt "${DESIRED["Required approving reviews"]}" ]]; then
            review_count="${DESIRED["Required approving reviews"]}"
        fi
        local dismiss_stale=$(secure_yes "Dismiss stale reviews")
        local code_owner=$(secure_yes "Require code owner reviews")
        local last_push=$(secure_yes "Require approval of most recent push")
        local status_checks=$(secure_yes "Require status checks to pass")
        local strict=$(secure_yes "Require branches to be up to date")
        local enforce_admins=$(secure_yes "Enforce admins")
        local linear_history=$(secure_yes "Require linear history")
        local conversation=$(secure_yes "Require conversation resolution")
        local signed_commits=$(secure_yes "Require signed commits")
        local lock_branch=$(secure_yes "Lock branch")
        local force_pushes=$(secure_no "Allow force pushes")
        local deletions=$(secure_no "Allow deletions")
        local block_creations=$(secure_yes "Block creations")
        local fork_syncing=$(secure_no "Allow fork syncing")
    else
        # Overwrite: apply desired settings as-is
        local review_count="${DESIRED["Required approving reviews"]}"
        local dismiss_stale="${DESIRED["Dismiss stale reviews"]}"
        local code_owner="${DESIRED["Require code owner reviews"]}"
        local last_push="${DESIRED["Require approval of most recent push"]}"
        local status_checks="${DESIRED["Require status checks to pass"]}"
        local strict="${DESIRED["Require branches to be up to date"]}"
        local enforce_admins="${DESIRED["Enforce admins"]}"
        local linear_history="${DESIRED["Require linear history"]}"
        local conversation="${DESIRED["Require conversation resolution"]}"
        local signed_commits="${DESIRED["Require signed commits"]}"
        local lock_branch="${DESIRED["Lock branch"]}"
        local force_pushes="${DESIRED["Allow force pushes"]}"
        local deletions="${DESIRED["Allow deletions"]}"
        local block_creations="${DESIRED["Block creations"]}"
        local fork_syncing="${DESIRED["Allow fork syncing"]}"
    fi

    # Store what we're actually applying
    APPLIED["Require pull request before merging"]="yes"
    APPLIED["Required approving reviews"]="$review_count"
    APPLIED["Dismiss stale reviews"]="$dismiss_stale"
    APPLIED["Require code owner reviews"]="$code_owner"
    APPLIED["Require approval of most recent push"]="$last_push"
    APPLIED["Require status checks to pass"]="$status_checks"
    APPLIED["Require branches to be up to date"]="$strict"
    APPLIED["Enforce admins"]="$enforce_admins"
    APPLIED["Require linear history"]="$linear_history"
    APPLIED["Require conversation resolution"]="$conversation"
    APPLIED["Require signed commits"]="$signed_commits"
    APPLIED["Lock branch"]="$lock_branch"
    APPLIED["Allow force pushes"]="$force_pushes"
    APPLIED["Allow deletions"]="$deletions"
    APPLIED["Block creations"]="$block_creations"
    APPLIED["Allow fork syncing"]="$fork_syncing"

    # Convert yes/no to true/false for JSON
    yn() { [[ "$1" == "yes" ]] && echo "true" || echo "false"; }

    # Build status checks payload
    local status_checks_json="null"
    if [[ "$status_checks" == "yes" ]]; then
        status_checks_json=$(cat <<SC_EOF
{
      "strict": $(yn "$strict"),
      "contexts": []
    }
SC_EOF
        )
    fi

    gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection" \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        --input - <<APPLY_EOF > /dev/null
{
  "required_pull_request_reviews": {
    "required_approving_review_count": ${review_count},
    "dismiss_stale_reviews": $(yn "$dismiss_stale"),
    "require_code_owner_reviews": $(yn "$code_owner"),
    "require_last_push_approval": $(yn "$last_push")
  },
  "required_status_checks": ${status_checks_json},
  "enforce_admins": $(yn "$enforce_admins"),
  "restrictions": null,
  "required_linear_history": $(yn "$linear_history"),
  "required_conversation_resolution": $(yn "$conversation"),
  "lock_branch": $(yn "$lock_branch"),
  "allow_force_pushes": $(yn "$force_pushes"),
  "allow_deletions": $(yn "$deletions"),
  "block_creations": $(yn "$block_creations"),
  "allow_fork_syncing": $(yn "$fork_syncing")
}
APPLY_EOF

    # Signed commits use a separate API endpoint
    if [[ "$signed_commits" == "yes" ]]; then
        gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection/required_signatures" \
            -X POST \
            -H "Accept: application/vnd.github+json" > /dev/null 2>&1 || true
    else
        gh api "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection/required_signatures" \
            -X DELETE \
            -H "Accept: application/vnd.github+json" > /dev/null 2>&1 || true
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
for key in "${RULE_ORDER[@]}"; do
    printf "  %-42s %s\n" "$key" "${APPLIED[$key]}"
done
