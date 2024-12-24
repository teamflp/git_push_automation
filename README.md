# Documentation Complète du Script

**Nom** : Git Push Automation – Version Avancée\
**Version** : 1.1.0\
**Auteur** : Paterne G. G.\
**Email** : [paterne81@hotmail.fr](mailto:paterne81@hotmail.fr)\
**Pour** : Équipe DevOps / Dev

---

## 1. Introduction

Le script **Git Push Automation – Version Avancée** est un outil en Bash qui facilite et renforce le processus de *push* Git en ajoutant :

- Un flux par défaut (sauvegarde, ajout, commit, et push).
- Des options avancées :
  - Gestion de hooks (pre-commit, pre-push).
  - Gestion de sous-modules.
  - Tests automatisés, statistiques de commits, liens vers tickets.
  - Vérifications de qualité (lint, sécurité, etc.).
  - Comparaison de branches, export de patches.
  - Notifications (Slack, e-mail, Mattermost) et intégration avec GitLab, GitHub, Bitbucket.
  - Génération de rapport HTML enrichi.
  - Nettoyage automatisé de branches fusionnées, etc.
- Une fiabilité et robustesse accrues (messages d’erreurs explicites, logs, mode `dry-run`, etc.).
- Une configuration flexible via un fichier `.env_git_push_automation` (ou `.env.git_push_automation`).

Le script peut être utilisé en mode interactif (menus et questions) ou en mode non-interactif (avec des options). Il s’adapte aussi bien aux petits dépôts qu’aux projets plus complexes (multi-dépôts).

---

## 2. Prérequis

- **Système d’exploitation** : Linux, macOS, ou un environnement compatible Bash (ex: Git Bash sous Windows).
- **Git** ≥ 2.20.0 (le script vérifie et alerte si la version est trop ancienne).
- **Outils recommandés** (selon vos besoins) :
  - `jq` et `curl` : pour analyser du JSON et envoyer des requêtes HTTP (notamment Slack, GitLab, GitHub).
  - `mailutils` / `mailx` : pour l’envoi d’e-mails automatisés.
  - `npm` : si vous lancez des tests/lint JavaScript, ou `bandit` si vous utilisez Python et souhaitez faire une analyse de sécurité.
  - `git-secrets` : pour vérifier la présence de secrets dans le code avant commit/push.

Si certains outils ne sont pas installés, le script s’adapte (il saute certaines étapes ou prévient l’utilisateur).

---

## 3. Installation

### 3.1. Se positionner à la racine de votre projet

```bash
cd /chemin/vers/votre/projet
```

### 3.2. Méthode A (Installation globale recommandée)

Télécharger le script dans un répertoire global (ex: `/usr/local/bin`) afin de l’exécuter depuis n’importe où :

```bash
sudo curl -L \
  https://raw.githubusercontent.com/teamflp/git_push_automation/master/git_push_automation.sh \
  -o /usr/local/bin/git_push_automation
```

### Rendre le script exécutable

```bash
sudo chmod +x /usr/local/bin/git_push_automation
```

Vous pouvez maintenant utiliser la commande  pour vérifier le fonctionnement du script:

```bash
git_push_automation -h
```

> **Astuce** : Placez un fichier `.env.git_push_automatio` à la racine de **chaque projet** pour personnaliser la configuration du script (tokens, variables, etc.).

---

Ainsi, même si vous avez installé le script globalement, le script chargera la configuration **dans le dossier courant** où vous exécutez la commande.

---

## 5. Vérification de fonctionnement

Pour vérifier le bon fonctionnement, vous pouvez exécuter :

```bash
git_push_automation.sh -h
```

(s’il est installé correctement) :

Vous verrez alors l’aide avec la liste des options disponibles.

## **4. Configuration** : `.env.git_push_automation`

- Par défaut, le script cherche un fichier `.env.git_push_automatio` à la racine.

- Vous pouvez copier l’exemple fourni (s’il y en a un) ou créer votre propre fichier.

