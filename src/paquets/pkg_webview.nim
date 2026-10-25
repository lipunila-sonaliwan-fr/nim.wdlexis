# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet webview : pages HTML / CSS / JavaScript dans une fenêtre
#   native (https://github.com/webview/webview : WebView2 sous Windows,
#   WKWebView sous macOS, WebKitGTK sous Linux).
#
#   wv = paquet("webview")
#   f = wv.fenetre{titre = "Bonjour", largeur = 800, hauteur = 600, fichier = "page.htm"}
#   f:lier("total", @TOTAL)          && JavaScript -> Lexis+ : await total(2, 3)
#   f:autoriser("ENREGISTRER")       && JavaScript -> Lexis+ : await lexis.appeler("ENREGISTRER", x)
#   f.surpret = @PRET                && page chargée
#   f:executer()                     && boucle de la fenêtre, jusqu'à sa fermeture
#
#   procedure PRET(ev)
#     f:appeler("afficher", "Bonjour depuis Lexis+")      && Lexis+ -> JavaScript
#     f:evaluer("document.title", @TITRE)                 && avec résultat (asynchrone)
#   retourner
#
# La bibliothèque webview (webview.dll / webview.dylib / webview.so) est
# chargée à l'exécution, seulement si le programme ouvre une fenêtre ; elle
# est cherchée : variable WDLEXIS_WEBVIEW (chemin complet), dossier winOS /
# macOS / linOS à côté de l'exécutable, à côté de l'exécutable, dossier
# courant, dossier du programme, puis bibliothèques du système.
#
# Fils d'exécution
# ----------------
# La fenêtre appartient au fil qui l'a créée ; f:executer() y fait tourner la
# boucle native (exigence de webview, et de Cocoa : sous macOS ce fil doit
# être le fil principal, c'est-à-dire le runtime wdlexisrt). Pendant la
# boucle, l'interpréteur est libéré (L.blocking) ; chaque appel venant de
# JavaScript le reprend le temps d'exécuter la procédure Lexis+, comme les
# gestionnaires du paquet interface. Les appels Lexis+ -> JavaScript faits
# depuis un autre fil (tâche) passent par webview_dispatch. Le bouton
# Arrêter de l'atelier termine la boucle (fil de surveillance).
#
# Côté JavaScript, un script injecté avant chaque page définit window.lexis :
#   lexis.appeler(nom, ...args)   -> Promise (procédure autorisée par f:autoriser)
#   lexis.envoyer(donnees)        -> f.surmessage(donnees)
#   lexis.journal(...)            -> console de l'atelier / du runtime
#   lexis.sur(nom, fn), lexis.retirer(nom, fn)   <- f:emettre(nom, donnees)
#   lexis.pret                    vrai une fois la page chargée
# Les fonctions liées par f:lier(nom) sont des fonctions globales
# asynchrones : window.nom(...args) -> Promise.

import std/[os, dynlib, json, locks, tables, sets, strutils, atomics, uri]
from std/unicode import toUpper, toLower
import ../lexis/[api, fonctions]

const
  osDir = when defined(windows): "winOS" elif defined(macosx): "macOS" else: "linOS"
  LibNames = when defined(windows): @["webview.dll", "libwebview.dll"]
             elif defined(macosx): @["webview.dylib", "libwebview.dylib"]
             else: @["webview.so", "libwebview.so", "libwebview.so.0"]

  HintNone = 0
  HintMin = 1
  HintMax = 2
  HintFixed = 3

#
# API C de webview, chargée à l'exécution
#

type
  WvHandle = pointer
  DispatchFn = proc (w: WvHandle, arg: pointer) {.cdecl.}
  BindFn = proc (id, req: cstring, arg: pointer) {.cdecl.}

  WvApi = object
    create: proc (debug: cint, window: pointer): WvHandle {.cdecl, gcsafe.}
    destroy: proc (w: WvHandle): cint {.cdecl, gcsafe.}
    run: proc (w: WvHandle): cint {.cdecl, gcsafe.}
    terminate: proc (w: WvHandle): cint {.cdecl, gcsafe.}
    dispatch: proc (w: WvHandle, fn: DispatchFn, arg: pointer): cint {.cdecl, gcsafe.}
    setTitle: proc (w: WvHandle, title: cstring): cint {.cdecl, gcsafe.}
    setSize: proc (w: WvHandle, width, height, hints: cint): cint {.cdecl, gcsafe.}
    navigate: proc (w: WvHandle, url: cstring): cint {.cdecl, gcsafe.}
    setHtml: proc (w: WvHandle, html: cstring): cint {.cdecl, gcsafe.}
    init: proc (w: WvHandle, js: cstring): cint {.cdecl, gcsafe.}
    eval: proc (w: WvHandle, js: cstring): cint {.cdecl, gcsafe.}
    bindFn: proc (w: WvHandle, name: cstring, fn: BindFn, arg: pointer): cint {.cdecl, gcsafe.}
    unbind: proc (w: WvHandle, name: cstring): cint {.cdecl, gcsafe.}
    ret: proc (w: WvHandle, id: cstring, status: cint, res: cstring): cint {.cdecl, gcsafe.}
    version: proc (): pointer {.cdecl, gcsafe.}      # facultatif (webview >= 0.11)

  # webview_version_info_t
  VersionInfo = object
    major, minor, patch: cuint
    number: array[32, char]
    preRelease: array[48, char]
    buildMetadata: array[48, char]

