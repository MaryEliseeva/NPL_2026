// Конвертация CSV в SQL: CREATE TABLE + INSERT.
// Разбор CSV по RFC 4180 (кавычки, запятые и переводы строк внутри полей),
// автоматическое определение разделителя и типов столбцов, экранирование строк.

import java.nio.charset.StandardCharsets

/** Разбор CSV конечным автоматом: символ за символом, с учётом состояния «внутри кавычек». */
List<List<String>> parseCsv(String text, char delim) {
    def rows = []
    def row = []
    def field = new StringBuilder()
    boolean inQuotes = false
    boolean wasQuoted = false
    int i = 0
    while (i < text.length()) {
        char c = text.charAt(i)
        if (inQuotes) {
            if (c == '"' as char) {
                if (i + 1 < text.length() && text.charAt(i + 1) == '"' as char) { field.append('"'); i++ }
                else inQuotes = false
            } else field.append(c)
        } else if (c == '"' as char) {
            inQuotes = true; wasQuoted = true
        } else if (c == delim) {
            row << (wasQuoted ? field.toString() : field.toString().trim()); field = new StringBuilder(); wasQuoted = false
        } else if (c == '\n' as char || c == '\r' as char) {
            if (c == '\r' as char && i + 1 < text.length() && text.charAt(i + 1) == '\n' as char) i++
            row << (wasQuoted ? field.toString() : field.toString().trim()); field = new StringBuilder(); wasQuoted = false
            if (!(row.size() == 1 && row[0] == '')) rows << row   // пустые строки пропускаем
            row = []
        } else field.append(c)
        i++
    }
    if (inQuotes) throw new IllegalArgumentException('незакрытая кавычка в конце файла')
    if (field.length() > 0 || !row.isEmpty()) { row << field.toString().trim(); rows << row }
    rows
}

char detectDelimiter(String text) {
    String firstLine = text.readLines().find { it.trim() } ?: ''
    [',', ';', '\t'].max { d -> firstLine.count(d) } as char
}

// ---------- типы ----------

boolean isInt(String s)  { s ==~ /-?\d{1,18}/ }
boolean isDec(String s)  { s ==~ /-?\d+([.,]\d+)?/ }
boolean isBool(String s) { s.toLowerCase() in ['true', 'false', 'да', 'нет'] }
boolean isDate(String s) { s ==~ /\d{4}-\d{2}-\d{2}/ }

/** Тип столбца — самый узкий тип, которому подходят все непустые значения. */
String inferType(List<String> values) {
    def nonEmpty = values.findAll { it != '' }
    if (nonEmpty.isEmpty()) return 'VARCHAR(255)'
    if (nonEmpty.every { isInt(it) })  return 'BIGINT'
    if (nonEmpty.every { isDec(it) })  return 'DECIMAL(18,4)'
    if (nonEmpty.every { isBool(it) }) return 'BOOLEAN'
    if (nonEmpty.every { isDate(it) }) return 'DATE'
    int maxLen = nonEmpty*.length().max()
    maxLen > 255 ? 'TEXT' : "VARCHAR(${Math.max(16, maxLen * 2)})".toString()
}

/** Имя столбца/таблицы: латиница, цифры, кириллица и _, всё прочее заменяется на _. */
String ident(String name) {
    String s = name.trim().toLowerCase().replaceAll(/[^\p{L}\p{N}_]+/, '_').replaceAll(/^_+|_+$/, '')
    if (!s) s = 'col'
    if (s[0] ==~ /\d/) s = '_' + s
    '"' + s + '"'   // идентификатор в двойных кавычках — безопасен даже для ключевых слов SQL
}

String sqlValue(String v, String type) {
    if (v == '') return 'NULL'
    switch (type) {
        case 'BIGINT': return v
        case 'DECIMAL(18,4)': return v.replace(',', '.')
        case 'BOOLEAN': return (v.toLowerCase() in ['true', 'да']) ? 'TRUE' : 'FALSE'
        default: return "'" + v.replace("'", "''") + "'"   // одинарная кавычка удваивается
    }
}

// ---------- запуск ----------

def cli = args as List
if (cli.isEmpty()) {
    System.err.println 'Использование: groovy csv2sql.groovy <файл.csv> [выход.sql] [--table имя] [--batch N]'
    System.exit(1)
}
String table = null
int batch = 1
def files = []
for (int k = 0; k < cli.size(); k++) {
    if (cli[k] == '--table') table = cli[++k]
    else if (cli[k] == '--batch') batch = cli[++k] as int
    else files << cli[k]
}
File input = new File(files[0])
String output = files.size() > 1 ? files[1] : null
table = ident(table ?: input.name.replaceAll(/\.[^.]*$/, ''))

String text = input.getText('UTF-8')
if (text.startsWith('﻿')) text = text.substring(1)   // убрать BOM
char delim = detectDelimiter(text)
def rows = parseCsv(text, delim)
if (rows.size() < 1) { System.err.println 'Пустой файл'; System.exit(2) }

def header = rows[0]
def data = rows.drop(1)
def problems = []
data.eachWithIndex { r, idx ->
    if (r.size() != header.size()) problems << "запись ${idx + 1}: полей ${r.size()} вместо ${header.size()}"
    while (r.size() < header.size()) r << ''
}
def columns = header.collect { ident(it) }
def types = (0..<header.size()).collect { col -> inferType(data.collect { it[col] }) }

def sql = new StringBuilder()
sql << "-- Сгенерировано из ${input.name}: ${data.size()} строк, разделитель '${delim == '\t' as char ? '\\t' : delim}'\n"
sql << "CREATE TABLE IF NOT EXISTS ${table} (\n"
sql << columns.withIndex().collect { c, i -> "    ${c} ${types[i]}" }.join(',\n')
sql << "\n);\n\n"

def tuples = data.collect { r -> '(' + (0..<header.size()).collect { sqlValue(r[it], types[it]) }.join(', ') + ')' }
tuples.collate(batch).each { chunk ->
    sql << "INSERT INTO ${table} (${columns.join(', ')}) VALUES\n    ${chunk.join(',\n    ')};\n"
}

System.err.println "Таблица ${table}, столбцов ${columns.size()}, строк ${data.size()}"
columns.eachWithIndex { c, i -> System.err.println "  ${c.padRight(16)} ${types[i]}" }
problems.each { System.err.println "  Внимание: ${it}" }

if (output) {
    new File(output).setText(sql.toString(), 'UTF-8')
    System.err.println "SQL записан в ${output}"
} else {
    new PrintStream(System.out, true, 'UTF-8').print(sql.toString())
}
