#!/usr/bin/env bash

###############################################################################
# NOTIFICATIONS ET RAPPORTS
###############################################################################
function set_email_recipients() {
    # Vérifier si EMAIL_RECIPIENTS est déjà défini
    if [ -n "$EMAIL_RECIPIENTS" ]; then
        echo_color "$GREEN" "Les destinataires e-mail actuels : $EMAIL_RECIPIENTS"
        return
    fi

    # Si non défini, demander à l'utilisateur
    echo_color "$YELLOW" "Aucun destinataire e-mail n'est défini. Voulez-vous en saisir maintenant ? (y/n)"
    read -r ANSWER
    if [ "$ANSWER" == "y" ]; then
        echo_color "$YELLOW" "Entrez les adresses e-mail séparées par des virgules (ex: user1@example.com,user2@example.com) :"
        read -r USER_EMAILS

        # Vérification simple (optionnelle) : s’assurer que la variable n’est pas vide
        if [ -z "$USER_EMAILS" ]; then
            echo_color "$RED" "Aucune adresse fournie, les e-mails ne seront pas envoyés."
            log_action "WARN" "Aucune adresse e-mail saisie."
            return
        fi

        # Assigner les destinataires à EMAIL_RECIPIENTS
        EMAIL_RECIPIENTS="$USER_EMAILS"
        export EMAIL_RECIPIENTS
        echo_color "$GREEN" "Destinataires définis : $EMAIL_RECIPIENTS"
        log_action "INFO" "EMAIL_RECIPIENTS défini à partir de l'entrée utilisateur."
    else
        echo_color "$YELLOW" "Aucune adresse e-mail définie. Les notifications par e-mail ne seront pas envoyées."
        log_action "INFO" "Aucune adresse e-mail définie, pas d'envoi d'e-mail."
    fi
}

# Envoie de notification via SendGrid
function send_email_via_sendgrid() {
  local to="$1"      # Adresse destinataire
  local subject="$2"
  local content="$3"

  # Variables d'environnement attendues
  local sg_api_key="$SENDGRID_API_KEY"
  local sg_from="$SENDGRID_FROM"

  # Construction du JSON pour l'API SendGrid
  local payload
  payload=$(jq -n \
    --arg from "$sg_from" \
    --arg to "$to" \
    --arg subj "$subject" \
    --arg body "$content" \
    '{
      "personalizations": [{
        "to": [{"email": $to}],
        "subject": $subj
      }],
      "from": {"email": $from},
      "content": [{
        "type": "text/plain",
        "value": $body
      }]
    }'
  )

  # Appel API SendGrid
  response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
    --request POST \
    --url "https://api.sendgrid.com/v3/mail/send" \
    --header "Authorization: Bearer $sg_api_key" \
    --header "Content-Type: application/json" \
    --data "$payload")

  http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  # shellcheck disable=SC2001
  body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

  if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
    echo "E-mail envoyé via SendGrid à $to (HTTP $http_status)."
  else
    echo "Erreur envoi SendGrid (HTTP $http_status): $body"
  fi
}

# Envoie de notification via Mailgun
# Cette fonction utilise l'API Mailgun pour envoyer un e-mail.
function send_email_via_mailgun() {
  local to="$1"
  local subject="$2"
  local content="$3"

  # Variables d'environnement attendues
  local mg_api_key="$MAILGUN_API_KEY"
  local mg_domain="$MAILGUN_DOMAIN"
  local mg_from="$MAILGUN_FROM"

  # Mailgun attend un POST vers l'API, ex:
  # https://api.mailgun.net/v3/votre-domaine.com/messages
  # Avec form-data: from, to, subject, text...

  response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
    -X POST "https://api.mailgun.net/v3/$mg_domain/messages" \
    -u "api:$mg_api_key" \
    -F from="$mg_from" \
    -F to="$to" \
    -F subject="$subject" \
    -F text="$content")

  http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  # shellcheck disable=SC2001
  body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

  if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
    echo "E-mail envoyé via Mailgun à $to (HTTP $http_status)."
  else
    echo "Erreur envoi Mailgun (HTTP $http_status): $body"
  fi
}

