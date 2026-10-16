//! Клиент сервера статистики.
//!   client [адрес] [--file данные.txt] [КОМАНДА ...]
//! --file  — прочитать числа из файла и отправить их серверу командой LOAD;
//! КОМАНДА — выполнить одну команду и выйти; без неё — интерактивный режим.

use std::io::{self, BufRead, BufReader, Write};
use std::net::TcpStream;

/// Читает ответ сервера: одну строку, а если ответ многострочный — до строки END.
fn read_reply(reader: &mut impl BufRead) -> io::Result<String> {
    let mut first = String::new();
    reader.read_line(&mut first)?;
    let mut reply = first.trim_end().to_string();
    if reply.ends_with(':') {
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line)? == 0 {
                break;
            }
            let line = line.trim_end();
            if line == "END" {
                break;
            }
            reply.push('\n');
            reply.push_str(line);
        }
    }
    Ok(reply)
}

fn read_numbers_file(path: &str) -> io::Result<String> {
    let text = std::fs::read_to_string(path)?;
    Ok(text
        .lines()
        .filter(|l| !l.trim_start().starts_with('#'))
        .flat_map(|l| l.split_whitespace())
        .collect::<Vec<_>>()
        .join(" "))
}

fn main() -> io::Result<()> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let addr = if args.first().map_or(false, |a| a.contains(':')) {
        args.remove(0)
    } else {
        "127.0.0.1:7878".to_string()
    };
    let file = match args.iter().position(|a| a == "--file") {
        Some(i) if i + 1 < args.len() => {
            let f = args.remove(i + 1);
            args.remove(i);
            Some(f)
        }
        _ => None,
    };

    let stream = TcpStream::connect(&addr)?;
    let mut writer = stream.try_clone()?;
    let mut reader = BufReader::new(stream);
    println!("{}", read_reply(&mut reader)?);

    let mut send = |cmd: &str, reader: &mut BufReader<TcpStream>| -> io::Result<String> {
        writeln!(writer, "{}", cmd)?;
        read_reply(reader)
    };

    if let Some(path) = file {
        let nums = read_numbers_file(&path)?;
        println!("LOAD из {} -> {}", path, send(&format!("LOAD {}", nums), &mut reader)?);
    }

    if !args.is_empty() {
        println!("{}", send(&args.join(" "), &mut reader)?);
        send("QUIT", &mut reader)?;
        return Ok(());
    }

    let stdin = io::stdin();
    loop {
        print!("> ");
        io::stdout().flush()?;
        let mut line = String::new();
        if stdin.lock().read_line(&mut line)? == 0 {
            break;
        }
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let reply = send(line, &mut reader)?;
        println!("{}", reply);
        if reply == "BYE" || reply.is_empty() {
            break;
        }
    }
    Ok(())
}
