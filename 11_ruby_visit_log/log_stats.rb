# Анализ журнала посещений сайта из текстового файла.
# Формат строки: ДАТА ВРЕМЯ IP МЕТОД СТРАНИЦА КОД_ОТВЕТА РАЗМЕР_БАЙТ

Visit = Struct.new(:time, :ip, :method, :page, :status, :bytes)

LINE_RE = /\A(\d{4}-\d{2}-\d{2}) (\d{2}):(\d{2}):(\d{2}) (\S+) (GET|POST|PUT|DELETE) (\S+) (\d{3}) (\d+)\z/

def parse(path)
  visits = []
  bad = []
  File.foreach(path, encoding: 'UTF-8').with_index(1) do |line, no|
    line = line.strip
    next if line.empty?
    m = LINE_RE.match(line)
    if m
      date, h, mi, s, ip, meth, page, status, bytes = m.captures
      y, mo, d = date.split('-').map(&:to_i)
      visits << Visit.new(Time.new(y, mo, d, h.to_i, mi.to_i, s.to_i), ip, meth, page,
                          status.to_i, bytes.to_i)
    else
      bad << no
    end
  end
  [visits, bad]
end

def bar(n, max, width = 30)
  '#' * (max.zero? ? 0 : (n * width.to_f / max).round)
end

def human_bytes(b)
  units = %w[Б КБ МБ ГБ]
  i = 0
  v = b.to_f
  while v >= 1024 && i < units.size - 1
    v /= 1024
    i += 1
  end
  format('%.1f %s', v, units[i])
end

def report(visits, bad, top_n)
  out = []
  first, last = visits.minmax_by(&:time)
  out << "Всего запросов: #{visits.size}" + (bad.empty? ? '' : " (нераспознанных строк: #{bad.size}, номера: #{bad.join(', ')})")
  out << "Период: #{first.time.strftime('%d.%m.%Y %H:%M')} — #{last.time.strftime('%d.%m.%Y %H:%M')}"
  out << "Уникальных посетителей (IP): #{visits.map(&:ip).uniq.size}"
  out << "Передано данных: #{human_bytes(visits.sum(&:bytes))}"

  out << "\nПопулярные страницы (топ-#{top_n}):"
  visits.group_by(&:page).transform_values(&:size).sort_by { |p, c| [-c, p] }.first(top_n).each do |page, c|
    out << format('  %-20s %4d', page, c)
  end

  out << "\nАктивные посетители (топ-#{top_n}):"
  visits.group_by(&:ip).sort_by { |ip, vs| [-vs.size, ip] }.first(top_n).each do |ip, vs|
    out << format('  %-15s %4d запросов, %d уникальных страниц', ip, vs.size, vs.map(&:page).uniq.size)
  end

  out << "\nПосещения по дням:"
  visits.group_by { |v| v.time.strftime('%d.%m.%Y') }.sort.each do |day, vs|
    out << format('  %s %4d', day, vs.size)
  end

  out << "\nПосещения по часам суток:"
  per_hour = visits.group_by { |v| v.time.hour }.transform_values(&:size)
  max = per_hour.values.max || 0
  (0..23).each do |h|
    n = per_hour.fetch(h, 0)
    out << format('  %02d:00 %3d %s', h, n, bar(n, max)) if n.positive?
  end
  peak = per_hour.max_by { |_, n| n }
  out << format('  Пиковый час: %02d:00 (%d запросов)', *peak) if peak

  out << "\nКоды ответа:"
  visits.group_by(&:status).sort.each do |status, vs|
    out << format('  %d %4d (%.1f%%)', status, vs.size, 100.0 * vs.size / visits.size)
  end

  errors = visits.select { |v| v.status >= 400 }
  out << "\nОшибочные запросы (#{errors.size}):"
  errors.group_by { |v| [v.status, v.page] }.sort.each do |(status, page), vs|
    out << format('  %d %-20s %3d раз, с IP: %s', status, page, vs.size, vs.map(&:ip).uniq.join(', '))
  end
  out.join("\n")
end

input  = ARGV[0] || 'access.log'
output = ARGV[1] || 'report.txt'
top_n  = (ARGV[2] || 5).to_i

abort "Файл не найден: #{input}" unless File.exist?(input)
visits, bad = parse(input)
abort 'В журнале нет ни одной корректной записи' if visits.empty?

text = report(visits, bad, top_n)
puts text
File.write(output, text + "\n")
puts "\nОтчёт сохранён в #{output}"
