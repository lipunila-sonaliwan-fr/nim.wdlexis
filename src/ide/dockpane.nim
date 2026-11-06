# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# Ensembles de pages affichés, masqués ou détachés dans une fenêtre dédiée
# (même comportement que le panneau Objets / Chercher / Favoris / Récents / Propriétés
# d'Atlas SQL) : un bouton à deux états masque / affiche, un second bouton détache
# l'ensemble dans sa propre fenêtre ou le rattache ; fermer la fenêtre le rattache.
import ../wdgui

type
  DockPane* = ref object
    title*: string
    host*: Container        # emplacement dans la fenêtre principale (masqué / affiché).
    content*: Control       # ensemble de pages déplacé entre l'emplacement et la fenêtre.
    win*: Window            # fenêtre dédiée (nil : rattaché).
    btnToggle*, btnDetach*: Button
    dispatch*: DispatchProc
    width*, height*: int    # taille de la fenêtre dédiée.
    hidden*: bool
    hideIcon*, showIcon*: string
    onChange*: proc (p: DockPane) {.nimcall, gcsafe.}   # après chaque changement (réglages).

proc refresh*(p: DockPane) =
  ## Symboles et infobulles des deux boutons selon l'état.
  if p.isNil: return
  guarded:
    let detached = p.win != nil
    if p.btnToggle != nil:
      p.btnToggle.icon = (if p.hidden and not detached: p.showIcon else: p.hideIcon)
      p.btnToggle.tooltip = (if detached: "Rattacher « " & p.title & " » à la fenêtre principale"
                             elif p.hidden: "Afficher « " & p.title & " » (>>)"
                             else: "Masquer « " & p.title & " » (<<)")
      markDirty(p.btnToggle)
    if p.btnDetach != nil:
      p.btnDetach.icon = (if detached: "rattacher" else: "fenetre")
      p.btnDetach.tooltip = (if detached: "Rattacher « " & p.title & " » à la fenêtre principale"
                             else: "Afficher « " & p.title & " » dans une fenêtre dédiée")
      markDirty(p.btnDetach)

proc changed(p: DockPane) =
  if p.isNil: return
  p.refresh()
  if p.onChange != nil: p.onChange(p)

proc newDockPane*(title: string, host: Container, content: Control, btnToggle, btnDetach: Button,
                  dispatch: DispatchProc, width = 420, height = 700,
                  hideIcon = "masquer", showIcon = "afficher"): DockPane =
  result = DockPane(title: title, host: host, content: content, btnToggle: btnToggle, btnDetach: btnDetach,
                    dispatch: dispatch, width: width, height: height, hideIcon: hideIcon, showIcon: showIcon)
  result.refresh()

proc isDetached*(p: DockPane): bool =
  if p.isNil: return
  guarded: result = p.win != nil

proc winId*(p: DockPane): ControlId =
  if p.isNil: return
  guarded: result = (if p.win != nil: p.win.id else: NoControl)

proc setHidden*(p: DockPane, hidden: bool) =
  if p.isNil: return
  guarded:
    p.hidden = hidden
    if p.win == nil:
      p.host.visible = not hidden
      markDirty(p.host)
  p.changed()

proc reattach*(p: DockPane) =
  ## Remet l'ensemble de pages dans la fenêtre principale (et ferme la fenêtre dédiée).
  if p.isNil: return
  var w: Window
  guarded:
    w = p.win
    if w == nil: return
    p.win = nil
    p.hidden = false
    discard p.host.addChild(p.content)
    p.host.visible = true
    markDirty(p.host)
  closeWindow(w.id)
  p.changed()

proc detach*(p: DockPane) =
  ## Ouvre l'ensemble de pages dans une fenêtre dédiée (l'emplacement est masqué).
  if p.isNil: return
  if p.isDetached:
    p.reattach()
    return
  var th: Theme
  var x, y: int
  guarded:
    let main = p.host.win
    th = main.theme
    x = 40
    y = 60
    if main.sdlWin != nil:
      x = int(p.host.rect.x) + 20
      y = int(p.host.rect.y) + 40
  let w = newWindow(p.title, p.width, p.height, p.dispatch, theme = th, layout = lkBorder)
  guarded:
    w.manualClose = true            # fermeture : rattachement (voir handleClose).
    w.root.margin = 0
    w.root.spacing = 0
    w.placed = true
    w.placeX = x
    w.placeY = y
    p.win = w
    p.content.dock = dkCenter
    discard w.root.addChild(p.content)
    p.host.visible = false
    markDirty(p.host)
  p.changed()

proc toggle*(p: DockPane) =
  ## Bouton à deux états : masque ou affiche l'ensemble (détaché : le rattache).
  if p.isNil: return
  if p.isDetached: p.reattach()
  else: p.setHidden(not p.hidden)

proc handleClose*(p: DockPane, id: ControlId): bool =
  ## Fermeture de la fenêtre dédiée : l'ensemble revient dans la fenêtre principale.
  if p.isNil or id == NoControl or id != p.winId: return false
  p.reattach()
  true

proc handleClick*(p: DockPane, id: ControlId): bool =
  if p.isNil: return false
  if p.btnToggle != nil and id == p.btnToggle.id:
    p.toggle()
    return true
  if p.btnDetach != nil and id == p.btnDetach.id:
    p.detach()
    return true
  false

proc iconTool*(bar: Container, icon, caption, tip: string): Button =
  ## Bouton plat à symbole ; le libellé (et l'explication) s'affichent en infobulle.
  result = newButton(caption)
  result.icon = icon
  result.flat = true
  result.tooltip = (if tip.len > 0: caption & " - " & tip else: caption)
  discard bar.addChild(result)

proc toolSeparator*(bar: Container) =
  ## Petit espace entre deux groupes de boutons.
  let s = newLabel("")
  s.fixedWidth = 8
  discard bar.addChild(s)

proc toolSpacer*(bar: Container) =
  let s = newLabel("")
  s.weight = 1
  discard bar.addChild(s)

proc isHidden*(p: DockPane): bool =
  ## Ensemble masqué (faux si l'ensemble n'existe pas).
  not p.isNil and p.hidden
