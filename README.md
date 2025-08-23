# Documentation complète du script Git Push Automation

**Nom** : Git Push Automation\
**Version** : 1.1.7\
**Auteur** : Paterne G. G.\
**Email** : [paterne81@hotmail.fr](mailto:paterne81@hotmail.fr)\
**Pour** : Équipe DevOps / Dev

---

## 1. Introduction

Le script **Git Push Automation** est un outil en Bash qui facilite et renforce le processus de *push* Git en ajoutant :

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
- Une configuration flexible via un fichier `config.yaml`.

Le script peut être utilisé en mode interactif (menus et questions) ou en mode non-interactif (avec des options). Il s’adapte aussi bien aux petits dépôts qu’aux projets plus complexes (multi-dépôts).

---

## 2. Prérequis

- **Système d’exploitation** : Linux, macOS, ou un environnement compatible Bash (ex: Git Bash sous Windows).
- **Git** ≥ 2.20.0 (le script vérifie et alerte si la version est trop ancienne).
- **yq** pour parser la configuration YAML. Installez-le via `pip install yq` ou votre gestionnaire de paquets.
- **Outils recommandés** (selon vos besoins) :
  - `jq` et `curl` : pour analyser du JSON et envoyer des requêtes HTTP (notamment Slack, GitLab, GitHub).
  - `mailutils` / `mailx` : pour l’envoi d’e-mails automatisés.
  - `npm` : si vous lancez des tests/lint JavaScript, ou `bandit` si vous utilisez Python et souhaitez faire une analyse de sécurité.
  - `git-secrets` : pour vérifier la présence de secrets dans le code avant commit/push.

Si certains outils ne sont pas installés, le script s’adapte (il saute certaines étapes ou prévient l’utilisateur).

---

## 3. Installation

### 3.1. Ouvrez votre terminal

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

Vous pouvez maintenant utiliser la commande pour vérifier le fonctionnement du script:

```bash
git_push_automation -h
```

> **Astuce** : Placez un fichier `config.yaml` à la racine de **chaque projet** pour personnaliser la configuration du script (tokens, variables, etc.).

---

Ainsi, même si vous avez installé le script globalement, le script chargera la configuration **dans le dossier courant** où vous exécutez la commande.

---

## 4. Vérification de fonctionnement

Pour vérifier le bon fonctionnement, vous pouvez exécuter :

```bash
git_push_automation -h
```

(s’il est installé correctement) :

Vous verrez alors l’aide avec la liste des options disponibles.

## 5. Configuration : `config.yaml`

- Par défaut, le script cherche un fichier `config.yaml` à la racine de votre projet.
- Vous pouvez copier l'exemple fourni (`config.exemple.yaml`) pour créer votre propre fichier `config.yaml`.
- Dans ce fichier, vous pouvez définir toutes les variables de configuration, comme les URLs de webhook, les tokens d'API, etc. Le script lira ce fichier pour configurer son comportement.

Voici un exemple de structure pour votre `config.yaml`:

```yaml
########################################################################################
# CONFIGURATION DU SCRIPT D'AUTOMATISATION PUSH GIT (Format YAML)
########################################################################################

# Paramétrage Slack
slack:
  webhook_url: "https://hooks.slack.com/services/T0XXXXXXXXX/xxxxxxxxxxxxxxxxxxxxxxxx"
  channel: "#my-channel"
  username: "MY_USERNAME"
  icon_emoji: ":ghost:"

# ... et ainsi de suite pour les autres configurations (GitLab, email, etc.)
# Référez-vous à config.exemple.yaml pour la structure complète.
```

En l'absence de certaines variables, les fonctionnalités associées seront ignorées ou dégradées.

## 6. Utilisation

### 6.1. Exécution simple (flux interactif)

Dans votre fichier .gitignore, ajoutez les fichiers suivants pour ne pas les suivre dans le dépôt :

```plaintext
/.vscode/
/config.yaml
/git_push_automation.log
/backup/
/reports/
/patches/
/stats/
```

Sans aucune option, le script propose un flux par défaut :

```plaintext
git_push_automation.sh
```

Celui-ci :

1. Vérifie le dépôt Git, la configuration utilisateur (e-mail), etc.
2. Demande si vous souhaitez gérer des hooks, des sous-modules, générer des stats…
3. Vous invite à sauvegarder, ajouter des fichiers, rédiger un message de commit, etc.
4. Gère la branche sur laquelle vous voulez pousser (pull, merge, rebase éventuels).
5. Pousse vers la branche distante.
6. Envoie les notifications, génère un rapport HTML (si activé), déclenche la CI (si configurée), etc.

