#!/usr/bin/env bash

##############################################################################
# 4. Intégration avec un Système de Tickets
# On suppose que le message de commit peut contenir un ID de ticket (ex: JIRA-123)
# on va l’extraire et ajouter un lien dans Slack et dans le rapport.
###############################################################################
function link_tickets() {
    # Hypothèse : le message de commit est dans COMMIT_MSG
    # shellcheck disable=SC2031
    if [[ $COMMIT_MSG =~ ([A-Z]+-[0-9]+) ]]; then
        local ticket_id="${BASH_REMATCH[1]}"

        # Si TICKET_BASE_URL n'est pas défini, on ne peut pas construire d'URL
        if [ -z "$TICKET_BASE_URL" ]; then
            echo_color "$YELLOW" "$(get_string "jira_no_base_url")"
            log_action "WARN" "TICKET_BASE_URL manquant: l'ID $ticket_id ne sera pas lié."
        else
            # Concatène l'URL de base avec l'ID du ticket
            local ticket_url="${TICKET_BASE_URL}${ticket_id}"
            log_action "INFO" "Ticket détecté : $ticket_id"

            # On enregistre ce ticket pour utilisation ultérieure (Slack, e-mail, etc.)
            export TICKET_URL="$ticket_url"
        fi
    fi
}
