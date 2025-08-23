#!/usr/bin/env bash

function notify_mattermost() {
    if [ -n "$MATTERMOST_WEBHOOK_URL" ]; then
        local mm_message="**Nouveau push** sur *$BRANCH_NAME* par $email_user.
Commit: \`$commit_hash\`.
[Voir le commit sur le remote](${repo_url})"

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : Notification Mattermost."
        else
            curl -X POST -H 'Content-type: application/json' \
                 --data "{\"text\":\"$mm_message\"}" \
                 "$MATTERMOST_WEBHOOK_URL" || {
                echo_color "$RED" "Erreur notif Mattermost."
                log_action "ERROR" "Mattermost fail."
            }
        fi
        log_action "INFO" "Notif Mattermost OK."
    else
        log_action "INFO" "MATTERMOST_WEBHOOK_URL non défini."
    fi
}
