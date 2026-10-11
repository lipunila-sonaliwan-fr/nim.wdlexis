Lexis+ &
wdlexis+ — l'atelier du langage Lexis+<br/>
© 2026 Jean‑Marc "jihem"Quéré, sonaliwan.fr<br/>
SIRET 13033319800013<br/>
Distribué sous licence CC BY‑NC‑SA 4.0.<br/>

Les utilisations commerciales ne sont pas couvertes par cette licence.<br/>
Pour obtenir une autorisation d'utilisation commerciale,<br/>
contactez l'auteur : metalab (at) sonaliwan.fr.<br/>

# Lexis+ et l'atelier wdlexis+

**Lexis+ — Développez naturellement vos applications métier**

Ce document décrit le langage Lexis+ tel qu'il s'utilise sur le poste de travail
avec l'atelier **wdlexis+** et le runtime **wdlexisrt** : le langage, la base de
données, l'interface graphique, le multitâche, l'atelier, puis la référence
complète des fonctions intégrées et des paquets. Les exemples de ce document ont
été exécutés tels qu'ils sont écrits (sauf ceux qui ouvrent des fenêtres).

---

## 1. Premier programme, pas à pas

1. Lancez l'atelier : `./wdlexis+`.
2. Menu *Fichier > Nouveau projet…*, acceptez le dossier proposé (`projet_lexis`).
   L'atelier crée `principal.prg`, le point d'entrée du projet, avec un petit
   exemple de fenêtre.
3. Remplacez son contenu par :

```lexis
&& Mon premier programme
locale nom = "Ada"
? "Bonjour", nom
pour i = 1 a 3
  ? i, "au carré :", CARRE(i)
suivant

fonction CARRE(n)
retourner n * n
```

4. *Ctrl+R* (ou le bouton **▶ Exécuter**). La console affiche :

```
Bonjour Ada
1 au carré : 1
2 au carré : 4
3 au carré : 9
```

5. Cliquez dans la marge à gauche de la ligne `? i, ...` pour poser un point
   d'arrêt, puis *F5* : le programme s'arrête sur la ligne, l'onglet **Variables**
   montre `i` et `nom`, *F11* avance d'une instruction (en entrant dans `CARRE`),
   *F10* passe par-dessus les appels, *Maj+F11* termine la procédure en cours,
   *F5* continue.

Le même programme s'exécute sans l'atelier : `./wdlexisrt projet_lexis/principal.prg`.

---

## 2. Organisation d'un projet

- Un projet est un **dossier**. Son fichier principal est `principal.prg`
  (modifiable par *Exécuter > Arguments et fichier principal…*).
- Le **programme principal** est l'ensemble des instructions écrites **en tête** du
  fichier principal, avant la première procédure.
- Les **procédures et fonctions** peuvent être écrites dans n'importe quel fichier
  `.prg` du dossier (et de ses sous-dossiers) : toutes sont chargées au lancement
  et s'appellent par leur nom depuis tout le projet. Seul le fichier principal
  peut contenir des instructions en tête.
- Si le fichier principal ne contient que des procédures, la procédure
  `PRINCIPAL` est exécutée.
- Le corps d'une procédure s'arrête à la procédure suivante, ou à
  `finprocedure` / `finfonction` : les instructions qui suivent un `finprocedure`
  appartiennent de nouveau au programme principal.

```lexis
&& principal.prg
? TTC(100)            && TTC est définie plus bas (ou dans un autre fichier .prg)

fonction TTC(ht)
retourner arrondi(ht * 1.2, 2)
finfonction

? "fin du programme"  && de nouveau le programme principal
```

---

## 3. Le langage

### 3.1 Lignes, commentaires, casse

- Une instruction par ligne. Une ligne terminée par `;` continue sur la suivante.
  À l'intérieur de parenthèses, crochets ou accolades, les fins de ligne sont libres.
- Commentaires : `&&` ou `//` jusqu'à la fin de la ligne ; `*` en début de ligne.
- Les **mots-clés** s'écrivent en minuscules (`si`, `pour`, `procedure`...).
- Les **noms** (variables, procédures, champs) ne tiennent pas compte de la casse :
  `total`, `Total` et `TOTAL` désignent la même variable ; `t.nom` et `t.NOM` le
  même champ. Les lettres accentuées sont permises ; `à` peut s'écrire `a`.
- Afficher : `? valeur, ...` (séparées par un espace, puis fin de ligne) ;
  `?? valeur, ...` sans fin de ligne.

```lexis
* commentaire de début de ligne
locale total = 1 + 2 + ;
               3          && suite de la ligne précédente
?? "total : "
? total                   // 6
```

### 3.2 Valeurs et types

| Type (`type(v)`) | Exemples | Remarques |
| --- | --- | --- |
| `nul` | `nul` | absence de valeur ; s'affiche vide |
| `logique` | `vrai`, `faux`, `.v.`, `.f.` | seuls `nul` et `faux` sont faux dans un `si` (`0` et `""` sont vrais) |
| `nombre` | `42`, `3.14`, `1e3` | entiers et décimaux ; `5.0` s'affiche `5` |
| `chaine` | `"texte"`, `'texte'`, `[[sur plusieurs lignes]]` | échappements `\n \t \" \\` |
| `table` | `{1, 2}`, `{nom = "Ada"}` | listes, fiches, objets |
| `procedure` | `@CARRE` | référence de procédure |
| `objet` | fenêtre, fichier, socket... | objets fournis par les paquets |

Conversions : `chaine(v)`, `texte(v)`, `valeur("12,5")` (12.5 ; 0 si impossible),
`nombre("x")` (nul si impossible). Le calcul accepte les chaînes numériques et la
virgule décimale : `"12,5" * 2` vaut 25.

### 3.3 Opérateurs

| Opérateurs | Sens |
| --- | --- |
| `+ - * / % ^` (`**`) | calcul ; `%` reste (du signe du diviseur) ; `/` par zéro est une erreur |
| `+` avec une chaîne, `..` | concaténation : `"a" + 1` vaut `"a1"` |
| `=` `==` | égalité (dans une expression) |
| `<>` `!=` `#` | différence |
| `< <= > >=` | comparaison de nombres ou de chaînes |
| `$` | inclusion : `"jour" $ "Bonjour"` est vrai |
| `et ou non` (`.et. .ou. .non.`) | logique ; `et` et `ou` renvoient l'une des deux valeurs |
| `#t` | longueur d'une chaîne (en caractères) ou d'une liste |
| `sisinon(c, a, b)` | `a` si `c`, sinon `b` (seule la branche choisie est calculée) |

```lexis
? 10 / 4, 7 % 3, 2 ^ 10, "a" + 1, "jour" $ "Bonjour"
? nul ou "défaut", sisinon(3 > 2, "oui", "non"), #"héllo"
```

### 3.4 Variables

- `locale x [= valeur]` déclare une variable de la procédure (ou du programme
  principal). Plusieurs à la fois : `locale a = 1, b, c = 3`.
- Les paramètres, la variable de `pour`, celles de `pour chaque` et de
  `capturer` sont aussi locaux.
