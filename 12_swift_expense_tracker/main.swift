// Трекер расходов: добавление, просмотр, удаление и статистика расходов.
// Данные хранятся в CSV-файле expenses.csv (id;дата;сумма;категория;описание).
// Работает как разовая команда из аргументов или в интерактивном режиме.

import Foundation

struct Expense {
    let id: Int
    let date: String      // ГГГГ-ММ-ДД
    let amount: Double
    let category: String
    let note: String
    var month: String { String(date.prefix(7)) }
}

let fileName = ProcessInfo.processInfo.environment["EXPENSES_FILE"] ?? "expenses.csv"

let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - файл

func load() -> [Expense] {
    guard let text = try? String(contentsOfFile: fileName, encoding: .utf8) else { return [] }
    var result: [Expense] = []
    for line in text.split(separator: "\n") {
        let p = line.split(separator: ";", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        // строка заголовка и повреждённые строки пропускаются
        guard p.count == 5, let id = Int(p[0]), let amount = Double(p[2]) else { continue }
        result.append(Expense(id: id, date: p[1], amount: amount, category: p[3], note: p[4]))
    }
    return result
}

func save(_ items: [Expense]) {
    var text = "id;date;amount;category;note\n"
    for e in items {
        text += "\(e.id);\(e.date);\(String(format: "%.2f", e.amount));\(e.category);\(e.note)\n"
    }
    do {
        try text.write(toFile: fileName, atomically: true, encoding: .utf8)
    } catch {
        print("Ошибка записи файла: \(error)")
    }
}

// MARK: - форматирование

// String.count считает символы, а не байты, поэтому кириллица выравнивается верно.
func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

func padLeft(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
}

func money(_ x: Double) -> String { String(format: "%.2f", x) }

/// Достаёт из списка аргументов пару «--имя значение» и удаляет её.
func takeOption(_ name: String, from args: inout [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

func printTable(_ items: [Expense]) {
    print(pad("#", 5) + pad("Дата", 12) + padLeft("Сумма", 11) + "  " + pad("Категория", 14) + "Описание")
    for e in items {
        print(pad(String(e.id), 5) + pad(e.date, 12) + padLeft(money(e.amount), 11) + "  "
              + pad(e.category, 14) + e.note)
    }
    let total = items.reduce(0.0) { $0 + $1.amount }
    print("Итого: \(money(total)) (\(items.count) записей)")
}

// MARK: - команды

func add(_ args: [String]) {
    var args = args
    let date = takeOption("--date", from: &args) ?? dateFormatter.string(from: Date())
    guard dateFormatter.date(from: date) != nil else {
        print("Неверная дата \(date), нужен формат ГГГГ-ММ-ДД"); return
    }
    guard args.count >= 2,
          let amount = Double(args[0].replacingOccurrences(of: ",", with: ".")), amount > 0 else {
        print("Использование: add <сумма> <категория> [описание] [--date ГГГГ-ММ-ДД]"); return
    }
    var items = load()
    let id = (items.map { $0.id }.max() ?? 0) + 1
    // «;» — разделитель полей в файле, внутри текста заменяем его на запятую
    let category = args[1].replacingOccurrences(of: ";", with: ",")
    let note = args.dropFirst(2).joined(separator: " ").replacingOccurrences(of: ";", with: ",")
    items.append(Expense(id: id, date: date, amount: amount, category: category, note: note))
    save(items)
    print("Добавлен расход #\(id): \(money(amount)) — \(category) (\(date))")
}

func list(_ args: [String]) {
    var args = args
    let category = takeOption("--category", from: &args)
    let month = takeOption("--month", from: &args)
    let items = load()
        .filter { category == nil || $0.category.lowercased() == category!.lowercased() }
        .filter { month == nil || $0.month == month! }
        .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    if items.isEmpty { print("Расходов не найдено"); return }
    printTable(items)
}

func delete(_ args: [String]) {
    guard let s = args.first, let id = Int(s) else { print("Использование: delete <номер>"); return }
    var items = load()
    guard let index = items.firstIndex(where: { $0.id == id }) else { print("Нет расхода #\(id)"); return }
    let removed = items.remove(at: index)
    save(items)
    print("Удалён расход #\(id): \(money(removed.amount)) — \(removed.category)")
}

func stats(_ args: [String]) {
    var args = args
    let month = takeOption("--month", from: &args)
    let items = load().filter { month == nil || $0.month == month! }
    if items.isEmpty { print("Нет данных для статистики"); return }

    let total = items.reduce(0.0) { $0 + $1.amount }
    let days = Set(items.map { $0.date }).count
    let biggest = items.max { $0.amount < $1.amount }!
    print("Статистика" + (month.map { " за \($0)" } ?? " за всё время"))
    print("  Всего потрачено: \(money(total)) в \(items.count) записях")
    print("  В среднем за день с расходами: \(money(total / Double(days)))")
    print("  Самая крупная трата: \(money(biggest.amount)) — \(biggest.category), \(biggest.note) (\(biggest.date))")

    print("\nПо категориям:")
    let byCategory = Dictionary(grouping: items, by: { $0.category })
        .mapValues { $0.reduce(0.0) { $0 + $1.amount } }
        .sorted { $0.value > $1.value }
    for (category, sum) in byCategory {
        let share = sum / total * 100
        let bar = String(repeating: "#", count: Int((share / 4).rounded()))
        print("  " + pad(category, 14) + padLeft(money(sum), 11) + padLeft(String(format: "%.1f%%", share), 8) + "  " + bar)
    }

    if month == nil {
        print("\nПо месяцам:")
        let byMonth = Dictionary(grouping: items, by: { $0.month })
            .mapValues { $0.reduce(0.0) { $0 + $1.amount } }
            .sorted { $0.key < $1.key }
        for (m, sum) in byMonth {
            print("  " + pad(m, 10) + padLeft(money(sum), 11))
        }
    }
}

func help() {
    print("""
    Команды:
      add <сумма> <категория> [описание] [--date ГГГГ-ММ-ДД]   добавить расход
      list [--category К] [--month ГГГГ-ММ]                    список расходов
      stats [--month ГГГГ-ММ]                                  статистика
      delete <номер>                                           удалить расход
      help                                                     справка
      exit                                                     выход (в интерактивном режиме)
    """)
}

/// Выполняет одну команду; возвращает false, если нужно завершить работу.
func run(_ words: [String]) -> Bool {
    guard let command = words.first else { return true }
    let args = Array(words.dropFirst())
    switch command {
    case "add": add(args)
    case "list": list(args)
    case "stats": stats(args)
    case "delete": delete(args)
    case "help": help()
    case "exit", "quit": return false
    default: print("Неизвестная команда \(command), введите help")
    }
    return true
}

// MARK: - запуск

let cliArgs = Array(CommandLine.arguments.dropFirst())
if !cliArgs.isEmpty {
    _ = run(cliArgs)
} else {
    print("Трекер расходов. Файл: \(fileName). Введите help для справки.")
    while true {
        print("> ", terminator: "")
        guard let line = readLine() else { break }
        let words = line.split(separator: " ").map(String.init)
        if !run(words) { break }
    }
}
