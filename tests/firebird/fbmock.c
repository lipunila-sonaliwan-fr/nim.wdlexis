/* Bibliothèque factice libfbclient : implémente le sous-ensemble de l'API ISC
 * utilisé par pkg_firebird.nim, avec les structures exactes d'ibase.h, pour
 * tester la liaison (descripteurs XSQLDA, paramètres, types, blobs,
 * transactions) sans serveur Firebird. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef intptr_t ISC_STATUS;
typedef unsigned int FB_API_HANDLE;
typedef int ISC_LONG;
typedef unsigned int ISC_ULONG;
typedef short ISC_SHORT;
typedef char ISC_SCHAR;
typedef struct { ISC_LONG gds_quad_high; ISC_ULONG gds_quad_low; } ISC_QUAD;

typedef struct {
  ISC_SHORT sqltype; ISC_SHORT sqlscale; ISC_SHORT sqlsubtype; ISC_SHORT sqllen;
  ISC_SCHAR *sqldata; ISC_SHORT *sqlind;
  ISC_SHORT sqlname_length; ISC_SCHAR sqlname[32];
  ISC_SHORT relname_length; ISC_SCHAR relname[32];
  ISC_SHORT ownname_length; ISC_SCHAR ownname[32];
  ISC_SHORT aliasname_length; ISC_SCHAR aliasname[32];
} XSQLVAR;

typedef struct {
  ISC_SHORT version; ISC_SCHAR sqldaid[8]; ISC_LONG sqldabc; ISC_SHORT sqln; ISC_SHORT sqld;
  XSQLVAR sqlvar[1];
} XSQLDA;

struct TEB { FB_API_HANDLE *db; int tpb_len; const unsigned char *tpb; };

#define SQL_TEXT 452
#define SQL_VARYING 448
#define SQL_SHORT 500
#define SQL_LONG 496
#define SQL_DOUBLE 480
#define SQL_TIMESTAMP 510
#define SQL_BLOB 520
#define SQL_TYPE_TIME 560
#define SQL_TYPE_DATE 570
#define SQL_INT64 580
#define SQL_INT128 32752
#define SQL_BOOLEAN 32764

#define ERR_IO 335544344
#define ERR_CONSTRAINT 335544347
#define ERR_SYNTAX 335544634

static void ok(ISC_STATUS *s) { s[0] = 1; s[1] = 0; s[2] = 0; }
static ISC_STATUS err(ISC_STATUS *s, ISC_STATUS code) { s[0] = 1; s[1] = code; s[2] = 0; return code; }

/* --- état global --- */
static FB_API_HANDLE next_handle = 100;
static int tr_started, tr_committed, tr_rolled, tr_active;
static char last_user[64], last_pw[64], last_charset[32], last_db[256];
static int last_tpb[32]; static int last_tpb_len;

typedef struct { int used; unsigned char *data; int len; } Blob;
static Blob blobs[64];
typedef struct { FB_API_HANDLE h; int blob; int pos; } OpenBlob;
static OpenBlob openblobs[16];

typedef struct {
  short type, scale, subtype, len, isnull;
  unsigned char data[300];
} Param;

typedef struct {
  FB_API_HANDLE h;
  char sql[2048];
  int kind;          /* 1 select, 2 insert, 3 update, 4 delete, 5 ddl, 8 exec proc */
  int nparams;
  char ptypes[32];
  Param bound[32];
  int nbound;
  int row;
  int executed;
} Stmt;
static Stmt stmts[32];

static Stmt *find_stmt(FB_API_HANDLE h) {
  for (int i = 0; i < 32; i++) if (stmts[i].h == h && h) return &stmts[i];
  return NULL;
}

static int has(const char *sql, const char *w) {
  char low[2048]; int n = (int)strlen(sql); if (n > 2047) n = 2047;
  for (int i = 0; i < n; i++) low[i] = (char)tolower((unsigned char)sql[i]);
  low[n] = 0;
  return strstr(low, w) != NULL;
}

static void setname(XSQLVAR *v, const char *n) {
  v->sqlname_length = (short)strlen(n); memset(v->sqlname, 0, 32); memcpy(v->sqlname, n, strlen(n));
  v->aliasname_length = (short)strlen(n); memset(v->aliasname, 0, 32); memcpy(v->aliasname, n, strlen(n));
}

