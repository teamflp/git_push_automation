#!/usr/bin/env bash

###############################################################################
# GIT PUSH AUTOMATION - VERSION AVANCÉE
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
# Configuration via un fichier .env_git_push_automation (exemple fourni).
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

# Version du script
SCRIPT_VERSION="1.1.0"

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
    echo_color "$BLUE$BOLD" " GIT PUSH AUTOMATION "
    echo_color "$BLUE$BOLD" "========================"
    echo ""
}

###############################################################################
# LOGGING
###############################################################################
LOG_FILE="./git_push_automation.log"

# Vérification ou création du fichier de log
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" || { echo_color "$RED" "Erreur : Impossible de créer $LOG_FILE"; exit 1; }
    echo_color "$GREEN" "Fichier de log créé : $LOG_FILE"
fi

# Vérifier si le fichier de log est accessible en écriture
if [ ! -w "$LOG_FILE" ]; then
    echo_color "$RED" "Erreur : Impossible d'écrire dans $LOG_FILE"
    exit 1
fi

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
# INSTALLATION ET VÉRIFICATION MESSAGERIE
###############################################################################
function check_mailer() {
    if command -v mail &> /dev/null; then
        echo_color "$GREEN" "Le système de messagerie (mail) est déjà installé."
        log_action "INFO" "Système de messagerie déjà installé."
        return 0
    fi

    if [ -n "$SILENT_INSTALL" ]; then
        log_action "INFO" "Mode silencieux activé. Tentative d'installation mail."
        if detect_and_install_mailer; then
            return 0
        else
            echo_color "$RED" "Impossible d'installer automatiquement mail en mode silencieux."
            log_action "ERROR" "Echec mail silent install."
            return 1
        fi
    fi

    echo_color "$YELLOW" "Aucun mail détecté. Installer ? (y/n)"
    read -r INSTALL_MAILER
    if [ "$INSTALL_MAILER" == "y" ]; then
        if detect_and_install_mailer; then
            return 0
        else
            echo_color "$RED" "Échec installation mail. Installez manuellement."
            log_action "ERROR" "Mail install failed."
            return 1
        fi
    else
        echo_color "$RED" "Pas d'outil mail. Pas d'e-mails envoyés."
        log_action "WARN" "Pas de mail, pas d'envoi e-mails."
        return 1
    fi
}

function detect_and_install_mailer() {
    log_action "INFO" "Détection OS pour mail."
    case "$OSTYPE" in
        linux-gnu*)
            if command -v apt-get &> /dev/null; then
                echo_color "$BLUE" "Installation mailutils via apt-get..."
                sudo apt-get update && sudo apt-get install -y mailutils || {
                    echo_color "$RED" "Échec apt-get mailutils."
                    log_action "ERROR" "apt-get mail fail."
                    return 1
                }
            elif command -v yum &> /dev/null; then
                echo_color "$BLUE" "Installation mailx via yum..."
                sudo yum install -y mailx || {
                    echo_color "$RED" "Échec yum mailx."
                    log_action "ERROR" "yum mail fail."
                    return 1
                }
            elif command -v dnf &> /dev/null; then
                echo_color "$BLUE" "Installation mailx via dnf..."
                sudo dnf install -y mailx || {
                    echo_color "$RED" "Échec dnf mailx."
                    log_action "ERROR" "dnf mail fail."
                    return 1
                }
            else
                echo_color "$RED" "Aucun apt/yum/dnf détecté."
                log_action "ERROR" "No pkg manager for mail."
                return 1
            fi
            ;;
        darwin*)
            if command -v brew &> /dev/null; then
                echo_color "$BLUE" "Installation mailutils via brew..."
                brew install mailutils || {
                    echo_color "$RED" "Échec brew mailutils."
                    log_action "ERROR" "brew mail fail."
                    return 1
                }
            else
                echo_color "$YELLOW" "Installez Homebrew puis mailutils manuellement."
                log_action "WARN" "Pas de mail sur mac sans brew."
                return 1
            fi
            ;;
        cygwin*|msys*|win32*)
            echo_color "$RED" "Windows: installez manuellement un outil mail."
            log_action "WARN" "Windows mail non géré."
            return 1
            ;;
        *)
            echo_color "$RED" "OS non reconnu, mail manuellement."
            log_action "ERROR" "Mail OS unsupported."
            return 1
            ;;
    esac

    if command -v mail &> /dev/null; then
        echo_color "$GREEN" "Mail installé."
        log_action "INFO" "Mail installé."
        return 0
    else
        echo_color "$RED" "mail non dispo après install."
        log_action "ERROR" "Mail absent post-install."
        return 1
    fi
}

###############################################################################
# AIDE ET OPTIONS
###############################################################################
function usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options :"
    echo "  -f [files]       Spécifie les fichiers à ajouter"
    echo "  -m [message]     Message de commit (Type: Description)"
    echo "  -b [branch]      Nom de la branche distante pour le push"
    echo "  -p               git pull avant le push"
    echo "  -M [branch]      merge d'une branche avant le push"
    echo "  -r [repo-dir]    Répertoire multi-dépôts"
    echo "  -v               Mode verbeux"
    echo "  -d               Mode dry-run (simulation)"
    echo "  -h               Afficher l'aide"
    echo "  -g               Signer le commit GPG"
    echo "  -R [branch]      Rebase sur cette branche avant le push"
    echo "  -t               Lancer tests avant commit/push"
    echo "  -T [tag_name]    Créer un tag et release"
    echo "  -H               Générer un rapport HTML"
    echo "  -C               Résolution auto des conflits"
    echo "  -k               Gérer les hooks Git"
    echo "  -S               Gérer les sous-modules"
    echo "  -q               Vérifications qualité (lint, sécurité)"
    echo "  -B [branch]      Comparer la branche courante à une autre branche"
    echo "  -P [N]           Exporter les N derniers commits en patch"
    echo "  -x               Nettoyer les branches locales fusionnées"
    echo "  -E               Générer stats de commits"
    echo "  -I               Intégration tickets (lier commit aux tickets JIRA par ex)"
    echo "  -U               Déclencher pipeline CI après push"
    echo "  -L               Loguer la release dans release_history.log"
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

