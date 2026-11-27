# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - atelier : outils de développement (inclus dans wdlexis.nim)
#
#   - service de langage : aller à la définition (F12), usages (Maj+F12), infobulles ;
#   - formateur (Ctrl+Maj+F) et conventions (.lexisformat) ;
#   - tests unitaires (Ctrl+T) : page Tests ;
#   - profileur (Exécuter › Profiler) : page Profil ;
#   - git : statut, comparaison, annotations, historique, fusion, conflits, validation.

var
  wsLock: Lock
  gWs: Workspace
  tblUsages, tblTests, lblTests, tblProf, tblProfLines, lblProf, edGit: ControlId
  usageRows: seq[RefLoc]
  testRows: seq[TestResult]
  profLineRows: seq[(string, int)]
  profFnRows: seq[(string, int)]
  testsRunning: Atomic[bool]
  selTests, selProf, selProfLines: Atomic[int]     # dernière ligne choisie (double-clic)
initLock(wsLock)

template withWs(body: untyped) =
  {.cast(gcsafe).}:
    withLock wsLock:
      body

const
  PageUsages = "5"
  PageTests = "6"
  PageProfil = "7"
  PageGit = "8"

proc showBottom(page: string) =
  if paneB.isHidden and not paneB.isDetached: paneB.setHidden(false)
  tabBottom.value = page

#
# Service de langage
#

proc resetWorkspace() =
  let w = newWorkspace(root())
  withWs: gWs = w

proc wsUpdate(path, text: string) =
  if path.len == 0: return
  withWs:
    if gWs.isNil: gWs = newWorkspace("")
    gWs.setText(path, text)

proc byteColOf(line: string, runeCol: int): int =
  var n = 0
  var i = 0
  while i < line.len and n < runeCol:
    let c = ord(line[i])
    i += (if c < 0x80: 1 elif c < 0xE0: 2 elif c < 0xF0: 3 else: 4)
    inc n
  min(i, line.len)

proc cursorPos(): (bool, int, string, int, int) =
  # (ok, uid, source, ligne, colonne en octets) ; le service reçoit le texte courant.
  let uid = activeUid()
  if uid < 0: return (false, -1, "", 0, 0)
  let path = editorSourceName(edId, uid)
  let text = editorText(edId, uid)
  wsUpdate(path, text)
  let (l, rc) = editorCursor(edId)
  let lines = text.split('\n')
  let lt = if l < lines.len: lines[l] else: ""
  (true, uid, path, l, byteColOf(lt, rc))

proc gotoLoc(r: RefLoc) =
  let uid = editorUidOf(edId, r.file)
  if uid >= 0:
    editorActivate(edId, uid)
    editorGoto(edId, uid, r.line, 0)
    editorFlush(edId)
  else: gotoFile(r.file, r.line, 0)

proc gotoDefinitionAtCursor(word: string) =
  let (ok, _, path, line, col) = cursorPos()
  if ok:
    var defs: seq[RefLoc]
    withWs: defs = gWs.definition(path, line, col)
    if defs.len > 0:
      gotoLoc(defs[0])
      status("Définition : " & relPath(defs[0].file) & " ligne " & $(defs[0].line + 1) &
             (if defs.len > 1: " (" & $defs.len & " définitions)" else: ""))
      return
  gotoDefinition(word)              # repli : index des procédures, documentation des paquets

proc lineText(path: string, line: int): string =
  let uid = editorUidOf(edId, path)
  let text = if uid >= 0: editorText(edId, uid)
             else: (try: readFile(path) except IOError, OSError: "")
  let ls = text.split('\n')
  if line < ls.len: ls[line].strip else: ""

proc listUsages() =
  let (ok, _, path, line, col) = cursorPos()
  if not ok: return
  var refs: seq[RefLoc]
  var name = ""
  withWs:
    refs = gWs.references(path, line, col, true)
  if refs.len == 0:
    status("Aucun symbole du projet sous le curseur")
    return
  name = lineText(refs[0].file, refs[0].line)
  tableDeleteAll(tblUsages)
  for r in refs:
    discard tableAddLine(tblUsages, relPath(r.file), $(r.line + 1), $(r.col + 1),
                         (if r.decl: "déclaration" else: $r.kind), lineText(r.file, r.line))
  {.cast(gcsafe).}: usageRows = refs
  showBottom(PageUsages)
  var files = initHashSet[string]()
  for r in refs: files.incl r.file
  status($refs.len & " usage(s) dans " & $files.len & " fichier(s) - double-clic pour y aller")