/* --- erreurs --- */
int fb_interpret(char *buf, unsigned int size, const ISC_STATUS **vec) {
  const ISC_STATUS *v = *vec;
  if (v[0] != 1 || v[1] == 0) return 0;
  const char *m = "erreur inconnue";
  switch (v[1]) {
    case ERR_IO: m = "I/O error during \"open\" operation for file"; break;
    case ERR_CONSTRAINT: m = "validation error for column \"CLIENT\".\"NOM\", value \"*** null ***\""; break;
    case ERR_SYNTAX: m = "Dynamic SQL Error -SQL error code = -104 -Token unknown"; break;
  }
  snprintf(buf, size, "%s", m);
  *vec = v + 2;
  return (int)strlen(buf);
}
ISC_LONG isc_sqlcode(const ISC_STATUS *s) { return s[1] == ERR_CONSTRAINT ? -625 : (s[1] ? -104 : 0); }
void isc_get_client_version(char *buf) { strcpy(buf, "LI-V5.0.0 Mock Firebird"); }

/* --- connexions --- */
ISC_STATUS isc_attach_database(ISC_STATUS *s, short n, const char *name, FB_API_HANDLE *db, short dpblen, const char *dpb) {
  int len = n ? n : (int)strlen(name);
  memcpy(last_db, name, len); last_db[len] = 0;
  if (strstr(last_db, "absente")) return err(s, ERR_IO);
  last_user[0] = last_pw[0] = last_charset[0] = 0;
  for (int i = 1; i < dpblen;) {
    int code = (unsigned char)dpb[i], l = (unsigned char)dpb[i + 1];
    char *dst = code == 28 ? last_user : code == 29 ? last_pw : code == 48 ? last_charset : NULL;
    if (dst) { memcpy(dst, dpb + i + 2, l); dst[l] = 0; }
    i += 2 + l;
  }
  *db = next_handle++;
  ok(s); return 0;
}
ISC_STATUS isc_detach_database(ISC_STATUS *s, FB_API_HANDLE *db) { *db = 0; ok(s); return 0; }

/* --- transactions --- */
ISC_STATUS isc_start_multiple(ISC_STATUS *s, FB_API_HANDLE *tr, short n, void *teb) {
  struct TEB *t = (struct TEB *)teb;
  if (n != 1 || !t->db || *t->db == 0 || t->tpb_len <= 0 || t->tpb[0] != 3) return err(s, ERR_SYNTAX);
  last_tpb_len = t->tpb_len;
  for (int i = 0; i < t->tpb_len && i < 32; i++) last_tpb[i] = t->tpb[i];
  *tr = next_handle++; tr_started++; tr_active++;
  ok(s); return 0;
}
ISC_STATUS isc_commit_transaction(ISC_STATUS *s, FB_API_HANDLE *tr) {
  if (!*tr) return err(s, ERR_SYNTAX);
  *tr = 0; tr_committed++; tr_active--; ok(s); return 0;
}
ISC_STATUS isc_rollback_transaction(ISC_STATUS *s, FB_API_HANDLE *tr) {
  if (!*tr) return err(s, ERR_SYNTAX);
  *tr = 0; tr_rolled++; tr_active--; ok(s); return 0;
}

