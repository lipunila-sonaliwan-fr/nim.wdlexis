// CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
// wdlexis+ - bibliothèque « wdlexis_lucene » : pont C entre le paquet lucene
// (pkg_lucene.nim, chargé à l'exécution) et Lucene++ (portage C++ de Lucene 3.0).
//
// Interface C :
//   char* wdlx_lucene_appel(const char* requete)   requête et réponse en JSON (UTF-8)
//   void  wdlx_lucene_liberer(char* reponse)
// Réponse : {"ok":true,"r":...} ou {"ok":false,"erreur":"..."}.
//
// Construction : voir outils/lucenepp.sh (Lucene++ et Boost liés statiquement :
// une seule bibliothèque à distribuer, dans linOS / macOS / winOS).

#if defined(_WIN32)
// Comme Lucene++ (LuceneInc.h, targetver.h) : windows.h réduit, sans les macros
// min/max, et winsock2.h avant windows.h (sinon Boost.Asio refuse de compiler).
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WINVER
#define WINVER 0x0501
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <winsock2.h>
#include <windows.h>
#endif

#include <lucene++/LuceneHeaders.h>
#include <lucene++/FileUtils.h>
#include <lucene++/MiscUtils.h>
#include <lucene++/MultiFieldQueryParser.h>
#include <lucene++/NumericRangeQuery.h>
#include <lucene++/NumericField.h>
#include <lucene++/KeywordAnalyzer.h>
#include <lucene++/PerFieldAnalyzerWrapper.h>
#include <lucene++/WhitespaceAnalyzer.h>
#include <lucene++/SimpleAnalyzer.h>
#include <lucene++/StopAnalyzer.h>
#include <lucene++/FieldCache.h>
#include <lucene++/SortField.h>
#include <lucene++/Sort.h>
#include <lucene++/TopFieldDocs.h>
#include <lucene++/MatchAllDocsQuery.h>
#include <lucene++/TermEnum.h>
#include <lucene++/RAMDirectory.h>
#include <lucene++/LuceneException.h>
#include <lucene++/StringUtils.h>
#include <lucene++/Constants.h>
#include "FrenchAnalyzer.h"
#include "GermanAnalyzer.h"
#include "SnowballAnalyzer.h"
#include "DutchAnalyzer.h"
#include "RussianAnalyzer.h"
#include "BrazilianAnalyzer.h"

#include <cstdlib>
#include <cstring>
#include <cmath>
#include <climits>
#include <cfloat>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <memory>
#include <algorithm>
#include <boost/algorithm/string/predicate.hpp>
#include <vector>

using namespace Lucene;

#if defined(_WIN32)
#define WDLX_EXPORT extern "C" __declspec(dllexport)
#else
#define WDLX_EXPORT extern "C" __attribute__((visibility("default")))
#endif

// ------------------------------------------------------------------ JSON

namespace {

struct JV {
    enum T { NUL, BOOL, INT, NUM, STR, ARR, OBJ } t = NUL;
    bool b = false;
    int64_t i = 0;
    double d = 0;
    std::string s;
    std::vector<JV> a;
    std::vector<std::pair<std::string, JV>> o;

