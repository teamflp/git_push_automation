#!/usr/bin/env bash

##############################################################################
# 2. Support des Sous-modules
# Fonction avancée : On va non seulement initialiser les sous-modules, mais aussi proposer de les synchroniser,
# de les mettre à jour sur la dernière version, et d’afficher leur statut.
###############################################################################
function handle_submodules() {
    echo_color "$BLUE" "Gestion des sous-modules"
    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git submodule update --init --recursive"
    else
        git submodule update --init --recursive
    fi

    # Afficher le statut des sous-modules
    echo_color "$BLUE" "Statut des sous-modules :"
    git submodule status

    # Proposer de synchroniser (en cas de changement d’URL)
    echo_color "$YELLOW" "Voulez-vous synchroniser les sous-modules ? (y/n)"
    read -r SYNC_ANSWER
    if [ "$SYNC_ANSWER" == "y" ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git submodule sync"
        else
            git submodule sync
        fi
    fi

    # Proposer de mettre à jour tous les sous-modules à la dernière version de la branche distante
    echo_color "$YELLOW" "Mettre à jour les sous-modules sur la dernière version distante ? (y/n)"
    read -r UPDATE_ANSWER
    if [ "$UPDATE_ANSWER" == "y" ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git submodule update --remote --merge"
        else
            git submodule update --remote --merge
        fi
    fi

    log_action "INFO" "Sous-modules gérés."
}
