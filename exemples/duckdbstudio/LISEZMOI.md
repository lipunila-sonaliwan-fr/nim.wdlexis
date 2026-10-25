# DuckDB Studio

Atelier de conception, d'administration, d'analyse et d'optimisation autour de
DuckDB, écrit en Lexis+ (interface inspirée de l'atelier Lexis+).

```
wdlexisrt principal.prg [dossier_du_projet]
```

Sans argument, le dernier projet ouvert est rouvert (à défaut
`~/DuckDBStudio`). Pour une première prise en main : *Fichier ▸ Créer la base
de démonstration*, puis F5 sur les requêtes de `demo.sql` et F6 (profil) sur la
requête 2 ou 4, et enfin *Analyser*.

## Ce que contient ce socle

| Domaine | Fonctions |
| --- | --- |
| Connexions | greffons JSON (`connecteurs/`), concepteur (paramètres, options, aperçu de l'ATTACH, test, ping, nombre d'objets), attachement au démarrage, catalogue mis en cache dans `.duckstudio/` |
| Explorateur | connexions ▸ schémas ▸ tables (volumétrie) / vues / macros, fiche de l'objet (colonnes, clés, définition), *Requête*, *Décrire* (SUMMARIZE), *Schéma* ; palette (sources, modèles SQL, flux) ; historique |
| Éditeur SQL | coloration SQL, complétion des tables et des colonnes (`table.` ▸ colonnes), commentaires `--`, validation pendant la frappe (analyseur de DuckDB), plusieurs scripts en onglets, exécution de la sélection ou du script (F5, Ctrl+R), erreurs soulignées |
| Résultats | grille typée (∅ pour NULL), limite réglable, comptage exact, export CSV / Parquet / JSON (COPY) |
| Profil | `EXPLAIN (ANALYZE, FORMAT JSON)` : graphe des opérateurs (temps, part, lignes, conditions), tableau, histogramme, latence, CPU, mémoire, disque temporaire |
| Expertise | règles sur le plan (balayages complets, produits cartésiens, jointures explosives, tris, débordements), sur le catalogue (volumétrie, clés absentes, structures redondantes, colonnes inutilisées, compression) et sur l'historique (requêtes répétées, agrégations répétées : mutualisation, gain et ROI estimés) ; niveaux Critique / Important / Opportunité ; correction SQL générée dans une nouvelle requête ; recommandations ignorées mémorisées |
| Schéma | modèle entité-relation (PK, FK, vues et leurs dépendances), disposition automatique et positions mémorisées, clé étrangère tirée à la souris, inspecteur de table (colonnes, types, PK, requis, défaut), renommage propagé, **Modèle → SQL** (CREATE dans l'ordre des dépendances) et **Script → modèle** (le script est rejoué dans une base jetable : l'analyseur est celui de DuckDB), analyse d'impact (clés, vues, historique, scripts du projet) avant suppression |
| Cartographie | sources ▸ schémas ▸ tables ▸ vues, dépendances entre vues, dépendances fédérées (en rouge), filtre par connexion et recherche |
| Tableau de bord | inventaire, statistiques d'exécution, requêtes les plus coûteuses, recommandations par criticité, score global |

## Architecture

| Fichier | Rôle |
| --- | --- |
| `principal.prg` | fenêtre, barre d'outils, réglages (`~/.duckdbstudio.json`), démarrage |
| `projet.prg` | projet (`duckstudio.json`), historique (500 requêtes), scripts |
| `connecteurs.prg` | greffons, gabarits d'ATTACH, extensions, attachement, introspection, cache |
| `connexions.prg` | boîte de connexion |
| `explorateur.prg` | arbre, fiches, palette |
| `requetes.prg` | découpage des scripts, exécution, résultats, validation, export |
| `profil.prg` | profil d'exécution |
| `expertise.prg` | moteur de règles et recommandations |
| `schema.prg` | concepteur de schéma, réversibilité SQL ↔ modèle, impact |
| `carto.prg` | cartographie |
| `tableau.prg` | tableau de bord |
| `menus.prg` | menus, raccourcis, à propos |
| `demo.prg` | base de démonstration |
| `connecteurs/*.json` | un fichier par type de connexion |

Le moteur est une base DuckDB **en mémoire** ; chaque connexion y est attachée
sous son nom (`ATTACH … AS ventes`), les sources de fichiers deviennent des vues
dans un schéma du même nom (`memory.objectifs.objectifs`). Une requête peut donc
joindre plusieurs sources :

```sql
SELECT m.mois, m.ca, o.objectif
FROM demo.ca_mensuel m JOIN objectifs.objectifs o USING (mois, categorie);
```

## Écrire un connecteur

```json
{
  "type": "postgres", "libelle": "PostgreSQL", "categorie": "Bases",
  "sigle": "PG", "couleur": "#3B82F6", "mode": "catalogue", "extension": "postgres",
  "parametres": [{"nom": "hote", "libelle": "Hôte", "defaut": "localhost"},
                 {"nom": "motdepasse", "libelle": "Mot de passe", "secret": true}],
  "options": [{"nom": "lecture", "libelle": "Lecture seule", "defaut": true}],
  "attacher": ["ATTACH 'host={hote} password={motdepasse}' AS {alias} (TYPE postgres{si_lecture:, READ_ONLY})"]
}
```

- `mode` : `catalogue` (ATTACH, introspection complète), `fichiers` (une vue
  par fichier : `lecteur` avec `{chemin}`), `requete` (fonctions de table, par
  exemple ODBC).
- `{param}` est remplacé par la valeur (apostrophes doublées), `{alias}` par le
  nom SQL de la connexion, `{si_option:texte}` par *texte* si l'option est cochée.
- `extension` est chargée (LOAD, sinon INSTALL puis LOAD) ; `installer` donne
  la commande d'installation (`INSTALL mssql FROM community`).
- `version_min` : version minimale de DuckDB (Quack : 2.0).
- `secret` : jamais écrit dans `duckstudio.json` ; redemandé à l'attachement.

Remarques : **Quack** (protocole client-serveur de DuckDB) demande DuckDB 2.0 ou
plus récent ; SQL Server passe par l'extension communautaire `mssql`, ODBC par
`nanodbc` ; les extensions sont téléchargées à la première utilisation (réseau
nécessaire).

## Lots suivants

- **lot 2** : concepteur de pipelines (sources ▸ transformations ▸ cibles,
  génération du SQL et réversibilité), planificateur (déclencheurs, dépendances,
  reprise) et diagramme de Gantt des exécutions (`ui.gantt`), mutualisation
  inter-requêtes plus fine (empreintes de plans) ;

- **lot 3** : assistant IA (paquet `llm` : explication de plan, réécriture de
  requête, génération de modèle à partir d'une description), tableau de bord BI
  (graphiques sur résultats), extensions Lexis+ chargées depuis le projet
  (règles d'expertise et vues supplémentaires).

- **lot 4** : si vous avez des idées...

Les éléments *Orchestration* de la palette annoncent ces évolutions.