    const JV* get(const std::string& k) const {
        for (auto& p : o) if (p.first == k) return &p.second;
        return nullptr;
    }
    JV& set(const std::string& k, JV v) {
        for (auto& p : o) if (p.first == k) { p.second = std::move(v); return p.second; }
        o.emplace_back(k, std::move(v));
        return o.back().second;
    }
};

JV jnull() { return JV(); }
JV jbool(bool b) { JV v; v.t = JV::BOOL; v.b = b; return v; }
JV jint(int64_t i) { JV v; v.t = JV::INT; v.i = i; return v; }
JV jnum(double d) { JV v; v.t = JV::NUM; v.d = d; return v; }
JV jstr(const std::string& s) { JV v; v.t = JV::STR; v.s = s; return v; }
JV jarr() { JV v; v.t = JV::ARR; return v; }
JV jobj() { JV v; v.t = JV::OBJ; return v; }

struct JsonParser {
    const std::string& s;
    size_t p = 0;
    explicit JsonParser(const std::string& src) : s(src) {}
    void ws() { while (p < s.size() && (s[p] == ' ' || s[p] == '\n' || s[p] == '\r' || s[p] == '\t')) p++; }
    void fail(const char* m) { throw std::runtime_error(std::string("JSON : ") + m); }
    static void utf8(std::string& out, uint32_t c) {
        if (c < 0x80) out += char(c);
        else if (c < 0x800) { out += char(0xC0 | (c >> 6)); out += char(0x80 | (c & 0x3F)); }
        else if (c < 0x10000) { out += char(0xE0 | (c >> 12)); out += char(0x80 | ((c >> 6) & 0x3F)); out += char(0x80 | (c & 0x3F)); }
        else { out += char(0xF0 | (c >> 18)); out += char(0x80 | ((c >> 12) & 0x3F)); out += char(0x80 | ((c >> 6) & 0x3F)); out += char(0x80 | (c & 0x3F)); }
    }
    std::string str() {
        p++;
        std::string r;
        while (true) {
            if (p >= s.size()) fail("chaîne non terminée");
            char c = s[p++];
            if (c == '"') return r;
            if (c != '\\') { r += c; continue; }
            char e = s[p++];
            switch (e) {
            case 'n': r += '\n'; break;
            case 't': r += '\t'; break;
            case 'r': r += '\r'; break;
            case 'b': r += '\b'; break;
            case 'f': r += '\f'; break;
            case 'u': {
                uint32_t c1 = std::stoul(s.substr(p, 4), nullptr, 16);
                p += 4;
                if (c1 >= 0xD800 && c1 < 0xDC00 && p + 6 <= s.size() && s[p] == '\\' && s[p + 1] == 'u') {
                    uint32_t c2 = std::stoul(s.substr(p + 2, 4), nullptr, 16);
                    p += 6;
                    c1 = 0x10000 + ((c1 - 0xD800) << 10) + (c2 - 0xDC00);
                }
                utf8(r, c1);
                break;
            }
            default: r += e;
            }
        }
    }
    JV value() {
        ws();
        if (p >= s.size()) fail("fin inattendue");
        char c = s[p];
        if (c == '{') {
            p++;
            JV o = jobj();
            ws();
            if (s[p] == '}') { p++; return o; }
            while (true) {
                ws();
                std::string k = str();
                ws();
                p++;  // ':'
                o.o.emplace_back(k, value());
                ws();
                char d = s[p++];
                if (d == '}') return o;
            }
        }
        if (c == '[') {
            p++;
            JV a = jarr();
            ws();
            if (s[p] == ']') { p++; return a; }
            while (true) {
                a.a.push_back(value());
                ws();
                char d = s[p++];
                if (d == ']') return a;
            }
        }
        if (c == '"') return jstr(str());
        if (s.compare(p, 4, "true") == 0) { p += 4; return jbool(true); }
        if (s.compare(p, 5, "false") == 0) { p += 5; return jbool(false); }
        if (s.compare(p, 4, "null") == 0) { p += 4; return jnull(); }
        size_t b = p;
        bool real = false;
        while (p < s.size() && strchr("+-0123456789.eE", s[p])) { if (strchr(".eE", s[p])) real = true; p++; }
        std::string n = s.substr(b, p - b);
        if (n.empty()) fail("valeur invalide");
        return real ? jnum(std::strtod(n.c_str(), nullptr)) : jint(std::strtoll(n.c_str(), nullptr, 10));
    }
};

void quote(std::string& out, const std::string& s) {
    out += '"';
    for (unsigned char c : s) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
            else out += char(c);
        }
    }
    out += '"';
}

void write(std::string& out, const JV& v) {
    switch (v.t) {
    case JV::NUL: out += "null"; break;
    case JV::BOOL: out += v.b ? "true" : "false"; break;
    case JV::INT: out += std::to_string(v.i); break;
    case JV::NUM: {
        if (std::isnan(v.d) || std::isinf(v.d)) { out += "null"; break; }
        char b[32];
        snprintf(b, sizeof b, "%.17g", v.d);
        out += b;
        if (!strpbrk(b, ".eEn")) out += ".0";
        break;
    }
    case JV::STR: quote(out, v.s); break;
    case JV::ARR: {
        out += '[';
        for (size_t i = 0; i < v.a.size(); i++) { if (i) out += ','; write(out, v.a[i]); }
        out += ']';
        break;
    }
    case JV::OBJ: {
        out += '{';
        for (size_t i = 0; i < v.o.size(); i++) {
            if (i) out += ',';
            quote(out, v.o[i].first);
            out += ':';
            write(out, v.o[i].second);
        }
        out += '}';
        break;
    }
    }
}

