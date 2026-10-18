# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - boîte « Générer l'application » (menu Exécuter)
#
#   Onglet « Projet » : type d'application, icône (avec cadrage), cibles,
#   distribution. Onglet « Détails » (grisé jusqu'à la compilation) : commandes
#   lancées et leurs retours, en couleurs, dans une zone de type shell.
#   Boutons : [Annuler] [Sauver] [Compiler].
#
#   generationDialog(dossier_du_projet, fichier_principal, thème)
#     bloque le fil appelant (gestionnaire d'événements de l'atelier) jusqu'à la
#     fermeture de la boîte, comme les boîtes de dialogue de wdgui.

import std/[os, strutils, atomics, monotimes, times, typedthreads, options, math, locks]
import ../wdgui
import toolchain, imagetools, shellview, cropview

type
  GenState = ref object
    winId: ControlId
    info: ProjectInfo
    s: BuildSettings
    appDir: string
    hasImage: bool
    imgW, imgH: int
    tab, pgProjet, pgDetails, body, rbType, iconRow, crop, btnChoose, btnRemove, lblIcon,
      rbDist, cbLibs, lblInfo, progRow, lblStep, prog, lblTime, btnDetails, shell,
      btnCancel, btnSave, btnCompile, lblStatus: ControlId
    cbTargets: array[Target, ControlId]
    building, started, cancelReq, closing: Atomic[bool]
    lastBlank: bool
    t0: MonoTime
    thr: Thread[GenState]
    timer: Thread[GenState]

var
  gGen: GenState             # boîte de génération ouverte (une seule à la fois).
  gGenOpen: Atomic[bool]     # réservée dès l'appel : un second appel (double clic sur
                             # le menu pendant l'analyse du projet) est ignoré.
  gGenLock: Lock             # les événements de la boîte (un fil chacun) sont traités
                             # l'un après l'autre : l'état n'est jamais modifié par deux fils.
initLock(gGenLock)

const
  TypeOrder = [atConsole, atGraphique, atService, atBibliotheque]
  TargetGrid = [tgLinuxX64, tgMacX64, tgWinX64, tgLinuxArm64, tgMacArm64, tgWinArm64]
  ImageFilter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tga\nTous les fichiers|*"
  LabelOk = Color(r: 0x2E, g: 0xAA, b: 0x4F, a: 255)    # lisibles en thème clair comme sombre
  LabelErr = Color(r: 0xE0, g: 0x48, b: 0x48, a: 255)

proc gen(): GenState =
  {.cast(gcsafe).}: result = gGen

proc resetColor(id: ControlId) =
  withControl(id, Control, c): c.style.text = none(Color)

#
# Lecture / mise à jour des options
#

proc readOptions(g: GenState) =
  let ti = (try: parseInt(g.rbType.value) - 1 except ValueError: 0)
  if ti >= 0 and ti < TypeOrder.len: g.s.appType = TypeOrder[ti]
  if g.info.usesUi: g.s.appType = atGraphique
  g.s.targets = {}
  for t in Target:
    if g.cbTargets[t].value == "1": g.s.targets.incl t
  g.s.dist = (if g.rbDist.value == "2": dmArchive else: dmFolder)
  g.s.bundleLibs = g.cbLibs.value == "1"
  if g.hasImage: g.s.crop = cropValue(g.crop)

proc refreshIconState(g: GenState) =
  ## L'icône n'a de sens que pour une application graphique.
  let on = g.s.appType == atGraphique and not g.started.load()
  g.iconRow.state = (if on: csActive else: csGrayed)
  g.btnRemove.state = (if on and g.hasImage: csActive else: csGrayed)
  if g.hasImage:
    g.lblIcon.caption = extractFilename(g.s.iconPath) & "\n" & $g.imgW & " x " & $g.imgH & " px\n" &
      "Glissez le cadre pour choisir la partie\nretenue ; molette ou coin : taille."
  else:
    g.lblIcon.caption = (if g.s.appType == atGraphique: "Aucune icône : celle du système\nsera utilisée."
                         else: "Icône : applications graphiques\nuniquement.")

