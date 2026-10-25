# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - chaîne de génération des applications (Zig embarqué)
#
# Utilisée par la boîte « Générer l'application » (ide/generer.nim) et par
# l'outil en ligne de commande wdlexisgen. Sans interface graphique.
#
# Pour chaque cible cochée :
#   1. transpilation du projet en C : projet.c contient les sources .prg
#      (embrouillées), le type d'application et la fonction main() ;
#   2. compilation C par Zig (zig cc) du runtime pré-transpilé (dossier rtc/)
#      et de projet.c, en parallèle, avec un cache d'objets ;
#   3. édition des liens (exécutable, bibliothèque partagée, icône Windows) ;
#   4. icône (.ico, .icns, .png) et paquet macOS (.app) ;
#   5. distribution : dossier ou archive (.zip pour Windows, .tar.gz sinon),
#      fichiers du projet, bibliothèques (linOS / macOS / winOS, ttf),
#      liste des modèles (paquets d'IA), fichiers de service, en-tête C.
#
# Organisation de wdlexis+ (à côté de l'exécutable de l'atelier) :
#   linZG/ macZG/ winZG/   Zig pour l'hôte : <arch>/zig[.exe] et lib/
#   rtc/                   runtime C (voir outils/rtc.nim)
#   linOS/ macOS/ winOS/   bibliothèques (SDL3, DuckDB, webview...), ttf/, models/

import std/[os, osproc, strutils, sets, tables, times, algorithm, monotimes, atomics,
            locks, typedthreads, streams]
import ../lexis/lexer
from ../lexis/parser import parseChunk
import imagetools, archives

type
  AppType* = enum
    atConsole = "console", atGraphique = "graphique", atService = "service",
    atBibliotheque = "bibliotheque"

  Target* = enum
    tgLinuxX64 = "linux-x64", tgLinuxArm64 = "linux-arm64",
    tgMacX64 = "macos-x64", tgMacArm64 = "macos-arm64",
    tgWinX64 = "windows-x64", tgWinArm64 = "windows-arm64"

  DistMode* = enum dmFolder = "dossier", dmArchive = "archive"

  BuildSettings* = object
    appType*: AppType
    targets*: set[Target]
    dist*: DistMode
    bundleLibs*: bool
    iconPath*: string            # image source de l'icône ("" = aucune).
    crop*: Crop                  # cadrage retenu dans l'image.

  ProjectInfo* = object
    root*: string                # dossier du projet (absolu).
    name*: string                # nom de l'application (fichiers, service...).
    mainRel*: string             # fichier principal, relatif au projet.
    prgFiles*: seq[string]       # sources .prg (relatifs, séparateur « / »).
    dataFiles*: seq[string]      # autres fichiers copiés dans la distribution.
    packages*: seq[string]       # paquets utilisés (par nom ou par paquet("...")).
    usesUi*: bool                # paquet « interface » (wdgui).
    usesIa*: bool                # paquets d'IA à modèles (llm, gguf, entrainement).

  LogKind* = enum
    lgStep                       # libellé d'étape (jaune).
    lgCommand                    # commande lancée.
    lgOutput                     # message capturé (blanc).
    lgWarning                    # avertissement (orange).
    lgError                      # erreur (rouge).
    lgDone                       # étape terminée, avec sa durée (vert).
    lgFinal                      # génération terminée.

  BuildHooks* = object
    log*: proc (kind: LogKind, text: string) {.gcsafe.}
    progress*: proc (fraction: float, label: string) {.gcsafe.}
    cancelled*: proc (): bool {.gcsafe.}

const
  OutputDirName* = "distribution"
  SettingsRel* = ".wdlexis" / "application.ini"
  IaPackages* = ["llm", "gguf", "entrainement"]
  UiPackage* = "interface"
  AllTargets* = [tgLinuxX64, tgLinuxArm64, tgMacX64, tgMacArm64, tgWinX64, tgWinArm64]
  HuggingFace = "https://huggingface.co"

proc label*(t: Target): string =
  case t
  of tgLinuxX64: "Linux x64"
  of tgLinuxArm64: "Linux arm64"
  of tgMacX64: "macOS x64"
  of tgMacArm64: "macOS Mx"
  of tgWinX64: "Windows x64"
  of tgWinArm64: "Windows arm64"

proc label*(a: AppType): string =
  case a
  of atConsole: "Console"
  of atGraphique: "Graphique"
  of atService: "Service"
  of atBibliotheque: "Bibliothèque"

proc isWindows*(t: Target): bool = t in {tgWinX64, tgWinArm64}
proc isMac*(t: Target): bool = t in {tgMacX64, tgMacArm64}
proc isLinux*(t: Target): bool = t in {tgLinuxX64, tgLinuxArm64}
proc isArm*(t: Target): bool = t in {tgLinuxArm64, tgMacArm64, tgWinArm64}

proc zigTriple*(t: Target): string =
  case t
  of tgLinuxX64: "x86_64-linux-gnu.2.28"
  of tgLinuxArm64: "aarch64-linux-gnu.2.28"
  of tgMacX64: "x86_64-macos.11.0"
  of tgMacArm64: "aarch64-macos.11.0"
  of tgWinX64: "x86_64-windows-gnu"
  of tgWinArm64: "aarch64-windows-gnu"

proc osLibDir*(t: Target): string =
  # Dossier des bibliothèques de wdlexis+ pour le système de la cible.
  if t.isWindows: "winOS" elif t.isMac: "macOS" else: "linOS"

proc archDir(t: Target): string = (if t.isArm: "arm64" else: "x64")

proc defaultSettings*(info: ProjectInfo): BuildSettings =
  result.appType = if info.usesUi: atGraphique else: atConsole
  result.dist = dmFolder
  result.bundleLibs = true
  result.crop = fullCrop()
  when defined(windows): result.targets = {tgWinX64}
  elif defined(macosx): result.targets = (when defined(arm64): {tgMacArm64} else: {tgMacX64})
  else: result.targets = (when defined(arm64): {tgLinuxArm64} else: {tgLinuxX64})

#
# Analyse du projet
#

proc safeName*(s: string): string =
  ## Nom de fichier portable (ASCII, sans espace) tiré du nom du dossier.
  const accents = [("à", "a"), ("â", "a"), ("ä", "a"), ("é", "e"), ("è", "e"), ("ê", "e"),
                   ("ë", "e"), ("î", "i"), ("ï", "i"), ("ô", "o"), ("ö", "o"), ("ù", "u"),
                   ("û", "u"), ("ü", "u"), ("ç", "c"), ("ÿ", "y"), ("æ", "ae"), ("œ", "oe"),
                   ("À", "A"), ("Â", "A"), ("É", "E"), ("È", "E"), ("Ê", "E"), ("Î", "I"),
                   ("Ô", "O"), ("Ù", "U"), ("Û", "U"), ("Ç", "C")]
  var t = s
  for (a, b) in accents: t = t.replace(a, b)
  for c in t:
    if c in {'A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.'}: result.add c
    elif c == ' ': result.add '_'
  result = result.strip(chars = {'.', '-', '_'})
  if result.len == 0: result = "application"

