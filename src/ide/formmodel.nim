# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - concepteur de formulaires : modèle, palette, persistance et
#   génération du fichier form_<nom>.prg (Lexis+).
#
# Adaptation du concepteur d'ednim au langage Lexis+ :
#   * les genres de contrôles sont ceux du paquet `interface` (bouton, saisie,
#     cadre, onglets…) et les propriétés portent leurs noms Lexis+ (libelle,
#     largeurfixe, ancrage…) ;
#   * le formulaire est un fichier form_<nom>.prg qui ne contient qu'une fonction
#     FORM<NOM>_OUVRIR() : le runtime charge tous les .prg du projet, il n'y a
#     donc rien à importer ;
#   * les événements sont associés dans ce fichier (`f.btn1.surclic = @BTN1_CLIC`) ;
#     les procédures appelées vivent dans le code édité, dans un bloc marqué.
import std/[json, strutils, os, math]
from std/unicode import runeAt, `$`

type
  PropKind* = enum
    pkString, pkInt, pkFloat, pkBool, pkEnum, pkColor, pkList
  PropDef* = object
    name*: string
    kind*: PropKind
    default*: string
    choices*: seq[string]

  PaletteEntry* = object
    kind*: string                # nom dans la palette et dans le modèle.
    category*: string
    base*: string                # genre natif utilisé pour l'aperçu (et le code des genres natifs).
    container*: bool
    props*: seq[PropDef]         # propriétés propres (les communes sont ajoutées).
    ctor*: string                # contrôles personnalisés : expression, "$prop" = valeur de la propriété.
    events*: seq[string]
    letter*: string              # pastille de la palette.

  DNode* = ref object
    uid*: int
    kind*: string
    name*: string
    props*: seq[tuple[key, value: string]]
    events*: seq[tuple[event, handler: string]]
    children*: seq[DNode]
    parent*: DNode

  FormModel* = ref object
    root*: DNode                 # genre "fenetre" ; son nom est celui du formulaire.
    code*: string                # fichier de code associé (relatif au projet).

var
  palette*: seq[PaletteEntry]
  uidCounter = 0

const
  layoutChoices* = ["vertical", "horizontal", "grille", "flux", "bordure", "pile", "absolue"]
  commonEvents = @["surclic", "surdoubleclic", "surclicdroit", "surentree", "sursortie",
                   "surfocus", "surfinfocus", "surtouchebas"]
  themeChoices* = ["natif", "windows", "macos", "linux"]
  PaletteFile* = "wdlexis_palette.json"
  DesignPrefix* = "&&§ "        # lignes du dessin, à la fin de form_<nom>.prg.

proc prop(name: string, kind: PropKind, default = "", choices: openArray[string] = []): PropDef =
  PropDef(name: name, kind: kind, default: default, choices: @choices)

# palette native

proc entry(kind, category, letter: string, container: bool, props: seq[PropDef],
           events: seq[string] = @[]): PaletteEntry =
  PaletteEntry(kind: kind, category: category, base: kind, container: container, props: props,
               letter: letter, events: commonEvents & events)

proc containerProps(layout = "vertical"): seq[PropDef] =
  @[prop("disposition", pkEnum, layout, layoutChoices), prop("marge", pkFloat, "-1"),
    prop("espacement", pkFloat, "-1"), prop("colonnes", pkInt, "2")]

