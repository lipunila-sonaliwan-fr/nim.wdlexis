#!/usr/bin/env python3
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
"""Faux serveur Firebird (protocole 17) pour tester le pilote fbwire sans serveur réel.

  python3 tests/firebird/serveur_simule.py 3055 [srp256|srp|nocrypt]

Le journal des échanges (connexion, authentification, chiffrement, lectures...)
est écrit sur la sortie standard.

Il reproduit la logique côté serveur telle que documentée (SRP, Arc4, DSQL, blobs),
sur une petite table en mémoire T. Mode d'authentification choisi par argv[2] :
  srp256  : op_cond_accept avec sel/B pour Srp256 (cas normal)
  srp     : le serveur choisit « Srp » et redemande la clé publique (op_cont_auth)
  nocrypt : comme srp256 mais sans proposer Arc4
"""
import hashlib, os, socket, struct, sys, threading, re

N = int("E67D2E994B2F900C3F41F08F5BB2627ED0D49EE1FE767A52EFCD565CD6E768812C3E1E9CE8F0A8BEA6CB13CD29DDEBF7A96D4A93B55D488DF099A15C89DCB0640738EB2CBDD9A8F7BAB561AB1B0DC1C6CDABF303264A08D1BCA932D1F1EE428B619D970F342ABA9A65793B8B2F041AE5364350C16F735F56ECBCA87BD57B29E7", 16)
g = 2
def lb(n): return n.to_bytes((n.bit_length() + 7) // 8, 'big')
def H(*a, f=hashlib.sha1):
    h = f()
    for x in a: h.update(x)
    return h.digest()
k = int.from_bytes(H(lb(N), lb(g).rjust(128, b'\0')), 'big')
USERS = {"SYSDBA": "masterkey"}
MODE = sys.argv[2] if len(sys.argv) > 2 else "srp256"
LOG = []

class RC4:
    def __init__(s, key):
        s.S = list(range(256)); j = 0
        for i in range(256):
            j = (j + s.S[i] + key[i % len(key)]) & 255; s.S[i], s.S[j] = s.S[j], s.S[i]
        s.i = s.j = 0
    def __call__(s, data):
        out = bytearray()
        for c in data:
            s.i = (s.i + 1) & 255; s.j = (s.j + s.S[s.i]) & 255
            s.S[s.i], s.S[s.j] = s.S[s.j], s.S[s.i]
            out.append(c ^ s.S[(s.S[s.i] + s.S[s.j]) & 255])
        return bytes(out)

# Table T : (nom, sqltype, subtype, scale, length)
COLS_T = [("ID", 496, 0, 0, 4), ("NOM", 448, 4, 0, 80), ("PRIX", 580, 0, -2, 8),
          ("DT", 570, 0, 0, 4), ("NOTE", 520, 1, 0, 8), ("OK", 32764, 0, 0, 1),
          ("BIG", 32752, 0, 0, 16), ("CODE", 452, 4, 0, 20), ("TS", 510, 0, 0, 8),
          ("TAUX", 480, 0, 0, 8)]
STATE = {"rows": [], "next_id": 1, "blobs": {}, "gen": 0, "blobseq": 0}

class Conn:
    def __init__(s, sock):
        s.sock = sock; s.buf = b""; s.out = b""; s.rin = s.rout = None
        s.stmts = {}; s.nexth = 1; s.openblobs = {}
    # --- XDR
    def need(s, n):
        while len(s.buf) < n:
            d = s.sock.recv(65536)
            if not d: raise EOFError
            if s.rin: d = s.rin(d)
            s.buf += d
    def rint(s):
        s.need(4); v = struct.unpack(">i", s.buf[:4])[0]; s.buf = s.buf[4:]; return v
    def ropaque(s, n):
        t = n + ((4 - n % 4) % 4); s.need(t); v = s.buf[:n]; s.buf = s.buf[t:]; return v
    def rbuf(s): return s.ropaque(s.rint())
    def wint(s, v): s.out += struct.pack(">i", v)
    def wopaque(s, b): s.out += b + b"\0" * ((4 - len(b) % 4) % 4)
    def wbuf(s, b): s.wint(len(b)); s.wopaque(b)
    def flush(s):
        d = s.out; s.out = b""
        if s.rout: d = s.rout(d)
        s.sock.sendall(d)
    def resp(s, obj=0, blob=b"\0" * 8, data=b"", status=None):
        s.wint(9); s.wint(obj); s.wopaque(blob); s.wbuf(data)
        for a in (status or [(1, 0)]):
            s.wint(a[0])
            if a[0] in (2, 5, 19): s.wbuf(a[1].encode())
            else: s.wint(a[1])
        s.wint(0); s.flush()

    def error(s, *status): s.resp(status=list(status))

    # --- connexion
    def handshake(s):
        op = s.rint(); assert op == 1, op
        s.rint(); s.rint(); s.rint(); path = s.rbuf(); n = s.rint(); uid = s.rbuf()
        protos = [[s.rint() for _ in range(5)] for _ in range(n)]
        p = 0; params = {}
        while p < len(uid):
            c = uid[p]; l = uid[p + 1]; v = uid[p + 2:p + 2 + l]; p += 2 + l
            if c == 7: params[7] = params.get(7, b"") + v[1:]
            else: params[c] = v
        LOG.append(("connect", path.decode(), [x[0] & 0x7fff for x in protos], params[8], params[10]))
        s.user = params[9].decode().upper()
        s.A = int(params[7].decode(), 16)
        s.salt = os.urandom(32).hex().encode()
        pw = USERS.get(s.user, "?")
        x = int.from_bytes(H(s.salt, H((s.user + ":" + pw).encode())), 'big')
        s.v = pow(g, x, N); s.b = int.from_bytes(os.urandom(16), 'big')
        s.B = (k * s.v + pow(g, s.b, N)) % N
        keys = b"\x00\x09Symmetric\x01\x04Arc4" if MODE != "nocrypt" else b""
        s.wint(98); s.wint(0x8000 | 17); s.wint(1); s.wint(3)
        if MODE == "srp":
            s.plugin = "Srp"
            s.wbuf(b""); s.wbuf(b"Srp"); s.wint(0); s.wbuf(keys); s.flush()
            op = s.rint(); assert op == 92, op
            a = s.rbuf(); pl = s.rbuf(); s.rbuf(); s.rbuf()
            assert pl == b"Srp"; s.A = int(a.decode(), 16)
            s.wint(92); s.wbuf(s.authdata()); s.wbuf(b"Srp"); s.wbuf(b"Srp256,Srp"); s.wbuf(keys); s.flush()
        else:
            s.plugin = "Srp256"
            s.wbuf(s.authdata()); s.wbuf(b"Srp256"); s.wint(0); s.wbuf(keys); s.flush()
        op = s.rint(); assert op == 92, op
        m = s.rbuf().decode(); pl = s.rbuf().decode(); s.rbuf(); s.rbuf()
        u = int.from_bytes(H(lb(s.A), lb(s.B)), 'big')
        S = pow(s.A * pow(s.v, u, N) % N, s.b, N); K = H(lb(S))
        n1 = pow(int.from_bytes(H(lb(N)), 'big'), int.from_bytes(H(lb(g)), 'big'), N)
        n2 = int.from_bytes(H(s.user.encode()), 'big')
        f = hashlib.sha256 if s.plugin == "Srp256" else hashlib.sha1
        M = H(lb(n1), lb(n2), s.salt, lb(s.A), lb(s.B), K, f=f).hex()
        if M != m.lower():
            LOG.append(("auth", "ECHEC")); s.error((1, 335544472)); return False
        LOG.append(("auth", "ok", s.plugin))
        s.resp(data=keys)
        s.K = K
        return True
    def authdata(s):
        bh = lb(s.B).hex().encode()
        return struct.pack("<H", len(s.salt)) + s.salt + struct.pack("<H", len(bh)) + bh

    # --- BLR / messages
    @staticmethod
    def parse_blr(b):
        assert b[0] == 5 and b[1] == 2 and b[2] == 4
        n = b[4] | (b[5] << 8); p = 6; items = []
        for _ in range(n // 2):
            t = b[p]; p += 1; it = {"t": t}
            if t in (15, 38): it["cs"] = b[p] | (b[p+1] << 8); it["len"] = b[p+2] | (b[p+3] << 8); p += 4
            elif t in (7, 8, 16, 9): it["scale"] = struct.unpack("b", bytes([b[p]]))[0]; p += 1
            items.append(it)
            assert b[p] == 7 and b[p + 1] == 0; p += 2
        assert b[p] == 255 and b[p + 1] == 76
        return items
    def read_msg(s, items):
        nb = (len(items) + 7) // 8; bm = s.ropaque(nb); vals = []
        for i, it in enumerate(items):
            if bm[i // 8] & (1 << (i % 8)): vals.append(None); continue
            t = it["t"]
            if t == 15: vals.append(s.ropaque(it["len"]).decode())
            elif t == 38: vals.append(s.rbuf().decode())
            elif t in (7, 8): vals.append(s.rint() * 10 ** it["scale"])
            elif t == 16:
                v = struct.unpack(">q", s.ropaque(8))[0]
                vals.append(v * 10 ** it["scale"] if it["scale"] else v)
            elif t == 27: vals.append(struct.unpack(">d", s.ropaque(8))[0])
            elif t == 12: vals.append(("date", s.rint()))
            elif t == 23: vals.append(s.ropaque(1)[0] != 0)
            elif t == 9: vals.append(("blob", s.ropaque(8)))
            else: raise ValueError("type BLR %d" % t)
        return vals
    def write_msg(s, items, vals):
        nb = (len(items) + 7) // 8; bm = bytearray(nb)
        for i, v in enumerate(vals):
            if v is None: bm[i // 8] |= 1 << (i % 8)
        s.wopaque(bytes(bm))
        for it, v in zip(items, vals):
            if v is None: continue
            t = it["t"]
            if t == 15:
                b = str(v).encode()[:it["len"]]; s.wopaque(b + b" " * (it["len"] - len(b)))
            elif t == 38: s.wbuf(str(v).encode())
            elif t in (7, 8): s.wint(int(round(v / 10 ** it["scale"])))
            elif t == 16: s.wopaque(struct.pack(">q", int(round(v / 10 ** it["scale"]))))
            elif t == 27: s.wopaque(struct.pack(">d", v))
            elif t == 10: s.wopaque(struct.pack(">f", v))
            elif t == 12: s.wint(v[1] if isinstance(v, tuple) else v)
            elif t == 35: s.wint(v[0]); s.wint(v[1])
            elif t == 23: s.wopaque(b"\1" if v else b"\0")
            elif t == 9: s.wopaque(v[1] if isinstance(v, tuple) else v)
            else: raise ValueError("type BLR sortie %d" % t)

    # --- description
    def describe(s, st, items, maxlen):
        out = bytearray(); p = 0; section = None; start = 1
        while p < len(items):
            c = items[p]; p += 1
            if c == 20: start = items[p + 1] | (items[p + 2] << 8); p += 3; continue
            if c == 21: out += bytes([21]) + struct.pack("<H", 4) + struct.pack("<i", st["kind"]); continue
            if c in (4, 5):
                section = st["outs"] if c == 4 else st["ins"]
                out.append(c)
                out += bytes([7]) + struct.pack("<H", 4) + struct.pack("<i", len(section))
                wanted = []
                while p < len(items) and items[p] not in (4, 5, 1):
                    if items[p] == 8: p += 1; break
                    if items[p] != 7: wanted.append(items[p])
                    p += 1
                for i in range(start - 1, len(section)):
                    col = section[i]; blk = bytearray()
                    def num(code, v): blk.extend(bytes([code]) + struct.pack("<H", 4) + struct.pack("<i", v))
                    def txt(code, v): b = v.encode(); blk.extend(bytes([code]) + struct.pack("<H", len(b)) + b)
                    for w in wanted:
                        if w == 9: num(9, i + 1)
                        elif w == 11: num(11, col[1] | 1)
                        elif w == 12: num(12, col[2])
                        elif w == 13: num(13, col[3])
                        elif w == 14: num(14, col[4])
                        elif w == 16: txt(16, col[0])
                        elif w == 17: txt(17, st.get("rel", ""))
                        elif w == 18: txt(18, "SYSDBA")
                        elif w == 19: txt(19, col[0])
                    blk.append(8)
                    if len(out) + len(blk) + 2 > maxlen:
                        out.append(2); return bytes(out)
                    out += blk
                start = 1
        out.append(1)
        return bytes(out)

    def plan(s, sql):
        u = sql.upper().strip()
        st = {"kind": 1, "outs": [], "ins": [], "sql": sql, "rel": ""}
        nq = sql.count("?")
        if "NOPE" in u: return None
        if u.startswith("SELECT RDB$GET_CONTEXT"):
            st["outs"] = [("V", 448, 4, 0, 40)]
        elif u.startswith("SELECT GEN_ID"):
            st["outs"] = [("V", 580, 0, 0, 8)]
        elif "FROM LARGE" in u:
            st["outs"] = [("C%d" % i, 496, 0, 0, 4) for i in range(600)]
        elif u.startswith("SELECT") and "FROM T" in u:
            st["outs"] = list(COLS_T); st["rel"] = "T"
            st["ins"] = [("ID", 496, 0, 0, 4)] * nq
        elif u.startswith("INSERT INTO T"):
            names = [x.strip().upper() for x in re.search(r"\(([^)]*)\)", sql).group(1).split(",")]
            st["kind"] = 2
            st["names"] = names
            if nq:
                st["ins"] = [next(c for c in COLS_T if c[0] == n) for n in names]
            else:
                # valeurs littérales : VALUES ('a', 1.5, true)
                vals = re.search(r"values\s*\((.*)\)", sql, re.I | re.S).group(1)
                st["litteraux"] = [v.strip() for v in re.split(r",(?=(?:[^']*'[^']*')*[^']*$)", vals)]
            if "RETURNING" in u: st["outs"] = [("ID", 496, 0, 0, 4)]
        elif u.startswith("DELETE FROM T"): st["kind"] = 4
        elif u.startswith("CREATE"): st["kind"] = 5
        elif u.startswith("EXECUTE PROCEDURE"):
            st["kind"] = 8; st["outs"] = [("TOTAL", 580, 0, -2, 8)]
        else: return None
        return st

    def run(s):
        if not s.handshake(): return
        while True:
            try: op = s.rint()
            except EOFError: return
            if op == 96:                                     # op_crypt
                pl = s.rbuf(); kt = s.rbuf(); LOG.append(("crypt", pl.decode(), kt.decode()))
                s.rin = RC4(s.K); s.rout = RC4(s.K); s.resp()
            elif op in (19, 20):
                s.rint(); path = s.rbuf(); dpb = s.rbuf()
                p = 1; items = {}
                while p < len(dpb):
                    c = dpb[p]; l = dpb[p + 1]; items[c] = dpb[p + 2:p + 2 + l]; p += 2 + l
                LOG.append(("attach" if op == 19 else "create", path.decode(), {k: v for k, v in sorted(items.items())}))
                if 29 in items: LOG.append(("ERREUR", "mot de passe en clair dans le DPB"))
                s.resp(obj=1)
            elif op == 29:
                s.rint(); s.rbuf(); s.nexth += 1; s.resp(obj=s.nexth)
            elif op in (30, 31):
                s.rint(); (LOG.append(("rollback",)) if op == 31 else None); s.resp()
            elif op == 62:
                s.rint(); s.nexth += 1; s.stmts[s.nexth] = None; s.resp(obj=s.nexth)
            elif op == 68:
                tr = s.rint(); h = s.rint(); s.rint(); sql = s.rbuf().decode(); items = s.rbuf(); ml = s.rint()
                st = s.plan(sql)
                if st is None:
                    s.error((1, 335544569), (1, 335544436), (4, -204), (1, 335544580), (1, 335544382), (2, "NOPE"),
                            (19, "42S02"))
                    continue
                s.stmts[h] = st
                s.resp(data=s.describe(st, items, ml))
            elif op == 70:
                h = s.rint(); s.rint(); items = s.rbuf(); ml = s.rint(); st = s.stmts[h]
                if items[0] == 23:
                    cnt = st.get("count", 0); code = {2: 14, 4: 16}.get(st["kind"], 13)
                    body = bytes([code]) + struct.pack("<H", 4) + struct.pack("<i", cnt) + b"\x01"
                    s.resp(data=bytes([23]) + struct.pack("<H", len(body)) + body + b"\x01")
                else:
                    LOG.append(("info_sql", "suite", items[:4].hex()))
                    s.resp(data=s.describe(st, items, ml))
            elif op in (63, 76):
                h = s.rint(); tr = s.rint(); blr = s.rbuf(); s.rint(); msgs = s.rint()
                st = s.stmts[h]; vals = []
                if msgs: vals = s.read_msg(s.parse_blr(blr))
                outblr = None
                if op == 76: outblr = s.rbuf(); s.rint()
                timeout = s.rint()                       # protocole 16+
                s.execute(st, vals, op, outblr)
            elif op == 65:
                h = s.rint(); blr = s.rbuf(); s.rint(); count = s.rint(); st = s.stmts[h]
                items = s.parse_blr(blr); rows = st["cursor"]
                batch = rows[:count]; st["cursor"] = rows[count:]
                for r in batch:
                    s.wint(66); s.wint(0); s.wint(1); s.write_msg(items, r)
                s.wint(66); s.wint(100 if not st["cursor"] else 0); s.wint(0); s.flush()
                LOG.append(("fetch", len(batch)))
            elif op == 67:
                h = s.rint(); s.rint(); s.stmts.pop(h, None); s.resp()
            elif op == 57:
                s.rbuf(); s.rint(); s.ropaque(8); STATE["blobseq"] += 1
                bid = struct.pack(">ii", 0, STATE["blobseq"]); s.nexth += 1
                s.openblobs[s.nexth] = [bid, b""]; s.resp(obj=s.nexth, blob=bid)
            elif op == 37:
                h = s.rint(); s.rint(); seg = s.rbuf(); s.openblobs[h][1] += seg; s.resp()
            elif op == 56:
                s.rbuf(); s.rint(); bid = s.ropaque(8); s.nexth += 1
                s.openblobs[s.nexth] = [bid, STATE["blobs"][bid], 0]; s.resp(obj=s.nexth)
            elif op == 36:
                h = s.rint(); ln = s.rint(); s.rbuf(); b = s.openblobs[h]
                data = b[1][b[2]:b[2] + min(ln, 1000)]; b[2] += len(data)   # segments de 1000 octets
                more = b[2] < len(b[1])
                s.resp(obj=1 if more else 2, data=struct.pack("<H", len(data)) + data)
            elif op == 39:
                h = s.rint(); b = s.openblobs.pop(h)
                if len(b) == 2: STATE["blobs"][b[0]] = b[1]; LOG.append(("blob", len(b[1])))
                s.resp()
            elif op == 21:
                s.rint(); s.resp(); LOG.append(("detach",))
            elif op == 6:
                return
            else:
                LOG.append(("op inconnue", op)); return

    def execute(s, st, vals, op, outblr):
        kind = st["kind"]; st["count"] = 0
        if kind == 1:
            u = st["sql"].upper()
            if st["outs"][0][0] == "V" and "GEN_ID" in u:
                STATE["gen"] += 1; st["cursor"] = [[STATE["gen"]]]
            elif st["outs"][0][0] == "V": st["cursor"] = [["5.0.1"]]
            elif len(st["outs"]) == 600: st["cursor"] = [list(range(600))]
            else:
                rows = STATE["rows"]
                if vals: rows = [r for r in rows if r["ID"] > vals[0]]
                st["cursor"] = [[r.get(c[0]) for c in COLS_T] for r in rows]
            s.resp(); return
        if kind == 2:
            r = {}
            if "litteraux" in st:
                def lit(x):
                    if x.startswith("'"): return x[1:-1].replace("''", "'")
                    if x.lower() in ("true", "false"): return x.lower() == "true"
                    return float(x) if "." in x else int(x)
                vals = [lit(x) for x in st["litteraux"]]
            for n, v in zip(st["names"], vals):
                if isinstance(v, tuple) and v[0] == "blob": v = STATE["blobs"][v[1]].decode()
                elif isinstance(v, tuple): v = v[1]
                r[n] = v
            if "ID" not in r: r["ID"] = STATE["next_id"]
            STATE["next_id"] = max(STATE["next_id"], r["ID"]) + 1
            if r.get("NOTE") is not None:
                STATE["blobseq"] += 1; bid = struct.pack(">ii", 0, STATE["blobseq"])
                STATE["blobs"][bid] = r["NOTE"].encode(); r["NOTE"] = ("blob", bid)
            if "BIG" not in r: r["BIG"] = 170141183460469231731687303715884105727
            if "TS" not in r: r["TS"] = (60000, 36000000 * 13 + 600000 * 5)
            STATE["rows"].append(r); st["count"] = 1
            if op == 76:
                items = s.parse_blr(outblr); s.wint(78); s.wint(1); s.write_msg(items, [r["ID"]])
            s.resp(); return
        if kind == 4:
            st["count"] = len(STATE["rows"]); STATE["rows"] = []; s.resp(); return
        if kind == 8:
            items = s.parse_blr(outblr); s.wint(78); s.wint(1); s.write_msg(items, [123.45]); s.resp(); return
        s.resp()

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3055
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port)); srv.listen(5)
    while True:
        c, _ = srv.accept()
        def go(c=c):
            try: Conn(c).run()
            except Exception as e:
                import traceback; traceback.print_exc(); LOG.append(("EXCEPTION", repr(e)))
            finally:
                c.close()
                for l in LOG: print(repr(l), flush=True)
                LOG.clear()
        threading.Thread(target=go, daemon=True).start()

main()
