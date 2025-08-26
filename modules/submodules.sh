#!/usr/bin/env bash

##############################################################################
# 2. Support des Sous-modules
# Fonction avancée : On va non seulement initialiser les sous-modules, mais aussi proposer de les synchroniser,
# de les mettre à jour sur la dernière version, et d’afficher leur statut.
###############################################################################
function handle_submodules() {
    echo_color "$BLUE" "$(get_string "submodules_title")"
    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "$(get_string "submodules_simulation_update")"
    else
        git submodule update --init --recursive
    fi

    # Afficher le statut des sous-modules
    echo_color "$BLUE" "$(get_string "submodules_status_title")"
    git submodule status

    # Proposer de synchroniser (en cas de changement d’URL)
    echo_color "$YELLOW" "$(get_string "submodules_sync_prompt" "$(get_string 'prompt_yes_no')")"
    read -r SYNC_ANSWER
    if [ "$SYNC_ANSWER" == "y" ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "$(get_string "submodules_simulation_sync")"
        else
            git submodule sync
        fi
    fi

    # Proposer de mettre à jour tous les sous-modules à la dernière version de la branche distante
    echo_color "$YELLOW" "$(get_string "submodules_update_remote_prompt" "$(get_string 'prompt_yes_no')")"
    read -r UPDATE_ANSWER
    if [ "$UPDATE_ANSWER" == "y" ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "$(get_string "submodules_simulation_update_remote")"
        else
            git submodule update --remote --merge
        fi
    fi

    log_action "INFO" "Sous-modules gérés."
}
