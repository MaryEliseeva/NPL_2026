%% TCP-сервер для хранения и выдачи заметок.
%% Процессы:
%%   storage  — единственный владелец данных, хранит заметки и сохраняет их в файл;
%%   acceptor — принимает новые подключения;
%%   client   — по одному процессу на каждого подключённого клиента.
%% Протокол текстовый, одна команда — одна строка (см. README).

-module(notes_server).
-export([start/0, start/1]).

-define(DEFAULT_PORT, 5555).
-define(DATA_FILE, "notes.dat").

start() -> start(?DEFAULT_PORT).

start([PortAtom]) when is_atom(PortAtom) ->           % из командной строки: -s notes_server start 6000
    start(list_to_integer(atom_to_list(PortAtom)));
start(Port) when is_integer(Port) ->
    io:setopts(standard_io, [{encoding, unicode}]),
    Storage = spawn(fun() -> storage_init() end),
    register(storage, Storage),
    {ok, Listen} = gen_tcp:listen(Port, [binary, {packet, line}, {active, false},
                                         {reuseaddr, true}]),
    io:format("Сервер заметок слушает порт ~p~n", [Port]),
    acceptor(Listen).

%% ---------- приём подключений ----------

acceptor(Listen) ->
    {ok, Socket} = gen_tcp:accept(Listen),
    Pid = spawn(fun() -> client_start(Socket) end),
    ok = gen_tcp:controlling_process(Socket, Pid),
    Pid ! go,
    acceptor(Listen).

client_start(Socket) ->
    receive go -> ok end,
    {ok, {Ip, Port}} = inet:peername(Socket),
    Peer = io_lib:format("~s:~p", [inet:ntoa(Ip), Port]),
    io:format("[+] клиент ~s подключился~n", [Peer]),
    send(Socket, "OK сервер заметок. HELP — список команд"),
    client_loop(Socket, Peer).

client_loop(Socket, Peer) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Line} ->
            Cmd = string:trim(Line),
            io:format("    ~s: ~ts~n", [Peer, Cmd]),
            case handle(Cmd) of
                quit -> send(Socket, "OK пока"), gen_tcp:close(Socket),
                        io:format("[-] клиент ~s отключился~n", [Peer]);
                Reply -> send(Socket, Reply), client_loop(Socket, Peer)
            end;
        {error, _} ->
            io:format("[-] клиент ~s отключился~n", [Peer])
    end.

send(Socket, Text) ->
    gen_tcp:send(Socket, [unicode:characters_to_binary(Text), "\n"]).

%% ---------- разбор команд ----------

handle(Cmd) ->
    {Word, Rest} = case string:split(Cmd, " ") of
                       [W, R] -> {W, string:trim(R)};
                       [W]    -> {W, <<>>}
                   end,
    case string:uppercase(Word) of
        <<"ADD">> when Rest =/= <<>> -> call({add, Rest});
        <<"ADD">>   -> "ERR пустая заметка";
        <<"LIST">>  -> call(list);
        <<"GET">>   -> with_id(Rest, fun(Id) -> call({get, Id}) end);
        <<"DEL">>   -> with_id(Rest, fun(Id) -> call({del, Id}) end);
        <<"FIND">> when Rest =/= <<>> -> call({find, Rest});
        <<"FIND">>  -> "ERR укажите слово";
        <<"COUNT">> -> call(count);
        <<"HELP">>  -> help();
        <<"QUIT">>  -> quit;
        <<>>        -> "ERR пустая команда";
        _           -> "ERR неизвестная команда, HELP — список команд"
    end.

with_id(Text, Fun) ->
    try binary_to_integer(Text) of
        Id -> Fun(Id)
    catch
        error:badarg -> "ERR номер должен быть числом"
    end.

help() ->
    "OK команды: ADD <текст> | LIST | GET <номер> | DEL <номер> | FIND <слово> | COUNT | QUIT".

%% Синхронный вызов процесса-хранилища: отправить запрос и дождаться ответа.
call(Request) ->
    Ref = make_ref(),
    storage ! {self(), Ref, Request},
    receive {Ref, Reply} -> Reply
    after 5000 -> "ERR хранилище не отвечает"
    end.

%% ---------- хранилище ----------

storage_init() ->
    Notes = case file:read_file(?DATA_FILE) of
                {ok, Bin} -> maps:from_list([parse_line(L) || L <- binary:split(Bin, <<"\n">>, [global, trim_all])]);
                {error, _} -> #{}
            end,
    io:format("Загружено заметок: ~p~n", [maps:size(Notes)]),
    storage_loop(Notes).

storage_loop(Notes) ->
    receive
        {From, Ref, Request} ->
            {Reply, NewNotes} = storage_handle(Request, Notes),
            if NewNotes =/= Notes -> persist(NewNotes); true -> ok end,
            From ! {Ref, Reply},
            storage_loop(NewNotes)
    end.

storage_handle({add, Text}, Notes) ->
    Id = lists:max([0 | maps:keys(Notes)]) + 1,
    Stamp = timestamp(),
    {io_lib:format("OK добавлена заметка ~p", [Id]), Notes#{Id => {Stamp, Text}}};
storage_handle(list, Notes) when map_size(Notes) =:= 0 ->
    {"OK заметок нет", Notes};
storage_handle(list, Notes) ->
    {format_list(maps:to_list(Notes)), Notes};
storage_handle({get, Id}, Notes) ->
    case maps:find(Id, Notes) of
        {ok, {Stamp, Text}} -> {[<<"OK ">>, Stamp, <<" | ">>, Text], Notes};
        error -> {"ERR нет заметки с таким номером", Notes}
    end;
storage_handle({del, Id}, Notes) ->
    case maps:is_key(Id, Notes) of
        true  -> {io_lib:format("OK заметка ~p удалена", [Id]), maps:remove(Id, Notes)};
        false -> {"ERR нет заметки с таким номером", Notes}
    end;
storage_handle({find, Word}, Notes) ->
    Needle = string:casefold(Word),
    Found = [N || {_, {_, Text}} = N <- maps:to_list(Notes),
                  string:find(string:casefold(Text), Needle) =/= nomatch],
    case Found of
        [] -> {"OK ничего не найдено", Notes};
        _  -> {format_list(Found), Notes}
    end;
storage_handle(count, Notes) ->
    {io_lib:format("OK заметок: ~p", [maps:size(Notes)]), Notes}.

%% Многострочный ответ: строки списка, в конце строка END.
format_list(Pairs) ->
    Lines = [[integer_to_binary(Id), <<". [">>, Stamp, <<"] ">>, Text]
             || {Id, {Stamp, Text}} <- lists:keysort(1, Pairs)],
    lists:join(<<"\n">>, [<<"OK список:"/utf8>> | Lines] ++ [<<"END">>]).

timestamp() ->
    {{Y, Mo, D}, {H, Mi, _}} = calendar:local_time(),
    list_to_binary(io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w", [Y, Mo, D, H, Mi])).

%% Файл хранения: одна заметка — одна строка «номер<TAB>дата<TAB>текст».
persist(Notes) ->
    file:write_file(?DATA_FILE, [[integer_to_binary(Id), $\t, Stamp, $\t, Text, $\n]
                                 || {Id, {Stamp, Text}} <- lists:keysort(1, maps:to_list(Notes))]).

parse_line(Line) ->
    [IdBin, Rest] = binary:split(Line, <<"\t">>),
    [Stamp, Text] = binary:split(Rest, <<"\t">>),
    {binary_to_integer(IdBin), {Stamp, Text}}.
