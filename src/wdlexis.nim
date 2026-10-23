#[
              _ _           _
  __      ____| | | _____  _(_)___   _
  \ \ /\ / / _` | |/ _ \ \/ / / __|_| |_
   \ V  V / (_| | |  __/>  <| \__ \_   _|
    \_/\_/ \__,_|_|\___/_/\_\_|___/ |_|   [S]tudio 1.6.0,
      Développez naturellement vos applications métier.

  wdlexis+ - atelier pour le langage Lexis+, construit sur wdgui.

  nim c -d:release -o:wdlexis+ wdlexis.nim
  ./wdlexis+ [dossier_de_projet | fichier.prg]

    Éditeur, analyse en continu, interpréteur intégré (exécution directe ou
    pas à pas avec points d'arrêt, variables et pile d'appels), console avec
    saisie, référence des fonctions intégrées et des paquets.

  Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
  SIRET 13033319800013 — metalab (at) sonaliwan.fr

]#

import std/[os, strutils, sets, tables, atomics, locks, algorithm, deques]
import wdgui
import ide/[compat, settings, lexislang, langdocs, lexislint, codeeditor, session]
from ide/generer import generationDialog
import ide/designer
from ide/formmodel import isFormFile
import ide/reportdesigner
import ide/appicon
from ide/etats import isReportFile
import lexis/api
import paquets/tous

const
  AppName = "wdlexis+"
  MainName = "principal.prg"
  TextExts = [".prg", ".txt", ".md", ".json", ".csv", ".sql", ".ini", ".cfg", ".html"]
  NewMain = """&& principal.prg : point d'entrée du projet
&& Le programme principal s'écrit en tête du fichier, les procédures ensuite.

? "Bonjour depuis wdlexis+ !"

ui = paquet("interface")
fen = ui.fenetre{titre = "Bonjour", largeur = 420, hauteur = 200}
lbl = fen:ajouter(ui.etiquette("Cliquez sur le bouton", "centre"))
nb = 0
btn = fen:ajouter(ui.bouton("Compter", {defaut = vrai}))
btn.surclic = @COMPTER
ui.executer()

procedure COMPTER(ev)
  nb += 1
  lbl.valeur = "Clics : " + nb
  si nb = 5
    ? "cinq clics !"
  finsi
retourner
"""
  Shortcuts = """Édition
Ctrl+X/C/V couper, copier, coller        Ctrl+Z/Y annuler, rétablir
Ctrl+F rechercher, Ctrl+H / F3 suivant   Ctrl+L aller à la ligne
Ctrl+W/E début / fin de ligne            Ctrl+D dupliquer la ligne
Tab / Maj+Tab indenter, désindenter      Ctrl+B commenter / décommenter (&&)
Ctrl+Espace complétion                   Ctrl+ + / - / 0 taille de la police
F12 ou Ctrl+clic aller à la définition   Ctrl+Tab document suivant

Exécution et débogage
Ctrl+R exécuter (sans débogueur)         F5 déboguer / continuer
F9 ou clic dans la marge : point d'arrêt F10 pas principal
F11 pas à pas                            Maj+F11 sortir de la procédure
Maj+F5 arrêter"""

type
  ProblemRow = object
    uid: int
    path: string
    line, col: int

  AppState = object
    settings: Settings
    root: string
    index: ProjectIndex
    diagByUid: Table[int, tuple[title, path: string, diags: seq[Diagnostic]]]
    runtimeRows: seq[tuple[path: string, line: int, msg: string]]
    rows: seq[ProblemRow]
    outline: seq[Symbol]
    outlineKey: string
    findReq: FindRequest
    apiRows: seq[ApiDoc]
    pause: PauseInfo
    paused: bool
    consoleBuf: string

var
  win: Window
  gWin: typeof(Event().window)
  haveWin: Atomic[bool]
  mnu, edId, trProj, lstOutline, trApi, edApiDoc, tabLeft, tabBottom,
    tblProb, edOut, edIn, btnSend, btnCopy, btnClear, tblVars, lstStack, lblStatus, lblPos,
    btnOpen, btnNew, btnSave, btnCheck, btnRun, btnDebug, btnStepIn, btnStepOver,
    btnStepOut, btnCont, btnPause, btnStop: ControlId
  gLock: Lock
  st: AppState
  lintGen: Atomic[int]
  running: Atomic[bool]
  stopAsked: Atomic[bool]   # Arrêter a été demandé pour l'exécution en cours.
  btnLock: Lock             # sérialise la mise à jour des boutons (plusieurs fils).
  inLock: Lock
  inCond: Cond
  inQueue: Deque[string]
  waitingInput: Atomic[bool]

initLock(gLock)
initLock(inLock)
initLock(btnLock)
initCond(inCond)

template withState(body: untyped) =
  {.cast(gcsafe).}:
    withLock gLock:
      body

#
# Aides
#

proc status(msg: string) = lblStatus.caption = msg

proc root(): string =
  withState: result = st.root

proc opts(): Settings =
  withState: result = st.settings

proc setOpts(s: Settings) =
  withState: st.settings = s
  saveSettings(s)

proc relPath(p: string): string =
  let r = root()
  if r.len > 0 and p.startsWith(r): relativePath(p, r) else: p

proc updateTitle() =
  let uid = editorActiveUid(edId)
  var t = AppName & " — Lexis+"
  if uid >= 0:
    let info = editorInfo(edId, uid)
    t = (if info.dirty: "● " else: "") & info.title & "  —  " & AppName
  let r = root()
  if r.len > 0: t.add "  [" & extractFilename(r) & "]"
  if running.load(): t.add "  (en cours)"
  if haveWin.load(): gWin.caption = t

proc consoleAppend(s: string) =
  # Ajoute à la console en gardant la fin visible (comme la console de wdnim).
  {.cast(gcsafe).}:
    withControl(edOut, Edit, e):
      var t = e.text & s
      if t.len > 400_000: t = t[t.len - 300_000 .. ^1]
      e.setValueText(t)

proc consoleClear() =
  edOut.value = ""

proc consoleCopy() =
  let text = edOut.value
  if text.len == 0:
    status("La console est vide.")
    return
  editorCopyToClipboard(edId, text)
  status("Contenu de la console copié dans le presse-papiers (" & $text.len & " caractères).")

proc setRunButtons(isRunning, isPaused: bool) =
  # Utiliser refreshRunButtons : l'état affiché doit refléter l'état réel.
  let idle = not isRunning
  btnRun.state = (if idle: csActive else: csGrayed)
  btnDebug.state = (if idle: csActive else: csGrayed)
  btnCont.state = (if isPaused: csActive else: csGrayed)
  btnStepIn.state = (if idle or isPaused: csActive else: csGrayed)
  btnStepOver.state = (if isPaused: csActive else: csGrayed)
  btnStepOut.state = (if isPaused: csActive else: csGrayed)
  btnPause.state = (if isRunning and not isPaused: csActive else: csGrayed)
  btnStop.state = (if isRunning: csActive else: csGrayed)

proc refreshRunButtons() =
  # Les boutons sont recalculés à partir de l'état réel (running, paused), sous
  # verrou : la fin du programme (fil de l'interpréteur) et les commandes de
  # l'atelier (autres fils) ne peuvent plus s'écraser dans le désordre.
  {.cast(gcsafe).}:
    withLock btnLock:
      var p = false
      withState: p = st.paused
      let r = running.load()
      setRunButtons(r, r and p)

#
# Projet
#

proc reindex() =
  let idx = indexProject(root())
  var names: seq[string]
  for n in idx.names: names.add n
  names.sort()
  withState: st.index = idx
  editorSetProjectNames(edId, names)

proc fillProjectTree() =
  let r = root()
  treeDeleteAll(trProj)
  if r.len == 0 or not dirExists(r): return
  var files: seq[string]
  for f in walkDirRec(r, relative = true):
    let u = f.replace('\\', '/')
    if u.startsWith(".") or "/." in u: continue
    files.add u
  files.sort()
  let top = extractFilename(r)
  for f in files: treeAdd(trProj, top & TreeSep & f.replace("/", $TreeSep))
  treeExpand(trProj, top)

proc openProject(dir: string) =
  if not dirExists(dir):
    alert(iconStop, "Dossier introuvable :\n" & dir)
    return
  withState:
    st.root = absolutePath(dir)
    st.settings.lastProject = st.root
  saveSettings(opts())
  fillProjectTree()
  reindex()
  if fileExists(dir / MainName) and not editorIsOpen(edId, dir / MainName):
    discard editorOpen(edId, dir / MainName, readFile(dir / MainName))
  status("Projet : " & dir)
  updateTitle()

proc openFile(path: string): int =
  result = -1
  let ext = path.splitFile.ext.toLowerAscii
  if ext notin TextExts and ext.len > 0:
    if confirm(iconQuestion, "Ouvrir « " & extractFilename(path) & " » comme texte ?") != drOk: return
  try:
    result = editorOpen(edId, path, readFile(path))
    if root().len == 0: openProject(path.parentDir)
  except IOError, OSError:
    alert(iconStop, "Lecture impossible :\n" & path)

#
# Analyse
#

proc refreshProblems() =
  var rowsText: seq[array[5, string]]
  var rows: seq[ProblemRow]
  withState:
    var uids: seq[int]
    for k in st.diagByUid.keys: uids.add k
    uids.sort()
    for uid in uids:
      let e = st.diagByUid[uid]
      for d in e.diags:
        rows.add ProblemRow(uid: uid, path: e.path, line: d.line, col: d.col)
        rowsText.add [$d.sev, e.title, $(d.line + 1), $(d.col + 1), d.msg]
    for r in st.runtimeRows:
      rows.add ProblemRow(uid: 0, path: r.path, line: r.line, col: 0)
      rowsText.add ["Exécution", extractFilename(r.path), $(r.line + 1), "", r.msg]
    st.rows = rows
  tableDeleteAll(tblProb)
  for t in rowsText:
    discard tableAddLine(tblProb, t[0], t[1], t[2], t[3], t[4])

proc refreshOutline(syms: seq[Symbol], uid: int) =
  var key = $uid & ":"
  for s in syms: key.add s.display & "@" & $s.line & ";"
  var changed = false
  withState:
    if key != st.outlineKey:
      st.outlineKey = key
      st.outline = syms
      changed = true
  if not changed: return
  listDeleteAll(lstOutline)
  for s in syms:
    let icon = case s.kind
      of symProc, symFunc: "ƒ "
      of symGlobal: "● "
      of symLocal: "· "
    discard listAdd(lstOutline, icon & s.display & "    :" & $(s.line + 1))

proc lintDoc(uid: int) =
  if uid < 0: return
  let snap = editorSnapshot(edId, uid)
  let info = editorInfo(edId, uid)
  if snap.lines.len == 0: return
  let (toks, _) = lexAll(snap.lines)
  let (syms, localNames) = collectSymbols(snap.lines, toks)
  var known: HashSet[string]
  var o: Settings
  withState:
    known = knownNamesFor(st.index, localNames)
    o = st.settings
  let diags = lint(snap.lines, toks, known,
                   LintOptions(flagGlobals: o.flagGlobals, unknownCalls: o.unknownCalls),
                   editorSourceName(edId, uid))
  editorSetDiagnostics(edId, uid, snap.version, diags)
  withState:
    st.diagByUid[uid] = (title: info.title, path: info.path, diags: diags)
  if uid == editorActiveUid(edId): refreshOutline(syms, uid)
  refreshProblems()

proc scheduleLint() =
  let g = lintGen.fetchAdd(1) + 1
  sleep(350)
  if lintGen.load() == g:
    lintDoc(editorActiveUid(edId))
    updateTitle()

proc lintAllOpen() =
  for d in editorDocs(edId): lintDoc(d.uid)

#
# Fichiers
#

proc saveAs(uid: int): bool

proc save(uid: int): bool =
  if uid < 0: return false
  let info = editorInfo(edId, uid)
  if info.path.len == 0: return saveAs(uid)
  try:
    writeFile(info.path, editorText(edId, uid))
    editorMarkSaved(edId, uid, info.version)
    status("Enregistré : " & relPath(info.path))
    reindex()
    lintDoc(uid)
    updateTitle()
    result = true
  except IOError, OSError:
    alert(iconStop, "Écriture impossible :\n" & info.path)

proc saveAs(uid: int): bool =
  if uid < 0: return false
  let info = editorInfo(edId, uid)
  var target = saveFileDialog(defaultName = info.title, filter = "Programmes Lexis+|*.prg\nTous les fichiers|*")
  if target.len == 0: return false
  if target.splitFile.ext.len == 0: target.add ".prg"
  try:
    writeFile(target, editorText(edId, uid))
    editorMarkSaved(edId, uid, info.version, target)
    if root().len == 0: openProject(target.parentDir) else: fillProjectTree()
    status("Enregistré : " & relPath(target))
    reindex()
    updateTitle()
    result = true
  except IOError, OSError:
    alert(iconStop, "Écriture impossible :\n" & target)

proc saveAll(): bool =
  result = true
  for d in editorDocs(edId):
    if d.dirty and d.path.len > 0 and not save(d.uid): result = false

proc closeDoc(uid: int) =
  let info = editorInfo(edId, uid)
  if info.dirty:
    if confirm(iconQuestion, "« " & info.title & " » a été modifié.\n" &
               "OK : enregistrer puis fermer.  Annuler : continuer l'édition.") != drOk: return
    if not save(uid): return
  editorClose(edId, uid)
  withState: st.diagByUid.del(uid)
  refreshProblems()
  lintDoc(editorActiveUid(edId))
  updateTitle()

proc newFileInProject() =
  let r = root()
  var name = "module.prg"
  # Annuler (ou fermeture de la boîte) : aucun fichier n'est créé.
  if not promptOk(iconQuestion, "Nom du nouveau fichier :", name): return
  name = name.strip()
  if name.len == 0: return
  if name.splitFile.ext.len == 0: name.add ".prg"
  if r.len == 0:
    discard editorNew(edId, name)
    return
  let path = r / name
  if fileExists(path):
    discard openFile(path)
    return
  let modName = name.changeFileExt("").extractFilename.toUpperAscii
  try:
    createDir(path.parentDir)
    writeFile(path, "&& " & name & " : procédures utilisables depuis tout le projet\n\n" &
              "procedure " & modName & "\n\nretourner\n")
  except IOError, OSError:
    alert(iconStop, "Création impossible :\n" & path)
    return
  fillProjectTree()
  discard openFile(path)

proc newProject() =
  var dir = getHomeDir() / "projet_lexis"
  # Annuler : aucun dossier ni fichier n'est créé.
  if not promptOk(iconQuestion, "Dossier du nouveau projet :", dir): return
  dir = dir.strip()
  if dir.len == 0: return
  try:
    createDir(dir)
    if not fileExists(dir / MainName): writeFile(dir / MainName, NewMain)
  except IOError, OSError:
    alert(iconStop, "Création impossible :\n" & dir)
    return
  openProject(dir)

#
# Navigation
#

proc uidForSource(source: string, open = true): int =
  result = editorUidOf(edId, source)
  if result < 0 and open and fileExists(source): result = openFile(source)

proc gotoFile(path: string, line, col: int) =
  var uid = uidForSource(path)
  if uid < 0 and root().len > 0:
    for f in walkDirRec(root()):
      if extractFilename(f) == extractFilename(path):
        uid = uidForSource(f)
        break
  if uid >= 0:
    editorGoto(edId, uid, line, col)
    editorFlush(edId)

proc gotoDefinition(word0: string) =
  if word0.len == 0: return
  let word = upper(word0.strip(chars = {'@'}))
  var locs: seq[Location]
  withState: locs = st.index.defs.getOrDefault(word)
  let uid = editorActiveUid(edId)
  if uid >= 0:
    let snap = editorSnapshot(edId, uid)
    let (toks, _) = lexAll(snap.lines)
    let (syms, _) = collectSymbols(snap.lines, toks)
    for s in syms:
      if s.name == word:
        editorGoto(edId, uid, s.line, 0)
        editorFlush(edId)
        return
  if locs.len > 0: gotoFile(locs[0].file, locs[0].line, 0)
  elif apiSummary(word0).len > 0: status(apiSummary(word0))
  else: status("Aucune définition trouvée pour « " & word0 & " »")

proc showSignature() =
  let ctx = editorCallContext(edId)
  if ctx.name.len > 0:
    let s = apiSummary(ctx.name, ctx.isMethod)
    if s.len > 0:
      status(s & "   [argument " & $(ctx.arg + 1) & "]")
      return
  let w = editorWordAtCursor(edId)
  if w.len > 0:
    let s = apiSummary(w)
    if s.len > 0: status(s)

#
# Recherche
#

proc doFind(replace: bool) =
  var req: FindRequest
  withState: req = st.findReq
  let sel = editorSelection(edId)
  if sel.len > 0 and '\n' notin sel: req.findText = sel
  if findDialog(req, replace = replace) != drOk: return
  withState: st.findReq = req
  if req.action == faReplaceAll:
    status($editorReplaceAll(edId, req) & " remplacement(s)")
  elif req.action == faReplace:
    discard editorReplace(edId, req)
  elif not editorFind(edId, req):
    status("« " & req.findText & " » introuvable")
  editorFlush(edId)

proc findAgain(backwards: bool) =
  var req: FindRequest
  withState: req = st.findReq
  if req.findText.len == 0:
    doFind(false)
    return
  when compiles(req.backwards):
    req.backwards = backwards
  if not editorFind(edId, req): status("« " & req.findText & " » introuvable")
  editorFlush(edId)

proc gotoLine() =
  let uid = editorActiveUid(edId)
  if uid < 0: return
  let cur = editorCursor(edId)
  let s = prompt(iconQuestion, "Aller à la ligne :", $(cur.line + 1))
  try:
    editorGoto(edId, uid, parseInt(s.strip()) - 1, 0)
    editorFlush(edId)
  except ValueError: discard

#
# Exécution et débogage
#

proc allBreakpoints(): seq[(string, seq[int])] =
  for d in editorDocs(edId):
    var lines: seq[int]
    for l in editorBreakpoints(edId, d.uid): lines.add l + 1
    result.add (editorSourceName(edId, d.uid), lines)

proc showPause(info: PauseInfo, frameIdx: int) =
  tableDeleteAll(tblVars)
  if frameIdx < info.frames.len:
    for v in info.frames[frameIdx].vars:
      discard tableAddLine(tblVars, v.name, v.value, v.kind, v.scope)
  for v in info.globals:
    discard tableAddLine(tblVars, v.name, v.value, v.kind, v.scope)

proc onPaused(info: PauseInfo) =
  if not running.load() or stopAsked.load(): return   # arrêt en cours : pas de pause.
  withState:
    st.pause = info
    st.paused = true
  refreshRunButtons()
  let uid = uidForSource(info.source)
  if uid >= 0:
    editorSetExecLine(edId, uid, info.line - 1)
    editorFlush(edId)
  listDeleteAll(lstStack)
  for f in info.frames:
    discard listAdd(lstStack, f.name & "    " & extractFilename(f.source) & ":" & $f.line)
  showPause(info, 0)
  tabBottom.value = "3"
  status("En pause : " & extractFilename(info.source) & " ligne " & $info.line &
         " — F5 continuer, F10 pas principal, F11 pas à pas, Maj+F11 sortir")

proc resume(mode: StepMode) =
  var wasPaused = false
  withState:
    wasPaused = st.paused
    st.paused = false
  if not wasPaused: return
  editorSetExecLine(edId, -1, 0)
  refreshRunButtons()
  status("Exécution…")
  debugCommand(mode)

proc programInput(prompt: string): (bool, string) =
  # es.lire / saisir : attend une ligne saisie dans la console.
  {.cast(gcsafe).}:
    if prompt.len > 0: consoleAppend(prompt)
    waitingInput.store(true)
    edIn.state = csActive
    setFocus(edIn)
    status("Le programme attend une saisie : tapez dans la console puis Entrée")
    acquire(inLock)
    while inQueue.len == 0 and running.load() and not stopAsked.load():
      wait(inCond, inLock)
    var line = ""
    var ok = false
    if inQueue.len > 0:
      line = inQueue.popFirst()
      ok = true
    release(inLock)
    waitingInput.store(false)
    if ok: consoleAppend(line & "\n")
    (ok, line)

proc sendInput() =
  let s = edIn.value
  edIn.value = ""
  {.cast(gcsafe).}:
    withLock inLock:
      inQueue.addLast s
      signal(inCond)

proc runProgramFrom(debug, stepFirst: bool) =
  # réservation atomique : deux déclenchements rapprochés ne lancent qu'une exécution.
  if running.exchange(true):
    status("Un programme est déjà en cours.")
    return
  let o = opts()
  let r = root()
  var path = ""
  if o.mainFile.len > 0 and r.len > 0 and fileExists(r / o.mainFile): path = r / o.mainFile
  elif r.len > 0 and fileExists(r / MainName): path = r / MainName
  else:
    let uid = editorActiveUid(edId)
    if uid < 0:
      running.store(false)
      status("Aucun programme à exécuter.")
      return
    path = editorSourceName(edId, uid)
  discard saveAll()
  stopAsked.store(false)
  {.cast(gcsafe).}:
    withLock inLock: inQueue.clear()     # pas de saisie restée d'une exécution précédente.
  withState:
    st.runtimeRows.setLen(0)
    st.paused = false
  refreshProblems()
  consoleClear()
  tableDeleteAll(tblVars)
  listDeleteAll(lstStack)
  tabBottom.value = "2"
  refreshRunButtons()
  updateTitle()
  consoleAppend("▶ " & extractFilename(path) & (if debug: " (débogage)" else: "") & "\n")
  status(if debug: "Débogage de " & extractFilename(path) else: "Exécution de " & extractFilename(path))
  var args: seq[string]
  for a in o.programArgs.splitWhitespace(): args.add a
  var hooks: SessionHooks
  hooks.output = proc (s: string) =
    {.cast(gcsafe).}: consoleAppend(s)
  hooks.input = proc (prompt: string): (bool, string) =
    {.cast(gcsafe).}: result = programInput(prompt)
  hooks.paused = proc (info: PauseInfo) =
    {.cast(gcsafe).}: onPaused(info)
  hooks.breakpoints = proc (): seq[(string, seq[int])] =
    {.cast(gcsafe).}: result = allBreakpoints()
  hooks.sourceProvider = proc (p: string): (bool, string) =
    {.cast(gcsafe).}:
      let uid = editorUidOf(edId, p)
      if uid >= 0: result = (true, editorText(edId, uid))
      else: result = (false, "")
  hooks.finished = proc (ok: bool, msg, source: string, line: int) =
    {.cast(gcsafe).}:
      running.store(false)
      withState: st.paused = false
      withLock inLock: signal(inCond)
      waitingInput.store(false)
      editorSetExecLine(edId, -1, 0)
      refreshRunButtons()
      if ok:
        consoleAppend("\n■ " & msg & "\n")
        status("Programme " & msg)
      else:
        consoleAppend("\n✖ " & msg & "\n")
        status("Erreur : " & msg.splitLines()[0])
        if line > 0:
          withState: st.runtimeRows.add (path: source, line: line - 1, msg: msg.splitLines()[0])
          refreshProblems()
          gotoFile(source, line - 1, 0)
      updateTitle()
  runProgram(path, args, debug, stepFirst, hooks)

proc doStop() =
  if not running.load(): return
  stopAsked.store(true)
  # Sortie de pause sans passer par resume() : resume() remettait les boutons
  # en « en cours » et pouvait le faire APRÈS la fin du programme (course entre
  # fils), laissant la barre figée alors que le programme était arrêté.
  withState: st.paused = false
  editorSetExecLine(edId, -1, 0)
  status("Arrêt demandé…")
  stopProgram()                          # drapeau d'arrêt + reprise du débogueur + fermeture des fenêtres.
  {.cast(gcsafe).}:
    withLock inLock: signal(inCond)      # débloque une saisie en attente.
  refreshRunButtons()
  # Si le programme ne s'arrête pas (appel bloquant : dialogue modal, réseau,
  # fil qui ne rend pas la main...), le dire au lieu de laisser un état ambigu.
  var waited = 0
  while running.load() and waited < 3000:
    sleep(50)
    waited += 50
  if running.load():
    status("Le programme ne répond pas encore à l'arrêt (appel bloquant en cours) — Arrêter à nouveau, ou fermez ses dialogues.")
    consoleAppend("\n[arrêt demandé : le programme est bloqué dans un appel qui ne rend pas la main " &
                  "(dialogue, réseau, fil...). Il s'arrêtera dès que cet appel se terminera.]\n")

proc doContinueOrDebug() =
  var p = false
  withState: p = st.paused
  if p: resume(smRun)
  elif not running.load(): runProgramFrom(true, false)

proc doStep(mode: StepMode) =
  var p = false
  withState: p = st.paused
  if p: resume(mode)
  elif not running.load() and mode == smInto: runProgramFrom(true, true)

proc syncBreakpoints(uid: int) =
  if not running.load(): return
  var lines: seq[int]
  for l in editorBreakpoints(edId, uid): lines.add l + 1
  updateBreakpoints(editorSourceName(edId, uid), lines)

proc programArguments() =
  var o = opts()
  o.programArgs = prompt(iconQuestion, "Arguments du programme (systeme.args) :", o.programArgs)
  o.mainFile = prompt(iconQuestion,
    "Fichier principal, relatif au projet (vide = principal.prg, sinon le fichier actif) :", o.mainFile).strip()
  setOpts(o)

#
# Panneau API
#

proc fillApiTree() =
  let rows = apiEntries()
  withState: st.apiRows = rows
  treeDeleteAll(trApi)
  for e in rows: treeAdd(trApi, e.section & TreeSep & e.signature)

#
# Fiches Markdown du panneau Référence
#

const ApiDocWelcome = """### Référence

Sélectionnez un **paquet** ou une **fonction** dans l'arbre ci-dessus pour afficher sa fiche.

- Double-clic sur une fonction : insérer l'appel dans l'éditeur.
- Cmd/Ctrl+C dans ce cadre : copier la fiche (Markdown)."""

proc mdEscape(s: string): string =
  for ch in s:
    if ch in {'\\', '`', '*', '_', '[', ']'}: result.add '\\'
    result.add ch