var wv: WvApi
var wvLoaded = false
var wvError = ""
var wvLibPath = ""
var loadLock: Lock
initLock(loadLock)

when defined(posix):
  proc c_dlerror(): cstring {.importc: "dlerror", header: "<dlfcn.h>".}
when defined(macosx):
  proc pthread_main_np(): cint {.importc, header: "<pthread.h>".}

proc candidates(extra: openArray[string]): seq[string] =
  let env = getEnv("WDLEXIS_WEBVIEW")
  if env.len > 0: result.add env
  let exe = getAppDir()
  for n in LibNames:
    result.add exe / osDir / n
    result.add exe / n
    when defined(macosx):
      result.add exe / ".." / "Frameworks" / n
      result.add exe / ".." / "Resources" / osDir / n
    result.add getCurrentDir() / osDir / n
    for d in extra:
      if d.len > 0:
        result.add d / osDir / n
        result.add d / n
  for n in LibNames: result.add n          # bibliothèques du système

proc loadWebview(extra: openArray[string]): bool =
  {.cast(gcsafe).}:
    withLock loadLock:
      if wvLoaded: return true
      var lib: LibHandle = nil
      var detail = ""
      for c in candidates(extra):
        lib = loadLib(c)
        if not lib.isNil:
          wvLibPath = c
          break
        if detail.len == 0 and c.isAbsolute and fileExists(c):
          # le fichier existe mais ne se charge pas : dépendance manquante.
          when defined(posix):
            let e = c_dlerror()
            detail = c & " : " & (if e.isNil: "chargement impossible" else: $e)
          else:
            detail = c & " : chargement impossible (runtime WebView2 ?)"
      if lib.isNil:
        wvError = "bibliothèque webview introuvable ; placez " & LibNames[0] &
                  " dans le dossier « " & osDir & " » à côté de l'exécutable ou du programme, " &
                  "ou indiquez son chemin dans la variable WDLEXIS_WEBVIEW"
        when defined(linux):
          wvError.add " (elle demande WebKitGTK 4.1 : paquet libwebkit2gtk-4.1-0)"
        if detail.len > 0: wvError = "bibliothèque webview présente mais inutilisable - " & detail
        return false
      template sym(field: untyped, name: string) =
        let p = lib.symAddr(name)
        if p.isNil:
          wvError = "symbole webview manquant : " & name & " (" & wvLibPath & ")"
          return false
        wv.field = cast[typeof(wv.field)](p)
      sym(create, "webview_create")
      sym(destroy, "webview_destroy")
      sym(run, "webview_run")
      sym(terminate, "webview_terminate")
      sym(dispatch, "webview_dispatch")
      sym(setTitle, "webview_set_title")
      sym(setSize, "webview_set_size")
      sym(navigate, "webview_navigate")
      sym(setHtml, "webview_set_html")
      sym(init, "webview_init")
      sym(eval, "webview_eval")
      sym(bindFn, "webview_bind")
      sym(unbind, "webview_unbind")
      sym(ret, "webview_return")
      wv.version = cast[typeof(wv.version)](lib.symAddr("webview_version"))
      wvLoaded = true
      return true

proc versionText(): string =
  if wv.version.isNil: return "inconnue (< 0.11)"
  let p = cast[ptr VersionInfo](wv.version())
  if p.isNil: return "inconnue"
  result = $cast[cstring](addr p.number[0])
  let pre = $cast[cstring](addr p.preRelease[0])
  if pre.len > 0 and not result.endsWith(pre): result.add pre

#
# Fenêtres
#

type
  OpKind = enum okEval, okTitle, okSize, okHtml, okNavigate, okTerminate
  WvOp = object
    kind: OpKind
    s: string
    w, h, hint: int

  WvWin* = ref object of LUser
    L: Interp
    h: WvHandle
    idx: int                    # index dans le registre (argument des rappels C).
    creator: int                # fil propriétaire (création, boucle, liaisons).
    running: bool
    closed: bool
    ready: bool                 # page chargée (événement « pret » reçu).
    contentSet: bool
    lock: Lock                  # protège ops (seule donnée partagée entre fils).
    ops: seq[WvOp]
    title: string
    handlers: LTable            # SURPRET, SURMESSAGE, SURFERMETURE.
    binds: Table[string, Value] # nom JavaScript -> procédure (nul : même nom).
    allowed: HashSet[string]
    allowAll: bool
    callbacks: Table[int, Value]
    nextCb: int
    pending: ref CatchableError # arrêt (systeme.quitter, Arrêter) à relancer après la boucle.

  BindRec = object
    win: int
    name: string