proc loadIcon(g: GenState, path: string, crop: Crop, keepCrop: bool): bool =
  try:
    let img = loadImage(path)
    let c = (if keepCrop: crop.normalized(img.w, img.h) else: centeredCrop(img.w, img.h))
    cropSetImage(g.crop, img, c)
    g.hasImage = true
    g.imgW = img.w
    g.imgH = img.h
    g.s.iconPath = path
    g.s.crop = c
    result = true
  except CatchableError as e:
    g.lblStatus.caption = "Image illisible : " & e.msg
    g.lblStatus.color = LabelErr

#
# Journal (onglet Détails)
#

proc blank(g: GenState) =
  if not g.lastBlank:
    shellAppend(g.shell, "")
    g.lastBlank = true

proc logLine(g: GenState, kind: LogKind, text: string) =
  case kind
  of lgStep:
    g.blank()
    shellAppend(g.shell, text, ShellStep)
    shellAppend(g.shell, "")
    g.lastBlank = true
  of lgDone:
    g.blank()
    shellAppend(g.shell, text, ShellOk)
    shellAppend(g.shell, "")
    g.lastBlank = true
  of lgFinal:
    g.blank()
    shellAppend(g.shell, text, ShellOk)
    g.lastBlank = false
  of lgCommand:
    shellAppend(g.shell, "$ " & text, ShellCmd)
    g.lastBlank = false
  of lgWarning:
    shellAppend(g.shell, text, ShellWarn)
    g.lastBlank = false
  of lgError:
    shellAppend(g.shell, text, ShellErr)
    g.lastBlank = false
  of lgOutput:
    shellAppend(g.shell, text, ShellFg)
    g.lastBlank = false

#
# Compilation (fil dédié)
#

proc timerLoop(g: GenState) {.thread.} =
  {.cast(gcsafe).}:
    while g.building.load():
      g.lblTime.caption = "⏱ " & fmtClock(getMonoTime() - g.t0)
      sleep(250)
    g.lblTime.caption = "⏱ " & fmtClock(getMonoTime() - g.t0)

proc buildLoop(g: GenState) {.thread.} =
  {.cast(gcsafe).}:
    var hooks: BuildHooks
    var lastLabel = ""
    hooks.log = proc (kind: LogKind, text: string) =
      {.cast(gcsafe).}:
        g.logLine(kind, text)
        if kind == lgFinal:
          g.lblStep.caption = text
          g.lblStep.color = LabelOk
        elif kind == lgError and (text.startsWith("Génération interrompue") or
                                  text.startsWith("Génération arrêtée")):
          g.lblStep.caption = text
          g.lblStep.color = LabelErr
    hooks.progress = proc (f: float, label: string) =
      {.cast(gcsafe).}:
        g.prog.valueNum = round(f * 1000) / 10
        if label != lastLabel:
          lastLabel = label
          g.lblStep.caption = label
    hooks.cancelled = proc (): bool =
      {.cast(gcsafe).}: result = g.cancelReq.load()
    var ok = false
    try:
      ok = build(g.info, g.s, g.appDir, hooks)
    except CatchableError as e:
      g.logLine(lgError, "erreur : " & e.msg)
    if ok: g.prog.valueNum = 100
    g.building.store(false)

proc startBuild(g: GenState) =
  if g.started.exchange(true): return
  g.readOptions()
  g.body.state = csGrayed                       # Projet : options grisées, onglet accessible.
  g.btnSave.state = csGrayed
  g.btnCompile.state = csGrayed
  g.pgDetails.state = csActive
  g.progRow.visible = true
  g.btnDetails.state = csActive
  g.lblStatus.caption = ""
  g.tab.value = "2"                             # bascule sur Détails.
  g.lblStep.caption = "Préparation…"
  resetColor(g.lblStep)
  g.prog.valueNum = 0
  g.t0 = getMonoTime()
  g.building.store(true)
  createThread(g.timer, timerLoop, g)
  createThread(g.thr, buildLoop, g)

proc closeDialog(g: GenState) =
  ## Annuler / fermeture : interrompt la compilation en cours puis ferme la boîte.
  if g.closing.exchange(true): return
  withLock gGenLock: discard                    # laisse finir un événement en cours (Compiler...).
  if g.building.load():
    g.cancelReq.store(true)
    g.lblStep.caption = "Interruption…"
    var waited = 0
    while g.building.load() and waited < 15_000:
      sleep(25)
      waited += 25
  if g.started.load():
    joinThread(g.thr)
    joinThread(g.timer)
  closeWindow(g.winId)

#
# Événements
#

