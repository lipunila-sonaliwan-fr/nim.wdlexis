# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - éditeur de code : coloration et complétion SQL (DuckDB, SQL Server, ANSI)
#
# Même interface que lexistok.nim (Token, LexState, lexLine) : un document .sql de
# l'éditeur (ou marqué « sql » par ed:langage) est coloré par ce module.

import std/strutils
import lexistok

const
  SqlKeywords* = [
    "select", "from", "where", "group", "by", "having", "order", "limit", "offset", "fetch", "first", "next",
    "rows", "row", "only", "distinct", "all", "as", "on", "using", "join", "inner", "left", "right", "full",
    "outer", "cross", "natural", "asof", "positional", "semi", "anti", "lateral", "union", "intersect", "except",
    "with", "recursive", "materialized", "insert", "into", "values", "default", "update", "set", "delete",
    "merge", "matched", "then", "returning", "create", "or", "replace", "temporary", "temp", "table", "view",
    "index", "unique", "sequence", "schema", "database", "macro", "function", "type", "enum", "secret",
    "if", "not", "exists", "drop", "cascade", "restrict", "alter", "add", "column", "rename", "to",
    "primary", "key", "foreign", "references", "constraint", "check", "null", "is", "and", "in", "between",
    "like", "ilike", "glob", "similar", "escape", "case", "when", "else", "end", "cast", "try_cast",
    "true", "false", "asc", "desc", "nulls", "last", "over", "partition", "window", "range", "groups",
    "preceding", "following", "unbounded", "current", "exclude", "ties", "others", "qualify", "filter",
    "within", "pivot", "unpivot", "for", "attach", "detach", "use", "copy", "export", "import", "load",
    "install", "force", "pragma", "describe", "summarize", "explain", "analyze", "show", "tables",
    "begin", "commit", "rollback", "transaction", "checkpoint", "vacuum", "call", "prepare", "execute",
    "deallocate", "collate", "generated", "always", "stored", "virtual", "returns", "declare", "go", "top",
    "nolock", "identity", "clustered", "nonclustered", "procedure", "proc", "exec", "connect", "disconnect",
    "struct", "map", "list", "array", "union_by_name", "by_name", "sample", "tablesample", "reservoir",
    "bernoulli", "system", "percent", "any", "some", "interval", "at", "time", "zone", "collation"]
  SqlTypes* = [
    "integer", "int", "bigint", "smallint", "tinyint", "hugeint", "uhugeint", "ubigint", "uinteger",
    "usmallint", "utinyint", "decimal", "numeric", "real", "float", "double", "boolean", "bool",
    "varchar", "char", "nvarchar", "nchar", "text", "string", "blob", "bytea", "varbinary", "binary",
    "date", "timestamp", "timestamptz", "datetime", "datetime2", "time", "uuid", "json", "bit", "money"]
  SqlFunctions* = [
    "count", "sum", "avg", "min", "max", "median", "mode", "quantile_cont", "quantile_disc", "stddev",
    "variance", "string_agg", "list", "array_agg", "first", "last", "any_value", "arg_max", "arg_min",
    "approx_count_distinct", "histogram", "bool_and", "bool_or", "row_number", "rank", "dense_rank",
    "percent_rank", "cume_dist", "ntile", "lag", "lead", "first_value", "last_value", "nth_value",
    "coalesce", "nullif", "ifnull", "greatest", "least", "abs", "round", "floor", "ceil", "sqrt", "pow",
    "power", "ln", "log", "exp", "random", "lower", "upper", "length", "trim", "ltrim", "rtrim", "substr",
    "substring", "replace", "concat", "concat_ws", "split_part", "string_split", "regexp_matches",
    "regexp_replace", "regexp_extract", "contains", "starts_with", "ends_with", "lpad", "rpad", "left",
    "right", "strftime", "strptime", "date_trunc", "date_part", "datediff", "date_diff", "date_add",
    "extract", "now", "current_date", "today", "epoch", "make_date", "to_timestamp", "age",
    "read_csv", "read_csv_auto", "read_parquet", "read_json", "read_json_auto", "read_xlsx",
    "parquet_scan", "parquet_metadata", "parquet_schema", "sqlite_scan", "postgres_scan", "glob",
    "duckdb_tables", "duckdb_columns", "duckdb_views", "duckdb_schemas", "duckdb_databases",
    "duckdb_constraints", "duckdb_indexes", "duckdb_functions", "duckdb_settings", "duckdb_extensions",
    "duckdb_dependencies", "pragma_storage_info", "database_size", "json_serialize_sql", "sql_auto_complete",
    "unnest", "generate_series", "range", "struct_pack", "list_value", "len", "hash", "md5", "sha256",
    "quack_query", "quack_serve", "quack_stop"]