var regLock: Lock
var registry: seq[WvWin]        # fenêtres, par index (jamais retirées : petites, rares).
var bindRecs: seq[BindRec]
initLock(regLock)

var wvBlocking {.threadvar.}: int   # > 0 : ce fil est dans f:executer(), verrou de l'interpréteur libéré.

proc winAt(i: int): WvWin =
  {.cast(gcsafe).}:
    withLock regLock:
      if i >= 0 and i < registry.len: result = registry[i]

proc onUi(win: WvWin): bool {.inline.} = getThreadId() == win.creator

#
# Conversions Lexis+ <-> JSON / JavaScript
#

proc jsKey(k: string): string =
  # Les identifiants Lexis+ sont rangés en majuscules (NOM) : ils deviennent
  # « nom » côté JavaScript. Une clef écrite avec une casse exacte (t["Ville"])
  # est gardée telle quelle.
  if k.len > 0 and toUpper(k) == k and toLower(k) != k: toLower(k) else: k

proc lowerKeys(j: JsonNode): JsonNode =
  case j.kind
  of JObject:
    if j.len == 0: return newJArray()   # table vide : liste vide (plus sûr pour for...of).
    result = newJObject()
    for k, v in j.fields: result[jsKey(k)] = lowerKeys(v)
  of JArray:
    result = newJArray()
    for v in j.elems: result.add lowerKeys(v)
  else: result = j

proc toJs(L: Interp, v: Value): string =
  # Littéral JavaScript (JSON) d'une valeur Lexis+.
  $lowerKeys(L.toJsonNode(v))

proc jsStr(s: string): string = $(%s)

proc fromJs(j: JsonNode): Value =
  if j.isNil: nilV else: fromJsonNode(j)

#
# Script injecté avant chaque page : window.lexis
#

const HelperJs = """
(function () {
  if (window.lexis && window.lexis.__interne) return;
  var appel = function () { return window.__lexis.apply(window, arguments); };
  var silence = function (p) { if (p && p.catch) p.catch(function () {}); return p; };
  var ecouteurs = {};
  var texte = function (args) {
    return Array.prototype.map.call(args, function (x) {
      if (typeof x === 'string') return x;
      if (x instanceof Error) return x.message;
      try { return JSON.stringify(x); } catch (e) { return String(x); }
    }).join(' ');
  };
  var L = {
    __interne: true,
    pret: false,
    appeler: function (nom) { return appel('appel', nom, Array.prototype.slice.call(arguments, 1)); },
    envoyer: function (donnees) { return appel('message', donnees === undefined ? null : donnees); },
    journal: function () { return silence(appel('journal', 'info', texte(arguments))); },
    sur: function (nom, fn) { (ecouteurs[nom] = ecouteurs[nom] || []).push(fn); },
    retirer: function (nom, fn) {
      var l = ecouteurs[nom] || [], i = l.indexOf(fn);
      if (i >= 0) l.splice(i, 1);
    },
    _emettre: function (nom, d) {
      (ecouteurs[nom] || []).slice().forEach(function (fn) {
        try { fn(d); } catch (e) { console.error(e); }
      });
    },
    _executer: function (fabrique, id) {
      var p;
      try { p = Promise.resolve(fabrique()); } catch (e) { p = Promise.reject(e); }
      p.then(function (v) { if (id) silence(appel('resultat', id, true, v === undefined ? null : v)); },
             function (e) {
               var m = (e && e.message) ? e.message : String(e);
               silence(id ? appel('resultat', id, false, m) : appel('journal', 'erreur', m));
             });
    },
    _appeler: function (chemin, args, id) {
      L._executer(function () {
        var parts = chemin.split('.'), ctx = window, f = window;
        for (var i = 0; i < parts.length; i++) { ctx = f; f = (f == null) ? undefined : f[parts[i]]; }
        if (typeof f !== 'function') throw new Error('fonction JavaScript inconnue : ' + chemin);
        return f.apply(ctx, args);
      }, id);
    },
    _evaluer: function (code, id) { L._executer(function () { return (0, eval)(code); }, id); }
  };
  window.lexis = L;
  if (/*CONSOLE*/true) {
    ['log', 'info', 'debug', 'warn', 'error'].forEach(function (n) {
      var orig = (console[n] || console.log || function () {}).bind(console);
      console[n] = function () {
        orig.apply(null, arguments);
        try { silence(appel('journal', n, texte(arguments))); } catch (e) {}
      };
    });
    window.addEventListener('error', function (e) {
      silence(appel('journal', 'erreur', (e.message || 'erreur') +
        (e.filename ? ' (' + e.filename + ':' + e.lineno + ')' : '')));
    });
    window.addEventListener('unhandledrejection', function (e) {
      var r = e.reason;
      silence(appel('journal', 'erreur', 'promesse rejetée : ' + ((r && r.message) ? r.message : String(r))));
    });
  }
  var signaler = function () {
    if (L.pret) return;
    L.pret = true;
    silence(appel('pret', String(location.href)));
  };
  if (document.readyState !== 'loading') setTimeout(signaler, 0);
  else document.addEventListener('DOMContentLoaded', signaler);
})();
"""

