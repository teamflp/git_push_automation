#!/usr/bin/env bash

# Créer une PR via l’API après le push. On peut utiliser gh cli (GitHub CLI) ou un curl.
function create_github_pr() {
    if [ "$CREATE_PR" != "y" ]; then
        return
    fi
    if [ "$PLATFORM" != "github" ]; then
        echo_color "$RED" "PLATFORM != github, impossible de créer PR."
        return
    fi

    echo_color "$BLUE" "=== Création Pull Request GitHub ==="
    local base_branch="main"  # ou la branch par défaut
    if [ -n "$MAIN_BRANCH" ]; then
        base_branch="$MAIN_BRANCH"
    fi

    if ! command -v gh &>/dev/null; then
        echo_color "$RED" "L'outil GitHub CLI (gh) n'est pas installé."
        return
    fi

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : gh pr create --base $base_branch --head $BRANCH_NAME --title 'PR depuis script' --body 'Auto-created PR'"
    else
        gh pr create --base "$base_branch" --head "$BRANCH_NAME" --title "PR depuis script" --body "Auto-created PR via git_push_automation.sh"
    fi
}
