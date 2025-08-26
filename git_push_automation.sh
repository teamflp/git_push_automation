#!/usr/bin/env bash

###############################################################################
# GIT PUSH AUTOMATION
#
# Ce script est conçu pour être utilisé par tous les développeurs d'une équipe.
# Il intègre:
# - Un flux par défaut (sauvegarde, ajout, commit, push)
# - Options avancées : gestion des hooks, sous-modules, stats de commits,
#   tickets, qualité (lint, sécurité), comparaison de branches, export de patches,
#   déclenchement CI, log des releases, nettoyage de branches fusionnées.
# - Intégration Slack, e-mail, GitLab/GitHub/Bitbucket pour notifications et releases.
# - Rapport HTML enrichi incluant tests, qualité, stats.
# - Messages d'aide et gestion fine des erreurs.
#
# Configuration via un fichier .env.git_push_automation (exemple fourni).
#
# Les développeurs peuvent utiliser ce script en ligne de commande avec différentes
# options, ou en mode par défaut interactif.
# 
# Fiabilité et robustesse :
# - Gestion des erreurs avec messages explicites.
# - Interaction limitée si DRY_RUN ou variables fixées.
# - Vérification de présence d'outils (git-secrets, bandit, npm, etc.) avant utilisation.
#
###############################################################################

# Charger les sous-modules
source "$(dirname "$0")/modules/hooks.sh"
source "$(dirname "$0")/modules/notifications.sh"
source "$(dirname "$0")/modules/submodules.sh"

# Charger les plugins
source "$(dirname "$0")/plugins/gitlab_plugin.sh"
source "$(dirname "$0")/plugins/jira_plugin.sh"
source "$(dirname "$0")/plugins/slack_plugin.sh"
source "$(dirname "$0")/plugins/bitbucket_plugin.sh"
source "$(dirname "$0")/plugins/github_plugin.sh"
source "$(dirname "$0")/plugins/mattermost_plugin.sh"

# Version du script
SCRIPT_VERSION="1.1.7"

# Arrêter le script en cas d'erreur et traiter les erreurs de pipeline
set -e
set -o pipefail

###############################################################################
# COULEURS ET AFFICHAGE
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
# shellcheck disable=SC2034
UNDERLINE='\033[4m'
NC='\033[0m' # Pas de couleur

# Fonction pour afficher du texte avec couleur et style

function echo_color() {
    echo -e "${1}${2}${NC}"
}

function display_header() {
    clear
    echo_color "$BLUE$BOLD" "========================"
    echo_color "$BLUE$BOLD" " $(get_string "header_title") "
    echo_color "$BLUE$BOLD" "========================"
    echo ""
}

###############################################################################
# I18N and STRING FORMATTING
###############################################################################
# Retrieves a string by its key and formats it with given arguments.
# This function reads the language file on each call as a robust workaround
# for shell variable scoping issues.
function get_string() {
    local key="$1"
    shift

    # LANGUAGE must be a global variable set by load_config
    local lang_file
    lang_file="$(dirname "$0")/lang/${LANGUAGE:-fr}.sh"

    if [ ! -f "$lang_file" ]; then
        echo "!!LANG FILE NOT FOUND: $lang_file!!"
        return
    fi

    # Pattern to find: I18N_STRINGS["key"]="value"
    # We grep for the key, then use sed to extract just the value between quotes.
    local line
    line=$(grep "I18N_STRINGS\[\"$key\"\]" "$lang_file")

    if [ -z "$line" ]; then
        echo "!!MISSING_STRING: $key!!"
        return
    fi

    # sed 's/.*="\(.*\)"/\1/' extracts the content between the last =" and "
    local value
    value=$(echo "$line" | sed -e 's/.*="\(.*\)"/\1/')

    # Use printf for formatting any additional arguments
    # shellcheck disable=SC2059
    printf "$value" "$@"
}

###############################################################################
# LOGGING
###############################################################################
LOG_FILE="./git_push_automation.log"

function init_logging() {
    # Vérification ou création du fichier de log
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE" || { echo_color "$RED" "$(get_string "error_cannot_create_file" "$LOG_FILE")"; exit 1; }
        echo_color "$GREEN" "$(get_string "log_file_created" "$LOG_FILE")"
    fi

    # Vérifier si le fichier de log est accessible en écriture
    if [ ! -w "$LOG_FILE" ]; then
        echo_color "$RED" "$(get_string "error_cannot_write_to_file" "$LOG_FILE")"
        exit 1
    fi
}

# Fonction de journalisation avec niveaux de verbosité
function log_action() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] : $message" >> "$LOG_FILE"
    if [ "$VERBOSE" == "y" ]; then
        echo_color "$BLUE" "[$level] $message"
    fi
}

###############################################################################
# FONCTIONS DE PARSING SÉMANTIQUE
# parse_semver() et compare_semver()
###############################################################################
function parse_semver() {
    # Convertit "v1.2.10" => 1002010 pour comparer numériquement
    local version="$1"
    # Supprime "v" si présent
    version="${version#v}"

    local major minor patch
    IFS='.' read -r major minor patch <<< "$version"
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}

    # Ex: M=1, m=2, p=10 => (1 * 1 000 000) + (2 * 1 000) + 10 = 1002010
    echo $(( major * 1000000 + minor * 1000 + patch ))
}

function compare_semver() {
    # Compare deux versions semver ex: "v1.2.3" "v1.2.10"
    # Retourne:
    #   0 si v1 == v2
    #   1 si v1 >  v2
    #  -1 si v1 <  v2
    local v1="$1"
    local v2="$2"

    local int1
    local int2
    int1=$(parse_semver "$v1")
    int2=$(parse_semver "$v2")

    if (( int1 > int2 )); then
        echo 1
    elif (( int1 < int2 )); then
        echo -1
    else
        echo 0
    fi
}

###############################################################################
# FONCTION DE MISE À JOUR
# perform_script_update() télécharge le script et le remplace
###############################################################################
function perform_script_update() {
    echo_color "$BLUE" "$(get_string "update_downloading")"

    # Commande de mise à jour
    sudo curl -L \
      "https://raw.githubusercontent.com/teamflp/git_push_automation/master/git_push_automation.sh" \
      -o /usr/local/bin/git_push_automation || {
        echo_color "$RED" "$(get_string "update_download_error")"
        log_action "ERROR" "Echec de perform_script_update()"
        exit 1
      }

    # On rend le script exécutable
    sudo chmod +x /usr/local/bin/git_push_automation

    echo_color "$GREEN" "$(get_string "update_finished")"
    log_action "INFO" "Script mis à jour vers la version distante."
}

###############################################################################
# FONCTION D'ORCHESTRATION
# check_for_script_update() récupère le tag distant, compare, propose la MAJ
###############################################################################
function check_for_script_update() {
    local repo_owner="teamflp"
    local repo_name="git_push_automation"

    # Récupère la liste des tags
    local tags_json
    tags_json=$(curl -s "https://api.github.com/repos/$repo_owner/$repo_name/tags")

    if [ -z "$tags_json" ]; then
        echo_color "$YELLOW" "$(get_string "update_check_error")"
        log_action "WARN" "Impossible de récupérer liste tags GitHub."
        return
    fi

    local latest_tag=""
    local first_loop=true

    # Parcourt chaque tag name
    local tag_name
    while read -r tag_name; do
        if [ "$first_loop" = true ]; then
            latest_tag="$tag_name"
            first_loop=false
        else
            local cmp
            cmp=$(compare_semver "$tag_name" "$latest_tag")
            if [ "$cmp" -eq 1 ]; then
                # tag_name > latest_tag
                latest_tag="$tag_name"
            fi
        fi
    done < <(echo "$tags_json" | jq -r '.[].name')

    if [ -z "$latest_tag" ]; then
        echo_color "$YELLOW" "$(get_string "update_no_tags_found" "$repo_owner" "$repo_name")"
        log_action "WARN" "Aucun tag trouvé."
        return
    fi

    # Compare latest_tag à SCRIPT_VERSION
    local cmp
    cmp=$(compare_semver "$latest_tag" "$SCRIPT_VERSION")
    if [ "$cmp" -eq 1 ]; then
        echo_color "$BLUE" "$(get_string "update_available" "$latest_tag" "$SCRIPT_VERSION")"
        echo_color "$YELLOW" "$(get_string "update_prompt" "$(get_string 'prompt_yes_no')")"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            perform_script_update
        else
            echo_color "$YELLOW" "$(get_string "update_cancelled" "$SCRIPT_VERSION")"
        fi
    elif [ "$cmp" -eq 0 ]; then
        echo_color "$GREEN" "$(get_string "update_already_latest" "$SCRIPT_VERSION")"
    else
        echo_color "$YELLOW" "$(get_string "update_local_newer" "$latest_tag" "$SCRIPT_VERSION")"
        log_action "INFO" "Le script local est plus récent ?"
    fi
}

