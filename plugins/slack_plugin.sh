#!/usr/bin/env bash

function notify_slack() {
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local slack_payload
        slack_payload=$(jq -n \
            --arg channel "$SLACK_CHANNEL" \
            --arg username "$SLACK_USERNAME" \
            --arg emoji "$SLACK_ICON_EMOJI" \
            --arg project_name "$project_name" \
            --arg branch_name "$safe_branch_name" \
            --arg email_user "$safe_email_user" \
            --arg commit_url "$commit_url" \
            --arg text "$common_message" \
            --arg ticket_url "$TICKET_URL" \
            '{
                "channel": $channel,
                "username": $username,
                "icon_emoji": $emoji,
                "text": $text,
                "blocks": [
                {
                    "type": "header",
                    "text": {
                    "type": "plain_text",
                    "text": "🎉 Nouveau push effectué !",
                    "emoji": true
                    }
                },
                {
                    "type": "section",
                    "fields": (
                    [
                        {
                        "type": "mrkdwn",
                        "text": "*Projet :*\n<\($commit_url)|\($project_name)>"
                        },
                        {
                        "type": "mrkdwn",
                        "text": "*Branche :*\n\($branch_name)"
                        },
                        {
                        "type": "mrkdwn",
                        "text": "*Auteur :*\n\($email_user)"
                        }
                    ]
                    | if $ticket_url == "" then
                        .
                        else
                        . + [
                            {
                            "type": "mrkdwn",
                            "text": "*Ticket :*\n<\($ticket_url)|Ticket>"
                            }
                        ]
                        end
                    )
                },
                {
                    "type": "divider"
                },
                {
                    "type": "section",
                    "text": {
                    "type": "mrkdwn",
                    "text": "Consultez le commit : <\($commit_url)|Voir le commit>"
                    }
                }
                ]
            }'
        )


        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : Notification Slack."
            echo "$slack_payload"
            log_action "INFO" "Simulation notif Slack."
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H 'Content-type: application/json' \
                --data "$slack_payload" \
                "$SLACK_WEBHOOK_URL")

            if [ "$response" != "200" ]; then
                echo_color "$RED" "Erreur notify Slack (HTTP $response)."
                log_action "ERROR" "Slack notif échouée HTTP $response"
            else
                echo_color "$GREEN" "Notification Slack envoyée."
                log_action "INFO" "Notif Slack OK."
            fi
        fi
    else
        log_action "INFO" "SLACK_WEBHOOK_URL non défini, pas de notif Slack."
    fi
}