proc hoverProvider(source, text: string, line, col: int): string {.gcsafe.} =
  # Appelé par l'éditeur (fil de l'interface, sous son verrou) : n'utilise que le service.
  var h: HoverInfo
  withWs:
    if gWs.isNil: gWs = newWorkspace("")
    try:
      gWs.setText(source, text)
      h = gWs.hover(source, line, col)
    except CatchableError: discard
  if h.found: plainHover(h.markdown) else: ""

#
# Formateur
#

proc formatDocument() =
  let uid = activeUid()
  if uid < 0: return
  let path = editorSourceName(edId, uid)
  let dir = if root().len > 0: root() else: path.parentDir
  let r = formatText(editorText(edId, uid), loadFormatOptions(dir))
  if not r.safe:
    status(r.message)
    return
  if not r.changed:
    status("Déjà formaté (conventions : " & (if findFormatFile(dir).len > 0: relPath(findFormatFile(dir)) else: "par défaut") & ")")
    return
  let (l, c) = editorCursor(edId)
  discard editorSetText(edId, uid, r.text)
  editorGoto(edId, uid, l, c)
  editorFlush(edId)
  status("Document formaté (Ctrl+Z pour annuler)")

proc editFormatConventions() =
  let r = root()
  if r.len == 0:
    status("Ouvrez d'abord un projet : les conventions sont dans son fichier .lexisformat")
    return
  let f = r / FormatFile
  if not fileExists(f):
    try: writeFile(f, formatOptionsText(defaultFormat()))
    except IOError, OSError:
      alert(iconStop, "Création impossible :\n" & f)
      return
  discard openFile(f)
  status("Conventions de formatage du projet : " & FormatFile & " (une option par ligne)")

#
# Tests unitaires
#

proc runTests(onlyCurrent: bool) =
  if testsRunning.exchange(true):
    status("Les tests sont déjà en cours.")
    return
  try:
    discard saveAll()
    var target = root()
    if onlyCurrent:
      let uid = activeUid()
      if uid >= 0: target = editorSourceName(edId, uid)
    if target.len == 0:
      status("Ouvrez d'abord un projet (ou un fichier de test).")
      return
    let (r, files) = discoverTests(target)
    tableDeleteAll(tblTests)
    showBottom(PageTests)
    if files.len == 0:
      lblTests.caption = "Aucun fichier de test : test_*.prg, *_test.prg ou dossier tests/ " &
                         "(procédures TEST_… et assertions du paquet test)"
      return
    lblTests.caption = "Tests en cours… (" & $files.len & " fichier(s))"
    var all: seq[TestResult]
    for f in files:
      let rs = runTestFile(f, r, "", proc (s: string) =
        {.cast(gcsafe).}: consoleAppend(s))
      for t in rs:
        let at = if t.errLine > 0:
                   (if t.errSource.len > 0 and t.errSource != t.file: extractFilename(t.errSource) & ":" else: "ligne ") &
                   $t.errLine & " : "
                 else: ""
        discard tableAddLine(tblTests, (case t.status
                                        of tsPass: "✓ réussi"
                                        of tsFail: "✗ échec"
                                        of tsError: "! erreur"
                                        of tsSkip: "- ignoré"),
                             t.name.toLowerAscii, relPath(t.file), formatFloat(t.ms, ffDecimal, 2),
                             $t.assertions, at & t.message)
      all.add rs
    {.cast(gcsafe).}: testRows = all
    let (p, f, e, s) = summary(all)
    lblTests.caption = $all.len & " test(s) : " & $p & " réussi(s), " & $f & " échec(s), " & $e &
                       " erreur(s), " & $s & " ignoré(s) - double-clic : aller au test ou à l'échec"
    status(if f + e == 0: "Tests réussis (" & $p & ")" else: "Tests : " & $(f + e) & " en échec")
  finally:
    testsRunning.store(false)

proc gotoTest(i: int) =
  var t: TestResult
  var ok = false
  {.cast(gcsafe).}:
    if i >= 0 and i < testRows.len:
      t = testRows[i]
      ok = true
  if not ok: return
  if t.status in {tsFail, tsError} and t.errLine > 0:
    gotoFile((if t.errSource.len > 0: t.errSource else: t.file), t.errLine - 1, 0)
  elif t.line > 0: gotoFile(t.file, t.line - 1, 0)

#
# Profileur
#