proc genDispatch(ev: var Event) {.nimcall, gcsafe.} =
  if ev.current != ev.id: return
  let g = gen()
  if g == nil or ev.window != g.winId: return
  {.cast(gcsafe).}:
    # Fermeture : hors verrou (elle attend la fin de la compilation).
    if ev.kind == evWindowClose or (ev.kind == evClick and ev.id == g.btnCancel):
      g.closeDialog()
      return
    if g.closing.load(): return
    # Choix de l'image : la boîte de fichiers est modale, on ne garde pas le verrou.
    if ev.kind == evClick and ev.id == g.btnChoose:
      var start = ""
      withLock gGenLock:
        start = (if g.s.iconPath.len > 0: g.s.iconPath.parentDir else: g.info.root)
      let f = openFileDialog(title = "Image de l'icône", folder = start, filter = ImageFilter)
      withLock gGenLock:
        if f.len > 0 and not g.started.load() and g.loadIcon(f, fullCrop(), keepCrop = false):
          g.lblStatus.caption = ""
        g.refreshIconState()
      return
    acquire(gGenLock)
    defer: release(gGenLock)
    case ev.kind
    of evClick:
      if ev.id == g.btnCompile: g.startBuild()
      elif ev.id == g.btnDetails:
        g.tab.value = (if g.tab.value == "2": "1" else: "2")
      elif ev.id == g.btnSave and not g.started.load():
        g.readOptions()
        try:
          saveSettings(g.info, g.s)
          g.lblStatus.caption = "Paramètres enregistrés (" & SettingsRel.replace('\\', '/') & ")"
          g.lblStatus.color = LabelOk
        except CatchableError as e:
          g.lblStatus.caption = "Enregistrement impossible : " & e.msg
          g.lblStatus.color = LabelErr
      elif ev.id == g.btnRemove and not g.started.load():
        cropClear(g.crop)
        g.hasImage = false
        g.s.iconPath = ""
        g.s.crop = fullCrop()
        g.refreshIconState()
    of evChange:
      if ev.id == g.rbType and not g.started.load():
        g.readOptions()
        g.refreshIconState()
      elif ev.id == g.crop and not g.started.load():
        g.s.crop = cropValue(g.crop)
    else: discard

#
# Construction de la boîte
#

proc sectionTitle(parent: Container, text: string) =
  discard parent.addChild(newLabel(text))


