//! Сервер статистических запросов.
//! Каждое подключение обслуживается в своём потоке. У каждого клиента свой
//! набор данных (LOAD/ADD), запросы считаются по нему или по числам из самого запроса.

use stats_client_server as st;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;

const HELP: &str = "OK команды:\n\
  LOAD <числа>        — задать набор данных\n\
  ADD <числа>         — добавить числа к набору\n\
  SHOW / CLEAR        — показать / очистить набор\n\
  COUNT SUM MEAN MEDIAN MODE MIN MAX RANGE VAR STD OUTLIERS [числа]\n\
  PERCENTILE <p> [числа]\n\
  SUMMARY [числа]     — всё сразу\n\
  QUIT\n\
END";

fn parse_numbers(parts: &[&str]) -> Result<Vec<f64>, String> {
    parts
        .iter()
        .map(|s| {
            s.replace(',', ".")
                .parse::<f64>()
                .map_err(|_| format!("«{}» — не число", s))
        })
        .collect()
}

fn fmt(x: f64) -> String {
    if x.fract() == 0.0 && x.abs() < 1e15 {
        format!("{}", x as i64)
    } else {
        format!("{:.4}", x)
    }
}

fn fmt_list(xs: &[f64]) -> String {
    xs.iter().map(|&x| fmt(x)).collect::<Vec<_>>().join(" ")
}

fn mode_text(xs: &[f64]) -> String {
    let (m, c) = st::mode(xs);
    if c == 1 {
        "нет (все значения различны)".to_string()
    } else {
        format!("{} (встречается {} раз)", fmt_list(&m), c)
    }
}

fn summary(xs: &[f64]) -> String {
    format!(
        "OK сводка по {} значениям:\n  сумма     {}\n  среднее   {}\n  медиана   {}\n  мода      {}\n  минимум   {}\n  максимум  {}\n  размах    {}\n  дисперсия {}\n  ст.откл.  {}\n  Q1 / Q3   {} / {}\n  выбросы   {}\nEND",
        xs.len(),
        fmt(st::sum(xs)),
        fmt(st::mean(xs)),
        fmt(st::median(xs)),
        mode_text(xs),
        fmt(st::min(xs)),
        fmt(st::max(xs)),
        fmt(st::max(xs) - st::min(xs)),
        fmt(st::variance(xs)),
        fmt(st::std_dev(xs)),
        fmt(st::percentile(xs, 25.0)),
        fmt(st::percentile(xs, 75.0)),
        {
            let o = st::outliers(xs);
            if o.is_empty() { "нет".to_string() } else { fmt_list(&o) }
        }
    )
}

/// Обрабатывает одну строку запроса. None — клиент попросил отключиться.
fn handle(line: &str, data: &mut Vec<f64>) -> Option<String> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    let cmd = parts.first()?.to_uppercase();
    let args = &parts[1..];

    let reply = match cmd.as_str() {
        "QUIT" => return None,
        "HELP" => HELP.to_string(),
        "LOAD" | "ADD" => match parse_numbers(args) {
            Ok(nums) if !nums.is_empty() => {
                if cmd == "LOAD" {
                    data.clear();
                }
                data.extend(nums);
                format!("OK в наборе {} значений", data.len())
            }
            Ok(_) => "ERR не переданы числа".into(),
            Err(e) => format!("ERR {}", e),
        },
        "CLEAR" => {
            data.clear();
            "OK набор очищен".into()
        }
        "SHOW" if data.is_empty() => "OK набор пуст".into(),
        "SHOW" => format!("OK [{}] {}", data.len(), fmt_list(data)),
        _ => {
            // Для PERCENTILE первый аргумент — p, дальше — необязательные числа.
            let (p, rest) = if cmd == "PERCENTILE" {
                match args.first().and_then(|s| s.parse::<f64>().ok()) {
                    Some(p) if (0.0..=100.0).contains(&p) => (p, &args[1..]),
                    _ => return Some("ERR формат: PERCENTILE <0..100> [числа]".into()),
                }
            } else {
                (0.0, args)
            };
            let xs = match parse_numbers(rest) {
                Ok(v) if !v.is_empty() => v,
                Ok(_) => data.clone(),
                Err(e) => return Some(format!("ERR {}", e)),
            };
            if xs.is_empty() {
                return Some("ERR набор пуст: передайте числа или выполните LOAD".into());
            }
            match cmd.as_str() {
                "COUNT" => format!("OK {}", xs.len()),
                "SUM" => format!("OK {}", fmt(st::sum(&xs))),
                "MEAN" => format!("OK {}", fmt(st::mean(&xs))),
                "MEDIAN" => format!("OK {}", fmt(st::median(&xs))),
                "MODE" => format!("OK {}", mode_text(&xs)),
                "MIN" => format!("OK {}", fmt(st::min(&xs))),
                "MAX" => format!("OK {}", fmt(st::max(&xs))),
                "RANGE" => format!("OK {}", fmt(st::max(&xs) - st::min(&xs))),
                "VAR" => format!("OK {}", fmt(st::variance(&xs))),
                "STD" => format!("OK {}", fmt(st::std_dev(&xs))),
                "PERCENTILE" => format!("OK {}", fmt(st::percentile(&xs, p))),
                "OUTLIERS" => {
                    let o = st::outliers(&xs);
                    format!("OK {}", if o.is_empty() { "выбросов нет".into() } else { fmt_list(&o) })
                }
                "SUMMARY" => summary(&xs),
                _ => "ERR неизвестная команда, HELP — список команд".into(),
            }
        }
    };
    Some(reply)
}

fn serve(stream: TcpStream, total: Arc<AtomicUsize>) -> std::io::Result<()> {
    let peer = stream.peer_addr()?;
    println!("[+] {} подключился", peer);
    let mut writer = stream.try_clone()?;
    let reader = BufReader::new(stream);
    let mut data: Vec<f64> = Vec::new();
    writeln!(writer, "OK сервер статистики, HELP — список команд")?;

    for line in reader.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let n = total.fetch_add(1, Ordering::SeqCst) + 1;
        println!("    #{} {}: {}", n, peer, line.trim());
        match handle(&line, &mut data) {
            Some(reply) => writeln!(writer, "{}", reply)?,
            None => {
                writeln!(writer, "BYE")?;
                break;
            }
        }
    }
    println!("[-] {} отключился", peer);
    Ok(())
}

fn main() -> std::io::Result<()> {
    let addr = std::env::args().nth(1).unwrap_or_else(|| "127.0.0.1:7878".into());
    let listener = TcpListener::bind(&addr)?;
    println!("Сервер статистики слушает {}", addr);
    let total = Arc::new(AtomicUsize::new(0)); // общий счётчик запросов всех клиентов

    for stream in listener.incoming() {
        match stream {
            Ok(s) => {
                let total = Arc::clone(&total);
                thread::spawn(move || {
                    if let Err(e) = serve(s, total) {
                        eprintln!("ошибка соединения: {}", e);
                    }
                });
            }
            Err(e) => eprintln!("ошибка подключения: {}", e),
        }
    }
    Ok(())
}