proc initPalette() =
  let al = ["gauche", "centre", "droite"]
  palette = @[
    entry("conteneur", "Dispositions", "▭", true, containerProps()),
    entry("cadre", "Dispositions", "▢", true, @[prop("titre", pkString, "Groupe")] & containerProps()),
    entry("panneau", "Dispositions", "⇕", true, containerProps() &
          @[prop("defilement", pkEnum, "toujours", ["toujours", "automatique", "masque"])]),
    entry("separateur", "Dispositions", "‖", true, @[prop("vertical", pkBool, "true"),
          prop("position", pkFloat, "0.5")], @["surchangement"]),
    entry("onglets", "Dispositions", "⊓", true, @[], @["surchangement"]),
    entry("page", "Dispositions", "⊔", true, @[prop("titre", pkString, "Page")] & containerProps()),
    entry("etiquette", "Contrôles", "A", false, @[prop("libelle", pkString, "Libellé"),
          prop("alignement", pkEnum, "gauche", al)]),
    entry("bouton", "Contrôles", "B", false, @[prop("libelle", pkString, "Bouton"),
          prop("defaut", pkBool, "false"), prop("annuler", pkBool, "false")]),
    entry("saisie", "Contrôles", "E", false, @[prop("texte", pkString, ""),
          prop("indication", pkString, ""), prop("multiligne", pkBool, "false")],
          @["surchangement", "sursaisie"]),
    entry("cases", "Contrôles", "✓", false, @[prop("options", pkList, "Option")], @["surchangement"]),
    entry("radio", "Contrôles", "◉", false, @[prop("options", pkList, "Un;Deux;Trois"),
          prop("selection", pkInt, "1")], @["surchangement"]),
    entry("combo", "Contrôles", "▾", false, @[prop("elements", pkList, "Premier;Deuxième;Troisième"),
          prop("selection", pkInt, "1")], @["surselection"]),
    entry("liste", "Contrôles", "☰", false, @[prop("elements", pkList, "Élément 1;Élément 2;Élément 3"),
          prop("multi", pkBool, "false")], @["surselection"]),
    entry("compteur", "Contrôles", "S", false, @[prop("valeur", pkFloat, "0"), prop("min", pkFloat, "0"),
          prop("max", pkFloat, "100")], @["surchangement"]),
    entry("curseur", "Contrôles", "—", false, @[prop("valeur", pkFloat, "50"), prop("min", pkFloat, "0"),
          prop("max", pkFloat, "100")], @["surchangement"]),
    entry("plage", "Contrôles", "↔", false, @[prop("basse", pkFloat, "20"), prop("haute", pkFloat, "80"),
          prop("min", pkFloat, "0"), prop("max", pkFloat, "100")], @["surchangement"]),
    entry("jauge", "Contrôles", "▰", false, @[prop("valeur", pkFloat, "40"), prop("min", pkFloat, "0"),
          prop("max", pkFloat, "100")]),
    entry("notation", "Contrôles", "★", false, @[prop("valeur", pkFloat, "3")], @["surchangement"]),
    entry("ascenseur", "Contrôles", "↕", false, @[prop("valeur", pkFloat, "0"), prop("min", pkFloat, "0"),
          prop("max", pkFloat, "100")], @["surchangement"]),
    entry("image", "Contrôles", "▣", false, @[prop("chemin", pkString, "")]),
    entry("codebarre", "Contrôles", "║", false, @[prop("texte", pkString, "WDLEXIS")]),
    entry("calendrier", "Données", "▦", false, @[prop("date", pkString, "")], @["surchangement"]),
    entry("graphe", "Données", "▮", false, @[prop("genre", pkEnum, "colonnes",
          ["colonnes", "lignes", "aires", "secteurs"]), prop("titre", pkString, "Graphe")]),
    entry("arbre", "Données", "⌥", false, @[prop("noeuds", pkList, "Racine;Racine/Enfant")],
          @["surselection", "surdeploiement", "surrepli"]),
    entry("tableau", "Données", "▤", false, @[prop("colonnes", pkList, "Nom;Valeur")], @["surselection"]),
    entry("grille", "Données", "▦", false, @[prop("colonnes", pkList, "nom:Nom;valeur:Valeur"),
          prop("multi", pkBool, "false"), prop("modifiable", pkBool, "false")],
          @["surselection", "surchangement", "survalidation"]),
    entry("kanban", "Données", "▥", false, @[prop("listes", pkList, "À faire;En cours;Fait")], @["surselection"]),
    entry("mosaique", "Données", "▚", false, @[]),
    entry("gantt", "Données", "▬", false, @[]),
    entry("markdown", "Données", "M", false, @[prop("texte", pkString, "# Titre\nTexte en **Markdown**.")],
          @["surselection"]),
    entry("barremenu", "Données", "≡", false, @[prop("menus", pkList,
          "Fichier/Ouvrir;Fichier/Quitter;Aide/À propos")], @["surselection"])]

proc windowEntry*(): PaletteEntry =
  PaletteEntry(kind: "fenetre", category: "", base: "fenetre", container: true, letter: "▢",
               events: @["surouverture", "surfermeture", "surredimension", "surtouchebas"],
               props: @[prop("titre", pkString, "Formulaire"), prop("largeur", pkInt, "640"),
                        prop("hauteur", pkInt, "480"), prop("disposition", pkEnum, "vertical", layoutChoices),
                        prop("theme", pkEnum, "natif", themeChoices), prop("sombre", pkBool, "false")])

proc commonProps*(): seq[PropDef] =
  @[prop("infobulle", pkString, ""), prop("visible", pkBool, "true"),
    prop("etat", pkEnum, "actif", ["actif", "grise", "lecture"]),
    prop("largeurfixe", pkFloat, "0"), prop("hauteurfixe", pkFloat, "0"),
    prop("x", pkFloat, "0"), prop("y", pkFloat, "0"),
    prop("poids", pkFloat, "0"), prop("etirer", pkEnum, "", ["", "true", "false"]),
    prop("ancrage", pkEnum, "", ["", "haut", "bas", "gauche", "droite", "centre"]),
    prop("couleur", pkColor, ""), prop("fond", pkColor, "")]