###############################################################################
# INSTALLATION ET VÉRIFICATION MESSAGERIE
###############################################################################
function check_mailer() {
    if command -v mail &> /dev/null; then
        echo_color "$GREEN" "$(get_string "mailer_already_installed")"
        log_action "INFO" "Système de messagerie déjà installé."
        return 0
    fi

    if [ -n "$SILENT_INSTALL" ]; then
        log_action "INFO" "Mode silencieux activé. Tentative d'installation mail."
        if detect_and_install_mailer; then
            return 0
        else
            echo_color "$RED" "$(get_string "mailer_silent_install_failed")"
            log_action "ERROR" "Echec mail silent install."
            return 1
        fi
    fi

    echo_color "$YELLOW" "$(get_string "mailer_not_found_prompt" "$(get_string 'prompt_yes_no')")"
    read -r INSTALL_MAILER
    if [ "$INSTALL_MAILER" == "y" ]; then
        if detect_and_install_mailer; then
            return 0
        else
            echo_color "$RED" "$(get_string "mailer_install_failed_manual")"
            log_action "ERROR" "Mail install failed."
            return 1
        fi
    else
        echo_color "$RED" "$(get_string "mailer_skipped_no_emails")"
        log_action "WARN" "Pas de mail, pas d'envoi e-mails."
        return 1
    fi
}

function detect_and_install_mailer() {
    log_action "INFO" "Détection OS pour mail."
    case "$OSTYPE" in
        linux-gnu*)
            if command -v apt-get &> /dev/null; then
                echo_color "$BLUE" "$(get_string "mailer_installing_apt")"
                # shellcheck disable=SC2015
                sudo apt-get update && sudo apt-get install -y mailutils || {
                    echo_color "$RED" "$(get_string "mailer_install_failed_apt")"
                    log_action "ERROR" "apt-get mail fail."
                    return 1
                }
            elif command -v yum &> /dev/null; then
                echo_color "$BLUE" "$(get_string "mailer_installing_yum")"
                sudo yum install -y mailx || {
                    echo_color "$RED" "$(get_string "mailer_install_failed_yum")"
                    log_action "ERROR" "yum mail fail."
                    return 1
                }
            elif command -v dnf &> /dev/null; then
                echo_color "$BLUE" "$(get_string "mailer_installing_dnf")"
                sudo dnf install -y mailx || {
                    echo_color "$RED" "$(get_string "mailer_install_failed_dnf")"
                    log_action "ERROR" "dnf mail fail."
                    return 1
                }
            else
                echo_color "$RED" "$(get_string "mailer_no_pkg_manager")"
                log_action "ERROR" "No pkg manager for mail."
                return 1
            fi
            ;;
        darwin*)
            if command -v brew &> /dev/null; then
                echo_color "$BLUE" "$(get_string "mailer_installing_brew")"
                brew install mailutils || {
                    echo_color "$RED" "$(get_string "mailer_install_failed_brew")"
                    log_action "ERROR" "brew mail fail."
                    return 1
                }
            else
                echo_color "$YELLOW" "$(get_string "mailer_install_manual_mac")"
                log_action "WARN" "Pas de mail sur mac sans brew."
                return 1
            fi
            ;;
        cygwin*|msys*|win32*)
            echo_color "$RED" "$(get_string "mailer_install_manual_windows")"
            log_action "WARN" "Windows mail non géré."
            return 1
            ;;
        *)
            echo_color "$RED" "$(get_string "mailer_unsupported_os")"
            log_action "ERROR" "Mail OS unsupported."
            return 1
            ;;
    esac

    if command -v mail &> /dev/null; then
        echo_color "$GREEN" "$(get_string "mailer_install_success")"
        log_action "INFO" "Mail installé."
        return 0
    else
        echo_color "$RED" "$(get_string "mailer_not_found_post_install")"
        log_action "ERROR" "Mail absent post-install."
        return 1
    fi
}

###############################################################################
# AIDE ET OPTIONS
###############################################################################
function usage() {
    echo "$(get_string "usage_header" "$0")"
    echo ""
    echo "$(get_string "usage_options_title")"
    echo "$(get_string "usage_opt_f")"
    echo "$(get_string "usage_opt_m")"
    echo "$(get_string "usage_opt_b")"
    echo "$(get_string "usage_opt_p")"
    echo "$(get_string "usage_opt_M")"
    echo "$(get_string "usage_opt_r")"
    echo "$(get_string "usage_opt_v")"
    echo "$(get_string "usage_opt_d")"
    echo "$(get_string "usage_opt_h")"
    echo "$(get_string "usage_opt_g")"
    echo "$(get_string "usage_opt_R")"
    echo "$(get_string "usage_opt_t")"
    echo "$(get_string "usage_opt_T")"
    echo "$(get_string "usage_opt_H")"
    echo "$(get_string "usage_opt_C")"
    echo "$(get_string "usage_opt_k")"
    echo "$(get_string "usage_opt_S")"
    echo "$(get_string "usage_opt_q")"
    echo "$(get_string "usage_opt_B")"
    echo "$(get_string "usage_opt_P")"
    echo "$(get_string "usage_opt_x")"
    echo "$(get_string "usage_opt_E")"
    echo "$(get_string "usage_opt_I")"
    echo "$(get_string "usage_opt_U")"
    echo "$(get_string "usage_opt_L")"
    echo "$(get_string "usage_opt_X")"
    echo "$(get_string "usage_opt_Y")"
    echo "$(get_string "usage_opt_Z")"
    echo "$(get_string "usage_opt_create_pr")"
    echo "$(get_string "usage_opt_create_mr")"
    echo "$(get_string "usage_opt_ci_friendly")"
    echo "$(get_string "usage_opt_V")"
    exit 1
}

###############################################################################
# VARIABLES GLOBALES ET INIT
###############################################################################
FILES=()
COMMIT_MSG=""
BRANCH_NAME=""
DO_PULL="n"
DO_MERGE="n"
MERGE_BRANCH=""
VERBOSE="n"
DRY_RUN="n"
MULTI_REPO_DIR=""
GPG_SIGN="n"
REBASE_BRANCH=""
RUN_TESTS="n"
TAG_NAME=""
GENERATE_REPORT="n"
AUTO_CONFLICT_RES="n"
MANAGE_HOOKS="n"
MANAGE_SUBMODULES="n"
RUN_QUALITY_CHECKS="n"
COMPARE_BRANCH=""
EXPORT_PATCHES="n"
PATCH_COUNT=""    # Pour -P
CLEANUP_BRANCHES="n"
GENERATE_COMMIT_STATS="n"
LINK_TICKETS="n"
TRIGGER_CI="n"
LOG_RELEASE="n"
ROLLBACK_COMMITS=""  # -X [ncommits]   -> rollback
DO_CHERRY_PICK="n"   # -Y              -> cherry-pick interactif
DO_REVIEW_DIFF="n"   # -Z              -> review/diff complet
CREATE_PR="n"        # --create-pr     -> création d'une Pull Request sur GitHub
CREATE_MR="n"        # --create-mr     -> création d'une Merge Request sur GitLab
CI_FRIENDLY="n"      # --ci-friendly   -> mode sans interaction (CI)
AUTO_VERSION_BUMP="" # ex: "major", "minor", "patch"

###############################################################################
# TRAITEMENT DES OPTIONS
###############################################################################
function process_options() {
    if [ $# -eq 0 ]; then return; fi

    # Ajoutons X: Y Z et V: dans la liste des options courtes
    # 'X:' => X requiert un argument (ex: -X 2)
    # 'Y' et 'Z' => sans argument
    # 'V:' => V requiert un argument (ex: -V patch)
    #
    # => Liste : :f:m:b:M:r:vdhpgR:tT:HCkSqB:P:xEILU X:YZV:

    while getopts ":f:m:b:M:r:vdhpgR:tT:HCkSqB:P:xEILUX:YZV:" opt; do
        case $opt in
            f)
                if [ "$OPTARG" == "." ]; then
                    FILES=(".")
                else
                    IFS=' ' read -r -a FILES <<< "$OPTARG"
                fi
                ;;
            m) COMMIT_MSG="$OPTARG" ;;
            b) BRANCH_NAME="$OPTARG" ;;
            M) DO_MERGE="y"; MERGE_BRANCH="$OPTARG" ;;
            r) MULTI_REPO_DIR="$OPTARG" ;;
            v) VERBOSE="y" ;;
            d)
                DRY_RUN="y"
                echo_color "$YELLOW" "$(get_string "dry_run_activated")"
                log_action "INFO" "dry-run activé."
                ;;
            h) usage ;;
            p) DO_PULL="y" ;;
            g) GPG_SIGN="y" ;;
            R) REBASE_BRANCH="$OPTARG" ;;
            t) RUN_TESTS="y" ;;
            T) TAG_NAME="$OPTARG" ;;
            H) GENERATE_REPORT="y" ;;
            C) AUTO_CONFLICT_RES="y" ;;
            k) MANAGE_HOOKS="y" ;;
            S) MANAGE_SUBMODULES="y" ;;
            q) RUN_QUALITY_CHECKS="y" ;;
            B) COMPARE_BRANCH="$OPTARG" ;;
            P)
                EXPORT_PATCHES="y"
                PATCH_COUNT="$OPTARG"
                ;;
            x) CLEANUP_BRANCHES="y" ;;
            E) GENERATE_COMMIT_STATS="y" ;;
            I) LINK_TICKETS="y" ;;
            U) TRIGGER_CI="y" ;;
            L) LOG_RELEASE="y" ;;

            # -- Nouvelles options courtes --
            X)  # Rollback commits => ex: -X 2
                ROLLBACK_COMMITS="$OPTARG"
                ;;
            Y)  # Cherry-pick interactif => ex: -Y
                DO_CHERRY_PICK="y"
                ;;
            Z)  # Review/diff => ex: -Z
                DO_REVIEW_DIFF="y"
                ;;
            V)  # Version bump => ex: -V patch
                AUTO_VERSION_BUMP="$OPTARG"
                ;;

            \?)
                echo_color "$RED" "$(get_string "error_invalid_option" "$OPTARG")"
                usage
                ;;
            :)
                echo_color "$RED" "$(get_string "error_option_requires_argument" "$OPTARG")"
                usage
                ;;
        esac
    done

    # À ce stade, OPTIND pointe après les options courtes traitées.
    # On peut analyser les options longues (type --create-pr, --create-mr, --ci-friendly).
    shift $((OPTIND -1))

    while [ $# -gt 0 ]; do
        case "$1" in
            --create-pr)
                CREATE_PR="y"
                shift
                ;;
            --create-mr)
                CREATE_MR="y"
                shift
                ;;
            --ci-friendly)
                CI_FRIENDLY="y"
                shift
                ;;
            *)
                # On n'a pas d'autre --long-option prévue,
                # donc on s'arrête ici
                break
                ;;
        esac
    done
}

