# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet usb : accès direct aux périphériques USB (libusb-1.0)
#
# Permet d'écrire en Lexis+ un pilote « en espace utilisateur » : liste des
# périphériques, ouverture, transferts de contrôle, bulk et interruption.
# La bibliothèque libusb-1.0 est chargée à la demande (std/dynlib) : un
# programme qui n'utilise pas ce paquet n'en a pas besoin.
#
#   p = usb.ouvrir(0x04a9, 0x190e)              && Canon LiDE 120
#   r = p:controle(0xc0, 0x04, 0x8e, 0x2200, 2)  && lecture (octets)
#   p:controle(0x40, 0x04, 0x83, 0, binaire.depuisoctets({0x0f, 0x01}))
#   d = p:lire(0x81, 65536)                      && bulk entrant
#   p:fermer()
#
# Recherche de la bibliothèque : variable WDLEXIS_LIBUSB (chemin complet),
# dossier linOS / macOS / winOS à côté de l'exécutable ou dans le dossier
# courant, puis les emplacements du système (libusb-1.0.so.0, Homebrew,
# libusb-1.0.dll).
#
# Droits : sous Linux, une règle udev donne l'accès sans être root
#   SUBSYSTEM=="usb", ATTR{idVendor}=="04a9", ATTR{idProduct}=="190e", MODE="0666"
# sous Windows, le périphérique doit utiliser le pilote WinUSB (Zadig).
#
# Les transferts libèrent l'interpréteur (L.blocking) : les fenêtres restent
# réactives pendant une attente du périphérique.

import std/[dynlib, os, locks, strutils, times]
import ../lexis/api

const osDir = when defined(windows): "winOS" elif defined(macosx): "macOS" else: "linOS"