proc mdCode(s: string): string =
  let f = if '`' in s: "`` " else: "`"
  f & s & (if '`' in s: " ``" else: "`")

proc isIdentByte(c: char): bool = c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}

proc matchingClose(s: string, i: int): int =
  ## Position de la parenthèse / accolade / crochet fermant celui ouvert en s[i], -1 sinon.
  var depth = 0
  var inStr = false
  for k in i ..< s.len:
    let c = s[k]
    if inStr:
      if c == '"': inStr = false
    elif c == '"': inStr = true
    elif c in {'(', '{', '['}: inc depth
    elif c in {')', '}', ']'}:
      dec depth
      if depth == 0: return k
  -1

proc mdInline(s: string): string =
  ## Texte de description -> Markdown : chaînes "…", appels f(…), noms pkg.f / obj:f,
  ## @procédures, URL et extensions .prg en code ; vrai/faux/nul en code.
  var i = 0
  while i < s.len:
    let c = s[i]
    let atStart = i == 0 or not (isIdentByte(s[i - 1]) or ord(s[i - 1]) >= 128)
    if c == '"':
      let j = s.find('"', i + 1)
      if j > i:
        result.add mdCode(s[i .. j])
        i = j + 1
        continue
    if c == '@' and i + 1 < s.len and isIdentByte(s[i + 1]):
      var j = i + 1
      while j < s.len and isIdentByte(s[j]): inc j
      result.add mdCode(s[i ..< j])
      i = j
      continue
    if c == '.' and atStart and i + 2 < s.len and s[i + 1] in {'a' .. 'z'} and
       (i == 0 or s[i - 1] == ' '):
      var j = i + 1
      while j < s.len and s[j] in {'a' .. 'z', '0' .. '9'}: inc j
      if j - i <= 6 and (j == s.len or not isIdentByte(s[j])):
        result.add mdCode(s[i ..< j])
        i = j
        continue
    if atStart and c in {'a' .. 'z', 'A' .. 'Z', '_'}:
      var j = i
      var dotted = false
      while j < s.len:
        if isIdentByte(s[j]): inc j
        elif s[j] in {'.', ':'} and j + 1 < s.len and s[j + 1] in {'a' .. 'z', 'A' .. 'Z', '_'}:
          dotted = true
          inc j
        else: break
      let word = s[i ..< j]
      if j + 2 < s.len and s[j] == ':' and s[j + 1] == '/' and s[j + 2] == '/':
        var k = j
        while k < s.len and s[k] notin {' ', ',', ';', ')'}: inc k
        if k > j + 3 and s[k - 1] == '.': dec k
        result.add mdCode(s[i ..< k])
        i = k
        continue
      if j < s.len and s[j] == '(':
        let k = matchingClose(s, j)
        if k > j:
          result.add mdCode(s[i .. k])
          i = k + 1
          continue
      if dotted and not word.endsWith("."):
        result.add mdCode(word)
        i = j
        continue
      if word.toLowerAscii in ["vrai", "faux", "nul"] and (j == s.len or not isIdentByte(s[j])) and
         not s[0 ..< i].endsWith("octet "):   # « octet nul » : adjectif, pas la valeur nul.
        result.add mdCode(word)
        i = j
        continue
      result.add mdEscape(word)
      i = j
      continue
    result.add mdEscape($c)
    inc i