proc findEntry*(kind: string): PaletteEntry =
  if kind == "fenetre": return windowEntry()
  if palette.len == 0: initPalette()
  for e in palette:
    if e.kind == kind: return e
  result = PaletteEntry(kind: kind, base: "etiquette", letter: "?")

proc allProps*(kind: string): seq[PropDef] =
  # Propriétés de l'inspecteur : propres (les personnalisés ont aussi celles de leur base), puis communes.
  let e = findEntry(kind)
  if kind == "fenetre": return e.props
  if e.base != e.kind:
    for p in findEntry(e.base).props: result.add p
  for p in e.props:
    var dup = false
    for q in result:
      if q.name == p.name: dup = true
    if not dup: result.add p
  result.add commonProps()

proc eventsOf*(kind: string): seq[string] =
  let e = findEntry(kind)
  if e.base != e.kind and kind != "fenetre": findEntry(e.base).events else: e.events

proc isContainerKind*(kind: string): bool =
  let e = findEntry(kind)
  e.container or (e.base != e.kind and findEntry(e.base).container)

proc baseOf*(kind: string): string = findEntry(kind).base

# contrôles personnalisés (wdlexis_palette.json du projet)

proc customPalettePath*(root: string): string = root / PaletteFile

proc loadCustomPalette*(root: string) =
  # [{"kind": "BoutonRond", "base": "bouton", "ctor": "BOUTONROND($libelle)",
  #   "category": "Personnalisés", "letter": "R",
  #   "props": [{"name": "compteur", "type": "int", "default": "0"}]}]
  initPalette()
  let f = customPalettePath(root)
  if not fileExists(f): return
  try:
    for it in parseJson(readFile(f)):
      var e = PaletteEntry(kind: it{"kind"}.getStr, base: it{"base"}.getStr("etiquette"),
                           ctor: it{"ctor"}.getStr, category: it{"category"}.getStr("Personnalisés"),
                           letter: it{"letter"}.getStr("★"))
      if e.kind.len == 0 or e.kind == "fenetre": continue
      e.container = findEntry(e.base).container
      let props = it{"props"}
      if props != nil and props.kind == JArray:
        for p in props:
          var k = pkString
          case p{"type"}.getStr("string")
          of "int", "entier": k = pkInt
          of "float", "nombre": k = pkFloat
          of "bool", "logique": k = pkBool
          of "color", "couleur": k = pkColor
          of "list", "liste": k = pkList
          else: discard
          e.props.add PropDef(name: p{"name"}.getStr, kind: k, default: p{"default"}.getStr)
      palette.add e
  except CatchableError: discard

proc addCustomEntry*(root, kind, base, ctor: string): bool =
  let f = customPalettePath(root)
  var arr = newJArray()
  try:
    if fileExists(f): arr = parseJson(readFile(f))
  except CatchableError: arr = newJArray()
  if arr.kind != JArray: arr = newJArray()
  arr.add %*{"kind": kind, "base": base, "ctor": ctor, "category": "Personnalisés",
             "letter": (if kind.len > 0: $kind.runeAt(0) else: "★"), "props": []}
  try:
    writeFile(f, arr.pretty)
    loadCustomPalette(root)
    result = true
  except CatchableError: result = false

# nœuds

proc newNode*(kind, name: string): DNode =
  inc uidCounter
  DNode(uid: uidCounter, kind: kind, name: name)

proc getProp*(n: DNode, key: string): string =
  for p in n.props:
    if p.key == key: return p.value
  for d in allProps(n.kind):
    if d.name == key: return d.default
  ""

proc setProp*(n: DNode, key, value: string) =
  for p in n.props.mitems:
    if p.key == key:
      p.value = value
      return
  n.props.add((key, value))

proc handlerFor*(n: DNode, event: string): string =
  for e in n.events:
    if e.event == event: return e.handler

proc setHandler*(n: DNode, event, handler: string) =
  for i in countdown(n.events.high, 0):
    if n.events[i].event == event: n.events.delete(i)
  if handler.len > 0: n.events.add((event, handler))

proc walk*(n: DNode, acc: var seq[DNode]) =
  acc.add n
  for c in n.children: walk(c, acc)

proc allNodes*(m: FormModel): seq[DNode] = walk(m.root, result)

proc isAncestor*(a, b: DNode): bool =
  # Vrai si `a` est `b` ou l'un de ses ancêtres.
  var p = b
  while p != nil:
    if p == a: return true
    p = p.parent

