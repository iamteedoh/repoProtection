#!/usr/bin/env bash
#
# List GitHub repositories and manage GNU GPL v3 licenses.
#
# A subcommand (list or license) is required.
#
# Usage:
#   ./repoList.sh list [options]           List repositories
#   ./repoList.sh license [options]        Check/manage GPL-3.0 licenses
#
# list options:
#   --sort <method>      Sort by: latest (default), stars, name, visibility
#   --filter <type>      Filter: all (default), public, private
#   --limit <n>          Max repos to show (default: 100)
#
# license options:
#   --check | --add      --check: show license status (default)
#                        --add:   interactively add GPL-3.0 to repos missing it
#   --filter <type>      Filter: public (default), private, all
#
# Shared options:
#   --filter <type>      Accepted by both subcommands (defaults differ)
#
# Requirements: gh (GitHub CLI) and jq must be installed and gh authenticated.

set -euo pipefail

# --- Dependency checks (mirrors repoProtection.sh) ---

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

if ! command -v jq &>/dev/null; then
    echo "Error: jq is not installed."
    echo ""
    echo "Install it using one of the following:"
    echo "  macOS (Homebrew):    brew install jq"
    echo "  Fedora/RHEL (dnf):   sudo dnf install jq"
    echo "  Debian/Ubuntu (apt): sudo apt install jq"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "Error: GitHub CLI is not authenticated."
    echo "To get started, run: gh auth login"
    exit 1
fi

# --- Usage ---

usage() {
    cat <<EOF
Usage:
  $(basename "$0") <subcommand> [options]

Subcommands:
  list                 List repositories
  license              Check/manage GPL-3.0 licenses

list options:
  --sort <method>      Sort by: latest (default), stars, name, visibility
  --filter <type>      Filter: all (default), public, private
  --limit <n>          Max repos to show (default: 100)

license options:
  --check | --add      --check: show license status (default)
                       --add:   interactively add GPL-3.0 to repos missing it
                       (mutually exclusive — use one or the other)
  --filter <type>      Filter: public (default), private, all

Examples:
  $(basename "$0") list --sort stars --filter public
  $(basename "$0") license --check
  $(basename "$0") license --add --filter all
EOF
    exit 0
}

# --- Argument parsing ---

SUBCOMMAND=""
SORT_METHOD="latest"
FILTER_TYPE=""
LIMIT=100
LICENSE_ACTION="check"

parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    SUBCOMMAND="$1"
    shift

    case "$SUBCOMMAND" in
        list)
            FILTER_TYPE="all"
            ;;
        license)
            FILTER_TYPE="public"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "Error: Unknown subcommand '$SUBCOMMAND'"
            echo ""
            usage
            ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sort)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --sort requires a value (latest, stars, name, visibility)"
                    exit 1
                fi
                SORT_METHOD="$2"
                case "$SORT_METHOD" in
                    latest|stars|name|visibility) ;;
                    *)
                        echo "Error: Invalid sort method '$SORT_METHOD'. Use: latest, stars, name, visibility"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --filter)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --filter requires a value (all, public, private)"
                    exit 1
                fi
                FILTER_TYPE="$2"
                case "$FILTER_TYPE" in
                    all|public|private) ;;
                    *)
                        echo "Error: Invalid filter type '$FILTER_TYPE'. Use: all, public, private"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --limit)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --limit requires a number"
                    exit 1
                fi
                LIMIT="$2"
                if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -eq 0 ]]; then
                    echo "Error: --limit must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            --check)
                LICENSE_ACTION="check"
                shift
                ;;
            --add)
                LICENSE_ACTION="add"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Error: Unknown option '$1'"
                echo ""
                usage
                ;;
        esac
    done
}

# --- Core functions ---

get_owner() {
    gh api user --jq '.login'
}

