# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdgui - chargement des images en textures (contrôle Image, icônes de la grille,
#   icônes des boîtes de dialogue).
#
#   PNG et JPEG sont décodés en Nim pur (ide/imagedecode) puis confiés au SDL de
#   wdgui : aucune bibliothèque externe n'est nécessaire, et l'on évite le piège de
#   SDL3_image lié à un *autre* exemplaire de SDL3 (par exemple la libSDL3_image de
#   Homebrew, liée à /opt/homebrew/.../libSDL3.0.dylib) : la surface qu'elle renvoie
#   appartient à cet autre SDL, que le SDL de wdgui refuse (« Parameter 'surface' is
#   invalid »), et l'image restait vide sans message.
#   BMP : SDL_LoadBMP. Autres formats (GIF, WEBP, TIFF...), PNG entrelacés et JPEG
#   progressifs : SDL3_image si wdgui est compilé avec -d:sdlimage.
#   Un échec est signalé une fois par chemin sur la sortie d'erreur.

import std/[strutils, os, sets, locks]
import ../sdl3
import ../ide/imagedecode

const PixRGBA32 = 0x16762004'u32        # SDL_PIXELFORMAT_ABGR8888 : octets R, G, B, A (petit-boutiste)

var reported: HashSet[string]
var reportLock: Lock
initLock(reportLock)

proc report(path, msg: string) =
  {.cast(gcsafe).}:
    withLock reportLock:
      if path in reported: return
      reported.incl path
  try: stderr.writeLine "wdgui: image « " & path & " » non chargée : " & msg
  except IOError: discard

proc fromSurface(ren: SDL_Renderer, s: SDL_Surface): tuple[tex: SDL_Texture, w, h: float, err: string] =
  result.tex = SDL_CreateTextureFromSurface(ren, s)
  if result.tex == nil:
    result.err = $SDL_GetError()
    return
  var w, h: cfloat
  discard SDL_GetTextureSize(result.tex, addr w, addr h)
  result.w = float(w)
  result.h = float(h)

proc loadTexture*(ren: SDL_Renderer, path: string): tuple[tex: SDL_Texture, w, h: float, err: string] =
  ## Texture de l'image `path` (nil et err renseigné en cas d'échec).
  if path.len == 0: return
  if not fileExists(path):
    result.err = "fichier introuvable"
    report(path, result.err)
    return
  let ext = path.splitFile.ext.toLowerAscii
  var native = ""
  if ext == ".bmp":
    let s = SDL_LoadBMP(path.cstring)
    if s != nil:
      result = fromSurface(ren, s)
      SDL_DestroySurface(s)
    else: result.err = $SDL_GetError()
  else:
    try:
      var img = decodeImageFile(path)
      if img.w > 0 and img.h > 0:
        let s = SDL_CreateSurfaceFrom(cint(img.w), cint(img.h), PixRGBA32, addr img.px[0], cint(img.w * 4))
        if s != nil:
          result = fromSurface(ren, s)
          SDL_DestroySurface(s)
        else: result.err = $SDL_GetError()
    except CatchableError as e:
      native = e.msg             # format non pris en charge en Nim pur : SDL3_image ensuite.
    if result.tex == nil and native.len > 0:
      when defined(sdlimage):
        let s = IMG_Load(path.cstring)
        if s != nil:
          result = fromSurface(ren, s)
          SDL_DestroySurface(s)
          if result.tex == nil:
            result.err = result.err & " (SDL3_image est-elle liée à un autre exemplaire de SDL3 ?)"
        else: result.err = native & " ; SDL3_image : " & $SDL_GetError()
      else:
        result.err = native & " (compilez avec -d:sdlimage pour les autres formats)"
  if result.tex == nil and result.err.len > 0: report(path, result.err)
