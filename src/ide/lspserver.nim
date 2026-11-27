# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - serveur LSP (Language Server Protocol) de Lexis+
#
#   wdlexisrt --lsp          (JSON-RPC sur l'entrée et la sortie standard)
#
# Pour VS Code, Neovim, Helix, Zed, Kate, Sublime (LSP), JetBrains (LSP4IJ)... :
# déclarer la commande « wdlexisrt --lsp » pour les fichiers *.prg (langage « lexis »).
#
# Fonctions : diagnostics (syntaxe, appels inconnus, collisions de noms, types
# déclarés), infobulles, complétion (. et : déclenchent les membres), aide à la
# signature, aller à la définition, usages, renommage, symboles du document et de
# l'espace de travail, formatage (conventions du fichier .lexisformat).
# Synchronisation des documents : texte complet (TextDocumentSyncKind.Full).

import std/[json, strutils, os, tables, uri]
import langservice, lexisanalyse, lexislint, formateur, langdocs
from lsptypes import CompletionItem

type
  Server = object
    ws: Workspace
    shutdown: bool
    rootSet: bool

#
# transport
#

proc readMessage(): (bool, JsonNode) =
  var length = -1
  while true:
    var line: string
    if not stdin.readLine(line): return (false, nil)
    line = line.strip(chars = {'\r', '\n'})
    if line.len == 0:
      if length >= 0: break
      continue
    let c = line.find(':')
    if c > 0 and line[0 ..< c].toLowerAscii == "content-length":
      length = parseInt(line[c + 1 .. ^1].strip)
  var buf = newString(length)
  if length > 0:
    let n = stdin.readBuffer(addr buf[0], length)
    if n < length: buf.setLen(n)
  try: (true, parseJson(buf))
  except JsonParsingError, ValueError: (true, newJNull())

proc send(msg: JsonNode) =
  let body = $msg
  stdout.write "Content-Length: " & $body.len & "\r\n\r\n" & body
  stdout.flushFile()

proc respond(id: JsonNode, res: JsonNode) =
  send(%*{"jsonrpc": "2.0", "id": id, "result": res})

proc respondError(id: JsonNode, code: int, msg: string) =
  send(%*{"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": msg}})

proc notify(meth: string, params: JsonNode) =
  send(%*{"jsonrpc": "2.0", "method": meth, "params": params})

#
# positions
#

proc uriToPath*(u: string): string =
  if not u.startsWith("file://"): return u
  var p = decodeUrl(u[7 .. ^1], decodePlus = false)
  when defined(windows):
    if p.len > 2 and p[0] == '/' and p[2] == ':': p = p[1 .. ^1]
    p = p.replace('/', '\\')
  p

proc pathToUri*(p: string): string =
  var s = p.replace('\\', '/')
  if not s.startsWith("/"): s = "/" & s
  var enc = ""
  for c in s:
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '/', '-', '_', '.', '~', ':'}: enc.add c
    else: enc.add "%" & toHex(ord(c), 2)
  "file://" & enc

proc utf16Col(line: string, byteCol: int): int =
  var i = 0
  while i < min(byteCol, line.len):
    let c = ord(line[i])
    if c < 0x80: inc i
    elif c < 0xE0: i += 2
    elif c < 0xF0: i += 3
    else:
      i += 4
      inc result             # paire de substitution
    inc result

proc byteCol(line: string, u16: int): int =
  var i = 0
  var n = 0
  while i < line.len and n < u16:
    let c = ord(line[i])
    if c < 0x80: inc i
    elif c < 0xE0: i += 2
    elif c < 0xF0: i += 3
    else:
      i += 4
      inc n
    inc n
  min(i, line.len)

proc lineOf(s: var Server, path: string, line: int): string =
  let t = s.ws.textOf(path)
  var i = 0
  for l in t.split('\n'):
    if i == line: return l.strip(leading = false, chars = {'\r'})
    inc i
  ""

proc pos(s: var Server, path: string, line, col: int): JsonNode =
  %*{"line": line, "character": utf16Col(s.lineOf(path, line), col)}