###############################################################################
# CHARGEMENT DE LA CONFIG ET CHECK
###############################################################################
function load_config() {
    local config_file="config.yaml"

    if [ ! -f "$config_file" ]; then
        # Cannot use get_string here as language is not yet known
        echo_color "$YELLOW" "Le fichier de configuration '$config_file' est manquant. / Configuration file '$config_file' is missing."
        exit 1
    fi

    # Set the global LANGUAGE variable. get_string will use this.
    LANGUAGE=$(yq -r '.language // "fr"' "$config_file")

    # Explicitly parse all known config values
    export SLACK_WEBHOOK_URL; SLACK_WEBHOOK_URL=$(yq -r '.slack.webhook_url // ""' "$config_file")
    export SLACK_CHANNEL; SLACK_CHANNEL=$(yq -r '.slack.channel // ""' "$config_file")
    export SLACK_USERNAME; SLACK_USERNAME=$(yq -r '.slack.username // ""' "$config_file")
    export SLACK_ICON_EMOJI; SLACK_ICON_EMOJI=$(yq -r '.slack.icon_emoji // ""' "$config_file")
    export GITLAB_PROJECT_ID; GITLAB_PROJECT_ID=$(yq -r '.gitlab.project_id // ""' "$config_file")
    export GITLAB_TOKEN; GITLAB_TOKEN=$(yq -r '.gitlab.token // ""' "$config_file")
    export GITLAB_GROUP_NAME; GITLAB_GROUP_NAME=$(yq -r '.gitlab.group_name // ""' "$config_file")
    export SILENT_INSTALL; SILENT_INSTALL=$(yq -r '.silent_install // ""' "$config_file")
    export EMAIL_PROVIDER; EMAIL_PROVIDER=$(yq -r '.email.provider // ""' "$config_file")
    export SENDGRID_API_KEY; SENDGRID_API_KEY=$(yq -r '.email.sendgrid.api_key // ""' "$config_file")
    export SENDGRID_FROM; SENDGRID_FROM=$(yq -r '.email.sendgrid.from // ""' "$config_file")
    export MAILGUN_API_KEY; MAILGUN_API_KEY=$(yq -r '.email.mailgun.api_key // ""' "$config_file")
    export MAILGUN_DOMAIN; MAILGUN_DOMAIN=$(yq -r '.email.mailgun.domain // ""' "$config_file")
    export MAILGUN_FROM; MAILGUN_FROM=$(yq -r '.email.mailgun.from // ""' "$config_file")
    export MAILJET_API_KEY; MAILJET_API_KEY=$(yq -r '.email.mailjet.api_key // ""' "$config_file")
    export MAILJET_SECRET_KEY; MAILJET_SECRET_KEY=$(yq -r '.email.mailjet.secret_key // ""' "$config_file")
    export MAILJET_FROM; MAILJET_FROM=$(yq -r '.email.mailjet.from // ""' "$config_file")
    export AWS_SES_ACCESS_KEY; AWS_SES_ACCESS_KEY=$(yq -r '.email.aws_ses.access_key // ""' "$config_file")
    export AWS_SES_SECRET_KEY; AWS_SES_SECRET_KEY=$(yq -r '.email.aws_ses.secret_key // ""' "$config_file")
    export AWS_SES_REGION; AWS_SES_REGION=$(yq -r '.email.aws_ses.region // ""' "$config_file")
    export AWS_SES_FROM; AWS_SES_FROM=$(yq -r '.email.aws_ses.from // ""' "$config_file")
    export GMAIL_HOST; GMAIL_HOST=$(yq -r '.email.gmail.host // ""' "$config_file")
    export GMAIL_PORT; GMAIL_PORT=$(yq -r '.email.gmail.port // ""' "$config_file")
    export GMAIL_USER; GMAIL_USER=$(yq -r '.email.gmail.user // ""' "$config_file")
    export GMAIL_PASS; GMAIL_PASS=$(yq -r '.email.gmail.pass // ""' "$config_file")
    export GMAIL_FROM; GMAIL_FROM=$(yq -r '.email.gmail.from // ""' "$config_file")
    export TEST_COMMAND; TEST_COMMAND=$(yq -r '.tests.command // ""' "$config_file")
    export QUALITY_COMMAND; QUALITY_COMMAND=$(yq -r '.quality.command // ""' "$config_file")
    export CI_TRIGGER_URL; CI_TRIGGER_URL=$(yq -r '.ci.trigger_url // ""' "$config_file")
    export PLATFORM; PLATFORM=$(yq -r '.platforms.current_platform // ""' "$config_file")
    export BITBUCKET_WORKSPACE; BITBUCKET_WORKSPACE=$(yq -r '.platforms.bitbucket.workspace // ""' "$config_file")
    export BITBUCKET_REPO_SLUG; BITBUCKET_REPO_SLUG=$(yq -r '.platforms.bitbucket.repo_slug // ""' "$config_file")
    export BITBUCKET_USER; BITBUCKET_USER=$(yq -r '.platforms.bitbucket.user // ""' "$config_file")
    export BITBUCKET_APP_PASSWORD; BITBUCKET_APP_PASSWORD=$(yq -r '.platforms.bitbucket.app_password // ""' "$config_file")
    export GITHUB_TOKEN; GITHUB_TOKEN=$(yq -r '.platforms.github.token // ""' "$config_file")
    export GITHUB_REPO; GITHUB_REPO=$(yq -r '.platforms.github.repo // ""' "$config_file")
    export TICKET_BASE_URL; TICKET_BASE_URL=$(yq -r '.tickets.base_url // ""' "$config_file")

    log_action "INFO" "$(get_string "config_loaded" "$config_file")"
}

function check_dependencies() {
    local missing_dependencies=()
    local dependencies=("jq" "curl" "git" "yq")

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_dependencies+=("$cmd")
        fi
    done

    if [ "${#missing_dependencies[@]}" -ne 0 ]; then
        echo_color "$RED" "$(get_string "error_missing_dependencies" "${missing_dependencies[*]}")"
        log_action "ERROR" "Commandes manquantes : ${missing_dependencies[*]}"
        exit 1
    fi

    local git_min_version="2.20.0"
    local git_version
    git_version=$(git --version | awk '{print $3}')
    if [ "$(printf '%s\n' "$git_min_version" "$git_version" | sort -V | head -n1)" != "$git_min_version" ]; then
        echo_color "$RED" "$(get_string "error_git_version_too_old" "$git_min_version")"
        log_action "ERROR" "Version de Git trop ancienne : $git_version"
        exit 1
    fi

    log_action "INFO" "$(get_string "dependencies_ok")"
}

function check_permissions() {
    if [ "$EUID" -eq 0 ]; then
        echo_color "$RED" "$(get_string "error_run_as_root")"
        log_action "ERROR" "Le script a été exécuté en tant que root."
        exit 1
    fi
}

function check_git_repo() {
    if [ ! -d ".git" ]; then
        echo_color "$RED" "$(get_string "error_not_a_git_repo")"
        log_action "ERROR" "Ce répertoire n'est pas un dépôt Git."
        return 1
    fi
    log_action "INFO" "Vérification du dépôt Git réussie."
}