// ------------------------------------------------------------------ valeurs

String W(const std::string& s) { return StringUtils::toUnicode(s); }
std::string U(const String& s) { return StringUtils::toUTF8(s); }

std::string text(const JV* v) {
    if (!v) return "";
    switch (v->t) {
    case JV::STR: return v->s;
    case JV::INT: return std::to_string(v->i);
    case JV::NUM: {
        if (v->d == std::floor(v->d) && std::fabs(v->d) < 1e15) return std::to_string(int64_t(v->d));
        char b[32];
        snprintf(b, sizeof b, "%.17g", v->d);
        return b;
    }
    case JV::BOOL: return v->b ? "vrai" : "faux";
    default: return "";
    }
}

int64_t integer(const JV* v) {
    if (!v) return 0;
    if (v->t == JV::INT) return v->i;
    if (v->t == JV::NUM) return int64_t(v->d);
    if (v->t == JV::BOOL) return v->b ? 1 : 0;
    std::string t = text(v);
    size_t used = 0;
    int64_t r = std::stoll(t, &used);
    return r;
}

double real(const JV* v) {
    if (!v) return 0;
    if (v->t == JV::INT) return double(v->i);
    if (v->t == JV::NUM) return v->d;
    std::string t = text(v);
    for (auto& c : t) if (c == ',') c = '.';
    return std::stod(t);
}

std::string lower(std::string s) {
    for (auto& c : s) if (c >= 'A' && c <= 'Z') c = char(c - 'A' + 'a');
    return s;
}

// ------------------------------------------------------------------ index

struct Index {
    DirectoryPtr dir;
    IndexWriterPtr writer;
    IndexReaderPtr reader;
    AnalyzerPtr analyzer;
    std::vector<std::pair<std::string, std::string>> schema;  // champ -> type, dans l'ordre
    std::string analyzerName;
    bool dirty = true;

    std::string typeOf(const std::string& f) const {
        for (auto& p : schema) if (p.first == f) return p.second;
        return "";
    }
    void setType(const std::string& f, const std::string& t) {
        for (auto& p : schema) if (p.first == f) { p.second = t; return; }
        schema.emplace_back(f, t);
    }
};

std::mutex gLock;
std::map<int64_t, Index*> gIndex;
int64_t gNext = 1;
const char* SchemaKey = "wdlexis.schema";
const char* AnalyzerKey = "wdlexis.analyseur";

std::string checkType(const std::string& t0) {
    std::string t = lower(t0);
    if (t == "clé") t = "cle";
    if (t == "réel") t = "reel";
    if (t == "stocké") t = "stocke";
    if (t == "texte" || t == "cle" || t == "entier" || t == "reel" || t == "stocke" || t == "index") return t;
    throw std::runtime_error("type de champ inconnu : « " + t0 + " » (texte, cle, entier, reel, stocke, index)");
}

AnalyzerPtr makeAnalyzer(const std::string& n0) {
    std::string n = lower(n0);
    LuceneVersion::Version v = LuceneVersion::LUCENE_CURRENT;
    if (n.empty() || n == "standard") return newLucene<StandardAnalyzer>(v);
    if (n == "francais" || n == "français" || n == "fr") return newLucene<FrenchAnalyzer>(v);
    if (n == "allemand" || n == "de") return newLucene<GermanAnalyzer>(v);
    if (n == "neerlandais" || n == "néerlandais" || n == "nl") return newLucene<DutchAnalyzer>(v);
    if (n == "russe" || n == "ru") return newLucene<RussianAnalyzer>(v);
    if (n == "bresilien" || n == "brésilien" || n == "pt-br") return newLucene<BrazilianAnalyzer>(v);
    if (n == "anglais" || n == "en") return newLucene<SnowballAnalyzer>(v, L"English", StopAnalyzer::ENGLISH_STOP_WORDS_SET());
    if (n == "espagnol" || n == "es") return newLucene<SnowballAnalyzer>(v, L"Spanish");
    if (n == "italien" || n == "it") return newLucene<SnowballAnalyzer>(v, L"Italian");
    if (n == "portugais" || n == "pt") return newLucene<SnowballAnalyzer>(v, L"Portuguese");
    if (n == "simple") return newLucene<SimpleAnalyzer>();
    if (n == "espaces") return newLucene<WhitespaceAnalyzer>();
    if (n == "mot" || n == "exact") return newLucene<KeywordAnalyzer>();
    throw std::runtime_error("analyseur inconnu : « " + n0 + " » (standard, francais, anglais, allemand, espagnol, "
                             "italien, portugais, neerlandais, russe, bresilien, simple, espaces)");
}

