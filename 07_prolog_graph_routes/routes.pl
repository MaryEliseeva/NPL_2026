% Поиск всех возможных маршрутов между двумя вершинами графа.
% Маршрут — простой путь (без повторных вершин). Prolog сам перебирает
% все варианты с возвратом (backtracking), findall собирает их в список.

:- initialization(main, main).
:- ensure_loaded(graph).    % граф берётся из graph.pl рядом с программой

% Дороги двусторонние.
connected(A, B, D) :- edge(A, B, D).
connected(A, B, D) :- edge(B, A, D).

% route(+Откуда, +Куда, -Путь, -Длина)
route(From, To, Path, Dist) :-
    walk(From, To, [From], RevPath, Dist),
    reverse(RevPath, Path).

% walk(+Текущая, +Цель, +Посещённые, -Путь_в_обратном_порядке, -Длина)
walk(To, To, Visited, Visited, 0).
walk(Cur, To, Visited, Path, Dist) :-
    Cur \== To,
    connected(Cur, Next, D1),
    \+ memberchk(Next, Visited),
    walk(Next, To, [Next | Visited], Path, D2),
    Dist is D1 + D2.

vertex(V) :- connected(V, _, _).

print_route(N, Dist-Path) :-
    atomic_list_concat(Path, ' -> ', Text),
    length(Path, L), Hops is L - 1,
    format("~w. ~w км, ~w перегон(ов): ~w~n", [N, Dist, Hops, Text]).

print_all([], _).
print_all([R | Rs], N) :- print_route(N, R), N1 is N + 1, print_all(Rs, N1).

main([From, To]) :- !,
    (   \+ vertex(From) -> format("Нет вершины ~w~n", [From])
    ;   \+ vertex(To)   -> format("Нет вершины ~w~n", [To])
    ;   findall(D-P, route(From, To, P, D), Routes0),
        msort(Routes0, Routes),            % по возрастанию длины
        length(Routes, Count),
        format("Маршруты из ~w в ~w: найдено ~w~n~n", [From, To, Count]),
        print_all(Routes, 1),
        (   Routes = [Best | _]
        ->  last(Routes, Worst),
            nl, write('Кратчайший:    '), print_route(1, Best),
            write('Самый длинный: '), print_route(Count, Worst)
        ;   true
        )
    ).
main(_) :-
    format("Использование: swipl routes.pl <откуда> <куда>~n").