proc namePrefix(kind: string): string =
  case kind
  of "bouton": "btn"
  of "etiquette": "lbl"
  of "saisie": "sai"
  of "cases": "chk"
  of "radio": "rad"
  of "combo": "cbo"
  of "liste": "lst"
  of "compteur": "cpt"
  of "curseur": "cur"
  of "plage": "plg"
  of "jauge": "jau"
  of "notation": "note"
  of "ascenseur": "asc"
  of "image": "img"
  of "codebarre": "cbr"
  of "calendrier": "cal"
  of "graphe": "gra"
  of "arbre": "arb"
  of "tableau": "tab"
  of "grille": "grl"
  of "kanban": "kan"
  of "mosaique": "mos"
  of "gantt": "gan"
  of "markdown": "mkd"
  of "barremenu": "menu"
  of "conteneur": "cnt"
  of "cadre": "cad"
  of "panneau": "pan"
  of "separateur": "sep"
  of "onglets": "ong"
  of "page": "page"
  else: (if kind.len >= 3: kind[0 .. 2].toLowerAscii else: "ctl")

proc uniqueName*(m: FormModel, kind: string): string =
  let prefix = namePrefix(kind)
  var n = 1
  while true:
    let cand = prefix & $n
    var used = false
    for x in m.allNodes:
      if cmpIgnoreCase(x.name, cand) == 0: used = true
    if not used: return cand
    inc n

const Reserved = ["fenetre", "si", "sinon", "finsi", "pour", "et", "ou", "non", "nul", "vrai", "faux",
                  "procedure", "fonction", "retourner", "locale", "globale", "dans", "chaque", "suivant"]

proc isIdent*(s: string): bool =
  # Nom de contrôle : lettre puis lettres, chiffres ou _ (ASCII) ; pas un mot réservé.
  if s.len == 0 or not s[0].isAlphaAscii: return false
  for c in s:
    if not (c.isAlphaNumeric or c == '_'): return false
  s.toLowerAscii notin Reserved

proc isFormName*(s: string): bool =
  if s.len == 0: return false
  for c in s:
    if not (c.isAlphaNumeric or c == '_'): return false
  true

proc newModel*(formName: string): FormModel =
  result = FormModel(root: newNode("fenetre", formName))
  result.root.setProp("titre", "Formulaire " & formName)

# JSON

proc toJson(n: DNode): JsonNode =
  var props = newJObject()
  for p in n.props: props[p.key] = %p.value
  var evs = newJArray()
  for e in n.events: evs.add %*[e.event, e.handler]
  var ch = newJArray()
  for c in n.children: ch.add toJson(c)
  %*{"kind": n.kind, "name": n.name, "props": props, "events": evs, "children": ch}

proc fromJson(j: JsonNode, parent: DNode): DNode =
  result = newNode(j{"kind"}.getStr("etiquette"), j{"name"}.getStr)
  result.parent = parent
  if j{"props"} != nil:
    for k, v in j{"props"}.pairs: result.props.add((k, v.getStr))
  if j{"events"} != nil:
    for e in j{"events"}:
      if e.len >= 2: result.events.add((e[0].getStr, e[1].getStr))
  if j{"children"} != nil:
    for c in j{"children"}: result.children.add fromJson(c, result)

proc modelToJson*(m: FormModel): string =
  var j = toJson(m.root)
  j["code"] = %m.code
  j.pretty

proc parseModel*(text: string): FormModel =
  # Dessin gardé à la fin de form_<nom>.prg, lignes « &&§ ».
  var js = ""
  for raw in text.splitLines:
    let l = raw.strip(trailing = false)
    if l.startsWith(DesignPrefix): js.add l[DesignPrefix.len .. ^1] & "\n"
    elif l == DesignPrefix.strip: js.add "\n"
  if js.strip.len == 0: return nil
  try:
    let j = parseJson(js)
    result = FormModel(root: fromJson(j, nil), code: j{"code"}.getStr)
    if result.root.kind != "fenetre": result = nil
  except CatchableError:
    result = nil

proc loadModel*(formFile: string): FormModel =
  try: result = parseModel(readFile(formFile))
  except CatchableError: result = nil

# noms et fichiers

proc formFileName*(name: string): string = "form_" & name & ".prg"

proc isFormFile*(path: string): bool =
  let f = extractFilename(path).toLowerAscii
  f.startsWith("form_") and f.endsWith(".prg")

proc nextFormName*(root: string): string =
  # Premier numéro N tel que form_N.prg n'existe pas dans le dossier du projet.
  var n = 1
  while fileExists(root / formFileName($n)): inc n
  $n

proc openProc*(formName: string): string = "FORM" & formName.toUpperAscii & "_OUVRIR"
proc formVar*(formName: string): string = "form" & formName.toLowerAscii