proc detectPackages(src: string, known: HashSet[string], found: var HashSet[string]) =
  var toks: seq[Tok]
  try: toks = tokenize(src, "")
  except SyntaxError: return
  for i, t in toks:
    if t.kind != tkName: continue
    let low = t.text.toLowerAscii
    if low == "paquet" and i + 2 < toks.len and toks[i + 1].kind == tkOp and toks[i + 1].text == "(" and
       toks[i + 2].kind == tkStr:
      found.incl toks[i + 2].text.toLowerAscii
    elif low in known and i + 1 < toks.len and toks[i + 1].kind == tkOp and toks[i + 1].text in [".", ":"]:
      # « ui.fenetre » où ui est un nom de paquet : utilisation par son nom.
      if i == 0 or not (toks[i - 1].kind == tkOp and toks[i - 1].text in [".", ":"]):
        found.incl low

proc analyzeProject*(root0: string, mainRel = "", knownPackages: openArray[string] = []): ProjectInfo =
  ## Inventaire du projet : sources, fichiers à distribuer, paquets utilisés.
  let root = normalizedPath(absolutePath(root0))
  result.root = root
  result.name = safeName(extractFilename(root))
  result.mainRel = if mainRel.len > 0: mainRel.replace('\\', '/') else: "principal.prg"
  var known = initHashSet[string]()
  for p in knownPackages: known.incl p.toLowerAscii
  if known.len == 0:
    for p in ["interface", "llm", "gguf", "entrainement", "dessin", "audio", "tenseur", "fichier",
              "json", "csv", "binaire", "http", "reseau", "ftp", "ssh", "sftp", "sqlite",
              "firebird", "tache", "fil", "webview"]: known.incl p
  if not dirExists(root): return
  var found = initHashSet[string]()
  var files: seq[string]
  for f in walkDirRec(root, relative = true):
    let rel = f.replace('\\', '/')
    if rel.startsWith(".") or "/." in rel: continue
    if rel == OutputDirName or rel.startsWith(OutputDirName & "/"): continue
    files.add rel
  files.sort()
  for rel in files:
    if rel.toLowerAscii.endsWith(".prg"):
      result.prgFiles.add rel
      try: detectPackages(readFile(root / rel), known, found)
      except IOError, OSError: discard
    else:
      result.dataFiles.add rel
  if result.mainRel notin result.prgFiles and result.prgFiles.len > 0 and
     "principal.prg" in result.prgFiles:
    result.mainRel = "principal.prg"
  for p in found: result.packages.add p
  result.packages.sort()
  result.usesUi = UiPackage in found
  for p in IaPackages:
    if p in found: result.usesIa = true

#
# Paramètres du projet (.wdlexis/application.ini)
#

proc loadSettings*(info: ProjectInfo): BuildSettings =
  result = defaultSettings(info)
  let path = info.root / SettingsRel
  if not fileExists(path): return
  var targetsSeen = false
  var targets: set[Target]
  for line in readFile(path).splitLines:
    let p = line.find('=')
    if p <= 0 or line.strip.startsWith("#"): continue
    let k = line[0 ..< p].strip.toLowerAscii
    let v = line[p + 1 .. ^1].strip
    case k
    of "type":
      for a in AppType:
        if $a == v: result.appType = a
    of "cibles":
      targetsSeen = true
      for c in v.split(','):
        for t in Target:
          if $t == c.strip: targets.incl t
    of "distribution": result.dist = (if v == "archive": dmArchive else: dmFolder)
    of "bibliotheques": result.bundleLibs = v in ["1", "oui", "vrai"]
    of "icone":
      result.iconPath = if v.len == 0 or isAbsolute(v): v else: info.root / v
    of "cadrage":
      let n = v.split(',')
      if n.len == 3:
        try: result.crop = Crop(left: parseFloat(n[0]), top: parseFloat(n[1]), side: parseFloat(n[2]))
        except ValueError: discard
    else: discard
  if targetsSeen: result.targets = targets
  if info.usesUi: result.appType = atGraphique

proc saveSettings*(info: ProjectInfo, s: BuildSettings) =
  var icon = s.iconPath
  if icon.len > 0 and icon.startsWith(info.root & DirSep): icon = relativePath(icon, info.root).replace('\\', '/')
  var cibles: seq[string]
  for t in AllTargets:
    if t in s.targets: cibles.add $t
  let txt = "# wdlexis+ : paramètres de génération de l'application\n" &
    "type=" & $s.appType & "\n" &
    "cibles=" & cibles.join(",") & "\n" &
    "distribution=" & $s.dist & "\n" &
    "bibliotheques=" & (if s.bundleLibs: "1" else: "0") & "\n" &
    "icone=" & icon & "\n" &
    "cadrage=" & formatFloat(s.crop.left, ffDecimal, 5) & "," & formatFloat(s.crop.top, ffDecimal, 5) &
      "," & formatFloat(s.crop.side, ffDecimal, 5) & "\n"
  createDir(info.root / ".wdlexis")
  writeFile(info.root / SettingsRel, txt)

#
# Emplacements de la toolchain
#

proc hostZigDir*(appDir: string): string =
  when defined(windows): appDir / "winZG"
  elif defined(macosx): appDir / "macZG"
  else: appDir / "linZG"

proc findZig*(appDir: string): tuple[exe, libDir, err: string] =
  ## Zig embarqué pour l'hôte : <OS>ZG/<arch>/zig (+ <OS>ZG/lib), ou <OS>ZG/zig.
  let exeName = when defined(windows): "zig.exe" else: "zig"
  let base = hostZigDir(appDir)
  var archs: seq[string]
  when defined(arm64): archs = @["aarch64", "x86_64"]   # x86_64 : émulation (Rosetta, Windows on Arm)
  else: archs = @["x86_64"]
  var cands: seq[string]
  for a in archs: cands.add base / a / exeName
  cands.add base / exeName
  let env = getEnv("WDLEXIS_ZIG")
  if env.len > 0: cands.insert(env, 0)
  for c in cands:
    if fileExists(c):
      var lib = ""
      for l in [c.parentDir / "lib", c.parentDir.parentDir / "lib"]:
        if fileExists(l / "std" / "std.zig"):
          lib = l
          break
      if lib.len == 0:
        return (c, "", "bibliothèque de Zig introuvable (dossier lib/ à côté de " & c & ")")
      return (c, lib, "")
  ("", "", "Zig introuvable : " & base & DirSep & archs[0] & DirSep & exeName &
           " (dossier " & extractFilename(base) & " de wdlexis+)")

proc findRtc*(appDir: string): string =
  for d in [appDir / "rtc", appDir.parentDir / "rtc", getEnv("WDLEXIS_RTC")]:
    if d.len > 0 and dirExists(d / "pool"): return d
  ""

#
# Durées
#

proc fmtDuration*(d: Duration): string =
  let ms = d.inMilliseconds
  if ms < 1000: $ms & " ms"
  else: formatFloat(float(ms) / 1000.0, ffDecimal, 1) & " s"

proc fmtClock*(d: Duration): string =
  let s = d.inSeconds
  align($(s div 60), 2, '0') & ":" & align($(s mod 60), 2, '0')

#
# Exécution parallèle des commandes (zig cc), interruptible
#

type
  Job = object
    exe: string
    args: seq[string]
    display: string
    tmpOut, finalOut: string     # objet du cache : renommé dès que la commande réussit.
  JobEventKind = enum jeStarted, jeFinished
  JobEvent = object
    kind: JobEventKind
    idx, code: int
    output: string

var
  rJobs: seq[Job]
  rNext: Atomic[int]
  rCancel: Atomic[bool]
  rChan: Channel[JobEvent]
  rLock: Lock
  rProcs: seq[Process]
initLock(rLock)