# Envoie de notification via Mailjet
# Cette fonction utilise l'API Mailjet pour envoyer un e-mail.
function send_email_via_mailjet() {
  local to="$1"
  local subject="$2"
  local content="$3"

  # Variables d'environnement attendues
  local mj_api_key="$MAILJET_API_KEY"
  local mj_secret_key="$MAILJET_SECRET_KEY"
  local mj_from="$MAILJET_FROM"

  # Construction du JSON pour Mailjet
  local payload
  payload=$(jq -n \
    --arg from "$mj_from" \
    --arg to "$to" \
    --arg subj "$subject" \
    --arg body "$content" \
    '{
      "Messages": [
        {
          "From": {"Email": $from},
          "To": [{"Email": $to}],
          "Subject": $subj,
          "TextPart": $body
        }
      ]
    }'
  )

  # Appel API Mailjet
  response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
    --request POST \
    --url "https://api.mailjet.com/v3.1/send" \
    --header "Content-Type: application/json" \
    --user "$mj_api_key:$mj_secret_key" \
    --data "$payload")

  http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  # shellcheck disable=SC2001
  body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

  if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
    echo "E-mail envoyé via Mailjet à $to (HTTP $http_status)."
  else
    echo "Erreur envoi Mailjet (HTTP $http_status): $body"
  fi
}

function send_notification() {
    local email_user
    email_user=$(git config --get user.email)
    local commit_hash
    commit_hash=$(git rev-parse HEAD)
    local repo_url
    repo_url=$(git config --get remote.origin.url)

    # Déterminer l'URL web du dépôt
    local web_repo_url
    if [[ $repo_url == git@* ]]; then
        local host
        local path
        host=$(echo "$repo_url" | awk -F'@|:' '{print $2}')
        path=$(echo "$repo_url" | awk -F':' '{print $2}' | sed 's/\.git$//')
        web_repo_url="https://$host/$path"
    elif [[ $repo_url == *:* && $repo_url != *//*:* ]]; then
        local host
        local path
        host=$(echo "$repo_url" | awk -F':' '{print $1}')
        path=$(echo "$repo_url" | awk -F':' '{print $2}' | sed 's/\.git$//')
        web_repo_url="https://$host/$path"
    elif [[ $repo_url == https://* ]]; then
        web_repo_url=${repo_url%.git}
    else
        echo_color "$RED" "Format d'URL non supporté : $repo_url"
        log_action "ERROR" "URL non supportée: $repo_url"
        return
    fi

    local project_name
    project_name=$(basename "$web_repo_url")
    local commit_url="${web_repo_url}/commit/${commit_hash}"

    # Variables de secours si BRANCH_NAME ou email_user sont vides
    local safe_branch_name="${BRANCH_NAME:-(branche inconnue)}"
    local safe_email_user="${email_user:-(auteur inconnu)}"

    # Message Markdown commun
    local common_message="** 🎉 Nouveau push effectué !**
- **Projet :** $project_name
- **Branche :** $BRANCH_NAME
- **Auteur :** $email_user

[Voir le commit]($commit_url)"

    #### Notification Slack ####
    notify_slack

    #### Notification GitLab ####
    if [ -n "$GITLAB_PROJECT_ID" ] && [ -n "$GITLAB_TOKEN" ]; then
        notify_gitlab "$common_message" "$commit_hash"
    else
        log_action "INFO" "GITLAB_PROJECT_ID ou GITLAB_TOKEN non défini, pas de notif GitLab."
    fi

    #### Notification Email ####
    if [ -n "$EMAIL_RECIPIENTS" ]; then
        check_mailer
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo_color "$YELLOW" "Pas de mailer, pas d'e-mail."
            log_action "WARN" "No mailer"
        else
            local subject="[GIT PUSH] Nouveau push sur la branche $BRANCH_NAME"
            local email_body="Bonjour l'équipe,

Un nouveau push a été effectué sur la branche '$BRANCH_NAME'.

- Auteur : $email_user
- Projet : $project_name
- Commit : $commit_hash

Voir le commit : $commit_url

Cordialement,
Votre script Git"

            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : Envoi e-mail via $EMAIL_PROVIDER à $EMAIL_RECIPIENTS"
                echo_color "$GREEN" "Sujet : $subject"
                echo "$email_body"
            else
                if [ -z "$EMAIL_PROVIDER" ]; then
                    echo_color "$RED" "Erreur : Pas de EMAIL_PROVIDER défini (sendgrid, mailgun, mailjet...)."
                    log_action "ERROR" "Aucun EMAIL_PROVIDER défini."
                else
                    # Selon la valeur de $EMAIL_PROVIDER, on appelle la bonne fonction
                    case "$EMAIL_PROVIDER" in
                        "sendgrid")
                            send_email_via_sendgrid "$EMAIL_RECIPIENTS" "$subject" "$email_body"
                            ;;
                        "mailgun")
                            send_email_via_mailgun "$EMAIL_RECIPIENTS" "$subject" "$email_body"
                            ;;
                        "mailjet")
                            send_email_via_mailjet "$EMAIL_RECIPIENTS" "$subject" "$email_body"
                            ;;
                        *)
                            echo_color "$RED" "EMAIL_PROVIDER inconnu : $EMAIL_PROVIDER"
                            log_action "ERROR" "EMAIL_PROVIDER inconnu : $EMAIL_PROVIDER"
                            ;;
                    esac
                fi
            fi
        fi
    else
        log_action "INFO" "EMAIL_RECIPIENTS non défini, pas d'e-mail."
    fi

    #### Notification Mattermost ####
    notify_mattermost

    echo ""
    echo_color "$GREEN" "------------- FIN DU RAPPORT -------------"
}

