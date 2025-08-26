#!/usr/bin/env bash

###############################################################################
# 1. Gestion des Hooks Git
# Cette fonction va lister les hooks disponibles, proposer d’en installer certains (pre-commit, pre-push)
# et, par exemple, ajouter un pre-commit hook qui lance un linter et des tests s’ils sont définis.
###############################################################################
function manage_hooks() {
    echo_color "$BLUE" "$(get_string "hooks_title")"

    # Get translated strings for the menu and hook content
    local item_pre_commit; item_pre_commit=$(get_string "hooks_item_pre_commit")
    local item_pre_push; item_pre_push=$(get_string "hooks_item_pre_push")
    local item_quit; item_quit=$(get_string "hooks_item_quit")

    local hook_pre_commit_checking_code; hook_pre_commit_checking_code=$(get_string "hook_pre_commit_checking_code")
    local hook_pre_commit_running_lint; hook_pre_commit_running_lint=$(get_string "hook_pre_commit_running_lint")
    local hook_pre_commit_lint_failed; hook_pre_commit_lint_failed=$(get_string "hook_pre_commit_lint_failed")
    # Note: We pass the literal string "$TEST_COMMAND" to get_string, which will be part of the generated script
    local hook_pre_commit_running_tests; hook_pre_commit_running_tests=$(get_string "hook_pre_commit_running_tests" "\$TEST_COMMAND")
    local hook_pre_commit_tests_failed; hook_pre_commit_tests_failed=$(get_string "hook_pre_commit_tests_failed")

    local hook_pre_push_sending_notif; hook_pre_push_sending_notif=$(get_string "hook_pre_push_sending_notif")
    local hook_pre_push_preparing; hook_pre_push_preparing=$(get_string "hook_pre_push_preparing")

    # Menu items
    local hooks=("$item_pre_commit" "$item_pre_push" "$item_quit")
    PS3="$(get_string "hooks_prompt")"

    select hk in "${hooks[@]}"; do
        case $hk in
            "$item_pre_commit")
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "$(get_string "hooks_simulation_install_pre_commit")"
                else
                    # Use variables in the heredoc to insert translated strings
                    cat > .git/hooks/pre-commit <<EOF
#!/usr/bin/env bash
echo "$hook_pre_commit_checking_code"
# Lancer lint
if command -v npm &>/dev/null && [ -f package.json ]; then
    echo "$hook_pre_commit_running_lint"
    npm run lint
    if [ \$? -ne 0 ]; then
        echo "$hook_pre_commit_lint_failed"
        exit 1
    fi
fi

# Lancer tests
if [ -n "\$TEST_COMMAND" ]; then
    echo "$hook_pre_commit_running_tests"
    \$TEST_COMMAND || { echo "$hook_pre_commit_tests_failed"; exit 1; }
fi

exit 0
EOF
                    chmod +x .git/hooks/pre-commit
                    echo_color "$GREEN" "$(get_string "hooks_install_success_pre_commit")"
                fi
                log_action "INFO" "Hook pre-commit géré."
                break
                ;;
            "$item_pre_push")
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "$(get_string "hooks_simulation_install_pre_push")"
                else
                    cat > .git/hooks/pre-push <<EOF
#!/usr/bin/env bash
echo "$hook_pre_push_sending_notif"
if [ -n "\$SLACK_WEBHOOK_URL" ]; then
    curl -X POST -H 'Content-type: application/json' --data '{"text":"$hook_pre_push_preparing"}' "\$SLACK_WEBHOOK_URL"
fi
exit 0
EOF
                    chmod +x .git/hooks/pre-push
                    echo_color "$GREEN" "$(get_string "hooks_install_success_pre_push")"
                fi
                log_action "INFO" "Hook pre-push géré."
                break
                ;;
            "$item_quit")
                break
                ;;
            *)
                echo_color "$RED" "$(get_string "hooks_invalid_choice")"
                ;;
        esac
    done
}