proc splitTop(s: string, sep: char): seq[string] =
  ## Découpe sur `sep` hors parenthèses, accolades, crochets, chaînes et « … ».
  var depth = 0
  var inStr = false
  var guil = 0
  var cur = ""
  var i = 0
  while i < s.len:
    let c = s[i]
    if s.continuesWith("«", i): inc guil
    elif s.continuesWith("»", i): guil = max(0, guil - 1)
    if inStr:
      if c == '"': inStr = false
    elif c == '"': inStr = true
    elif c in {'(', '{', '['}: inc depth
    elif c in {')', '}', ']'}: dec depth
    elif c == sep and depth == 0 and guil == 0:
      result.add cur.strip()
      cur = ""
      inc i
      continue
    cur.add c
    inc i
  if cur.strip().len > 0: result.add cur.strip()

proc mdParams(sig: string): seq[string] =
  ## Lignes de liste Markdown décrivant les paramètres d'une signature.
  let p = sig.find({'(', '{'})
  if p < 0: return
  let q = matchingClose(sig, p)
  if q < 0: return
  let named = sig[p] == '{'
  proc option(o: string): string =
    let eq = o.find('=')
    if eq < 0: return "  - " & mdCode(o.strip())
    let k = o[0 ..< eq].strip()
    let d = o[eq + 1 .. ^1].strip()
    "  - " & mdCode(k) & (if d.len > 0: " — défaut " & mdCode(d) else: "")
  if named:
    result.add "- **Options nommées** (table `{...}`) :"
    for o in splitTop(sig[p + 1 ..< q], ','): result.add option(o)
    return
  for a0 in splitTop(sig[p + 1 ..< q], ','):
    var a = a0
    var optional = false
    if a.startsWith("[") and a.endsWith("]"):
      optional = true
      a = a[1 .. ^2].strip()
    if a == "...":
      result.add "- " & mdCode("...") & " — nombre variable de valeurs"
    elif a.startsWith("{") and a.endsWith("}"):
      result.add "- **Options** (table `{...}`" & (if optional: ", facultative" else: "") & ") :"
      for o in splitTop(a[1 .. ^2], ','): result.add option(o)
    elif a.startsWith("@"):
      result.add "- " & mdCode(a) & " — procédure passée par référence (`@NOM`)" &
        (if optional: ", *facultative*" else: "")
    elif a.endsWith("..."):
      result.add "- " & mdCode(a) & " — valeurs supplémentaires"
    else:
      result.add "- " & mdCode(a) & (if optional: " — *facultatif*" else: "")