type
  UsbCtx = pointer
  UsbDev = pointer
  UsbHandle = pointer

  DeviceDescriptor {.bycopy.} = object
    bLength, bDescriptorType: uint8
    bcdUSB: uint16
    bDeviceClass, bDeviceSubClass, bDeviceProtocol, bMaxPacketSize0: uint8
    idVendor, idProduct, bcdDevice: uint16
    iManufacturer, iProduct, iSerialNumber, bNumConfigurations: uint8

  EndpointDescriptor {.bycopy.} = object
    bLength, bDescriptorType, bEndpointAddress, bmAttributes: uint8
    wMaxPacketSize: uint16
    bInterval, bRefresh, bSynchAddress: uint8
    extra: pointer
    extraLength: cint

  InterfaceDescriptor {.bycopy.} = object
    bLength, bDescriptorType, bInterfaceNumber, bAlternateSetting: uint8
    bNumEndpoints, bInterfaceClass, bInterfaceSubClass, bInterfaceProtocol: uint8
    iInterface: uint8
    endpoint: ptr UncheckedArray[EndpointDescriptor]
    extra: pointer
    extraLength: cint

  Interface {.bycopy.} = object
    altsetting: ptr UncheckedArray[InterfaceDescriptor]
    numAltsetting: cint

  ConfigDescriptor {.bycopy.} = object
    bLength, bDescriptorType: uint8
    wTotalLength: uint16
    bNumInterfaces, bConfigurationValue, iConfiguration, bmAttributes, maxPower: uint8
    iface: ptr UncheckedArray[Interface]
    extra: pointer
    extraLength: cint

  Api = object
    init: proc (ctx: ptr UsbCtx): cint {.cdecl, gcsafe.}
    getDeviceList: proc (ctx: UsbCtx, list: ptr ptr UncheckedArray[UsbDev]): int {.cdecl, gcsafe.}
    freeDeviceList: proc (list: ptr UncheckedArray[UsbDev], unref: cint) {.cdecl, gcsafe.}
    getDeviceDescriptor: proc (d: UsbDev, desc: ptr DeviceDescriptor): cint {.cdecl, gcsafe.}
    getBusNumber: proc (d: UsbDev): uint8 {.cdecl, gcsafe.}
    getDeviceAddress: proc (d: UsbDev): uint8 {.cdecl, gcsafe.}
    getDeviceSpeed: proc (d: UsbDev): cint {.cdecl, gcsafe.}
    open: proc (d: UsbDev, h: ptr UsbHandle): cint {.cdecl, gcsafe.}
    close: proc (h: UsbHandle) {.cdecl, gcsafe.}
    getDevice: proc (h: UsbHandle): UsbDev {.cdecl, gcsafe.}
    getConfiguration: proc (h: UsbHandle, c: ptr cint): cint {.cdecl, gcsafe.}
    setConfiguration: proc (h: UsbHandle, c: cint): cint {.cdecl, gcsafe.}
    claimInterface: proc (h: UsbHandle, i: cint): cint {.cdecl, gcsafe.}
    releaseInterface: proc (h: UsbHandle, i: cint): cint {.cdecl, gcsafe.}
    kernelDriverActive: proc (h: UsbHandle, i: cint): cint {.cdecl, gcsafe.}
    detachKernelDriver: proc (h: UsbHandle, i: cint): cint {.cdecl, gcsafe.}
    attachKernelDriver: proc (h: UsbHandle, i: cint): cint {.cdecl, gcsafe.}
    controlTransfer: proc (h: UsbHandle, rt, req: uint8, value, index: uint16,
                           data: pointer, length: uint16, timeout: cuint): cint {.cdecl, gcsafe.}
    bulkTransfer: proc (h: UsbHandle, ep: uint8, data: pointer, length: cint,
                        transferred: ptr cint, timeout: cuint): cint {.cdecl, gcsafe.}
    interruptTransfer: proc (h: UsbHandle, ep: uint8, data: pointer, length: cint,
                             transferred: ptr cint, timeout: cuint): cint {.cdecl, gcsafe.}
    clearHalt: proc (h: UsbHandle, ep: uint8): cint {.cdecl, gcsafe.}
    resetDevice: proc (h: UsbHandle): cint {.cdecl, gcsafe.}
    errorName: proc (code: cint): cstring {.cdecl, gcsafe.}
    getStringAscii: proc (h: UsbHandle, idx: uint8, data: pointer, length: cint): cint {.cdecl, gcsafe.}
    getActiveConfig: proc (d: UsbDev, cfg: ptr ptr ConfigDescriptor): cint {.cdecl, gcsafe.}
    freeConfig: proc (cfg: ptr ConfigDescriptor) {.cdecl, gcsafe.}

  UsbPeripheral = ref object of LUser
    h: UsbHandle
    vendor, product: int
    claimed: seq[int]
    trace: File
    tracing: bool
    t0: float
    nTransfers: int
    bytesIn, bytesOut: int64

const
  ErrTimeout = -7
  ErrorTexts = [
    (-1, "erreur d'entrée-sortie"), (-2, "paramètre invalide"),
    (-3, "accès refusé (droits insuffisants : règle udev sous Linux, pilote WinUSB sous Windows)"),
    (-4, "périphérique absent (débranché ?)"), (-5, "introuvable"),
    (-6, "occupé (utilisé par un autre programme ou un pilote)"), (-7, "délai dépassé"),
    (-8, "débordement"), (-9, "transfert refusé par le périphérique (pipe)"),
    (-10, "appel interrompu"), (-11, "mémoire insuffisante"),
    (-12, "opération non prise en charge par ce système"), (-99, "erreur inconnue")]

var
  lu: Api
  ctx: UsbCtx
  loaded = false
  loadError = ""
  libLock: Lock
initLock(libLock)

proc libNames(): seq[string] =
  let env = getEnv("WDLEXIS_LIBUSB")
  if env.len > 0: result.add env
  let base = when defined(windows): "libusb-1.0.dll"
             elif defined(macosx): "libusb-1.0.0.dylib"
             else: "libusb-1.0.so.0"
  for d in [getAppDir(), getCurrentDir()]:
    result.add d / osDir / base
    result.add d / base
  when defined(windows):
    result.add ["libusb-1.0.dll", "libusb0.dll"]
  elif defined(macosx):
    result.add ["libusb-1.0.0.dylib", "/opt/homebrew/lib/libusb-1.0.0.dylib",
                "/usr/local/lib/libusb-1.0.0.dylib", "/opt/local/lib/libusb-1.0.0.dylib"]
  else:
    result.add ["libusb-1.0.so.0", "libusb-1.0.so", "/usr/lib/x86_64-linux-gnu/libusb-1.0.so.0",
                "/usr/local/lib/libusb-1.0.so.0"]

