# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# Récursion trop profonde : erreur Lexis+ interceptable, jamais d'arrêt brutal du
# processus (garde d'appels de Nim) ni de débordement de pile. Chaque programme
# s'exécute dans un fil de 2 Mo de pile, comme dans l'atelier (fils de wdgui).
#   nim c -r -d:release tests/t_recursion.nim
import std/[strutils, typedthreads]
import ../src/lexis/[api, fonctions]

const progs = [
  ("factorielle", """
? FACT(100000)

fonction FACT(n)
  si n <= 1
    retourner 1
  sinon
    retourner n * FACT(n - 1.0)
  finsi
finfonction
"""),
  ("récursion infinie", """
? F(1)

fonction F(n)
retourner F(n + 1)
"""),
  ("récursion lourde (essayer, méthodes, expressions)", """
Compte = {}
Compte.__index = Compte
Compte:procedure DESCENDRE comme descendre
c = fixermetatable({}, Compte)
? c:descendre(1)

fonction DESCENDRE(soi, n)
  essayer
    locale t = {a = {b = {c = n}}}
    retourner ((((t.a.b.c + 1) * 2 - 2) / 2) + sisinon(n > 0, soi:descendre(n + 1), 0))
  capturer e
    erreur e
  finessayer
retourner 0
"""),
  ("interceptée par essayer", """
essayer
  F(1)
capturer e
  ? "OK intercepté : " + e
finessayer

fonction F(n)
retourner F(n + 1)
""")]

var results: array[progs.len, string]

proc runOne(i: int) {.thread.} =
  {.cast(gcsafe).}:
    let L = newFullInterp()
    var outp = ""
    L.output = proc (s: string) = outp.add s
    L.enter()
    curCtx = Ctx()
    try:
      discard L.runMain(L.load(progs[i][1], progs[i][0] & ".prg"), @[])
      results[i] = "fin normale : " & outp.strip
    except LexisError as e:
      results[i] = "erreur Lexis+ : " & e.msg
    L.shutdown()
    L.leave()

var failed = false
for i in 0 ..< progs.len:
  var th: Thread[int]
  createThread(th, runOne, i)
  joinThread(th)
  echo progs[i][0], " -> ", results[i]
  let ok = if i == 3: results[i].contains("OK intercepté") else: results[i].startsWith("erreur Lexis+")
  if not ok: failed = true
if failed: quit 1
echo "récursion : OK"