- **Tout nom non déclaré est global** : il est partagé par tout le programme et
  rangé dans la table `SESSION`. C'est commode pour les données de l'application
  (et indispensable pour les gestionnaires d'événements, qui sont des procédures)
  mais c'est aussi le piège le plus courant : l'atelier signale les affectations de
  variables non déclarées dans une procédure (option *Affichage > Signaler les
  variables globales implicites*).
- `globale x [= valeur]` assume explicitement une variable globale.
- `stocker valeur dans a, b` affecte la même valeur à plusieurs variables.
- `x += 1`, `x -= 1`.
- `liberer x` remet une variable à `nul`.

```lexis
compteur = 0                 && globale (programme principal)
AUGMENTER()
AUGMENTER()
? compteur, SESSION.COMPTEUR

procedure AUGMENTER
  locale pas = 1             && locale
  compteur += pas            && globale : partagée
retourner
```

### 3.5 Conditions

```lexis
locale note = 14
si note >= 16
  ? "très bien"
sinonsi note >= 12           && ou : sinon si
  ? "bien"
sinon
  ? "à revoir"
finsi

faire cas
cas note < 10
  ? "insuffisant"
cas note < 15
  ? "correct"
autrement
  ? "excellent"
fincas
```

### 3.6 Boucles

```lexis
pour i = 10 a 1 pas -3      && « jusqua » est aussi accepté
  ?? i, ""
suivant
?

locale n = 0
tantque n < 3               && ou : faire tantque
  n += 1
fintantque

pour chaque v dans {"a", "b"}           && valeurs
  ?? v, ""
suivant
pour chaque k, v dans {x = 1, y = 2}    && clefs et valeurs
  ?? k + "=" + v, ""
suivant
?
pour i = 1 a 10
  si i % 2 = 0
    boucler                 && tour suivant
  finsi
  si i > 7
    sortir                  && quitte la boucle
  finsi
  ?? i, ""
suivant
?
```

`pour chaque` accepte aussi un **itérateur** : une procédure (souvent fournie par
un paquet, comme `es.lignes(chemin)`) appelée à chaque tour jusqu'à ce qu'elle
renvoie `nul`.

### 3.7 Procédures et fonctions

```lexis
? AIRE(3, 4), AIRE(5)       && un argument manquant vaut nul
faire SALUER avec "Ada"     && forme dBase de l'appel
SALUER("Bob")

fonction AIRE(l, h)
  si h = nul
    h = l
  finsi
retourner l * h

procedure SALUER(qui)
  ? "Bonjour", qui
retourner
```

- `procedure` et `fonction` sont équivalents ; `retourner [valeur]` renvoie une
  valeur (`nul` sinon).
- `parametres a, b` relit les arguments dans des variables locales (style dBase).
- `@NOM` est une **référence** de procédure, à passer à `trier`, `appeler`, aux
  gestionnaires d'événements, aux tâches, aux métatables :

```lexis
locale notes = {12, 8, 17}
trier(notes, @DECROISSANT)
? joindre(notes, " "), appeler(@DECROISSANT, 2, 1)

fonction DECROISSANT(a, b)
retourner a > b
```

- Un appel avec une seule table d'options peut s'écrire sans parenthèses :
  `ui.fenetre{titre = "x"}` équivaut à `ui.fenetre({titre = "x"})`.
- La récursion est limitée à 200 niveaux.

### 3.8 Tables

Une table est à la fois une **liste** (index 1, 2, 3...) et une **fiche** (clefs).

```lexis
locale fruits = {"pomme", "poire"}
inserer "kiwi" dans fruits                  && à la fin
inserer "abricot" dans fruits position 1
retirer de fruits position 2 dans enleve    && enleve reçoit "pomme"
? joindre(fruits, ", "), #fruits, enleve

nouvelle table client
client.nom = "Durand"              && clef NOM (insensible à la casse)
client["Ville"] = "Brest"          && clef exacte, sensible à la casse
inserer "France" dans client clef "PAYS"
? client.NOM, client["Ville"], client.pays, aclef(client, "VILLE")

locale cmd = {numero = 12, lignes = {{article = "stylo", qte = 3}}}
? cmd.lignes[1].article, json(cmd)
supprimer table client
```

Une table est partagée, pas copiée : `b = a` désigne la même table ; `copier(a)`
en fait une copie de premier niveau.

### 3.9 Objets et métatables

Une procédure peut être rangée dans une table (`t:procedure NOM comme methode`) et
appelée avec `:` ; la table est alors passée en premier argument.

```lexis
Compte = {}
Compte.__index = Compte
Compte:procedure COMPTE_DEPOSER comme deposer
Compte:procedure COMPTE_TEXTE comme __tostring

c = fixermetatable({titulaire = "Ada", solde = 0}, Compte)
c:deposer(50)
c:deposer(25)
? texte(c)

procedure COMPTE_DEPOSER(soi, montant)
  soi.solde += montant
retourner

fonction COMPTE_TEXTE(soi)
retourner soi.titulaire + " : " + soi.solde + " €"
```

Métaméthodes reconnues : `__index`, `__newindex`, `__call`, `__tostring`, `__len`,
`__eq`, `__lt`, `__le`, `__add`, `__sub`, `__mul`, `__div`, `__mod`, `__pow`,
`__concat`, `__unm`. `lirebrut` / `ecrirebrut` contournent les métaméthodes.

### 3.10 Erreurs

```lexis
essayer
  ? 1 / 0
capturer e
  ? "erreur :", e           && e reçoit le message, sans position
finessayer

essayer
  erreur "montant invalide"
capturer e
  ? "levée :", e
finessayer
```

Une erreur non interceptée arrête le programme : l'atelier affiche le message,
la pile d'appels, et place le curseur sur la ligne fautive. Les paquets signalent
leurs échecs (fichier introuvable, connexion refusée...) par des erreurs que l'on
intercepte de la même façon.

---

## 4. Base de données (DuckDB)

Le programme dispose d'une base **DuckDB**, ouverte à la première requête : par
défaut le fichier `donnees.duckdb` du dossier du programme. `ouvrirbase(chemin)`
en choisit une autre (`":memoire:"` : base en mémoire), `fermerbase()` la ferme,
`base()` donne son chemin.

### 4.1 En SQL

```lexis
ouvrirbase(":memoire:")
sql "create table produits(id integer primary key, libelle varchar, prix double)"
sql "insert into produits values (?, ?, ?)" avec 1, "Stylo", 1.5
sql "insert into produits values (?, ?, ?)" avec 2, "Cahier", 3.2
sql "select * from produits where prix > ? order by prix" avec 1 dans liste
pour chaque p dans liste
  ? p.id, p.libelle, p.PRIX       && colonnes en majuscules
suivant
? valeursql("select count(*) from produits"), #requete("select * from produits")
```

Toujours des paramètres `?` (avec `avec`), jamais de valeurs collées dans le
texte SQL.

### 4.2 Enregistrement par enregistrement (zones, à la manière de dBase)

```lexis
ouvrirbase(":memoire:")
sql "create table clients(code varchar primary key, nom varchar, ville varchar)"
sql "insert into clients values ('C1', 'Durand', 'Lyon'), ('C2', 'Martin', 'Brest')"

utiliser clients ordre "nom" alias cli
parcourir pour ville = "Brest"
  ? numenr(), code, nom              && champs lus directement par leur nom
finparcourir
chercher "Durand"                   && sur la première colonne de l'ordre
si trouve()
  remplacer ville par "Paris"
finsi
ajouter avec code par "C3", nom par "Petit", ville par "Lyon"
compter pour ville = "Lyon" dans n
? n, cli->ville, nbenr()
aller haut
? nom, m->n                         && m->x : la variable x (et non un champ)
fermer cli
```

| Instruction | Rôle (équivalent dBase) |
| --- | --- |
| `utiliser table [alias a] [ordre "sql"] [filtre "sql"]` | ouvre une zone (`USE`) |
| `selectionner alias` / `fermer [alias \| tout]` | change de zone / ferme (`SELECT`, `CLOSE`) |
| `aller haut \| bas \| n`, `sauter [n]` | se déplacer (`GO`, `SKIP`) |
| `chercher valeur` / `localiser pour cond` / `continuer` | rechercher (`SEEK`, `LOCATE`, `CONTINUE`) |
| `ajouter [vide \| avec champ par v, ...]` | nouvel enregistrement (`APPEND`) |
| `remplacer champ par v, ...` / `effacer` | modifier / supprimer (`REPLACE`, `DELETE`) |
| `parcourir [pour cond] ... finparcourir` | boucle sur la zone (`SCAN`) |
| `compter [pour cond] dans x` / `rafraichir` | compter (`COUNT`) / relire |
| `fdf() ddf() numenr() nbenr() trouve() alias()` | `EOF() BOF() RECNO() RECCOUNT() FOUND() ALIAS()` |
| `champ(nom [, alias])`, `enregistrement([alias])`, `alias->champ` | lecture de champs |

Dans une zone ouverte, un nom de champ se lit comme une variable ; `m->nom`
désigne explicitement la variable.

---

## 5. Interface graphique

Le paquet `interface` donne accès à wdgui. Les **gestionnaires d'événements** sont
des procédures (`@NOM`) qui reçoivent l'événement ; les variables partagées entre
le programme et les gestionnaires sont donc **globales**.

```lexis-interface
ui = paquet("interface")
fen = ui.fenetre{titre = "Convertisseur", largeur = 360, hauteur = 180}
saisie = fen:ajouter(ui.saisie{indication = "Montant en euros"})
resultat = fen:ajouter(ui.etiquette("", "centre"))
bouton = fen:ajouter(ui.bouton("Convertir", {defaut = vrai}))
bouton.surclic = @CONVERTIR
ui.executer()

procedure CONVERTIR(ev)
  locale euros = nombre(saisie.valeur)
  si euros = nul
    ui.alerte("Montant invalide", "attention")
    retourner
  finsi
  resultat.valeur = chaine(euros * 1.08, 1, 2) + " $"
retourner
```

- Contrôles : `fenetre`, `etiquette`, `bouton`, `saisie`, `cases`, `radio`,
  `liste`, `combo`, `tableau`, `arbre`, `grille`, `jauge`, `curseur`, `plage`,
  `ascenseur`, `compteur`, `notation`, `image`, `codebarre`, `graphe`,
  `calendrier`, `kanban`, `mosaique`, `gantt`, `barremenu`, `onglets`,
  `separateur`, `conteneur`, `colonne`, `rangee`, `superconteneur`, `cadre`,
  `panneau`, `pdf`. Un contrôle s'ajoute avec `conteneur:ajouter(controle)`.
- Propriétés : `valeur`, `num`, `libelle` (ou `titre`), `texte`, `visible`, `etat`
  (`actif`, `grise`, `lecture`), `actif`, `infobulle`, `nom`, `x`, `y`, `largeur`,
  `hauteur`, `couleur`, `fond`, `bordure`, `accent`, `rayon`, `coche`, `min`, `max`,
  `ancrage` (`haut`, `bas`, `gauche`, `droite`, `centre`), `poids`, `largeurfixe`,
  `hauteurfixe`, `etirer`, `marge`, `espacement`, `colonnes`, `famille`, `genre`.
- Événements : `surclic`, `surdoubleclic`, `surclicdroit`, `surchangement`,
  `surselection`, `surtouchebas`, `surtouchehaut`, `sursaisie`, `surfocus`,
  `surfinfocus`, `surentree`, `sursortie`, `surdeplacement`, `surmolette`,
  `surdeploiement`, `surrepli`, `survalidation`, `surouverture`, `surfermeture`,
  `surredimension`, `suractivation`, `surdesactivation`, et `surevenement` pour
  tous. L'événement `ev` a les champs `genre`, `id`, `courant`, `x`, `y`, `dx`,
  `dy`, `touche`, `modificateurs`, `index`, `colonne`, `bouton`, `texte`,
  `chemin` ; `ev:arreter()` arrête sa propagation aux conteneurs.
- `ui.executer()` attend la fermeture des fenêtres ; dans le runtime, si le
  programme se termine sans l'appeler, la boucle de l'interface est lancée
  automatiquement.
- `ui.tracer(vrai)` affiche dans la console chaque événement reçu.

L'exemple `exemples/carnet` montre une grille, une barre de menus et une base.

---

## 6. Multitâche

- **Tâches** (`tache`) : des procédures qui s'exécutent à tour de rôle dans le même
  programme ; une tâche rend la main par `tache.ceder()`, `tache.attendre(s)` ou en
  attendant un canal. Une attente bloquante (réseau, `systeme.attendre`) bloque
  toutes les tâches : pour cela, utilisez un fil.
- **Fils d'exécution** (`fil`) : un vrai fil du système, avec son propre
  interpréteur et ses propres variables ; on échange des valeurs par messages.

```lexis
canal = tache.canal()
tache.lancer(@PRODUIRE)
tache.lancer(@CONSOMMER)
tache.executer()

f = fil.demarrer([[
locale s = 0
pour i = 1 a fil.recevoir()
  s += i
suivant
fil.envoyer({somme = s})
]])
f:envoyer(1000)
? "somme :", f:recevoir().SOMME
f:joindre()

procedure PRODUIRE
  pour i = 1 a 3
    canal:envoyer(i * 10)
    tache.ceder()
  suivant
  canal:envoyer("fin")
retourner

procedure CONSOMMER
  tantque vrai
    locale v = canal:recevoir()
    si v = "fin"
      sortir
    finsi
    ? "reçu", v
  fintantque
retourner
```

---

## 7. Paquets

Les fonctions intégrées (chapitre 11) sont toujours disponibles, ainsi que les
paquets `es` (entrées / sorties) et `systeme`. Les autres paquets s'utilisent
directement par leur nom — `fichier.lire(chemin)`, `json.encoder(t)` — ou se
rangent dans une variable : `ui = paquet("interface")`.

```lexis
locale chemin = fichier.joindre(fichier.dossiertemp(), "essai.txt")
fichier.ecrire(chemin, "un" + car(10) + "deux" + car(10))
pour chaque l dans es.lignes(chemin)
  ? "ligne :", l
suivant
? systeme.date("%A %d %B %Y", 0)
locale lignes = csv.analyser("nom,age" + car(10) + "Ada,36", {entete = vrai})
? lignes[1].nom, lignes[1].AGE + 1, joindre(lignes.entete, "|")
? json.encoder({nom = "Ada", langages = {"Lexis+"}})
```

Les objets des paquets (fichiers, sockets, contrôles...) ont des méthodes qui
s'appellent avec `:` : `f:lire()`, `s:envoyer(donnees)`, `liste:ajouter("x")`.

---

## 8. L'atelier

| Touche | Action |
| --- | --- |
| Ctrl+R | exécuter (sans débogueur, plus rapide) |
| F5 | déboguer (s'arrête aux points d'arrêt) / continuer |
| F9, clic dans la marge | point d'arrêt |
| F11 / F10 / Maj+F11 | pas à pas / pas principal / sortir de la procédure |
| Maj+F5 | arrêter |
| Ctrl+Espace | complétion |
| Ctrl+B | commenter / décommenter (`&&`) |
| F12 ou Ctrl+clic | aller à la définition d'une procédure |

- **Analyse en continu** : erreurs de syntaxe (le vrai analyseur de
  l'interpréteur), appels de procédures inconnues, variables non déclarées dans
  les procédures. Onglet **Problèmes** ; double-clic pour aller à la ligne.
- **Structure** : les procédures et les variables globales du fichier.
- **Référence** : toutes les fonctions intégrées et les paquets ; double-clic pour
  insérer l'appel.
- **Diagramme de structure** dans la marge : procédures, `si`, boucles,
  `faire cas`, `essayer`.
- **Console** : sortie du programme ; la ligne de saisie répond à `saisir()` et
  `es.lire()`.
- En pause : ligne courante surlignée, **Variables** (paramètres, locales,
  globales et zone de base de données courante), **Pile d'appels** (cliquer un
  niveau affiche ses variables).
- Les documents ouverts sont exécutés tels qu'à l'écran, même non enregistrés.

## 9. Le runtime

```
wdlexisrt programme.prg [arguments...]   exécute (avec les .prg du dossier)
wdlexisrt --verifier programme.prg       vérifie la syntaxe
wdlexisrt -e "? 1 + 1"                   exécute du code
wdlexisrt --paquets                      liste les paquets
```

Les arguments sont dans `systeme.args` (`systeme.args[0]` est le chemin du
programme). `systeme.quitter(code)` termine le programme avec un code de retour.

## 10. Différences avec le serveur wdGestion V

| Sur le serveur | Sur le poste (wdlexis+) |
| --- | --- |
| Fichiers `.prg` du dossier `PROG`, appelés par le navigateur | Fichiers `.prg` du projet ; programme principal en tête de `principal.prg` |
| `SESSION` : mémoire du visiteur | `SESSION` : variables globales du programme |
| Pages, `envoyer`, `rediriger`, `statut`, `entete`, `deconnecter`, `REQUETE` | non disponibles (erreur de syntaxe explicite) |
| Base configurée dans le JSON du serveur | `donnees.duckdb` du dossier du programme, ou `ouvrirbase()` |
| Limites d'instructions et de durée par requête | pas de limite (bouton **Arrêter**) |
| — | paquets (interface, fichiers, réseau...), `saisir()`, appels `f{...}`, itérateurs dans `pour chaque` |

---

## 11. Référence des fonctions intégrées et des paquets

### Fonctions intégrées

Fonctions intégrées de Lexis+

| Appel | Rôle |
| --- | --- |
| `majuscule(s)` | Texte en majuscules (accents compris). |
| `minuscule(s)` | Texte en minuscules. |
| `rogner(s)` | Retire les espaces aux deux bouts (ALLTRIM). |
| `rognerg(s)` | Retire les espaces à gauche (LTRIM). |
| `rognerd(s)` | Retire les espaces à droite (RTRIM). |
| `longueur(s)` | Nombre de caractères (ou d'éléments d'une liste). |
| `souschaine(s, debut, [n])` | Extrait n caractères à partir de debut (SUBSTR) ; positions à partir de 1. |
| `gauche(s, n)` | Les n premiers caractères. |
| `droite(s, n)` | Les n derniers caractères. |
| `position(sous, s)` | Position de sous dans s, 0 si absente (AT). |
| `chaine(v, [largeur], [decimales])` | Texte d'une valeur ; avec largeur : nombre aligné à droite (STR). |
| `texte(v)` | Texte d'une valeur (utilise __tostring). |
| `valeur(s)` | Nombre d'un texte (virgule décimale admise), 0 si impossible (VAL). |
| `nombre(s)` | Nombre d'un texte, nul si impossible. |
| `espace(n)` | n espaces (SPACE). |
| `repliquer(s, n)` | s répété n fois (REPLICATE). |
| `remplacertexte(s, a, b)` | Remplace toutes les occurrences de a par b (STRTRAN). |
| `contient(s, sous)` | Vrai si s contient sous ; avec une table : vrai si la valeur y figure. |
| `commencepar(s, debut)` | Vrai si s commence par debut. |
| `finitpar(s, fin)` | Vrai si s finit par fin. |
| `decouper(s, [separateur])` | Liste des morceaux (séparateur « , » par défaut). |
| `joindre(liste, [separateur])` | Texte des éléments d'une liste. |
| `html(s)` | Échappe < > & " ' pour le HTML. |
| `url(s)` | Encode un texte pour une URL. |
| `car(code, ...)` | Caractères à partir de leurs codes Unicode. |
| `code(s, [i])` | Code Unicode du i-ème caractère. |
| `abs(x)` | Valeur absolue. |
| `entier(x)` | Partie entière, vers zéro (INT). |
| `arrondi(x, [decimales])` | Arrondi (0 décimale par défaut). |
| `plancher(x)` | Entier inférieur. |
| `plafond(x)` | Entier supérieur. |
| `racine(x)` | Racine carrée. |
| `mod(a, b)` | Reste de la division, du signe du diviseur. |
| `max(a, b, ...)` | Plus grande valeur (nombres ou chaînes). |
| `min(a, b, ...)` | Plus petite valeur. |
| `aleatoire([n])` | Réel entre 0 et 1, ou entier entre 1 et n. |
| `sin(x)` | Sinus (radians). |
| `cos(x)` | Cosinus. |
| `tan(x)` | Tangente. |
| `asin(x)` | Arc sinus. |
| `acos(x)` | Arc cosinus. |
| `atan(y, [x])` | Arc tangente (atan2 avec deux arguments). |
| `exp(x)` | Exponentielle. |
| `log(x, [base])` | Logarithme (népérien par défaut). |
| `pi()` | π. |
| `type(v)` | "nul", "logique", "nombre", "chaine", "table", "procedure", "objet" ou "tache". |
| `estnul(v)` | Vrai si v vaut nul. |
| `vide(v)` | Vrai pour nul, faux, 0, une chaîne blanche ou une table sans élément (EMPTY). |
| `sisinon(condition, si_vrai, si_faux)` | Valeur selon la condition ; seule la branche choisie est calculée (IIF). |
| `date()` | Date du jour, AAAA-MM-JJ. |
| `heure()` | Heure, HH:MM:SS. |
| `maintenant()` | Date et heure. |
| `horodatage()` | Secondes depuis le 1er janvier 1970 (avec décimales). |
| `taille(t)` | Nombre d'éléments de la partie liste (#t). |
| `nbelements(t)` | Nombre total d'éléments. |
| `clefs(t)` | Liste des clefs. |
| `valeurs(t)` | Liste des valeurs. |
| `aclef(t, k)` | Vrai si la clef existe. |
| `copier(t)` | Copie de premier niveau. |
| `fixermetatable(t, mt)` | Donne une métatable ; renvoie t. |
| `obtenirmetatable(t)` | La métatable ou nul. |
| `lirebrut(t, k)` | Lecture sans métaméthode. |
| `ecrirebrut(t, k, v)` | Écriture sans métaméthode ; renvoie t. |
| `inserer(t, v, [position])` | Ajoute v (à la fin ou à la position) ; renvoie t. |
| `retirer(t, [position])` | Enlève et renvoie un élément (le dernier par défaut). |
| `trier(t, [@comparer])` | Trie la liste sur place ; renvoie t. |
| `appeler(@proc, ...)` | Appelle une procédure référencée. |
| `json(v)` | Texte JSON d'une valeur. |
| `dejson(s)` | Valeur d'un texte JSON (clefs d'objets en majuscules). |
| `requete(sql, ...)` | Liste des lignes d'une requête DuckDB (paramètres « ? »). |
| `valeursql(sql, ...)` | Première valeur de la première ligne, ou nul. |
| `ouvrirbase(chemin)` | Ouvre une base DuckDB (":memoire:" pour une base en mémoire) ; par défaut donnees.duckdb du dossier du programme. |
| `fermerbase()` | Ferme la base et les zones. |
| `base()` | Chemin de la base ouverte ("" si aucune). |
| `hachage(s)` | Empreinte SHA-256 en hexadécimal (pas pour les mots de passe). |
| `hachermdp(mdp)` | Empreinte PBKDF2-SHA256 salée d'un mot de passe. |
| `verifiermdp(mdp, empreinte)` | Vérifie un mot de passe (temps constant). |
| `mdpaleatoire([n])` | Mot de passe aléatoire (16 caractères par défaut). |
| `uuid()` | Identifiant unique aléatoire. |
| `fdf([alias])` | Fin de fichier de la zone (EOF). |
| `ddf([alias])` | Début de fichier (BOF). |
| `numenr([alias])` | Numéro de l'enregistrement courant (RECNO). |
| `nbenr([alias])` | Nombre d'enregistrements (RECCOUNT). |
| `trouve([alias])` | Résultat du dernier chercher / localiser (FOUND). |
| `alias()` | Alias de la zone courante. |
| `champ(nom, [alias])` | Valeur d'un champ par son nom (FIELD). |
| `enregistrement([alias])` | L'enregistrement courant sous forme de table. |
| `paquet(nom)` | Charge un paquet : interface, fichier, json, csv, http, reseau, tache... |
| `saisir([invite])` | Lit une ligne saisie (console de l'atelier ou terminal) ; nul en fin d'entrée. |

### Paquet `es`

Entrées / sorties : console et fichiers — toujours disponible.

| Appel | Rôle |
| --- | --- |
| `es.ecrire(...)` | Écrit les valeurs (sans séparateur ni fin de ligne) sur la sortie : console de l'atelier ou terminal. |
| `es.lire([format])` | Lit l'entrée : "l" une ligne (défaut), "n" un nombre, "L" une ligne avec sa fin ; nul en fin d'entrée. |
| `es.lignes([chemin])` | Itérateur sur les lignes d'un fichier (ou de l'entrée) : pour chaque l dans es.lignes(chemin). |
| `es.ouvrir(chemin, [mode])` | Ouvre un fichier : "l" lecture (défaut), "e" écriture, "a" ajout, "l+", "e+". |
| `es.type(v)` | "fichier", "fichier fermé" ou nul. |
| `es.sortie` | Sortie standard. |
| `es.erreur` | Sortie d'erreur. |
| `es.entree` | Entrée standard. |
| `f:lire([format])` | Lit : "l", "L", "n", "t" (tout) ou un nombre d'octets ; nul en fin de fichier. |
| `f:ecrire(...)` | Écrit des valeurs ; renvoie le fichier. |
| `f:lignes()` | Itérateur sur les lignes restantes. |
| `f:position([origine], [decalage])` | Déplace la position ("debut", "courant", "fin") et la renvoie. |
| `f:vider()` | Vide les tampons. |
| `f:fermer()` | Ferme le fichier. |

