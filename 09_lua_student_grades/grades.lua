-- Анализ файла с оценками студентов и формирование статистики.
-- Читает CSV (студент;группа;предмет;оценка), считает средние по студентам,
-- предметам и группам, распределение оценок, отличников и должников.
-- Отчёт выводится в консоль и записывается в файл.

local input  = arg[1] or "grades.csv"
local output = arg[2] or "report.txt"

-- string.format считает байты, а кириллица в UTF-8 занимает 2 байта на букву,
-- поэтому выравнивание делаем по числу символов (utf8.len).
local function pad(s, n)
  s = tostring(s)
  return s .. string.rep(" ", math.max(0, n - (utf8.len(s) or #s)))
end

local function split(line, sep)
  local fields = {}
  for field in (line .. sep):gmatch("(.-)" .. sep) do
    fields[#fields + 1] = field:match("^%s*(.-)%s*$")
  end
  return fields
end

local function avg(list)
  local s = 0
  for _, v in ipairs(list) do s = s + v end
  return #list > 0 and s / #list or 0
end

-- ---------- чтение ----------
local file, err = io.open(input, "r")
if not file then
  io.stderr:write("Не удалось открыть файл: " .. err .. "\n")
  os.exit(1)
end

local records, errors = {}, {}
local lineNo = 0
for line in file:lines() do
  lineNo = lineNo + 1
  if lineNo > 1 and line:match("%S") then
    local f = split(line, ";")
    local grade = tonumber(f[4])
    if #f ~= 4 then
      errors[#errors + 1] = ("строка %d: ожидалось 4 поля, получено %d"):format(lineNo, #f)
    elseif not grade or grade < 2 or grade > 5 or grade % 1 ~= 0 then
      errors[#errors + 1] = ("строка %d: некорректная оценка «%s»"):format(lineNo, f[4])
    else
      records[#records + 1] = { student = f[1], group = f[2], subject = f[3], grade = grade }
    end
  end
end
file:close()

-- ---------- группировка ----------
local function groupBy(key)
  local map, order = {}, {}
  for _, r in ipairs(records) do
    local k = r[key]
    if not map[k] then map[k] = {}; order[#order + 1] = k end
    table.insert(map[k], r.grade)
  end
  return map, order
end

local byStudent, students = groupBy("student")
local bySubject, subjects = groupBy("subject")
local byGroup, groups     = groupBy("group")
local all = {}
for _, r in ipairs(records) do all[#all + 1] = r.grade end

-- ---------- отчёт ----------
local out = {}
local function say(fmt, ...) out[#out + 1] = fmt:format(...) end

say("Статистика по файлу %s", input)
say("Записей: %d, студентов: %d, предметов: %d, групп: %d",
    #records, #students, #subjects, #groups)
say("Средний балл по всем оценкам: %.2f", avg(all))

say("\nРейтинг студентов:")
table.sort(students, function(a, b) return avg(byStudent[a]) > avg(byStudent[b]) end)
for i, s in ipairs(students) do
  say("  %2d. %s средний %.2f   оценки: %s", i, pad(s, 18), avg(byStudent[s]),
      table.concat(byStudent[s], " "))
end

say("\nПо предметам:")
for _, subj in ipairs(subjects) do
  local g = bySubject[subj]
  say("  %s средний %.2f, мин %d, макс %d", pad(subj, 18), avg(g),
      math.min(table.unpack(g)), math.max(table.unpack(g)))
end

say("\nПо группам:")
for _, grp in ipairs(groups) do
  say("  %s средний %.2f", pad(grp, 18), avg(byGroup[grp]))
end

say("\nРаспределение оценок:")
local dist = { [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
for _, g in ipairs(all) do dist[g] = dist[g] + 1 end
for g = 5, 2, -1 do
  say("  %d: %s %d (%.0f%%)", g, string.rep("#", dist[g]), dist[g], 100 * dist[g] / #all)
end

local excellent, debtors = {}, {}
for _, s in ipairs(students) do
  local min = math.min(table.unpack(byStudent[s]))
  if min == 5 then excellent[#excellent + 1] = s end
  if min == 2 then debtors[#debtors + 1] = s end
end
say("\nОтличники: %s", #excellent > 0 and table.concat(excellent, ", ") or "нет")
say("Есть двойки: %s", #debtors > 0 and table.concat(debtors, ", ") or "нет")

if #errors > 0 then
  say("\nПропущенные строки:")
  for _, e in ipairs(errors) do say("  %s", e) end
end

local text = table.concat(out, "\n") .. "\n"
io.write(text)
local f = assert(io.open(output, "w"))
f:write(text)
f:close()
print("\nОтчёт сохранён в " .. output)