- Dans ce fichier, vous pouvez définir des variables comme `SLACK_WEBHOOK_URL`, `GITLAB_PROJECT_ID`, `GITLAB_TOKEN`, `EMAIL_RECIPIENTS`, `TEST_COMMAND`, `QUALITY_COMMAND`, etc.

Rénommez le le fichier `.env_git_push_automation.exemple` en `.env_git_push_automation` . Le script charge automatiquement les variables d’environnement depuis le fichier `.env_git_push_automation.` Par exemple :

```plaintext
########################################################################################
#                               .env.git_push_automation                               #
########################################################################################
# URL du webhook Slack (nouveau format Slack App recommandé)
# Remplacez ci-dessous par l'URL de votre webhook Slack
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/XXXXXXX/XXXXXXX/XXXXXXXXXXXXXXXXXX"

# Canal Slack où envoyer les notifications (ex: #develop)
SLACK_CHANNEL="#mon-canal"

# Nom d'utilisateur affiché par le bot Slack
SLACK_USERNAME="webhookbot"

# Emoji du bot (ex :ghost: ou :robot_face:)
SLACK_ICON_EMOJI=":ghost:"

########################################################################################
#                               PARAMETRAGE GITLAB                                     #
########################################################################################
# ID du projet sur GitLab (visible dans l'URL du projet ou dans les réglages)
GITLAB_PROJECT_ID="12345678"

# Jeton d'accès personnel GitLab avec le scope 'api'
# Générer sur GitLab dans votre profil -> Settings -> Access Tokens
GITLAB_TOKEN="glpat-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Nom du groupe GitLab (optionnel)
GITLAB_GROUP_NAME="mon-groupe"

########################################################################################
#                               PARAMETRAGE EMAIL                                      #
########################################################################################
# Destinataires des e-mails séparés par des virgules (ex : "dev1@example.com,dev2@example.com")
EMAIL_RECIPIENTS="dev@example.com"

# Mode silencieux pour l'installation du mailer (1 = oui, 0 = non)
SILENT_INSTALL=1

########################################################################################
#                               PARAMETRAGE TESTS                                      #
########################################################################################
# COMMANDES DE TEST
# Indiquez la commande à exécuter avant le commit/push pour valider le code.
# Si cette commande échoue (code retour != 0), le push est annulé.
# Exemples :
# TEST_COMMAND="./run_tests.sh"
# TEST_COMMAND="npm test"
TEST_COMMAND="./run_tests.sh"

########################################################################################
#                               PARAMETRAGE QUALITE/LINTING                            #
########################################################################################
# COMMANDES DE QUALITÉ
# Indiquez la commande à exécuter pour lancer un linter ou un outil de contrôle qualité.
# Par exemple : QUALITY_COMMAND="npm run lint"
# Le script exécutera cette commande avant le commit (si -q est utilisé).
# QUALITY_COMMAND="npm run lint"

########################################################################################
#                                PARAMETRAGE CI/CD                                     #
########################################################################################
# URL pour déclencher un pipeline CI après le push (facultatif)
# Ex : CI_TRIGGER_URL="https://ci.example.com/trigger?token=XYZ"
# CI_TRIGGER_URL=""

########################################################################################
#                            PARAMETRAGE DES PLATEFORMES GIT                           #
########################################################################################
# Choisissez la plateforme cible : gitlab, github, bitbucket
PLATFORM="gitlab"

########################################################################################
#                      PARAMETRAGE BITBUCKET/GITHUB (Optionnel)                       #
########################################################################################
# BITBUCKET (si PLATFORM=bitbucket)
# BITBUCKET_WORKSPACE="monworkspace"
# BITBUCKET_REPO_SLUG="monrepo"
# BITBUCKET_USER="monuser"
# BITBUCKET_APP_PASSWORD="monAppPassword"

# GITHUB (si PLATFORM=github)
# GITHUB_TOKEN="ghp_votreToken"
# GITHUB_REPO="username/myrepo"

########################################################################################
#                         PARAMETRAGE TICKETS (Optionnel)                              #
########################################################################################
# Si vous avez un système de tickets (ex: JIRA) et voulez détecter un pattern dans le commit
# Ajoutez ici l'URL de base. Le script détectera par ex. ABC-123 dans le commit
# et proposera un lien https://jira.example.com/browse/ABC-123
# TICKET_BASE_URL="https://jira.example.com/browse/"

########################################################################################
#                             FIN DE LA CONFIGURATION                                  #
########################################################################################
```