proc loadUsb(): bool =
  acquire(libLock)
  defer: release(libLock)
  if loaded: return true
  if loadError.len > 0: return false
  var lib: LibHandle = nil
  for n in libNames():
    lib = loadLib(n)
    if not lib.isNil: break
  if lib.isNil:
    loadError = "bibliothèque libusb-1.0 introuvable ; installez-la (Linux : paquet libusb-1.0-0, " &
                "macOS : brew install libusb, Windows : libusb-1.0.dll) ou placez-la dans le dossier « " &
                osDir & " » à côté de l'exécutable, ou indiquez son chemin dans la variable WDLEXIS_LIBUSB"
    return false
  template sym(field: untyped, name: string) =
    let p = lib.symAddr(name)
    if p.isNil:
      loadError = "symbole libusb manquant : " & name
      return false
    lu.field = cast[typeof(lu.field)](p)
  sym(init, "libusb_init")
  sym(getDeviceList, "libusb_get_device_list")
  sym(freeDeviceList, "libusb_free_device_list")
  sym(getDeviceDescriptor, "libusb_get_device_descriptor")
  sym(getBusNumber, "libusb_get_bus_number")
  sym(getDeviceAddress, "libusb_get_device_address")
  sym(getDeviceSpeed, "libusb_get_device_speed")
  sym(open, "libusb_open")
  sym(close, "libusb_close")
  sym(getDevice, "libusb_get_device")
  sym(getConfiguration, "libusb_get_configuration")
  sym(setConfiguration, "libusb_set_configuration")
  sym(claimInterface, "libusb_claim_interface")
  sym(releaseInterface, "libusb_release_interface")
  sym(kernelDriverActive, "libusb_kernel_driver_active")
  sym(detachKernelDriver, "libusb_detach_kernel_driver")
  sym(attachKernelDriver, "libusb_attach_kernel_driver")
  sym(controlTransfer, "libusb_control_transfer")
  sym(bulkTransfer, "libusb_bulk_transfer")
  sym(interruptTransfer, "libusb_interrupt_transfer")
  sym(clearHalt, "libusb_clear_halt")
  sym(resetDevice, "libusb_reset_device")
  sym(errorName, "libusb_error_name")
  sym(getStringAscii, "libusb_get_string_descriptor_ascii")
  sym(getActiveConfig, "libusb_get_active_config_descriptor")
  sym(freeConfig, "libusb_free_config_descriptor")
  let rc = lu.init(addr ctx)
  if rc != 0:
    loadError = "libusb_init a échoué (" & $rc & ")"
    return false
  loaded = true
  true

proc errText(code: cint): string =
  for (c, t) in ErrorTexts:
    if c == int(code): return t & " [" & $lu.errorName(code) & "]"
  "erreur " & $code

proc need(L: Interp) =
  if not loadUsb(): rtError("usb : " & loadError)

proc speedName(s: cint): string =
  case s
  of 1: "basse"
  of 2: "pleine"
  of 3: "haute"
  of 4: "super"
  of 5: "super+"
  else: "inconnue"

proc hex4(x: int): string = "0x" & toHex(x, 4).toLowerAscii

proc deviceInfo(d: UsbDev): LTable =
  var desc: DeviceDescriptor
  discard lu.getDeviceDescriptor(d, addr desc)
  result = newLTable()
  result.set("bus", intV(int(lu.getBusNumber(d))))
  result.set("adresse", intV(int(lu.getDeviceAddress(d))))
  result.set("vendeur", intV(int(desc.idVendor)))
  result.set("produit", intV(int(desc.idProduct)))
  result.set("id", strV(toHex(int(desc.idVendor), 4).toLowerAscii & ":" & toHex(int(desc.idProduct), 4).toLowerAscii))
  result.set("version", intV(int(desc.bcdDevice)))
  result.set("usb", intV(int(desc.bcdUSB)))
  result.set("classe", intV(int(desc.bDeviceClass)))
  result.set("vitesse", strV(speedName(lu.getDeviceSpeed(d))))