const BlankPage = "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>"

#
# Exécution des opérations sur le fil de la fenêtre
#

proc execOp(win: WvWin, op: WvOp) =
  {.cast(gcsafe).}:
    if win.h.isNil: return
    case op.kind
    of okEval: discard wv.eval(win.h, op.s.cstring)
    of okTitle: discard wv.setTitle(win.h, op.s.cstring)
    of okSize: discard wv.setSize(win.h, cint(op.w), cint(op.h), cint(op.hint))
    of okHtml:
      win.ready = false
      win.contentSet = true
      discard wv.setHtml(win.h, op.s.cstring)
    of okNavigate:
      win.ready = false
      win.contentSet = true
      discard wv.navigate(win.h, op.s.cstring)
    of okTerminate: discard wv.terminate(win.h)

proc flush(win: WvWin) =
  # Fil de la fenêtre : exécute les opérations en attente ; les évaluations
  # JavaScript attendent que la page soit prête.
  var todo: seq[WvOp]
  withLock win.lock:
    var keep: seq[WvOp]
    for op in win.ops:
      if op.kind == okEval and not win.ready: keep.add op
      else: todo.add op
    win.ops = keep
  for op in todo: win.execOp(op)

proc dispatchCb(w: WvHandle, arg: pointer) {.cdecl.} =
  let win = winAt(cast[int](arg) - 1)
  if not win.isNil: win.flush()

proc post(win: WvWin, op: WvOp) =
  if win.closed: rtError("la fenêtre webview est fermée")
  if win.onUi:
    if op.kind == okEval and not win.ready:
      withLock win.lock: win.ops.add op      # envoyé dès que la page est prête.
    else:
      win.execOp(op)
  else:
    # autre fil (tâche) : la fenêtre exécutera l'opération dans sa boucle.
    withLock win.lock: win.ops.add op
    {.cast(gcsafe).}:
      discard wv.dispatch(win.h, dispatchCb, cast[pointer](win.idx + 1))

proc postJs(win: WvWin, js: string) = win.post(WvOp(kind: okEval, s: js))

#
# Appels de Lexis+ depuis la boucle de la fenêtre
#

template lexisSide(win: WvWin, body: untyped) =
  # Reprend le verrou de l'interpréteur si la boucle l'avait libéré ; sinon
  # (rappel imbriqué dans du code Lexis+ du même fil) il est déjà tenu.
  let needEnter = wvBlocking > 0
  if needEnter:
    dec wvBlocking
    win.L.enter()
  try:
    body
  finally:
    if needEnter:
      win.L.leave()
      inc wvBlocking

proc stopLoop(win: WvWin, e: ref CatchableError) =
  if win.pending.isNil: win.pending = e
  {.cast(gcsafe).}:
    if not win.h.isNil: discard wv.terminate(win.h)

proc callProc(win: WvWin, f: Value, args: seq[Value], ok: var bool): Value =
  # Appelle une procédure ; ok = faux et résultat = message si erreur.
  let L = win.L
  ok = false
  if L.stopRequested(): return strV("programme arrêté")
  try:
    let r = L.call(f, args)
    ok = true
    result = if r.len > 0: r[0] else: nilV
  except LexisStop as e:
    win.stopLoop(e)
    result = strV("programme arrêté")
  except LexisError as e:
    result = strV(display(e.value))
    win.L.onError(e.msg & "\n" & e.traceback)
  except CatchableError as e:
    result = strV(e.msg)
    win.L.onError("erreur dans un appel webview : " & e.msg)

proc fireEvent(win: WvWin, name: string, args: seq[Value]) =
  let h = win.handlers.rawGet(cle(name))
  if h.kind == vkNil: return
  var ok: bool
  discard win.callProc(h, args, ok)

proc reply(win: WvWin, id: cstring, ok: bool, json: string) =
  {.cast(gcsafe).}:
    if not win.h.isNil: discard wv.ret(win.h, id, (if ok: 0.cint else: 1.cint), json.cstring)

proc resultJson(win: WvWin, v: Value, ok: var bool): string =
  if not ok: return jsStr(win.L.tostr(v))
  try:
    result = win.L.toJs(v)
  except LexisError as e:
    ok = false
    result = jsStr("valeur de retour non convertible en JSON : " & display(e.value))

proc argsOf(j: JsonNode, start: int): seq[Value] =
  if j.kind == JArray:
    for i in start ..< j.len: result.add fromJs(j[i])