function check_user_email() {
    local email
    email=$(git config --get user.email)
    if [ -z "$email" ]; then
        echo_color "$YELLOW" "$(get_string "git_email_missing")"
        echo_color "$YELLOW" "$(get_string "git_email_prompt")"
        read -r email
        if [ -z "$email" ]; then
            echo_color "$RED" "$(get_string "git_email_error_empty")"
            log_action "ERROR" "L'adresse e-mail saisie est vide."
            return 1
        fi
        git config --global user.email "$email"
        log_action "INFO" "Adresse e-mail configurée globalement : $email"
    else
        log_action "INFO" "Utilisateur actuel : $email"
    fi
}

###############################################################################
# FONCTIONS UTILES (backup, add, tests, etc.)
###############################################################################
function backup_files() {
    BACKUP_DIR="./backup/backup_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$BACKUP_DIR"
    log_action "INFO" "Répertoire de sauvegarde créé : $BACKUP_DIR"

    for FILE in "${FILES[@]}"; do
        if [ -e "$FILE" ]; then
            rsync -R "$FILE" "$BACKUP_DIR"
            log_action "INFO" "Fichier sauvegardé : $FILE"
        else
            echo_color "$YELLOW" "$(get_string "backup_file_not_found" "$FILE")"
            log_action "WARN" "Fichier '$FILE' n'existe pas."
        fi
    done

    echo_color "$GREEN" "$(get_string "backup_finished" "$BACKUP_DIR")"
    log_action "INFO" "Sauvegarde terminée."
}

function add_files() {
    echo_color "$BLUE" "$(get_string "add_modified_files_title")"
    git status -s
    log_action "INFO" "Affichage des modifications."

    if [ ${#FILES[@]} -eq 0 ]; then
        echo_color "$YELLOW" "$(get_string "add_prompt_for_files")"
        read -r -a INPUT_FILES
        if [ "${INPUT_FILES[0]}" == "." ]; then
            FILES=(".")
        else
            FILES=("${INPUT_FILES[@]}")
        fi
        log_action "INFO" "Fichiers par utilisateur : ${FILES[*]}"
    fi

    log_action "INFO" "Fichiers à ajouter : ${FILES[*]}"

    if [ "${FILES[0]}" == "." ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "$(get_string "add_simulation_all")"
        else
            git add .
        fi
    else
        for FILE in "${FILES[@]}"; do
            if [ -e "$FILE" ]; then
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "$(get_string "add_simulation_file" "$FILE")"
                else
                    git add "$FILE"
                fi
            else
                echo_color "$RED" "$(get_string "add_file_not_exist" "$FILE")"
                log_action "ERROR" "Fichier '$FILE' inexistant."
                return 1
            fi
        done
    fi

    if [ "$DRY_RUN" != "y" ]; then
        echo_color "$GREEN" "$(get_string "add_files_added_title")"
        git diff --cached --name-only
    else
        echo_color "$GREEN" "$(get_string "add_simulation_complete")"
    fi
}

function improved_validate_commit_message() {
    # Valide le message de commit selon le format Type: Description
    if [[ ! $COMMIT_MSG =~ ^(Tâche|Bug|Amélioration|Refactor):[[:space:]].+ ]]; then
        echo_color "$RED" "$(get_string "commit_invalid_format")"
        echo_color "$YELLOW" "$(get_string "commit_format_hint")"
        echo_color "$GREEN" "$(get_string "commit_format_example")"
        return 1
    fi
    return 0
}

function run_tests() {
    # Vérifier si l'utilisateur veut lancer des tests (RUN_TESTS = "y")
    # et si TEST_COMMAND est défini et non vide dans le fichier de configuration.

    if [ "$RUN_TESTS" == "y" ] && [ -n "$TEST_COMMAND" ]; then
        echo_color "$YELLOW" "$(get_string "tests_running")"
        log_action "INFO" "Exécution des tests via : $TEST_COMMAND"

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "$(get_string "tests_simulation" "$TEST_COMMAND")"
            log_action "INFO" "Simulation des tests."
        else
            if ! $TEST_COMMAND; then
                echo_color "$RED" "$(get_string "tests_failed")"
                log_action "ERROR" "Echec des tests."
                exit 1
            fi
            log_action "INFO" "Tests réussis."
        fi
    else
        # Soit RUN_TESTS n'est pas 'y', soit TEST_COMMAND est vide.
        # Dans ce cas, on n'exécute pas de tests.
        log_action "INFO" "Aucun test à exécuter (RUN_TESTS != y ou TEST_COMMAND non défini)."
    fi
}

function create_commit() {
    # Original keywords for logic/validation
    local original_types=("Tâche" "Bug" "Amélioration" "Refactor")
    # Translated types for display in the select menu
    local display_types=(
        "$(get_string "commit_type_task")"
        "$(get_string "commit_type_bug")"
        "$(get_string "commit_type_improvement")"
        "$(get_string "commit_type_refactor")"
    )
    local type_choice=""
    local commit_description=""

    while true; do
        if [ -n "$COMMIT_MSG" ]; then
            improved_validate_commit_message && break || COMMIT_MSG=""
        fi

        echo_color "$BLUE" "$(get_string "commit_prompt_type")"
        PS3="$(get_string "commit_prompt_ps3")"
        select opt in "${display_types[@]}"; do
            if [[ -n "$opt" ]]; then
                # Find the index of the selected display type
                for i in "${!display_types[@]}"; do
                    if [[ "${display_types[$i]}" == "$opt" ]]; then
                        # Get the original keyword from the other array
                        type_choice="${original_types[$i]}"
                        break 2 # Break out of both the for and select loops
                    fi
                done
            else
                echo_color "$RED" "$(get_string "commit_invalid_choice")"
            fi
        done

        echo_color "$YELLOW" "$(get_string "commit_prompt_description")"
        read -r commit_description
        COMMIT_MSG="$type_choice: $commit_description"
        # shellcheck disable=SC2030
        # shellcheck disable=SC2015
        improved_validate_commit_message && break || (echo_color "$RED" "$(get_string "commit_invalid_retry")"; COMMIT_MSG="")
    done

    run_tests

    if [ "$DRY_RUN" == "y" ]; then
        # shellcheck disable=SC2031
        echo_color "$GREEN" "$(get_string "commit_simulation" "$COMMIT_MSG")"
        # shellcheck disable=SC2031
        log_action "INFO" "Simul commit : $COMMIT_MSG"
    else
        if [ "$GPG_SIGN" == "y" ]; then
            # shellcheck disable=SC2031
            git commit -m "$COMMIT_MSG" -S
        else
            # shellcheck disable=SC2031
            git commit -m "$COMMIT_MSG"
        fi
        # shellcheck disable=SC2031
        log_action "INFO" "Commit créé : $COMMIT_MSG"
    fi
}

###############################################################################
# FONCTIONS AVANCÉES (ROLLBACK, CHERRY-PICK, REVIEW, ETC.)
###############################################################################

# Pour la sécurité, on peut demander à l’utilisateur s’il veut faire un revert
# (qui crée un commit inverse) ou un reset (qui efface l’historique local).
function rollback_commits() {
    if [ -z "$ROLLBACK_COMMITS" ]; then
        return
    fi

    echo_color "$RED" "$(get_string "rollback_prompt_info" "$ROLLBACK_COMMITS")"
    if [ "$CI_FRIENDLY" == "y" ]; then
        # En mode CI, on part direct sur un revert ou reset
        echo_color "$YELLOW" "$(get_string "rollback_ci_info" "$ROLLBACK_COMMITS")"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "$(get_string "rollback_simulation_revert" "$((ROLLBACK_COMMITS-1))")"
        else
            git revert --no-edit HEAD~$((ROLLBACK_COMMITS-1))..HEAD
        fi
        return
    fi

    echo_color "$YELLOW" "$(get_string "rollback_prompt_which_type")"
    echo "$(get_string "rollback_choice_revert")"
    echo "$(get_string "rollback_choice_reset")"
    read -rp "> " ROLLBACK_CHOICE
    case "$ROLLBACK_CHOICE" in
        1)
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "$(get_string "rollback_simulation_revert" "$((ROLLBACK_COMMITS-1))")"
            else
                git revert --no-edit HEAD~$((ROLLBACK_COMMITS-1))..HEAD
            fi
            ;;
        2)
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "$(get_string "rollback_simulation_reset" "$ROLLBACK_COMMITS")"
            else
                git reset --hard HEAD~"$ROLLBACK_COMMITS"
            fi
            ;;
        *)
            echo_color "$RED" "$(get_string "generic_cancelled")"
            ;;
    esac
}