proc mdDescription(doc: string): tuple[body: string, returns: string] =
  ## Sépare « renvoie … » du reste ; trois propositions ou plus (séparées par « ; »)
  ## deviennent une liste, « clé : texte » mettant la clé en code.
  const NewSentence = '\1'   # proposition qui commence une nouvelle phrase.
  var clauses: seq[string]
  for c in splitTop(doc, ';'):
    let l = c.toLowerAscii
    if l.startsWith("renvoie ") and result.returns.len == 0:
      var r = c[8 .. ^1].strip()
      let dot = r.find(". ")
      if dot >= 0:
        clauses.add NewSentence & r[dot + 2 .. ^1]
        r = r[0 .. dot]
      result.returns = r
    else: clauses.add c
  if result.returns.len == 0:
    for k, c in clauses:
      let pos = c.find(". Renvoie ")
      if pos >= 0:
        var r = c[pos + 10 .. ^1].strip()
        clauses[k] = c[0 .. pos]
        let dot = r.find(". ")
        if dot >= 0:
          clauses.insert(NewSentence & r[dot + 2 .. ^1], k + 1)
          r = r[0 .. dot]
        result.returns = r
        break
  if result.returns.endsWith("."): result.returns.setLen(result.returns.len - 1)
  var semis = 0
  for c in clauses:
    if c.len == 0 or c[0] != NewSentence: inc semis
  if semis >= 3:
    var intro = ""
    var items = clauses
    for it in items.mitems: it = it.strip(chars = {NewSentence})
    let dot = items[0].rfind(". ")
    if dot >= 0:
      intro = items[0][0 .. dot]
      items[0] = items[0][dot + 2 .. ^1]
    var lines: seq[string]
    if intro.len > 0: lines.add mdInline(intro) & "\n"
    for it in items:
      var t = it.strip()
      if t.endsWith("."): t.setLen(t.len - 1)
      let colon = t.find(" : ")
      if colon > 0 and colon <= 24 and t[0 ..< colon].allCharsInSet(IdentChars + {' ', '=', '"'}):
        lines.add "- " & mdCode(t[0 ..< colon]) & " : " & mdInline(t[colon + 3 .. ^1])
      else: lines.add "- " & mdInline(t)
    result.body = lines.join("\n")
  else:
    var t = ""
    for c in clauses:
      if c.len > 0 and c[0] == NewSentence:
        if t.len > 0 and t[^1] notin {'.', '!', '?', ')'}: t.add '.'
        t.add " " & c[1 .. ^1]
      elif t.len > 0: t.add " ; " & c
      else: t = c
    t = t.strip()
    if t.len > 0 and t[0] in {'a' .. 'z'}: t[0] = toUpperAscii(t[0])
    if t.len > 0 and t[^1] notin {'.', '!', '?', ':', ')'} and not t.endsWith("»"): t.add '.'
    elif t.endsWith(")") and not t.endsWith(".)"): t.add '.'
    result.body = mdInline(t)
  if result.returns.len > 0 and result.returns[0] in {'A' .. 'Z'} and
     (result.returns.len < 2 or result.returns[1] notin {'A' .. 'Z'}):
    result.returns[0] = toLowerAscii(result.returns[0])