/* --- instructions --- */
ISC_STATUS isc_dsql_allocate_statement(ISC_STATUS *s, FB_API_HANDLE *db, FB_API_HANDLE *st) {
  if (!*db) return err(s, ERR_SYNTAX);
  for (int i = 0; i < 32; i++) if (!stmts[i].h) {
    memset(&stmts[i], 0, sizeof(Stmt)); stmts[i].h = next_handle++; *st = stmts[i].h; ok(s); return 0;
  }
  return err(s, ERR_SYNTAX);
}
ISC_STATUS isc_dsql_free_statement(ISC_STATUS *s, FB_API_HANDLE *st, unsigned short opt) {
  Stmt *x = find_stmt(*st); if (x) x->h = 0; *st = 0; ok(s); return 0;
}
ISC_STATUS isc_dsql_prepare(ISC_STATUS *s, FB_API_HANDLE *tr, FB_API_HANDLE *st, unsigned short n, const char *sql,
                            unsigned short dialect, XSQLDA *da) {
  Stmt *x = find_stmt(*st);
  if (!x || !*tr || dialect != 3) return err(s, ERR_SYNTAX);
  int len = n ? n : (int)strlen(sql); if (len > 2047) len = 2047;
  memcpy(x->sql, sql, len); x->sql[len] = 0;
  if (has(x->sql, "syntaxe!")) return err(s, ERR_SYNTAX);
  while (*sql == ' ' || *sql == '\n') sql++;
  x->kind = has(x->sql, "insert") ? 2 : has(x->sql, "update") ? 3 : has(x->sql, "delete") ? 4 :
            has(x->sql, "create") ? 5 : has(x->sql, "execute procedure") ? 8 : 1;
  if (x->kind != 1 && strncasecmp(sql, "select", 6) == 0) x->kind = 1;
  x->nparams = 0;
  for (char *p = x->sql; *p; p++) if (*p == '?') x->nparams++;
  // types des paramètres : commentaire « /*T:LVDB*/ » (L long, V varchar, D date, B blob, O booléen, N numeric, F double)
  char *t = strstr(x->sql, "/*T:");
  memset(x->ptypes, 'V', sizeof(x->ptypes));
  if (t) for (int i = 0; t[4 + i] && t[4 + i] != '*' && i < 32; i++) x->ptypes[i] = t[4 + i];
  x->row = 0; x->executed = 0; x->nbound = 0;
  ok(s); return 0;
}

static int sql_info_kind(Stmt *x) { return x->kind; }

ISC_STATUS isc_dsql_sql_info(ISC_STATUS *s, FB_API_HANDLE *st, short ilen, const char *items, short blen, char *buf) {
  Stmt *x = find_stmt(*st); if (!x) return err(s, ERR_SYNTAX);
  memset(buf, 0, blen);
  if (items[0] == 21) { buf[0] = 21; buf[1] = 4; buf[2] = 0; int k = sql_info_kind(x); memcpy(buf + 3, &k, 4); buf[7] = 1; }
  else if (items[0] == 23) {
    int p = 0; buf[p++] = 23; buf[p++] = 0; buf[p++] = 0;
    int counts[4] = { 0, x->kind == 2 ? 1 : 0, x->kind == 3 ? 2 : 0, x->kind == 4 ? 3 : 0 };
    unsigned char codes[4] = { 13, 14, 15, 16 };
    for (int i = 0; i < 4; i++) { buf[p++] = codes[i]; buf[p++] = 4; buf[p++] = 0; memcpy(buf + p, &counts[i], 4); p += 4; }
    buf[p++] = 1;
  }
  ok(s); return 0;
}

/* colonnes du jeu de résultats standard */
const char *mock_last(void);
static int n_out(Stmt *x) {
  if (x->kind == 1 && (has(x->sql, "gen_id") || has(x->sql, "dpb"))) return 1;
  if (x->kind == 1 && has(x->sql, "echo")) return x->nparams;
  if (x->kind == 1 && has(x->sql, "etat")) return 4;
  if (x->kind == 1) return 11;
  if (has(x->sql, "returning")) return 1;
  return 0;
}