### Paquet `systeme`

Système d'exploitation — toujours disponible.

| Appel | Rôle |
| --- | --- |
| `systeme.temps([date])` | Heure actuelle (secondes Unix), ou date d'une table {annee, mois, jour, heure, minute, seconde}. |
| `systeme.horloge()` | Temps écoulé depuis le lancement, en secondes (horloge monotone). |
| `systeme.date([format], [t])` | Date formatée : %Y %m %d %H %M %S %A (jour) %B (mois) %F %T %x... ; "*t" renvoie une table ; "!" en tête pour l'heure UTC. |
| `systeme.ecart(t2, t1)` | Différence en secondes. |
| `systeme.env(nom)` | Variable d'environnement (nul si absente). |
| `systeme.fixerenv(nom, valeur)` | Définit une variable d'environnement. |
| `systeme.executer(commande)` | Exécute une commande système ; renvoie son code de retour. |
| `systeme.capturer(commande)` | Exécute une commande ; renvoie {sortie, code}. |
| `systeme.supprimer(chemin)` | Supprime un fichier ou un dossier. |
| `systeme.renommer(ancien, nouveau)` | Renomme un fichier. |
| `systeme.nomtemporaire()` | Nom de fichier temporaire. |
| `systeme.quitter([code])` | Termine le programme. |
| `systeme.attendre(secondes)` | Pause (les fenêtres restent réactives). |
| `systeme.plateforme()` | "linux", "macosx", "windows"... |
| `systeme.dossierprogramme()` | Dossier du programme principal. |
| `systeme.args` | Arguments du programme ; systeme.args[0] est le chemin du programme. |