proc availabilityMd(section: string): string =
  if section == "base": "fonction intégrée, toujours disponible."
  elif section in ["es", "systeme"]: "paquet " & mdCode(section) & ", toujours disponible."
  else: "paquet " & mdCode(section) & " : " & mdCode(section & ".fonction(...)") &
        " ou " & mdCode("x = paquet(\"" & section & "\")") & "."

proc apiDocMarkdown(e: ApiDoc): string =
  let callable = e.signature.find({'(', '{'}) >= 0
  let full = e.signature.split({'(', '{'})[0].strip()
  var md = @["# " & mdEscape(full), ""]
  if e.isMethod:
    md.add "**Méthode** de l'objet " & mdCode(e.owner) & " · paquet " & mdCode(e.section)
  elif e.owner.len > 0:
    md.add (if callable: "**Fonction** du paquet " else: "**Valeur** du paquet ") & mdCode(e.owner)
  else:
    md.add "**Fonction intégrée**"
  md.add ""
  md.add "```"
  md.add e.signature
  md.add "```"
  md.add ""
  let params = mdParams(e.signature)
  if params.len > 0:
    md.add "## Paramètres"
    md.add params
    md.add ""
  elif callable:
    md.add "*Aucun paramètre.*"
    md.add ""
  let (body, returns) = mdDescription(e.doc)
  md.add "## Description"
  md.add body
  md.add ""
  if returns.len > 0:
    md.add "**Renvoie** : " & mdInline(returns) & "."
    md.add ""
  md.add "---"
  md.add "> **Disponibilité** : " & availabilityMd(e.section)
  md.add ""
  md.add "*Double-clic dans l'arbre : insérer l'appel.*"
  md.join("\n")

proc firstSentence(s: string): string =
  var p = s.find(". ")
  while p > 0 and s[p - 1] == '.': p = s.find(". ", p + 2)   # « ... » n'est pas une fin de phrase.
  result = if p >= 0: s[0 .. p - 1] else: s.strip(chars = {' ', '.'})
  if result.len > 90:
    let cut = result.rfind(' ', 0, 85)
    result = result[0 ..< max(cut, 40)] & "…"

proc packageMarkdown(section: string, rows: seq[ApiDoc]): string =
  var desc = ""
  for p in packages():
    if p.name == section:
      desc = p.description
      break
  var md = @[(if section == "base": "# Fonctions intégrées" else: "# Paquet " & mdCode(section)), ""]
  if desc.len > 0: md.add mdInline(desc) & "\n"
  md.add "> **Disponibilité** : " & availabilityMd(section)
  md.add ""
  var fns, meths, vals: seq[string]
  for e in rows:
    if e.section != section: continue
    let line = "- " & mdCode(e.signature) & " — " & mdInline(firstSentence(e.doc))
    if e.isMethod: meths.add line
    elif e.signature.find({'(', '{'}) < 0: vals.add line
    else: fns.add line
  if fns.len > 0:
    md.add "## Fonctions (" & $fns.len & ")"
    md.add fns
    md.add ""
  if vals.len > 0:
    md.add "## Valeurs (" & $vals.len & ")"
    md.add vals
    md.add ""
  if meths.len > 0:
    md.add "## Méthodes (" & $meths.len & ")"
    md.add meths
    md.add ""
  md.add "*Sélectionnez une entrée pour afficher sa fiche.*"
  md.join("\n")

proc apiEntryForPath(path: string): (bool, ApiDoc) =
  let parts = path.split(TreeSep)
  if parts.len < 2: return
  withState:
    for e in st.apiRows:
      if e.section == parts[0] and e.signature == parts[^1]:
        return (true, e)

proc callTemplate(e: ApiDoc): string =
  var sig = e.signature
  let p = sig.find('(')
  if p < 0: return sig
  var args = sig[p + 1 .. ^2]
  let b = args.find('[')
  if b >= 0: args = args[0 ..< b]
  args = args.strip(chars = {' ', ','})
  let head = sig[0 ..< p]
  if e.isMethod: ":" & e.name & "(" & args & ")" else: head & "(" & args & ")"

#
# Menus
#

const EditorBaseFont = 14.0     # taille par défaut de la police de l'éditeur.

proc applyView() =
  let o = opts()
  editorSetOptions(edId, o.minimap, o.dark)
  editorSetFontSize(edId, EditorBaseFont + float(o.fontDelta))
  if haveWin.load(): gWin.theme = themeFor(o.dark, o.fontDelta)

proc changeFont(delta: int, reset = false) =
  var o = opts()
  let d = (if reset: 0 else: clamp(o.fontDelta + delta, FontDeltaMin, FontDeltaMax))
  if d == o.fontDelta:
    status(if reset: "La police est déjà à sa taille par défaut."
           elif delta > 0: "Taille de police maximale atteinte."
           else: "Taille de police minimale atteinte.")
    return
  o.fontDelta = d
  setOpts(o)
  applyView()
  status("Police : " & $int(EditorBaseFont + float(d)) & " pt dans l'éditeur" &
         (if d == 0: " (taille par défaut)" elif d > 0: " (+" & $d & ")" else: " (" & $d & ")"))