proc userBindCb(id, req: cstring, arg: pointer) {.cdecl.} =
  # window.<nom>(...args) : procédure liée par f:lier.
  {.cast(gcsafe).}:
    var rec: BindRec
    withLock regLock: rec = bindRecs[cast[int](arg) - 1]
    let win = winAt(rec.win)
    if win.isNil: return
    var ok = false
    var res = "null"
    lexisSide(win):
      let target = win.binds.getOrDefault(rec.name, nilV)
      var args: seq[Value]
      try: args = argsOf(parseJson($req), 0)
      except CatchableError: discard
      var f = target
      if f.kind == vkNil:
        let n = cle(rec.name)
        f = win.L.procs.getOrDefault(n, nilV)
        if f.kind == vkNil: f = win.L.globals.rawGet(n)
      if f.kind == vkNil or not win.L.callable(f):
        res = jsStr("procédure Lexis+ inconnue : " & rec.name)
      else:
        let v = win.callProc(f, args, ok)
        res = win.resultJson(v, ok)
    win.reply(id, ok, res)

proc internalCb(id, req: cstring, arg: pointer) {.cdecl.} =
  # window.__lexis(genre, ...) : canal du script window.lexis.
  {.cast(gcsafe).}:
    let win = winAt(cast[int](arg) - 1)
    if win.isNil: return
    var j: JsonNode
    try: j = parseJson($req)
    except CatchableError: j = newJArray()
    let kind = if j.kind == JArray and j.len > 0 and j[0].kind == JString: j[0].getStr else: ""
    var ok = true
    var res = "null"
    case kind
    of "pret":
      win.ready = true
      win.flush()
      lexisSide(win):
        win.fireEvent("surpret", @[record({"url": strV(if j.len > 1: j[1].getStr else: "")})])
    of "journal":
      let niveau = if j.len > 1: j[1].getStr else: "info"
      let txt = if j.len > 2: j[2].getStr else: ""
      let prefix = case niveau
                   of "warn": "[js:attention] "
                   of "error", "erreur": "[js:erreur] "
                   else: "[js] "
      lexisSide(win):
        win.L.output(prefix & txt & "\n")
    of "message":
      lexisSide(win):
        win.fireEvent("surmessage", @[if j.len > 1: fromJs(j[1]) else: nilV])
    of "resultat":
      let cid = if j.len > 1: int(j[1].getBiggestInt) else: 0
      let succes = j.len > 2 and j[2].kind == JBool and j[2].getBool
      lexisSide(win):
        let cb = win.callbacks.getOrDefault(cid, nilV)
        win.callbacks.del(cid)
        if cb.kind != vkNil:
          var cok: bool
          let v = if j.len > 3: fromJs(j[3]) else: nilV
          if succes: discard win.callProc(cb, @[v, nilV], cok)
          else: discard win.callProc(cb, @[nilV, (if v.kind == vkNil: strV("erreur JavaScript") else: v)], cok)
    of "appel":
      let nom = if j.len > 1 and j[1].kind == JString: j[1].getStr else: ""
      let args = if j.len > 2 and j[2].kind == JArray: argsOf(j[2], 0) else: @[]
      lexisSide(win):
        let n = cle(nom)
        if not (win.allowAll or n in win.allowed):
          ok = false
          res = jsStr("procédure Lexis+ non autorisée : " & nom & " (voir f:autoriser)")
        else:
          var f = win.L.procs.getOrDefault(n, nilV)
          if f.kind == vkNil: f = win.L.globals.rawGet(n)
          if f.kind == vkNil or not win.L.callable(f):
            ok = false
            res = jsStr("procédure Lexis+ inconnue : " & nom)
          else:
            let v = win.callProc(f, args, ok)
            res = win.resultJson(v, ok)
    else:
      ok = false
      res = jsStr("appel interne inconnu : " & kind)
    win.reply(id, ok, res)

#
# Surveillance de l'arrêt (bouton Arrêter de l'atelier)
#

type WatchArg = object
  h: WvHandle
  done: ptr Atomic[bool]
  stop: ptr Atomic[bool]
  parent: ptr Atomic[bool]

proc watch(a: ptr WatchArg) {.thread.} =
  {.cast(gcsafe).}:
    while not a.done[].load():
      if a.stop[].load() or (not a.parent.isNil and a.parent[].load()):
        discard wv.terminate(a.h)
        break
      sleep(50)

#
# Objet fenêtre côté Lexis+
#

var wvMethods: LTable
var wvMeta: LTable

proc self(a: seq[Value], fname: string): WvWin =
  let v = arg(a, 1)
  if v.kind != vkUser or not (v.u of WvWin):
    rtError("« " & fname & " » : appelez-la avec « : » (fenetre:" & fname & "(...))")
  WvWin(v.u)