# génération du code Lexis+

proc lit*(s: string): string =
  result = "\""
  for c in s:
    case c
    of '"': result.add "\\\""
    of '\\': result.add "\\\\"
    of '\n': result.add "\\n"
    of '\t': result.add "\\t"
    of '\r': discard
    else: result.add c
  result.add "\""

proc pnum(s: string, default = 0.0): float =
  try: result = parseFloat(s.strip.replace(',', '.'))
  except ValueError: result = default

proc numLit*(f: float): string =
  if f == float(int64(f)) and abs(f) < 1e15: $int64(f)
  else:
    var s = formatFloat(f, ffDecimal, 4)
    s = s.strip(leading = false, chars = {'0'})
    if s.endsWith("."): s.setLen(s.len - 1)
    s

proc isTrue*(s: string): bool = s.strip.toLowerAscii in ["true", "1", "vrai", "yes", "oui"]

proc boolLit(s: string): string = (if isTrue(s): "vrai" else: "faux")

proc listOf*(s: string): seq[string] =
  for x in s.split(';'):
    if x.strip.len > 0: result.add x.strip

proc listLits(s: string): string =
  var parts: seq[string]
  for x in listOf(s): parts.add lit(x)
  parts.join(", ")

proc valueLit(n: DNode, key: string): string =
  # Littéral Lexis+ d'une propriété selon sa définition.
  let v = n.getProp(key)
  for d in allProps(n.kind):
    if d.name == key:
      return case d.kind
             of pkString, pkColor, pkEnum: lit(v)
             of pkInt: $int(round(pnum(v, pnum(d.default))))
             of pkFloat: numLit(pnum(v, pnum(d.default)))
             of pkBool: boolLit(v)
             of pkList: "{" & listLits(v) & "}"
  lit(v)

proc isDefault(n: DNode, key: string): bool =
  for d in allProps(n.kind):
    if d.name == key:
      let v = n.getProp(key)
      return case d.kind
             of pkFloat, pkInt: pnum(v, pnum(d.default)) == pnum(d.default)
             of pkBool: isTrue(v) == isTrue(d.default)
             else: v == d.default
  true

proc ctorExpr*(n: DNode): string =
  # Expression de création d'un nœud (personnalisés : `ctor` avec « $prop » remplacé).
  let e = findEntry(n.kind)
  if e.ctor.len > 0:
    result = e.ctor
    for d in allProps(n.kind): result = result.replace("$" & d.name, valueLit(n, d.name))
    return
  template v(k: string): string = valueLit(n, k)
  template g(k: string): string = n.getProp(k)
  case e.base
  of "conteneur":
    if g("disposition") == "vertical" and pnum(g("colonnes"), 2) == 2: "interface.conteneur()"
    elif pnum(g("colonnes"), 2) == 2: "interface.conteneur(" & v("disposition") & ")"
    else: "interface.conteneur(" & v("disposition") & ", " & v("colonnes") & ")"
  of "cadre":
    if g("disposition") == "vertical": "interface.cadre(" & v("titre") & ")"
    else: "interface.cadre(" & v("titre") & ", " & v("disposition") & ")"
  of "panneau":
    "interface.panneau{disposition = " & v("disposition") & ", defilement = " & v("defilement") &
      ", colonnes = " & v("colonnes") & "}"
  of "separateur": "interface.separateur{vertical = " & v("vertical") & ", position = " & v("position") & "}"
  of "onglets": "interface.onglets()"
  of "etiquette":
    if g("alignement") in ["", "gauche"]: "interface.etiquette(" & v("libelle") & ")"
    else: "interface.etiquette(" & v("libelle") & ", " & v("alignement") & ")"
  of "bouton":
    var o: seq[string]
    if isTrue(g("defaut")): o.add "defaut = vrai"
    if isTrue(g("annuler")): o.add "annuler = vrai"
    if o.len == 0: "interface.bouton(" & v("libelle") & ")"
    else: "interface.bouton(" & v("libelle") & ", {" & o.join(", ") & "})"
  of "saisie":
    var o: seq[string]
    if g("texte").len > 0: o.add "texte = " & v("texte")
    if g("indication").len > 0: o.add "indication = " & v("indication")
    if isTrue(g("multiligne")): o.add "multiligne = vrai"
    if o.len == 0: "interface.saisie()"
    elif o.len == 1 and g("texte").len > 0: "interface.saisie(" & v("texte") & ")"
    else: "interface.saisie{" & o.join(", ") & "}"
  of "cases": "interface.cases(" & listLits(g("options")) & ")"
  of "radio": "interface.radio(" & listLits(g("options")) & ")"
  of "combo": "interface.combo(" & listLits(g("elements")) & ")"
  of "liste": (if isTrue(g("multi")): "interface.liste(vrai)" else: "interface.liste()")
  of "compteur", "curseur", "plage", "jauge", "notation", "ascenseur", "arbre", "tableau",
     "kanban", "mosaique", "gantt", "barremenu":
    "interface." & e.base & "()"
  of "image": (if g("chemin").len > 0: "interface.image(" & v("chemin") & ")" else: "interface.image()")
  of "codebarre": "interface.codebarre(" & v("texte") & ")"
  of "calendrier": (if g("date").len > 0: "interface.calendrier(" & v("date") & ")" else: "interface.calendrier()")
  of "graphe": "interface.graphe(" & v("genre") & ", " & v("titre") & ")"
  of "grille": (if isTrue(g("multi")): "interface.grille{multi = vrai}" else: "interface.grille()")
  of "markdown": "interface.markdown(" & v("texte") & ")"
  else: "interface.etiquette(" & lit(n.name) & ")"