#
# Concepteur de formulaires
#

proc designerCodeFile(): string =
  # Code qui recevra les procédures : le .prg actif s'il est dans le projet (et
  # n'est pas un formulaire), sinon le fichier principal.
  let r = root()
  let uid = editorActiveUid(edId)
  if uid >= 0:
    let p = editorInfo(edId, uid).path
    if p.len > 0 and p.toLowerAscii.endsWith(".prg") and not isFormFile(p) and
       normalizedPath(absolutePath(p)).startsWith(normalizedPath(absolutePath(r))):
      return p
  let o = opts()
  if o.mainFile.len > 0 and fileExists(r / o.mainFile): return r / o.mainFile
  if fileExists(r / MainName): return r / MainName
  ""

proc openFormDesigner(formFile: string) =
  let r = root()
  if r.len == 0:
    alert(iconInformation, "Ouvrez d'abord un projet (Fichier > Ouvrir un projet…).", title = "Concepteur de formulaires")
    return
  if designerIsOpen():
    alert(iconInformation, "Le concepteur de formulaires est déjà ouvert.", title = "Concepteur de formulaires")
    return
  var code = designerCodeFile()
  if code.len == 0:
    alert(iconInformation, "Ouvrez ou créez d'abord un fichier .prg du projet : il recevra les procédures " &
          "des événements du formulaire.", title = "Concepteur de formulaires")
    return
  let uid = editorUidOf(edId, code)
  if uid >= 0 and editorInfo(edId, uid).dirty: discard save(uid)
  if not openDesigner(r, code, formFile, edId, theme(gWin)):
    alert(iconStop, "« " & extractFilename(formFile) & " » ne contient pas de dessin de formulaire " &
          "(lignes « &&§ » écrites par le concepteur).", title = "Concepteur de formulaires")
  else:
    status("Concepteur : " & (if formFile.len > 0: extractFilename(formFile) else: "nouveau formulaire") &
           " · code : " & extractFilename(code))

proc designerButton() =
  # Formulaire actif dans l'éditeur : le rouvrir ; sinon nouveau formulaire pour le fichier courant.
  let uid = editorActiveUid(edId)
  let p = if uid >= 0: editorInfo(edId, uid).path else: ""
  if p.len > 0 and isFormFile(p): openFormDesigner(p) else: openFormDesigner("")

proc onDesignerFile(path: string) {.nimcall, gcsafe.} =
  {.cast(gcsafe).}: (fillProjectTree(); reindex())

proc onDesignerCode(path: string) {.nimcall, gcsafe.} =
  {.cast(gcsafe).}: reindex()

proc openReport(reportFile: string) =
  let r = root()
  if r.len == 0:
    alert(iconInformation, "Ouvrez d'abord un projet (Fichier > Ouvrir un projet…).", title = "Éditeur d'états")
    return
  let msg = openReportDesigner(r, reportFile, edId, theme(gWin))
  if msg.len > 0: alert(iconInformation, msg, title = "Éditeur d'états")
  else: status("Éditeur d'états : " & (if reportFile.len > 0: extractFilename(reportFile) else: "nouvel état"))

proc onMenu(path: string) =
  let item = path.split(TreeSep)[^1]
  case item
  of "Nouveau projet…": newProject()
  of "Ouvrir un projet…":
    let f = openFileDialog(title = "Choisissez un fichier du dossier du projet (ex. principal.prg)",
                           filter = "Programmes Lexis+|*.prg\nTous les fichiers|*")
    if f.len > 0: openProject(f.parentDir)
  of "Ouvrir un dossier par son chemin…":
    var d = (if root().len > 0: root() else: getHomeDir())
    if promptOk(iconQuestion, "Chemin du dossier :", d) and d.strip().len > 0: openProject(d.strip())
  of "Nouveau fichier…": newFileInProject()
  of "Ouvrir un fichier…":
    let f = openFileDialog(title = "Ouvrir", filter = "Programmes Lexis+|*.prg\nTous les fichiers|*")
    if f.len > 0: discard openFile(f)
  of "Enregistrer": discard save(editorActiveUid(edId))
  of "Enregistrer sous…": discard saveAs(editorActiveUid(edId))
  of "Enregistrer tout": discard saveAll()
  of "Fermer l'onglet":
    let uid = editorActiveUid(edId)
    if uid >= 0: closeDoc(uid)
  of "Quitter":
    var dirty = false
    for d in editorDocs(edId):
      if d.dirty: dirty = true
    if not dirty or confirm(iconExclamation, "Des fichiers ne sont pas enregistrés. Quitter quand même ?") == drOk:
      doStop()
      saveSettings(opts())
      quitApplication()
  of "Annuler": editorCommand(edId, "undo")
  of "Rétablir": editorCommand(edId, "redo")
  of "Couper": editorCommand(edId, "cut")
  of "Copier": editorCommand(edId, "copy")
  of "Coller": editorCommand(edId, "paste")
  of "Tout sélectionner": editorCommand(edId, "selectall")
  of "Dupliquer la ligne": editorCommand(edId, "dup")
  of "Commenter / décommenter": editorCommand(edId, "comment")
  of "Indenter": editorCommand(edId, "indent")
  of "Désindenter": editorCommand(edId, "outdent")
  of "Rechercher…": doFind(false)
  of "Remplacer…": doFind(true)
  of "Occurrence suivante": findAgain(false)
  of "Aller à la ligne…": gotoLine()
  of "Aller à la définition": gotoDefinition(editorWordAtCursor(edId))
  of "Vérifier les fichiers ouverts":
    reindex()
    lintAllOpen()
    tabBottom.value = "1"
  of "Exécuter (Ctrl+R)": runProgramFrom(false, false)
  of "Déboguer / Continuer (F5)": doContinueOrDebug()
  of "Pas à pas (F11)": doStep(smInto)
  of "Pas principal (F10)": doStep(smOver)
  of "Sortir de la procédure (Maj+F11)": doStep(smOut)
  of "Pause": pauseProgram()
  of "Arrêter (Maj+F5)": doStop()
  of "Basculer le point d'arrêt (F9)": editorToggleBreakpoint(edId)
  of "Supprimer tous les points d'arrêt": editorClearBreakpoints(edId)
  of "Arguments et fichier principal…": programArguments()
  of "Nouveau formulaire pour le fichier courant…": openFormDesigner("")
  of "Ouvrir un formulaire…":
    let r = root()
    if r.len == 0: openFormDesigner("")
    else:
      let p = openFileDialog(title = "Ouvrir un formulaire", folder = r,
                             filter = "Formulaires Lexis+ (form_*.prg)|*.prg")
      if p.len > 0:
        if not isFormFile(p):
          alert(iconInformation, "Choisissez un fichier form_<nom>.prg créé par le concepteur.",
                title = "Concepteur de formulaires")
        else: openFormDesigner(p)
  of "Concepteur de formulaires": designerButton()
  of "Nouvel état…": openReport("")
  of "Ouvrir un état…":
    let r = root()
    if r.len == 0: openReport("")
    else:
      let p = openFileDialog(title = "Ouvrir un état", folder = r, filter = "États Lexis+ (etat_*.prg)|*.prg")
      if p.len > 0:
        if not isReportFile(p):
          alert(iconInformation, "Choisissez un fichier etat_<nom>.prg créé par l'éditeur d'états.",
                title = "Éditeur d'états")
        else: openReport(p)
  of "Générer l'application…":
    if root().len == 0:
      alert(iconInformation, "Ouvrez d'abord un projet (Fichier > Ouvrir un projet…).", title = "Générer l'application")
    else:
      discard saveAll()
      status("Génération de l'application…")
      generationDialog(root(), opts().mainFile, theme(gWin))
      fillProjectTree()
      status("Prêt")
  of "Minicarte":
    var o = opts()
    o.minimap = not o.minimap
    setOpts(o)
    applyView()
  of "Agrandir la police (Ctrl++)": changeFont(+1)
  of "Réduire la police (Ctrl+-)": changeFont(-1)
  of "Taille de police par défaut (Ctrl+0)": changeFont(0, reset = true)
  of "Thème sombre / clair":
    var o = opts()
    o.dark = not o.dark
    setOpts(o)
    applyView()
  of "Signaler les variables globales implicites":
    var o = opts()
    o.flagGlobals = not o.flagGlobals
    setOpts(o)
    lintAllOpen()
  of "Signaler les procédures inconnues":
    var o = opts()
    o.unknownCalls = not o.unknownCalls
    setOpts(o)
    lintAllOpen()
  of "Raccourcis clavier": alert(iconInformation, Shortcuts, title = "Raccourcis")
  of "Référence des fonctions et paquets": tabLeft.value = "3"
  of "Copier la console": consoleCopy()
  of "Effacer la console": consoleClear()
  of "À propos":
    var names: seq[string]
    for p in packages(): names.add p.name
    alert(iconInformation,
      "wdlexis+ [S]tudio 1.6.0\nAtelier du langage Lexis+\n" &
      "Développez naturellement vos applications métier\n\n" &
      "Tous droits réservés 2026 - Jean-Marc QUÉRÉ\n" &
      "⛶ https://sonaliwan.fr - ✉ metalab (at) sonaliwan.fr\n" &
      "SIRET 13033319800013\n\n" &
      "Paquets : " & names.join(", ") & "\n" & $apiEntries().len & " fonctions documentées.",
      title = "À propos")
  else: discard