proc requireUi(win: WvWin, what: string) =
  if win.closed: rtError("la fenêtre webview est fermée")
  if not win.onUi: rtError(what & " : à appeler depuis le fil qui a créé la fenêtre")

proc destroyWin(win: WvWin) =
  if win.h.isNil: return
  {.cast(gcsafe).}:
    discard wv.destroy(win.h)
  win.h = nil
  win.closed = true
  win.ready = false

proc hintOf(s: string): int =
  case s.toLowerAscii
  of "min", "minimum", "minimale": HintMin
  of "max", "maximum", "maximale": HintMax
  of "fixe", "fixed": HintFixed
  else: HintNone

proc fileUrl*(L: Interp, path: string): string =
  ## URL file:// d'un chemin (relatif au dossier du programme).
  var p = path
  if not p.isAbsolute:
    let base = if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir()
    p = base / p
  p = absolutePath(p).normalizedPath
  when defined(windows): p = p.replace('\\', '/')
  var parts: seq[string]
  for seg in p.split('/'):
    when defined(windows):
      if seg.len == 2 and seg[1] == ':':
        parts.add seg
        continue
    parts.add encodeUrl(seg, usePlus = false)
  result = (when defined(windows): "file:///" else: "file://") & parts.join("/")

proc addCallback(win: WvWin, cb: Value): int =
  if cb.kind == vkNil: return 0
  inc win.nextCb
  win.callbacks[win.nextCb] = cb
  win.nextCb

proc wvIndex(L: Interp, a: seq[Value]): seq[Value] =
  let win = WvWin(a[0].u)
  let key = arg(a, 2)
  if key.kind != vkStr: return @[nilV]
  let m = wvMethods.rawGet(cle(key.s))
  if m.kind != vkNil: return @[m]
  case key.s.toLowerAscii
  of "titre": @[strV(win.title)]
  of "ouverte": @[boolV(not win.closed)]
  of "prete": @[boolV(win.ready)]
  of "enexecution": @[boolV(win.running)]
  of "surpret", "surmessage", "surfermeture": @[win.handlers.rawGet(cle(key.s))]
  else: @[nilV]

proc wvNewIndex(L: Interp, a: seq[Value]): seq[Value] =
  let win = WvWin(a[0].u)
  let key = arg(a, 2)
  if key.kind != vkStr: rtError("nom de propriété attendu")
  let v = arg(a, 3)
  case key.s.toLowerAscii
  of "titre":
    win.title = L.tostr(v)
    win.post(WvOp(kind: okTitle, s: win.title))
  of "surpret", "surmessage", "surfermeture":
    if v.kind != vkNil and not L.callable(v):
      rtError(key.s.toLowerAscii & " : référence de procédure attendue (@NOM)")
    win.handlers.rawSet(cle(key.s), v)
  else:
    rtError("propriété inconnue de webview.fenetre : " & key.s.toLowerAscii)