###############################################################################
# TRAITEMENT DES OPTIONS
###############################################################################
function process_options() {
    if [ $# -eq 0 ]; then return; fi

    while getopts ":f:m:b:M:r:vdhpgR:tT:HCkSqB:P:xEILU" opt; do
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
                echo_color "$YELLOW" "Mode simulation (dry-run) activé."
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
            \?)
                echo_color "$RED" "Option invalide : -$OPTARG"
                usage
                ;;
            :)
                echo_color "$RED" "L'option -$OPTARG requiert un argument."
                usage
                ;;
        esac
    done

    shift $((OPTIND -1))
}

###############################################################################
# CHARGEMENT DE LA CONFIG ET CHECK
###############################################################################
function load_config() {
    local env_file="./.env.git_push_automation"

    if [ -f "$env_file" ]; then
        # Activer l'export automatique des variables lues
        set -a
        source "$env_file"
        set +a
        log_action "INFO" "Fichier de configuration chargé : $env_file"
    else
        echo_color "$YELLOW" "Le fichier de configuration $env_file est manquant."
        log_action "WARN" "Fichier de configuration $env_file manquant."
        exit 1
    fi
}

function check_dependencies() {
    local missing_dependencies=()
    local dependencies=("jq" "curl" "git")

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_dependencies+=("$cmd")
        fi
    done

    if [ "${#missing_dependencies[@]}" -ne 0 ]; then
        echo_color "$RED" "Les commandes suivantes sont manquantes : ${missing_dependencies[*]}"
        log_action "ERROR" "Commandes manquantes : ${missing_dependencies[*]}"
        exit 1
    fi

    local git_min_version="2.20.0"
    local git_version
    git_version=$(git --version | awk '{print $3}')
    if [ "$(printf '%s\n' "$git_min_version" "$git_version" | sort -V | head -n1)" != "$git_min_version" ]; then
        echo_color "$RED" "Git version $git_min_version ou supérieure est requise."
        log_action "ERROR" "Version de Git trop ancienne : $git_version"
        exit 1
    fi

    log_action "INFO" "Toutes les dépendances sont satisfaites."
}

function check_permissions() {
    if [ "$EUID" -eq 0 ]; then
        echo_color "$RED" "Veuillez ne pas exécuter ce script en tant que root."
        log_action "ERROR" "Le script a été exécuté en tant que root."
        exit 1
    fi
}

function check_git_repo() {
    if [ ! -d ".git" ]; then
        echo_color "$RED" "Erreur : ce répertoire n'est pas un dépôt Git."
        log_action "ERROR" "Ce répertoire n'est pas un dépôt Git."
        return 1
    fi
    log_action "INFO" "Vérification du dépôt Git réussie."
}

function check_user_email() {
    local email
    email=$(git config --get user.email)
    if [ -z "$email" ]; then
        echo_color "$YELLOW" "Aucune adresse e-mail configurée pour Git."
        echo_color "$YELLOW" "Entrez une adresse e-mail pour configurer Git globalement :"
        read -r email
        if [ -z "$email" ]; then
            echo_color "$RED" "Erreur : L'adresse e-mail ne peut pas être vide."
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
            echo_color "$YELLOW" "Avertissement : '$FILE' n'existe pas."
            log_action "WARN" "Fichier '$FILE' n'existe pas."
        fi
    done

    echo_color "$GREEN" "Sauvegarde terminée dans $BACKUP_DIR"
    log_action "INFO" "Sauvegarde terminée."
}