proc hexBytes(s: string, maxn = 32): string =
  for i in 0 ..< min(s.len, maxn):
    if i > 0: result.add ' '
    result.add toHex(ord(s[i]), 2).toLowerAscii
  if s.len > maxn: result.add " …(" & $s.len & ")"

proc log(p: UsbPeripheral, line: string) =
  if p.tracing:
    try:
      p.trace.writeLine(formatFloat(epochTime() - p.t0, ffDecimal, 4) & " " & line)
      p.trace.flushFile()
    except IOError: discard

proc checkPeriph(L: Interp, a: seq[Value], fname: string): UsbPeripheral =
  result = L.checkUser[:UsbPeripheral](a, 1, fname, "périphérique usb")
  if result.h.isNil: rtError("usb : " & fname & " : périphérique fermé")

proc closePeriph(p: UsbPeripheral) =
  if p.h.isNil: return
  for i in p.claimed: discard lu.releaseInterface(p.h, cint(i))
  p.claimed.setLen(0)
  lu.close(p.h)
  p.h = nil
  if p.tracing:
    try: p.trace.close() except CatchableError: discard
    p.tracing = false

proc claim(L: Interp, p: UsbPeripheral, i: int) =
  if i in p.claimed: return
  when not defined(windows) and not defined(macosx):
    if lu.kernelDriverActive(p.h, cint(i)) == 1:
      let rc = lu.detachKernelDriver(p.h, cint(i))
      if rc != 0 and rc != -12:
        rtError("usb : impossible de détacher le pilote du système (" & errText(rc) & ")")
  var rc: cint
  L.blocking:
    rc = lu.claimInterface(p.h, cint(i))
  if rc != 0: rtError("usb : réclamer l'interface " & $i & " : " & errText(rc))
  p.claimed.add i