proc defineMethods() =
  let m = newLib()
  m.fn "html", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "html")
    win.post(WvOp(kind: okHtml, s: L.checkStr(a, 2, "html")))
  m.fn "naviguer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "naviguer")
    win.post(WvOp(kind: okNavigate, s: L.checkStr(a, 2, "naviguer")))
  m.fn "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "ouvrir")
    let p = L.checkStr(a, 2, "ouvrir")
    let url = L.fileUrl(p)
    var local = p
    if not local.isAbsolute:
      local = (if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir()) / p
    if not fileExists(local): return fail(p & " : fichier introuvable")
    win.post(WvOp(kind: okNavigate, s: url))
  m.fn "initialiser", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "initialiser")
    win.requireUi("initialiser")
    {.cast(gcsafe).}:
      discard wv.init(win.h, L.checkStr(a, 2, "initialiser").cstring)
  m.fn "evaluer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "evaluer")
    let code = L.checkStr(a, 2, "evaluer")
    var cb = nilV
    if arg(a, 3).kind != vkNil: cb = L.checkFunc(a, 3, "evaluer")
    let id = win.addCallback(cb)
    win.postJs("window.lexis._evaluer(" & jsStr(code) & "," & $id & ");")
  m.fn "appeler", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "appeler")
    let fname = L.checkStr(a, 2, "appeler")
    var last = a.len
    var cb = nilV
    if last >= 3 and a[last - 1].kind == vkFunc:
      cb = a[last - 1]
      dec last
    var args = "["
    for i in 3 .. last:
      if i > 3: args.add ","
      args.add L.toJs(a[i - 1])
    args.add "]"
    let id = win.addCallback(cb)
    win.postJs("window.lexis._appeler(" & jsStr(fname) & "," & args & "," & $id & ");")
  m.fn "emettre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "emettre")
    let nom = L.checkStr(a, 2, "emettre")
    win.postJs("window.lexis._emettre(" & jsStr(nom) & "," & L.toJs(arg(a, 3)) & ");")
  m.fn "lier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "lier")
    win.requireUi("lier")
    let nom = L.checkStr(a, 2, "lier")
    var f = nilV
    if arg(a, 3).kind != vkNil: f = L.checkFunc(a, 3, "lier")
    if win.binds.hasKey(nom):
      win.binds[nom] = f          # déjà liée : on change seulement la procédure.
      return
    win.binds[nom] = f
    var ridx: int
    {.cast(gcsafe).}:
      withLock regLock:
        bindRecs.add BindRec(win: win.idx, name: nom)
        ridx = bindRecs.len
      discard wv.bindFn(win.h, nom.cstring, userBindCb, cast[pointer](ridx))
  m.fn "delier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "delier")
    win.requireUi("delier")
    let nom = L.checkStr(a, 2, "delier")
    if win.binds.hasKey(nom):
      win.binds.del(nom)
      {.cast(gcsafe).}:
        discard wv.unbind(win.h, nom.cstring)
  m.fn "autoriser", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "autoriser")
    for i in 2 .. a.len:
      let v = a[i - 1]
      if v.kind == vkTable:
        for k in 1 .. v.t.rawLen: win.allowed.incl cle(L.tostr(v.t.rawGet(intV(k))))
      else:
        let n = L.tostr(v)
        if n == "*": win.allowAll = true else: win.allowed.incl cle(n)
  m.fn "taille", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "taille")
    win.post(WvOp(kind: okSize, w: int(L.checkInt(a, 2, "taille")), h: int(L.checkInt(a, 3, "taille")),
                  hint: hintOf(L.optStr(a, 4, "taille", "normale"))))
  m.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "fermer")
    if win.closed: return
    if win.running or not win.onUi: win.post(WvOp(kind: okTerminate))
    else: win.destroyWin()
  m.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let win = self(a, "executer")
    win.requireUi("executer")
    if win.running: rtError("la fenêtre webview est déjà en cours d'exécution")
    if not win.contentSet: win.post(WvOp(kind: okHtml, s: BlankPage))
    win.running = true
    var done: Atomic[bool]
    done.store(false)
    var wa = WatchArg(h: win.h, done: addr done, stop: addr L.stopFlag, parent: L.parentStop)
    var th: Thread[ptr WatchArg]
    createThread(th, watch, addr wa)
    L.blocking:
      inc wvBlocking
      try:
        {.cast(gcsafe).}:
          discard wv.run(win.h)
      finally:
        dec wvBlocking
    done.store(true)
    joinThread(th)
    win.running = false
    win.destroyWin()
    win.fireEvent("surfermeture", @[])
    if not win.pending.isNil:
      let e = win.pending
      win.pending = nil
      raise e
    L.checkStop()
  wvMethods = m

proc newWindow(L: Interp, o: LTable): Value =
  if not loadWebview(L.searchDirs & @[(if L.scriptPath.len > 0: L.scriptPath.parentDir else: "")]):
    {.cast(gcsafe).}: rtError(wvError)
  when defined(macosx):
    if pthread_main_np() == 0:
      rtError("sous macOS, une fenêtre webview doit être créée par le fil principal : " &
              "exécutez ce programme avec le runtime (wdlexisrt programme.prg), pas dans l'atelier")
  let debug = optField(o, "debogage", false)
  var h: WvHandle
  {.cast(gcsafe).}:
    h = wv.create((if debug: 1.cint else: 0.cint), nil)
  if h.isNil:
    rtError("webview_create a échoué (moteur web absent ? Windows : runtime WebView2 ; " &
            "Linux : WebKitGTK 4.1 et un affichage graphique)")
  let win = WvWin(L: L, h: h, creator: getThreadId(), handlers: newLTable(),
                  binds: initTable[string, Value](), allowed: initHashSet[string](),
                  callbacks: initTable[int, Value]())
  initLock(win.lock)
  {.cast(gcsafe).}:
    withLock regLock:
      win.idx = registry.len
      registry.add win
  let first = L.ext.getOrDefault("webview").isNil
  if first:
    L.ext["webview"] = RootRef()
    L.closers.add proc () =
      # fin du programme : fenêtres créées mais jamais exécutées.
      {.cast(gcsafe).}:
        var mine: seq[WvWin]
        withLock regLock:
          for w in registry:
            if w.L == L and not w.closed and not w.running: mine.add w
        for w in mine:
          if w.onUi: w.destroyWin()
  let helper = HelperJs.replace("/*CONSOLE*/true", (if optField(o, "console", true): "true" else: "false"))
  {.cast(gcsafe).}:
    discard wv.init(h, helper.cstring)
    discard wv.bindFn(h, "__lexis", internalCb, cast[pointer](win.idx + 1))
  win.title = optField(o, "titre", "wdlexis+")
  win.post(WvOp(kind: okTitle, s: win.title))
  win.post(WvOp(kind: okSize, w: optField(o, "largeur", 800), h: optField(o, "hauteur", 600),
                hint: hintOf(optField(o, "taille", "normale"))))
  let html = optField(o, "html", "")
  let url = optField(o, "url", "")
  let fichier = optField(o, "fichier", "")
  if fichier.len > 0: win.post(WvOp(kind: okNavigate, s: L.fileUrl(fichier)))
  elif url.len > 0: win.post(WvOp(kind: okNavigate, s: url))
  elif html.len > 0: win.post(WvOp(kind: okHtml, s: html))
  win.tname = "webview.fenetre"
  win.meta = wvMeta
  userV(win)