proc rng(s: var Server, path: string, line, col, len: int): JsonNode =
  %*{"start": s.pos(path, line, col), "end": s.pos(path, line, col + len)}

proc location(s: var Server, r: RefLoc): JsonNode =
  %*{"uri": pathToUri(r.file), "range": s.rng(r.file, r.line, r.col, r.len)}

proc docPos(s: var Server, params: JsonNode): (string, int, int, string) =
  let path = uriToPath(params["textDocument"]["uri"].getStr)
  let line = params["position"]["line"].getInt
  let lt = s.lineOf(path, line)
  (path, line, byteCol(lt, params["position"]["character"].getInt), lt)

#
# diagnostics
#

proc publish(s: var Server, path: string) =
  var arr = newJArray()
  for d in s.ws.diagnostics(path):
    let sev = case d.sev
      of sevError: 1
      of sevWarning: 2
      of sevInfo: 3
    arr.add %*{"range": s.rng(path, d.line, d.col, d.len), "severity": sev, "source": "lexis",
               "message": d.msg}
  notify("textDocument/publishDiagnostics", %*{"uri": pathToUri(path), "diagnostics": arr})

#
# requêtes
#

proc symbolKind(k: string): int =
  case k
  of "procedure": 12        # Function
  of "fonction": 12
  of "globale": 13          # Variable
  else: 13