proc openUsb(L: Interp): Value =
  let pm = newLib()

  pm.fn "descripteur", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "descripteur")
    let d = lu.getDevice(p.h)
    let r = deviceInfo(d)
    var desc: DeviceDescriptor
    discard lu.getDeviceDescriptor(d, addr desc)
    proc str(idx: uint8): string =
      if idx == 0: return ""
      var buf: array[256, char]
      let n = lu.getStringAscii(p.h, idx, addr buf[0], 255)
      if n > 0:
        result = newString(n)
        copyMem(addr result[0], addr buf[0], n)
    L.blocking:
      r.set("fabricant", strV(str(desc.iManufacturer)))
      r.set("nom", strV(str(desc.iProduct)))
      r.set("serie", strV(str(desc.iSerialNumber)))
    @[tableV(r)]

  pm.fn "points", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "points")
    var cfg: ptr ConfigDescriptor
    let rc = lu.getActiveConfig(lu.getDevice(p.h), addr cfg)
    if rc != 0: rtError("usb : points : " & errText(rc))
    let r = newLTable()
    var k = 1
    for i in 0 ..< int(cfg.bNumInterfaces):
      let itf = cfg.iface[i]
      if itf.numAltsetting < 1: continue
      let alt = itf.altsetting[0]
      for e in 0 ..< int(alt.bNumEndpoints):
        let ep = alt.endpoint[e]
        let t = newLTable()
        t.set("adresse", intV(int(ep.bEndpointAddress)))
        t.set("sens", strV(if (ep.bEndpointAddress and 0x80) != 0: "entree" else: "sortie"))
        t.set("genre", strV(case ep.bmAttributes and 3
                            of 0: "controle"
                            of 1: "isochrone"
                            of 2: "bulk"
                            else: "interruption"))
        t.set("taille", intV(int(ep.wMaxPacketSize)))
        t.set("interface", intV(int(alt.bInterfaceNumber)))
        r.rawSet(k, tableV(t)); inc k
    lu.freeConfig(cfg)
    @[tableV(r)]

  pm.fn "configuration", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "configuration")
    if arg(a, 2).kind != vkNil:
      let c = L.checkInt(a, 2, "configuration")
      var rc: cint
      L.blocking:
        rc = lu.setConfiguration(p.h, cint(c))
      if rc != 0: rtError("usb : configuration : " & errText(rc))
    var c: cint
    discard lu.getConfiguration(p.h, addr c)
    @[intV(int(c))]

  pm.fn "reclamer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "reclamer")
    L.claim(p, int(L.optInt(a, 2, "reclamer", 0)))
    @[boolV(true)]

  pm.fn "liberer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "liberer")
    let i = int(L.optInt(a, 2, "liberer", 0))
    if i in p.claimed:
      discard lu.releaseInterface(p.h, cint(i))
      p.claimed.delete(p.claimed.find(i))
    @[boolV(true)]

  pm.fn "controle", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## controle(type, requete, valeur, index, donnees | longueur, [delai_ms])
    let p = L.checkPeriph(a, "controle")
    let rt = int(L.checkInt(a, 2, "controle")) and 0xff
    let req = int(L.checkInt(a, 3, "controle")) and 0xff
    let value = int(L.checkInt(a, 4, "controle")) and 0xffff
    let index = int(L.checkInt(a, 5, "controle")) and 0xffff
    let timeout = cuint(L.optInt(a, 7, "controle", 5000))
    let incoming = (rt and 0x80) != 0
    var buf: string
    if incoming:
      let n = int(L.checkInt(a, 6, "controle"))
      if n < 0 or n > 65535: rtError("usb : controle : longueur invalide")
      buf = newString(n)
    else:
      let d = arg(a, 6)
      buf = if d.kind == vkNil: "" elif d.kind == vkStr: d.s else: L.checkStr(a, 6, "controle")
      if buf.len > 65535: rtError("usb : controle : données trop longues")
    var rc: cint
    L.blocking:
      rc = lu.controlTransfer(p.h, uint8(rt), uint8(req), uint16(value), uint16(index),
                               (if buf.len > 0: addr buf[0] else: nil), uint16(buf.len), timeout)
    inc p.nTransfers
    let head = "CTRL " & toHex(rt, 2).toLowerAscii & " " & toHex(req, 2).toLowerAscii & " " &
               toHex(value, 4).toLowerAscii & " " & toHex(index, 4).toLowerAscii & " " & $buf.len
    if rc < 0:
      p.log(head & " ! " & $lu.errorName(rc))
      rtError("usb : controle (type " & hex4(rt) & ", requête " & hex4(req) & ", valeur " &
              hex4(value) & ", index " & hex4(index) & ") : " & errText(rc))
    if incoming:
      buf.setLen(int(rc))
      p.bytesIn += rc
      p.log(head & " < " & hexBytes(buf))
      return @[strV(buf)]
    p.bytesOut += rc
    p.log(head & " > " & hexBytes(buf))
    @[intV(int(rc))]

  proc transfer(L: Interp, a: seq[Value], fname: string, interrupt: bool, write: bool): seq[Value] =
    let p = L.checkPeriph(a, fname)
    let ep = int(L.checkInt(a, 2, fname)) and 0xff
    var buf: string
    if write: buf = L.checkStr(a, 3, fname)
    else:
      let n = int(L.checkInt(a, 3, fname))
      if n < 0: rtError("usb : " & fname & " : longueur invalide")
      buf = newString(n)
    let timeout = cuint(L.optInt(a, 4, fname, if interrupt: 1000 else: 30000))
    var done: cint = 0
    var rc: cint
    L.blocking:
      if interrupt:
        rc = lu.interruptTransfer(p.h, uint8(ep), (if buf.len > 0: addr buf[0] else: nil),
                                   cint(buf.len), addr done, timeout)
      else:
        rc = lu.bulkTransfer(p.h, uint8(ep), (if buf.len > 0: addr buf[0] else: nil),
                              cint(buf.len), addr done, timeout)
    inc p.nTransfers
    let head = (if interrupt: "INTR " else: "BULK ") & toHex(ep, 2).toLowerAscii & " " & $buf.len
    if rc < 0 and not (rc == ErrTimeout and done > 0):
      p.log(head & " ! " & $lu.errorName(rc))
      if rc == ErrTimeout and interrupt and not write: return @[nilV()]
      rtError("usb : " & fname & " (point " & hex4(ep) & ", " & $buf.len & " octets) : " & errText(rc))
    if write:
      p.bytesOut += done
      p.log(head & " > " & hexBytes(buf))
      return @[intV(int(done))]
    buf.setLen(int(done))
    p.bytesIn += done
    p.log(head & " < " & hexBytes(buf, 16))
    @[strV(buf)]

  pm.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    transfer(L, a, "lire", false, false)
  pm.fn "ecrire", proc (L: Interp, a: seq[Value]): seq[Value] =
    transfer(L, a, "ecrire", false, true)
  pm.fn "interruption", proc (L: Interp, a: seq[Value]): seq[Value] =
    transfer(L, a, "interruption", true, false)

  pm.fn "debloquer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "debloquer")
    let ep = int(L.checkInt(a, 2, "debloquer")) and 0xff
    var rc: cint
    L.blocking:
      rc = lu.clearHalt(p.h, uint8(ep))
    @[boolV(rc == 0)]

  pm.fn "reinitialiser", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "reinitialiser")
    var rc: cint
    L.blocking:
      rc = lu.resetDevice(p.h)
    @[boolV(rc == 0)]

  pm.fn "tracer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkPeriph(a, "tracer")
    if p.tracing:
      try: p.trace.close() except CatchableError: discard
      p.tracing = false
    if arg(a, 2).kind == vkStr and a[1].s.len > 0:
      try:
        p.trace = open(a[1].s, fmWrite)
        p.tracing = true
        p.t0 = epochTime()
        p.log("# trace usb " & toHex(p.vendor, 4).toLowerAscii & ":" & toHex(p.product, 4).toLowerAscii)
      except IOError as e:
        rtError("usb : tracer : " & e.msg)
    @[boolV(p.tracing)]

  pm.fn "statistiques", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkUser[:UsbPeripheral](a, 1, "statistiques", "périphérique usb")
    let r = newLTable()
    r.set("transferts", intV(p.nTransfers))
    r.set("octetslus", intV(p.bytesIn))
    r.set("octetsecrits", intV(p.bytesOut))
    r.set("ouvert", boolV(not p.h.isNil))
    @[tableV(r)]

  pm.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkUser[:UsbPeripheral](a, 1, "fermer", "périphérique usb")
    closePeriph(p)
    @[boolV(true)]

  discard L.userMeta("usb", pm)

  let m = newLib()
  m.fn "disponible", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(loadUsb())]
  m.fn "erreur", proc (L: Interp, a: seq[Value]): seq[Value] =
    discard loadUsb()
    @[strV(loadError)]

  m.fn "peripheriques", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.need()
    let fv = int(L.optInt(a, 1, "peripheriques", -1))
    let fp = int(L.optInt(a, 2, "peripheriques", -1))
    var list: ptr UncheckedArray[UsbDev]
    var n: int
    L.blocking:
      n = lu.getDeviceList(ctx, addr list)
    if n < 0: rtError("usb : liste des périphériques : " & errText(cint(n)))
    let r = newLTable()
    var k = 1
    for i in 0 ..< n:
      let t = deviceInfo(list[i])
      if fv >= 0 and t.rawGet("VENDEUR").i != fv: continue
      if fp >= 0 and t.rawGet("PRODUIT").i != fp: continue
      r.rawSet(k, tableV(t)); inc k
    lu.freeDeviceList(list, 1)
    @[tableV(r)]

  m.fn "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## ouvrir(vendeur, produit, [{bus=, adresse=, interface=0, reclamer=vrai, configuration=}])
    L.need()
    let vendor = int(L.checkInt(a, 1, "ouvrir"))
    let product = int(L.checkInt(a, 2, "ouvrir"))
    let o = if arg(a, 3).kind == vkTable: a[2].t else: nil
    let bus = optField(o, "bus", -1)
    let adr = optField(o, "adresse", -1)
    let itf = optField(o, "interface", 0)
    let doClaim = optField(o, "reclamer", true)
    let conf = optField(o, "configuration", -1)
    var list: ptr UncheckedArray[UsbDev]
    var n: int
    L.blocking:
      n = lu.getDeviceList(ctx, addr list)
    if n < 0: rtError("usb : liste des périphériques : " & errText(cint(n)))
    var found: UsbDev = nil
    for i in 0 ..< n:
      var desc: DeviceDescriptor
      if lu.getDeviceDescriptor(list[i], addr desc) != 0: continue
      if int(desc.idVendor) != vendor or int(desc.idProduct) != product: continue
      if bus >= 0 and int(lu.getBusNumber(list[i])) != bus: continue
      if adr >= 0 and int(lu.getDeviceAddress(list[i])) != adr: continue
      found = list[i]
      break
    var h: UsbHandle = nil
    var rc: cint = -5
    if not found.isNil:
      L.blocking:
        rc = lu.open(found, addr h)
    lu.freeDeviceList(list, 1)
    if found.isNil: return @[nilV()]
    if rc != 0:
      rtError("usb : ouverture de " & toHex(vendor, 4).toLowerAscii & ":" &
              toHex(product, 4).toLowerAscii & " : " & errText(rc))
    let p = UsbPeripheral(h: h, vendor: vendor, product: product)
    L.closers.add proc () = closePeriph(p)
    if conf >= 0:
      var cur: cint
      discard lu.getConfiguration(h, addr cur)
      if cur != cint(conf):
        L.blocking:
          rc = lu.setConfiguration(h, cint(conf))
    if doClaim:
      try: L.claim(p, itf)
      except CatchableError:
        closePeriph(p)
        raise
    @[L.wrap(p, "usb", pm)]
  tableV(m)

