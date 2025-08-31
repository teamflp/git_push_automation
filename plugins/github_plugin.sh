#!/usr/bin/env bash

# Créer une PR via l’API après le push. On peut utiliser gh cli (GitHub CLI) ou un curl.
function create_github_pr() {
    if [ "$CREATE_PR" != "y" ]; then
        return
    fi
    if [ "$PLATFORM" != "github" ]; then
        echo_color "$RED" "$(get_string "github_pr_not_github_platform")"
        return
    fi

    echo_color "$BLUE" "$(get_string "github_pr_title")"
    local base_branch="main"  # ou la branch par défaut
    if [ -n "$MAIN_BRANCH" ]; then
        base_branch="$MAIN_BRANCH"
    fi

    if ! command -v gh &>/dev/null; then
        echo_color "$RED" "$(get_string "github_pr_gh_missing")"
        return
    fi

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "$(get_string "github_pr_sim" "$base_branch" "$BRANCH_NAME")"
    else
        gh pr create --base "$base_branch" --head "$BRANCH_NAME" --title "PR depuis script" --body "Auto-created PR via git_push_automation.sh"
    fi
}