proc genNode(n: DNode, parentRef, parentLayout: string, lines: var seq[string]) =
  let x = "f." & n.name
  let base = baseOf(n.kind)
  template g(k: string): string = n.getProp(k)
  template add(s: string) = lines.add "  " & s
  if base == "page":
    add x & " = " & parentRef & ":ajouterpage(" & valueLit(n, "titre") & ", " & valueLit(n, "disposition") & ")"
  else:
    add x & " = " & parentRef & ":ajouter(" & ctorExpr(n) & ")"
  let custom = findEntry(n.kind).ctor.len > 0
  # contenu propre au genre (après l'ajout : la valeur passe par la fenêtre).
  if not custom:
    case base
    of "saisie":
      # interface.saisie ignore le texte quand une indication est donnée (sauf multiligne).
      if g("texte").len > 0 and g("indication").len > 0 and not isTrue(g("multiligne")):
        add x & ".valeur = " & valueLit(n, "texte")
    of "radio", "combo":
      if pnum(g("selection"), 1) != 1: add x & ".valeur = " & valueLit(n, "selection")
    of "liste":
      if listOf(g("elements")).len > 0: add x & ":ajouter(" & listLits(g("elements")) & ")"
    of "compteur", "curseur", "jauge", "ascenseur":
      if not isDefault(n, "min"): add x & ".min = " & valueLit(n, "min")
      if not isDefault(n, "max"): add x & ".max = " & valueLit(n, "max")
      add x & ".num = " & valueLit(n, "valeur")
    of "notation":
      add x & ".num = " & valueLit(n, "valeur")
    of "plage":
      if not isDefault(n, "min"): add x & ".min = " & valueLit(n, "min")
      if not isDefault(n, "max"): add x & ".max = " & valueLit(n, "max")
      add x & ".valeur = " & lit(numLit(pnum(g("basse"), 20)) & ";" & numLit(pnum(g("haute"), 80)))
    of "arbre":
      for p in listOf(g("noeuds")): add x & ":ajouter(" & lit(p) & ")"
    of "tableau":
      for c in listOf(g("colonnes")): add x & ":ajoutercolonne(" & lit(c) & ")"
    of "grille":
      for c in listOf(g("colonnes")):
        let parts = c.split(':')
        let nm = parts[0].strip
        let title = if parts.len > 1: parts[1].strip else: nm
        add x & ":ajoutercolonne{nom = " & lit(nm) & ", titre = " & lit(title) & "}"
      if isTrue(g("modifiable")): add x & ":fixermodifiable(vrai)"
    of "kanban":
      for l in listOf(g("listes")): add x & ":ajouterliste(" & lit(l) & ")"
    of "barremenu":
      for p in listOf(g("menus")): add x & ":ajouter(" & lit(p) & ")"
    of "conteneur", "cadre", "panneau", "page":
      if pnum(g("marge"), -1) >= 0: add x & ".marge = " & valueLit(n, "marge")
      if pnum(g("espacement"), -1) >= 0: add x & ".espacement = " & valueLit(n, "espacement")
      if base in ["cadre", "page"] and g("disposition") == "grille" and pnum(g("colonnes"), 2) != 2:
        add x & ".colonnes = " & valueLit(n, "colonnes")
    else: discard
  # propriétés communes.
  if g("infobulle").len > 0: add x & ".infobulle = " & valueLit(n, "infobulle")
  if not isTrue(g("visible")): add x & ".visible = faux"
  if g("etat") notin ["", "actif"]: add x & ".etat = " & valueLit(n, "etat")
  if pnum(g("largeurfixe")) > 0: add x & ".largeurfixe = " & valueLit(n, "largeurfixe")
  if pnum(g("hauteurfixe")) > 0: add x & ".hauteurfixe = " & valueLit(n, "hauteurfixe")
  if parentLayout == "absolue":
    add x & ".x = " & valueLit(n, "x")
    add x & ".y = " & valueLit(n, "y")
  if pnum(g("poids")) > 0: add x & ".poids = " & valueLit(n, "poids")
  if g("etirer").len > 0: add x & ".etirer = " & boolLit(g("etirer"))
  if g("ancrage").len > 0: add x & ".ancrage = " & valueLit(n, "ancrage")
  if g("couleur").len > 0: add x & ".couleur = " & valueLit(n, "couleur")
  if g("fond").len > 0: add x & ".fond = " & valueLit(n, "fond")
  let layout = if isContainerKind(n.kind) and base notin ["onglets", "separateur"]: g("disposition") else: ""
  for c in n.children: genNode(c, x, layout, lines)