function add_files() {
    echo_color "$BLUE" "Fichiers modifiés ou nouveaux :"
    git status -s
    log_action "INFO" "Affichage des modifications."

    if [ ${#FILES[@]} -eq 0 ]; then
        echo_color "$YELLOW" "Entrez les fichiers à ajouter (ou '.' pour tous) :"
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
            echo_color "$GREEN" "Simulation : git add ."
        else
            git add .
        fi
    else
        for FILE in "${FILES[@]}"; do
            if [ -e "$FILE" ]; then
                if [ "$DRY_RUN" == "y" ]; then
                    echo_color "$GREEN" "Simulation : git add '$FILE'"
                else
                    git add "$FILE"
                fi
            else
                echo_color "$RED" "Le fichier '$FILE' n'existe pas."
                log_action "ERROR" "Fichier '$FILE' inexistant."
                return 1
            fi
        done
    fi

    if [ "$DRY_RUN" != "y" ]; then
        echo_color "$GREEN" "Fichiers ajoutés :"
        git diff --cached --name-only
    else
        echo_color "$GREEN" "Simulation complète de l'ajout."
    fi
}

function improved_validate_commit_message() {
    # Valide le message de commit selon le format Type: Description
    if [[ ! $COMMIT_MSG =~ ^(Tâche|Bug|Amélioration|Refactor):[[:space:]].+ ]]; then
        echo_color "$RED" "Format invalide."
        echo_color "$YELLOW" "<Type>: <Description> (Types: Tâche, Bug, Amélioration, Refactor)"
        echo_color "$GREEN" "Ex: Tâche: Ajout fonctionnalité X"
        return 1
    fi
    return 0
}

function run_tests() {
    # Vérifier si l'utilisateur veut lancer des tests (RUN_TESTS = "y")
    # et si TEST_COMMAND est défini et non vide dans le fichier de configuration.

    if [ "$RUN_TESTS" == "y" ] && [ -n "$TEST_COMMAND" ]; then
        echo_color "$YELLOW" "Exécution des tests avant le commit..."
        log_action "INFO" "Exécution des tests via : $TEST_COMMAND"

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : $TEST_COMMAND"
            log_action "INFO" "Simulation des tests."
        else
            if ! $TEST_COMMAND; then
                echo_color "$RED" "Les tests ont échoué. Annulation du commit."
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
    local types=("Tâche" "Bug" "Amélioration" "Refactor")
    local type_choice=""
    local commit_description=""

    while true; do
        if [ -n "$COMMIT_MSG" ]; then
            improved_validate_commit_message && break || COMMIT_MSG=""
        fi

        echo_color "$BLUE" "Choisissez le type de commit:"
        PS3="Votre choix (1:Tâche,2:Bug,3:Amélioration,4:Refactor) : "
        select opt in "${types[@]}"; do
            if [[ -n "$opt" ]]; then
                type_choice="$opt"
                break
            else
                echo_color "$RED" "Choix invalide."
            fi
        done

        echo_color "$YELLOW" "Entrez la description du commit :"
        read -r commit_description
        COMMIT_MSG="$type_choice: $commit_description"
        improved_validate_commit_message && break || (echo_color "$RED" "Invalide. Réessayer."; COMMIT_MSG="")
    done

    run_tests

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git commit -m '$COMMIT_MSG'"
        log_action "INFO" "Simul commit : $COMMIT_MSG"
    else
        if [ "$GPG_SIGN" == "y" ]; then
            git commit -m "$COMMIT_MSG" -S
        else
            git commit -m "$COMMIT_MSG"
        fi
        log_action "INFO" "Commit créé : $COMMIT_MSG"
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

        PS3="Sélectionnez une branche : "
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
                echo_color "$RED" "Sélection invalide."
            fi
        done
    fi
    log_action "INFO" "Branche distante cible : $BRANCH_NAME"
}

function check_branch_status() {
    echo_color "$BLUE" "Vérification de l'état de la branche '$BRANCH_NAME'..."
    git fetch origin "$BRANCH_NAME"
    LOCAL=$(git rev-parse "$BRANCH_NAME")
    REMOTE=$(git rev-parse "origin/$BRANCH_NAME")
    BASE=$(git merge-base "$BRANCH_NAME" "origin/$BRANCH_NAME")

    if [ "$LOCAL" == "$REMOTE" ]; then
        echo_color "$GREEN" "La branche '$BRANCH_NAME' est à jour."
    elif [ "$LOCAL" == "$BASE" ]; then
        echo_color "$YELLOW" "La branche '$BRANCH_NAME' est en retard."
    elif [ "$REMOTE" == "$BASE" ]; then
        echo_color "$YELLOW" "La branche '$BRANCH_NAME' est en avance."
    else
        echo_color "$RED" "La branche '$BRANCH_NAME' et la branche distante ont divergé."
        echo_color "$YELLOW" "Voulez-vous fusionner la branche distante dans la branche locale ? (y/n)"
        read -r MERGE_REMOTE
        if [ "$MERGE_REMOTE" == "y" ]; then
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git merge 'origin/$BRANCH_NAME'"
            else
                git merge "origin/$BRANCH_NAME" || {
                    echo_color "$RED" "Erreur lors de la fusion."
                    check_for_conflicts
                    return 1
                }
            fi
        else
            echo_color "$RED" "Opération annulée."
            return 1
        fi
    fi
}

function check_for_conflicts() {
    if git ls-files -u | grep -q .; then
        echo_color "$RED" "Des conflits de fusion détectés."
        if [ "$AUTO_CONFLICT_RES" == "y" ]; then
            # AJOUT: Tentative de résolution auto des conflits (exemple)
            echo_color "$YELLOW" "Tentative de résolution automatique des conflits avec 'git mergetool'..."
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git mergetool --tool=meld"
            else
                git mergetool --tool=meld
                git add -A
                git commit -m "Résolution automatique des conflits"
            fi
        else
            echo_color "$YELLOW" "Voulez-vous les résoudre maintenant ? (y/n)"
            read -r RESOLVE_CONFLICTS
            if [ "$RESOLVE_CONFLICTS" == "y" ]; then
                conflicted_files=$(git diff --name-only --diff-filter=U)
                for file in $conflicted_files; do
                    echo_color "$YELLOW" "Résoudre le conflit dans : $file"
                    ${EDITOR:-nano} "$file"
                    git add "$file"
                done
                git commit -m "Résolution des conflits"
            else
                echo_color "$RED" "Opération annulée en raison de conflits non résolus."
                return 1
            fi
        fi
    fi
}

function stash_changes() {
    if [ -n "$(git status --porcelain)" ]; then
        echo_color "$YELLOW" "Modifs locales détectées. Stasher ? (y/n)"
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
        echo_color "$YELLOW" "Appliquer les stash ? (y/n)"
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

function perform_pull() {
    if [ "$DO_PULL" == "y" ]; then
        echo_color "$YELLOW" "Exécuter git pull..."
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git pull origin '$BRANCH_NAME'"
        else
            git pull origin "$BRANCH_NAME" || {
                echo_color "$RED" "Erreur lors du pull."
                check_for_conflicts
                return 1
            }
        fi
    else
        echo_color "$YELLOW" "Voulez-vous faire un pull ? (y/n)"
        read -r PULL_ANSWER
        if [ "$PULL_ANSWER" == "y" ]; then
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git pull origin '$BRANCH_NAME'"
            else
                git pull origin "$BRANCH_NAME" || {
                    echo_color "$RED" "Erreur lors du pull."
                    check_for_conflicts
                    return 1
                }
            fi
        fi
    fi
}

function perform_merge() {
    if [ "$DO_MERGE" == "y" ]; then
        echo_color "$YELLOW" "Merge de '$MERGE_BRANCH'..."
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git merge '$MERGE_BRANCH'"
        else
            git merge "$MERGE_BRANCH" || {
                echo_color "$RED" "Erreur lors du merge."
                check_for_conflicts
                return 1
            }
        fi
    else
        echo_color "$YELLOW" "Voulez-vous merger une autre branche ? (y/n)"
        read -r MERGE_ANSWER
        if [ "$MERGE_ANSWER" == "y" ]; then
            echo_color "$YELLOW" "Entrez le nom de la branche à merger :"
            read -r MERGE_BRANCH
            if [ "$DRY_RUN" == "y" ]; then
                echo_color "$GREEN" "Simulation : git merge '$MERGE_BRANCH'"
            else
                git merge "$MERGE_BRANCH" || {
                    echo_color "$RED" "Erreur lors du merge."
                    check_for_conflicts
                    return 1
                }
            fi
        fi
    fi
}

function perform_rebase() {
    # AJOUT: Rebase sur une branche donnée avant le push
    if [ -n "$REBASE_BRANCH" ]; then
        echo_color "$YELLOW" "Rebase sur la branche '$REBASE_BRANCH'..."
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git rebase '$REBASE_BRANCH'"
        else
            git fetch origin "$REBASE_BRANCH"
            git rebase "origin/$REBASE_BRANCH" || {
                echo_color "$RED" "Erreur lors du rebase."
                check_for_conflicts
                return 1
            }
        fi
    fi
}

function perform_push() {
    while true; do
        echo ""
        echo -n "Pousser sur '$BRANCH_NAME' ? (y/n) "
        read CONFIRM_PUSH
        case "$CONFIRM_PUSH" in
            y|Y) break ;;
            n|N) echo_color "$RED" "Opération annulée."; return 1 ;;
            *) echo_color "$RED" "Réponse invalide." ;;
        esac
    done

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git push origin '$BRANCH_NAME'"
    else
        git push origin "$BRANCH_NAME" || {
            echo_color "$RED" "Erreur lors du push."
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
        echo_color "$GREEN" "Tag '$TAG_NAME' créé et poussé."
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
        echo_color "$RED" "Format d'URL du dépôt non supporté : $repo_url"
        log_action "ERROR" "Format d'URL du dépôt non supporté : $repo_url"
        # On ne bloque pas ici, mais pas de création de release si URL non supportée.
    fi

    local project_name
    project_name=$(basename "$web_repo_url")
    local commit_url="${web_repo_url}/commit/${commit_hash}"

    # AJOUT: Création d'une Release GitLab si un tag est présent et si GITLAB_PROJECT_ID et GITLAB_TOKEN sont disponibles
    if [ -n "$TAG_NAME" ] && [ -n "$GITLAB_PROJECT_ID" ] && [ -n "$GITLAB_TOKEN" ] && [ "$DRY_RUN" != "y" ]; then
        local gitlab_api_url="https://gitlab.com/api/v4"
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
        body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

        if [ "$http_status" -eq 201 ]; then
            echo_color "$GREEN" "Release GitLab créée avec succès pour le tag $TAG_NAME."
            log_action "INFO" "Release GitLab créée avec succès."
        else
            echo_color "$RED" "Erreur lors de la création de la release GitLab. Statut HTTP : $http_status"
            echo_color "$RED" "Réponse : $body"
            log_action "ERROR" "Erreur lors de la création de la release GitLab. Statut : $http_status, Réponse : $body"
        fi
    else
        log_action "INFO" "Pas de création de release GitLab (TAG_NAME, GITLAB_PROJECT_ID, GITLAB_TOKEN manquants ou DRY_RUN activé)."
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
        echo_color "$GREEN" "Poussée réussie sur '$BRANCH_NAME'."
    else
        echo_color "$GREEN" "Simulation de push réussie."
    fi
}

###############################################################################
# PLATFORM-AGNOSTIC ABSTRACTION
# VARIABLE PLATFORM DOIT ÊTRE DÉFINIE DANS LE FICHIER DE CONFIGURATION
# (ex: export PLATFORM="github" ou "gitlab" ou "bitbucket" etc.)
# SELON PLATFORM, ON APPELLE LES FONCTIONS SPÉCIFIQUES
###############################################################################

function notify_platform_after_push() {
    local commit_hash="$1"
    local project_name="$2"
    local commit_url="$3"

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
        github)
            [ -z "$GITHUB_TOKEN" ] && { log_action "WARN" "GITHUB_TOKEN manquant pour GitHub."; return; }
            [ -z "$GITHUB_REPO" ] && { log_action "WARN" "GITHUB_REPO manquant."; return; }
            notify_github "$message" "$commit_hash"
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
        github)
            [ -z "$GITHUB_TOKEN" ] && { log_action "WARN" "Pas de GITHUB_TOKEN."; return; }
            [ -z "$GITHUB_REPO" ] && { log_action "WARN" "Pas de GITHUB_REPO."; return; }
            create_github_release "$tag_name" "$description"
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
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -ne 201 ]; then
        echo_color "$RED" "Erreur notif GitLab HTTP:$http_status"
        echo_color "$RED" "Réponse: $body"
        log_action "ERROR" "GitLab notif fail $http_status $body"
    else
        echo_color "$GREEN" "Notif GitLab OK."
        log_action "INFO" "Notif GitLab OK"
    fi
}