# On affiche la liste des commits d’une autre branche, et on propose de cherry-pick le commit voulu
function cherry_pick_interactive() {
    if [ "$DO_CHERRY_PICK" != "y" ]; then
        return
    fi

    echo_color "$BLUE" "$(get_string "cherry_pick_title")"
    echo_color "$YELLOW" "$(get_string "cherry_pick_prompt_branch")"
    read -r SOURCE_BRANCH

    # Récupérer un log succinct
    echo_color "$BLUE" "$(get_string "cherry_pick_commits_available" "$SOURCE_BRANCH")"
    git fetch origin "$SOURCE_BRANCH"
    git log --oneline "origin/$SOURCE_BRANCH" -n 10

    echo_color "$YELLOW" "$(get_string "cherry_pick_prompt_hash")"
    read -r COMMIT_HASH

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "$(get_string "cherry_pick_simulation" "$COMMIT_HASH")"
    else
        git cherry-pick "$COMMIT_HASH" || {
            echo_color "$RED" "$(get_string "cherry_pick_conflict")"
            check_for_conflicts
        }
    fi
}

# Review (diff) avant push
function review_changes() {
    if [ "$DO_REVIEW_DIFF" != "y" ]; then
        return
    fi

    echo_color "$BLUE" "$(get_string "review_title")"
    # Résumé
    git diff --stat

    if [ "$CI_FRIENDLY" == "y" ]; then
        # Pas de question en CI
        return
    fi

    echo_color "$YELLOW" "$(get_string "review_prompt_full_diff" "$(get_string 'prompt_yes_no')")"
    read -r SHOW_DIFF
    if [ "$SHOW_DIFF" == "y" ]; then
        git diff --color | less -R
    fi

    echo_color "$YELLOW" "$(get_string "review_prompt_graphical_tool" "$(get_string 'prompt_yes_no')")"
    read -r GRAPHICAL
    if [ "$GRAPHICAL" == "y" ]; then
        if command -v meld &>/dev/null; then
            meld .
        else
            echo_color "$RED" "$(get_string "review_meld_not_installed")"
        fi
    fi
}



# Versioning sémantique (bumping major/minor/patch)
# On peut lire le dernier tag vX.Y.Z, incrémenter, et créer un nouveau tag.
function auto_semver_bump() {
    if [ -z "$AUTO_VERSION_BUMP" ]; then
        return
    fi
    echo_color "$BLUE" "$(get_string "semver_title" "$AUTO_VERSION_BUMP")"

    # Récupérer le dernier tag
    local last_tag
    last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    # suppose format vMAJOR.MINOR.PATCH
    local version="${last_tag#v}"  # remove leading 'v' si existant
    local major="${version%%.*}"
    local rest="${version#*.}"
    local minor="${rest%%.*}"
    local patch="${rest#*.}"

    case "$AUTO_VERSION_BUMP" in
        major)
            major=$((major+1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor+1))
            patch=0
            ;;
        patch)
            patch=$((patch+1))
            ;;
        *)
            echo_color "$RED" "$(get_string "semver_unknown_bump_type" "$AUTO_VERSION_BUMP")"
            return
            ;;
    esac
    local new_tag="v${major}.${minor}.${patch}"

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "$(get_string "semver_simulation" "$new_tag" "$new_tag")"
    else
        git tag -a "$new_tag" -m "Auto semver bump"
        git push origin "$new_tag"
        echo_color "$GREEN" "$(get_string "semver_tag_created" "$new_tag")"
        # Optionnel : vous pourriez lancer create_release $new_tag "Nouvelle version"
    fi
}

###############################################################################
# GESTION DES BRANCHES, PULL, MERGE, REBASE, PUSH
###############################################################################
function handle_branch() {
    if [ -n "$BRANCH_NAME" ]; then
        # Si la branche est spécifiée, s'assurer qu'on est bien dessus
        if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git checkout '$BRANCH_NAME'"
            else
                git checkout "$BRANCH_NAME"
            fi
        else
            # Créer la branche si elle n'existe pas
            if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "Simulation : git checkout -b '$BRANCH_NAME' 'origin/$BRANCH_NAME'"
                else
                    git checkout -b "$BRANCH_NAME" "origin/$BRANCH_NAME"
                fi
            else
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "Simulation : git checkout -b '$BRANCH_NAME'"
                else
                    git checkout -b "$BRANCH_NAME"
                fi
            fi
        fi
    else
        # Demande interactive si aucune branche n'a été spécifiée
        branches=()
        while IFS= read -r line; do
            branches+=("$line")
        done < <(git branch -r | sed 's/origin\///' | uniq)

        PS3="$(get_string "branch_select_prompt")"
        select BRANCH_NAME in "${branches[@]}"; do
            if [ -n "$BRANCH_NAME" ]; then
                BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "Simulation : git checkout '$BRANCH_NAME'"
                else
                    git checkout "$BRANCH_NAME"
                fi
                break
            else
                echo_color "$RED" "$(get_string "branch_invalid_selection")"
            fi
        done
    fi
    log_action "INFO" "Branche distante cible : $BRANCH_NAME"
}

function check_branch_status() {
    echo_color "$BLUE" "$(get_string "branch_status_checking" "$BRANCH_NAME")"
    git fetch origin "$BRANCH_NAME"
    LOCAL=$(git rev-parse "$BRANCH_NAME")
    REMOTE=$(git rev-parse "origin/$BRANCH_NAME")
    BASE=$(git merge-base "$BRANCH_NAME" "origin/$BRANCH_NAME")

    if [ "$LOCAL" == "$REMOTE" ]; then
        echo_color "$GREEN" "$(get_string "branch_status_up_to_date" "$BRANCH_NAME")"
    elif [ "$LOCAL" == "$BASE" ]; then
        echo_color "$YELLOW" "$(get_string "branch_status_behind" "$BRANCH_NAME")"
    elif [ "$REMOTE" == "$BASE" ]; then
        echo_color "$YELLOW" "$(get_string "branch_status_ahead" "$BRANCH_NAME")"
    else
        echo_color "$RED" "$(get_string "branch_status_diverged" "$BRANCH_NAME")"
        echo_color "$YELLOW" "$(get_string "branch_merge_remote_prompt" "$(get_string 'prompt_yes_no')")"
        read -r MERGE_REMOTE
        if [ "$MERGE_REMOTE" == "y" ]; then
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git merge 'origin/$BRANCH_NAME'"
            else
                git merge "origin/$BRANCH_NAME" || {
                    echo_color "$RED" "$(get_string "branch_merge_error")"
                    check_for_conflicts
                    return 1
                }
            fi
        else
            echo_color "$RED" "$(get_string "generic_cancelled")"
            return 1
        fi
    fi
}

function check_for_conflicts() {
    if git ls-files -u | grep -q .; then
        echo_color "$RED" "$(get_string "conflict_detected")"
        if [ "$AUTO_CONFLICT_RES" == "y" ]; then
            # AJOUT: Tentative de résolution auto des conflits (exemple)
            echo_color "$YELLOW" "$(get_string "conflict_auto_resolve_attempt")"
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git mergetool --tool=meld"
            else
                git mergetool --tool=meld
                git add -A
                git commit -m "$(get_string "conflict_auto_resolve_commit_msg")"
            fi
        else
            echo_color "$YELLOW" "$(get_string "conflict_manual_resolve_prompt" "$(get_string 'prompt_yes_no')")"
            read -r RESOLVE_CONFLICTS
            if [ "$RESOLVE_CONFLICTS" == "y" ]; then
                conflicted_files=$(git diff --name-only --diff-filter=U)
                for file in $conflicted_files; do
                    echo_color "$YELLOW" "$(get_string "conflict_manual_resolve_file" "$file")"
                    ${EDITOR:-nano} "$file"
                    git add "$file"
                done
                git commit -m "$(get_string "conflict_manual_resolve_commit_msg")"
            else
                echo_color "$RED" "$(get_string "conflict_unresolved_error")"
                return 1
            fi
        fi
    fi
}

function stash_changes() {
    if [ -n "$(git status --porcelain)" ]; then
        echo_color "$YELLOW" "$(get_string "stash_prompt" "$(get_string 'prompt_yes_no')")"
        read -r STASH_ANSWER
        if [ "$STASH_ANSWER" == "y" ]; then
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git stash"
            else
                git stash
            fi
        fi
    fi
}

function unstash_changes() {
    if git stash list | grep -q .; then
        echo_color "$YELLOW" "$(get_string "unstash_prompt" "$(get_string 'prompt_yes_no')")"
        read -r UNSTASH_ANSWER
        if [ "$UNSTASH_ANSWER" == "y" ]; then
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git stash pop"
            else
                git stash pop
                check_for_conflicts
            fi
        fi
    fi
}

# PULL : Mettre à jour la branche locale avec les modifications de la branche distante
function perform_pull() {
    if [ "$DO_PULL" == "y" ]; then
        echo_color "$YELLOW" "$(get_string "pull_running")"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git pull origin '$BRANCH_NAME'"
        else
            git pull origin "$BRANCH_NAME" || {
                echo_color "$RED" "$(get_string "pull_error")"
                check_for_conflicts
                return 1
            }
        fi
    else
        echo_color "$YELLOW" "$(get_string "pull_prompt" "$(get_string 'prompt_yes_no')")"
        read -r PULL_ANSWER
        if [ "$PULL_ANSWER" == "y" ]; then
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git pull origin '$BRANCH_NAME'"
            else
                git pull origin "$BRANCH_NAME" || {
                    echo_color "$RED" "$(get_string "pull_error")"
                    check_for_conflicts
                    return 1
                }
            fi
        fi
    fi
}