### 6.2. Lancement avec options

Le script supporte de nombreuses options (les passer en ligne de commande). Pour les voir :

```plaintext
git_push_automation.sh -h
```

## Options principales

| Option | Argument | Description | Exemple |
| --- | --- | --- | --- |
| `-f` | `[files]` | Spécifiez les fichiers à ajouter. `.`pour tous. | `git_push_automation.sh -f "."` |
| `-m` | `[message]` | Message de commit (Type : Description) | `git_push_automation.sh -m "Bug: Fix crash"` |
| `-b` | `[branch]` | Spécifier la branche distante pour le push | `git_push_automation.sh -b feature-xyz` |
| `-p` | Aucun | Effectuer un `git pull`avant le push | `git_push_automation.sh -p` |
| `-M` | `[branch]` | Fusion une branche avant le push | `git_push_automation.sh -M dev` |
| `-r` | `[repo-dir]` | Gère plusieurs dépôts Git dans un répertoire | `git_push_automation.sh -r ./multi_repos` |
| `-v` | Aucun | Mode verbeux | `git_push_automation.sh -v` |
| `-d` | Aucun | Mode dry-run (simulation, aucune action réelle) | `git_push_automation.sh -d` |
| `-h` | Aucun | Affiche l'aide | `git_push_automation.sh -h` |
| `-g` | Aucun | Signez le commit avec GPG | `git_push_automation.sh -g` |
| `-R` | `[branch]` | Rebase sur la branche précise avant le push | `git_push_automation.sh -R main` |
| `-t` | Aucun | Lancez les tests avant commit/push (nécessite TEST_COMMAND) | `git_push_automation.sh -t` |
| `-T` | `[tag_name]` | Créez un tag et une release sur la plateforme | `git_push_automation.sh -T v1.0.0` |
| `-H` | Aucun | Génère un rapport HTML local | `git_push_automation.sh -H` |
| `-C` | Aucun | Résolution automatique des conflits | `git_push_automation.sh -C` |

## Options Avancées

| Option | Argument | Description | Exemple |
| --- | --- | --- | --- |
| `-k` | Aucun | Gérer les hooks Git (pre-commit, pre-push) | `git_push_automation.sh -k` |
| `-S` | Aucun | Gérer les sous-modules (init, sync, update) | `git_push_automation.sh -S` |
| `-q` | Aucun | Vérifications qualité (peluches, sécurité) | `git_push_automation.sh -q` |
| `-B` | `[branch]` | Comparez la branche courante avec`[branch]` | `git_push_automation.sh -B main` |
| `-P` | `[n]` | Exporter les n derniers commits en patchs (dans ./patches) | `git_push_automation.sh -P 5` |
| `-x` | Aucun | Nettoyer les branches locales fusionnées | `git_push_automation.sh -x` |
| `-E` | Aucun | Générer des statistiques de commits (top auteurs, nb par type) | `git_push_automation.sh -E` |
| `-I` | Aucun | Tickets d'intégration (ex: JIRA), lie le commit à un ticket | `git_push_automation.sh -I` |
| `-U` | Aucun | Déclencher un pipeline CI après le push (CI_TRIGGER_URL requis) | `git_push_automation.sh -U` |
| `-L` | Aucun | Lire la release (après création de tag) dans release_history.log | `git_push_automation.sh -L` |
| `-X` | `[n]` | Rollback (annuler) les *n* derniers commits (via revert ou reset). | `git_push_automation -X 2` |
| `-Y` | Aucun | Cherry-pick interactif (permet de prendre un commit d’une autre branche). | `git_push_automation -Y` |
| `-Z` | Aucun | Afficher un **diff** / review complet avant le push (stat + diff, outil graphique éventuellement). | `git_push_automation -Z` |
| `-V [type]` | `[type]` | Incrémentation sémantique (`major`, `minor`, ou `patch`) et création automatique d’un nouveau tag. | `git_push_automation -V patch` |
| `--create-pr` | Aucun | Crée automatiquement une Pull Request (GitHub) après le push. | `git_push_automation --create-pr` |
| `--create-mr` | Aucun | Crée automatiquement une Merge Request (GitLab) après le push. | `git_push_automation --create-mr` |
| `--ci-friendly` | Aucun | Mode **non interactif** (idéal pour la CI) : pas de questions posées, comportement “par défaut”. | `git_push_automation --ci-friendly` |

## Scénarios d'utilisation

### **Exécution simple avec tests et rapport HTML :**

```bash
git_push_automation -t -H
```

- Lance les tests (`TEST_COMMAND`) avant le commit/push.
- Génère ensuite un rapport HTML dans `./reports/report_YYYYMMDD_HHMMSS.html`.