fetch_repos() {
    local owner="$1"
    local visibility_flag=""

    if [[ "$FILTER_TYPE" == "public" ]]; then
        visibility_flag="--visibility public"
    elif [[ "$FILTER_TYPE" == "private" ]]; then
        visibility_flag="--visibility private"
    fi

    # shellcheck disable=SC2086
    gh repo list "$owner" \
        --json name,isPrivate,stargazerCount,updatedAt,licenseInfo,defaultBranchRef,isEmpty,isArchived,isFork \
        --limit "$LIMIT" \
        $visibility_flag
}

sort_repos() {
    local json="$1"
    local method="$2"

    case "$method" in
        latest)
            echo "$json" | jq 'sort_by(.updatedAt) | reverse'
            ;;
        stars)
            echo "$json" | jq 'sort_by(.stargazerCount) | reverse'
            ;;
        name)
            echo "$json" | jq 'sort_by(.name | ascii_downcase)'
            ;;
        visibility)
            echo "$json" | jq 'sort_by(.isPrivate)'
            ;;
    esac
}

print_repo_table() {
    local json="$1"
    local count
    count=$(echo "$json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "No repositories found."
        return
    fi

    echo ""
    printf "  %-4s %-30s %-12s %-7s %-16s %s\n" "#" "Name" "Visibility" "Stars" "License" "Updated"
    printf "  %-4s %-30s %-12s %-7s %-16s %s\n" "---" "------------------------------" "----------" "-----" "----------------" "----------"

    local i=0
    while IFS= read -r line; do
        i=$((i + 1))
        local name visibility stars license updated
        name=$(echo "$line" | jq -r '.name')
        if [[ $(echo "$line" | jq -r '.isPrivate') == "true" ]]; then
            visibility="private"
        else
            visibility="public"
        fi
        stars=$(echo "$line" | jq -r '.stargazerCount')
        license=$(echo "$line" | jq -r '.licenseInfo.key // "none"')
        updated=$(echo "$line" | jq -r '.updatedAt[:10]')

        # Truncate long names
        if [[ ${#name} -gt 28 ]]; then
            name="${name:0:25}..."
        fi

        printf "  %-4s %-30s %-12s %-7s %-16s %s\n" "$i" "$name" "$visibility" "$stars" "$license" "$updated"
    done < <(echo "$json" | jq -c '.[]')

    echo ""
    echo "  Total: $count repositories"
}

check_licenses() {
    local json="$1"
    local owner="$2"
    local count
    count=$(echo "$json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "No repositories found."
        return 1
    fi

    local gpl_repos other_repos no_license_repos
    gpl_repos=$(echo "$json" | jq '[.[] | select(.licenseInfo.key == "gpl-3.0")]')
    other_repos=$(echo "$json" | jq '[.[] | select(.licenseInfo.key != null and .licenseInfo.key != "gpl-3.0")]')
    no_license_repos=$(echo "$json" | jq '[.[] | select(.licenseInfo.key == null)]')

    local gpl_count other_count no_count
    gpl_count=$(echo "$gpl_repos" | jq 'length')
    other_count=$(echo "$other_repos" | jq 'length')
    no_count=$(echo "$no_license_repos" | jq 'length')

    echo ""
    echo "License summary for ${owner} (${FILTER_TYPE} repos):"
    echo ""
    printf "  %-12s %s\n" "GPL-3.0:" "$gpl_count"
    printf "  %-12s %s\n" "Other:" "$other_count"
    printf "  %-12s %s\n" "None:" "$no_count"
    printf "  %-12s %s\n" "Total:" "$count"

    if [[ "$other_count" -gt 0 ]]; then
        echo ""
        echo "Repos with non-GPL licenses:"
        echo ""
        printf "  %-4s %-30s %-16s %s\n" "#" "Name" "License" "Visibility"
        printf "  %-4s %-30s %-16s %s\n" "---" "------------------------------" "----------------" "----------"
        local i=0
        while IFS= read -r line; do
            i=$((i + 1))
            local name license visibility
            name=$(echo "$line" | jq -r '.name')
            license=$(echo "$line" | jq -r '.licenseInfo.key')
            if [[ $(echo "$line" | jq -r '.isPrivate') == "true" ]]; then
                visibility="private"
            else
                visibility="public"
            fi
            printf "  %-4s %-30s %-16s %s\n" "$i" "$name" "$license" "$visibility"
        done < <(echo "$other_repos" | jq -c '.[]')
    fi

    if [[ "$no_count" -gt 0 ]]; then
        echo ""
        echo "Repos with no license:"
        echo ""
        printf "  %-4s %-30s %-12s %s\n" "#" "Name" "Visibility" "Flags"
        printf "  %-4s %-30s %-12s %s\n" "---" "------------------------------" "----------" "-----"
        local i=0
        while IFS= read -r line; do
            i=$((i + 1))
            local name visibility flags=""
            name=$(echo "$line" | jq -r '.name')
            if [[ $(echo "$line" | jq -r '.isPrivate') == "true" ]]; then
                visibility="private"
            else
                visibility="public"
            fi
            [[ $(echo "$line" | jq -r '.isArchived') == "true" ]] && flags+="archived "
            [[ $(echo "$line" | jq -r '.isEmpty') == "true" ]] && flags+="empty "
            [[ $(echo "$line" | jq -r '.isFork') == "true" ]] && flags+="fork "
            printf "  %-4s %-30s %-12s %s\n" "$i" "$name" "$visibility" "$flags"
        done < <(echo "$no_license_repos" | jq -c '.[]')
    fi

    if [[ "$gpl_count" -eq "$count" ]]; then
        echo ""
        echo "All repos already have GPL-3.0. Nothing to do."
        return 1
    fi

    return 0
}

get_license_body() {
    gh api licenses/gpl-3.0 --jq '.body'
}

base64_encode() {
    if [[ "$(uname)" == "Darwin" ]]; then
        base64
    else
        base64 -w 0
    fi
}

add_license_to_repo() {
    local owner="$1"
    local repo_name="$2"
    local license_body_b64="$3"
    local full_repo="${owner}/${repo_name}"

    # Check if LICENSE file already exists
    local existing_sha=""
    local existing_response
    existing_response=$(gh api "repos/${full_repo}/contents/LICENSE" 2>/dev/null || true)

    if [[ -n "$existing_response" && "$existing_response" != *'"message"'* ]]; then
        existing_sha=$(echo "$existing_response" | jq -r '.sha')
    fi

    local payload
    if [[ -n "$existing_sha" ]]; then
        payload=$(jq -n \
            --arg message "Add GNU GPL v3 license" \
            --arg content "$license_body_b64" \
            --arg sha "$existing_sha" \
            '{message: $message, content: $content, sha: $sha}')
    else
        payload=$(jq -n \
            --arg message "Add GNU GPL v3 license" \
            --arg content "$license_body_b64" \
            '{message: $message, content: $content}')
    fi

    echo "$payload" | gh api "repos/${full_repo}/contents/LICENSE" \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        --input - > /dev/null
}

interactive_add_licenses() {
    local json="$1"
    local owner="$2"

    # Filter to repos that are candidates for license addition
    local candidates
    candidates=$(echo "$json" | jq '[.[] | select(.licenseInfo.key == null or .licenseInfo.key != "gpl-3.0") | select(.isArchived == false) | select(.isEmpty == false)]')
    local candidate_count
    candidate_count=$(echo "$candidates" | jq 'length')

    if [[ "$candidate_count" -eq 0 ]]; then
        echo ""
        echo "No eligible repos to add GPL-3.0 license to."
        echo "(Archived and empty repos are excluded.)"
        return
    fi

    echo ""
    echo "Eligible repos for GPL-3.0 license ($candidate_count):"
    echo ""

    local i=0
    while IFS= read -r line; do
        i=$((i + 1))
        local name current_license visibility flags=""
        name=$(echo "$line" | jq -r '.name')
        current_license=$(echo "$line" | jq -r '.licenseInfo.key // "none"')
        if [[ $(echo "$line" | jq -r '.isPrivate') == "true" ]]; then
            visibility="private"
        else
            visibility="public"
        fi
        [[ $(echo "$line" | jq -r '.isFork') == "true" ]] && flags+="fork "
        printf "  %2d. %-30s %-12s license: %s  %s\n" "$i" "$name" "$visibility" "$current_license" "$flags"
    done < <(echo "$candidates" | jq -c '.[]')

    echo ""
    echo "Options:"
    echo "  [a] Add GPL-3.0 to all listed repos"
    echo "  [s] Select individual repos"
    echo "  [q] Quit"
    echo ""
    read -rp "Choose [a/s/q]: " choice

    case "${choice,,}" in
        a)
            echo ""
            echo "Fetching GPL-3.0 license text..."
            local license_body license_b64
            license_body=$(get_license_body)
            license_b64=$(echo "$license_body" | base64_encode)

            while IFS= read -r line; do
                local name current_license
                name=$(echo "$line" | jq -r '.name')
                current_license=$(echo "$line" | jq -r '.licenseInfo.key // "none"')

                if [[ "$current_license" != "none" && "$current_license" != "gpl-3.0" ]]; then
                    echo ""
                    echo "  WARNING: $name currently has '$current_license' license."
                    read -rp "  Replace with GPL-3.0? [y/n]: " replace
                    if [[ "${replace,,}" != "y" ]]; then
                        echo "  Skipping $name."
                        continue
                    fi
                fi

                printf "  Adding GPL-3.0 to %s... " "$name"
                if add_license_to_repo "$owner" "$name" "$license_b64"; then
                    echo "done."
                else
                    echo "FAILED."
                fi
            done < <(echo "$candidates" | jq -c '.[]')
            ;;
        s)
            echo ""
            echo "Fetching GPL-3.0 license text..."
            local license_body license_b64
            license_body=$(get_license_body)
            license_b64=$(echo "$license_body" | base64_encode)

            local idx=0
            while IFS= read -r line; do
                idx=$((idx + 1))
                local name current_license
                name=$(echo "$line" | jq -r '.name')
                current_license=$(echo "$line" | jq -r '.licenseInfo.key // "none"')

                echo ""
                if [[ "$current_license" != "none" ]]; then
                    echo "  [$idx/$candidate_count] $name (current license: $current_license)"
                    read -rp "  Replace with GPL-3.0? [y/n]: " confirm
                else
                    echo "  [$idx/$candidate_count] $name (no license)"
                    read -rp "  Add GPL-3.0? [y/n]: " confirm
                fi

                if [[ "${confirm,,}" == "y" ]]; then
                    printf "  Adding GPL-3.0 to %s... " "$name"
                    if add_license_to_repo "$owner" "$name" "$license_b64"; then
                        echo "done."
                    else
                        echo "FAILED."
                    fi
                else
                    echo "  Skipping $name."
                fi
            done < <(echo "$candidates" | jq -c '.[]')
            ;;
        *)
            echo "Aborted."
            return
            ;;
    esac

    echo ""
    echo "Done."
}

# --- Main ---

parse_args "$@"

OWNER=$(get_owner)
echo "Authenticated as: $OWNER"

case "$SUBCOMMAND" in
    list)
        echo "Fetching repositories (filter: ${FILTER_TYPE}, sort: ${SORT_METHOD}, limit: ${LIMIT})..."
        REPOS=$(fetch_repos "$OWNER")
        SORTED=$(sort_repos "$REPOS" "$SORT_METHOD")
        print_repo_table "$SORTED"
        ;;
    license)
        echo "Fetching repositories (filter: ${FILTER_TYPE})..."
        REPOS=$(fetch_repos "$OWNER")
        SORTED=$(sort_repos "$REPOS" "name")

        if check_licenses "$SORTED" "$OWNER"; then
            if [[ "$LICENSE_ACTION" == "add" ]]; then
                interactive_add_licenses "$SORTED" "$OWNER"
            fi
        fi
        ;;
esac