ISC_STATUS isc_dsql_describe(ISC_STATUS *s, FB_API_HANDLE *st, unsigned short v, XSQLDA *da) {
  Stmt *x = find_stmt(*st); if (!x || da->version != 1) return err(s, ERR_SYNTAX);
  int n = n_out(x);
  da->sqld = (short)n;
  if (n > da->sqln) { ok(s); return 0; }
  for (int i = 0; i < n; i++) memset(&da->sqlvar[i], 0, sizeof(XSQLVAR));
  if (x->kind == 1 && has(x->sql, "echo")) {
    for (int i = 0; i < n; i++) {
      char t = x->ptypes[i]; XSQLVAR *c = &da->sqlvar[i];
      char nm[8]; snprintf(nm, 8, "P%d", i + 1); setname(c, nm);
      switch (t) {
        case 'L': c->sqltype = SQL_INT64 + 1; c->sqllen = 8; break;
        case 'N': c->sqltype = SQL_INT64 + 1; c->sqllen = 8; c->sqlscale = -2; break;
        case 'F': c->sqltype = SQL_DOUBLE + 1; c->sqllen = 8; break;
        case 'D': c->sqltype = SQL_TYPE_DATE + 1; c->sqllen = 4; break;
        case 'B': c->sqltype = SQL_BLOB + 1; c->sqllen = 8; c->sqlsubtype = 1; break;
        case 'O': c->sqltype = SQL_BOOLEAN + 1; c->sqllen = 1; break;
        default: c->sqltype = SQL_VARYING + 1; c->sqllen = 200; c->sqlsubtype = 4; break;
      }
    }
  } else if (x->kind == 1 && has(x->sql, "gen_id")) {
    da->sqlvar[0].sqltype = SQL_INT64; da->sqlvar[0].sqllen = 8; setname(&da->sqlvar[0], "V");
  } else if (x->kind == 1 && has(x->sql, "dpb")) {
    da->sqlvar[0].sqltype = SQL_VARYING; da->sqlvar[0].sqllen = 400; setname(&da->sqlvar[0], "INFO");
  } else if (x->kind == 1 && has(x->sql, "etat")) {
    const char *names[4] = { "DEBUTS", "VALIDEES", "ANNULEES", "ACTIVES" };
    for (int i = 0; i < 4; i++) { da->sqlvar[i].sqltype = SQL_LONG; da->sqlvar[i].sqllen = 4; setname(&da->sqlvar[i], names[i]); }
  } else if (x->kind == 1) {
    XSQLVAR *c = da->sqlvar;
    c[0].sqltype = SQL_LONG; c[0].sqllen = 4; setname(&c[0], "ID");
    c[1].sqltype = SQL_VARYING + 1; c[1].sqllen = 80; c[1].sqlsubtype = 4; setname(&c[1], "NOM");
    c[2].sqltype = SQL_INT64 + 1; c[2].sqllen = 8; c[2].sqlscale = -2; setname(&c[2], "CREDIT");
    c[3].sqltype = SQL_TYPE_DATE + 1; c[3].sqllen = 4; setname(&c[3], "INSCRIT");
    c[4].sqltype = SQL_TIMESTAMP + 1; c[4].sqllen = 8; setname(&c[4], "MAJ");
    c[5].sqltype = SQL_BLOB + 1; c[5].sqllen = 8; c[5].sqlsubtype = 1; setname(&c[5], "NOTES");
    c[6].sqltype = SQL_BOOLEAN + 1; c[6].sqllen = 1; setname(&c[6], "ACTIF");
    c[7].sqltype = SQL_TEXT + 1; c[7].sqllen = 20; c[7].sqlsubtype = 4; setname(&c[7], "CODE");
    c[8].sqltype = SQL_INT128 + 1; c[8].sqllen = 16; setname(&c[8], "GROS");
    c[9].sqltype = SQL_TYPE_TIME + 1; c[9].sqllen = 4; setname(&c[9], "HEURE");
    c[10].sqltype = SQL_SHORT + 1; c[10].sqllen = 2; c[10].sqlscale = -1; setname(&c[10], "NOTE");
  } else {
    da->sqlvar[0].sqltype = SQL_LONG; da->sqlvar[0].sqllen = 4; setname(&da->sqlvar[0], "ID");
  }
  ok(s); return 0;
}

ISC_STATUS isc_dsql_describe_bind(ISC_STATUS *s, FB_API_HANDLE *st, unsigned short v, XSQLDA *da) {
  Stmt *x = find_stmt(*st); if (!x) return err(s, ERR_SYNTAX);
  da->sqld = (short)x->nparams;
  if (x->nparams > da->sqln) { ok(s); return 0; }
  for (int i = 0; i < x->nparams; i++) {
    XSQLVAR *c = &da->sqlvar[i]; memset(c, 0, sizeof(XSQLVAR));
    switch (x->ptypes[i]) {
      case 'L': case 'N': c->sqltype = SQL_LONG + 1; c->sqllen = 4; break;
      case 'F': c->sqltype = SQL_DOUBLE + 1; c->sqllen = 8; break;
      case 'D': c->sqltype = SQL_TYPE_DATE + 1; c->sqllen = 4; break;
      case 'B': c->sqltype = SQL_BLOB + 1; c->sqllen = 8; c->sqlsubtype = 1; break;
      case 'O': c->sqltype = SQL_BOOLEAN + 1; c->sqllen = 1; break;
      default: c->sqltype = SQL_VARYING + 1; c->sqllen = 400; c->sqlsubtype = 4; break;
    }
  }
  ok(s); return 0;
}