proc generateCode*(m: FormModel): string =
  # Fichier form_<nom>.prg complet (le dessin est gardé dans les lignes « &&§ » de la fin).
  let name = m.root.name
  let fv = formVar(name)
  let r = m.root
  var o: seq[string]
  o.add "&& Formulaire « " & name & " » — généré par le concepteur de wdlexis+."
  o.add "&& Régénéré à chaque modification dans le concepteur : modifiez le dessin là-bas, pas ce fichier."
  o.add "&& " & openProc(name) & "() ouvre la fenêtre et renvoie ses contrôles, aussi rangés dans la"
  o.add "&& variable globale " & fv & " (" & fv & ".fenetre, " & fv & "." &
        (if r.children.len > 0: r.children[0].name else: "nom_du_controle") & "…)."
  o.add ""
  o.add "fonction " & openProc(name) & "()"
  o.add "  globale " & fv
  o.add "  locale f = {}"
  var opts = @["titre = " & valueLit(r, "titre"), "largeur = " & valueLit(r, "largeur"),
               "hauteur = " & valueLit(r, "hauteur"), "disposition = " & valueLit(r, "disposition")]
  if r.getProp("theme") notin ["", "natif"]: opts.add "theme = " & valueLit(r, "theme")
  if isTrue(r.getProp("sombre")): opts.add "sombre = vrai"
  o.add "  f.fenetre = interface.fenetre{" & opts.join(", ") & "}"
  var body: seq[string]
  for c in r.children: genNode(c, "f.fenetre", r.getProp("disposition"), body)
  o.add body
  var evs: seq[string]
  for n in m.allNodes:
    let x = if n == r: "f.fenetre" else: "f." & n.name
    for e in n.events: evs.add "  " & x & "." & e.event & " = @" & e.handler
  if evs.len > 0:
    o.add "  && événements (procédures du code : " & (if m.code.len > 0: m.code else: "projet") & ")"
    o.add evs
  o.add "  " & fv & " = f"
  o.add "retourner f"
  o.add "finfonction"
  o.add ""
  o.add "&& Dessin du formulaire (relu par le concepteur) : ne pas modifier."
  for l in modelToJson(m).splitLines: o.add DesignPrefix & l
  o.join("\n") & "\n"

# code édité : procédures des gestionnaires
#
# Dans le code édité avec le concepteur, un bloc marqué (à la fin du fichier)
# reçoit les procédures créées par « + nouveau gestionnaire… ». Les
# associations, elles, sont écrites dans form_<nom>.prg.

proc beginMarker*(name: string): string =
  "&& ---- formulaire « " & name & " » : début (généré par le concepteur, gardez ces marques) ----"
proc endMarker*(name: string): string = "&& ---- formulaire « " & name & " » : fin ----"

proc procHeader(l: string): tuple[ok: bool, name: string, params: int] =
  # « procedure NOM(a) » / « fonction NOM(a, b) » / « procedure NOM »
  let s = l.strip
  var rest = ""
  if s.startsWith("procedure "): rest = s[10 .. ^1]
  elif s.startsWith("fonction "): rest = s[9 .. ^1]
  else: return
  rest = rest.strip
  var name = ""
  var i = 0
  while i < rest.len and (rest[i].isAlphaNumeric or rest[i] == '_' or ord(rest[i]) >= 128):
    name.add rest[i]
    inc i
  if name.len == 0: return
  var params = 0
  let a = rest.find('(')
  let b = rest.find(')')
  if a >= 0 and b > a:
    let inside = rest[a + 1 ..< b].strip
    if inside.len > 0: params = inside.count(',') + 1
  (true, name, params)