function send_custom_webhook() {
    # shellcheck disable=SC2155
    local email="$(git config --get user.email)"

    #### 1) Webhook Slack ####
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local slack_payload="{\"message\": \"Nouveau push sur $BRANCH_NAME par $email.\"}"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : custom Slack webhook"
            echo "$slack_payload"
        else
            curl -s -X POST -H "Content-type: application/json" \
                 --data "$slack_payload" "$SLACK_WEBHOOK_URL" || {
                log_action "ERROR" "Erreur lors de l'envoi du webhook personnalisé Slack."
            }
        fi
        log_action "INFO" "Webhook Slack personnalisé envoyé."
    else
        log_action "WARN" "SLACK_WEBHOOK_URL non défini, pas de notif Slack."
    fi

    #### 2) Webhook GitHub (commentaire sur commit) ####
    if [ "$PLATFORM" == "github" ] && [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        # On récupère le hash du dernier commit local (HEAD)
        local commit_hash
        commit_hash=$(git rev-parse HEAD)

        # Message brut à commenter
        local raw_message="Nouveau push sur la branche $BRANCH_NAME par $email."

        # === DEBUG LOGS ===
        echo_color "$BLUE" "=== DEBUG custom GitHub webhook ==="
        echo_color "$BLUE" "GITHUB_TOKEN (masqué) => ${GITHUB_TOKEN:0:6}..."
        echo_color "$BLUE" "GITHUB_REPO => $GITHUB_REPO"
        echo_color "$BLUE" "Commit Hash => $commit_hash"
        echo_color "$BLUE" "Message brut =>"
        # Affiche les caractères spéciaux (\n, \r, etc.) s'il y en a
        echo "$raw_message" | sed -n 'l'

        # Vérifier si jq est installé
        if ! command -v jq &>/dev/null; then
            echo_color "$RED" "Erreur : 'jq' n'est pas installé. Impossible d'échapper le message."
            log_action "ERROR" "jq manquant pour l'échappement JSON GitHub"
            return
        fi
        # ============================

        # On échappe correctement le message via jq
        local encoded_message
        encoded_message=$(echo "$raw_message" | jq -Rs '.')

        # On construit la payload JSON finale
        local github_payload
        github_payload="{\"body\": $encoded_message}"

        echo_color "$BLUE" "encoded_message => $encoded_message"
        echo_color "$BLUE" "Payload final => $github_payload"
        echo_color "$BLUE" "==================================="

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : custom GitHub webhook (commentaire sur commit)"
             echo "$github_payload"
        else
            # Envoi d'un commentaire sur le commit via l'API GitHub
             response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
                 -X POST \
                 -H "Authorization: token $GITHUB_TOKEN" \
                 -H "Content-Type: application/json" \
                 --data "$github_payload" \
                 "https://api.github.com/repos/$GITHUB_REPO/commits/$commit_hash/comments")

             http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
             # shellcheck disable=SC2001
             body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

            if [ "$http_status" -ne 201 ]; then
                 echo_color "$RED" "Erreur custom webhook GitHub HTTP:$http_status"
                 echo_color "$RED" "Réponse: $body"
                 log_action "ERROR" "GitHub custom webhook fail $http_status $body"
            else
                 echo_color "$GREEN" "Webhook GitHub OK."
                 log_action "INFO" "Webhook GitHub OK."
            fi
        fi
    fi
}

