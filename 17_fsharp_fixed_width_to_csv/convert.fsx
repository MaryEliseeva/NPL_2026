// Конвертация таблицы фиксированной ширины в CSV.
// Границы столбцов определяются одним из трёх способов (по приоритету):
//   1) явно: --widths 6,14,6 (ширины столбцов в символах, кроме последнего — он до конца строки);
//   2) по строке-разделителю из дефисов под заголовком: "---- -------- ------";
//   3) автоматически: столбец символов, где во ВСЕХ строках пробел, считается границей.

open System
open System.IO

type Options =
    { Input: string
      Output: string option
      Widths: int list option
      Delimiter: char }

let usage () =
    eprintfn "Использование: dotnet fsi convert.fsx <вход.txt> [выход.csv] [--widths 6,14,6] [--delimiter ;]"
    exit 1

let parseArgs (argv: string list) =
    let rec loop args opts =
        match args with
        | "--widths" :: w :: rest ->
            let widths = w.Split(',') |> Array.map int |> List.ofArray
            loop rest { opts with Widths = Some widths }
        | "--delimiter" :: d :: rest -> loop rest { opts with Delimiter = (if d = "tab" then '\t' else d.[0]) }
        | file :: rest when opts.Input = "" -> loop rest { opts with Input = file }
        | file :: rest when opts.Output.IsNone -> loop rest { opts with Output = Some file }
        | [] -> opts
        | _ -> usage ()
    let opts = loop argv { Input = ""; Output = None; Widths = None; Delimiter = ',' }
    if opts.Input = "" then usage () else opts

/// Столбец описывается парой (начало, длина); длина -1 — до конца строки.
type Column = int * int

/// Ширины всех столбцов, кроме последнего: последний занимает остаток строки.
let fromWidths (widths: int list) : Column list =
    let starts = widths |> List.scan (+) 0
    List.zip (List.take widths.Length starts) widths @ [ (List.last starts, -1) ]

let isRuler (line: string) =
    line.Trim().Length > 0 && line |> Seq.forall (fun c -> c = '-' || c = ' ')

/// Границы по набору «занятых» позиций: непрерывные участки занятых позиций — столбцы.
let fromOccupied (occupied: bool[]) : Column list =
    let cols = ResizeArray<Column>()
    let mutable start = -1
    for i in 0 .. occupied.Length do
        let busy = i < occupied.Length && occupied.[i]
        if busy && start < 0 then start <- i
        elif not busy && start >= 0 then
            cols.Add((start, i - start))
            start <- -1
    // Последний столбец читаем до конца строки, а каждый столбец расширяем до начала
    // следующего — так значение, не попавшее ровно в колонку, не потеряется.
    let n = cols.Count
    [ for k in 0 .. n - 1 ->
        let (s, _) = cols.[k]
        if k = n - 1 then (s, -1) else (s, fst cols.[k + 1] - s) ]

let fromRuler (ruler: string) = ruler |> Seq.map (fun c -> c = '-') |> Array.ofSeq |> fromOccupied

let autoDetect (lines: string list) =
    let width = lines |> List.map (fun l -> l.Length) |> List.max
    let occupied =
        Array.init width (fun i -> lines |> List.exists (fun l -> i < l.Length && l.[i] <> ' '))
    fromOccupied occupied

let cut (line: string) ((start, len): Column) =
    if start >= line.Length then ""
    elif len < 0 || start + len > line.Length then line.Substring(start).Trim()
    else line.Substring(start, len).Trim()

/// Экранирование по правилам CSV (RFC 4180): поле с разделителем, кавычкой или переводом
/// строки заключается в кавычки, а кавычки внутри удваиваются.
let csvField (delim: char) (s: string) =
    if s.IndexOfAny([| delim; '"'; '\n'; '\r' |]) >= 0 then "\"" + s.Replace("\"", "\"\"") + "\""
    else s

let run (opts: Options) =
    let lines =
        File.ReadAllLines(opts.Input)
        |> Array.map (fun l -> l.Replace("\t", "    ").TrimEnd())
        |> Array.filter (fun l -> l <> "")
        |> List.ofArray
    if lines.IsEmpty then failwith "входной файл пуст"

    let columns, dataLines, method =
        match opts.Widths, lines with
        | Some w, _ -> fromWidths w, lines, sprintf "по заданным ширинам %A" w
        | None, header :: ruler :: rest when isRuler ruler ->
            fromRuler ruler, header :: rest, "по строке-разделителю из дефисов"
        | None, _ -> autoDetect lines, lines, "автоматически по пустым столбцам"

    let rows = dataLines |> List.map (fun l -> columns |> List.map (cut l))
    let csv =
        rows
        |> List.map (fun r -> r |> List.map (csvField opts.Delimiter) |> String.concat (string opts.Delimiter))
        |> String.concat Environment.NewLine

    eprintfn "Столбцы определены %s: %d шт." method columns.Length
    columns |> List.iteri (fun i (s, l) ->
        eprintfn "  %d. позиции %d..%s  «%s»" (i + 1) s (if l < 0 then "конец" else string (s + l - 1)) (List.head rows).[i])
    eprintfn "Строк данных: %d" (rows.Length - 1)

    match opts.Output with
    | Some path ->
        File.WriteAllText(path, csv + Environment.NewLine)
        eprintfn "CSV записан в %s" path
    | None -> printfn "%s" csv

let argv = fsi.CommandLineArgs |> Array.skip 1 |> List.ofArray
try
    run (parseArgs argv)
with ex ->
    eprintfn "Ошибка: %s" ex.Message
    exit 2
