import std.stdio;
import std.conv : to;
import std.parallelism : TaskPool, totalCPUs;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.algorithm : min, joiner;
import std.array : array;
import std.range : iota;

bool isPrime(ulong n)
{
    // Простые числа — целые числа больше 1; 0 и 1 простыми не считаются.
    if (n < 2) return false;
    // После предыдущей проверки здесь остаются 2 и 3 — оба простые.
    if (n < 4) return true;
    // Все простые числа больше 3 имеют вид 6k-1 или 6k+1.
    // Поэтому числа, делящиеся на 2 или 3, сразу составные.
    if (n % 2 == 0 || n % 3 == 0) return false;
    // Проверяем делители 6k-1 и 6k+1 до корня из n.
    // Это только кандидаты на простые делители: составные числа тоже могут иметь такой вид.
    for (ulong i = 5; i * i <= n; i += 6)
        if (n % i == 0 || n % (i + 2) == 0) return false;
    return true;
}

ulong[] primesIn(ulong from, ulong to)
{
    ulong[] res;
    foreach (n; from .. to + 1)
        if (isPrime(n)) res ~= n;
    return res;
}

void main(string[] args)
{
    ulong from    = args.length > 1 ? args[1].to!ulong : 1;
    ulong to      = args.length > 2 ? args[2].to!ulong : 5_000_000;
    uint  threads = args.length > 3 ? args[3].to!uint  : totalCPUs;
    string outFile = args.length > 4 ? args[4] : "";

    if (from > to) { stderr.writeln("Ошибка: начало диапазона больше конца"); return; }
    if (threads < 1) threads = 1;

    writefln("Диапазон: [%s; %s], потоков: %s (ядер в системе: %s)", from, to, threads, totalCPUs);

    // Блоки делаем мельче, чем «по одному на поток»: большие числа проверяются
    // дольше маленьких, и мелкие блоки выравнивают нагрузку между потоками.
    immutable size_t blocks = threads * 16;
    immutable ulong blockLen = (to - from + 1 + blocks - 1) / blocks;
    auto parts = new ulong[][blocks];

    auto sw = StopWatch(AutoStart.yes);
    // TaskPool(n) создаёт n рабочих потоков; вызывающий поток тоже участвует в foreach.
    auto pool = new TaskPool(threads - 1);
    scope (exit) pool.finish(true);
    foreach (b, ref part; pool.parallel(parts, 1))
    {
        ulong lo = from + b * blockLen;
        if (lo > to) continue;
        ulong hi = min(to, lo + blockLen - 1);
        part = primesIn(lo, hi);
    }
    ulong[] primes = parts.joiner.array;
    double parallelMs = sw.peek.total!"usecs" / 1000.0;

    sw.reset();
    auto check = primesIn(from, to);
    double sequentialMs = sw.peek.total!"usecs" / 1000.0;

    writefln("Найдено простых: %s", primes.length);
    if (primes.length > 0)
    {
        writefln("Первые: %s", primes[0 .. min(10, $)]);
        writefln("Последние: %s", primes[$ - min(10, $) .. $]);
    }
    writefln("Параллельно: %.1f мс, последовательно: %.1f мс, ускорение: %.2f",
             parallelMs, sequentialMs, sequentialMs / (parallelMs > 0 ? parallelMs : 1e-3));
    writefln("Результаты совпадают: %s", primes == check);

    if (outFile.length)
    {
        auto f = File(outFile, "w");
        foreach (p; primes) f.writeln(p);
        writefln("Список записан в %s", outFile);
    }
}