proc worker(slot: int) {.thread.} =
  {.cast(gcsafe).}:
    while not rCancel.load():
      let i = rNext.fetchAdd(1)
      if i >= rJobs.len: break
      let j = rJobs[i]
      rChan.send JobEvent(kind: jeStarted, idx: i)
      var code = -1
      var output = ""
      try:
        let p = startProcess(j.exe, args = j.args, options = {poStdErrToStdOut})
        withLock rLock: rProcs[slot] = p
        output = p.outputStream.readAll()
        code = p.waitForExit()
        withLock rLock: rProcs[slot] = nil
        p.close()
      except CatchableError as e:
        output = "lancement impossible : " & j.exe & " (" & e.msg & ")"
        code = -1
      rChan.send JobEvent(kind: jeFinished, idx: i, code: code, output: output)

proc classify(line: string): LogKind =
  let l = line.toLowerAscii
  if "error:" in l or "erreur" in l or l.startsWith("error"): lgError
  elif "warning:" in l or l.startsWith("warning"): lgWarning
  else: lgOutput

type Progress = ref object
  total, done: float
  label: string

proc runJobs(jobs: seq[Job], hooks: BuildHooks, prog: Progress, weight = 1.0,
             showOutputOk = true): bool =
  # Lance les commandes (en parallèle) ; false si l'une échoue ou si l'on annule.
  if jobs.len == 0: return true
  {.cast(gcsafe).}:
    rJobs = jobs
    rNext.store(0)
    rCancel.store(false)
    # Nim 2.2 (ARC/ORC) : close() libère le tampon du canal sans remettre
    # data/count/rd/wr à zéro, et open() ne les réinitialise pas. Au second
    # runJobs (édition des liens après la compilation), le premier send
    # agrandissait la file et libérait une seconde fois l'ancien tampon :
    # double libération, tas corrompu (plantage malloc sur macOS, dans
    # startProcess ou le cache de textes de l'interface). On repart d'un
    # canal entièrement remis à zéro.
    zeroMem(addr rChan, sizeof(rChan))
    rChan.open()
    let n = max(1, min(jobs.len, countProcessors()))
    rProcs = newSeq[Process](n)
    var threads = newSeq[Thread[int]](n)
    for i in 0 ..< n: createThread(threads[i], worker, i)
    var failed = false
    proc handle(ev: JobEvent) =
      case ev.kind
      of jeStarted:
        if not failed: hooks.log(lgCommand, jobs[ev.idx].display)
      of jeFinished:
        prog.done += weight
        hooks.progress(min(1.0, prog.done / prog.total), prog.label)
        let outText = ev.output.strip(leading = false)
        if ev.code != 0:
          if not failed:
            for line in outText.splitLines:
              if line.len > 0:
                let k = classify(line)
                hooks.log(if k == lgOutput: lgError else: k, line)
            hooks.log(lgError, "échec (code " & $ev.code & ") : " & jobs[ev.idx].display)
          failed = true
          rCancel.store(true)    # plus aucune nouvelle commande.
        else:
          let j = jobs[ev.idx]
          if j.tmpOut.len > 0 and fileExists(j.tmpOut):
            try: moveFile(j.tmpOut, j.finalOut) except OSError: discard
          if outText.len > 0 and showOutputOk and not failed:
            for line in outText.splitLines:
              if line.len > 0: hooks.log(classify(line), line)
    while true:
      if not failed and hooks.cancelled():
        failed = true
        rCancel.store(true)
        withLock rLock:
          for p in rProcs:
            if p != nil:
              try: p.kill() except CatchableError: discard
      let (ok, ev) = rChan.tryRecv()
      if ok:
        handle(ev)
        continue
      var alive = false
      for t in threads:
        if t.running: alive = true
      if not alive:
        while true:
          let (ok2, ev2) = rChan.tryRecv()
          if not ok2: break
          handle(ev2)
        break
      sleep(10)
    for t in threads.mitems: joinThread(t)
    rChan.close()
    zeroMem(addr rChan, sizeof(rChan))
    rProcs.setLen(0)
    result = not failed

#
# Projet embarqué (projet.c)
#

proc scramble(data: var string) =
  # Même suite que unscramble() de wdlexisapp.nim.
  var k = 0x5EED1234'u32
  for i in 0 ..< data.len:
    k = k xor (k shl 13)
    k = k xor (k shr 17)
    k = k xor (k shl 5)
    data[i] = char(uint8(ord(data[i])) xor uint8(k and 0xFF))

proc bundleBytes*(info: ProjectInfo, s: BuildSettings, t: Target): string =
  proc u32(r: var string, v: int) =
    for i in 0 .. 3: r.add char((v shr (8 * i)) and 0xFF)
  var entries: seq[(string, string)] = @[("@type", $s.appType), ("@nom", info.name),
    ("@principal", info.mainRel), ("@cible", $t)]
  for f in info.prgFiles: entries.add ("prg:" & f, readFile(info.root / f))
  result = "WDLXB1"
  result.u32 entries.len
  for (k, v) in entries:
    result.u32 k.len
    result.add k
    result.u32 v.len
    result.add v
  scramble(result)

