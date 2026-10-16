(* Конвертация JSON в YAML.
   1) Собственный парсер JSON (рекурсивный спуск) строит дерево типа json.
   2) Генератор YAML обходит дерево и выводит блочный YAML с отступами,
      решая для каждой строки, можно ли писать её без кавычек. *)

type json =
  | Null
  | Bool of bool
  | Num of string                    (* число храним как было записано *)
  | Str of string
  | Arr of json list
  | Obj of (string * json) list      (* список, а не таблица — сохраняем порядок ключей *)

exception Parse_error of string

(* ---------- парсер JSON ---------- *)

let parse (s : string) : json =
  let pos = ref 0 in
  let len = String.length s in
  let fail msg =
    (* вычисляем номер строки и позицию для сообщения об ошибке *)
    let line = ref 1 and col = ref 1 in
    for i = 0 to min !pos len - 1 do
      if s.[i] = '\n' then (incr line; col := 1) else incr col
    done;
    raise (Parse_error (Printf.sprintf "строка %d, позиция %d: %s" !line !col msg))
  in
  let peek () = if !pos < len then s.[!pos] else '\000' in
  let rec skip_ws () =
    match peek () with
    | ' ' | '\t' | '\n' | '\r' -> incr pos; skip_ws ()
    | _ -> ()
  in
  let expect c =
    if peek () = c then incr pos else fail (Printf.sprintf "ожидался символ '%c'" c)
  in
  let literal word value =
    let n = String.length word in
    if !pos + n <= len && String.sub s !pos n = word then (pos := !pos + n; value)
    else fail "неизвестное значение"
  in
  (* кодирование символа Unicode (code point) в байты UTF-8 *)
  let add_utf8 buf cp =
    let add i = Buffer.add_char buf (Char.chr i) in
    if cp < 0x80 then add cp
    else if cp < 0x800 then (add (0xC0 lor (cp lsr 6)); add (0x80 lor (cp land 0x3F)))
    else if cp < 0x10000 then (
      add (0xE0 lor (cp lsr 12));
      add (0x80 lor ((cp lsr 6) land 0x3F));
      add (0x80 lor (cp land 0x3F)))
    else (
      add (0xF0 lor (cp lsr 18));
      add (0x80 lor ((cp lsr 12) land 0x3F));
      add (0x80 lor ((cp lsr 6) land 0x3F));
      add (0x80 lor (cp land 0x3F)))
  in
  let hex4 () =
    if !pos + 4 > len then fail "обрезанная последовательность \\u";
    let v =
      try int_of_string ("0x" ^ String.sub s !pos 4)
      with Failure _ -> fail "неверная последовательность \\u"
    in
    pos := !pos + 4;
    v
  in
  let parse_string () =
    expect '"';
    let buf = Buffer.create 16 in
    let rec loop () =
      if !pos >= len then fail "незакрытая строка";
      let c = s.[!pos] in
      incr pos;
      match c with
      | '"' -> ()
      | '\\' ->
        let e = peek () in
        incr pos;
        (match e with
         | '"' -> Buffer.add_char buf '"'
         | '\\' -> Buffer.add_char buf '\\'
         | '/' -> Buffer.add_char buf '/'
         | 'b' -> Buffer.add_char buf '\b'
         | 'f' -> Buffer.add_char buf '\012'
         | 'n' -> Buffer.add_char buf '\n'
         | 'r' -> Buffer.add_char buf '\r'
         | 't' -> Buffer.add_char buf '\t'
         | 'u' ->
           let hi = hex4 () in
           (* символы вне BMP (например, эмодзи) записываются суррогатной парой *)
           if hi >= 0xD800 && hi <= 0xDBFF && peek () = '\\' then begin
             pos := !pos + 2;
             let lo = hex4 () in
             add_utf8 buf (0x10000 + ((hi - 0xD800) lsl 10) + (lo - 0xDC00))
           end else add_utf8 buf hi
         | _ -> fail "неверная escape-последовательность");
        loop ()
      | c when Char.code c < 0x20 -> fail "управляющий символ внутри строки"
      | c -> Buffer.add_char buf c; loop ()
    in
    loop ();
    Buffer.contents buf
  in
  let parse_number () =
    let start = !pos in
    let digits () = while (match peek () with '0' .. '9' -> true | _ -> false) do incr pos done in
    if peek () = '-' then incr pos;
    if not (match peek () with '0' .. '9' -> true | _ -> false) then fail "неверное число";
    digits ();
    if peek () = '.' then (incr pos; digits ());
    if peek () = 'e' || peek () = 'E' then begin
      incr pos;
      if peek () = '+' || peek () = '-' then incr pos;
      digits ()
    end;
    Num (String.sub s start (!pos - start))
  in
  let rec parse_value () =
    skip_ws ();
    match peek () with
    | '{' ->
      incr pos; skip_ws ();
      if peek () = '}' then (incr pos; Obj [])
      else
        let rec members acc =
          skip_ws ();
          let k = parse_string () in
          skip_ws (); expect ':';
          let v = parse_value () in
          skip_ws ();
          match peek () with
          | ',' -> incr pos; members ((k, v) :: acc)
          | '}' -> incr pos; Obj (List.rev ((k, v) :: acc))
          | _ -> fail "в объекте ожидалась ',' или '}'"
        in
        members []
    | '[' ->
      incr pos; skip_ws ();
      if peek () = ']' then (incr pos; Arr [])
      else
        let rec items acc =
          let v = parse_value () in
          skip_ws ();
          match peek () with
          | ',' -> incr pos; items (v :: acc)
          | ']' -> incr pos; Arr (List.rev (v :: acc))
          | _ -> fail "в массиве ожидалась ',' или ']'"
        in
        items []
    | '"' -> Str (parse_string ())
    | 't' -> literal "true" (Bool true)
    | 'f' -> literal "false" (Bool false)
    | 'n' -> literal "null" Null
    | '-' | '0' .. '9' -> parse_number ()
    | '\000' -> fail "неожиданный конец файла"
    | c -> fail (Printf.sprintf "неожиданный символ '%c'" c)
  in
  let v = parse_value () in
  skip_ws ();
  if !pos < len then fail "лишние символы после JSON";
  v