function create_gitlab_release() {
    local tag_name="$1"
    local description="$2"
    local gitlab_api_url="https://gitlab.com/api/v4"
    local release_name="Release $(date '+%Y-%m-%d %H:%M:%S')"

    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$(jq -n --arg tag "$tag_name" --arg name "$release_name" --arg desc "$description" '{ tag_name: $tag, name: $name, description: $desc }')" \
        "$gitlab_api_url/projects/$GITLAB_PROJECT_ID/releases")

    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -eq 201 ]; then
        echo_color "$GREEN" "Release GitLab créée."
        log_action "INFO" "Release GitLab OK"
    else
        echo_color "$RED" "Erreur release GitLab:$http_status"
        echo_color "$RED" "Réponse: $body"
        log_action "ERROR" "GitLab release fail $http_status $body"
    fi
}

#### NOTIFICATION GITHUB ####
function notify_github() {
    local message="$1"
    local commit_hash="$2"
    local github_api_url="https://api.github.com"
    
    # Encodage du message pour éviter les problèmes de caractères spéciaux
    local encoded_message
    encoded_message=$(echo "$message" | jq -Rs '.')  # -R (raw), -s (slurp)

    # Appel à l’API GitHub pour ajouter un commentaire sur le commit
    # (on suppose que GITHUB_TOKEN et GITHUB_REPO sont déjà définis)
    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        --request POST \
        --header "Authorization: token $GITHUB_TOKEN" \
        --header "Accept: application/vnd.github+json" \
        --header "Content-Type: application/json" \
        --data "{\"body\": $encoded_message}" \
        "$github_api_url/repos/$GITHUB_REPO/commits/$commit_hash/comments")

    # Récupération du code HTTP et du corps de la réponse
    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    # Vérification du statut
    if [ "$http_status" -ne 201 ]; then
        echo_color "$RED" "Erreur notif GitHub HTTP:$http_status"
        echo_color "$RED" "Réponse: $body"
        log_action "ERROR" "GitHub notif fail $http_status $body"
    else
        echo_color "$GREEN" "Notif GitHub OK."
        log_action "INFO" "Notif GitHub OK"
    fi
}