En l'absence de certaines variables, les fonctionnalités associées seront ignorées ou dégradées.

## 5. Utilisation

### 5.1. Exécution simple (flux interactif)

Sans aucune option, le script propose un flux par défaut :

```plaintext
./git_push_automation.sh
```

Celui-ci :

1. Vérifie le dépôt Git, la configuration utilisateur (e-mail), etc.
2. Demande si vous souhaitez gérer des hooks, des sous-modules, générer des stats…
3. Vous invite à sauvegarder, ajouter des fichiers, rédiger un message de commit, etc.
4. Gère la branche sur laquelle vous voulez pousser (pull, merge, rebase éventuels).
5. Pousse vers la branche distante.
6. Envoie les notifications, génère un rapport HTML (si activé), déclenche la CI (si configurée), etc.

### 5.2. Lancement avec options

Le script supporte de nombreuses options (les passer en ligne de commande). Pour les voir :

```plaintext
./git_push_automation.sh -h
```

## Options principales

| Option | Argument | Description | Exemple |
| --- | --- | --- | --- |
| `-f` | `[files]` | Spécifiez les fichiers à ajouter. `.`pour tous. | `./git_push_automation.sh -f "."` |
| `-m` | `[message]` | Message de commit (Type : Description) | `./git_push_automation.sh -m "Bug: Fix crash"` |
| `-b` | `[branch]` | Spécifier la branche distante pour le push | `./git_push_automation.sh -b feature-xyz` |
| `-p` | Aucun | Effectuer un `git pull`avant le push | `./git_push_automation.sh -p` |
| `-M` | `[branch]` | Fusion une branche avant le push | `./git_push_automation.sh -M dev` |
| `-r` | `[repo-dir]` | Gère plusieurs dépôts Git dans un répertoire | `./git_push_automation.sh -r ./multi_repos` |
| `-v` | Aucun | Mode verbeux | `./git_push_automation.sh -v` |
| `-d` | Aucun | Mode dry-run (simulation, aucune action réelle) | `./git_push_automation.sh -d` |
| `-h` | Aucun | Affiche l'aide | `./git_push_automation.sh -h` |
| `-g` | Aucun | Signez le commit avec GPG | `./git_push_automation.sh -g` |
| `-R` | `[branch]` | Rebase sur la branche précise avant le push | `./git_push_automation.sh -R main` |
| `-t` | Aucun | Lancez les tests avant commit/push (nécessite TEST_COMMAND) | `./git_push_automation.sh -t` |
| `-T` | `[tag_name]` | Créez un tag et une release sur la plateforme | `./git_push_automation.sh -T v1.0.0` |
| `-H` | Aucun | Génère un rapport HTML local | `./git_push_automation.sh -H` |
| `-C` | Aucun | Résolution automatique des conflits | `./git_push_automation.sh -C` |

## Options Avancées

| Option | Argument | Description | Exemple |
| --- | --- | --- | --- |
| `-k` | Aucun | Gérer les hooks Git (pre-commit, pre-push) | `./git_push_automation.sh -k` |
| `-S` | Aucun | Gérer les sous-modules (init, sync, update) | `./git_push_automation.sh -S` |
| `-q` | Aucun | Vérifications qualité (peluches, sécurité) | `./git_push_automation.sh -q` |
| `-B` | `[branch]` | Comparez la branche courante avec`[branch]` | `./git_push_automation.sh -B main` |
| `-P` | `[N]` | Exporter les N derniers commits en patchs (dans ./patches) | `./git_push_automation.sh -P 5` |
| `-x` | Aucun | Nettoyer les branches locales fusionnées | `./git_push_automation.sh -x` |
| `-E` | Aucun | Générer des statistiques de commits (top auteurs, nb par type) | `./git_push_automation.sh -E` |
| `-I` | Aucun | Tickets d'intégration (ex: JIRA), lie le commit à un ticket | `./git_push_automation.sh -I` |
| `-U` | Aucun | Déclencher un pipeline CI après le push (CI_TRIGGER_URL requis) | `./git_push_automation.sh -U` |
| `-L` | Aucun | Lire la release (après création de tag) dans release_history.log | `./git_push_automation.sh -L` |