static ISC_STATUS do_execute(ISC_STATUS *s, FB_API_HANDLE *tr, Stmt *x, XSQLDA *in) {
  if (!*tr) return err(s, ERR_SYNTAX);
  int n = in ? in->sqld : 0;
  if (n != x->nparams) return err(s, ERR_SYNTAX);
  x->nbound = n;
  for (int i = 0; i < n; i++) {
    XSQLVAR *c = &in->sqlvar[i]; Param *p = &x->bound[i];
    p->type = c->sqltype; p->scale = c->sqlscale; p->subtype = c->sqlsubtype; p->len = c->sqllen;
    if ((c->sqltype & 1) == 0 || !c->sqlind) return err(s, ERR_SYNTAX);   /* le pilote met toujours le drapeau « nullable » */
    p->isnull = *c->sqlind < 0;
    if (!p->isnull) memcpy(p->data, c->sqldata, c->sqllen > 300 ? 300 : c->sqllen);
  }
  if (has(x->sql, "erreur")) {
    for (int i = 0; i < n; i++) if (x->bound[i].isnull) return err(s, ERR_CONSTRAINT);
  }
  x->executed = 1; x->row = 0;
  ok(s); return 0;
}

ISC_STATUS isc_dsql_execute(ISC_STATUS *s, FB_API_HANDLE *tr, FB_API_HANDLE *st, unsigned short v, XSQLDA *in) {
  Stmt *x = find_stmt(*st); if (!x) return err(s, ERR_SYNTAX);
  return do_execute(s, tr, x, in);
}

static void put_text_varying(XSQLVAR *c, const char *txt) {
  unsigned short l = (unsigned short)strlen(txt); memcpy(c->sqldata, &l, 2); memcpy(c->sqldata + 2, txt, l);
}

static int new_blob(const unsigned char *d, int len) {
  for (int i = 1; i < 64; i++) if (!blobs[i].used) {
    blobs[i].used = 1; blobs[i].data = malloc(len + 1); memcpy(blobs[i].data, d, len); blobs[i].len = len; return i;
  }
  return 0;
}

static int date_of(int y, int m, int d) {  /* jours depuis le 17/11/1858 */
  int a = (14 - m) / 12, yy = y + 4800 - a, mm = m + 12 * a - 3;
  int jdn = d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045;
  return jdn - 2400001;
}