std::string schemaJson(const Index& ix) {
    JV o = jobj();
    for (auto& p : ix.schema) o.set(p.first, jstr(p.second));
    std::string out;
    write(out, o);
    return out;
}

void commit(Index& ix) {
    MapStringString data(MapStringString::newInstance());
    data.put(W(SchemaKey), W(schemaJson(ix)));
    data.put(W(AnalyzerKey), W(ix.analyzerName));
    ix.writer->commit(data);
}

IndexReaderPtr reader(Index& ix) {
    if (ix.dirty || !ix.reader) {
        IndexReaderPtr r = ix.writer->getReader();     // lecture quasi temps réel : modifications visibles
        if (ix.reader) ix.reader->close();
        ix.reader = r;
        ix.dirty = false;
    }
    return ix.reader;
}

std::string keyField(const Index& ix) {
    for (auto& p : ix.schema) if (p.second == "cle") return p.first;
    return "";
}

// ---- documents

void addValue(DocumentPtr& doc, const std::string& name, const std::string& t, const JV& x) {
    String n = W(name);
    if (t == "texte") doc->add(newLucene<Field>(n, W(text(&x)), Field::STORE_YES, Field::INDEX_ANALYZED));
    else if (t == "index") doc->add(newLucene<Field>(n, W(text(&x)), Field::STORE_NO, Field::INDEX_ANALYZED));
    else if (t == "cle") doc->add(newLucene<Field>(n, W(text(&x)), Field::STORE_YES, Field::INDEX_NOT_ANALYZED_NO_NORMS));
    else if (t == "entier") doc->add(newLucene<NumericField>(n, Field::STORE_YES, true)->setLongValue(integer(&x)));
    else if (t == "reel") doc->add(newLucene<NumericField>(n, Field::STORE_YES, true)->setDoubleValue(real(&x)));
    else doc->add(newLucene<Field>(n, W(text(&x)), Field::STORE_YES, Field::INDEX_NO));
}

DocumentPtr makeDocument(Index& ix, const JV* d) {
    DocumentPtr doc = newLucene<Document>();
    if (!d || d->t != JV::OBJ) return doc;
    for (auto& p : d->o) {
        const JV& v = p.second;
        if (v.t == JV::NUL) continue;
        std::vector<const JV*> vals;
        if (v.t == JV::ARR) for (auto& x : v.a) { if (x.t != JV::NUL) vals.push_back(&x); }
        else vals.push_back(&v);
        if (vals.empty()) continue;
        std::string t = ix.typeOf(p.first);
        if (t.empty()) {
            const JV* f = vals[0];
            t = f->t == JV::INT ? "entier" : f->t == JV::NUM ? "reel" : f->t == JV::BOOL ? "cle" : "texte";
            ix.setType(p.first, t);
        }
        for (auto* x : vals) addValue(doc, p.first, t, *x);
    }
    return doc;
}