proc showProfile(p: Profiler) =
  tableDeleteAll(tblProf)
  tableDeleteAll(tblProfLines)
  let d = max(p.duration, 1e-9)
  var fnRows: seq[(string, int)]
  for f in p.functionsByTime:
    discard tableAddLine(tblProf, f.name.toLowerAscii, $f.calls, formatFloat(f.total * 1000, ffDecimal, 3),
                         formatFloat(f.self * 1000, ffDecimal, 3), formatFloat(100 * f.self / d, ffDecimal, 1),
                         $f.tables, relPath(f.source) & ":" & $f.line)
    fnRows.add (f.source, f.line)
  var rows: seq[(string, int)]
  for l in p.linesByTime(200):
    discard tableAddLine(tblProfLines, formatFloat(l.time * 1000, ffDecimal, 3), $l.hits,
                         relPath(l.source) & ":" & $l.line, lineText(l.source, l.line - 1))
    rows.add (l.source, l.line)
  {.cast(gcsafe).}:
    profLineRows = rows
    profFnRows = fnRows
  lblProf.caption = "Durée " & formatFloat(p.duration * 1000, ffDecimal, 1) & " ms - mémoire résidente : départ " &
                    $p.rss0 & " Ko, fin " & $p.rss1 & " Ko, pic " & $p.rssPeak & " Ko - tables créées : " &
                    $(p.tables1 - p.tables0) & " - double-clic : aller au code"
  showBottom(PageProfil)

proc gotoProfileRow(fromLines: bool, i: int) =
  var r: (string, int)
  var ok = false
  {.cast(gcsafe).}:
    let rows = if fromLines: profLineRows else: profFnRows
    if i >= 0 and i < rows.len:
      r = rows[i]
      ok = true
  if ok and r[1] > 0: gotoFile(r[0], r[1] - 1, 0)

#
# Git
#

proc gitRun(args: seq[string], dir = ""): (int, string) =
  let d = if dir.len > 0: dir else: root()
  if d.len == 0: return (-1, "aucun projet ouvert")
  try:
    let (o, code) = execCmdEx(quoteShellCommand(@["git"] & args), workingDir = d)
    (code, o)
  except OSError as e:
    (-1, "git introuvable : " & e.msg)

proc gitShow(title, text: string) =
  edGit.value = title & "\n" & repeat("─", 60) & "\n" & text
  showBottom(PageGit)

proc gitReady(): bool =
  let (code, o) = gitRun(@["rev-parse", "--show-toplevel"])
  if code != 0:
    gitShow("Git", "Le projet n'est pas un dépôt git (ou git est absent) :\n" & o &
            "\nInitialiser : git init dans le dossier du projet.")
    return false
  true

proc showReadOnlyDoc(title, text: string) =
  # Document en lecture seule (comparaison, annotations, historique) ; remplacé s'il existe.
  var uid = -1
  for d in editorDocs(edId):
    if editorInfo(edId, d.uid).title == title: uid = d.uid
  if uid < 0: uid = editorNew(edId, title)
  editorSetReadOnly(edId, uid, false)
  discard editorSetText(edId, uid, text, modified = false)
  editorSetLanguage(edId, uid, "texte")
  editorSetReadOnly(edId, uid, true)
  editorActivate(edId, uid)
  editorFlush(edId)

proc currentFile(): string =
  let uid = activeUid()
  if uid < 0: return ""
  let p = editorInfo(edId, uid).path
  p

proc gitStatus() =
  if not gitReady(): return
  let (_, br) = gitRun(@["status", "--short", "--branch"])
  let (_, lg) = gitRun(@["log", "--oneline", "-n", "10", "--decorate"])
  gitShow("Statut du dépôt", br & "\nDernières validations :\n" & lg)

proc gitDiff(all: bool) =
  if not gitReady(): return
  discard saveAll()
  if all:
    let (_, o) = gitRun(@["diff", "HEAD", "--stat", "--patch", "--no-color"])
    showReadOnlyDoc("projet (diff HEAD)", (if o.strip.len == 0: "Aucune différence avec la dernière validation." else: o))
  else:
    let f = currentFile()
    if f.len == 0:
      status("Ouvrez un fichier enregistré du projet.")
      return
    let (_, o) = gitRun(@["diff", "HEAD", "--no-color", "--", f])
    showReadOnlyDoc(extractFilename(f) & " (diff HEAD)",
                    (if o.strip.len == 0: "Aucune différence avec la dernière validation." else: o))

proc gitBlame() =
  if not gitReady(): return
  let f = currentFile()
  if f.len == 0:
    status("Ouvrez un fichier enregistré du projet.")
    return
  let (code, o) = gitRun(@["blame", "--date=short", "-w", "--", f])
  showReadOnlyDoc(extractFilename(f) & " (annotations)",
                  (if code != 0: "Annotations indisponibles (fichier non validé ?) :\n" & o else: o))