# MERGE : Fusionner une branche dans la branche courante avant le push
function perform_merge() {
    if [ "$DO_MERGE" == "y" ]; then
        echo_color "$YELLOW" "$(get_string "merge_running" "$MERGE_BRANCH")"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git merge '$MERGE_BRANCH'"
        else
            git merge "$MERGE_BRANCH" || {
                echo_color "$RED" "$(get_string "merge_error")"
                check_for_conflicts
                return 1
            }
        fi
    else
        echo_color "$YELLOW" "$(get_string "merge_prompt_another_branch" "$(get_string 'prompt_yes_no')")"
        read -r MERGE_ANSWER
        if [ "$MERGE_ANSWER" == "y" ]; then
            echo_color "$YELLOW" "$(get_string "merge_prompt_branch_name")"
            read -r MERGE_BRANCH
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git merge '$MERGE_BRANCH'"
            else
                git merge "$MERGE_BRANCH" || {
                    echo_color "$RED" "$(get_string "merge_error")"
                    check_for_conflicts
                    return 1
                }
            fi
        fi
    fi
}

# REBASE : Rebase sur une branche avant le push. Utile pour garder l'historique propre. (ex: rebase sur master avant de pousser une feature)
# ATTENTION : Ne jamais rebase une branche partagée (ex: master)
# Utilisation : git_push_automation.sh -R master
# Le rebase sert à appliquer les commits de la branche cible (ex: master) sur la branche courante (ex: feature)
function perform_rebase() {
    # AJOUT: Rebase sur une branche donnée avant le push
    if [ -n "$REBASE_BRANCH" ]; then
        echo_color "$YELLOW" "$(get_string "rebase_running" "$REBASE_BRANCH")"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git rebase '$REBASE_BRANCH'"
        else
            git fetch origin "$REBASE_BRANCH"
            git rebase "origin/$REBASE_BRANCH" || {
                echo_color "$RED" "$(get_string "rebase_error")"
                check_for_conflicts
                return 1
            }
        fi
    fi
}


# SECURE_PUSH : Scan des secrets dans le code source avant le push
# Utilisation : git_push_automation.sh
function secure_push() {
    # Lancement d’un scan avant le push
    if command -v git-secrets &>/dev/null; then
        git-secrets --scan
        if [ $? -ne 0 ]; then
            echo_color "$RED" "$(get_string "secure_push_secrets_detected")"
            exit 1
        fi
    fi
}

# PUSH : Pousser les modifications locales sur la branche distante
function perform_push() {
    secure_push
    while true; do
        echo ""
        echo -n "$(get_string "push_prompt" "$BRANCH_NAME" "$(get_string 'prompt_yes_no')") "
        # shellcheck disable=SC2162
        read CONFIRM_PUSH
        case "$CONFIRM_PUSH" in
            y|Y) break ;;
            n|N) echo_color "$RED" "$(get_string "generic_cancelled")"; return 1 ;;
            *) echo_color "$RED" "$(get_string "push_invalid_answer")" ;;
        esac
    done

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git push origin '$BRANCH_NAME'"
    else
        git push origin "$BRANCH_NAME" || {
            echo_color "$RED" "$(get_string "push_error")"
            return 1
        }
    fi

    # AJOUT: Gestion du tag
    if [ -n "$TAG_NAME" ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git tag '$TAG_NAME' && git push origin '$TAG_NAME'"
        else
            git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
            git push origin "$TAG_NAME"
        fi
        echo_color "$GREEN" "$(get_string "push_tag_success" "$TAG_NAME")"
    fi

    # Préparation des variables pour la création de la release GitLab (si nécessaire)
    local email_user
    email_user=$(git config --get user.email)
    local commit_hash
    commit_hash=$(git rev-parse HEAD)
    local repo_url
    repo_url=$(git config --get remote.origin.url)

    # Déterminer l'URL web du dépôt
    local web_repo_url
    if [[ $repo_url == git@* ]]; then
        # Si l'URL est au format SSH
        local host
        local path
        host=$(echo "$repo_url" | awk -F'@|:' '{print $2}')
        path=$(echo "$repo_url" | awk -F':' '{print $2}' | sed 's/\.git$//')
        web_repo_url="https://$host/$path"
    elif [[ $repo_url == *:* && $repo_url != *//*:* ]]; then
        # Format host:path
        local host
        local path
        host=$(echo "$repo_url" | awk -F':' '{print $1}')
        path=$(echo "$repo_url" | awk -F':' '{print $2}' | sed 's/\.git$//')
        web_repo_url="https://$host/$path"
    elif [[ $repo_url == https://* ]]; then
        # Déjà HTTPS
        web_repo_url=${repo_url%.git}
    else
        echo_color "$RED" "$(get_string "push_unsupported_repo_url" "$repo_url")"
        log_action "ERROR" "Format d'URL du dépôt non supporté : $repo_url"
        # On ne bloque pas ici, mais pas de création de release si URL non supportée.
    fi

    local project_name
    project_name=$(basename "$web_repo_url")
    local commit_url="${web_repo_url}/commit/${commit_hash}"

    # AJOUT: Création d'une Release GitLab si un tag est présent et si GITLAB_PROJECT_ID et GITLAB_TOKEN sont disponibles
    if [ -n "$TAG_NAME" ] && [ -n "$GITLAB_PROJECT_ID" ] && [ -n "$GITLAB_TOKEN" ] && [ "$DRY_RUN" != "y" ]; then
        local gitlab_api_url="https://gitlab.com/api/v4"
        # shellcheck disable=SC2155
        local release_name="Release $(date '+%Y-%m-%d %H:%M:%S')"
        local release_description="Cette release correspond au tag \`$TAG_NAME\` :
- Projet : $project_name
- Branche : $BRANCH_NAME
- Commit : $commit_hash

[Voir le commit]($commit_url)"

        response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" --request POST \
            --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --header "Content-Type: application/json" \
            --data "$(jq -n --arg tag "$TAG_NAME" --arg name "$release_name" --arg desc "$release_description" '{ tag_name: $tag, name: $name, description: $desc }')" \
            "$gitlab_api_url/projects/$GITLAB_PROJECT_ID/releases")

        http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
        # shellcheck disable=SC2001
        body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

        if [ "$http_status" -eq 201 ]; then
            echo_color "$GREEN" "$(get_string "push_release_success" "$TAG_NAME")"
            log_action "INFO" "Release GitLab créée avec succès."
        else
            echo_color "$RED" "$(get_string "push_release_error" "$http_status")"
            echo_color "$RED" "Réponse : $body"
            log_action "ERROR" "Erreur lors de la création de la release GitLab. Statut : $http_status, Réponse : $body"
        fi
    else
        log_action "INFO" "$(get_string "push_no_release")"
    fi

    # Envoi des notifications
    send_notification
    send_custom_webhook

    # Génération du rapport si demandé
    if [ "$GENERATE_REPORT" == "y" ]; then
        generate_report
    fi

    # Message final
    if [ "$DRY_RUN" != "y" ]; then
        echo_color "$GREEN" "$(get_string "push_success" "$BRANCH_NAME")"
    else
        echo_color "$GREEN" "$(get_string "push_simulation_success")"
    fi
}

###############################################################################
# PLATFORM-AGNOSTIC ABSTRACTION
# VARIABLE PLATFORM DOIT ÊTRE DÉFINIE DANS LE FICHIER DE CONFIGURATION
# (ex: export PLATFORM="gitlab" ou "bitbucket" etc.)
# SELON PLATFORM, ON APPELLE LES FONCTIONS SPÉCIFIQUES
###############################################################################

function notify_platform_after_push() {
    local commit_hash="$1"
    local project_name="$2"
    local commit_url="$3"

    # shellcheck disable=SC2155
    local message="**Nouveau push effectué !**
- **Projet :** $project_name
- **Branche :** $BRANCH_NAME
- **Auteur :** $(git config --get user.email)

[Voir le commit]($commit_url)"

    if [ -z "$PLATFORM" ]; then
        log_action "WARN" "Aucune plateforme définie."
        return
    fi

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation: Notification plateforme ($PLATFORM)."
        return
    fi

    case "$PLATFORM" in
        gitlab)
            [ -z "$GITLAB_TOKEN" ] && { log_action "WARN" "GITLAB_TOKEN manquant pour GitLab."; return; }
            [ -z "$GITLAB_PROJECT_ID" ] && { log_action "WARN" "GITLAB_PROJECT_ID manquant."; return; }
            notify_gitlab "$message" "$commit_hash"
            ;;
        bitbucket)
            [ -z "$BITBUCKET_USER" ] && { log_action "WARN" "BITBUCKET_USER manquant pour Bitbucket."; return; }
            [ -z "$BITBUCKET_APP_PASSWORD" ] && { log_action "WARN" "BITBUCKET_APP_PASSWORD manquant."; return; }
            notify_bitbucket "$message" "$commit_hash"
            ;;
        *)
            log_action "WARN" "Plateforme inconnue: $PLATFORM"
            ;;
    esac
}

function create_release() {
    local tag_name="$1"
    local description="$2"

    if [ -z "$PLATFORM" ]; then
        log_action "WARN" "Pas de plateforme définie, release ignorée."
        return
    fi

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation: create_release $PLATFORM ($tag_name)"
        return
    fi

    case "$PLATFORM" in
        gitlab)
            [ -z "$GITLAB_TOKEN" ] && { log_action "WARN" "Pas de GITLAB_TOKEN."; return; }
            [ -z "$GITLAB_PROJECT_ID" ] && { log_action "WARN" "Pas de GITLAB_PROJECT_ID."; return; }
            create_gitlab_release "$tag_name" "$description"
            ;;
        bitbucket)
            [ -z "$BITBUCKET_USER" ] && { log_action "WARN" "Pas de BITBUCKET_USER."; return; }
            [ -z "$BITBUCKET_APP_PASSWORD" ] && { log_action "WARN" "Pas de BITBUCKET_APP_PASSWORD."; return; }
            create_bitbucket_release "$tag_name" "$description"
            ;;

        *)
            log_action "WARN" "Plateforme inconnue: $PLATFORM"
            ;;
    esac
}