## 6. Scénarios d'utilisation

### **6.1 Exécution simple avec tests et rapport HTML :**

```bash
./git_push_automation.sh -t -H
```

- Lance les tests (`TEST_COMMAND`) avant le commit/push.
- Génère ensuite un rapport HTML dans `./reports/report_YYYYMMDD_HHMMSS.html`.

### **6.2. Exécuter en mode simulation (dry-run) et gérer des sous-modules, hooks, qualité :**

```bash
./git_push_automation.sh -d -k -S -q
```

- **Aucune** action réelle n’est effectuée (`-d` = dry-run).
- Propose d’installer des hooks Git (`-k`).
- Met à jour/synchronise les sous-modules (`-S`).
- Lance un check de qualité (`-q` = ex. lint, audit, bandit…).

### 6.3. Créer un tag, lancer tests + qualité, exporter 5 derniers commits en patch

```bash
./git_push_automation.sh -t -q -T v2.0.0 -H -P 5
```

### **6.4.** Comparer la branche courante avec `main`, nettoyer les branches fusionnées, déclencher CI

```bash
./git_push_automation.sh -B main -x -U
```

- Affiche le diff entre la branche courante et `main` (`-B main`).
- Nettoie les branches locales fusionnées (`-x`).
- Après push, déclenche le pipeline CI (`-U`).

### **6.5.** Lier un ticket, générer des stats, exécuter tests & qualité sur une branche spécifique

```bash
./git_push_automation.sh -m "Tâche: Ajout feature Y" -b feature-y -t -q -E -I
```

- Message de commit : **Tâche: Ajout feature Y**.
- Pousse sur la branche **feature-y**.
- Lance tests (`-t`) et vérifications qualité (`-q`).
- Génère des statistiques de commits (`-E`).
- Détecte un éventuel ID de ticket dans le message (`-I`) et peut générer un lien (ex: JIRA).

---

## 7. Fonctionnalités principales et avancées

 1. **Sauvegarde automatique** : avant d’ajouter des fichiers, le script peut sauvegarder dans `./backup/backup_YYYYMMDD_HHMMSS/`.
 2. **Ajout de fichiers** : possibilité de spécifier une liste de fichiers, ou `.` pour tous.
 3. **Validation de format de message** : le message de commit doit suivre le format **Type: Description** (ex: `Bug: Fix duplication`).
 4. **Tests** : si `-t` est utilisé et qu’une commande `TEST_COMMAND` est définie dans la config.
 5. **Vérifications de qualité** : lint (npm ou autre), audit sécurité (npm audit, git-secrets, bandit…) avec `-q`.
 6. **Gestion de hooks Git** (`-k`) : installe/édite par exemple un hook pre-commit pour exécuter un linter.
 7. **Gestion de sous-modules** (`-S`) : init, sync et update récursive.
 8. **Comparaison de branches** (`-B`) : affiche les commits en retard/avance et le diff.
 9. **Export de patches** (`-P`) : génère des fichiers patch dans `./patches`.
10. **Statistiques de commits** (`-E`) : top auteurs, nombre de commits par type, etc.
11. **Intégration tickets** (`-I`) : détecte un ticket (ex: `JIRA-123`) dans le message et l’associe dans Slack ou le rapport HTML.
12. **Création de release** (`-T`) : crée un tag local et tente de créer une release sur la plateforme configurée.
13. **Notifications** : Slack, e-mail, GitLab/GitHub/Bitbucket (commentaire de commit), Mattermost.
14. **Rapport HTML** (`-H`) : un fichier HTML détaillé, incluant informations sur le commit, fichiers modifiés, 5 derniers commits, etc.
15. **Déclenchement CI** (`-U`) : appelle l’URL définie (`CI_TRIGGER_URL`) après le push.
16. **Nettoyage de branches locales** (`-x`) : supprime celles qui sont déjà fusionnées (confirmation de l’utilisateur).
17. **Logging** (`git_push_automation.log`) : toutes les actions et erreurs sont loguées.
18. **Collecte de feedback** : le script peut demander un retour utilisateur en fin de processus, pour améliorer l’outil.