proc openWebview(L: Interp): Value =
  let m = newLib()
  m.fn "fenetre", proc (L: Interp, a: seq[Value]): seq[Value] =
    var o: LTable = nil
    if arg(a, 1).kind == vkTable: o = a[0].t
    elif arg(a, 1).kind == vkStr:
      o = newLTable()
      o.set("titre", a[0])
    @[L.newWindow(o)]
  m.fn "disponible", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(loadWebview(L.searchDirs & @[(if L.scriptPath.len > 0: L.scriptPath.parentDir else: "")]))]
  m.fn "erreur", proc (L: Interp, a: seq[Value]): seq[Value] =
    {.cast(gcsafe).}:
      result = @[(if wvError.len > 0: strV(wvError) else: nilV)]
  m.fn "version", proc (L: Interp, a: seq[Value]): seq[Value] =
    {.cast(gcsafe).}:
      if not loadWebview(L.searchDirs): return fail(wvError)
      result = @[strV(versionText())]
  m.fn "bibliotheque", proc (L: Interp, a: seq[Value]): seq[Value] =
    {.cast(gcsafe).}:
      result = @[(if wvLoaded: strV(wvLibPath) else: nilV)]
  m.fn "url", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(L.fileUrl(L.checkStr(a, 1, "url")))]
  m.fn "js", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(L.toJs(arg(a, 1)))]
  tableV(m)

defineMethods()
wvMeta = newLTable()
wvMeta.set "__index", fnV("webview.index", wvIndex)
wvMeta.set "__newindex", fnV("webview.newindex", wvNewIndex)
wvMeta.set "__name", strV("webview.fenetre")

registerPackage PackageDef(name: "webview", open: openWebview,
  description: "Pages HTML / JavaScript dans une fenêtre native (webview)",
  docs: docs("webview", [
    "webview.fenetre{titre=, largeur=, hauteur=, taille=, fichier=, url=, html=, debogage=, console=}",
      "Crée une fenêtre web. taille : normale, min, max, fixe ; fichier : page locale (relative au programme) ; debogage = vrai : outils de développement ; console = faux : ne pas renvoyer console.log vers la console Lexis+.",
    "webview.disponible()", "Vrai si la bibliothèque webview est chargée (sinon voir webview.erreur()).",
    "webview.erreur()", "Raison de l'échec du chargement de la bibliothèque (nul si aucune).",
    "webview.version()", "Version de la bibliothèque webview.",
    "webview.bibliotheque()", "Chemin de la bibliothèque chargée.",
    "webview.url(chemin)", "URL file:// d'un fichier local (relatif au dossier du programme).",
    "webview.js(valeur)", "Littéral JavaScript (JSON) d'une valeur Lexis+ ; les clefs deviennent minuscules, une table vide devient [].",
    "fen:html(code)", "Affiche du HTML.",
    "fen:naviguer(url)", "Charge une URL (https://, file://, data:...).",
    "fen:ouvrir(chemin)", "Charge un fichier HTML local (relatif au dossier du programme).",
    "fen:initialiser(js)", "Ajoute un script exécuté avant chaque page.",
    "fen:evaluer(code, [@rappel])", "Lexis+ -> JavaScript : évalue du code ; rappel(valeur, erreur) reçoit le résultat.",
    "fen:appeler(fonction, arg..., [@rappel])", "Lexis+ -> JavaScript : appelle window.fonction(arg...) (chemin \"app.maj\" accepté) ; rappel(valeur, erreur).",
    "fen:emettre(nom, [donnees])", "Lexis+ -> JavaScript : déclenche les écouteurs lexis.sur(nom, fn).",
    "fen:lier(nomjs, [@procedure])", "JavaScript -> Lexis+ : crée window.nomjs(...) (Promise) qui appelle la procédure (par défaut celle du même nom).",
    "fen:delier(nomjs)", "Retire une liaison.",
    "fen:autoriser(nom, ...)", "JavaScript -> Lexis+ : procédures appelables par lexis.appeler(nom, ...) ; \"*\" les autorise toutes.",
    "fen:taille(largeur, hauteur, [genre])", "Taille de la fenêtre (genre : normale, min, max, fixe).",
    "fen:executer()", "Affiche la fenêtre et traite ses événements jusqu'à sa fermeture.",
    "fen:fermer()", "Ferme la fenêtre (termine fen:executer())."]))