proc buildMenu(m: ControlId) =
  let menus = [
    ("Fichier", @["Nouveau projet…", "Ouvrir un projet…", "Ouvrir un dossier par son chemin…",
                  "Nouveau fichier…", "Ouvrir un fichier…", "Enregistrer", "Enregistrer sous…",
                  "Enregistrer tout", "Fermer l'onglet", "Quitter"]),
    ("Édition", @["Annuler", "Rétablir", "Couper", "Copier", "Coller", "Tout sélectionner",
                  "Dupliquer la ligne", "Commenter / décommenter", "Indenter", "Désindenter"]),
    ("Recherche", @["Rechercher…", "Remplacer…", "Occurrence suivante", "Aller à la ligne…",
                    "Aller à la définition"]),
    ("Exécuter", @["Exécuter (Ctrl+R)", "Déboguer / Continuer (F5)", "Pas à pas (F11)",
                   "Pas principal (F10)", "Sortir de la procédure (Maj+F11)", "Pause",
                   "Arrêter (Maj+F5)", "Basculer le point d'arrêt (F9)",
                   "Supprimer tous les points d'arrêt", "Vérifier les fichiers ouverts",
                   "Arguments et fichier principal…", "Générer l'application…"]),
    ("Conception", @["Nouveau formulaire pour le fichier courant…", "Ouvrir un formulaire…",
                     "Concepteur de formulaires", "-", "Nouvel état…", "Ouvrir un état…"]),
    ("Affichage", @["Copier la console", "Effacer la console", "Agrandir la police (Ctrl++)",
                    "Réduire la police (Ctrl+-)", "Taille de police par défaut (Ctrl+0)",
                    "Minicarte", "Thème sombre / clair", "Signaler les variables globales implicites",
                    "Signaler les procédures inconnues"]),
    ("Aide", @["Raccourcis clavier", "Référence des fonctions et paquets", "À propos"])]
  for (top, items) in menus:
    for it in items: menuAdd(m, top & TreeSep & it)

#
# Signaux de l'éditeur
#

proc onEditorSignal(text: string) =
  if text.startsWith("pos:"):
    let p = text.split(':')
    if p.len >= 3: lblPos.caption = "Ln " & p[1] & ", Col " & p[2]
    showSignature()
  elif text.startsWith("doc:"):
    lintDoc(editorActiveUid(edId))
    updateTitle()
  elif text.startsWith("bp:"):
    try: syncBreakpoints(parseInt(text[3 .. ^1])) except ValueError: discard
  elif text.startsWith("cmd:"):
    let parts = text[4 .. ^1].split(':', maxsplit = 1)
    let arg = if parts.len > 1: parts[1] else: ""
    case parts[0]
    of "save": discard save(editorActiveUid(edId))
    of "saveas": discard saveAs(editorActiveUid(edId))
    of "find": doFind(false)
    of "replace": doFind(true)
    of "findnext": findAgain(false)
    of "findprev": findAgain(true)
    of "goto": gotoLine()
    of "run": runProgramFrom(false, false)
    of "debug": doContinueOrDebug()
    of "stop": doStop()
    of "stepinto": doStep(smInto)
    of "stepover": doStep(smOver)
    of "stepout": doStep(smOut)
    of "new": newFileInProject()
    of "fontbigger": changeFont(+1)
    of "fontsmaller": changeFont(-1)
    of "fontreset": changeFont(0, reset = true)
    of "open": onMenu("Fichier" & TreeSep & "Ouvrir un fichier…")
    of "close":
      try: closeDoc(parseInt(arg)) except ValueError: discard
    of "definition": gotoDefinition(arg)
    else: discard

#
# Gestionnaire
#

proc handleEvent(ev: var Event) =
  block:
    if not haveWin.load():
      {.cast(gcsafe).}: gWin = ev.window
      haveWin.store(true)
    if ev.current != ev.id: return
    case ev.kind
    of evWindowOpen:
      applyView()
      let uid = editorActiveUid(edId)
      if uid >= 0: lintDoc(uid)
      updateTitle()
    of evSelection:
      if ev.id == mnu: onMenu(ev.text)
      elif ev.id == edId: onEditorSignal(ev.text)
      elif ev.id == trProj:
        let r = root()
        let parts = ev.text.split(TreeSep)
        if r.len > 0 and parts.len > 1:
          let p = r / parts[1 .. ^1].join($DirSep)
          if fileExists(p):
            discard openFile(p)
            lintDoc(editorActiveUid(edId))
            updateTitle()
      elif ev.id == lstOutline:
        var s: Symbol
        var ok = false
        withState:
          if ev.index >= 1 and ev.index <= st.outline.len:
            s = st.outline[ev.index - 1]
            ok = true
        if ok:
          editorGoto(edId, editorActiveUid(edId), s.line, 0)
          editorFlush(edId)
      elif ev.id == lstStack:
        var info: PauseInfo
        withState: info = st.pause
        let i = ev.index - 1
        if i >= 0 and i < info.frames.len:
          showPause(info, i)
          gotoFile(info.frames[i].source, info.frames[i].line - 1, 0)
      elif ev.id == trApi:
        let (ok, e) = apiEntryForPath(ev.text)
        if ok: edApiDoc.value = apiDocMarkdown(e)
        elif ev.text.len > 0 and TreeSep notin ev.text:
          var rows: seq[ApiDoc]
          withState: rows = st.apiRows
          edApiDoc.value = packageMarkdown(ev.text, rows)
      elif ev.id == tblProb:
        var row: ProblemRow
        var ok = false
        withState:
          if ev.index >= 1 and ev.index <= st.rows.len:
            row = st.rows[ev.index - 1]
            ok = true
        if ok:
          if row.uid > 0:
            editorGoto(edId, row.uid, row.line, row.col)
            editorFlush(edId)
          else: gotoFile(row.path, row.line, 0)
    of evDoubleClick:
      if ev.id == trProj:
        let r = root()
        let parts = trProj.value.split(TreeSep)
        if r.len > 0 and parts.len > 1:
          let p = r / parts[1 .. ^1].join($DirSep)
          if fileExists(p) and isFormFile(p): openFormDesigner(p)
          elif fileExists(p) and isReportFile(p): openReport(p)
      elif ev.id == trApi:
        let (ok, e) = apiEntryForPath(trApi.value)
        if ok:
          editorInsert(edId, callTemplate(e))
          editorFlush(edId)
    of evChange:
      if ev.id == edId:
        updateTitle()
        scheduleLint()
    of evKeyDown:
      if ev.id == edIn and int(ev.key) in [KReturn, KKpEnter]: sendInput()
    of evClick:
      if ev.id == btnOpen: onMenu("Fichier" & TreeSep & "Ouvrir un projet…")
      elif ev.id == btnNew: newFileInProject()
      elif ev.id == btnSave: discard save(editorActiveUid(edId))
      elif ev.id == btnCheck: onMenu("Exécuter" & TreeSep & "Vérifier les fichiers ouverts")
      elif ev.id == btnRun: runProgramFrom(false, false)
      elif ev.id == btnDebug: runProgramFrom(true, false)
      elif ev.id == btnCont: resume(smRun)
      elif ev.id == btnStepIn: doStep(smInto)
      elif ev.id == btnStepOver: doStep(smOver)
      elif ev.id == btnStepOut: doStep(smOut)
      elif ev.id == btnPause: pauseProgram()
      elif ev.id == btnStop: doStop()
      elif ev.id == btnSend: sendInput()
      elif ev.id == btnCopy: consoleCopy()
      elif ev.id == btnClear: consoleClear()
    of evWindowClose:
      doStop()
      closeDesigner()
      closeReportDesigner()
      saveSettings(opts())
    else: discard

