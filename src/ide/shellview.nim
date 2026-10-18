# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - zone de texte de type « shell » (journal coloré de la génération)
#
#   fond sombre, une couleur par ligne, retour à la ligne automatique, ascenseur
#   vertical (molette, glisser la barre), suivi de la fin tant que l'on n'a pas
#   remonté ; Ctrl/Cmd+C ou clic droit : copie de tout le journal.
#
#   shellAppend(id, texte, couleur)    ajout (depuis n'importe quel fil)
#   shellClear(id), shellText(id)

import std/[strutils, unicode]
import ../wdgui
import ../sdl3

type
  ShellLine = object
    text: string
    color: Color
  WrapLine = object
    text: string
    color: Color

  ShellView* = ref object of Control
    lines: seq[ShellLine]
    wrapped: seq[WrapLine]
    wrappedCount: int            # nombre de lignes déjà découpées.
    wrapWidth: float
    scroll: float                # en pixels depuis le haut.
    follow: bool                 # suit la fin du journal.
    dragging: bool
    lineH: float

const
  ShellBg* = hex"#1B1D23"
  ShellFg* = hex"#E8E8E8"        # messages (blanc).
  ShellStep* = hex"#F2D43D"      # étapes (jaune).
  ShellWarn* = hex"#FF9F43"      # avertissements (orange).
  ShellErr* = hex"#FF5C5C"       # erreurs (rouge).
  ShellOk* = hex"#4CD964"        # étapes terminées (vert).
  ShellCmd* = hex"#9AB8D8"       # commandes lancées.
  ShellPad = 10.0

proc newShellView*(): ShellView =
  result = ShellView(follow: true)
  initControl(result)
  result.focusable = true

method typeName*(c: ShellView): string = "Shell"

method preferredSize*(c: ShellView, d: Drawing, t: Theme): tuple[w, h: float] = (400.0, 200.0)

proc wrapOne(d: Drawing, s: string, width: float): seq[string] =
  # Coupe une ligne logique en lignes affichables (mots, sinon caractères).
  if s.len == 0: return @[""]
  if d.textWidth(s) <= width: return @[s]
  var cur = ""
  var i = 0
  let runes = s.toRunes
  var lastSpace = -1
  var start = 0
  while i < runes.len:
    let cand = $runes[start .. i]
    if d.textWidth(cand) > width and i > start:
      var cut = i
      if lastSpace > start: cut = lastSpace + 1
      result.add $runes[start ..< cut]
      start = cut
      lastSpace = -1
      i = start
      continue
    if runes[i] == Rune(' '): lastSpace = i
    inc i
  cur = $runes[start .. ^1]
  if cur.len > 0 or result.len == 0: result.add cur

proc rewrap(c: ShellView, d: Drawing, width: float) =
  if abs(width - c.wrapWidth) > 0.5:
    c.wrapWidth = width
    c.wrapped.setLen(0)
    c.wrappedCount = 0
  while c.wrappedCount < c.lines.len:
    let l = c.lines[c.wrappedCount]
    for part in wrapOne(d, l.text, width): c.wrapped.add WrapLine(text: part, color: l.color)
    inc c.wrappedCount

proc textArea(c: ShellView): Rect = c.rect.shrink(ShellPad)

method draw*(c: ShellView, d: Drawing, t: Theme) =
  let r = c.rect
  d.fillRoundRect(r, 6, ShellBg)
  let area = c.textArea
  c.lineH = max(14.0, d.textHeight + 2)
  c.rewrap(d, max(40.0, area.w - 10))
  let total = float(c.wrapped.len) * c.lineH
  let maxScroll = max(0.0, total - area.h)
  if c.follow: c.scroll = maxScroll
  c.scroll = clamp(c.scroll, 0.0, maxScroll)
  d.pushClip(area)
  let first = max(0, int(c.scroll / c.lineH))
  var y = area.y - (c.scroll - float(first) * c.lineH)
  var i = first
  let grayed = c.isGrayed
  while i < c.wrapped.len and y < area.y + area.h:
    let w = c.wrapped[i]
    let col = if grayed: mix(w.color, ShellBg, 0.5) else: w.color
    d.text(area.x, y + (c.lineH - d.textHeight) / 2, w.text, col)
    y += c.lineH
    inc i
  d.popClip()
  drawScrollIndicator(d, t, rect(r.x, r.y + 4, r.w - 2, r.h - 8), total, area.h, c.scroll)
  if c.focus: d.strokeRoundRect(r, 6, withAlpha(t.accent, 160), 1)

proc scrollBy(c: ShellView, dy: float) =
  let area = c.textArea
  let total = float(c.wrapped.len) * c.lineH
  let maxScroll = max(0.0, total - area.h)
  c.scroll = clamp(c.scroll + dy, 0.0, maxScroll)
  c.follow = c.scroll >= maxScroll - 1

method onWheel*(c: ShellView, dx, dy: float): bool =
  c.scrollBy(-dy * c.lineH * 3)
  markDirty(c)
  true

proc copyAll(c: ShellView) =
  var s = ""
  for l in c.lines: s.add l.text & "\n"
  discard SDL_SetClipboardText(s.cstring)

method onMouse*(c: ShellView, e: MouseEvent) =
  let area = c.textArea
  let total = float(c.wrapped.len) * c.lineH
  let onBar = e.x >= c.rect.x + c.rect.w - 14
  case e.action
  of maPress:
    if e.button == mbRight:
      c.copyAll()
      return
    if e.button == mbLeft and onBar and total > area.h:
      c.dragging = true
  of maRelease:
    c.dragging = false
  of maMove: discard
  if c.dragging:
    c.scroll = scrollFromBar(rect(c.rect.x, c.rect.y + 4, c.rect.w, c.rect.h - 8), total, area.h, e.y)
    c.follow = c.scroll >= total - area.h - 1
    markDirty(c)

method onKey*(c: ShellView, e: KeyEvent): bool =
  let page = c.textArea.h - c.lineH
  if (e.mods and (KMOD_CTRL or KMOD_GUI)) != 0 and e.key == SDLK_C:
    c.copyAll()
    return true
  case e.key
  of SDLK_PAGEUP: c.scrollBy(-page)
  of SDLK_PAGEDOWN: c.scrollBy(page)
  of SDLK_UP: c.scrollBy(-c.lineH)
  of SDLK_DOWN: c.scrollBy(c.lineH)
  of SDLK_HOME: c.scrollBy(-1e12)
  of SDLK_END: c.scrollBy(1e12)
  else: return false
  true

method valueText*(c: ShellView): string =
  for l in c.lines: result.add l.text & "\n"

# accès par identifiant (fils d'exécution).

proc shellAppend*(id: ControlId, text: string, color = ShellFg) =
  withControl(id, ShellView, c):
    for line in text.split('\n'):
      c.lines.add ShellLine(text: line.replace("\t", "    ").replace("\r", ""), color: color)

proc shellClear*(id: ControlId) =
  withControl(id, ShellView, c):
    c.lines.setLen(0)
    c.wrapped.setLen(0)
    c.wrappedCount = 0
    c.scroll = 0
    c.follow = true

proc shellText*(id: ControlId): string =
  readControl(id, ShellView, c):
    for l in c.lines: result.add l.text & "\n"