static void fill_row(Stmt *x, XSQLDA *out) {
  int r = x->row;
  if (has(x->sql, "echo")) {
    for (int i = 0; i < out->sqld; i++) {
      XSQLVAR *c = &out->sqlvar[i]; Param *p = &x->bound[i];
      *c->sqlind = p->isnull ? -1 : 0;
      if (p->isnull) continue;
      int bt = p->type & ~1, ct = c->sqltype & ~1;
      if (ct == SQL_VARYING) {
        if (bt == SQL_TEXT) { char tmp[301]; memcpy(tmp, p->data, p->len); tmp[p->len] = 0; put_text_varying(c, tmp); }
        else if (bt == SQL_INT64) { char tmp[64]; long long v; memcpy(&v, p->data, 8); snprintf(tmp, 64, "%lld", v); put_text_varying(c, tmp); }
        else if (bt == SQL_DOUBLE) { char tmp[64]; double v; memcpy(&v, p->data, 8); snprintf(tmp, 64, "%g", v); put_text_varying(c, tmp); }
        else put_text_varying(c, "?");
      } else if (ct == SQL_INT64) {
        long long v = 0;
        if (bt == SQL_INT64) memcpy(&v, p->data, 8);
        else if (bt == SQL_DOUBLE) { double d; memcpy(&d, p->data, 8); v = (long long)(d * 100 + (d >= 0 ? 0.5 : -0.5)); }
        else if (bt == SQL_TEXT) { char tmp[301]; memcpy(tmp, p->data, p->len); tmp[p->len] = 0; v = atoll(tmp); }
        if (c->sqlscale == -2 && bt == SQL_INT64) v *= 100;
        memcpy(c->sqldata, &v, 8);
      } else if (ct == SQL_DOUBLE) {
        double d = 0; if (bt == SQL_DOUBLE) memcpy(&d, p->data, 8); else if (bt == SQL_INT64) { long long v; memcpy(&v, p->data, 8); d = (double)v; }
        memcpy(c->sqldata, &d, 8);
      } else if (ct == SQL_TYPE_DATE) {
        int days = 0;
        if (bt == SQL_TYPE_DATE) memcpy(&days, p->data, 4);
        else if (bt == SQL_TEXT) { int y, m, d; char tmp[64]; memcpy(tmp, p->data, p->len < 63 ? p->len : 63); tmp[p->len < 63 ? p->len : 63] = 0;
          if (sscanf(tmp, "%d.%d.%d", &d, &m, &y) == 3) days = date_of(y, m, d); }
        memcpy(c->sqldata, &days, 4);
      } else if (ct == SQL_BLOB) {
        ISC_QUAD q; memcpy(&q, p->data, 8);
        memcpy(c->sqldata, &q, 8);
      } else if (ct == SQL_BOOLEAN) {
        c->sqldata[0] = bt == SQL_BOOLEAN ? p->data[0] : 9;
      }
    }
    return;
  }
  if (has(x->sql, "gen_id")) { long long v = 7; memcpy(out->sqlvar[0].sqldata, &v, 8); return; }
  if (has(x->sql, "dpb")) { put_text_varying(&out->sqlvar[0], mock_last()); return; }
  if (has(x->sql, "etat")) {
    int vals[4] = { tr_started, tr_committed, tr_rolled, tr_active };
    for (int i = 0; i < 4; i++) memcpy(out->sqlvar[i].sqldata, &vals[i], 4);
    return;
  }
  XSQLVAR *c = out->sqlvar;
  int id = r + 1; memcpy(c[0].sqldata, &id, 4);
  const char *noms[3] = { "Dupont", "Éléonore Durand", "" };
  for (int i = 1; i < out->sqld; i++) *c[i].sqlind = 0;
  put_text_varying(&c[1], noms[r]);
  long long credit = r == 0 ? 12050 : -3; memcpy(c[2].sqldata, &credit, 8);
  int days = date_of(2024, 3, 12) + r; memcpy(c[3].sqldata, &days, 4);
  unsigned int t = ((14 * 60 + 30) * 60 + 15) * 10000 + (r == 1 ? 1234 : 0);
  memcpy(c[4].sqldata, &days, 4); memcpy(c[4].sqldata + 4, &t, 4);
  /* blob texte long (plusieurs segments) */
  char big[5000]; int bl = 0;
  for (int k = 0; k < 300; k++) bl += snprintf(big + bl, sizeof(big) - bl, "%d;", k);
  int bid = new_blob((unsigned char *)big, bl);
  ISC_QUAD q = { 0, (ISC_ULONG)bid }; memcpy(c[5].sqldata, &q, 8);
  c[6].sqldata[0] = (r == 0);
  memset(c[7].sqldata, ' ', 20); memcpy(c[7].sqldata, "AB1", 3);
  /* INT128 : la liaison doit avoir demandé une conversion en VARCHAR */
  if ((c[8].sqltype & ~1) == SQL_VARYING) put_text_varying(&c[8], "123456789012345678901234567890");
  else { int z = 0; memcpy(c[8].sqldata, &z, 4); }
  memcpy(c[9].sqldata, &t, 4);
  short note = 175; memcpy(c[10].sqldata, &note, 2);
  if (r == 2) for (int i = 1; i < out->sqld; i++) *c[i].sqlind = -1;
}

ISC_STATUS isc_dsql_execute2(ISC_STATUS *s, FB_API_HANDLE *tr, FB_API_HANDLE *st, unsigned short v, XSQLDA *in, XSQLDA *out) {
  Stmt *x = find_stmt(*st); if (!x) return err(s, ERR_SYNTAX);
  ISC_STATUS rc = do_execute(s, tr, x, in); if (rc) return rc;
  if (out && out->sqld > 0) { int id = 42; memcpy(out->sqlvar[0].sqldata, &id, 4); if (out->sqlvar[0].sqlind) *out->sqlvar[0].sqlind = 0; }
  ok(s); return 0;
}

ISC_STATUS isc_dsql_fetch(ISC_STATUS *s, FB_API_HANDLE *st, unsigned short v, XSQLDA *out) {
  Stmt *x = find_stmt(*st); if (!x || !x->executed) return err(s, ERR_SYNTAX);
  int nrows = has(x->sql, "echo") || has(x->sql, "etat") || has(x->sql, "gen_id") || has(x->sql, "dpb") ? 1 : 3;
  if (x->row >= nrows) { ok(s); return 100; }
  for (int i = 0; i < out->sqld; i++) {
    XSQLVAR *c = &out->sqlvar[i];
    if (!c->sqldata || ((c->sqltype & 1) && !c->sqlind)) return err(s, ERR_SYNTAX);
  }
  fill_row(x, out);
  x->row++;
  ok(s); return 0;
}

