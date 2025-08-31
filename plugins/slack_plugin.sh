#!/usr/bin/env bash

function notify_slack() {
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        # Get translated strings
        local s_header; s_header=$(get_string "slack_push_header")
        local s_project; s_project=$(get_string "slack_project_field" "$commit_url" "$project_name")
        local s_branch; s_branch=$(get_string "slack_branch_field" "$safe_branch_name")
        local s_author; s_author=$(get_string "slack_author_field" "$safe_email_user")
        local s_ticket; s_ticket=$(get_string "slack_ticket_field" "$TICKET_URL")
        local s_view_commit_btn; s_view_commit_btn=$(get_string "slack_view_commit_button")
        local s_view_commit_text; s_view_commit_text=$(get_string "slack_view_commit_text" "$commit_url" "$s_view_commit_btn")

        local slack_payload
        slack_payload=$(jq -n \
            --arg channel "$SLACK_CHANNEL" \
            --arg username "$SLACK_USERNAME" \
            --arg emoji "$SLACK_ICON_EMOJI" \
            --arg text "$common_message" \
            --arg header_text "$s_header" \
            --arg project_text "$s_project" \
            --arg branch_text "$s_branch" \
            --arg author_text "$s_author" \
            --arg ticket_text "$s_ticket" \
            --arg view_commit_text "$s_view_commit_text" \
            --arg ticket_url "$TICKET_URL" \
            '{
                "channel": $channel,
                "username": $username,
                "icon_emoji": $emoji,
                "text": $text,
                "blocks": [
                {
                    "type": "header",
                    "text": { "type": "plain_text", "text": $header_text, "emoji": true }
                },
                {
                    "type": "section",
                    "fields": (
                    [
                        { "type": "mrkdwn", "text": $project_text },
                        { "type": "mrkdwn", "text": $branch_text },
                        { "type": "mrkdwn", "text": $author_text }
                    ]
                    | if $ticket_url == "" then . else . + [ { "type": "mrkdwn", "text": $ticket_text } ] end
                    )
                },
                { "type": "divider" },
                {
                    "type": "section",
                    "text": { "type": "mrkdwn", "text": $view_commit_text }
                }
                ]
            }'
        )

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "$(get_string "slack_simulation")"
            echo "$slack_payload"
            log_action "INFO" "Simulation notif Slack."
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H 'Content-type: application/json' \
                --data "$slack_payload" \
                "$SLACK_WEBHOOK_URL")

            if [ "$response" != "200" ]; then
                echo_color "$RED" "$(get_string "slack_error" "$response")"
                log_action "ERROR" "Slack notif échouée HTTP $response"
            else
                echo_color "$GREEN" "$(get_string "slack_success")"
                log_action "INFO" "Notif Slack OK."
            fi
        fi
    else
        log_action "INFO" "SLACK_WEBHOOK_URL non défini, pas de notif Slack."
    fi
}