JV toJson(const Index& ix, const DocumentPtr& d) {
    JV o = jobj();
    Collection<FieldablePtr> fields = d->getFields();
    for (Collection<FieldablePtr>::iterator f = fields.begin(); f != fields.end(); ++f) {
        std::string n = U((*f)->name());
        std::string s = U((*f)->stringValue());
        std::string t = ix.typeOf(n);
        JV v = jstr(s);
        try {
            if (t == "entier") v = jint(std::stoll(s));
            else if (t == "reel") v = jnum(std::stod(s));
        } catch (...) {}
        const JV* old = o.get(n);
        if (!old) o.set(n, v);
        else if (old->t == JV::ARR) { JV a = *old; a.a.push_back(v); o.set(n, a); }
        else { JV a = jarr(); a.a.push_back(*old); a.a.push_back(v); o.set(n, a); }
    }
    return o;
}

// ---- requêtes : intervalles et valeurs exactes sur les champs numériques

class WdlxParser : public MultiFieldQueryParser {
public:
    WdlxParser(Collection<String> fields, const AnalyzerPtr& a, Index* ix)
        : MultiFieldQueryParser(LuceneVersion::LUCENE_CURRENT, fields, a), ix(ix) {}
    virtual ~WdlxParser() {}
    LUCENE_CLASS(WdlxParser);

    Index* ix;

protected:
    static bool open(const String& s) { return s.empty() || s == L"*"; }

    virtual QueryPtr getRangeQuery(const String& field, const String& part1, const String& part2, bool inclusive) {
        std::string t = field.empty() ? "" : ix->typeOf(U(field));
        if (t == "entier") {
            int64_t a = open(part1) ? LLONG_MIN : std::stoll(U(part1));
            int64_t b = open(part2) ? LLONG_MAX : std::stoll(U(part2));
            return NumericRangeQuery::newLongRange(field, a, b, inclusive, inclusive);
        }
        if (t == "reel") {
            double a = open(part1) ? -DBL_MAX : std::stod(U(part1));
            double b = open(part2) ? DBL_MAX : std::stod(U(part2));
            return NumericRangeQuery::newDoubleRange(field, a, b, inclusive, inclusive);
        }
        return MultiFieldQueryParser::getRangeQuery(field, part1, part2, inclusive);
    }

    virtual QueryPtr getFieldQuery(const String& field, const String& queryText) {
        std::string t = field.empty() ? "" : ix->typeOf(U(field));
        if (t == "entier") {
            int64_t v = std::stoll(U(queryText));
            return NumericRangeQuery::newLongRange(field, v, v, true, true);
        }
        if (t == "reel") {
            double v = std::stod(U(queryText));
            return NumericRangeQuery::newDoubleRange(field, v, v, true, true);
        }
        return MultiFieldQueryParser::getFieldQuery(field, queryText);
    }
};

QueryPtr makeQuery(Index& ix, const std::string& q0, const JV* champs) {
    std::string q = q0;
    size_t b = q.find_first_not_of(" \t\r\n"), e = q.find_last_not_of(" \t\r\n");
    q = b == std::string::npos ? "" : q.substr(b, e - b + 1);
    if (q.empty() || q == "*" || q == "*:*") return newLucene<MatchAllDocsQuery>();
    Collection<String> fields(Collection<String>::newInstance());
    if (champs && champs->t == JV::ARR) for (auto& c : champs->a) fields.add(W(text(&c)));
    if (fields.empty()) for (auto& p : ix.schema) if (p.second == "texte" || p.second == "index") fields.add(W(p.first));
    if (fields.empty()) fields.add(L"texte");
    // champs « cle » : valeur exacte, sans analyse
    PerFieldAnalyzerWrapperPtr pa = newLucene<PerFieldAnalyzerWrapper>(ix.analyzer);
    AnalyzerPtr kw = newLucene<KeywordAnalyzer>();
    for (auto& p : ix.schema) if (p.second == "cle") pa->addAnalyzer(W(p.first), kw);
    QueryParserPtr p = newLucene<WdlxParser>(fields, pa, &ix);
    p->setAllowLeadingWildcard(true);
    p->setDefaultOperator(QueryParser::AND_OPERATOR);
    p->setLowercaseExpandedTerms(true);
    return p->parse(W(q));
}

// ---- opérations

int64_t num(const JV* v, int64_t def) { return v && (v->t == JV::INT || v->t == JV::NUM) ? integer(v) : def; }