###############################################################################
# GESTION MULTI-DEPOT, MENU, ACTIONS PAR DEFAUT, HOOKS, SOUS-MODULES, ETC.
###############################################################################
function handle_multiple_repositories() {
    local repo_dir="$1"
    shift
    if [ -d "$repo_dir" ]; then
        for dir in "$repo_dir"/*/; do
            if [ -d "${dir}.git" ]; then
                (
                    echo_color "$BLUE" "$(get_string "multi_repo_start" "$dir")"
                    log_action "INFO" "Opérations sur le dépôt dans $dir"
                    cd "$dir" || { echo_color "$RED" "$(get_string "multi_repo_cd_error" "$dir")"; exit 1; }
                    main_without_repo_dir "$@"
                ) &
            fi
        done
        wait
    else
        echo_color "$RED" "$(get_string "multi_repo_dir_not_found" "$repo_dir")"
        log_action "ERROR" "Le répertoire spécifié n'existe pas : $repo_dir"
        exit 1
    fi
}


##############################################################################
# 3. Historique et Statistiques de commits
# On extrait plus d’infos, par exemple le nombre de commits par type, le top 3 des auteurs, etc.
###############################################################################
function generate_commit_stats() {
    echo_color "$BLUE" "$(get_string "stats_generating")"

    # Créer le répertoire stats s'il n'existe pas
    mkdir -p stats

    # Générer le fichier dans le dossier stats
    local stats_file="stats/commit_stats.md"

    # Top 3 des auteurs sur les 30 derniers commits
    echo "## Statistiques de commits" > "$stats_file"
    # shellcheck disable=SC2129
    echo "### Top Auteurs (30 derniers commits):" >> "$stats_file"
    git shortlog -n -s -e -30 | head -n 3 >> "$stats_file"

    # Compter le nombre de commits par type (Tâche, Bug, etc.)
    echo "### Nombre de commits par type (30 derniers):" >> "$stats_file"
    for t in "Tâche" "Bug" "Amélioration" "Refactor"; do
        # shellcheck disable=SC2126
        count=$(git log -30 --pretty=%s | grep "^$t:" | wc -l)
        echo "- $t : $count" >> "$stats_file"
    done

    log_action "INFO" "Statistiques de commits générées dans $stats_file"
    echo_color "$GREEN" "$(get_string "stats_finished" "$stats_file")"
}

###############################################################################
# 5. Vérifications de Qualité (Linting, Sécurité)
# Fonction avancée: exécuter un linter (ex: ESLint) et un scan de sécurité (ex: npm audit)
###############################################################################
function run_quality_checks() {
    if [ -n "$QUALITY_COMMAND" ]; then
        echo_color "$YELLOW" "$(get_string "quality_running" "$QUALITY_COMMAND")"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : $QUALITY_COMMAND"
        else
            # Vérifier si l'outil de qualité (par ex: npm) est dispo
            if ! command -v npm &>/dev/null; then
                echo_color "$RED" "$(get_string "quality_npm_missing")"
                log_action "WARN" "npm non dispo, saut lint."
            else
                if ! $QUALITY_COMMAND; then
                    echo_color "$RED" "$(get_string "quality_failed")"
                    log_action "ERROR" "Echec qualité."
                    exit 1
                else
                    echo_color "$GREEN" "$(get_string "quality_ok")"
                    log_action "INFO" "Qualité OK."
                fi
            fi
        fi
    fi

    # Vérifications additionnelles (audit sécurité)
    # Vérification npm audit
    if command -v npm &>/dev/null && [ -f package.json ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation: npm audit"
        else
            npm audit --audit-level=moderate
            # shellcheck disable=SC2181
            if [ $? -ne 0 ]; then
                echo_color "$RED" "$(get_string "quality_audit_failed")"
                log_action "ERROR" "Audit sécurité fail."
                exit 1
            fi
            echo_color "$GREEN" "$(get_string "quality_audit_ok")"
            log_action "INFO" "Audit npm OK."
        fi
    fi

    # Vérification git-secrets
    if command -v git-secrets &>/dev/null; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git-secrets --scan"
        else
            git-secrets --scan
            # shellcheck disable=SC2181
            if [ $? -ne 0 ]; then
                echo_color "$RED" "$(get_string "quality_secrets_detected")"
                log_action "ERROR" "Secrets détectés."
                exit 1
            fi
            echo_color "$GREEN" "$(get_string "quality_secrets_ok")"
            log_action "INFO" "Aucun secret."
        fi
    else
        echo_color "$YELLOW" "$(get_string "quality_secrets_missing")"
        log_action "WARN" "git-secrets absent."
    fi

    # Vérification bandit (Python)
    if command -v bandit &>/dev/null && [ -f requirements.txt ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : bandit -r ."
        else
            bandit -r .
            # shellcheck disable=SC2181
            if [ $? -ne 0 ]; then
                echo_color "$RED" "$(get_string "quality_bandit_failed")"
                log_action "ERROR" "Bandit fail."
                exit 1
            fi
            echo_color "$GREEN" "$(get_string "quality_bandit_ok")"
            log_action "INFO" "Bandit OK."
        fi
    else
        echo_color "$YELLOW" "$(get_string "quality_bandit_missing")"
        log_action "WARN" "bandit absent ou pas de code Python."
    fi
}

##############################################################################
# 6. Comparaison entre Branches
# On va afficher un diff plus complet, éventuellement lister les commits en plus sur l’autre branche.
###############################################################################
function compare_branches() {
    echo_color "$YELLOW" "$(get_string "compare_running" "$BRANCH_NAME" "$COMPARE_BRANCH")"
    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git log $BRANCH_NAME..$COMPARE_BRANCH --oneline"
    else
        echo_color "$BLUE" "$(get_string "compare_commits_in_other" "$COMPARE_BRANCH")"
        git log --oneline "$BRANCH_NAME..$COMPARE_BRANCH"
        echo_color "$BLUE" "$(get_string "compare_diff_title")"
        git diff "$BRANCH_NAME..$COMPARE_BRANCH"
    fi
    log_action "INFO" "Comparaison effectuée."
}

##############################################################################
# 7. Sauvegarde/Export de Patchs
# On demande combien de commits exporter, propose de nommer les patchs.
###############################################################################
function export_patches() {
    # Utiliser PATCH_COUNT si défini, sinon défaut à 3
    local count=${PATCH_COUNT:-3}
    echo_color "$YELLOW" "$(get_string "patch_exporting" "$count")"

    # Créer le répertoire patches s'il n'existe pas
    mkdir -p "./patches"

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git format-patch -$count HEAD -o ./patches"
    else
        git format-patch -"$count" HEAD -o ./patches
        echo_color "$GREEN" "$(get_string "patch_finished")"
    fi
    log_action "INFO" "$count patches exportés dans ./patches."
}

##############################################################################
# 8. Intégration d’un Système de Build/CI
# Fonction avancée: après le push, appeler un endpoint CI
###############################################################################
function trigger_ci() {
    if [ -n "$CI_TRIGGER_URL" ]; then
        echo_color "$YELLOW" "$(get_string "ci_triggering")"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : curl -X POST $CI_TRIGGER_URL"
        else
            # Possibilité d'envoyer un token avec --header "CI-Token: ..."
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$CI_TRIGGER_URL")
            if [ "$response" != "200" ]; then
                echo_color "$RED" "$(get_string "ci_trigger_failed" "$response")"
                log_action "ERROR" "CI fail."
            else
                echo_color "$GREEN" "$(get_string "ci_trigger_success")"
                log_action "INFO" "CI déclenchée."
            fi
        fi
    fi
}

##############################################################################
# 9. Historique de Releases
# Après avoir créé un tag/release, loguer dans release_history.log
###############################################################################
function log_release() {
    if [ -n "$TAG_NAME" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : Release $TAG_NAME créée." >> release_history.log
        log_action "INFO" "Release $TAG_NAME logguée dans release_history.log."
    fi
}

##############################################################################
# 10. Nettoyage et Maintenance (branches locales)
# Fonction avancée: lister les branches déjà mergées dans main ou master, proposer de les supprimer.
###############################################################################
function cleanup_branches() {
    echo_color "$YELLOW" "$(get_string "cleanup_running")"
    local main_branch="main"
    # shellcheck disable=SC2162
    git branch | grep -v "$main_branch" | while read b; do
        # Vérifier si fusionnée
        git branch --merged $main_branch | grep -q " $b$" && {
            echo_color "$BLUE" "$(get_string "cleanup_prompt" "$b" "$(get_string 'prompt_yes_no')")"
            read -r DEL_ANSWER
            if [ "$DEL_ANSWER" == "y" ]; then
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "Simulation : git branch -d $b"
                else
                    git branch -d "$b"
                fi
            fi
        }
    done
    log_action "INFO" "Nettoyage branches terminé."
}

function default_actions_sequence() {
    local actions=("backup_files" "add_files" "create_commit" "handle_branch" "stash_changes" "perform_pull" "perform_rebase" "check_branch_status" "perform_merge" "perform_push" "unstash_changes")
    local action_names=(
        "$(get_string "menu_item_1" | sed 's/1. //')"
        "$(get_string "menu_item_2" | sed 's/2. //')"
        "$(get_string "menu_item_3" | sed 's/3. //')"
        "$(get_string "menu_item_4" | sed 's/4. //')"
        "$(get_string "menu_item_5" | sed 's/5. //')"
        "$(get_string "menu_item_6" | sed 's/6. //')"
        "$(get_string "menu_item_7" | sed 's/7. //')"
        "$(get_string "menu_item_8" | sed 's/8. //')"
    )
    local total_actions=${#actions[@]}
    local current_action=0

    while [ "$current_action" -lt "$total_actions" ]; do
        display_header
        echo_color "$GREEN" "$(get_string "sequence_action_title" "${action_names[$current_action]}")"
        echo_color "$YELLOW" "$(get_string "sequence_prompt")"
        read -rp "> " user_choice

        if [ -z "$user_choice" ]; then
            ${actions[$current_action]}
            action_status=$?
            if [ $action_status -ne 0 ]; then
                echo_color "$RED" "$(get_string "sequence_error_retry" "${action_names[$current_action]}" "$(get_string 'prompt_yes_no')")"
                read -rp "> " retry_choice
                if [ "$retry_choice" == "y" ]; then
                    continue
                else
                    current_action=$((current_action + 1))
                    continue
                fi
            else
                current_action=$((current_action + 1))
            fi
        elif [ "$user_choice" == "n" ]; then
            main_menu "$current_action"
            break
        else
            echo_color "$RED" "$(get_string "sequence_invalid_option")"
        fi
    done
}

function main_without_repo_dir() {
    echo_color "$GREEN" "$(get_string "main_repo_operations_starting")"
    check_git_repo || exit 1
    check_user_email || exit 1

    # 1) Si l’utilisateur a demandé un rollback (option -X n)
    rollback_commits

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$YELLOW" "$(get_string "dry_run_activated")"
    fi

    # 2) Gérer les hooks si besoin
    if [ "$MANAGE_HOOKS" == "y" ]; then
        manage_hooks
    fi

    # 3) Gérer les sous-modules si besoin
    if [ "$MANAGE_SUBMODULES" == "y" ]; then
        handle_submodules
    fi

    # 4) Générer stats de commits
    if [ "$GENERATE_COMMIT_STATS" == "y" ]; then
        generate_commit_stats
    fi

    # 5) Lier les tickets si demandé
    if [ "$LINK_TICKETS" == "y" ]; then
        link_tickets
    fi

    # 6) Vérifications qualité (lint, audit, etc.)
    if [ "$RUN_QUALITY_CHECKS" == "y" ]; then
        run_quality_checks
    fi

    # 7) Comparer la branche si besoin
    if [ -n "$COMPARE_BRANCH" ]; then
        compare_branches
    fi

    # 8) Exporter des patches si demandé
    if [ "$EXPORT_PATCHES" == "y" ]; then
        export_patches
    fi

    # 9) Cherry-pick interactif (option -Y) avant d'ajouter/committer/pousser
    cherry_pick_interactive

    # 10) Review/diff complet (option -Z) juste avant la séquence d'actions
    review_changes

    # 11) Lancer la séquence d'actions par défaut (backup, add_files, create_commit, push, etc.)
    default_actions_sequence
}

function main_menu() {
    local current_action=$1
    while true; do
        display_header
        echo_color "$YELLOW" "$(get_string "menu_title")"
        echo_color "$BLUE" "$(get_string "menu_item_1")"
        echo_color "$BLUE" "$(get_string "menu_item_2")"
        echo_color "$BLUE" "$(get_string "menu_item_3")"
        echo_color "$BLUE" "$(get_string "menu_item_4")"
        echo_color "$BLUE" "$(get_string "menu_item_5")"
        echo_color "$BLUE" "$(get_string "menu_item_6")"
        echo_color "$BLUE" "$(get_string "menu_item_7")"
        echo_color "$BLUE" "$(get_string "menu_item_8")"
        echo ""
        echo_color "$YELLOW" "$(get_string "sequence_prompt")"
        read -rp "> " CHOICE

        if [ -z "$CHOICE" ]; then
            default_actions_sequence "$current_action"
            break
        fi

        case $CHOICE in
            1) backup_files ;;
            2) add_files ;;
            3) create_commit ;;
            4) handle_branch ;;
            5) perform_pull ;;
            6) perform_merge ;;
            7) perform_push ;;
            8)
                echo_color "$GREEN" "$(get_string "menu_exit_message")"
                exit 0
                ;;
            *) echo_color "$RED" "$(get_string "sequence_invalid_option")" ;;
        esac

        echo_color "$YELLOW" "$(get_string "menu_return_to_sequence_prompt" "$(get_string 'prompt_yes_no')")"
        read -rp "> " return_choice
        if [ "$return_choice" == "y" ]; then
            default_actions_sequence "$current_action"
            break
        fi
    done
}

function collect_feedback() {
    # Après la séquence, si TRIGGER_CI == "y", déclencher CI ici
    if [ "$TRIGGER_CI" == "y" ]; then
        trigger_ci
    fi

    # Si LOG_RELEASE == "y" et qu'un tag a été créé, log_release
    if [ "$LOG_RELEASE" == "y" ] && [ -n "$TAG_NAME" ]; then
        log_release
    fi

    # Nettoyage branches si CLEANUP_BRANCHES == "y"
    if [ "$CLEANUP_BRANCHES" == "y" ]; then
        cleanup_branches
    fi

    echo_color "$YELLOW" "$(get_string "feedback_prompt" "$(get_string 'prompt_yes_no')")"
    read -r FEEDBACK_RESPONSE
    if [ "$FEEDBACK_RESPONSE" == "y" ]; then
        echo_color "$YELLOW" "$(get_string "feedback_prompt_comment")"
        read -r USER_FEEDBACK
        echo "$(date '+%Y-%m-%d %H:%M:%S') : $USER_FEEDBACK" >> feedback.log
        echo_color "$GREEN" "$(get_string "feedback_thanks")"
        log_action "INFO" "Feedback collecté."
    fi
}

###############################################################################
# MAIN
###############################################################################
function main() {
    # Load config and language first. This is safe because the config
    # file path is not a configurable option.
    load_config
    init_logging

    # Now process options, which may call usage() and needs the language loaded.
    process_options "$@"

    echo_color "$BLUE$BOLD" "$(get_string "main_start" "$SCRIPT_VERSION")"
    log_action "INFO" "Démarrage du script v$SCRIPT_VERSION"
    log_action "INFO" "Options : $*"

    check_dependencies
    check_permissions

    # -- Vérification de mise à jour du script via l'API GitHub --
    check_for_script_update  # Ici, on peut comparer la version distante (tags GitHub) à SCRIPT_VERSION

    check_git_repo || exit 1
    check_user_email || exit 1

    # -- Si l'utilisateur a spécifié un répertoire multi-dépôts --
    if [ -n "$MULTI_REPO_DIR" ]; then
        handle_multiple_repositories "$MULTI_REPO_DIR" "$@"
        exit 0
    fi

    # -- Exécuter les actions principales (mode par défaut ou avec arguments) --
    if [ $# -eq 0 ]; then
        main_without_repo_dir
    else
        main_without_repo_dir "$@"
    fi

    # -- Indications post-push ou simulation --
    if [ "$DRY_RUN" != "y" ]; then
        echo_color "$GREEN" "$(get_string "main_post_push_check_remote")"
    else
        echo_color "$YELLOW" "$(get_string "main_post_push_simulation_finished")"
    fi

    # -- Collecte éventuelle de feedback --
    collect_feedback
}

main "$@"