proc handle(s: var Server, msg: JsonNode) =
  if msg.kind != JObject: return
  let meth = msg{"method"}.getStr
  let id = msg{"id"}
  let params = msg{"params"}
  let isRequest = not id.isNil and id.kind != JNull
  try:
    case meth
    of "initialize":
      var root = ""
      if params.hasKey("rootUri") and params["rootUri"].kind == JString: root = uriToPath(params["rootUri"].getStr)
      elif params.hasKey("rootPath") and params["rootPath"].kind == JString: root = params["rootPath"].getStr
      s.ws = newWorkspace(root)
      s.rootSet = root.len > 0
      respond(id, %*{
        "capabilities": {
          "textDocumentSync": {"openClose": true, "change": 1, "save": {"includeText": false}},
          "hoverProvider": true,
          "completionProvider": {"triggerCharacters": [".", ":"], "resolveProvider": false},
          "signatureHelpProvider": {"triggerCharacters": ["(", ","]},
          "definitionProvider": true,
          "referencesProvider": true,
          "renameProvider": true,
          "documentSymbolProvider": true,
          "workspaceSymbolProvider": true,
          "documentFormattingProvider": true},
        "serverInfo": {"name": "wdlexis-lsp", "version": "2.1.0"}})
    of "initialized", "$/cancelRequest", "$/setTrace", "workspace/didChangeConfiguration",
       "workspace/didChangeWatchedFiles":
      discard
    of "shutdown":
      s.shutdown = true
      respond(id, newJNull())
    of "exit":
      quit(if s.shutdown: 0 else: 1)
    of "textDocument/didOpen":
      let path = uriToPath(params["textDocument"]["uri"].getStr)
      if s.ws.isNil: s.ws = newWorkspace(path.parentDir)
      s.ws.setText(path, params["textDocument"]["text"].getStr)
      s.publish(path)
    of "textDocument/didChange":
      let path = uriToPath(params["textDocument"]["uri"].getStr)
      let changes = params["contentChanges"]
      if changes.len > 0:
        s.ws.setText(path, changes[changes.len - 1]["text"].getStr)
        s.publish(path)
    of "textDocument/didSave":
      let path = uriToPath(params["textDocument"]["uri"].getStr)
      s.publish(path)
    of "textDocument/didClose":
      let path = uriToPath(params["textDocument"]["uri"].getStr)
      s.ws.closeFile(path)
      notify("textDocument/publishDiagnostics", %*{"uri": pathToUri(path), "diagnostics": []})
    of "textDocument/hover":
      let (path, line, col, _) = s.docPos(params)
      let h = s.ws.hover(path, line, col)
      if not h.found or h.markdown.len == 0: respond(id, newJNull())
      else:
        respond(id, %*{"contents": {"kind": "markdown", "value": h.markdown},
                       "range": s.rng(path, h.line, h.col, h.len)})
    of "textDocument/definition":
      let (path, line, col, _) = s.docPos(params)
      var arr = newJArray()
      for r in s.ws.definition(path, line, col): arr.add s.location(r)
      respond(id, arr)
    of "textDocument/references":
      let (path, line, col, _) = s.docPos(params)
      let incl = params{"context"}{"includeDeclaration"}.getBool(true)
      var arr = newJArray()
      for r in s.ws.references(path, line, col, incl): arr.add s.location(r)
      respond(id, arr)
    of "textDocument/rename":
      let (path, line, col, _) = s.docPos(params)
      let (ok, err, locs) = s.ws.rename(path, line, col, params["newName"].getStr)
      if not ok: respondError(id, -32602, err)
      else:
        var changes = newJObject()
        for r in locs:
          let u = pathToUri(r.file)
          if not changes.hasKey(u): changes[u] = newJArray()
          changes[u].add %*{"range": s.rng(r.file, r.line, r.col, r.len), "newText": params["newName"].getStr}
        respond(id, %*{"changes": changes})
    of "textDocument/completion":
      let (path, line, col, lt) = s.docPos(params)
      var arr = newJArray()
      for c in s.ws.completion(path, line, col, lt):
        var it = %*{"label": c.label, "kind": c.kind, "detail": c.detail}
        if c.insertText.len > 0: it["insertText"] = %c.insertText
        if c.documentation.len > 0: it["documentation"] = %*{"kind": "markdown", "value": c.documentation}
        arr.add it
      respond(id, %*{"isIncomplete": false, "items": arr})
    of "textDocument/signatureHelp":
      let (path, line, col, lt) = s.docPos(params)
      let sg = s.ws.signatureHelp(path, line, col, lt)
      if not sg.found: respond(id, newJNull())
      else:
        var ps = newJArray()
        for p in sg.params: ps.add %*{"label": p}
        respond(id, %*{"signatures": [{"label": sg.label, "documentation": sg.doc, "parameters": ps}],
                       "activeSignature": 0, "activeParameter": min(sg.active, max(0, sg.params.len - 1))})
    of "textDocument/documentSymbol":
      let path = uriToPath(params["textDocument"]["uri"].getStr)
      var arr = newJArray()
      for sy in s.ws.documentSymbols(path):
        let endLen = s.lineOf(path, sy.lastLine).len
        arr.add %*{"name": sy.name, "detail": sy.detail, "kind": symbolKind(sy.kind),
                   "range": {"start": s.pos(path, sy.line, 0), "end": s.pos(path, sy.lastLine, endLen)},
                   "selectionRange": s.rng(path, sy.line, sy.col, max(1, sy.name.len))}
      respond(id, arr)
    of "workspace/symbol":
      var arr = newJArray()
      for (p, sy) in s.ws.workspaceSymbols(params{"query"}.getStr):
        arr.add %*{"name": sy.name, "kind": symbolKind(sy.kind),
                   "location": {"uri": pathToUri(p), "range": s.rng(p, sy.line, sy.col, 1)}}
      respond(id, arr)
    of "textDocument/formatting":
      let path = uriToPath(params["textDocument"]["uri"].getStr)
      let old = s.ws.textOf(path)
      let r = s.ws.format(path)
      if not r.changed: respond(id, newJArray())
      else:
        let n = old.split('\n').len
        respond(id, %*[{"range": {"start": {"line": 0, "character": 0}, "end": {"line": n, "character": 0}},
                        "newText": r.text}])
    else:
      if isRequest: respondError(id, -32601, "méthode non prise en charge : " & meth)
  except CatchableError as e:
    if isRequest: respondError(id, -32603, "erreur interne : " & e.msg)

proc runLspServer*() =
  initLangDocs()
  var s = Server()
  while true:
    let (ok, msg) = readMessage()
    if not ok: break
    if s.ws.isNil and msg.kind == JObject and msg{"method"}.getStr notin ["initialize"]:
      s.ws = newWorkspace(getCurrentDir())
    s.handle(msg)