registerPackage PackageDef(name: "usb", open: openUsb,
  description: "Accès direct aux périphériques USB (libusb-1.0) : pilotes en espace utilisateur",
  docs: docs("usb", [
    "usb.disponible()", "Vrai si la bibliothèque libusb-1.0 est chargée (voir usb.erreur()).",
    "usb.erreur()", "Raison pour laquelle libusb n'a pas pu être chargée (\"\" sinon).",
    "usb.peripheriques([vendeur, produit])", "Liste des périphériques : {bus, adresse, vendeur, produit, id (\"04a9:190e\"), version (bcdDevice), usb (bcdUSB), classe, vitesse}.",
    "usb.ouvrir(vendeur, produit, [{bus=, adresse=, interface=0, reclamer=vrai, configuration=}])", "Ouvre le premier périphérique correspondant (nul s'il est absent) et réclame son interface (le pilote du système est détaché sous Linux). Erreur explicite si l'accès est refusé.",
    "p:descripteur()", "Description : bus, adresse, vendeur, produit, version, vitesse, fabricant, nom, serie.",
    "p:points()", "Points de terminaison de la configuration active : {adresse, sens (entree, sortie), genre (controle, isochrone, bulk, interruption), taille, interface}.",
    "p:configuration([n])", "Configuration active (la change si n est donné).",
    "p:reclamer([interface])", "Réclame une interface (0 par défaut).",
    "p:liberer([interface])", "Libère une interface.",
    "p:controle(type, requete, valeur, index, donnees | longueur, [delai_ms=5000])", "Transfert de contrôle. Sens donné par le bit 7 de type : entrant (0x80) → renvoie les octets lus (longueur demandée) ; sortant → envoie donnees (octets) et renvoie le nombre envoyé.",
    "p:lire(point, longueur, [delai_ms=30000])", "Transfert bulk entrant : renvoie les octets reçus (au plus longueur).",
    "p:ecrire(point, donnees, [delai_ms=30000])", "Transfert bulk sortant : renvoie le nombre d'octets envoyés.",
    "p:interruption(point, longueur, [delai_ms=1000])", "Transfert d'interruption entrant ; nul si rien n'arrive dans le délai.",
    "p:debloquer(point)", "Efface l'état bloqué (halt) d'un point de terminaison.",
    "p:reinitialiser()", "Réinitialise le périphérique (réénumération USB).",
    "p:tracer([chemin])", "Journalise chaque transfert dans un fichier (sans chemin : arrête) ; utile pour comparer avec une capture usbmon ou Wireshark.",
    "p:statistiques()", "{transferts, octetslus, octetsecrits, ouvert}.",
    "p:fermer()", "Libère les interfaces et ferme le périphérique (fait aussi à la fin du programme)."]))