proc handler(ev: var Event) {.nimcall, gcsafe.} =
  # L'état partagé est protégé par gLock (withState). Le corps est dans une
  # procédure à part : avec Nim 2.2, un {.cast(gcsafe).} imbriqué (withState,
  # guarded…) rétablit le contrôle pour la suite du bloc englobant.
  {.cast(gcsafe).}: handleEvent(ev)

#
# Interface
#

proc toolButton[T](bar: T, caption, tip: string): ControlId =
  result = bar.addChild(newButton(caption)).id
  result.tooltip = tip

proc buildUi() =
  initLangDocs()
  let s = loadSettings()
  withState:
    st.settings = s
    st.diagByUid = initTable[int, tuple[title, path: string, diags: seq[Diagnostic]]]()
    st.index = initProjectIndex()
  {.cast(gcsafe).}: inQueue = initDeque[string]()
  var startDir = ""
  var startFile = ""
  if paramCount() >= 1:
    let a = absolutePath(paramStr(1))
    if dirExists(a): startDir = a
    elif fileExists(a):
      startDir = a.parentDir
      startFile = a
  elif s.lastProject.len > 0 and dirExists(s.lastProject):
    startDir = s.lastProject

  win = newWindow(AppName & " — Lexis+", 1320, 860, handler, layout = lkBorder, theme = themeFor(s.dark, s.fontDelta))

  let top = win.addChild(newSupercontrol(lkVertical))
  top.dock = dkTop
  mnu = top.addChild(newMenuBar()).id
  buildMenu(mnu)
  let bar = top.addChild(newSupercontrol(lkHorizontal))
  btnOpen = bar.toolButton("Ouvrir", "Ouvrir un projet")
  btnNew = bar.toolButton("Nouveau", "Nouveau fichier")
  btnSave = bar.toolButton("Enregistrer", "Ctrl+S")
  btnCheck = bar.toolButton("Vérifier", "Analyser les fichiers ouverts")
  btnRun = bar.toolButton("▶ Exécuter", "Ctrl+R : exécution directe")
  btnDebug = bar.toolButton("Déboguer", "F5 : exécution jusqu'au prochain point d'arrêt")
  btnCont = bar.toolButton("Continuer", "F5 (en pause)")
  btnStepIn = bar.toolButton("Pas à pas", "F11 : entrer dans les procédures")
  btnStepOver = bar.toolButton("Pas principal", "F10 : passer par-dessus les appels")
  btnStepOut = bar.toolButton("Sortir", "Maj+F11 : terminer la procédure en cours")
  btnPause = bar.toolButton("Pause", "Interrompre à la prochaine instruction")
  btnStop = bar.toolButton("■ Arrêter", "Maj+F5")
  let spacer = bar.addChild(newLabel(""))
  spacer.weight = 1

  let sb = win.addChild(newSupercontrol(lkHorizontal))
  sb.dock = dkBottom
  let ls = sb.addChild(newLabel("Prêt"))
  ls.weight = 1
  lblStatus = ls.id
  let lp = sb.addChild(newLabel("Ln 1, Col 1"))
  lp.fixedWidth = 140
  lblPos = lp.id

  let split = win.addChild(newSplitter(vertical = true, position = 0.22))
  split.dock = dkCenter

  let left = split.addChild(newTab())
  tabLeft = left.id
  let pgProj = left.addPage("Projet", lkVertical)
  let tp = pgProj.addChild(newTreeView())
  tp.weight = 1
  trProj = tp.id
  let pgOut = left.addPage("Structure", lkVertical)
  let lo = pgOut.addChild(newListBox())
  lo.weight = 1
  lstOutline = lo.id
  let pgApi = left.addPage("Référence", lkVertical)
  let ta = pgApi.addChild(newTreeView())
  ta.weight = 1
  trApi = ta.id
  # fiche de l'élément sélectionné : Markdown mis en forme, ascenseur si nécessaire
  let ad = pgApi.addChild(newMarkdownView(ApiDocWelcome))
  ad.weight = 1
  edApiDoc = ad.id

  let right = split.addChild(newSplitter(vertical = false, position = 0.70))
  let ed = right.addChild(newLexisEditor())
  ed.weight = 1
  edId = ed.id

  let bottom = right.addChild(newTab())
  tabBottom = bottom.id
  let pgProb = bottom.addPage("Problèmes", lkVertical)
  let tb = pgProb.addChild(newTable(multiSelection = false))
  tb.weight = 1
  tblProb = tb.id
  tableAddColumn(tblProb, "Type", 110)
  tableAddColumn(tblProb, "Fichier", 140)
  tableAddColumn(tblProb, "Ligne", 60, alRight)
  tableAddColumn(tblProb, "Col", 50, alRight)
  tableAddColumn(tblProb, "Message", 700)

  let pgCon = bottom.addPage("Console", lkBorder)
  let conHead = pgCon.addChild(newSupercontrol(lkHorizontal))
  conHead.dock = dkTop
  btnCopy = conHead.toolButton("Copier", "Copier tout le contenu de la console")
  btnClear = conHead.toolButton("Effacer", "Vider la console")
  let conSpacer = conHead.addChild(newLabel(""))
  conSpacer.weight = 1
  let inRow = pgCon.addChild(newSupercontrol(lkHorizontal))
  inRow.dock = dkBottom
  let ei = inRow.addChild(newEdit(placeholder = "Saisie pour saisir() ou es.lire() (Entrée pour envoyer)"))
  ei.weight = 1
  edIn = ei.id
  btnSend = inRow.toolButton("Envoyer", "Envoie la ligne au programme")
  # zone de texte multiligne : défilement, sélection et Cmd/Ctrl+C natifs (comme wdnim)
  let eo = pgCon.addChild(newEdit("", multiline = true,
                                  placeholder = "Sortie du programme (?, es.ecrire, erreurs)"))
  eo.dock = dkCenter
  edOut = eo.id

  let pgVars = bottom.addPage("Variables", lkVertical)
  let tv = pgVars.addChild(newTable(multiSelection = false))
  tv.weight = 1
  tblVars = tv.id
  tableAddColumn(tblVars, "Nom", 160)
  tableAddColumn(tblVars, "Valeur", 520)
  tableAddColumn(tblVars, "Type", 90)
  tableAddColumn(tblVars, "Portée", 90)

  let pgStack = bottom.addPage("Pile d'appels", lkVertical)
  let lsk = pgStack.addChild(newListBox())
  lsk.weight = 1
  lstStack = lsk.id

  designerFileCreated = onDesignerFile
  designerCodeChanged = onDesignerCode
  reportFileCreated = onDesignerFile
  editorSetOptions(edId, s.minimap, s.dark)
  editorSetFontSize(edId, EditorBaseFont + float(s.fontDelta))
  fillApiTree()
  refreshRunButtons()
  if startDir.len > 0: openProject(startDir)
  if startFile.len > 0:
    try: discard editorOpen(edId, startFile, readFile(startFile))
    except IOError, OSError: discard

when isMainModule:
  useLexisIcon()
  buildUi()
  runApplication()
