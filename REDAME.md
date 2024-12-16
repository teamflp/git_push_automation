# Documentation Complète du Script Git Push Automation - Version Avancée

## Introduction

Le **Git Push Automation - Version Avancée** est un script Bash conçu pour faciliter et renforcer le processus de push Git au sein d'une équipe de développement. Il offre un flux interactif par défaut (sauvegarde des fichiers, ajout, commit, gestion des branches, push), enrichi de nombreuses fonctionnalités avancées :

- Intégration avec plusieurs plateformes (GitLab, GitHub, Bitbucket)
- Gestion des hooks Git (pre-commit, pre-push)
- Vérifications de qualité (linting, sécurité), tests automatisés
- Support des sous-modules (synchronisation, mise à jour)
- Génération d’un rapport HTML local
- Comparaison de branches, export de patchs
- Déclenchement d’un pipeline CI
- Envoi de notifications (Slack, e-mail, Mattermost), création de releases
- Nettoyage automatique de branches locales fusionnées, collecte de feedback
- Statistiques de commits et lien vers des tickets (JIRA, etc.)

Ce script vise à améliorer la productivité et la fiabilité du cycle de développement, en s'adaptant aux besoins de chaque équipe.

## Pré-requis

- **Système d’exploitation** : Linux, macOS, ou environnements compatibles (Git Bash sous Windows).
- **Git** : Version ≥ 2.20.0 requise.
- **Outils additionnels** (optionnels) : 
  - `npm` pour exécuter les lints ou audits de sécurité JavaScript.
  - `git-secrets` pour détecter la présence de secrets dans le code.
  - `bandit` pour analyser la sécurité du code Python.
  - Un outil de messagerie (mailutils, mailx) pour envoyer des e-mails.
- **jq** et **curl** : Pour les notifications et l'analyse JSON.
- **Accès internet** (optionnel) : Pour envoyer notifications Slack, GitLab/GitHub/Bitbucket, déclencher pipeline CI.

Si ces outils ne sont pas disponibles, le script tentera une dégradation douce (par exemple, sauter l’étape concernée ou avertir l’utilisateur).

## Installation

1. **Cloner le script** :

   ```bash
   git clone https://votre_repo/git_push_automation.git
   cd git_push_automation
   ```

**Rendre le script exécutable** :

```bash
chmod +x git_push_automation.sh
```

**Configurer le fichier**`git_push_automation_config` : \
Copier le fichier d'exemple `git_push_automation_config.example`en `git_push_automation_config`et adapter les variables (plateforme, tokens, URLs, etc.).

Exemple :

```bash
cp git_push_automation_config.example git_push_automation_config
nano git_push_automation_config
# Modifier PLATFORM, SLACK_WEBHOOK_URL, GITLAB_TOKEN, etc.
```

1. **Installer les dépendances optionnelles** :

   - npm (si lint/test JS), git-secrets, bandit (si sécurité Python)
   - mailutils/mailx si vous souhaitez envoyer des e-mails sans interaction

## Configuration

Le fichier `git_push_automation_config`permet de définir :

- `PLATFORM="gitlab"`ou `"github"`ou`"bitbucket"`
- Les jetons d'accès personnels `GITLAB_TOKEN`, `GITHUB_TOKEN`ou`BITBUCKET_APP_PASSWORD`
- `EMAIL_RECIPIENTS`pour envoyer des notifications par e-mail
- `SLACK_WEBHOOK_URL`et `MATTERMOST_WEBHOOK_URL`pour les intégrations de chat
- `TEST_COMMAND`pour lancer des tests avant le push
- `QUALITY_COMMAND`pour lancer lint/audit sécurité avant le push
- `CI_TRIGGER_URL`pour déclencher un pipeline CI post-push

En l'absence de certaines variables, les fonctionnalités associées seront ignorées ou dégradées.

## Utilisation de la base

Sans aucune option, le script propose un flux interactif par défaut :

```bash
./git_push_automation.sh
```

Il vous guidera à travers les étapes (sauvegarde, ajout de fichiers, création de commit, gestion de branches, pull, merge, push, etc.) et proposera des menus pour choisir les actions.

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

## Scénarios d'utilisation

- **Exécution simple avec tests et rapport HTML :**

  ```bash
  ./git_push_automation.sh -t -H
  ```

- **Exécuter en mode simulation (dry-run) et gérer des sous-modules, hooks, qualité :**

  ```bash
  ./git_push_automation.sh -d -k -S -q
  ```

- **Créer un tag et une release, lancer des tests et qualité, et exporter 5 patchs :**

  ```bash
  ./git_push_automation.sh -t -q -T v2.0.0 -H -P 5
  ```

- **Comparer la branche courante avec** `main`**, nettoyer les branches fusionnées, déclencher CI :**

  ```bash
  ./git_push_automation.sh -B main -x -U
  ```

- **Lier un ticket, génère des stats commits, tests, qualité sur une branche donnée :**

  ```bash
  ./git_push_automation.sh -m "Tâche: Ajout feature Y" -b feature-y -t -q -E -I
  ```

## Comportement en cas d'outils manquants

Si les outils requis (npm, git-secrets, bandit) ne sont pas installés, le script :

- Afficher un message d'avertissement et enregistrer dans le journal.
- Faire sauter l'étape concernée.
- Continuez le workflow sans bloquer complètement.

Cela permet une utilisation par tous les développeurs, modifiant leur configuration exacte.

## Interactions et Menus

Si vous lancez le script sans options, il proposera des menus et des questions (ex : souhaitez-vous faire un pull ?), gérer ainsi un flux semi-automatique.

## Rapport HTML

Une fois le push effectué ( `-H`est utilisé), un rapport HTML local est généré dans `./reports/`. Celui-ci contient :

- Les informations sur la branche, l'auteur, le commit
- Le message de commit, l'URL distante
- Peut être enrichi selon les besoins (tests, qualité, stats).

## Pipeline CI, versions, commentaires

- Le pipeline CI peut être déclenché après le push avec `-U`.
- La création de release ( `-T`) crée un tag et notifie la plateforme, ce qui peut être logué ( `-L`).
- Le script propose de collecter un feedback utilisateur en fin d'exécution, utile pour s'améliorer dans une équipe.

## Conclusion

Le **Git Push Automation - Version Avancée** est un outil flexible, fiable et complet. Qu'il s'agisse d'équipes cherchant simplement à automatiser le flux de push ou de développeurs voulant intégrer pleinement la qualité, la sécurité, la CI/CD et les notifications, ce script s'adapte à toutes les situations. Il centralise des tâches souvent répétitives et source de confusion, tout en fournissant une expérience cohérente et intégrée dans le cycle de développement Git.

Pour aller plus loin, référez-vous au fichier de configuration, préparez les dépendances et lancez le script avec les options qui conviennent à votre workflow. Bon push !