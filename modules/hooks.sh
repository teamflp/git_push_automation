#!/usr/bin/env bash

###############################################################################
# 1. Gestion des Hooks Git
# Cette fonction va lister les hooks disponibles, proposer d’en installer certains (pre-commit, pre-push)
# et, par exemple, ajouter un pre-commit hook qui lance un linter et des tests s’ils sont définis.
###############################################################################
function manage_hooks() {
    echo_color "$BLUE" "Gestion des hooks Git"
    # Liste des hooks possibles
    local hooks=("pre-commit: Lancer lint et tests" "pre-push: Envoyer notif Slack supplémentaire" "Quitter")
    PS3="Choisissez un hook à gérer : "
    select hk in "${hooks[@]}"; do
        case $hk in
            "pre-commit: Lancer lint et tests")
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "Simulation : Installation d'un hook pre-commit"
                else
                    cat > .git/hooks/pre-commit <<EOF
#!/usr/bin/env bash
echo "Hook pre-commit: Vérification du code..."
# Lancer lint
if command -v npm &>/dev/null && [ -f package.json ]; then
    echo "Lancement du lint (npm run lint)"
    npm run lint
    if [ \$? -ne 0 ]; then
        echo "Lint échoué, annulation du commit."
        exit 1
    fi
fi

# Lancer tests
if [ -n "\$TEST_COMMAND" ]; then
    echo "Lancement des tests via \$TEST_COMMAND"
    \$TEST_COMMAND || { echo "Tests échoués, annulation du commit."; exit 1; }
fi

exit 0
EOF
                    chmod +x .git/hooks/pre-commit
                    echo_color "$GREEN" "Hook pre-commit installé."
                fi
                log_action "INFO" "Hook pre-commit géré."
                break
                ;;
            "pre-push: Envoyer notif Slack supplémentaire")
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "Simulation : Installation d'un hook pre-push"
                else
                    cat > .git/hooks/pre-push <<EOF
#!/usr/bin/env bash
echo "Hook pre-push: Envoi d'une notification Slack avant le push..."
if [ -n "\$SLACK_WEBHOOK_URL" ]; then
    curl -X POST -H 'Content-type: application/json' --data '{"text":"Préparation du push..."}' "\$SLACK_WEBHOOK_URL"
fi
exit 0
EOF
                    chmod +x .git/hooks/pre-push
                    echo_color "$GREEN" "Hook pre-push installé."
                fi
                log_action "INFO" "Hook pre-push géré."
                break
                ;;
            "Quitter")
                break
                ;;
            *)
                echo_color "$RED" "Choix invalide."
                ;;
        esac
    done
}