### **Exécuter en mode simulation (dry-run) et gérer des sous-modules, hooks, qualité :**

```bash
git_push_automation -d -k -S -q
```

- **Aucune** action réelle n’est effectuée (`-d` = dry-run).
- Propose d’installer des hooks Git (`-k`).
- Met à jour/synchronise les sous-modules (`-S`).
- Lance un check de qualité (`-q` = ex. lint, audit, bandit…).

### Créer un tag, lancer tests + qualité, exporter 5 derniers commits en patch

```bash
git_push_automation -t -q -T v2.0.0 -H -P 5
```

### Comparer la branche courante avec `main`, nettoyer les branches fusionnées, déclencher CI

```bash
git_push_automation -B main -x -U
```

- Affiche le diff entre la branche courante et `main` (`-B main`).
- Nettoie les branches locales fusionnées (`-x`).
- Après push, déclenche le pipeline CI (`-U`).

### Lier un ticket, générer des stats, exécuter tests & qualité sur une branche spécifique

```bash
git_push_automation.sh -m "Tâche: Ajout feature Y" -b feature-y -t -q -E -I
```

- Message de commit : **Tâche: Ajout feature Y**.
- Pousse sur la branche **feature-y**.
- Lance tests (`-t`) et vérifications qualité (`-q`).
- Génère des statistiques de commits (`-E`).
- Détecte un éventuel ID de ticket dans le message (`-I`) et peut générer un lien (ex: JIRA).

---

### Rollback de 2 commits

```bash
git_push_automation -X 2
```

- Le script va demander si vous souhaitez faire un `revert` ou un `reset --hard` (sauf en mode CI-friendly, où il fera un revert par défaut).
- Ensuite, il continue le flux normal (hooks, submodules, etc.) si la commande n’est pas interrompue.

### Cherry-pick interactif + Review avant le push

```bash
git_push_automation -Y -Z
```

- **-Y** : vous propose de choisir la branche source, liste les derniers commits, et vous demande de saisir le hash du commit à cherry-pick.
- **-Z** : juste avant la séquence d’actions par défaut, le script affichera un résumé (`git diff --stat`), puis vous demandera si vous voulez un diff complet ou ouvrir un outil graphique.

Vous pourrez ensuite poursuivre la séquence standard (backup, add_files, create_commit, push).

### Incrémenter la version patch et créer un tag

```bash
git_push_automation -V patch
```

- Le script repère le dernier tag `vX.Y.Z`, incrémente `Z` de +1 pour créer `vX.Y.(Z+1)`.
- Il pousse le tag si vous acceptez de pousser la branche.

### Créer une Pull Request après le push

```bash
git_push_automation --create-pr
```

- Après l’exécution du `perform_push()`, le script appellera `create_github_pr()`.
- Attention : vous devez avoir `PLATFORM=github` dans votre `.env` et l’outil `gh` (ou la logique `curl` vers l’API GitHub) configuré.
- Le script ouvrira une PR de la branche courante vers la branche principale configurée (souvent `main` ou `master`).

### Créer une Merge Request sur GitLab

```bash
git_push_automation --create-mr
```

- Après le push, le script appellera `create_gitlab_mr()`.
- Vous devez avoir `PLATFORM=gitlab`, `GITLAB_PROJECT_ID` et `GITLAB_TOKEN` configurés dans `.env`.

### Mode CI-friendly (non interactif)

```bash
git_push_automation --ci-friendly -f . -m "Bug: Correction rapide" -b develop -q -U
```

- **Pas de questions** : Le script ne vous demandera **pas** de choisir (y/n) pour un pull, un revert, etc.
- **-f .** : ajoute tous les fichiers.
- **-m** : message de commit.
- **-b** : branche `develop`.
- **-q** : exécute le `run_quality_checks`.
- **-U** : déclenche pipeline CI après le push.

*==🟡(Vous pouvez combiner==* `--create-pr` *==🟡en mode CI, pour créer automatiquement la PR après le push.)==*

## Points de configuration importants

- **Pour le rollback** : Si vous êtes **en CI** (`--ci-friendly`), il fera un revert par défaut, sans vous demander. Dans un usage **local**, vous aurez un prompt pour choisir `revert` ou `reset --hard`.

- **Pour la création de PR sur GitHub** :

  - Nécessite `PLATFORM=github`
  - Nécessite un jeton ou l’outil `gh` (GitHub CLI) installé, ou un script `curl` bien configuré.

- **Pour la création de MR sur GitLab** :

  - Nécessite `PLATFORM=gitlab`
  - Variables `GITLAB_PROJECT_ID` et `GITLAB_TOKEN` doivent être définies dans `.env`.

