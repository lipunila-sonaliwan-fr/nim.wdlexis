# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - pilote Firebird natif : primitives cryptographiques
#
# Aucune dépendance : SHA-1, SHA-256, RC4 (greffon de chiffrement "Arc4" du
# protocole), grands entiers non signés (exponentiation modulaire de Montgomery)
# et client SRP-6a tel que l'emploient Firebird 3+ et Jaybird (greffons
# d'authentification "Srp" et "Srp256").

import std/sysrand

#
# SHA-1 / SHA-256
#

proc rol(x: uint32, n: int): uint32 {.inline.} = (x shl n) or (x shr (32 - n))
proc ror(x: uint32, n: int): uint32 {.inline.} = (x shr n) or (x shl (32 - n))

proc padMessage(data: openArray[byte]): seq[byte] =
  ## Remplissage commun à SHA-1 et SHA-256 (longueur en bits, gros-boutiste).
  result = @data
  let bits = uint64(data.len) * 8
  result.add 0x80'u8
  while result.len mod 64 != 56: result.add 0'u8
  for i in countdown(7, 0): result.add byte((bits shr (8 * i)) and 0xff)

proc be32(b: openArray[byte], i: int): uint32 {.inline.} =
  (uint32(b[i]) shl 24) or (uint32(b[i + 1]) shl 16) or (uint32(b[i + 2]) shl 8) or uint32(b[i + 3])

proc put32(r: var seq[byte], x: uint32) =
  for k in countdown(3, 0): r.add byte((x shr (8 * k)) and 0xff)