### Paquet `fichier`

Fichiers et dossiers (texte et binaire) — disponible par son nom (`fichier.…`) ou par `paquet("fichier")`.

| Appel | Rôle |
| --- | --- |
| `fichier.lire(chemin)` | Contenu complet d'un fichier (texte ou binaire). |
| `fichier.lireoctets(chemin)` | Contenu binaire (les chaînes sont des suites d'octets). |
| `fichier.ecrire(chemin, donnees)` | Remplace le contenu d'un fichier. |
| `fichier.ecrireoctets(chemin, donnees)` | Écrit des octets. |
| `fichier.ajouter(chemin, donnees)` | Ajoute à la fin d'un fichier. |
| `fichier.lignes(chemin)` | Liste des lignes d'un fichier. |
| `fichier.ecrirelignes(chemin, lignes)` | Écrit une liste de lignes. |
| `fichier.existe(chemin)` | Vrai si le fichier ou le dossier existe. |
| `fichier.estfichier(chemin)` | Vrai pour un fichier. |
| `fichier.estdossier(chemin)` | Vrai pour un dossier. |
| `fichier.taille(chemin)` | Taille en octets. |
| `fichier.liste([dossier], [recursif])` | Noms contenus dans un dossier (les dossiers finissent par /). |
| `fichier.creerdossier(chemin)` | Crée un dossier (et ses parents). |
| `fichier.supprimer(chemin)` | Supprime un fichier ou un dossier (récursif). |
| `fichier.copier(source, destination)` | Copie (dossiers récursivement). |
| `fichier.deplacer(source, destination)` | Déplace ou renomme. |
| `fichier.infos(chemin)` | Table {taille, genre ("fichier" ou "dossier"), modifie, cree} ou nul. |
| `fichier.courant()` | Dossier courant. |
| `fichier.changer(dossier)` | Change de dossier courant. |
| `fichier.joindre(a, b, ...)` | Assemble des chemins. |
| `fichier.nom(chemin)` | Nom du fichier. |
| `fichier.dossier(chemin)` | Dossier parent. |
| `fichier.extension(chemin)` | Extension. |
| `fichier.absolu(chemin)` | Chemin absolu. |
| `fichier.dossiertemp()` | Dossier temporaire. |
| `fichier.dossierperso()` | Dossier personnel. |

### Paquet `binaire`

Données binaires — disponible par son nom (`binaire.…`) ou par `paquet("binaire")`.

| Appel | Rôle |
| --- | --- |
| `binaire.coder(format, ...)` | Code des valeurs en binaire. Format : < petit-boutiste, > gros-boutiste, b/B 8 bits, h/H 16, i/I 32 (iN : N octets), l/L/j/J 64, f flottant 32, d flottant 64, z chaîne terminée par zéro, s chaîne préfixée par sa longueur, cN chaîne de N octets, x octet nul. |
| `binaire.decoder(format, donnees, [position])` | Décode ; renvoie la liste des valeurs, avec le champ suite (position suivante). |
| `binaire.taille(format)` | Taille d'un format fixe. |
| `binaire.hex(donnees)` | Représentation hexadécimale. |
| `binaire.dehex(hex)` | Octets à partir de l'hexadécimal. |

### Paquet `json`

JSON — disponible par son nom (`json.…`) ou par `paquet("json")`.

| Appel | Rôle |
| --- | --- |
| `json.encoder(valeur, [joli])` | Texte JSON ; une liste 1..n devient un tableau, sinon un objet (joli = vrai : indenté). |
| `json.decoder(texte, [exact])` | Valeur Lexis+ ; les clefs d'objets sont mises en majuscules sauf si exact = vrai. |
| `json.lire(chemin, [exact])` | Lit et décode un fichier JSON. |
| `json.ecrire(chemin, valeur, [joli])` | Encode et écrit un fichier JSON (indenté par défaut). |
| `json.nul` | Valeur représentant null dans les données à encoder. |

### Paquet `csv`

Fichiers CSV — disponible par son nom (`csv.…`) ou par `paquet("csv")`.

| Appel | Rôle |
| --- | --- |
| `csv.analyser(texte, [options])` | Liste des lignes d'un texte CSV. options : sep (","), entete (faux : lignes = listes ; vrai : lignes = tables par nom de colonne, et lignes.entete donne les noms), convertir (vrai : nombres convertis). |
| `csv.lire(chemin, [options])` | Lit un fichier CSV (mêmes options). |
| `csv.encoder(lignes, [options])` | Texte CSV. options : sep, entete (liste des colonnes, ou vrai pour les déduire). |
| `csv.ecrire(chemin, lignes, [options])` | Écrit un fichier CSV. |

### Paquet `reseau`

Sockets TCP/UDP — disponible par son nom (`reseau.…`) ou par `paquet("reseau")`.

| Appel | Rôle |
| --- | --- |
| `reseau.connecter(hote, port, [options])` | Connexion TCP. options : tls (vrai pour TLS, -d:ssl), delai (secondes). |
| `reseau.ecouter(port, [hote])` | Socket serveur TCP. |
| `reseau.udp([port], [hote])` | Socket UDP, éventuellement lié à un port. |
| `reseau.resoudre(hote)` | Adresse IP d'un nom. |
| `reseau.nomhote()` | Nom de la machine. |
| `s:envoyer(donnees)` | Envoie des octets ; renvoie le nombre envoyé. |
| `s:recevoir([mode])` | Reçoit : "l" une ligne (défaut), "t" tout jusqu'à la fermeture, ou un nombre d'octets ; nul si la connexion est fermée. |
| `s:delai(secondes)` | Délai maximal des réceptions (nul = aucun). |
| `s:accepter()` | Attend un client (socket serveur) ; renvoie son socket. |
| `s:envoyervers(donnees, port, hote)` | Envoi UDP. |
| `s:recevoirde([taille])` | Réception UDP : {donnees, adresse, port}. |
| `s:distant()` | {adresse, port} de l'autre extrémité. |
| `s:fermer()` | Ferme le socket. |

### Paquet `http`

Client HTTP/HTTPS — disponible par son nom (`http.…`) ou par `paquet("http")`.

| Appel | Rôle |
| --- | --- |
| `http.lire(url, [entetes])` | Requête GET ; renvoie le corps de la réponse. |
| `http.envoyer(url, corps, [entetes])` | Requête POST ; renvoie le corps de la réponse. |
| `http.requete{methode=, url=, entetes=, corps=, delai=}` | Requête quelconque ; renvoie {statut, raison, corps, entetes} (en-têtes en minuscules : r.entetes["content-type"]). |
| `http.telecharger(url, chemin)` | Télécharge dans un fichier ; renvoie le statut. |
| `http.encoder(texte \| table)` | Encodage d'URL (une table devient a=1&b=2). |
| `http.decoder(texte)` | Décodage d'URL. |

### Paquet `ftp`

Client FTP — disponible par son nom (`ftp.…`) ou par `paquet("ftp")`.

| Appel | Rôle |
| --- | --- |
| `ftp.connecter{hote=, port=21, utilisateur="anonymous", motdepasse=""}` | Ouvre une session FTP (mode passif). |
| `c:liste([chemin], [detail])` | Noms des fichiers (detail = vrai : format détaillé). |
| `c:lire(distant, [local])` | Télécharge : renvoie les données, ou les écrit dans le fichier local. |
| `c:envoyer(local_ou_donnees, [distant], [sontdesdonnees])` | Envoie un fichier local (ou des données). |
| `c:dossier(chemin)` | Change de dossier distant. |
| `c:courant()` | Dossier distant courant. |
| `c:creerdossier(chemin)` | Crée un dossier. |
| `c:supprimerdossier(chemin)` | Supprime un dossier. |
| `c:supprimer(chemin)` | Supprime un fichier. |
| `c:renommer(ancien, nouveau)` | Renomme. |
| `c:fermer()` | Ferme la session. |

### Paquet `ssh`

SSH (client OpenSSH) — disponible par son nom (`ssh.…`) ou par `paquet("ssh")`.

| Appel | Rôle |
| --- | --- |
| `ssh.connecter{hote=, utilisateur=, port=22, clef=, motdepasse=, options={}}` | Ouvre une session (vérifie la connexion). Authentification par clef ; motdepasse demande sshpass. |
| `ssh.executer{hote=, utilisateur=, commande=, ...}` | Exécute une commande sans garder de session : {sortie, code}. |
| `session:executer(commande)` | Exécute une commande distante : {sortie, code}. |
| `session:lire(distant, [local])` | Télécharge un fichier ou dossier (scp). |
| `session:envoyer(local, [distant])` | Envoie un fichier ou dossier (scp). |
| `session:liste([chemin])` | Noms d'un dossier distant (sftp). |
| `session:creerdossier(chemin)` | Crée un dossier distant (sftp). |
| `session:supprimerdossier(chemin)` | Supprime un dossier distant (sftp). |
| `session:supprimer(chemin)` | Supprime un fichier distant (sftp). |
| `session:renommer(ancien, nouveau)` | Renomme (sftp). |

### Paquet `sftp`

SFTP : mêmes sessions que ssh — disponible par son nom (`sftp.…`) ou par `paquet("sftp")`.

| Appel | Rôle |
| --- | --- |
| `sftp.connecter{hote=, utilisateur=, port=22, clef=, motdepasse=}` | Ouvre une session de transfert (identique à ssh.connecter). |

### Paquet `sqlite`

Bases SQLite — disponible par son nom (`sqlite.…`) ou par `paquet("sqlite")`.

| Appel | Rôle |
| --- | --- |
| `sqlite.ouvrir(chemin)` | Ouvre (ou crée) une base ; ":memoire:" pour une base en mémoire. |
| `sqlite.version()` | Version de la bibliothèque SQLite. |
| `db:executer(sql, ...)` | Exécute une instruction avec paramètres « ? » ; renvoie le nombre de lignes modifiées. Sans paramètre, accepte plusieurs instructions séparées par « ; ». |
| `db:requete(sql, ...)` | Liste des lignes ; chaque ligne est une table colonne (majuscules) -> valeur. |
| `db:premier(sql, ...)` | Première ligne ou nul. |
| `db:lignes(sql, ...)` | Itérateur sur les lignes : pour chaque r dans db:lignes(sql) ... suivant. |
| `db:dernierid()` | Identifiant de la dernière ligne insérée. |
| `db:modifications()` | Lignes modifiées par la dernière instruction. |
| `db:transaction(@proc)` | Appelle proc(db) dans une transaction (annulée en cas d'erreur). |
| `db:fermer()` | Ferme la base. |

### Paquet `tache`

Tâches coopératives — disponible par son nom (`tache.…`) ou par `paquet("tache")`.

| Appel | Rôle |
| --- | --- |
| `tache.lancer(@proc, ...)` | Crée une tâche qui exécutera proc(...) ; elle démarre au prochain tache.executer(), tache.attendre() ou attente. |
| `tache.executer()` | Fait tourner les tâches jusqu'à ce qu'elles soient toutes terminées. |
| `tache.attendre(secondes)` | Dans une tâche : la suspend ; ailleurs : attend en faisant tourner les tâches. |
| `tache.ceder()` | Rend la main aux autres tâches. |
| `tache.canal([capacite])` | Canal de communication (capacité 0 = illimitée). |
| `tache.nombre()` | Nombre de tâches en cours. |
| `tache.maintenant()` | Heure en secondes (avec décimales). |
| `t:attendre()` | Attend la fin d'une tâche et renvoie son résultat. |
| `t:etat()` | "suspendue", "en cours", "terminee" ou "erreur". |
| `t:annuler()` | Arrête une tâche suspendue. |
| `c:envoyer(valeur)` | Envoie une valeur (attend si le canal est plein). |
| `c:recevoir([delai])` | Reçoit une valeur (attend si vide) ; nul après le délai. |
| `c:nombre()` | Nombre de valeurs en attente. |

### Paquet `fil`

Fils d'exécution du système (interpréteurs séparés, messages) — disponible par son nom (`fil.…`) ou par `paquet("fil")`.

| Appel | Rôle |
| --- | --- |
| `fil.demarrer(code_ou_fichier, ...)` | Lance un fil qui exécute du code Lexis+ (chaîne) ou un fichier .prg, avec ses propres variables ; renvoie le fil. |
| `fil.envoyer(valeur)` | Dans le fil : envoie une valeur au programme qui l'a lancé. |
| `fil.recevoir([delai])` | Dans le fil : reçoit une valeur (nul après le délai). |
| `fil.estenfant()` | Vrai dans un fil lancé par fil.demarrer. |
| `f:envoyer(valeur)` | Envoie une valeur au fil (tables, chaînes, nombres, logiques). |
| `f:recevoir([delai])` | Reçoit une valeur du fil ; nul après le délai. |
| `f:actif()` | Vrai tant que le fil s'exécute. |
| `f:joindre()` | Attend la fin du fil ; son erreur éventuelle est relevée. |
| `f:arreter()` | Demande l'arrêt du fil. |

### Paquet `interface`

Interface graphique wdgui — disponible par son nom (`interface.…`) ou par `paquet("interface")` ; l'usage est d'écrire `ui = paquet("interface")`.

| Appel | Rôle |
| --- | --- |
| `interface.fenetre{titre=, largeur=, hauteur=, disposition=, theme=, sombre=}` | Crée une fenêtre. disposition : vertical, horizontal, grille, flux, bordure, pile, absolue ; theme : windows, macos, linux, natif. |
| `interface.executer()` | Attend la fermeture des fenêtres (atelier) ou lance la boucle de wdgui (runtime). |
| `interface.quitter()` | Ferme toutes les fenêtres du programme. |
| `interface.fenetres()` | Nombre de fenêtres ouvertes. |
| `interface.tracer([actif])` | Affiche dans la console chaque événement reçu (diagnostic). |
| `interface.etiquette(texte, [alignement])` | Libellé (alignement : gauche, centre, droite). |
| `interface.bouton(libelle, [{defaut=, annuler=}])` | Bouton. |
| `interface.saisie(texte \| {texte=, indication=, multiligne=})` | Champ de saisie. |
| `interface.cases(option, ...)` | Cases à cocher ; valeur = masque de bits. |
| `interface.radio(option, ...)` | Boutons radio ; valeur = index choisi. |
| `interface.liste([multi])` | Liste. |
| `interface.combo(element, ...)` | Liste déroulante. |
| `interface.tableau()` | Tableau simple. |
| `interface.arbre()` | Arbre. |
| `interface.grille{multi=, remplissage="programme\|manuel\|automatique"}` | Grille de saisie. |
| `interface.jauge()` | Jauge. |
| `interface.curseur()` | Potentiomètre. |
| `interface.plage()` | Potentiomètre de plage. |
| `interface.ascenseur()` | Ascenseur. |
| `interface.compteur()` | Compteur à flèches. |
| `interface.notation()` | Notation. |
| `interface.image(chemin)` | Image. |
| `interface.codebarre(texte)` | Code-barres. |
| `interface.graphe([genre], [titre])` | Graphe : colonnes, lignes, aires, secteurs. |
| `interface.calendrier(["AAAAMMJJ"])` | Calendrier. |
| `interface.kanban()` | Kanban. |
| `interface.mosaique()` | Mosaïque proportionnelle (treemap). |
| `interface.gantt()` | Gantt. |
| `interface.barremenu()` | Barre de menus. |
| `interface.onglets()` | Onglets. |
| `interface.separateur{vertical=, position=}` | Séparateur (deux enfants). |
| `interface.conteneur([disposition], [colonnes])` | Conteneur. |
| `interface.colonne()` | Conteneur vertical. |
| `interface.rangee()` | Conteneur horizontal. |
| `interface.superconteneur([disposition])` | Conteneur sans marge. |
| `interface.cadre(titre, [disposition])` | Cadre de groupe. |
| `interface.panneau{disposition=, defilement=, colonnes=}` | Conteneur défilant (defilement : toujours, automatique, masque). |
| `interface.pdf()` | Visionneuse PDF (PDFium). |
| `interface.alerte(message, [icone], [titre])` | Message (icone : information, question, attention, stop, aucune). |
| `interface.confirmer(message, [icone])` | OK / Annuler ; renvoie un logique. |
| `interface.demander(message, [defaut])` | Saisie d'un texte. |
| `interface.ouvrirfichier{titre=, filtre=, dossier=}` | Choix d'un fichier à ouvrir ; nul si annulé. |
| `interface.enregistrerfichier{nom=, filtre=}` | Choix d'un fichier à enregistrer ; nul si annulé. |
| `interface.couleur(["#RRGGBB"])` | Sélecteur de couleur. |
| `interface.police([famille], [taille])` | Sélecteur de police : {famille, taille, gras, italique}. |
| `interface.sep` | Séparateur des chemins d'arbre et de menu. |
| `c:ajouter(enfant, ...)` | Ajoute des contrôles à un conteneur ou une fenêtre ; renvoie le premier. |
| `c:focus()` | Donne le focus. |
| `c:menucontextuel(element, ...)` | Menu contextuel ; le choix arrive dans surselection. |
| `c:redessiner()` | Redessine le contrôle. |
| `fen:fermer()` | Ferme la fenêtre. |
| `fen:fixertheme(nom, [sombre])` | Change le thème. |
| `onglets:ajouterpage(titre, [disposition])` | Ajoute une page ; renvoie son conteneur. |
| `liste:ajouter(element, ...)` | Ajoute (listes et combos). |
| `liste:inserer(i, element)` | Insère. |
| `liste:supprimer(i)` | Supprime. |
| `liste:vider()` | Vide. |
| `liste:selectionner(i)` | Sélectionne. |
| `liste:selection()` | Index sélectionné. |
| `liste:nombre()` | Nombre d'éléments. |
| `liste:element(i)` | Texte d'un élément. |
| `liste:modifier(i, texte)` | Modifie. |
| `liste:chercher(texte)` | Recherche. |
| `tableau:ajoutercolonne(titre, [largeur], [alignement])` | Ajoute une colonne. |
| `tableau:ajouterligne(cellule, ...)` | Ajoute une ligne. |
| `tableau:cellule(ligne, colonne)` | Texte d'une cellule. |
| `tableau:fixercellule(ligne, colonne, texte)` | Modifie une cellule. |
| `tableau:selection()` | Ligne sélectionnée. |
| `tableau:trier(colonne, [croissant])` | Trie. |
| `arbre:ajouter(chemin...)` | Ajoute un nœud ("A", "B" ou "A/B"). |
| `arbre:deplier(chemin...)` | Déplie. |
| `arbre:replier(chemin...)` | Replie. |
| `arbre:supprimer(chemin...)` | Supprime. |
| `arbre:vider()` | Vide. |
| `barremenu:ajouter(chemin...)` | Ajoute un élément de menu ("Fichier", "Ouvrir") ; le choix arrive dans surselection (ev.chemin). |
| `cases:coche([i])` | État d'une case. |
| `cases:cocher(i, [b])` | Coche une case. |
| `graphe:ajouterdonnee(serie, categorie, valeur)` | Ajoute une donnée. |
| `graphe:libellecategorie(i, texte)` | Libellé de catégorie. |
| `graphe:libelleserie(i, texte)` | Libellé de série. |
| `graphe:fixergenre(genre)` | Genre de graphe. |
| `grille:ajoutercolonne{nom=, titre=, genre=, largeur=, choix=, decimales=}` | Ajoute une colonne (genre : texte, nombre, date, image, bouton, combo, case) ; renvoie la colonne. |
| `grille:ajouterligne(cellule, ...)` | Ajoute une ligne. |
| `grille:cellule(ligne, colonne)` | Valeur d'une cellule (colonne = nom ou index). |
| `grille:fixercellule(ligne, colonne, valeur)` | Modifie une cellule. |
| `grille:nombre()` | Nombre de lignes. |
| `grille:trier(colonne, [croissant])` | Trie. |
| `grille:chercher(colonne, valeur, [exact], [debut])` | Cherche une ligne. |
| `grille:fixerpied(colonne, genre)` | Pied de colonne : somme, moyenne, min, max, nombre. |
| `grille:ajouterformat(colonne, operateur, valeur, {fond=, texte=, ligneentiere=})` | Mise en forme conditionnelle. |
| `grille:fixermodifiable([b])` | Mode saisie. |
| `grille:verscsv([sep])` | Export CSV. |
| `grille:chargercsv(chemin, [sep])` | Import CSV. |
| `grille:versjson()` | Export JSON. |
| `grille:chargerjson(chemin)` | Import JSON. |
| `panneau:defilera(x, y)` | Fait défiler. |
| `pdf:ouvrir(chemin)` | Ouvre un PDF. |
| `pdf:enregistrer([chemin])` | Enregistre. |


---

## 12. Écrire un paquet en Nim

```nim
# paquets/pkg_salut.nim
import ../lexis/api

proc ouvrirSalut(L: Interp): Value =
  let m = newLib()
  m.fn "bonjour", proc (L: Interp, a: seq[Value]): seq[Value] =
    ret strV("Bonjour " & L.checkStr(a, 1, "bonjour"))
  tableV(m)

registerPackage PackageDef(name: "salut", open: ouvrirSalut,
  description: "Exemple",
  docs: docs("salut", ["salut.bonjour(nom)", "Renvoie une salutation."]))
```

Ajoutez `pkg_salut` à `paquets/tous.nim` : `salut.bonjour("Ada")` fonctionne, et la
complétion, l'aide et la coloration de l'atelier le connaissent. Les noms sont
enregistrés en majuscules (Lexis+ est insensible à la casse) ; `api.nim` fournit
la vérification des arguments (`checkStr`, `checkInt`, `optNum`, `checkTable`...),
les objets natifs (`wrap`, `checkUser`), les options en table (`optField`),
`record` pour renvoyer une fiche, `fail` pour signaler un échec (erreur
interceptable) et `L.blocking:` pour libérer l'interpréteur pendant une attente.

---

## 13. Mentions légales

**Lexis+** - *Développez naturellement vos applications métier*

© 2026 Jean‑Marc QUÉRÉ, sonaliwan.fr<br/>
SIRET : 13033319800013<br/>
<br/>
Distribué sous licence CC BY‑NC‑SA 4.0
<br/>
Les utilisations commerciales ne sont pas couvertes par cette licence.<br/>
Pour obtenir une autorisation d'utilisation commerciale,<br/>
contactez l'auteur.<br/>
<br/>
Contact : metalab (at) sonaliwan.fr<br/>
