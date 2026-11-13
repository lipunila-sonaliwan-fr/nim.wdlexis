# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - export et import d'un projet sous forme d'archive (.zip, .tar.gz)
#
# Menu Fichier de l'atelier : « Exporter le projet (archive)… » et « Importer un
# projet (archive)… ». Même logique que l'atelier écrit en Lexis+
# (exemples/atelier/projet.prg, paquet archive) : les fichiers du projet sont
# rangés sous un dossier de tête portant le nom du projet ; les fichiers cachés,
# la session et le dossier de distribution sont laissés de côté, mais les
# réglages de génération (.wdlexis/application.ini) sont gardés.

import std/[os, strutils, times, algorithm]
import ../paquets/compression
from toolchain import OutputDirName

type ProjectArchiveError* = object of CatchableError

proc perr(msg: string) {.noreturn.} =
  raise newException(ProjectArchiveError, msg)

proc projectFiles*(root: string): seq[string] =
  ## Fichiers à exporter, chemins relatifs avec « / ».
  for f in walkDirRec(root, relative = true):
    let rel = f.replace('\\', '/')
    if rel == ".wdlexis/application.ini":
      result.add rel
      continue
    if rel.startsWith(".") or "/." in rel: continue
    if rel == OutputDirName or rel.startsWith(OutputDirName & "/"): continue
    result.add rel
  result.sort()

proc isTarGz(path: string): bool =
  let p = path.toLowerAscii
  p.endsWith(".tar.gz") or p.endsWith(".tgz")

proc exportProject*(root, dest: string, level = 9): int =
  ## Écrit l'archive du projet (zip, ou tar.gz d'après l'extension) ; renvoie le
  ## nombre de fichiers.
  let top = extractFilename(root.strip(leading = false, chars = {'/', '\\'}))
  let files = projectFiles(root)
  if files.len == 0: perr("Le projet ne contient aucun fichier : " & root)
  let tmp = dest & ".part"
  try:
    if isTarGz(dest):
      var tar = ""
      for rel in files:
        let p = root / rel
        tar.tarAdd(top & "/" & rel, readFile(p), getLastModificationTime(p).toUnix, 0o644)
      tar.tarFinish()
      writeFile(tmp, gzipCompress(tar, level))
    else:
      let z = createZip(tmp, level)
      try:
        for rel in files:
          let p = root / rel
          z.addEntry(top & "/" & rel, readFile(p), getLastModificationTime(p).toUnix, 0o644)
      finally:
        z.close()
    moveFile(tmp, dest)
  except CompressionError, IOError, OSError:
    if fileExists(tmp): removeFile(tmp)
    perr("Export impossible : " & getCurrentExceptionMsg())
  files.len

proc importProject*(archivePath, destParent: string): string =
  ## Extrait l'archive dans destParent ; renvoie le dossier du projet (le dossier
  ## de tête s'il est unique). Refuse d'écraser un projet existant et les chemins
  ## dangereux (.., chemins absolus).
  var entries: seq[(string, string, bool)]       # (nom sûr, contenu, dossier)
  try:
    case detectKind(archivePath)
    of akZip:
      let z = openZip(archivePath)
      try:
        for e in z.entries:
          if e.encrypted: perr("Entrée chiffrée non prise en charge : " & e.name)
          let name = safeRelative(e.name)
          if name.len == 0: continue
          entries.add (name, (if e.isDir: "" else: z.read(e)), e.isDir)
      finally:
        z.close()
    of akTar, akTarGz:
      var data = readFile(archivePath)
      if isGzip(data): data = gzipDecompress(data)
      for e in tarList(data):
        if e.isLink: continue
        let name = safeRelative(e.name)
        if name.len == 0: continue
        entries.add (name, (if e.isDir: "" else: tarRead(data, e)), e.isDir)
    else:
      perr("Format d'archive non reconnu (zip, tar ou tar.gz attendu) : " & archivePath)
  except CompressionError, IOError, OSError:
    perr("Archive illisible : " & getCurrentExceptionMsg())
  if entries.len == 0: perr("L'archive est vide.")
  # dossier de tête commun ?
  var top = ""
  var single = true
  for (n, _, _) in entries:
    let first = n.split('/')[0]
    if top.len == 0: top = first
    elif first != top: single = false
    if not single: break
  if single and entries.len == 1 and not entries[0][2]: single = false
  let root = if single: destParent / top else: destParent
  if single and dirExists(root):
    var nonEmpty = false
    for _ in walkDir(root):
      nonEmpty = true
      break
    if nonEmpty: perr("Le dossier existe déjà et n'est pas vide : " & root)
  try:
    for (n, data, isDir) in entries:
      let p = destParent / n
      if isDir:
        createDir(p)
      else:
        if not single and fileExists(p): perr("Le fichier existe déjà : " & p)
        createDir(p.parentDir)
        writeFile(p, data)
  except IOError, OSError:
    perr("Extraction impossible : " & getCurrentExceptionMsg())
  root