const ProjetCTemplate = """/* projet.c - généré par wdlexis+ ($DATE) : ne pas modifier.
   Application « $NAME » ($TYPE, $TARGET).
   Contient le projet Lexis+ et le point d'entrée ;
   le runtime Lexis+ (rtc/) est compilé à part par Zig. */
#if !defined(_WIN32) && !defined(__APPLE__)
#  define _GNU_SOURCE
#endif
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#if defined(_WIN32)
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  include <windows.h>
#else
#  include <dlfcn.h>
#  include <unistd.h>
#  include <limits.h>
#  include <sys/stat.h>
#  include <pthread.h>
#  if defined(__APPLE__)
#    include <mach-o/dyld.h>
#  endif
#endif

#define WDLX_LIB $LIB
#define WDLX_GUI_SUBSYSTEM $GUISUB

static const unsigned char wdlx_data[$SIZE] = {
$DATA
};
const unsigned char *wdlx_bundle_data(void) { return wdlx_data; }
size_t wdlx_bundle_size(void) { return sizeof wdlx_data; }

static char wdlx_base[4096];
const char *wdlx_base_dir(void) { return wdlx_base; }

extern void NimMain(void);

static void wdlx_prepare(void) {
#if defined(_WIN32)
  wchar_t w[4096];
  HMODULE m = NULL;
#  if WDLX_LIB
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     (LPCWSTR)(void *)&wdlx_prepare, &m);
#  endif
  DWORD n = GetModuleFileNameW(m, w, 4096);
  if (n == 0 || n >= 4096) return;
  w[n] = 0;
  wchar_t *s = wcsrchr(w, L'\\');
  if (s) *s = 0;
  WideCharToMultiByte(CP_UTF8, 0, w, -1, wdlx_base, (int)sizeof wdlx_base, NULL, NULL);
  if (_wgetenv(L"WDGUI_PATH") == NULL) {
    _wputenv_s(L"WDGUI_PATH", w);
    SetEnvironmentVariableW(L"WDGUI_PATH", w);
  }
#else
  char path[4096];
  path[0] = 0;
#  if WDLX_LIB
  Dl_info info;
  if (dladdr((void *)&wdlx_prepare, &info) && info.dli_fname) {
    if (realpath(info.dli_fname, path) == NULL) snprintf(path, sizeof path, "%s", info.dli_fname);
  }
#  elif defined(__APPLE__)
  char raw[4096];
  uint32_t size = sizeof raw;
  if (_NSGetExecutablePath(raw, &size) == 0) {
    if (realpath(raw, path) == NULL) snprintf(path, sizeof path, "%s", raw);
  }
#  else
  ssize_t n = readlink("/proc/self/exe", path, sizeof path - 1);
  path[n > 0 ? n : 0] = 0;
#  endif
  char *s = strrchr(path, '/');
  if (s) *s = 0;
#  if defined(__APPLE__)
  {
    const char *suffix = "/Contents/MacOS";
    size_t l = strlen(path), k = strlen(suffix);
    if (l > k && strcmp(path + l - k, suffix) == 0) {
      char res[4096];
      struct stat st;
      snprintf(res, sizeof res, "%.*s/Contents/Resources", (int)(l - k), path);
      if (stat(res, &st) == 0) snprintf(path, sizeof path, "%s", res);
    }
  }
#  endif
  snprintf(wdlx_base, sizeof wdlx_base, "%s", path);
  if (wdlx_base[0] && getenv("WDGUI_PATH") == NULL) setenv("WDGUI_PATH", wdlx_base, 1);
#endif
}

#if WDLX_LIB
/* Bibliothèque : le runtime est initialisé au premier appel (une seule fois). */
#  if defined(_WIN32)
#    define WDLX_API __declspec(dllexport)
static INIT_ONCE wdlx_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK wdlx_init_cb(PINIT_ONCE o, PVOID p, PVOID *c) {
  (void)o; (void)p; (void)c;
  wdlx_prepare();
  NimMain();
  return TRUE;
}
static void wdlx_init(void) { InitOnceExecuteOnce(&wdlx_once, wdlx_init_cb, NULL, NULL); }
#  else
#    define WDLX_API __attribute__((visibility("default")))
static pthread_once_t wdlx_once = PTHREAD_ONCE_INIT;
static void wdlx_init_cb(void) { wdlx_prepare(); NimMain(); }
static void wdlx_init(void) { pthread_once(&wdlx_once, wdlx_init_cb); }
#  endif
int cmdCount = 0;
char **cmdLine = NULL;
char **gEnv = NULL;
extern int wdlx_lib_initialiser(void);
extern char *wdlx_lib_appeler(const char *procedure, const char *args_json);
extern void wdlx_lib_liberer(char *s);
extern const char *wdlx_lib_erreur(void);
extern void wdlx_lib_terminer(void);
extern const char *wdlx_lib_version(void);
WDLX_API int wdlexis_initialiser(void) { wdlx_init(); return wdlx_lib_initialiser(); }
WDLX_API char *wdlexis_appeler(const char *procedure, const char *args_json) {
  wdlx_init();
  return wdlx_lib_appeler(procedure, args_json);
}
WDLX_API void wdlexis_liberer(char *s) { wdlx_init(); wdlx_lib_liberer(s); }
WDLX_API const char *wdlexis_derniere_erreur(void) { wdlx_init(); return wdlx_lib_erreur(); }
WDLX_API void wdlexis_terminer(void) { wdlx_init(); wdlx_lib_terminer(); }
WDLX_API const char *wdlexis_version(void) { wdlx_init(); return wdlx_lib_version(); }
#else
/* Exécutable. */
extern int wdlx_main(void);
int cmdCount;
char **cmdLine;
char **gEnv;
int main(int argc, char **argv, char **envp) {
  cmdCount = argc;
  cmdLine = argv;
  gEnv = envp;
  wdlx_prepare();
  NimMain();
  return wdlx_main();
}
#  if defined(_WIN32) && WDLX_GUI_SUBSYSTEM
int WINAPI WinMain(HINSTANCE a, HINSTANCE b, LPSTR c, int d) {
  (void)a; (void)b; (void)c; (void)d;
  return main(__argc, __argv, _environ);
}
#  endif
#endif
"""

proc projetC*(info: ProjectInfo, s: BuildSettings, t: Target): string =
  let data = bundleBytes(info, s, t)
  var arr = newStringOfCap(data.len * 5)
  for i, c in data:
    if i mod 24 == 0:
      if i > 0: arr.add "\n"
      arr.add "  "
    arr.add $ord(c)
    arr.add ','
  if data.len == 0: arr = "  0"
  result = ProjetCTemplate.multiReplace(
    ("$DATE", now().format("yyyy-MM-dd HH:mm")), ("$NAME", info.name), ("$TYPE", $s.appType),
    ("$TARGET", $t), ("$LIB", if s.appType == atBibliotheque: "1" else: "0"),
    ("$GUISUB", if s.appType == atGraphique: "1" else: "0"),
    ("$SIZE", $max(1, data.len)), ("$DATA", arr))

#
# Runtime C : manifestes
#

type Manifest = object
  cflags, ldflags: seq[string]
  files: seq[tuple[hash, name: string]]

proc variantFor(s: BuildSettings, info: ProjectInfo): string =
  if info.usesUi: "gui" else: "cli"

proc readManifest(rtc: string, t: Target, variant: string): Manifest =
  let path = rtc / ($t & "-" & variant & ".txt")
  if not fileExists(path): raise newException(IOError, "manifeste du runtime introuvable : " & path)
  for line in readFile(path).splitLines:
    if line.len == 0 or line.startsWith("#"): continue
    if line.startsWith("cflags:"): result.cflags = line[7 .. ^1].splitWhitespace
    elif line.startsWith("ldflags:"):
      for f in line[8 .. ^1].splitWhitespace:
        if (f.startsWith("-l") or f == "-pthread") and f in result.ldflags: continue
        result.ldflags.add f
    else:
      let p = line.find(' ')
      if p > 0: result.files.add (line[0 ..< p], line[p + 1 .. ^1])

proc fnv(s: string): string =
  var h = 0xcbf29ce484222325'u64
  for c in s: h = (h xor uint64(ord(c))) * 0x100000001b3'u64
  toHex(h).toLowerAscii

#
# Bibliothèques : contrôle de l'architecture (ELF, PE, Mach-O)
#

proc binaryArch*(path: string): string =
  ## "x64", "arm64", "universel", "?" (non reconnu) ; "" si ce n'est pas un binaire.
  var f: File
  if not open(f, path): return ""
  defer: f.close()
  var h: array[64, uint8]
  let n = f.readBytes(h, 0, 64)
  if n < 20: return ""
  if h[0] == 0x7F and h[1] == ord('E') and h[2] == ord('L') and h[3] == ord('F'):
    let m = int(h[18]) or (int(h[19]) shl 8)
    return (if m == 0x3E: "x64" elif m == 0xB7: "arm64" else: "?")
  let magic = uint32(h[0]) or (uint32(h[1]) shl 8) or (uint32(h[2]) shl 16) or (uint32(h[3]) shl 24)
  if magic == 0xFEEDFACF'u32:
    let cpu = uint32(h[4]) or (uint32(h[5]) shl 8) or (uint32(h[6]) shl 16) or (uint32(h[7]) shl 24)
    return (if cpu == 0x01000007'u32: "x64" elif cpu == 0x0100000C'u32: "arm64" else: "?")
  if magic == 0xBEBAFECA'u32: return "universel"
  if h[0] == ord('M') and h[1] == ord('Z'):
    let pe = int(h[60]) or (int(h[61]) shl 8) or (int(h[62]) shl 16) or (int(h[63]) shl 24)
    var b: array[6, uint8]
    f.setFilePos(pe)
    if f.readBytes(b, 0, 6) == 6 and b[0] == ord('P') and b[1] == ord('E'):
      let m = int(b[4]) or (int(b[5]) shl 8)
      return (if m == 0x8664: "x64" elif m == 0xAA64: "arm64" else: "?")
  ""