proc gitHistory() =
  if not gitReady(): return
  let f = currentFile()
  if f.len == 0:
    status("Ouvrez un fichier enregistré du projet.")
    return
  let (_, o) = gitRun(@["log", "--follow", "--date=short", "--pretty=format:%h  %ad  %an  %s", "--", f])
  gitShow("Historique de " & extractFilename(f), (if o.strip.len == 0: "(aucune validation)" else: o))

proc reloadOpenDocs() =
  # Après une fusion ou un abandon : les documents non modifiés reprennent le disque.
  for d in editorDocs(edId):
    let info = editorInfo(edId, d.uid)
    if info.path.len > 0 and fileExists(info.path) and not info.dirty:
      try: discard editorSetText(edId, d.uid, readFile(info.path), modified = false)
      except IOError, OSError: discard
  reindex()
  resetWorkspace()
  lintAllOpen()

proc gitConflicts(): seq[string] =
  let (_, o) = gitRun(@["diff", "--name-only", "--diff-filter=U"])
  for l in o.splitLines():
    if l.strip.len > 0: result.add l.strip

proc gitMerge() =
  if not gitReady(): return
  var dirty = false
  for d in editorDocs(edId):
    if d.dirty: dirty = true
  if dirty:
    if confirm(iconQuestion, "Enregistrer les fichiers modifiés avant la fusion ?") != drOk: return
    discard saveAll()
  let (_, cur) = gitRun(@["branch", "--show-current"])
  let (_, brs) = gitRun(@["branch", "--format=%(refname:short)"])
  var b = ""
  if not promptOk(iconQuestion, "Branche à fusionner dans « " & cur.strip & " » :\n(" &
                  brs.splitLines().filterIt(it.strip.len > 0 and it.strip != cur.strip).join(", ") & ")", b): return
  b = b.strip
  if b.len == 0: return
  let (code, o) = gitRun(@["merge", "--no-ff", "--no-edit", b])
  let conflicts = gitConflicts()
  reloadOpenDocs()
  if conflicts.len > 0:
    gitShow("Fusion de " & b & " : conflits", o & "\nFichiers en conflit :\n  " & conflicts.join("\n  ") &
            "\n\nOuvrez chaque fichier et choisissez Git › Conflits : garder la version locale / " &
            "la version fusionnée / les deux, puis Git › Valider.")
    let r = root()
    discard openFile(r / conflicts[0])
  else:
    gitShow("Fusion de " & b, (if code == 0: o else: "Échec de la fusion :\n" & o))

proc gitAbortMerge() =
  if not gitReady(): return
  let (code, o) = gitRun(@["merge", "--abort"])
  reloadOpenDocs()
  gitShow("Abandon de la fusion", (if code == 0: "Fusion abandonnée : fichiers revenus à l'état d'avant.\n" else: "") & o)

proc resolveConflicts(keep: string) =
  # keep : "local" (HEAD), "fusion" (branche fusionnée) ou "deux".
  let uid = activeUid()
  if uid < 0: return
  let lines = editorText(edId, uid).split('\n')
  var o: seq[string]
  var mode = 0                      # 0 hors conflit, 1 partie locale, 2 partie fusionnée
  var n = 0
  for l in lines:
    if l.startsWith("<<<<<<<"):
      mode = 1
      inc n
    elif l.startsWith("=======") and mode == 1: mode = 2
    elif l.startsWith("|||||||") and mode == 1: mode = 3          # base (diff3) : ignorée
    elif l.startsWith("=======") and mode == 3: mode = 2
    elif l.startsWith(">>>>>>>") and mode == 2: mode = 0
    elif mode == 0: o.add l
    elif mode == 1 and keep in ["local", "deux"]: o.add l
    elif mode == 2 and keep in ["fusion", "deux"]: o.add l
  if n == 0:
    status("Aucun conflit (<<<<<<< … >>>>>>>) dans ce document")
    return
  discard editorSetText(edId, uid, o.join("\n"))
  editorFlush(edId)
  status($n & " conflit(s) résolu(s) - enregistrez, puis Git › Valider")

proc gitCommit() =
  if not gitReady(): return
  discard saveAll()
  var msg = ""
  if not promptOk(iconQuestion, "Message de validation (tous les fichiers modifiés du projet) :", msg): return
  if msg.strip.len == 0: return
  let (_, a) = gitRun(@["add", "-A"])
  let (code, o) = gitRun(@["commit", "-m", msg.strip])
  gitShow("Validation", a & o & (if code == 0: "" else: "\n(échec de la validation)"))
