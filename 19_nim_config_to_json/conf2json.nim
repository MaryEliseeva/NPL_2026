# Конвертация блочного конфигурационного формата в JSON.
# Разбор — рекурсивным спуском: для каждой конструкции формата (тело блока, значение,
# список, строка) своя процедура, вложенные блоки разбираются рекурсивным вызовом.

import std/[json, strutils, os]

type
  Parser = object
    src: string
    pos, line, col: int

  ConfigError = object of CatchableError

proc fail(p: Parser, msg: string) {.noreturn.} =
  raise newException(ConfigError, "строка " & $p.line & ", позиция " & $p.col & ": " & msg)

proc atEnd(p: Parser): bool = p.pos >= p.src.len
proc peek(p: Parser, k = 0): char =
  if p.pos + k < p.src.len: p.src[p.pos + k] else: '\0'

proc advance(p: var Parser) =
  if p.peek == '\n':
    inc p.line
    p.col = 1
  else:
    inc p.col
  inc p.pos

proc atComment(p: Parser): bool = p.peek == '#' or (p.peek == '/' and p.peek(1) == '/')

proc skipComment(p: var Parser) =
  while not p.atEnd and p.peek != '\n': p.advance

## Пропуск пробелов (и, если allowNewlines, переводов строк, `;` и комментариев).
proc skipSpace(p: var Parser, allowNewlines: bool) =
  while not p.atEnd:
    let c = p.peek
    if c in {' ', '\t', '\r'}: p.advance
    elif p.atComment: p.skipComment
    elif allowNewlines and c in {'\n', ';'}: p.advance
    else: break

proc isKeyChar(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'} or ord(c) >= 0x80  # байты UTF-8 — тоже буквы

proc parseKey(p: var Parser): string =
  while not p.atEnd and isKeyChar(p.peek):
    result.add p.peek
    p.advance
  if result.len == 0:
    p.fail("ожидалось имя параметра, встречено '" & $p.peek & "'")

proc parseQuoted(p: var Parser): string =
  p.advance  # открывающая кавычка
  while true:
    if p.atEnd or p.peek == '\n': p.fail("незакрытая кавычка")
    let c = p.peek
    p.advance
    case c
    of '"': break
    of '\\':
      let e = p.peek
      p.advance
      case e
      of 'n': result.add '\n'
      of 't': result.add '\t'
      of '"', '\\': result.add e
      else: p.fail("неизвестная escape-последовательность \\" & $e)
    else: result.add c

## Значение без кавычек: число, true/false/null или строка.
proc typed(raw: string): JsonNode =
  case raw
  of "true": return newJBool(true)
  of "false": return newJBool(false)
  of "null": return newJNull()
  else: discard
  try:
    return newJInt(parseBiggestInt(raw))
  except ValueError: discard
  try:
    if raw.len > 0 and raw[0] in {'0'..'9', '-', '+', '.'} and raw.count('.') <= 1:
      return newJFloat(parseFloat(raw))
  except ValueError: discard
  newJString(raw)

proc parseBare(p: var Parser, stopAt: set[char]): JsonNode =
  var raw = ""
  while not p.atEnd and p.peek notin stopAt and not p.atComment:
    raw.add p.peek
    p.advance
  raw = raw.strip
  if raw.len == 0: p.fail("пустое значение")
  typed(raw)

proc parseBody(p: var Parser, nested: bool): JsonNode

proc parseValue(p: var Parser, inList: bool): JsonNode =
  p.skipSpace(allowNewlines = inList)
  case p.peek
  of '"': newJString(p.parseQuoted)
  of '[':
    p.advance
    var arr = newJArray()
    while true:
      p.skipSpace(allowNewlines = true)
      if p.atEnd: p.fail("незакрытый список '['")
      if p.peek == ']':
        p.advance
        break
      arr.add p.parseValue(inList = true)
      p.skipSpace(allowNewlines = true)
      if p.atEnd: p.fail("незакрытый список '['")
      if p.peek == ',': p.advance
      elif p.peek != ']': p.fail("в списке ожидалась ',' или ']'")
    arr
  of '{':
    p.advance
    p.parseBody(nested = true)
  of '\n', '\0': p.fail("после '=' нет значения")
  else:
    if inList: p.parseBare({',', ']', '\n'})
    else: p.parseBare({'\n', ';', '}'})

## Добавляет пару в объект. Повтор блока превращает значение в массив объектов.
proc put(p: Parser, obj: JsonNode, key: string, value: JsonNode, isBlock: bool) =
  if not obj.hasKey(key):
    obj[key] = value
  elif isBlock and obj[key].kind == JObject:
    obj[key] = %[obj[key], value]
  elif isBlock and obj[key].kind == JArray and obj[key].len > 0 and obj[key][0].kind == JObject:
    obj[key].add value
  else:
    p.fail("параметр '" & key & "' задан повторно")

## Тело файла или блока: последовательность «ключ = значение» и «ключ { ... }».
proc parseBody(p: var Parser, nested: bool): JsonNode =
  result = newJObject()
  while true:
    p.skipSpace(allowNewlines = true)
    if p.atEnd:
      if nested: p.fail("не хватает закрывающей '}'")
      return
    if p.peek == '}':
      if not nested: p.fail("лишняя '}'")
      p.advance
      return
    let key = p.parseKey
    p.skipSpace(allowNewlines = false)
    case p.peek
    of '{':
      p.advance
      p.put(result, key, p.parseBody(nested = true), isBlock = true)
    of '=':
      p.advance
      let v = p.parseValue(inList = false)
      p.put(result, key, v, isBlock = v.kind == JObject)
      p.skipSpace(allowNewlines = false)
      if not (p.atEnd or p.peek in {'\n', ';', '}'}):
        p.fail("после значения ожидался конец строки")
    else:
      p.fail("после имени '" & key & "' ожидалось '=' или '{'")

proc convert*(text: string): JsonNode =
  var p = Parser(src: text, pos: 0, line: 1, col: 1)
  p.parseBody(nested = false)

when isMainModule:
  if paramCount() < 1:
    stderr.writeLine "Использование: conf2json <файл.conf> [выход.json]"
    quit 1
  let input = paramStr(1)
  try:
    let json = convert(readFile(input)).pretty(2)
    if paramCount() >= 2:
      writeFile(paramStr(2), json & "\n")
      stderr.writeLine "JSON записан в " & paramStr(2)
    else:
      echo json
  except ConfigError as e:
    stderr.writeLine "Ошибка в " & input & ": " & e.msg
    quit 2
  except IOError as e:
    stderr.writeLine "Не удалось прочитать файл: " & e.msg
    quit 3
