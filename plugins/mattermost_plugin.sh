#!/usr/bin/env bash

function notify_mattermost() {
    if [ -n "$MATTERMOST_WEBHOOK_URL" ]; then
        local mm_message; mm_message=$(get_string "mattermost_message" "$BRANCH_NAME" "$email_user" "$commit_hash" "$repo_url")

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "$(get_string "mattermost_sim")"
        else
            # Use jq to safely embed the message into a JSON payload
            local payload; payload=$(jq -n --arg text "$mm_message" '{text: $text}')
            curl -X POST -H 'Content-type: application/json' \
                 --data "$payload" \
                 "$MATTERMOST_WEBHOOK_URL" || {
                echo_color "$RED" "$(get_string "mattermost_error")"
                log_action "ERROR" "Mattermost fail."
            }
        fi
        log_action "INFO" "Notif Mattermost OK."
    else
        log_action "INFO" "MATTERMOST_WEBHOOK_URL non défini."
    fi
}