proc isLibFor(name: string, t: Target): bool =
  let l = name.toLowerAscii
  if t.isWindows: l.endsWith(".dll")
  elif t.isMac: l.endsWith(".dylib")
  else: l.endsWith(".so") or ".so." in l

#
# Textes générés
#

proc modelsText*(appDir: string): string =
  var models: seq[string]
  var links: seq[string]
  let dir = appDir / "models"
  if dirExists(dir):
    for f in walkDir(dir):
      let n = extractFilename(f.path)
      if n.toLowerAscii.endsWith(".gguf"):
        var size = ""
        try: size = " (" & formatSize(getFileSize(f.path), includeSpace = true) & ")"
        except OSError: discard
        models.add n & size
      elif n.toLowerAscii.endsWith(".gguf.md"):
        for line in readFile(f.path).splitLines:
          let p = line.find("https://")
          if p >= 0: links.add n[0 ..< n.len - 3] & " : " & line[p .. ^1].strip
  models.sort()
  result = "Modèles GGUF utilisables par cette application\n" &
           "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n\n"
  if models.len == 0 and links.len == 0:
    result.add "(aucun modèle dans le dossier « models » de wdlexis+ lors de la génération)\n"
  for m in models: result.add "- " & m & "\n"
  if links.len > 0:
    result.add "\nEmplacements indiqués :\n"
    for l in links: result.add "- " & l & "\n"
  result.add "\nPlacez le ou les fichiers .gguf dans ce dossier « models ».\n\n" &
    "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n" &
    "Les modèles sont disponibles sur " & HuggingFace & " .\n" &
    "Il convient d'y créer un compte pour pouvoir les télécharger et de ne les\n" &
    "utiliser que dans le cadre de leur licence respective, uniquement après avoir\n" &
    "déclaré la nature de leur usage dans le projet, accepté leur licence respective\n" &
    "et obtenu l'accord de leurs propriétaires.\n"

proc headerText(name: string): string =
  let g = name.toUpperAscii.multiReplace(("-", "_"), (".", "_"))
  "/* " & name & ".h - bibliothèque générée par wdlexis+ (application Lexis+).\n\n" &
  "   Les procédures et fonctions du projet s'appellent par leur nom ; arguments et\n" &
  "   résultat sont échangés en JSON (tableau d'arguments, résultat JSON).\n\n" &
  "     wdlexis_initialiser();                       facultatif : exécute l'en-tête du\n" &
  "                                                  fichier principal (0 = succès)\n" &
  "     char *r = wdlexis_appeler(\"CARRE\", \"[12]\");  r = \"144\" (NULL en cas d'erreur)\n" &
  "     wdlexis_liberer(r);\n" &
  "     wdlexis_derniere_erreur();                   message de la dernière erreur\n" &
  "     wdlexis_terminer();                          libère l'interpréteur\n*/\n" &
  "#ifndef " & g & "_H\n#define " & g & "_H\n\n" &
  "#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n" &
  "#if defined(_WIN32)\n#  define WDLEXIS_IMPORT __declspec(dllimport)\n#else\n#  define WDLEXIS_IMPORT\n#endif\n\n" &
  "WDLEXIS_IMPORT int wdlexis_initialiser(void);\n" &
  "WDLEXIS_IMPORT char *wdlexis_appeler(const char *procedure, const char *arguments_json);\n" &
  "WDLEXIS_IMPORT void wdlexis_liberer(char *resultat);\n" &
  "WDLEXIS_IMPORT const char *wdlexis_derniere_erreur(void);\n" &
  "WDLEXIS_IMPORT void wdlexis_terminer(void);\n" &
  "WDLEXIS_IMPORT const char *wdlexis_version(void);\n\n" &
  "#ifdef __cplusplus\n}\n#endif\n\n#endif\n"

proc infoPlist(name, exe: string, hasIcon: bool): string =
  let id = "wdlexis.app." & name.toLowerAscii.multiReplace(("_", "-"))
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" &
  "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" &
  "<plist version=\"1.0\">\n<dict>\n" &
  "  <key>CFBundleName</key><string>" & name & "</string>\n" &
  "  <key>CFBundleDisplayName</key><string>" & name & "</string>\n" &
  "  <key>CFBundleExecutable</key><string>" & exe & "</string>\n" &
  "  <key>CFBundleIdentifier</key><string>" & id & "</string>\n" &
  "  <key>CFBundlePackageType</key><string>APPL</string>\n" &
  "  <key>CFBundleShortVersionString</key><string>1.0</string>\n" &
  "  <key>CFBundleVersion</key><string>1</string>\n" &
  "  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>\n" &
  (if hasIcon: "  <key>CFBundleIconFile</key><string>" & name & ".icns</string>\n" else: "") &
  "  <key>LSMinimumSystemVersion</key><string>11.0</string>\n" &
  "  <key>NSHighResolutionCapable</key><true/>\n" &
  "</dict>\n</plist>\n"

proc readmeText(info: ProjectInfo, s: BuildSettings, t: Target, exe: string): string =
  result = info.name & " - application Lexis+ générée par wdlexis+\n" &
    repeat('=', info.name.len + 41) & "\n\n" &
    "Type : " & s.appType.label & "      Cible : " & t.label & "\n" &
    "Générée le " & now().format("dd/MM/yyyy") & " à " & now().format("HH:mm") & "\n\n"
  case s.appType
  of atConsole:
    result.add "Lancement : " & (if t.isWindows: exe else: "./" & exe) & " [arguments]\n"
  of atGraphique:
    if t.isMac: result.add "Lancement : ouvrir " & exe & " (double-clic).\n"
    else: result.add "Lancement : " & (if t.isWindows: exe & " (double-clic)" else: "./" & exe) & "\n"
  of atService:
    if t.isWindows: result.add "Installation du service : installer-service.cmd (en administrateur).\n" &
                               "Les sorties du programme sont écrites dans " & info.name & ".log.\n"
    elif t.isMac: result.add "Installation du service : sudo ./installer-service.sh (launchd).\n"
    else: result.add "Installation du service : sudo ./installer-service.sh (systemd).\n"
    result.add "Le programme peut aussi être lancé directement depuis un terminal.\n"
  of atBibliotheque:
    result.add "Bibliothèque partagée : " & exe & " ; en-tête C : " & info.name & ".h\n"
  if t.isMac:
    result.add "\nmacOS : si le système refuse d'ouvrir l'application téléchargée,\n" &
      "  xattr -dr com.apple.quarantine " & exe & "\n"
  if t.isLinux and s.appType == atGraphique:
    result.add "\nLinux : un fichier " & info.name & ".desktop est fourni pour le menu des applications\n" &
      "(./installer-bureau.sh l'installe pour l'utilisateur courant).\n"
  result.add "\nLe runtime Lexis+ est soumis à la licence de wdlexis+ ; les bibliothèques\n" &
    "fournies (dossier LICENCES) à leur licence respective.\n"

#
# Génération
#

type BuildError = object of CatchableError