proc existingHandlers*(code: string): seq[string] =
  # Procédures à un paramètre (ev) : candidates pour un gestionnaire.
  for l in code.splitLines:
    let h = procHeader(l)
    if h.ok and h.params == 1:
      var dup = false
      for x in result:
        if cmpIgnoreCase(x, h.name) == 0: dup = true
      if not dup: result.add h.name

proc definesProc*(code, name: string): bool =
  for l in code.splitLines:
    let h = procHeader(l)
    if h.ok and cmpIgnoreCase(h.name, name) == 0: return true

proc blockRange(lines: seq[string], name: string): tuple[a, b: int] =
  result = (-1, -1)
  for i, l in lines:
    if l == beginMarker(name): result.a = i
    elif l == endMarker(name) and result.a >= 0:
      result.b = i
      return

proc ensureBlock*(code, name: string): string =
  # Ajoute le bloc marqué (vide) à la fin du code s'il manque.
  var lines = code.split('\n')
  if blockRange(lines, name).a >= 0: return code
  while lines.len > 0 and lines[^1].strip.len == 0: lines.setLen(lines.len - 1)
  if lines.len > 0: lines.add ""
  lines.add beginMarker(name)
  lines.add "&& " & openProc(name) & "() ouvre le formulaire ; ses contrôles sont dans " &
            formVar(name) & " (" & formVar(name) & ".fenetre…)."
  lines.add ""
  lines.add endMarker(name)
  lines.add ""
  lines.join("\n")

proc handlerStub*(handler, event, nodeName, formName: string): string =
  "procedure " & handler & "(ev)\n" &
  "  && " & event & " de " & nodeName & " (formulaire « " & formName & " »)\n" &
  "  \n" &
  "finprocedure\n"

proc insertStub*(code, name, stub: string): tuple[text: string, line: int] =
  # Insère une procédure à la fin du bloc ; renvoie le texte et la ligne (1-based) de
  # la ligne vide à compléter.
  var lines = ensureBlock(code, name).split('\n')
  let r = blockRange(lines, name)
  var at = r.b
  let stubLines = stub.strip(leading = false).split('\n') & @[""]
  for k in countdown(stubLines.high, 0): lines.insert(stubLines[k], at)
  (lines.join("\n"), at + 3)

proc mainEnd(lines: seq[string]): int =
  # Fin du programme principal : première procédure / fonction / bloc de formulaire.
  for i, l in lines:
    if procHeader(l).ok or l.startsWith("&& ---- formulaire « "): return i
  lines.len

proc ensureOpenCall*(code, name: string): tuple[text: string, added: bool] =
  # Programme principal : ajoute FORM<NOM>_OUVRIR() (et interface.executer()) s'il manque.
  var lines = code.split('\n')
  for l in lines:
    let s = l.strip.toLowerAscii
    if s.startsWith("&&") or s.startsWith("//") or s.startsWith("*"): continue
    let c = s.find("&&")
    let codePart = if c >= 0: s[0 ..< c] else: s
    if openProc(name).toLowerAscii & "(" in codePart: return (code, false)
  let e = mainEnd(lines)
  var at = -1
  for i in 0 ..< e:
    let l = lines[i].strip.toLowerAscii
    if not l.startsWith("&&") and "executer()" in l and ("ui." in l or "interface." in l):
      at = i
      break
  if at >= 0:
    lines.insert(openProc(name) & "()", at)
  else:
    at = e
    while at > 0 and lines[at - 1].strip.len == 0: dec at
    var ins = @[openProc(name) & "()", "interface.executer()"]
    if at < lines.len and lines[at].strip.len > 0: ins.add ""
    if at > 0: ins.insert("", 0)
    for k in countdown(ins.high, 0): lines.insert(ins[k], at)
  (lines.join("\n"), true)

proc replaceWord(s, old, new: string): string =
  # Remplace le mot `old` (insensible à la casse, limites de mot).
  let lo = s.toLowerAscii
  let o = old.toLowerAscii
  var i = 0
  while i < s.len:
    let j = lo.find(o, i)
    if j < 0:
      result.add s[i .. ^1]
      break
    let before = j == 0 or not (s[j - 1].isAlphaNumeric or s[j - 1] == '_')
    let k = j + o.len
    let after = k >= s.len or not (s[k].isAlphaNumeric or s[k] == '_')
    result.add s[i ..< j]
    if before and after: result.add new else: result.add s[j ..< k]
    i = k

proc renameWiring*(code, oldName, newName: string): string =
  # Suit le renommage d'un formulaire dans le code (marques, appel, variable).
  result = code.replace(beginMarker(oldName), beginMarker(newName))
  result = result.replace(endMarker(oldName), endMarker(newName))
  result = result.replaceWord(openProc(oldName), openProc(newName))
  result = result.replaceWord(formVar(oldName), formVar(newName))