proc isWord(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'} or ord(c) >= 128

proc lexSqlLine*(line: string, state: var LexState, depth: var int): seq[Token] =
  ## Jetons d'une ligne SQL ; `state` : commentaire /* */ en cours à la fin de la ligne.
  depth = 0
  var i = 0
  let n = line.len
  if state == lsBlockComment:
    let e = line.find("*/")
    if e < 0:
      if n > 0: result.add Token(kind: tkComment, start: 0, len: n)
      return
    result.add Token(kind: tkComment, start: 0, len: e + 2)
    i = e + 2
    state = lsNormal
  var prevWord = ""
  while i < n:
    let c = line[i]
    if c in {' ', '\t'}:
      inc i
      continue
    if c == '-' and i + 1 < n and line[i + 1] == '-':
      result.add Token(kind: tkComment, start: i, len: n - i)
      break
    if c == '/' and i + 1 < n and line[i + 1] == '*':
      let e = line.find("*/", i + 2)
      if e < 0:
        result.add Token(kind: tkComment, start: i, len: n - i)
        state = lsBlockComment
        break
      result.add Token(kind: tkComment, start: i, len: e + 2 - i)
      i = e + 2
      continue
    if c == '\'':
      var j = i + 1
      while j < n:
        if line[j] == '\'':
          if j + 1 < n and line[j + 1] == '\'': j += 2
          else: break
        else: inc j
      result.add Token(kind: tkString, start: i, len: min(n, j + 1) - i)
      i = j + 1
      continue
    if c == '"' or c == '[' and (i + 1 < n and line[i + 1].isWord) or c == '`':
      let close = if c == '[': ']' else: c
      var j = i + 1
      while j < n and line[j] != close: inc j
      result.add Token(kind: tkText, start: i, len: min(n, j + 1) - i)   # identifiant entre guillemets
      i = j + 1
      continue
    if c in {'0'..'9'} or (c == '.' and i + 1 < n and line[i + 1] in {'0'..'9'}):
      var j = i
      while j < n and (line[j] in {'0'..'9', '.', '_'} or (line[j] in {'e', 'E'} and j + 1 < n and line[j + 1] in {'0'..'9', '-', '+'})):
        inc j
      result.add Token(kind: tkNumber, start: i, len: j - i)
      i = j
      continue
    if c.isWord:
      var j = i
      while j < n and line[j].isWord: inc j
      let w = line[i ..< j].toLowerAscii
      var k = tkText
      var p = j
      while p < n and line[p] == ' ': inc p
      if w in SqlKeywords and not (p < n and line[p] == '(' and w in ["left", "right", "replace", "range", "list", "if", "filter", "first", "last"]):
        k = tkKeyword
      elif w in SqlTypes: k = tkType
      elif p < n and line[p] == '(': k = (if w in SqlFunctions: tkBuiltin else: tkProcName)
      elif prevWord in ["from", "join", "into", "table", "update", "view", "references"]: k = tkType
      result.add Token(kind: k, start: i, len: j - i)
      prevWord = w
      i = j
      continue
    if c in {'(', ')', ',', ';', '.', '[', ']', '{', '}'}:
      result.add Token(kind: tkPunct, start: i, len: 1)
    elif c in {'$', '?', ':'} and i + 1 < n and (line[i + 1].isWord):
      var j = i + 1
      while j < n and line[j].isWord: inc j
      result.add Token(kind: tkPragma, start: i, len: j - i)      # paramètres $1, ?, :nom
      i = j
      continue
    else:
      result.add Token(kind: tkOperator, start: i, len: 1)
    inc i