proc sha1*(data: openArray[byte]): seq[byte] =
  var h = [0x67452301'u32, 0xEFCDAB89'u32, 0x98BADCFE'u32, 0x10325476'u32, 0xC3D2E1F0'u32]
  let m = padMessage(data)
  var w: array[80, uint32]
  var blk = 0
  while blk < m.len:
    for i in 0 ..< 16: w[i] = be32(m, blk + 4 * i)
    for i in 16 ..< 80: w[i] = rol(w[i - 3] xor w[i - 8] xor w[i - 14] xor w[i - 16], 1)
    var a = h[0]
    var b = h[1]
    var c = h[2]
    var d = h[3]
    var e = h[4]
    for i in 0 ..< 80:
      var f, k: uint32
      if i < 20: (f = (b and c) or ((not b) and d); k = 0x5A827999'u32)
      elif i < 40: (f = b xor c xor d; k = 0x6ED9EBA1'u32)
      elif i < 60: (f = (b and c) or (b and d) or (c and d); k = 0x8F1BBCDC'u32)
      else: (f = b xor c xor d; k = 0xCA62C1D6'u32)
      let t = rol(a, 5) + f + e + k + w[i]
      e = d
      d = c
      c = rol(b, 30)
      b = a
      a = t
    h[0] += a
    h[1] += b
    h[2] += c
    h[3] += d
    h[4] += e
    blk += 64
  for x in h: result.put32 x

const K256 = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32, 0x59f111f1'u32,
  0x923f82a4'u32, 0xab1c5ed5'u32, 0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
  0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32, 0xe49b69c1'u32, 0xefbe4786'u32,
  0x0fc19dc6'u32, 0x240ca1cc'u32, 0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32,
  0x06ca6351'u32, 0x14292967'u32, 0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
  0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32, 0xa2bfe8a1'u32, 0xa81a664b'u32,
  0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32,
  0x5b9cca4f'u32, 0x682e6ff3'u32, 0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
  0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]

proc sha256*(data: openArray[byte]): seq[byte] =
  var h = [0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
           0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32]
  let m = padMessage(data)
  var w: array[64, uint32]
  var blk = 0
  while blk < m.len:
    for i in 0 ..< 16: w[i] = be32(m, blk + 4 * i)
    for i in 16 ..< 64:
      let s0 = ror(w[i - 15], 7) xor ror(w[i - 15], 18) xor (w[i - 15] shr 3)
      let s1 = ror(w[i - 2], 17) xor ror(w[i - 2], 19) xor (w[i - 2] shr 10)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    var v = h
    for i in 0 ..< 64:
      let S1 = ror(v[4], 6) xor ror(v[4], 11) xor ror(v[4], 25)
      let ch = (v[4] and v[5]) xor ((not v[4]) and v[6])
      let t1 = v[7] + S1 + ch + K256[i] + w[i]
      let S0 = ror(v[0], 2) xor ror(v[0], 13) xor ror(v[0], 22)
      let maj = (v[0] and v[1]) xor (v[0] and v[2]) xor (v[1] and v[2])
      let t2 = S0 + maj
      v[7] = v[6]
      v[6] = v[5]
      v[5] = v[4]
      v[4] = v[3] + t1
      v[3] = v[2]
      v[2] = v[1]
      v[1] = v[0]
      v[0] = t1 + t2
    for i in 0 ..< 8: h[i] += v[i]
    blk += 64
  for x in h: result.put32 x

proc toBytes*(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

proc hexOf*(b: openArray[byte]): string =
  const digits = "0123456789abcdef"
  for x in b:
    result.add digits[int(x shr 4)]
    result.add digits[int(x and 15)]

#
# RC4 ("Arc4") : un flux par sens de communication.
#

type Rc4* = object
  s: array[256, uint8]
  i, j: uint8

proc initRc4*(key: openArray[byte]): Rc4 =
  for k in 0 .. 255: result.s[k] = uint8(k)
  var j = 0
  for k in 0 .. 255:
    j = (j + int(result.s[k]) + int(key[k mod key.len])) and 255
    swap(result.s[k], result.s[j])

proc apply*(r: var Rc4, data: var string, start = 0) =
  for k in start ..< data.len:
    r.i = r.i + 1
    r.j = r.j + r.s[r.i]
    swap(r.s[r.i], r.s[r.j])
    data[k] = char(uint8(data[k]) xor r.s[uint8(r.s[r.i] + r.s[r.j])])

#
# Grands entiers non signés : membres de 32 bits, petit-boutistes, normalisés.
#

type Big* = seq[uint32]

proc norm(a: var Big) =
  while a.len > 0 and a[^1] == 0: a.setLen(a.len - 1)

proc fromBytes*(b: openArray[byte]): Big =
  ## Octets gros-boutistes -> entier.
  result = newSeq[uint32]((b.len + 3) div 4)
  for k in 0 ..< b.len:
    let pos = b.len - 1 - k              # poids k
    result[k div 4] = result[k div 4] or (uint32(b[pos]) shl (8 * (k mod 4)))
  result.norm

proc bigFromHex*(s: string): Big =
  var b: seq[byte]
  var t = ""
  for c in s:
    if c in {'0'..'9', 'a'..'f', 'A'..'F'}: t.add c
  if t.len mod 2 == 1: t = "0" & t
  var i = 0
  while i < t.len:
    var v = 0
    for c in t[i .. i + 1]:
      v = v * 16 + (if c <= '9': ord(c) - ord('0') elif c <= 'F': ord(c) - ord('A') + 10 else: ord(c) - ord('a') + 10)
    b.add byte(v)
    i += 2
  fromBytes(b)

proc toBytes*(a: Big): seq[byte] =
  ## Entier -> octets gros-boutistes minimaux (comme BigInteger, sans octet de signe).
  for k in countdown(a.len * 4 - 1, 0):
    let x = byte((a[k div 4] shr (8 * (k mod 4))) and 0xff)
    if result.len == 0 and x == 0: continue
    result.add x

proc isZero*(a: Big): bool = a.len == 0

proc cmp*(a, b: Big): int =
  if a.len != b.len: return (if a.len < b.len: -1 else: 1)
  for k in countdown(a.len - 1, 0):
    if a[k] != b[k]: return (if a[k] < b[k]: -1 else: 1)
  0

proc `+`*(a, b: Big): Big =
  result = newSeq[uint32](max(a.len, b.len) + 1)
  var c = 0'u64
  for k in 0 ..< result.len:
    let x = (if k < a.len: uint64(a[k]) else: 0'u64) + (if k < b.len: uint64(b[k]) else: 0'u64) + c
    result[k] = uint32(x and 0xffffffff'u64)
    c = x shr 32
  result.norm

proc `-`*(a, b: Big): Big =
  ## a - b, avec a >= b.
  result = a
  var borrow = 0'i64
  for k in 0 ..< result.len:
    var x = int64(result[k]) - (if k < b.len: int64(b[k]) else: 0) - borrow
    if x < 0:
      x += 0x1_0000_0000'i64
      borrow = 1
    else: borrow = 0
    result[k] = uint32(x)
  result.norm

proc `*`*(a, b: Big): Big =
  if a.len == 0 or b.len == 0: return @[]
  result = newSeq[uint32](a.len + b.len)
  for i in 0 ..< a.len:
    var c = 0'u64
    for j in 0 ..< b.len:
      let x = uint64(result[i + j]) + uint64(a[i]) * uint64(b[j]) + c
      result[i + j] = uint32(x and 0xffffffff'u64)
      c = x shr 32
    result[i + b.len] = uint32(c)
  result.norm

proc bitLen(a: Big): int =
  if a.len == 0: return 0
  var top = a[^1]
  result = (a.len - 1) * 32
  while top != 0:
    inc result
    top = top shr 1

proc bit(a: Big, i: int): bool {.inline.} = ((a[i div 32] shr (i mod 32)) and 1) != 0

proc `mod`*(a, n: Big): Big =
  ## Division binaire : réservée aux quelques réductions hors exponentiation.
  if cmp(a, n) < 0: return a
  result = @[]
  for i in countdown(a.bitLen - 1, 0):
    # result = result * 2 + bit
    var carry = (if a.bit(i): 1'u32 else: 0'u32)
    for k in 0 ..< result.len:
      let nc = result[k] shr 31
      result[k] = (result[k] shl 1) or carry
      carry = nc
    if carry != 0: result.add carry
    if cmp(result, n) >= 0: result = result - n

proc modPow*(base, exp, n: Big): Big =
  ## base^exp mod n (n impair) : multiplication de Montgomery (CIOS).
  let s = n.len
  var inv = 1'u32                         # inverse de n[0] modulo 2^32 (Newton)
  for _ in 0 ..< 5: inv = inv * (2'u32 - n[0] * inv)
  let n0 = 0'u32 - inv
  proc mont(a, b: seq[uint32]): seq[uint32] =
    var t = newSeq[uint32](s + 2)
    for i in 0 ..< s:
      var c = 0'u64
      for j in 0 ..< s:
        let x = uint64(t[j]) + uint64(a[j]) * uint64(b[i]) + c
        t[j] = uint32(x and 0xffffffff'u64)
        c = x shr 32
      var x = uint64(t[s]) + c
      t[s] = uint32(x and 0xffffffff'u64)
      t[s + 1] = uint32(x shr 32)
      let m = t[0] * n0
      x = uint64(t[0]) + uint64(m) * uint64(n[0])
      c = x shr 32
      for j in 1 ..< s:
        x = uint64(t[j]) + uint64(m) * uint64(n[j]) + c
        t[j - 1] = uint32(x and 0xffffffff'u64)
        c = x shr 32
      x = uint64(t[s]) + c
      t[s - 1] = uint32(x and 0xffffffff'u64)
      t[s] = t[s + 1] + uint32(x shr 32)
      t[s + 1] = 0
    var r: Big = t[0 .. s]
    r.norm
    if cmp(r, n) >= 0: r = r - n
    result = r
    result.setLen(s)
  proc fixed(a: Big): seq[uint32] =
    result = a
    result.setLen(s)
  # passage dans le domaine de Montgomery : x * R mod n
  var shifted = newSeq[uint32](s)
  shifted.add(base mod n)
  shifted.norm
  var x = fixed(shifted mod n)
  var one = newSeq[uint32](s)
  one.add 1'u32
  var r = fixed(one mod n)                # R mod n = 1 en Montgomery
  for i in countdown(exp.bitLen - 1, 0):
    r = mont(r, r)
    if exp.bit(i): r = mont(r, x)
  var unit = newSeq[uint32](s)
  unit[0] = 1
  result = mont(r, unit)
  result.norm

#
# SRP-6a (Firebird)
#

const
  SrpPrimeHex = "E67D2E994B2F900C3F41F08F5BB2627ED0D49EE1FE767A52EFCD565CD6E768812C3E1E9CE8F0A8BE" &
                "A6CB13CD29DDEBF7A96D4A93B55D488DF099A15C89DCB0640738EB2CBDD9A8F7BAB561AB1B0DC1C6" &
                "CDABF303264A08D1BCA932D1F1EE428B619D970F342ABA9A65793B8B2F041AE5364350C16F735F56" &
                "ECBCA87BD57B29E7"

type SrpClient* = object
  N, g, k: Big
  a*, A*: Big

proc srpPrime*(): Big = bigFromHex(SrpPrimeHex)

proc multiplier(N, g: Big): Big =
  ## k = SHA1(N | g complété à la taille de N)
  let nb = N.toBytes
  var gb = newSeq[byte](nb.len)
  let gx = g.toBytes
  for i in 0 ..< gx.len: gb[gb.len - gx.len + i] = gx[i]
  fromBytes(sha1(nb & gb))

proc newSrpClient*(secret: Big = @[]): SrpClient =
  result.N = srpPrime()
  result.g = @[2'u32]
  result.k = multiplier(result.N, result.g)
  if secret.len > 0: result.a = secret
  else:
    var r = newSeq[byte](16)              # 128 bits, comme Firebird et Jaybird
    if not urandom(r):
      raise newException(OSError, "générateur aléatoire indisponible")
    r[0] = r[0] or 0x80
    result.a = fromBytes(r)
  result.A = modPow(result.g, result.a, result.N)

proc multiplierValue*(c: SrpClient): Big = c.k

proc publicKeyHex*(c: SrpClient): string = hexOf(c.A.toBytes)

proc normalizeUser*(user: string): string =
  # Nom tel que le serveur le connaît : entre guillemets -> tel quel ("""" -> """),
  # sinon en majuscules.
  if user.len >= 2 and user[0] == '"' and user[^1] == '"':
    var r = ""
    var i = 1
    while i < user.len - 1:
      r.add user[i]
      if user[i] == '"' and i + 1 < user.len - 1 and user[i + 1] == '"': inc i
      inc i
    return r
  for c in user:
    result.add(if c in {'a'..'z'}: char(ord(c) - 32) else: c)

proc clientProof*(c: SrpClient, user, password: string, salt: openArray[byte], B: Big,
                  sha256Proof: bool): tuple[proof, sessionKey: seq[byte]] =
  # Preuve M (SHA-1 pour "Srp", SHA-256 pour "Srp256") et clé de session
  # K = SHA1(S), qui sert aussi de clé au chiffrement Arc4.
  let N = c.N
  if (B mod N).isZero: raise newException(ValueError, "clé publique du serveur invalide")
  let u = fromBytes(sha1(c.A.toBytes & B.toBytes))
  let x = fromBytes(sha1(@salt & sha1(toBytes(user & ":" & password))))
  let gx = modPow(c.g, x, N)
  let kgx = (c.k * gx) mod N
  let bm = B mod N
  let diff = if cmp(bm, kgx) >= 0: bm - kgx else: (bm + N) - kgx
  let ux = (u * x) mod N
  let aux = (c.a + ux) mod N
  let S = modPow(diff, aux, N)
  let K = sha1(S.toBytes)
  let n1 = fromBytes(sha1(N.toBytes))
  let n2 = fromBytes(sha1(c.g.toBytes))
  let hng = modPow(n1, n2, N)
  let hu = fromBytes(sha1(toBytes(user)))
  let data = hng.toBytes & hu.toBytes & @salt & c.A.toBytes & B.toBytes & K
  result.proof = if sha256Proof: sha256(data) else: sha1(data)
  result.sessionKey = K