function generate_report() {
    # AJOUT: Générer un rapport HTML local plus professionnel
    # shellcheck disable=SC2155
    local report_file="./reports/report_$(date '+%Y%m%d_%H%M%S').html"

    # Créer le répertoire parent du fichier de rapport
    mkdir -p "$(dirname "$report_file")"

    local email
    email=$(git config --get user.email)

    # Dates plus lisibles (local)
    local commit_hash
    commit_hash=$(git rev-parse HEAD)
    local commit_msg
    commit_msg=$(git log -1 --pretty=%B)
    local commit_author
    commit_author=$(git log -1 --pretty="%an")
    local commit_author_email
    commit_author_email=$(git log -1 --pretty="%ae")
    local commit_date
    commit_date=$(git log -1 --date=local --pretty="%cd")
    local committer
    committer=$(git log -1 --pretty="%cn")
    local committer_email
    committer_email=$(git log -1 --pretty="%ce")
    local committer_date
    committer_date=$(git log -1 --date=local --pretty="%cd")

    local branch_url
    branch_url=$(git config --get remote.origin.url)

    # Déterminer l'URL web du dépôt (pour lien de la branche)
    local web_repo_url
    if [[ $branch_url == git@* ]]; then
        local host
        local path
        host=$(echo "$branch_url" | awk -F'@|:' '{print $2}')
        path=$(echo "$branch_url" | awk -F':' '{print $2}' | sed 's/\.git$//')
        web_repo_url="https://$host/$path"
    elif [[ $branch_url == *:* && $branch_url != *//*:* ]]; then
        local host
        local path
        host=$(echo "$branch_url" | awk -F':' '{print $1}')
        path=$(echo "$branch_url" | awk -F':' '{print $2}' | sed 's/\.git$//')
        web_repo_url="https://$host/$path"
    elif [[ $branch_url == https://* ]]; then
        web_repo_url=${branch_url%.git}
    else
        web_repo_url="$branch_url"
    fi

    local branch_link="${web_repo_url}/tree/${BRANCH_NAME}"
    local commit_link="${web_repo_url}/commit/${commit_hash}"

    # Détection d'un ticket éventuel dans le message de commit
    local ticket_link=""
    if [[ -n "$TICKET_BASE_URL" && "$commit_msg" =~ ([A-Z]+-[0-9]+) ]]; then
        local ticket_id="${BASH_REMATCH[1]}"
        ticket_link="$TICKET_BASE_URL$ticket_id"
    fi

    # Récupération des fichiers modifiés lors du dernier commit
    local changed_files_html=""
    while IFS=$'\t' read -r status filename; do
        # shellcheck disable=SC2015
        [ -n "$status" ] && [ -n "$filename" ] || continue
        changed_files_html+="<tr><td>${status}</td><td>${filename}</td></tr>"
    done < <(git show --pretty="" --name-status HEAD)

    # Compter le nombre de fichiers modifiés
    local changed_files_count
    changed_files_count=$(echo "$changed_files_html" | grep -c '^<tr>')

    # Récupération des 5 derniers commits
    local recent_commits_html=""
    while IFS='|' read -r c_hash c_author c_date c_msg; do
        c_hash=$(echo "$c_hash" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        c_author=$(echo "$c_author" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        c_date=$(echo "$c_date" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        c_msg=$(echo "$c_msg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        recent_commits_html+="<tr><td><a href=\"${web_repo_url}/commit/${c_hash}\">$c_hash</a></td><td>$c_author</td><td>$c_date</td><td>$c_msg</td></tr>"
    done < <(git log -5 --date=local --pretty=format:'%h|%an|%ad|%s')

    # Compter le nombre de commits affichés
    local commits_count
    commits_count=$(echo "$recent_commits_html" | grep -c '^<tr>')

    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Rapport de push Git</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            background: #f9f9f9;
            color: #333;
        }
        header {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 20px;
            margin-bottom: 30px;
        }
        header .logo {
            display: flex;
            align-items: center;
        }
        header img {
            height: 40px;
            margin-right: 15px;
        }
        header h1 {
            font-size: 24px;
            margin: 0;
        }
        .container {
            width: 90%;
            max-width: 1000px;
            margin: auto;
        }
        h2 {
            color: #2c3e50;
            border-bottom: 2px solid #2c3e50;
            padding-bottom: 5px;
            margin-top: 50px;
            margin-bottom: 20px;
            position: relative;
        }
        h2:before {
            content: "⚙ ";
            font-weight: normal;
            color: #2c3e50;
            position: absolute;
            left: -30px;
            top: 0;
        }
        p.description {
            font-size: 15px;
            line-height: 1.5;
            margin-bottom: 20px;
        }
        p.summary {
            font-size: 14px;
            margin-bottom: 30px;
            color: #555;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            background: #fff;
            border: 1px solid #ccc;
            margin-bottom: 30px;
        }
        th, td {
            padding: 10px 12px;
            border: 1px solid #ddd;
            vertical-align: top;
        }
        th {
            background: #f2f2f2;
            text-align: left;
            font-weight: bold;
            width: 25%;
        }
        .commit-msg {
            white-space: pre-wrap;
        }
        .footer {
            margin-top: 20px;
            font-size: 0.85em;
            color: #555;
            text-align: center;
            padding-bottom: 30px;
        }
        a {
            color: #2980b9;
            text-decoration: none;
            transition: color 0.2s ease;
        }
        a:hover {
            text-decoration: underline;
            color: #1a6fb9;
        }
        .no-ticket {
            color: #7f8c8d;
            font-style: italic;
        }
    </style>
</head>
<body>
<header>
    <div class="logo">
        <img src="https://via.placeholder.com/40x40/ffffff/000000?text=G" alt="Logo">
        <h1>Rapport de push Git</h1>
    </div>
</header>
<div class="container">
    <p class="description">
        Ce rapport a été généré automatiquement après un push. Il récapitule les informations clés du push effectué,
        notamment la branche, l'auteur, le commit et le message associé. Il peut être utilisé pour un suivi plus précis
        des modifications introduites dans le dépôt.
    </p>
    <p class="summary">Ce push a modifié $changed_files_count fichier(s) et affiche un aperçu des $commits_count derniers commits.</p>

    <h2>Détails du dernier commit</h2>
    <table>
        <tr>
            <th>Branche</th>
            <td><a href="$branch_link">$BRANCH_NAME</a></td>
        </tr>
        <tr>
            <th>Projet (Remote URL)</th>
            <td><a href="$web_repo_url">$web_repo_url</a></td>
        </tr>
        <tr>
            <th>Commit</th>
            <td><a href="$commit_link">$commit_hash</a></td>
        </tr>
        <tr>
            <th>Auteur du Commit</th>
            <td>$commit_author ($commit_author_email)</td>
        </tr>
        <tr>
            <th>Date du Commit</th>
            <td>$commit_date</td>
        </tr>
        <tr>
            <th>Committer</th>
            <td>$committer ($committer_email)</td>
        </tr>
        <tr>
            <th>Date du Committer</th>
            <td>$committer_date</td>
        </tr>
        <tr>
            <th>Message</th>
            <td class="commit-msg">$commit_msg</td>
        </tr>
        <tr>
            <th>Ticket Lié</th>
            <td>
                ${ticket_link:+"<a href=\"$ticket_link\">Aller au ticket</a> (Ticket détecté: $ticket_id)"}${ticket_link:-<span class="no-ticket">Aucun ticket détecté</span>}
            </td>
        </tr>
    </table>

    <h2>Fichiers modifiés lors du dernier commit</h2>
    <table>
        <tr>
            <th style="width:100px;">Statut</th>
            <th>Fichier</th>
        </tr>
        $changed_files_html
    </table>

    <h2>Aperçu des derniers commits</h2>
    <table>
        <tr>
            <th style="width:100px;">Hash</th>
            <th>Auteur</th>
            <th>Date</th>
            <th>Message</th>
        </tr>
        $recent_commits_html
    </table>

    <div class="footer">
        <p><em>Généré le $(date '+%Y-%m-%d %H:%M:%S')</em></p>
        <p>Version du script : $SCRIPT_VERSION</p>
        <p>Auteur du script actuel : $email</p>
    </div>
</div>
</body>
</html>
EOF

    echo_color "$GREEN" "Rapport généré : $report_file"
    log_action "INFO" "Rapport généré : $report_file"
}