- **Pour l’incrémentation sémantique** :

  - Le script détecte le dernier tag au format `vX.Y.Z`.
  - S’il ne trouve pas de tag, il part de `v0.0.0`.
  - Incrémente selon la valeur (`major`, `minor`, `patch`) et pousse le nouveau tag sur `origin`.

## Exemples d’enchaînements concrets

**Annuler 1 commit, faire un cherry-pick, review, push + PR** :

```bash
git_push_automation -X 1 -Y -Z --create-pr -f . -m "Refactor: Correction après revert" -b featureX
```

- Annule le dernier commit,
- Cherry-pick un commit d’une autre branche,
- Affiche un diff complet,
- Ensuite exécute le flux standard : backup, add (`-f .`), commit (`-m`), push (`-b featureX`),
- Crée enfin une PR.

**CI pipeline** (non interactif), incluant un version bump patch :

```bash
git_push_automation --ci-friendly -V patch -f . -m "Bug: Correction d'index hors limites" -b production
```

- Pas de prompts,
- Ajoute tous les fichiers,
- Commit “Bug: Correction…”,
- Pousse sur `production`,
- A la fin (dans `collect_feedback()`), bump `vX.Y.Z` -&gt; `vX.Y.(Z+1)` et push le tag.
- (Si `TRIGGER_CI=y`, déclenche pipeline CI en plus).

## Fonctionnalités principales et avancées

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

## Fichier de logs

Le script écrit (ou crée) un fichier `git_push_automation.log` à la racine. Y sont consignées les actions et erreurs.

- Exemple de log :

  ```plaintext
  2024-01-01 10:15:42 [INFO] : Fichier de log créé : git_push_automation.log
  2024-01-01 10:15:42 [INFO] : Démarrage du script v3.1.0
  2024-01-01 10:15:43 [INFO] : Fichiers à ajouter : .
  2024-01-01 10:15:45 [ERROR] : Fichier 'inexistant.txt' inexistant.
  ...
  ```

---

## Mode multi-dépôts

Avec l’option `-r <repo-dir>`, le script itère automatiquement sur tous les sous-répertoires qui contiennent un `.git` et exécute la séquence.

- Pratique pour des projets monorepo ou pour automatiser la même procédure sur plusieurs dépôts à la fois.

---

## Questions fréquentes (FAQ)

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

## Conseils et bonnes pratiques

- **Sécurisez vos tokens** (GitLab, GitHub, Bitbucket). Ils ne doivent pas être commités en clair dans le dépôt.
- **Activez la vérification git-secrets** si vous manipulez régulièrement des identifiants ou secrets dans le code.
- **Vérifiez la configuration Git utilisateur** : le script paramètre `user.email` si vous n’en avez pas, mais c’est mieux de le faire vous-même (ex: `git config --global user.email "dev@example.com"`).
- **Servez-vous du mode** `dry-run` (`-d`) pour tester et comprendre l’effet des opérations avant de les faire en production.

## Conclusion

Le **Git Push Automation – Version Avancée** permet de :

- Centraliser et automatiser de nombreuses étapes liées au `git push`.
- Uniformiser les pratiques dans une équipe (messages de commit, tests, qualité, etc.).
- Gagner du temps et de la fiabilité grâce aux vérifications automatiques, aux hooks et aux notifications.
- **Ajoutez** les options `-X`, `-Y`, `-Z`, `-V`, `--create-pr`, `--create-mr`, `--ci-friendly` à votre commande.
- **Combinez**-les avec vos options existantes (`-f, -m, -b, etc.`) pour personnaliser le flux.
- **Le script** s’occupera d’appeler `rollback_commits`, `cherry_pick_interactive`, `review_changes`, `create_github_pr`, `create_gitlab_mr`, `auto_semver_bump` selon les drapeaux passés.
- **En mode CI-friendly** (`--ci-friendly`), le script ne posera aucune question et utilisera le comportement par défaut.

Cela vous donne un **contrôle très fin** sur les actions Git et la gestion de vos branches, commits, tags et éventuelles PR/MR sur GitHub/GitLab. Bon usage !

Il suffit de configurer correctement votre fichier `.env_git_push_automation`, d’installer (optionnellement) les outils nécessaires, puis de lancer :

```bash
git_push_automation
```

ou encore :

```bash
git_push_automation [OPTIONS]
```

Vous pouvez me contacter pour toute question ou suggestion.\
email : [paterne81@hotmail.fr](https://github.com/teamflp/git_push_automation)

Bonne utilisation !

- 