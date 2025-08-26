#!/usr/bin/env bash

# BITBUCKET
function notify_bitbucket() {
    local message="$1"
    local commit_hash="$2"

    # Vérifications de variables
    if [ -z "$BITBUCKET_WORKSPACE" ] || [ -z "$BITBUCKET_REPO_SLUG" ] || [ -z "$BITBUCKET_USER" ] || [ -z "$BITBUCKET_APP_PASSWORD" ]; then
        log_action "WARN" "Variables Bitbucket manquantes (BITBUCKET_WORKSPACE, BITBUCKET_REPO_SLUG, BITBUCKET_USER, BITBUCKET_APP_PASSWORD)."
        return
    fi

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "$(get_string "bitbucket_notif_sim" "$commit_hash")"
        echo "Message : $message"
        return
    fi

    # Endpoint pour commenter un commit sur Bitbucket Cloud:
    # POST /2.0/repositories/{workspace}/{repo_slug}/commit/{node}/comments
    local bitbucket_api_url="https://api.bitbucket.org/2.0/repositories/$BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG/commit/$commit_hash/comments"

    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        --user "$BITBUCKET_USER:$BITBUCKET_APP_PASSWORD" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"content\":{\"raw\":\"$message\"}}" \
        "$bitbucket_api_url")

    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    # shellcheck disable=SC2001
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -eq 201 ]; then
        echo_color "$GREEN" "$(get_string "bitbucket_notif_success")"
        log_action "INFO" "Notification Bitbucket OK"
    else
        echo_color "$RED" "$(get_string "bitbucket_notif_error" "$http_status")"
        echo_color "$RED" "Réponse : $body"
        log_action "ERROR" "Bitbucket notif fail $http_status $body"
    fi
}

function create_bitbucket_release() {
    local tag_name="$1"
    local description="$2"

    # Vérifications
    if [ -z "$BITBUCKET_WORKSPACE" ] || [ -z "$BITBUCKET_REPO_SLUG" ] || [ -z "$BITBUCKET_USER" ] || [ -z "$BITBUCKET_APP_PASSWORD" ]; then
        log_action "WARN" "Variables Bitbucket manquantes, pas de release."
        return
    fi

    # Pour créer un tag "annoté", on a besoin du commit hash cible.
    # On prend le HEAD actuel comme cible du tag.
    local commit_hash
    commit_hash=$(git rev-parse HEAD)

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "$(get_string "bitbucket_release_sim" "$tag_name")"
        echo "Description : $description"
        return
    fi

    # Endpoint pour créer un tag sur Bitbucket Cloud:
    # POST /2.0/repositories/{workspace}/{repo_slug}/refs/tags
    # Exemple de payload :
    # {
    #  "name": "v1.0.0",
    #   "target": {
    #       "hash": "commit_hash"
    #   },
    #   "message": "Description de la release"
    # }

    local bitbucket_api_url="https://api.bitbucket.org/2.0/repositories/$BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG/refs/tags"

    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        --user "$BITBUCKET_USER:$BITBUCKET_APP_PASSWORD" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "$(jq -n --arg tag "$tag_name" --arg desc "$description" --arg hash "$commit_hash" '{ name: $tag, target: {hash: $hash}, message: $desc }')" \
        "$bitbucket_api_url")

    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    # shellcheck disable=SC2001
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -eq 201 ]; then
        echo_color "$GREEN" "$(get_string "bitbucket_release_success" "$tag_name")"
        log_action "INFO" "Bitbucket tag/release OK"
    else
        echo_color "$RED" "$(get_string "bitbucket_release_error" "$http_status")"
        echo_color "$RED" "Réponse : $body"
        log_action "ERROR" "Bitbucket release fail $http_status $body"
    fi
}