ISC_STATUS isc_dsql_execute_immediate(ISC_STATUS *s, FB_API_HANDLE *db, FB_API_HANDLE *tr, unsigned short n, const char *sql,
                                      unsigned short dialect, XSQLDA *da) {
  if (strncasecmp(sql, "CREATE DATABASE", 15) != 0) return err(s, ERR_SYNTAX);
  memcpy(last_db, sql, n < 255 ? n : 255); last_db[n < 255 ? n : 255] = 0;
  *db = next_handle++; ok(s); return 0;
}

/* --- blobs --- */
ISC_STATUS isc_create_blob2(ISC_STATUS *s, FB_API_HANDLE *db, FB_API_HANDLE *tr, FB_API_HANDLE *bh, ISC_QUAD *id, short l, const char *bpb) {
  int b = new_blob((const unsigned char *)"", 0); if (!b) return err(s, ERR_SYNTAX);
  id->gds_quad_high = 0; id->gds_quad_low = (ISC_ULONG)b;
  for (int i = 0; i < 16; i++) if (!openblobs[i].h) { openblobs[i].h = next_handle++; openblobs[i].blob = b; openblobs[i].pos = 0; *bh = openblobs[i].h; ok(s); return 0; }
  return err(s, ERR_SYNTAX);
}
ISC_STATUS isc_put_segment(ISC_STATUS *s, FB_API_HANDLE *bh, unsigned short n, const char *buf) {
  for (int i = 0; i < 16; i++) if (openblobs[i].h == *bh && *bh) {
    Blob *b = &blobs[openblobs[i].blob];
    b->data = realloc(b->data, b->len + n + 1); memcpy(b->data + b->len, buf, n); b->len += n; ok(s); return 0;
  }
  return err(s, ERR_SYNTAX);
}
ISC_STATUS isc_open_blob2(ISC_STATUS *s, FB_API_HANDLE *db, FB_API_HANDLE *tr, FB_API_HANDLE *bh, ISC_QUAD *id, unsigned short l, const unsigned char *bpb) {
  int b = (int)id->gds_quad_low;
  if (b <= 0 || b >= 64 || !blobs[b].used || !*tr) return err(s, ERR_SYNTAX);
  for (int i = 0; i < 16; i++) if (!openblobs[i].h) { openblobs[i].h = next_handle++; openblobs[i].blob = b; openblobs[i].pos = 0; *bh = openblobs[i].h; ok(s); return 0; }
  return err(s, ERR_SYNTAX);
}
ISC_STATUS isc_get_segment(ISC_STATUS *s, FB_API_HANDLE *bh, unsigned short *actual, unsigned short size, char *buf) {
  for (int i = 0; i < 16; i++) if (openblobs[i].h == *bh && *bh) {
    Blob *b = &blobs[openblobs[i].blob];
    int left = b->len - openblobs[i].pos;
    if (left <= 0) { *actual = 0; return err(s, 335544367); }
    int seg = left < 700 ? left : 700;               /* segments de 700 octets */
    if (seg > size) seg = size;
    memcpy(buf, b->data + openblobs[i].pos, seg); openblobs[i].pos += seg; *actual = (unsigned short)seg;
    if (seg < left && seg == size) return err(s, 335544366);
    ok(s); return 0;
  }
  return err(s, ERR_SYNTAX);
}
ISC_STATUS isc_close_blob(ISC_STATUS *s, FB_API_HANDLE *bh) {
  for (int i = 0; i < 16; i++) if (openblobs[i].h == *bh && *bh) { openblobs[i].h = 0; *bh = 0; ok(s); return 0; }
  return err(s, ERR_SYNTAX);
}

/* --- inspection par le test --- */
const char *mock_last(void) {
  static char out[512];
  char tpb[128] = ""; int p = 0;
  for (int i = 0; i < last_tpb_len && p < 120; i++) p += snprintf(tpb + p, sizeof(tpb) - p, "%d,", last_tpb[i]);
  snprintf(out, sizeof out, "db=%s user=%s pw=%s cs=%s tpb=%s", last_db, last_user, last_pw, last_charset, tpb);
  return out;
}