proc generationDialog*(root, mainRel: string, theme: Theme, appDir = getAppDir()) =
  ## Ouvre la boîte (modale) et attend sa fermeture.
  if gGenOpen.exchange(true): return
  defer: gGenOpen.store(false)
  let info = analyzeProject(root, mainRel)
  let g = GenState(info: info, appDir: appDir)
  g.s = loadSettings(info)
  {.cast(gcsafe).}: gGen = g
  var owner: Window
  guarded:
    owner = activeWindow
    let win = newWindow("Générer l'application — " & info.name, 780, 700, genDispatch, theme, lkBorder)
    win.resizable = true
    win.isModal = true
    win.modalFor = owner
    win.alwaysThreaded = true
    win.manualClose = true                    # la croix = Annuler (interrompt la compilation).
    g.winId = win.id

    # pied : progression puis boutons
    let foot = win.addChild(newSupercontrol(lkVertical))
    foot.dock = dkBottom
    let pr = foot.addChild(newSupercontrol(lkVertical))
    g.progRow = pr.id
    let ls = pr.addChild(newLabel("Prêt"))
    g.lblStep = ls.id
    let pline = pr.addChild(newSupercontrol(lkHorizontal))
    let pb = pline.addChild(newProgressBar(0, 0, 100))
    pb.weight = 1
    g.prog = pb.id
    let lt = pline.addChild(newLabel("⏱ 00:00", alRight))
    lt.fixedWidth = 90
    g.lblTime = lt.id
    let bd = pline.addChild(newButton("Détails"))
    bd.tooltip = "Commandes lancées et leurs retours"
    g.btnDetails = bd.id
    pr.visible = false
    let brow = foot.addChild(newSupercontrol(lkHorizontal))
    let st = brow.addChild(newLabel(""))
    st.weight = 1
    g.lblStatus = st.id
    let bc = brow.addChild(newButton("Annuler", isCancel = true))
    g.btnCancel = bc.id
    let bs = brow.addChild(newButton("Sauver"))
    bs.tooltip = "Enregistre ces paramètres dans le projet"
    g.btnSave = bs.id
    let bk = brow.addChild(newButton("Compiler", isDefault = true))
    bk.tooltip = "Transpile le projet en C et compile chaque cible avec Zig"
    g.btnCompile = bk.id

    # onglets
    let tab = win.addChild(newTab())
    tab.dock = dkCenter
    g.tab = tab.id
    let pgP = tab.addPage("Projet", lkVertical)
    g.pgProjet = pgP.id
    let pgD = tab.addPage("Détails", lkVertical)
    g.pgDetails = pgD.id
    pgD.state = csGrayed                         # accessible une fois la compilation lancée.
    let sh = pgD.addChild(newShellView())
    sh.weight = 1
    g.shell = sh.id

    let body = pgP.addChild(newContainer(lkVertical, 4, 6))
    body.weight = 1
    g.body = body.id

    body.sectionTitle("Type d'application :")
    let rt = body.addChild(newRadioButton(["Console", "Graphique", "Service", "Bibliothèque"],
                                          TypeOrder.find(g.s.appType), horizontal = true))
    if info.usesUi:
      rt.selection = 1
      rt.disabled = @[true, false, true, true]
      rt.tooltip = "Le projet utilise le paquet « interface » : application graphique"
    g.rbType = rt.id

    body.sectionTitle("Icône de l'application :")
    let ir = body.addChild(newSupercontrol(lkHorizontal, 12))
    g.iconRow = ir.id
    let cv = ir.addChild(newCropView())
    cv.fixedWidth = 230
    cv.fixedHeight = 150
    g.crop = cv.id
    let icol = ir.addChild(newSupercontrol(lkVertical))
    icol.weight = 1
    let bch = icol.addChild(newButton("Choisir une image…"))
    bch.stretch = false
    g.btnChoose = bch.id
    let brm = icol.addChild(newButton("Retirer l'icône"))
    brm.stretch = false
    g.btnRemove = brm.id
    let li = icol.addChild(newLabel(""))
    g.lblIcon = li.id

    body.sectionTitle("Générer un exécutable pour :")
    let grid = body.addChild(newContainer(lkGrid, 0, 4, 3))
    for t in TargetGrid:
      let cb = grid.addChild(newCheckBox(t.label, t in g.s.targets))
      g.cbTargets[t] = cb.id

    body.sectionTitle("Distribution :")
    let rd = body.addChild(newRadioButton(["Fichiers dans un dossier",
                                           "Archive (zip ou tgz selon l'environnement) dans un dossier"],
                                          (if g.s.dist == dmArchive: 1 else: 0)))
    g.rbDist = rd.id
    let cl = body.addChild(newCheckBox("Intégrer les bibliothèques requises", g.s.bundleLibs))
    cl.tooltip = "Dossier linOS, macOS ou winOS (selon la cible), bibliothèques à côté de wdlexis+ et dossier ttf"
    g.cbLibs = cl.id

    var extra = "Paquets utilisés : " & (if info.packages.len > 0: info.packages.join(", ") else: "aucun")
    if info.usesIa: extra.add "   (IA : models/models.txt sera ajouté)"
    extra.add "\nDestination : " & (info.root / OutputDirName)
    let lin = body.addChild(newLabel(extra))
    lin.style.text = some(Color(r: 0x8A, g: 0x8F, b: 0x98, a: 255))
    g.lblInfo = lin.id

  # icône enregistrée.
  if g.s.iconPath.len > 0 and fileExists(g.s.iconPath):
    discard g.loadIcon(g.s.iconPath, g.s.crop, keepCrop = true)
  g.refreshIconState()
  if not dirExists(root):
    g.lblStatus.caption = "Ouvrez d'abord un projet."
    g.btnCompile.state = csGrayed
    g.btnSave.state = csGrayed
  elif info.prgFiles.len == 0:
    g.lblStatus.caption = "Le projet ne contient aucun fichier .prg."
    g.btnCompile.state = csGrayed
  wakeUI()
  # attente de la fermeture (comme les boîtes de wdgui).
  while true:
    var done = false
    guarded:
      let c = control(g.winId)
      done = c == nil or (c of Window and (Window(c).closed or Window(c).closeRequested))
    if done: break
    sleep(30)
  {.cast(gcsafe).}: gGen = nil