JV opOpen(const JV& q) {
    std::string dossier = text(q.get("dossier"));
    DirectoryPtr dir;
    if (dossier.empty()) dir = newLucene<RAMDirectory>();
    else dir = FSDirectory::open(W(dossier));
    bool exists = IndexReader::indexExists(dir);
    const JV* creer = q.get("creer");
    if (!exists && creer && creer->t == JV::BOOL && !creer->b) throw std::runtime_error("aucun index dans " + dossier);
    std::unique_ptr<Index> ix(new Index());
    ix->dir = dir;
    std::string an = text(q.get("analyseur"));
    if (exists) {
        MapStringString data = IndexReader::getCommitUserData(dir);
        if (data.contains(W(SchemaKey))) {
            std::string sj = U(data.get(W(SchemaKey)));
            JsonParser ps(sj);
            JV s = ps.value();
            for (auto& p : s.o) ix->schema.emplace_back(p.first, text(&p.second));
        }
        if (an.empty() && data.contains(W(AnalyzerKey))) an = U(data.get(W(AnalyzerKey)));
    }
    const JV* sc = q.get("schema");
    if (sc && sc->t == JV::OBJ) for (auto& p : sc->o) ix->setType(p.first, checkType(text(&p.second)));
    ix->analyzerName = an;
    ix->analyzer = makeAnalyzer(an);
    ix->writer = newLucene<IndexWriter>(dir, ix->analyzer, !exists, IndexWriter::MaxFieldLengthUNLIMITED);
    if (!exists) commit(*ix);
    int64_t h = gNext++;
    gIndex[h] = ix.release();
    return jint(h);
}

JV opSearch(Index& ix, const JV& q) {
    QueryPtr query = makeQuery(ix, text(q.get("requete")), q.get("champs"));
    int64_t debut = std::max<int64_t>(0, num(q.get("debut"), 0));
    int64_t max = std::max<int64_t>(1, num(q.get("max"), 10));
    std::string tri = text(q.get("tri"));
    IndexSearcherPtr s = newLucene<IndexSearcher>(reader(ix));
    TopDocsPtr top;
    if (tri.empty() || tri == "score") top = s->search(query, FilterPtr(), int32_t(debut + max));
    else {
        std::string t = ix.typeOf(tri);
        const JV* inv = q.get("inverse");
        bool reverse = inv && inv->t == JV::BOOL && inv->b;
        SortFieldPtr sf;
        if (t == "entier") sf = newLucene<SortField>(W(tri), FieldCache::NUMERIC_UTILS_LONG_PARSER(), reverse);
        else if (t == "reel") sf = newLucene<SortField>(W(tri), FieldCache::NUMERIC_UTILS_DOUBLE_PARSER(), reverse);
        else if (t == "cle") sf = newLucene<SortField>(W(tri), SortField::STRING, reverse);
        else if (t.empty()) throw std::runtime_error("tri : champ inconnu « " + tri + " »");
        else throw std::runtime_error("tri : « " + tri + " » doit être de type cle, entier ou reel");
        s->setDefaultFieldSortScoring(true, false);
        top = s->search(query, FilterPtr(), int32_t(debut + max), newLucene<Sort>(sf));
    }
    JV res = jarr();
    for (int32_t i = int32_t(debut); i < top->scoreDocs.size(); i++) {
        ScoreDocPtr sd = top->scoreDocs[i];
        JV r = jobj();
        r.set("score", jnum(std::isnan(sd->score) ? 0.0 : double(sd->score)));
        r.set("numero", jint(sd->doc));
        r.set("document", toJson(ix, s->doc(sd->doc)));
        res.a.push_back(r);
    }
    JV out = jobj();
    out.set("total", jint(top->totalHits));
    out.set("resultats", res);
    return out;
}

JV opTerms(Index& ix, const JV& q) {
    String champ = W(text(q.get("champ")));
    String prefixe = W(text(q.get("prefixe")));
    int64_t max = num(q.get("max"), 20);
    JV res = jarr();
    TermEnumPtr te = reader(ix)->terms(newLucene<Term>(champ, prefixe));
    for (int64_t n = 0; n < max;) {
        TermPtr t = te->term();
        if (!t || t->field() != champ) break;
        String v = t->text();
        if (!boost::starts_with(v, prefixe)) break;
        JV r = jobj();
        r.set("terme", jstr(U(v)));
        r.set("documents", jint(te->docFreq()));
        res.a.push_back(r);
        n++;
        if (!te->next()) break;
    }
    te->close();
    return res;
}

