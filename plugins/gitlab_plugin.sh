#!/usr/bin/env bash

# Créer une Merge Request sur GitLab
function create_gitlab_mr() {
    if [ "$CREATE_MR" != "y" ]; then
        return
    fi
    if [ "$PLATFORM" != "gitlab" ]; then
        echo_color "$RED" "$(get_string "gitlab_mr_not_gitlab_platform")"
        return
    fi

    echo_color "$BLUE" "$(get_string "gitlab_mr_title")"
    if [ -z "$GITLAB_PROJECT_ID" ] || [ -z "$GITLAB_TOKEN" ]; then
        echo_color "$RED" "$(get_string "gitlab_mr_missing_vars")"
        return
    fi

    # On suppose qu'on veut merger la branche $BRANCH_NAME dans 'main'
    local base_branch="main"
    local mr_title; mr_title=$(get_string "gitlab_mr_default_title")
    local mr_description; mr_description=$(get_string "gitlab_mr_default_desc")

    local payload
    payload=$(jq -n \
        --arg src "$BRANCH_NAME" \
        --arg tgt "$base_branch" \
        --arg title "$mr_title" \
        --arg desc "$mr_description" \
        '{
            "source_branch": $src,
            "target_branch": $tgt,
            "title": $title,
            "description": $desc,
            "remove_source_branch": false
        }'
    )

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "$(get_string "gitlab_mr_sim")"
        echo "$payload"
    else
        response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
            --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --header "Content-Type: application/json" \
            --data "$payload" \
            "https://gitlab.com/api/v4/projects/$GITLAB_PROJECT_ID/merge_requests")

        http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
        # shellcheck disable=SC2001
        body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')
        if [ "$http_status" -ne 201 ]; then
            echo_color "$RED" "$(get_string "gitlab_mr_error" "$http_status")"
            echo_color "$RED" "Réponse : $body"
        else
            echo_color "$GREEN" "$(get_string "gitlab_mr_success")"
        fi
    fi
}

# GITLAB
function notify_gitlab() {
    local message="$1"
    local commit_hash="$2"
    local gitlab_api_url="https://gitlab.com/api/v4"

    local encoded_message
    encoded_message=$(jq -Rn --arg msg "$message" '$msg')

    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"note\": $encoded_message}" \
        "$gitlab_api_url/projects/$GITLAB_PROJECT_ID/repository/commits/$commit_hash/comments")

    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    # shellcheck disable=SC2001
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -ne 201 ]; then
        echo_color "$RED" "$(get_string "gitlab_notif_error" "$http_status")"
        echo_color "$RED" "Réponse: $body"
        log_action "ERROR" "GitLab notif fail $http_status $body"
    else
        echo_color "$GREEN" "$(get_string "gitlab_notif_success")"
        log_action "INFO" "Notif GitLab OK"
    fi
}

function create_gitlab_release() {
    local tag_name="$1"
    local description="$2"
    local gitlab_api_url="https://gitlab.com/api/v4"
    # shellcheck disable=SC2155
    local release_name="Release $(date '+%Y-%m-%d %H:%M:%S')"

    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$(jq -n --arg tag "$tag_name" --arg name "$release_name" --arg desc "$description" '{ tag_name: $tag, name: $name, description: $desc }')" \
        "$gitlab_api_url/projects/$GITLAB_PROJECT_ID/releases")

    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    # shellcheck disable=SC2001
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -eq 201 ]; then
        echo_color "$GREEN" "$(get_string "gitlab_release_success")"
        log_action "INFO" "Release GitLab OK"
    else
        echo_color "$RED" "$(get_string "gitlab_release_error" "$http_status")"
        echo_color "$RED" "Réponse: $body"
        log_action "ERROR" "GitLab release fail $http_status $body"
    fi
}