function create_github_release() {
    local tag_name="$1"
    local description="$2"
    local release_name="$tag_name"

    # https://docs.github.com/en/rest/releases/releases#create-a-release
    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"tag_name\":\"$tag_name\",\"name\":\"$release_name\",\"body\":\"$description\"}" \
        "https://api.github.com/repos/$GITHUB_REPO/releases")

    http_status=$(echo "$response" | tr -d '\n' | sed 's/.*HTTPSTATUS://')
    body=$(echo "$response" | sed 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -eq 201 ]; then
        echo_color "$GREEN" "Release GitHub créée."
        log_action "INFO" "Release GitHub OK"
    else
        echo_color "$RED" "Erreur release GitHub:$http_status"
        echo_color "$RED" "Réponse: $body"
        log_action "ERROR" "GitHub release fail $http_status $body"
    fi
}

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
        echo_color "$GREEN" "Simulation : Notification Bitbucket (ajout d'un commentaire sur le commit $commit_hash)."
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
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -eq 201 ]; then
        echo_color "$GREEN" "Notification Bitbucket envoyée."
        log_action "INFO" "Notification Bitbucket OK"
    else
        echo_color "$RED" "Erreur notif Bitbucket: HTTP $http_status"
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
        echo_color "$GREEN" "Simulation : Création de 'release' Bitbucket en créant un tag '$tag_name'."
        echo "Description : $description"
        return
    fi

    # Endpoint pour créer un tag sur Bitbucket Cloud:
    # POST /2.0/repositories/{workspace}/{repo_slug}/refs/tags
    # Exemple de payload :
    {
      "name": "v1.0.0",
       "target": {
           "hash": "commit_hash"
       },
       "message": "Description de la release"
    }

    local bitbucket_api_url="https://api.bitbucket.org/2.0/repositories/$BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG/refs/tags"

    response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        --user "$BITBUCKET_USER:$BITBUCKET_APP_PASSWORD" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "$(jq -n --arg tag "$tag_name" --arg desc "$description" --arg hash "$commit_hash" '{ name: $tag, target: {hash: $hash}, message: $desc }')" \
        "$bitbucket_api_url")

    http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [ "$http_status" -eq 201 ]; then
        echo_color "$GREEN" "Tag '$tag_name' créé sur Bitbucket (équivalent 'release')."
        log_action "INFO" "Bitbucket tag/release OK"
    else
        echo_color "$RED" "Erreur création tag Bitbucket: HTTP $http_status"
        echo_color "$RED" "Réponse : $body"
        log_action "ERROR" "Bitbucket release fail $http_status $body"
    fi
}

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
                        "fields": [
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
            }')

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : Notification Slack."
            echo "$slack_payload"
            log_action "INFO" "Simulation notif Slack."
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H 'Content-type: application/json' --data "$slack_payload" "$SLACK_WEBHOOK_URL")
            if [ "$response" != "200" ]; then
                echo_color "$RED" "Erreur notif Slack (HTTP $response)."
                log_action "ERROR" "Slack notif fail HTTP $response"
            else
                echo_color "$GREEN" "Notification Slack envoyée."
                log_action "INFO" "Notif Slack OK."
            fi
        fi
    else
        log_action "INFO" "SLACK_WEBHOOK_URL non défini, pas de notif Slack."
    fi

    #### Notification GitHub ####
    if [ -n "$GITHUB_TOKEN" ]; then
        local github_message="$common_message"
        local github_api_url="https://api.github.com/repos/$GITHUB_REPO/commits/$commit_hash/comments"

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : Notification GitHub."
            echo "POST $github_api_url"
            echo "Data: $github_message"
        else
            # On échappe correctement le message via jq (lecture en mode 'raw' puis conversion JSON)
            local encoded_github_message
            encoded_github_message=$(echo "$github_message" | jq -Rs '.')

            # On l'utilise ensuite dans le champ "body"
            response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
                --request POST \
                --header "Authorization: token $GITHUB_TOKEN" \
                --header "Content-Type: application/json" \
                --data "{\"body\": $encoded_github_message}" \
                "$github_api_url")

            http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
            body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

            if [ "$http_status" -ne 201 ]; then
                echo_color "$RED" "Erreur notif GitHub HTTP:$http_status"
                echo_color "$RED" "Réponse : $body"
                log_action "ERROR" "GitHub notif fail $http_status $body"
            else
                echo_color "$GREEN" "Notification GitHub OK."
                log_action "INFO" "Notif GitHub OK."
            fi
        fi
    else
        log_action "INFO" "GITHUB_TOKEN non défini, pas de notif GitHub."
    fi


    #### Notification GitLab ####
    if [ -n "$GITLAB_PROJECT_ID" ] && [ -n "$GITLAB_TOKEN" ]; then
        local gitlab_message="$common_message"
        local gitlab_api_url="https://gitlab.com/api/v4"
        local encoded_message
        encoded_message=$(jq -Rn --arg msg "$gitlab_message" '$msg')

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : Notification GitLab."
            echo "POST $gitlab_api_url/projects/$GITLAB_PROJECT_ID/repository/commits/$commit_hash/comments"
            echo "Data: $gitlab_message"
        else
            response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" --request POST \
                --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                --header "Content-Type: application/json" \
                --data "{\"note\": $encoded_message}" \
                "$gitlab_api_url/projects/$GITLAB_PROJECT_ID/repository/commits/$commit_hash/comments")

            http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
            body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

            if [ "$http_status" -ne 201 ]; then
                echo_color "$RED" "Erreur notif GitLab HTTP:$http_status"
                echo_color "$RED" "Réponse : $body"
                log_action "ERROR" "GitLab notif fail $http_status $body"
            else
                echo_color "$GREEN" "Notification GitLab OK."
                log_action "INFO" "Notif GitLab OK."
            fi
        fi
    else
        log_action "INFO" "GITLAB_PROJECT_ID ou GITLAB_TOKEN non défini, pas de notif GitLab."
    fi

    #### Notification Email ####
    if [ -n "$EMAIL_RECIPIENTS" ]; then
        check_mailer
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
                echo_color "$GREEN" "Simulation : e-mail à $EMAIL_RECIPIENTS"
                echo_color "$GREEN" "Sujet : $subject"
                echo "$email_body"
            else
                echo "$email_body" | mail -s "$subject" "$EMAIL_RECIPIENTS"
                if [ $? -eq 0 ]; then
                    echo_color "$GREEN" "Email envoyé à : $EMAIL_RECIPIENTS"
                    log_action "INFO" "Email envoyé."
                else
                    echo_color "$RED" "Erreur envoi e-mail."
                    log_action "ERROR" "Email fail."
                fi
            fi
        fi
    else
        log_action "INFO" "EMAIL_RECIPIENTS non défini, pas d'e-mail."
    fi

    #### Notification Mattermost ####
    if [ -n "$MATTERMOST_WEBHOOK_URL" ]; then
        local mm_message="**Nouveau push** sur *$BRANCH_NAME* par $email_user.
