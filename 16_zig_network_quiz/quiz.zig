//! Сетевая викторина: TCP-сервер задаёт подключившимся игрокам вопросы
//! с вариантами ответа, проверяет ответы и ведёт общую таблицу рекордов.
//! Каждый игрок обслуживается в отдельной параллельной задаче (Io.Group.concurrent),
//! общая таблица рекордов защищена мьютексом.

const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Question = struct {
    text: []const u8,
    options: []const []const u8,
    correct: usize, // индекс правильного варианта (с нуля)
};

const Result = struct {
    name: []const u8,
    score: usize,
    total: usize,
};

const Shared = struct {
    questions: []const Question,
    gpa: std.mem.Allocator,
    mutex: Io.Mutex = .init,
    results: std.ArrayList(Result) = .empty,
};

/// Формат строки файла: Вопрос|Вариант 1|Вариант 2|...|номер правильного варианта
fn loadQuestions(io: Io, arena: std.mem.Allocator, path: []const u8) ![]Question {
    const data = try Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
    var list: std.ArrayList(Question) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \r\t");
        if (line.len == 0 or line[0] == '#') continue;

        var parts: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, '|');
        while (it.next()) |p| try parts.append(arena, std.mem.trim(u8, p, " "));

        const n = parts.items.len;
        const correct = std.fmt.parseInt(usize, parts.items[n - 1], 10) catch 0;
        if (n < 4 or correct < 1 or correct > n - 2) {
            std.debug.print("questions: строка {d} пропущена — неверный формат\n", .{line_no});
            continue;
        }
        try list.append(arena, .{
            .text = parts.items[0],
            .options = parts.items[1 .. n - 1],
            .correct = correct - 1,
        });
    }
    return list.items;
}

fn handleClient(io: Io, stream: net.Stream, shared: *Shared, seed: u64, id: u64) Io.Cancelable!void {
    defer stream.close(io);
    std.debug.print("[+] игрок #{d} подключился\n", .{id});
    play(io, stream, shared, seed, id) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => std.debug.print("    игрок #{d}: соединение прервано ({s})\n", .{ id, @errorName(err) }),
    };
    std.debug.print("[-] игрок #{d} отключился\n", .{id});
}

/// Читает строку от клиента; null — клиент отключился.
fn readLine(r: *Io.Reader) !?[]const u8 {
    const raw = (try r.takeDelimiter('\n')) orelse return null;
    return std.mem.trim(u8, raw, " \r\t");
}

fn play(io: Io, stream: net.Stream, shared: *Shared, seed: u64, id: u64) !void {
    var read_buf: [1024]u8 = undefined;
    var write_buf: [1024]u8 = undefined;
    var sr = stream.reader(io, &read_buf);
    var sw = stream.writer(io, &write_buf);
    const r = &sr.interface;
    const w = &sw.interface;

    try w.print("Добро пожаловать в сетевую викторину! Вопросов: {d}.\nКак вас зовут?\n> ", .{shared.questions.len});
    try w.flush();

    // Имя копируется в свой буфер: срез из reader станет недействительным после следующего чтения.
    var name_buf: [64]u8 = undefined;
    const typed = (try readLine(r)) orelse return;
    const src = if (typed.len == 0) "Игрок" else typed;
    const name_len = @min(src.len, name_buf.len);
    @memcpy(name_buf[0..name_len], src[0..name_len]);
    const name = name_buf[0..name_len];
    std.debug.print("    игрок #{d} назвался «{s}»\n", .{ id, name });

    // Свой случайный порядок вопросов для каждого игрока.
    const order = try shared.gpa.alloc(usize, shared.questions.len);
    defer shared.gpa.free(order);
    for (order, 0..) |*o, i| o.* = i;
    var prng = std.Random.DefaultPrng.init(seed);
    prng.random().shuffle(usize, order);

    var score: usize = 0;
    for (order, 1..) |qi, num| {
        const q = shared.questions[qi];
        try w.print("\nВопрос {d}/{d}: {s}\n", .{ num, order.len, q.text });
        for (q.options, 1..) |opt, i| try w.print("  {d}) {s}\n", .{ i, opt });

        while (true) {
            try w.writeAll("Ваш ответ (номер): ");
            try w.flush();
            const answer = (try readLine(r)) orelse return;
            const n = std.fmt.parseInt(usize, answer, 10) catch {
                try w.writeAll("Введите номер варианта цифрой.\n");
                continue;
            };
            if (n < 1 or n > q.options.len) {
                try w.print("Номер должен быть от 1 до {d}.\n", .{q.options.len});
                continue;
            }
            if (n - 1 == q.correct) {
                score += 1;
                try w.writeAll("Верно!\n");
            } else {
                try w.print("Неверно. Правильный ответ: {d}) {s}\n", .{ q.correct + 1, q.options[q.correct] });
            }
            break;
        }
    }

    try w.print("\n{s}, ваш результат: {d} из {d}\n", .{ name, score, order.len });
    std.debug.print("    игрок #{d} «{s}»: {d}/{d}\n", .{ id, name, score, order.len });

    // Общая таблица рекордов — изменяется под мьютексом.
    try shared.mutex.lock(io);
    defer shared.mutex.unlock(io);
    try shared.results.append(shared.gpa, .{
        .name = try shared.gpa.dupe(u8, name),
        .score = score,
        .total = order.len,
    });
    std.mem.sort(Result, shared.results.items, {}, struct {
        fn better(_: void, a: Result, b: Result) bool {
            return a.score > b.score;
        }
    }.better);

    try w.writeAll("\nТаблица рекордов:\n");
    for (shared.results.items, 1..) |res, place| {
        if (place > 10) break;
        try w.print("  {d:>2}. {s} — {d}/{d}\n", .{ place, res.name, res.score, res.total });
    }
    try w.writeAll("Спасибо за игру!\n");
    try w.flush();
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const port: u16 = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 9000;
    const path: []const u8 = if (args.len > 2) args[2] else "questions.txt";

    const questions = try loadQuestions(io, arena, path);
    if (questions.len == 0) {
        std.debug.print("В файле {s} нет ни одного вопроса\n", .{path});
        return;
    }

    var shared: Shared = .{ .questions = questions, .gpa = init.gpa };

    const address = try net.IpAddress.parse("0.0.0.0", port);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.debug.print("Викторина: загружено {d} вопросов, сервер слушает порт {d}\n", .{ questions.len, port });

    var group: Io.Group = .init;
    defer group.cancel(io);

    var next_id: u64 = 1;
    while (true) {
        const stream = try server.accept(io);
        var seed_bytes: [8]u8 = undefined;
        io.random(&seed_bytes);
        const seed = std.mem.readInt(u64, &seed_bytes, .little);
        try group.concurrent(io, handleClient, .{ io, stream, &shared, seed, next_id });
        next_id += 1;
    }
}