(* ---------- генератор YAML ---------- *)

(* Слова, которые YAML прочитает не как строку (логические значения, null). *)
let reserved =
  [ "true"; "false"; "yes"; "no"; "on"; "off"; "y"; "n"; "null"; "~"; "" ]

let looks_like_number s =
  let s' = String.lowercase_ascii s in
  List.mem s' [ ".inf"; "-.inf"; "+.inf"; ".nan" ]
  || (try ignore (float_of_string s); true with Failure _ -> false)

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

(* Можно ли записать строку без кавычек, чтобы YAML прочитал её обратно как ту же строку. *)
let is_plain s =
  let n = String.length s in
  n > 0
  && (not (List.mem (String.lowercase_ascii s) reserved))
  && (not (looks_like_number s))
  && s.[0] <> ' ' && s.[n - 1] <> ' '
  && (not (String.contains "-?:,[]{}#&*!|>'\"%@`" s.[0]))
  && (not (contains s ": ")) && (not (contains s " #"))
  && s.[n - 1] <> ':'
  && not (String.exists (fun c -> Char.code c < 0x20) s)

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | '\r' -> Buffer.add_string b "\\r"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\x%02x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

(* Многострочная строка удобнее читается как блок «|»: текст как есть, с отступом. *)
let is_block_string s =
  String.contains s '\n'
  && (not (String.exists (fun c -> Char.code c < 0x20 && c <> '\n') s))
  && s.[0] <> ' ' && s.[0] <> '\n'

let block_string s =
  let n = String.length s in
  let trailing = ref 0 in
  while !trailing < n && s.[n - 1 - !trailing] = '\n' do incr trailing done;
  (* индикатор «chomping»: |- без завершающего перевода строки, | — один, |+ — несколько *)
  let header = match !trailing with 0 -> "|-" | 1 -> "|" | _ -> "|+" in
  let body = String.sub s 0 (n - !trailing) in
  let lines = String.split_on_char '\n' body @ List.init (max 0 (!trailing - 1)) (fun _ -> "") in
  (header, lines)

(* Числа с экспонентой пишем в виде 1.5e+10: так их поймут и парсеры YAML 1.1,
   которым нужна точка в мантиссе и знак у порядка. *)
let normalize_number n =
  match String.index_opt (String.lowercase_ascii n) 'e' with
  | None -> n
  | Some i ->
    let mant = String.sub n 0 i and exp = String.sub n (i + 1) (String.length n - i - 1) in
    let mant = if String.contains mant '.' then mant else mant ^ ".0" in
    let exp = if exp <> "" && (exp.[0] = '+' || exp.[0] = '-') then exp else "+" ^ exp in
    mant ^ "e" ^ exp

let scalar = function
  | Null -> Some "null"
  | Bool b -> Some (string_of_bool b)
  | Num n -> Some (normalize_number n)
  | Str s when is_block_string s -> None
  | Str s -> Some (if is_plain s then s else quote s)
  | Arr [] -> Some "[]"
  | Obj [] -> Some "{}"
  | Arr _ | Obj _ -> None

let indent = List.map (fun l -> if l = "" then "" else "  " ^ l)

(* Строки YAML для значения в блочном контексте. *)
let rec lines (v : json) : string list =
  match v with
  | Obj kvs ->
    List.concat_map
      (fun (k, v) ->
        let key = match scalar (Str k) with Some s -> s | None -> quote k in
        match v, scalar v with
        | _, Some s -> [ key ^ ": " ^ s ]
        | Str s, None -> let h, ls = block_string s in (key ^ ": " ^ h) :: indent ls
        | _, None -> (key ^ ":") :: indent (lines v))
      kvs
  | Arr items ->
    List.concat_map
      (fun v ->
        match v, scalar v with
        | _, Some s -> [ "- " ^ s ]
        | Str s, None -> let h, ls = block_string s in ("- " ^ h) :: indent ls
        | _, None ->
          (* первый ключ объекта или элемент вложенного списка — на строке с дефисом *)
          (match lines v with
           | first :: rest -> ("- " ^ first) :: indent rest
           | [] -> [ "- " ]))
      items
  | Str s when is_block_string s -> let h, ls = block_string s in h :: indent ls
  | _ -> (match scalar v with Some s -> [ s ] | None -> [])

(* ---------- запуск ---------- *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  match args with
  | [] ->
    prerr_endline "Использование: ocaml json2yaml.ml <вход.json> [выход.yaml]";
    exit 1
  | input :: rest ->
    let text =
      try read_file input
      with Sys_error e -> prerr_endline ("Не удалось прочитать файл: " ^ e); exit 3
    in
    let text =   (* убрать BOM, если он есть *)
      if String.length text >= 3 && String.sub text 0 3 = "\xEF\xBB\xBF"
      then String.sub text 3 (String.length text - 3) else text
    in
    (match parse text with
     | exception Parse_error msg ->
       prerr_endline ("Ошибка JSON в " ^ input ^ ": " ^ msg);
       exit 2
     | json ->
       let yaml = String.concat "\n" (lines json) ^ "\n" in
       (match rest with
        | out :: _ ->
          let oc = open_out_bin out in
          output_string oc yaml;
          close_out oc;
          prerr_endline ("YAML записан в " ^ out)
        | [] -> print_string yaml))