JV dispatch(const JV& q) {
    std::string op = text(q.get("op"));
    if (op == "version") return jstr("Lucene++ " + U(Constants::LUCENE_VERSION));
    if (op == "ouvrir") return opOpen(q);
    int64_t h = num(q.get("h"), 0);
    auto it = gIndex.find(h);
    if (it == gIndex.end()) throw std::runtime_error("index fermé");
    Index& ix = *it->second;
    if (op == "ajouter") { ix.writer->addDocument(makeDocument(ix, q.get("doc"))); ix.dirty = true; return jbool(true); }
    if (op == "remplacer") {
        const JV* d = q.get("doc");
        std::string cle = text(q.get("cle"));
        if (cle.empty()) cle = keyField(ix);
        if (cle.empty()) throw std::runtime_error("remplacer : aucun champ de type « cle » dans le schéma");
        const JV* v = d ? d->get(cle) : nullptr;
        if (!v) throw std::runtime_error("remplacer : le document n'a pas de champ « " + cle + " »");
        ix.writer->updateDocument(newLucene<Term>(W(cle), W(text(v))), makeDocument(ix, d));
        ix.dirty = true;
        return jbool(true);
    }
    if (op == "supprimer") {
        if (q.get("requete")) ix.writer->deleteDocuments(makeQuery(ix, text(q.get("requete")), nullptr));
        else ix.writer->deleteDocuments(newLucene<Term>(W(text(q.get("champ"))), W(text(q.get("valeur")))));
        ix.dirty = true;
        return jbool(true);
    }
    if (op == "vider") { ix.writer->deleteAll(); ix.dirty = true; return jbool(true); }
    if (op == "valider") { commit(ix); return jbool(true); }
    if (op == "optimiser") { ix.writer->optimize(); commit(ix); ix.dirty = true; return jbool(true); }
    if (op == "chercher") return opSearch(ix, q);
    if (op == "compter") {
        IndexSearcherPtr s = newLucene<IndexSearcher>(reader(ix));
        TopDocsPtr top = s->search(makeQuery(ix, text(q.get("requete")), q.get("champs")), FilterPtr(), 1);
        return jint(top->totalHits);
    }
    if (op == "nombre") return jint(reader(ix)->numDocs());
    if (op == "analyser") return jstr(U(makeQuery(ix, text(q.get("requete")), q.get("champs"))->toString()));
    if (op == "schema") { JV o = jobj(); for (auto& p : ix.schema) o.set(p.first, jstr(p.second)); return o; }
    if (op == "termes") return opTerms(ix, q);
    if (op == "fermer") {
        commit(ix);
        gIndex.erase(it);
        if (ix.reader) ix.reader->close();
        ix.writer->close();
        ix.dir->close();
        delete &ix;
        return jbool(true);
    }
    throw std::runtime_error("opération inconnue : " + op);
}

char* dup(const std::string& s) {
    char* r = static_cast<char*>(std::malloc(s.size() + 1));
    std::memcpy(r, s.c_str(), s.size() + 1);
    return r;
}

} // namespace

WDLX_EXPORT char* wdlx_lucene_appel(const char* requete) {
    std::lock_guard<std::mutex> g(gLock);
    JV rep = jobj();
    try {
        std::string src(requete ? requete : "");
        JsonParser p(src);
        JV q = p.value();
        rep.set("ok", jbool(true));
        rep.set("r", dispatch(q));
    } catch (LuceneException& e) {
        rep = jobj();
        rep.set("ok", jbool(false));
        rep.set("erreur", jstr(U(e.getError())));
    } catch (std::exception& e) {
        rep = jobj();
        rep.set("ok", jbool(false));
        rep.set("erreur", jstr(e.what()));
    } catch (...) {
        rep = jobj();
        rep.set("ok", jbool(false));
        rep.set("erreur", jstr("erreur inconnue"));
    }
    std::string out;
    write(out, rep);
    return dup(out);
}

WDLX_EXPORT void wdlx_lucene_liberer(char* reponse) { std::free(reponse); }