proc build*(info: ProjectInfo, s: BuildSettings, appDir: string, hooks: BuildHooks): bool =
  # Génère l'application pour chaque cible ; false en cas d'erreur ou d'annulation.
  let t0 = getMonoTime()
  var prog = Progress(total: 1, done: 0)
  var stepStart: MonoTime
  var stepName = ""

  proc step(name: string) =
    stepName = name
    stepStart = getMonoTime()
    prog.label = name
    hooks.progress(prog.done / prog.total, name)
    hooks.log(lgStep, name)

  proc stepDone(msg = "") =
    hooks.log(lgDone, (if msg.len > 0: msg else: stepName & " : terminé") &
                      " [" & fmtDuration(getMonoTime() - stepStart) & "]")

  proc fail(msg: string) {.noreturn.} =
    raise newException(BuildError, msg)

  proc checkCancel() =
    if hooks.cancelled(): fail("")

  proc advance(w: float) =
    prog.done += w
    hooks.progress(min(1.0, prog.done / prog.total), prog.label)

  var targets: seq[Target]
  for t in AllTargets:
    if t in s.targets: targets.add t
  let outRoot = info.root / OutputDirName
  let workRoot = outRoot / ".travail"
  try:
    # 1. Analyse
    step("Analyse du projet")
    if targets.len == 0: fail("aucune cible cochée (« Générer un exécutable pour : »)")
    if info.prgFiles.len == 0: fail("le projet ne contient aucun fichier .prg")
    if info.mainRel notin info.prgFiles: fail("fichier principal introuvable : " & info.mainRel)
    hooks.log(lgOutput, "Projet : " & info.root)
    hooks.log(lgOutput, "Application : " & info.name & " (" & s.appType.label & ")")
    hooks.log(lgOutput, "Sources : " & $info.prgFiles.len & " fichier(s) .prg, " &
                        $info.dataFiles.len & " autre(s) fichier(s)")
    hooks.log(lgOutput, "Paquets utilisés : " & (if info.packages.len > 0: info.packages.join(", ") else: "aucun"))
    var names: seq[string]
    for t in targets: names.add t.label
    hooks.log(lgOutput, "Cibles : " & names.join(", "))
    let (zig, zigLib, zigErr) = findZig(appDir)
    if zigErr.len > 0: fail(zigErr)
    putEnv("ZIG_LIB_DIR", zigLib)
    var (zv, zc) = execCmdEx(quoteShellCommand([zig, "version"]))
    when defined(macosx):
      if zc != 0:
        # archive téléchargée : macOS refuse de lancer un exécutable en quarantaine.
        let zdir = zig.parentDir.parentDir
        discard execCmdEx(quoteShellCommand(["xattr", "-dr", "com.apple.quarantine", zdir]))
        hooks.log(lgWarning, "macOS : attribut de quarantaine retiré du dossier " & zdir)
        (zv, zc) = execCmdEx(quoteShellCommand([zig, "version"]))
    if zc != 0: fail("Zig ne démarre pas : " & zig & "\n" & zv.strip &
                     (when defined(macosx): "\n(macOS : xattr -dr com.apple.quarantine sur le dossier macZG)" else: ""))
    let zigVersion = zv.strip
    hooks.log(lgOutput, "Zig " & zigVersion & " : " & zig)
    let rtc = findRtc(appDir)
    if rtc.len == 0: fail("runtime C introuvable (dossier rtc/ de wdlexis+ ; voir « nimble rtc »)")
    hooks.log(lgOutput, "Runtime C : " & rtc)
    if info.usesUi and s.appType != atGraphique:
      fail("le projet utilise le paquet « interface » : seul le type Graphique est possible")
    if s.iconPath.len > 0 and s.appType == atGraphique and not fileExists(s.iconPath):
      fail("image de l'icône introuvable : " & s.iconPath)
    let variant = variantFor(s, info)
    var manifests: Table[Target, Manifest]
    for t in targets: manifests[t] = readManifest(rtc, t, variant)
    # poids de la jauge.
    prog.total = 2 + float(info.prgFiles.len) * 0.2
    for t in targets: prog.total += 1 + float(manifests[t].files.len + 2) + 4 + 1 + 3
    advance(1)
    stepDone("Analyse terminée")
    checkCancel()

    step("Vérification de la syntaxe")
    for f in info.prgFiles:
      try: discard parseChunk(readFile(info.root / f), info.root / f)
      except SyntaxError as e: fail(e.msg)
      advance(0.2)
    stepDone("Syntaxe correcte (" & $info.prgFiles.len & " fichier(s))")
    advance(1)
    checkCancel()

    # icône (préparée une fois).
    var iconSquare: RgbaImage
    var hasIcon = false
    if s.appType == atGraphique and s.iconPath.len > 0:
      step("Préparation de l'icône")
      try:
        let img = loadImage(s.iconPath)
        iconSquare = cropImage(img, s.crop).resized(1024)
        hasIcon = true
        hooks.log(lgOutput, extractFilename(s.iconPath) & " : " & $img.w & " x " & $img.h &
                            " px, cadrage " & $int(s.crop.side * float(min(img.w, img.h))) & " px")
      except CatchableError as e: fail("icône : " & e.msg)
      stepDone("Icône prête")

    createDir(outRoot)
    let objRoot = getCacheDir("wdlexis") / "obj" / zigVersion
    for ti, t in targets:
      let tag = "[" & $(ti + 1) & "/" & $targets.len & "] " & t.label
      let m = manifests[t]
      let work = workRoot / $t
      removeDir(work)
      createDir(work)
      let triple = zigTriple(t)
      let exeBase = info.name
      let outName =
        case s.appType
        of atBibliotheque:
          (if t.isWindows: exeBase & ".dll" elif t.isMac: "lib" & exeBase & ".dylib" else: "lib" & exeBase & ".so")
        else: (if t.isWindows: exeBase & ".exe" else: exeBase)

      # 2. transpilation du projet.
      step(tag & " - transpilation du projet en C")
      let projetPath = work / "projet.c"
      writeFile(projetPath, projetC(info, s, t))
      hooks.log(lgOutput, "projet.c : " & formatSize(getFileSize(projetPath), includeSpace = true) &
                          " (" & $info.prgFiles.len & " source(s) embarquée(s)), runtime " & variant &
                          " : " & $m.files.len & " fichiers C")
      advance(1)
      stepDone("Transpilation terminée")
      checkCancel()

      # 3. compilation C.
      step(tag & " - compilation C par Zig (" & $(m.files.len + 1) & " fichiers)")
      var cflags = @["-target", triple, "-c", "-w", "-O3"] & m.cflags & @["-I" & rtc / "include"]
      if t.isLinux: cflags.add "-fPIC"
      if t.isMac: cflags.add "-I" & rtc / "compat" / "darwin"
      let flagKey = fnv(cflags.join(" "))
      let objDir = objRoot / ($t & "-" & variant)
      createDir(objDir)
      for f in walkFiles(objDir / "*.tmp*"):                      # restes d'une compilation interrompue /!\ ???
        try: removeFile(f) except OSError: discard
      var jobs: seq[Job]
      var objs: seq[string]
      var cached = 0
      for (h, name) in m.files:
        let o = objDir / (h & "-" & flagKey & ".o")
        objs.add o
        if fileExists(o):
          inc cached
          continue
        let src = rtc / "pool" / (h & ".c")
        let tmpO = o & ".tmp"
        jobs.add Job(exe: zig, args: @["cc"] & cflags & @["-o", tmpO, src], tmpOut: tmpO, finalOut: o,
                     display: "zig cc -target " & triple & " -c -O3 " & name & "  (" & extractFilename(src) & ")")
      if cached > 0:
        hooks.log(lgOutput, $cached & " fichier(s) du runtime déjà compilé(s) (cache : " & objDir & ")")
      advance(float(cached))
      let projetO = work / "projet.o"
      jobs.add Job(exe: zig, args: @["cc"] & cflags & @["-o", projetO, projetPath],
                   display: quoteShellCommand(@["zig", "cc"] & cflags & @["-o", projetO, projetPath]))
      objs.add projetO
      if t.isMac:
        let compatO = work / "wdlx_darwin.o"
        jobs.add Job(exe: zig, args: @["cc"] & cflags & @["-o", compatO, rtc / "compat" / "darwin" / "wdlx_darwin.c"],
                     display: "zig cc -target " & triple & " -c wdlx_darwin.c")
        objs.add compatO
      if not runJobs(jobs, hooks, prog, showOutputOk = true):
        fail(if hooks.cancelled(): "" else: "la compilation C a échoué")
      advance(1)
      stepDone("Compilation terminée (" & $(jobs.len) & " compilé(s), " & $cached & " en cache)")
      checkCancel()

      # 4. icône Windows (ressource liée à l'exécutable).
      var rcFile = ""
      if hasIcon and t.isWindows:
        step(tag & " - icône Windows (.ico)")
        writeFile(work / "app.ico", makeIco(iconSquare))
        rcFile = work / "app.rc"
        writeFile(rcFile, "1 ICON \"app.ico\"\n" &
          "1 VERSIONINFO\nFILEVERSION 1,0,0,0\nPRODUCTVERSION 1,0,0,0\nBEGIN\n" &
          "  BLOCK \"StringFileInfo\"\n  BEGIN\n    BLOCK \"040C04B0\"\n    BEGIN\n" &
          "      VALUE \"FileDescription\", \"" & info.name & "\"\n" &
          "      VALUE \"ProductName\", \"" & info.name & "\"\n" &
          "      VALUE \"OriginalFilename\", \"" & outName & "\"\n" &
          "    END\n  END\n  BLOCK \"VarFileInfo\"\n  BEGIN\n    VALUE \"Translation\", 0x040C, 1200\n  END\nEND\n")
        stepDone("Icône Windows prête")

      # 5. édition des liens.
      step(tag & " - édition des liens")
      let linked = work / outName
      let rsp = work / "objets.rsp"
      var rspText = ""
      for o in objs: rspText.add "\"" & o.replace("\\", "/") & "\"\n"
      writeFile(rsp, rspText)
      var largs = @["cc", "-target", triple, "-o", linked, "@" & rsp, "-s"]
      if rcFile.len > 0: largs.add rcFile
      case s.appType
      of atBibliotheque:
        largs.add "-shared"
        if t.isMac: largs.add "-Wl,-install_name,@rpath/" & outName
        if t.isLinux: largs.add "-Wl,-soname," & outName
      of atGraphique:
        if t.isWindows: largs.add "-Wl,--subsystem,windows"
      else: discard
      largs.add m.ldflags
      if t.isLinux and "-pthread" notin largs: largs.add "-pthread"
      let linkJob = Job(exe: zig, args: largs, display: quoteShellCommand(@["zig"] & largs))
      if not runJobs(@[linkJob], hooks, prog, weight = 4):
        fail(if hooks.cancelled(): "" else: "l'édition des liens a échoué")
      hooks.log(lgOutput, outName & " : " & formatSize(getFileSize(linked), includeSpace = true) &
                          " (" & binaryArch(linked) & ")")
      if (getMonoTime() - stepStart).inSeconds >= 20:
        hooks.log(lgOutput, "(Zig a préparé les bibliothèques C de " & t.label &
                            " : elles sont gardées en cache, les prochaines générations seront plus rapides)")
      stepDone("Édition des liens terminée")
      checkCancel()

      # 6. distribution.
      let distName = info.name & "-" & $t
      let stage = (if s.dist == dmFolder: outRoot / distName else: work / "stage" / distName)
      step(tag & " - distribution (" & (if s.dist == dmFolder: "dossier" else:
                                      (if t.isWindows: "archive zip" else: "archive tar.gz")) & ")")
      removeDir(stage)
      createDir(stage)
      var execs = initHashSet[string]()
      var base = stage           # dossier des ressources (fichiers du projet, bibliothèques).
      var exeRel = outName
      if s.appType == atGraphique and t.isMac:
        let app = stage / (info.name & ".app")
        createDir(app / "Contents" / "MacOS")
        createDir(app / "Contents" / "Resources")
        copyFile(linked, app / "Contents" / "MacOS" / outName)
        writeFile(app / "Contents" / "Info.plist", infoPlist(info.name, outName, hasIcon))
        writeFile(app / "Contents" / "PkgInfo", "APPL????")
        if hasIcon: writeFile(app / "Contents" / "Resources" / (info.name & ".icns"), makeIcns(iconSquare))
        base = app / "Contents" / "Resources"
        exeRel = info.name & ".app/Contents/MacOS/" & outName
        hooks.log(lgOutput, info.name & ".app (paquet macOS" & (if hasIcon: ", icône .icns" else: "") & ")")
      else:
        copyFile(linked, stage / outName)
      if s.appType != atBibliotheque or not t.isWindows: execs.incl exeRel
      when not defined(windows):
        if s.appType != atBibliotheque:
          setFilePermissions(stage / exeRel, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead,
                             fpGroupExec, fpOthersRead, fpOthersExec})
      # fichiers du projet.
      for f in info.dataFiles:
        let dst = base / f.replace('/', DirSep)
        createDir(dst.parentDir)
        copyFile(info.root / f, dst)
      if info.dataFiles.len > 0: hooks.log(lgOutput, $info.dataFiles.len & " fichier(s) du projet copié(s)")
      # bibliothèques.
      if s.bundleLibs:
        let osDir = osLibDir(t)
        var src = appDir / osDir
        if dirExists(src / archDir(t)): src = src / archDir(t)
        var nlibs = 0
        if dirExists(src):
          for f in walkDirRec(src, relative = true):
            let rel = f
            if src == appDir / osDir and (rel.startsWith("x64") or rel.startsWith("arm64")): continue
            let dst = base / osDir / rel
            createDir(dst.parentDir)
            copyFile(src / rel, dst)
            inc nlibs
            let a = binaryArch(dst)
            if a in ["x64", "arm64"] and a != archDir(t):
              hooks.log(lgWarning, "bibliothèque " & osDir & "/" & rel.replace('\\', '/') & " : architecture " &
                                   a & ", la cible est " & archDir(t))
        for f in walkDir(appDir):
          if f.kind in {pcFile, pcLinkToFile} and isLibFor(extractFilename(f.path), t):
            copyFile(f.path, base / extractFilename(f.path))
            inc nlibs
        if dirExists(appDir / "ttf"):
          copyDir(appDir / "ttf", base / "ttf")
          hooks.log(lgOutput, "polices : ttf/")
        if nlibs > 0: hooks.log(lgOutput, $nlibs & " bibliothèque(s) : " & osDir & "/")
        else: hooks.log(lgWarning, "aucune bibliothèque trouvée dans " & appDir / osDir)
      elif info.usesUi:
        hooks.log(lgWarning, "bibliothèques non intégrées : SDL3 et SDL3_ttf devront être fournies (" &
                             osLibDir(t) & "/ à côté de l'application)")
      # modèles (paquets d'IA).
      if info.usesIa:
        createDir(base / "models")
        writeFile(base / "models" / "models.txt", modelsText(appDir))
        hooks.log(lgOutput, "models/models.txt (paquets d'IA)")
      # licences (à embarquer).
      if dirExists(appDir / "LICENCES"):
        copyDir(appDir / "LICENCES", stage / "LICENCES")
      if fileExists(appDir / "LICENCE.md"):
        copyFile(appDir / "LICENCE.md", stage / "LICENCES" / "wdlexis-LICENCE.md")
      # selon le type...
      case s.appType
      of atGraphique:
        if t.isLinux:
          if hasIcon: writeFile(stage / (info.name & ".png"), encodePng(iconSquare.resized(256)))
          writeFile(stage / (info.name & ".desktop"),
            "[Desktop Entry]\nType=Application\nName=" & info.name & "\nExec=@DOSSIER@/" & outName &
            "\nPath=@DOSSIER@\n" & (if hasIcon: "Icon=@DOSSIER@/" & info.name & ".png\n" else: "") &
            "Terminal=false\nCategories=Utility;\n")
          writeFile(stage / "installer-bureau.sh",
            "#!/bin/sh\n# Installe le raccourci de " & info.name & " pour l'utilisateur courant.\n" &
            "D=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\nmkdir -p \"$HOME/.local/share/applications\"\n" &
            "sed \"s#@DOSSIER@#$D#g\" \"$D/" & info.name & ".desktop\" > \"$HOME/.local/share/applications/" &
            info.name & ".desktop\"\necho \"Raccourci installé.\"\n")
          execs.incl "installer-bureau.sh"
          when not defined(windows):
            setFilePermissions(stage / "installer-bureau.sh", {fpUserRead, fpUserWrite, fpUserExec,
                               fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})
          if hasIcon: hooks.log(lgOutput, info.name & ".png, " & info.name & ".desktop")
      of atService:
        if t.isWindows:
          writeFile(stage / "installer-service.cmd",
            "@echo off\r\nrem Installe " & info.name & " comme service Windows (à lancer en administrateur).\r\n" &
            "sc create \"" & info.name & "\" binPath= \"%~dp0" & outName & "\" start= auto DisplayName= \"" &
            info.name & "\"\r\nsc start \"" & info.name & "\"\r\n")
          writeFile(stage / "desinstaller-service.cmd",
            "@echo off\r\nsc stop \"" & info.name & "\"\r\nsc delete \"" & info.name & "\"\r\n")
        elif t.isMac:
          let id = "wdlexis.service." & info.name.toLowerAscii
          writeFile(stage / (id & ".plist"),
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" &
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" &
            "<plist version=\"1.0\">\n<dict>\n  <key>Label</key><string>" & id & "</string>\n" &
            "  <key>ProgramArguments</key><array><string>/usr/local/" & info.name & "/" & outName & "</string></array>\n" &
            "  <key>WorkingDirectory</key><string>/usr/local/" & info.name & "</string>\n" &
            "  <key>RunAtLoad</key><true/>\n  <key>KeepAlive</key><true/>\n" &
            "  <key>StandardOutPath</key><string>/usr/local/" & info.name & "/" & info.name & ".log</string>\n" &
            "  <key>StandardErrorPath</key><string>/usr/local/" & info.name & "/" & info.name & ".log</string>\n" &
            "</dict>\n</plist>\n")
          writeFile(stage / "installer-service.sh",
            "#!/bin/sh\n# Installe " & info.name & " comme service launchd (sudo ./installer-service.sh).\nset -e\n" &
            "D=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\nmkdir -p /usr/local/" & info.name & "\n" &
            "cp -R \"$D\"/. /usr/local/" & info.name & "/\n" &
            "cp \"$D/" & id & ".plist\" /Library/LaunchDaemons/\n" &
            "launchctl bootstrap system /Library/LaunchDaemons/" & id & ".plist\n" &
            "echo \"Service " & id & " installé.\"\n")
          writeFile(stage / "desinstaller-service.sh",
            "#!/bin/sh\nlaunchctl bootout system /Library/LaunchDaemons/" & id & ".plist\n" &
            "rm -f /Library/LaunchDaemons/" & id & ".plist\nrm -rf /usr/local/" & info.name & "\n")
        else:
          writeFile(stage / (info.name & ".service"),
            "[Unit]\nDescription=" & info.name & " (application Lexis+)\nAfter=network.target\n\n" &
            "[Service]\nType=simple\nExecStart=/opt/" & info.name & "/" & outName & "\n" &
            "WorkingDirectory=/opt/" & info.name & "\nRestart=on-failure\n\n" &
            "[Install]\nWantedBy=multi-user.target\n")
          writeFile(stage / "installer-service.sh",
            "#!/bin/sh\n# Installe " & info.name & " comme service systemd (sudo ./installer-service.sh).\nset -e\n" &
            "D=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\nmkdir -p /opt/" & info.name & "\n" &
            "cp -R \"$D\"/. /opt/" & info.name & "/\n" &
            "cp \"$D/" & info.name & ".service\" /etc/systemd/system/\n" &
            "systemctl daemon-reload\nsystemctl enable --now " & info.name & ".service\n" &
            "echo \"Service " & info.name & " installé.\"\n")
          writeFile(stage / "desinstaller-service.sh",
            "#!/bin/sh\nsystemctl disable --now " & info.name & ".service\n" &
            "rm -f /etc/systemd/system/" & info.name & ".service\nsystemctl daemon-reload\nrm -rf /opt/" &
            info.name & "\n")
        for sh in ["installer-service.sh", "desinstaller-service.sh"]:
          if fileExists(stage / sh):
            execs.incl sh
            when not defined(windows):
              setFilePermissions(stage / sh, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead,
                                 fpGroupExec, fpOthersRead, fpOthersExec})
        hooks.log(lgOutput, "fichiers d'installation du service")
      of atBibliotheque:
        writeFile(stage / (info.name & ".h"), headerText(info.name))
        hooks.log(lgOutput, info.name & ".h (en-tête C)")
      of atConsole: discard
      writeFile(stage / "LISEZMOI.txt", readmeText(info, s, t, exeRel))
      advance(2)
      if s.dist == dmArchive:
        let archive = outRoot / (distName & (if t.isWindows: ".zip" else: ".tar.gz"))
        removeFile(archive)
        if t.isWindows: writeZip(archive, stage, distName, execs)
        else: writeTarGz(archive, stage, distName, execs)
        hooks.log(lgOutput, extractFilename(archive) & " : " & formatSize(getFileSize(archive), includeSpace = true))
        removeDir(work / "stage")
        stepDone("Distribution prête : " & archive)
      else:
        stepDone("Distribution prête : " & stage)
      advance(1)
      removeDir(work)
      checkCancel()
    removeDir(workRoot)
    hooks.progress(1.0, "Génération terminée")
    hooks.log(lgFinal, "Génération terminée [" & fmtDuration(getMonoTime() - t0) & "]")
    result = true
  except BuildError as e:
    if e.msg.len == 0:
      try: removeDir(workRoot) except OSError: discard
      hooks.log(lgError, "Génération interrompue [" & fmtDuration(getMonoTime() - t0) & "]")
    else:
      for line in e.msg.splitLines: hooks.log(lgError, line)
      hooks.log(lgError, "Génération arrêtée sur erreur [" & fmtDuration(getMonoTime() - t0) & "]")
  except CatchableError as e:
    hooks.log(lgError, "erreur : " & e.msg)
    hooks.log(lgError, "Génération arrêtée sur erreur [" & fmtDuration(getMonoTime() - t0) & "]")
