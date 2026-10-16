#!/usr/bin/env perl
# Консольный менеджер заметок с сохранением в текстовый файл.
# Режимы: интерактивный (без аргументов) и разовая команда из аргументов.

use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));
use POSIX qw(strftime);

my $FILE = $ENV{NOTES_FILE} // 'notes.txt';
my @notes;    # элементы: { id, created, title, text }

# ---------- хранение ----------
# Одна заметка — одна строка: id<TAB>дата<TAB>заголовок<TAB>текст.
# Табуляции, переводы строк и обратные слеши внутри полей экранируются.
sub esc   { my $s = shift; $s =~ s/\\/\\\\/g; $s =~ s/\t/\\t/g; $s =~ s/\n/\\n/g; $s }
sub unesc { my $s = shift; $s =~ s/\\(.)/$1 eq 't' ? "\t" : $1 eq 'n' ? "\n" : $1/ge; $s }

sub load {
    @notes = ();
    return unless -e $FILE;
    open my $fh, '<', $FILE or die "Не могу открыть $FILE: $!\n";
    while (my $line = <$fh>) {
        chomp $line;
        next unless length $line;
        my ($id, $created, $title, $text) = split /\t/, $line, 4;
        push @notes, { id => $id, created => $created,
                       title => unesc($title // ''), text => unesc($text // '') };
    }
    close $fh;
}

sub save {
    open my $fh, '>', $FILE or die "Не могу записать $FILE: $!\n";
    print $fh join("\t", $_->{id}, $_->{created}, esc($_->{title}), esc($_->{text})), "\n"
        for @notes;
    close $fh;
}

sub next_id { my $max = 0; $max < $_->{id} and $max = $_->{id} for @notes; $max + 1 }
sub find    { my $id = shift; (grep { $_->{id} == $id } @notes)[0] }
sub now     { strftime('%Y-%m-%d %H:%M', localtime) }

# ---------- команды ----------
sub cmd_add {
    my ($title, $text) = @_;
    return print "Заголовок не может быть пустым\n" unless defined $title && $title =~ /\S/;
    my $n = { id => next_id(), created => now(), title => $title, text => $text // '' };
    push @notes, $n;
    save();
    print "Добавлена заметка #$n->{id}\n";
}

sub cmd_list {
    return print "Заметок нет\n" unless @notes;
    printf "%-4s %-17s %s\n", '#', 'Создана', 'Заголовок';
    printf "%-4s %-17s %s\n", $_->{id}, $_->{created}, $_->{title} for @notes;
}

sub cmd_show {
    my $n = find(shift // 0) or return print "Нет такой заметки\n";
    print "#$n->{id}  [$n->{created}]\n$n->{title}\n", '-' x 30, "\n$n->{text}\n";
}

sub cmd_edit {
    my ($id, $title, $text) = @_;
    my $n = find($id // 0) or return print "Нет такой заметки\n";
    $n->{title} = $title if defined $title && $title =~ /\S/;
    $n->{text}  = $text  if defined $text;
    save();
    print "Заметка #$id изменена\n";
}

sub cmd_delete {
    my $id = shift // 0;
    my $before = @notes;
    @notes = grep { $_->{id} != $id } @notes;
    return print "Нет такой заметки\n" if @notes == $before;
    save();
    print "Заметка #$id удалена\n";
}

sub cmd_search {
    my $word = shift;
    return print "Укажите слово для поиска\n" unless defined $word && length $word;
    my @found = grep { $_->{title} =~ /\Q$word\E/i || $_->{text} =~ /\Q$word\E/i } @notes;
    return print "Ничего не найдено\n" unless @found;
    printf "#%-3s %s\n", $_->{id}, $_->{title} for @found;
}

sub help {
    print <<'END';
Команды:
  add               добавить заметку (заголовок и текст будут запрошены)
  list              список заметок
  show <N>          показать заметку N
  edit <N>          изменить заметку N
  delete <N>        удалить заметку N
  search <слово>    поиск по заголовку и тексту
  help              эта справка
  exit              выход
END
}

# Многострочный ввод: читаем строки до пустой строки.
sub ask {
    my ($prompt, $multiline) = @_;
    print $prompt;
    if (!$multiline) { my $l = <STDIN> // ''; chomp $l; return $l }
    my @lines;
    while (defined(my $l = <STDIN>)) { chomp $l; last if $l eq ''; push @lines, $l }
    join "\n", @lines;
}

sub interactive {
    print "Менеджер заметок. Файл: $FILE. Введите help для справки.\n";
    while (1) {
        print "> ";
        my $line = <STDIN>;
        last unless defined $line;
        chomp $line;
        my ($cmd, $arg) = split ' ', $line, 2;
        next unless defined $cmd;
        if    ($cmd eq 'add')    { cmd_add(ask('Заголовок: '), ask("Текст (пустая строка — конец):\n", 1)) }
        elsif ($cmd eq 'list')   { cmd_list() }
        elsif ($cmd eq 'show')   { cmd_show($arg) }
        elsif ($cmd eq 'edit')   {
            unless (find($arg // 0)) { print "Нет такой заметки\n"; next }
            cmd_edit($arg, ask('Новый заголовок (Enter — оставить): '),
                     ask("Новый текст (пустая строка — конец; сразу Enter — оставить):\n", 1) || undef);
        }
        elsif ($cmd eq 'delete') { cmd_delete($arg) }
        elsif ($cmd eq 'search') { cmd_search($arg) }
        elsif ($cmd eq 'help')   { help() }
        elsif ($cmd eq 'exit' || $cmd eq 'quit') { last }
        else  { print "Неизвестная команда, введите help\n" }
    }
    print "До свидания!\n";
}

# ---------- запуск ----------
load();
if (@ARGV) {
    @ARGV = map { utf8::decode($_); $_ } @ARGV;
    my $cmd = shift @ARGV;
    my %dispatch = (add => \&cmd_add, list => \&cmd_list, show => \&cmd_show,
                    edit => \&cmd_edit, delete => \&cmd_delete, search => \&cmd_search,
                    help => \&help);
    ($dispatch{$cmd} // \&help)->(@ARGV);
} else {
    interactive();
}