---

## 8. Fichier de logs

Le script écrit (ou crée) un fichier `git_push_automation.log` à la racine. Y sont consignées les actions et erreurs.

- Exemple de log :

  ```plaintext
  2024-01-01 10:15:42 [INFO] : Fichier de log créé : ./git_push_automation.log
  2024-01-01 10:15:42 [INFO] : Démarrage du script v3.1.0
  2024-01-01 10:15:43 [INFO] : Fichiers à ajouter : .
  2024-01-01 10:15:45 [ERROR] : Fichier 'inexistant.txt' inexistant.
  ...
  ```

---

## 9. Mode multi-dépôts

Avec l’option `-r <repo-dir>`, le script itère automatiquement sur tous les sous-répertoires qui contiennent un `.git` et exécute la séquence.

- Pratique pour des projets monorepo ou pour automatiser la même procédure sur plusieurs dépôts à la fois.

---

## 10. Questions fréquentes (FAQ)

1. **Que se passe-t-il si un outil manque (ex: npm, mail, etc.) ?**\
   Le script affiche un message d’avertissement ou propose d’installer l’outil (apt-get, yum, brew…).\
   En mode silencieux, il tente une installation automatique si possible. Sinon, cette fonctionnalité est sautée.

2. **Mon message de commit n’est pas au bon format (**`Bug:`**,** `Tâche:`**, etc.).**\
   Le script vous redemandera un message correct ou l’adaptera selon vos préférences (voir la fonction `improved_validate_commit_message`).

3. **Comment fonctionne la création d’une release GitLab/GitHub/Bitbucket ?**

   - Le script crée d’abord le tag localement.
   - Ensuite, il utilise l’API de la plateforme (en se basant sur les tokens configurés) pour créer la *release*correspondante.
   - Le tag est alors poussé et rendu visible à distance.

4. **Puis-je personnaliser les hooks ?**\
   Oui. Le script place par exemple un hook `pre-commit` ou `pre-push` dans `.git/hooks/`. Vous pouvez ensuite l’éditer manuellement.

5. **Où se trouve le rapport HTML ?**\
   Par défaut dans `./reports/report_YYYYMMDD_HHMMSS.html`. Vous pouvez l’ouvrir dans un navigateur pour consulter les détails du push.

---

## 11. Conseils et bonnes pratiques

- **Sécurisez vos tokens** (GitLab, GitHub, Bitbucket). Ils ne doivent pas être commités en clair dans le dépôt.
- **Activez la vérification git-secrets** si vous manipulez régulièrement des identifiants ou secrets dans le code.
- **Vérifiez la configuration Git utilisateur** : le script paramètre `user.email` si vous n’en avez pas, mais c’est mieux de le faire vous-même (ex: `git config --global user.email "dev@example.com"`).
- **Servez-vous du mode** `dry-run` (`-d`) pour tester et comprendre l’effet des opérations avant de les faire en production.

---

## 12. Conclusion

Le **Git Push Automation – Version Avancée** permet de :

- Centraliser et automatiser de nombreuses étapes liées au `git push`.
- Uniformiser les pratiques dans une équipe (messages de commit, tests, qualité, etc.).
- Gagner du temps et de la fiabilité grâce aux vérifications automatiques, aux hooks et aux notifications.

Il suffit de configurer correctement votre fichier `.env_git_push_automation`, d’installer (optionnellement) les outils nécessaires, puis de lancer :

```bash
./git_push_automation.sh
```

ou encore :

```bash
./git_push_automation.sh [OPTIONS]
```

Pour aller plus loin, vous pouvez **forker** le script et adapter davantage la logique interne (hooks, messages, CI, etc.) à vos besoins spécifiques.

Bonne utilisation !