Commit: \`$commit_hash\`.
[Voir le commit sur le remote](${repo_url})"

        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : Notification Mattermost."
        else
            curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$mm_message\"}" "$MATTERMOST_WEBHOOK_URL" || {
                echo_color "$RED" "Erreur notif Mattermost."
                log_action "ERROR" "Mattermost fail."
            }
        fi
        log_action "INFO" "Notif Mattermost OK."
    else
        log_action "INFO" "MATTERMOST_WEBHOOK_URL non défini."
    fi

    echo ""
    echo_color "$GREEN" "------------- FIN DU RAPPORT -------------"
}

function send_custom_webhook() {
    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        log_action "WARN" "SLACK_WEBHOOK_URL non défini."
        return
    fi

    local email=$(git config --get user.email)
    local payload="{\"message\": \"Nouveau push sur $BRANCH_NAME par $email.\"}"
    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : custom webhook"
    else
        curl -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL" || {
            log_action "ERROR" "Erreur lors de l'envoi du webhook personnalisé."
        }
    fi
    log_action "INFO" "Webhook personnalisé envoyé."
}

function generate_report() {
    # AJOUT: Générer un rapport HTML local plus professionnel
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
                    echo_color "$BLUE" "Début des opérations sur le dépôt dans $dir"
                    log_action "INFO" "Opérations sur le dépôt dans $dir"
                    cd "$dir" || { echo_color "$RED" "Erreur : Impossible de cd vers $dir"; exit 1; }
                    main_without_repo_dir "$@"
                ) &
            fi
        done
        wait
    else
        echo_color "$RED" "Le répertoire spécifié n'existe pas : $repo_dir"
        log_action "ERROR" "Le répertoire spécifié n'existe pas : $repo_dir"
        exit 1
    fi
}

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

##############################################################################
# 3. Historique et Statistiques de commits
# On extrait plus d’infos, par exemple le nombre de commits par type, le top 3 des auteurs, etc.
###############################################################################
function generate_commit_stats() {
    echo_color "$BLUE" "Génération de statistiques de commits..."

    # Créer le répertoire stats s'il n'existe pas
    mkdir -p stats

    # Générer le fichier dans le dossier stats
    local stats_file="stats/commit_stats.md"

    # Top 3 des auteurs sur les 30 derniers commits
    echo "## Statistiques de commits" > "$stats_file"
    echo "### Top Auteurs (30 derniers commits):" >> "$stats_file"
    git shortlog -n -s -e -30 | head -n 3 >> "$stats_file"

    # Compter le nombre de commits par type (Tâche, Bug, etc.)
    echo "### Nombre de commits par type (30 derniers):" >> "$stats_file"
    for t in "Tâche" "Bug" "Amélioration" "Refactor"; do
        count=$(git log -30 --pretty=%s | grep "^$t:" | wc -l)
        echo "- $t : $count" >> "$stats_file"
    done

    log_action "INFO" "Statistiques de commits générées dans $stats_file"
    echo_color "$GREEN" "Statistiques de commits générées dans $stats_file"
}


##############################################################################
# 4. Intégration avec un Système de Tickets
# On suppose que le message de commit peut contenir un ID de ticket (ex: JIRA-123)
# on va l’extraire et ajouter un lien dans Slack et dans le rapport.
###############################################################################
function link_tickets() {
    # Hypothèse : Le message de commit est dans COMMIT_MSG
    if [[ $COMMIT_MSG =~ ([A-Z]+-[0-9]+) ]]; then
        local ticket_id="${BASH_REMATCH[1]}"
        # Supposons un lien vers JIRA
        local ticket_url="https://jira.example.com/browse/$ticket_id"
        log_action "INFO" "Ticket détecté : $ticket_id"

        # Enregistrer ce ticket pour utilisation dans Slack ou rapport
        TICKET_URL="$ticket_url"
    fi
}

###############################################################################
# 5. Vérifications de Qualité (Linting, Sécurité)
# Fonction avancée: exécuter un linter (ex: ESLint) et un scan de sécurité (ex: npm audit)
###############################################################################
function run_quality_checks() {
    if [ -n "$QUALITY_COMMAND" ]; then
        echo_color "$YELLOW" "Exécution des vérifications qualité via : $QUALITY_COMMAND"
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : $QUALITY_COMMAND"
        else
            # Vérifier si l'outil de qualité (par ex: npm) est dispo
            if ! command -v npm &>/dev/null; then
                echo_color "$RED" "npm non installé, impossible de lancer 'npm run lint'. Saut de la vérification."
                log_action "WARN" "npm non dispo, saut lint."
            else
                if ! $QUALITY_COMMAND; then
                    echo_color "$RED" "Vérifications qualité échouées. Annulation."
                    log_action "ERROR" "Echec qualité."
                    exit 1
                else
                    echo_color "$GREEN" "Qualité OK."
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
            if [ $? -ne 0 ]; then
                echo_color "$RED" "Audit sécurité échoué (npm audit). Annulation."
                log_action "ERROR" "Audit sécurité fail."
                exit 1
            fi
            echo_color "$GREEN" "Audit npm OK."
            log_action "INFO" "Audit npm OK."
        fi
    fi

    # Vérification git-secrets
    if command -v git-secrets &>/dev/null; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : git-secrets --scan"
        else
            git-secrets --scan
            if [ $? -ne 0 ]; then
                echo_color "$RED" "git-secrets a détecté des secrets ! Annulation."
                log_action "ERROR" "Secrets détectés."
                exit 1
            fi
            echo_color "$GREEN" "Aucun secret détecté (git-secrets)."
            log_action "INFO" "Aucun secret."
        fi
    else
        echo_color "$YELLOW" "git-secrets non installé, saut de cette vérification."
        log_action "WARN" "git-secrets absent."
    fi

    # Vérification bandit (Python)
    if command -v bandit &>/dev/null && [ -f requirements.txt ]; then
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : bandit -r ."
        else
            bandit -r .
            if [ $? -ne 0 ]; then
                echo_color "$RED" "Analyse bandit échouée (problèmes de sécurité Python). Annulation."
                log_action "ERROR" "Bandit fail."
                exit 1
            fi
            echo_color "$GREEN" "Analyse bandit OK (pas de vulnérabilités Python graves)."
            log_action "INFO" "Bandit OK."
        fi
    else
        echo_color "$YELLOW" "bandit non installé ou pas de requirements.txt, saut de l'analyse Python."
        log_action "WARN" "bandit absent ou pas de code Python."
    fi
}

##############################################################################
# 6. Comparaison entre Branches
# On va afficher un diff plus complet, éventuellement lister les commits en plus sur l’autre branche.
###############################################################################
function compare_branches() {
    echo_color "$YELLOW" "Comparaison de '$BRANCH_NAME' avec '$COMPARE_BRANCH'..."
    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git log $BRANCH_NAME..$COMPARE_BRANCH --oneline"
    else
        echo_color "$BLUE" "Commits dans $COMPARE_BRANCH non présents dans $BRANCH_NAME:"
        git log --oneline "$BRANCH_NAME..$COMPARE_BRANCH"
        echo_color "$BLUE" "Diff entre les deux branches:"
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
    echo_color "$YELLOW" "Export de $count commits en patches dans le répertoire './patches'."

    # Créer le répertoire patches s'il n'existe pas
    mkdir -p "./patches"

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$GREEN" "Simulation : git format-patch -$count HEAD -o ./patches"
    else
        git format-patch -$count HEAD -o ./patches
        echo_color "$GREEN" "Patches créés dans ./patches."
    fi
    log_action "INFO" "$count patches exportés dans ./patches."
}

##############################################################################
# 8. Intégration d’un Système de Build/CI
# Fonction avancée: après le push, appeler un endpoint CI
###############################################################################
function trigger_ci() {
    if [ -n "$CI_TRIGGER_URL" ]; then
        echo_color "$YELLOW" "Déclenchement du pipeline CI..."
        if [ "$DRY_RUN" == "y" ]; then
            echo_color "$GREEN" "Simulation : curl -X POST $CI_TRIGGER_URL"
        else
            # Possibilité d'envoyer un token avec --header "CI-Token: ..."
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$CI_TRIGGER_URL")
            if [ "$response" != "200" ]; then
                echo_color "$RED" "Échec du déclenchement CI (HTTP $response)."
                log_action "ERROR" "CI fail."
            else
                echo_color "$GREEN" "Pipeline CI déclenché avec succès."
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
    echo_color "$YELLOW" "Nettoyage des branches locales fusionnées..."
    local main_branch="main"
    git branch | grep -v "$main_branch" | while read b; do
        # Vérifier si fusionnée
        git branch --merged $main_branch | grep -q " $b$" && {
            echo_color "$BLUE" "Branch $b est fusionnée, suppression ? (y/n)"
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
    local action_names=("Sauvegarder les fichiers" "Ajouter des fichiers" "Créer un commit" "Gérer les branches" "Cacher les modifications locales" "Effectuer un pull" "Rebase" "Vérifier l'état de la branche" "Effectuer un merge" "Effectuer un push" "Appliquer modifications sauvegardées")
    local total_actions=${#actions[@]}
    local current_action=0

    while [ "$current_action" -lt "$total_actions" ]; do
        display_header
        echo_color "$GREEN" "Action par défaut : ${action_names[$current_action]}"
        echo_color "$YELLOW" "Appuyez sur Entrée pour exécuter ou 'n' pour le menu"
        read -rp "> " user_choice

        if [ -z "$user_choice" ]; then
            ${actions[$current_action]}
            action_status=$?
            if [ $action_status -ne 0 ]; then
                echo_color "$RED" "Erreur lors de '${action_names[$current_action]}'. Réessayer ? (y/n)"
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
            echo_color "$RED" "Option invalide."
        fi
    done
}

function main_without_repo_dir() {
    echo_color "$GREEN" "Début opérations sur dépôt courant."
    check_git_repo || exit 1
    check_user_email || exit 1

    if [ "$DRY_RUN" == "y" ]; then
        echo_color "$YELLOW" "Simulation activée."
    fi

    # Appeler manage_hooks si MANAGE_HOOKS == "y"
    if [ "$MANAGE_HOOKS" == "y" ]; then
        manage_hooks
    fi

    # Appeler handle_submodules si MANAGE_SUBMODULES == "y"
    if [ "$MANAGE_SUBMODULES" == "y" ]; then
        handle_submodules
    fi

    # Appeler generate_commit_stats si GENERATE_COMMIT_STATS == "y"
    if [ "$GENERATE_COMMIT_STATS" == "y" ]; then
        generate_commit_stats
    fi

    # Appeler link_tickets si LINK_TICKETS == "y"
    if [ "$LINK_TICKETS" == "y" ]; then
        link_tickets
    fi

    # Appeler run_quality_checks si RUN_QUALITY_CHECKS == "y"
    if [ "$RUN_QUALITY_CHECKS" == "y" ]; then
        run_quality_checks
    fi

    # Si COMPARE_BRANCH n'est pas vide, comparer
    if [ -n "$COMPARE_BRANCH" ]; then
        compare_branches
    fi

    # Si EXPORT_PATCHES == "y", exporter
    if [ "$EXPORT_PATCHES" == "y" ]; then
        export_patches
    fi

    # On ne déclenche CI et log release qu'après le push, donc ces fonctions seront appelées post-push
    # On fera trigger_ci et log_release après perform_push dans ce cas (à adapter selon la logique voulue)
    # Idem pour le nettoyage des branches: après la séquence par défaut, par exemple dans collect_feedback.

    default_actions_sequence
}

function main_menu() {
    local current_action=$1
    while true; do
        display_header
        echo_color "$YELLOW" "Menu principal :"
        echo_color "$BLUE" "1. Sauvegarder les fichiers"
        echo_color "$BLUE" "2. Ajouter des fichiers"
        echo_color "$BLUE" "3. Créer un commit"
        echo_color "$BLUE" "4. Gérer les branches"
        echo_color "$BLUE" "5. Effectuer un pull"
        echo_color "$BLUE" "6. Effectuer un merge"
        echo_color "$BLUE" "7. Effectuer un push"
        echo_color "$BLUE" "8. Quitter"
        echo ""
        echo_color "$YELLOW" "Entrée: Continuer la séquence"
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
                echo_color "$GREEN" "Merci d'avoir utilisé ce script !"
                exit 0
                ;;
            *) echo_color "$RED" "Option invalide." ;;
        esac

        echo_color "$YELLOW" "Revenir à la séquence par défaut ? (y/n)"
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

    echo_color "$YELLOW" "Des commentaires sur le script ? (y/n)"
    read -r FEEDBACK_RESPONSE
    if [ "$FEEDBACK_RESPONSE" == "y" ]; then
        echo_color "$YELLOW" "Entrez vos commentaires :"
        read -r USER_FEEDBACK
        echo "$(date '+%Y-%m-%d %H:%M:%S') : $USER_FEEDBACK" >> feedback.log
        echo_color "$GREEN" "Merci pour votre feedback !"
        log_action "INFO" "Feedback collecté."
    fi
}


###############################################################################
# MAIN
###############################################################################
function main() {
    echo_color "$BLUE$BOLD" "Lancement du script (Version $SCRIPT_VERSION)."
    log_action "INFO" "Démarrage du script v$SCRIPT_VERSION"
    process_options "$@"
    log_action "INFO" "Options : $*"

    load_config
    check_dependencies
    check_permissions
    check_git_repo || exit 1
    check_user_email || exit 1

    if [ -n "$MULTI_REPO_DIR" ]; then
        handle_multiple_repositories "$MULTI_REPO_DIR" "$@"
        exit 0
    fi

    if [ $# -eq 0 ]; then
        main_without_repo_dir
    else
        main_without_repo_dir "$@"
    fi

    if [ "$DRY_RUN" != "y" ]; then
        echo_color "$GREEN" "Vérifiez la plateforme distante pour les modifications."
    else
        echo_color "$YELLOW" "Simulation terminée, aucune modification réelle."
    fi

    collect_feedback
}

main "$@"