#!/bin/bash
# =====================================================================
# PreToolUse(Bash) hook: ラベルが足りない Issue の起票を止める
#
# Claude が Bash で打つコマンドの中に Issue を作るコマンドがあれば、
# ラベルの一覧のファイル(.github/labels.json)と照らし、ラベルが足りなければ
# 実行前に止めて(exit 2)理由を返す(#500)。ラベルを選ぶことと、
# コマンドを書き換えることはしない。
#
# Issue を作るコマンド(&& || ; | & 改行でつないだものと、sh -c '...' / bash -c '...'
# の中、url=$(gh issue create ...) の形に書いたものも含む):
#   gh issue create / gh issue new(create の別名)。gh と issue の間や、issue と create の
#   間に書いた -R / --repo も読む
#   ヒアドキュメントの本文の行は読まない。ただし、sh か bash が受けるもの
#   (bash <<EOF、sh -s <<EOF など)の本文はコマンドとして読む
#   gh api で Issue を作るもの(repos/<owner>/<repo>/issues に -f / -F / --field /
#   --raw-field / --input か -X POST / --method POST を付けたもの。-X GET などは除く。
#   graphql の createIssue)
#
# 止める決まり(この順に見て、最初に当たったもので止める):
#   1. gh api で Issue を作るコマンドである
#   2. (-R / --repo がこのリポジトリでないときは、止めずに通す)
#   3. --template / -T、--recover、--web / -w、--editor / -e のどれかがある
#   4. ラベルの一覧のファイルを読めない、JSON として読めない、group が kind のラベルが無い
#   5. -l / --label の値(重ね書き・カンマ区切り・--label=値。大文字と小文字は区別しない)の
#      うち、group が kind のラベルに当たるものがちょうど1つでない
#   6. 当たった種類のラベルの area_required が true なのに、group が area のラベルが1つも無い
# フックはラベルの名前を持たない。どのラベルが種類で、どの種類が場所のラベルを要るかは、
# ファイルの group と area_required で決まる。
#
# ファイルを読む場所: 入力の cwd で git rev-parse --show-toplevel を呼び、その下の
# .github/labels.json を読む。cwd が無いかリポジトリの中でなければ、CLAUDE_PROJECT_DIR の下の
# .github/labels.json を読む。フック自身の置き場所からはたどらない(Claude Desktop の
# worktree のセッションが本体の作業フォルダのフックを使ったときに、本体の古いファイルを
# 読まないため)。このリポジトリかどうかは、同じフォルダの git remote get-url origin の
# <owner>/<repo> で決める(https と git@ の形を読む。大文字と小文字は区別しない)。
#
# 入力が JSON でないときと、コマンドの欄が無いときは、止めずに通す。
#
# 前提: bash・perl(JSON::PP・Text::ParseWords)・git。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
# =====================================================================
set -u

payload=$(cat)

why=$(printf '%s' "$payload" | perl -MJSON::PP -MText::ParseWords -e '
    use strict;
    use warnings;
    use utf8;
    binmode STDOUT, ":encoding(UTF-8)";
    local $/;
    my $d = eval { JSON::PP::decode_json(<STDIN>) };
    exit 0 unless ref $d eq "HASH";
    my $cmd = eval { $d->{tool_input}{command} };
    exit 0 unless defined $cmd && !ref $cmd;
    my $cwd = $d->{cwd};
    $cwd = undef if ref $cwd;

    # ---- コマンドを読む ----

    # 見つけた Issue を作るコマンド: { type => "issue", args => [...] } か { type => "api" }
    my @found;

    sub base { my $t = shift; $t =~ s{.*[/\\]}{}; $t =~ s/\.exe\z//i; return $t; }

    # コマンドの前に置ける語(環境変数の指定のほかに飛ばすもの)
    my %prefix = map { $_ => 1 }
        qw(env command builtin exec time nohup if then else elif do while until ! {);

    my %api_value = map { $_ => 1 }
        qw(-X --method -f --raw-field -F --field -H --header --input -q --jq -t --template
           --hostname --cache -p --preview);

    # gh api の引数から、Issue を作る呼び出しかどうかを決める
    sub api_creates {
        my @a = @_;
        my ($method, $body, @pos) = (undef, 0);
        for (my $i = 0; $i < @a; $i++) {
            my $t = $a[$i];
            if ($t eq "--") { push @pos, @a[$i + 1 .. $#a]; last; }
            my ($name, $val);
            if ($t =~ /\A(--[A-Za-z][\w-]*)=(.*)\z/s) {
                ($name, $val) = ($1, $2);
            } elsif ($t =~ /\A(-[A-Za-z])(.+)\z/s && $api_value{$1}) {
                ($name, $val) = ($1, $2);
                $val =~ s/\A=//;
            } elsif ($t =~ /\A-./s) {
                $name = $t;
                $val = $a[++$i] if $api_value{$t};
            } else {
                push @pos, $t;
                next;
            }
            $body = 1 if $name =~ /\A(?:-f|-F|--field|--raw-field|--input)\z/;
            $method = $val if $name =~ /\A(?:-X|--method)\z/ && defined $val;
        }
        return 0 unless @pos;
        return (grep { /createIssue/ } @a) ? 1 : 0 if $pos[0] eq "graphql";
        (my $p = $pos[0]) =~ s/\?.*\z//s;
        return 0 unless $p =~ m{\A/?repos/[^/]+/[^/]+/issues/?\z};
        return uc($method) eq "POST" ? 1 : 0 if defined $method;
        return $body;
    }

    # 区切った1つのコマンドを読む
    sub segment {
        my @w;
        for my $t (@_) {
            my $x = $t;
            # NAME=$( の NAME= を外し、語の頭の $( ( ` と末尾の ) ` を外す
            $x =~ s/\A[A-Za-z_][A-Za-z0-9_]*=(?=\$\(|`)//;
            $x =~ s/\A(?:\$\(|\(|`)+//;
            $x =~ s/(?:\)|`)+\z//;
            push @w, $x if length $x;
        }
        my $i = 0;
        while ($i < @w) {
            if ($w[$i] =~ /\A[A-Za-z_][A-Za-z0-9_]*=/) { $i++; next; }
            if ($prefix{$w[$i]}) {
                $i++;
                $i++ while $i < @w && $w[$i] =~ /\A-/;
                next;
            }
            last;
        }
        return if $i >= @w || base($w[$i]) ne "gh";
        my @a = @w[$i + 1 .. $#w];
        # gh と issue の間に書いた -R / --repo(--repo=値、-R値 を含む)とその値は、
        # 飛ばして読み、起票の引数に入れる
        my @repo;
        while (@a && $a[0] =~ /\A(?:-R(.*)|--repo(=.*)?)\z/s) {
            my $attached = (defined $1 && length $1) || defined $2;
            push @repo, shift @a;
            push @repo, shift @a if !$attached && @a;
        }
        return unless @a;
        if ($a[0] eq "issue") {
            # issue と create / new の間に書いたフラグ(-R など)も引数に入れる
            my @pre = @repo;
            my $j = 1;
            while ($j < @a && $a[$j] =~ /\A-/) {
                push @pre, $a[$j];
                if ($a[$j] =~ /\A(?:-R|--repo)\z/ && $j + 1 < @a) { push @pre, $a[++$j]; }
                $j++;
            }
            return unless $j < @a && ($a[$j] eq "create" || $a[$j] eq "new");
            push @found, { type => "issue", args => [@pre, @a[$j + 1 .. $#a]] };
        } elsif ($a[0] eq "api") {
            push @found, { type => "api" } if api_creates(@a[1 .. $#a]);
        }
    }

    # コマンドの区切り(&& || ; | & 改行)。2>&1 の & は区切りにしない
    my $sep = q{\s*(?:&&|\|\||(?<![<>])&(?!>)|[;|\n])\s*};
    # parse_line は区切りの正規表現を括弧でくくらずに埋め込むので、こちらでくくる
    my $delim = q{(?:} . $sep . q{|\s+)};

    # ヒアドキュメントを受けるコマンドが sh か bash(パスと .exe を外した名前)かどうか。
    # $before は、行のうち << より前の文字列。最後の区切りより後ろを、受けるコマンドとして見る
    sub heredoc_to_shell {
        my $s = shift;
        $s =~ s/\A.*(?:&&|\|\||(?<![<>])&(?!>)|[;|(`{]|\$\()//s;
        my @w = shellwords($s);
        @w = split " ", $s unless @w;
        my $i = 0;
        while ($i < @w) {
            if ($w[$i] =~ /\A[A-Za-z_][A-Za-z0-9_]*=/) { $i++; next; }
            if ($prefix{$w[$i]}) {
                $i++;
                $i++ while $i < @w && $w[$i] =~ /\A-/;
                next;
            }
            last;
        }
        return 0 if $i >= @w;
        my $b = base($w[$i]);
        return $b eq "sh" || $b eq "bash";
    }

    # 1行に書かれたヒアドキュメント(<<EOF、<<-EOF、<<\x27EOF\x27 など)を、書かれた順に返す。
    # 要素は [終わりの語, <<- かどうか, 本文をコマンドとして読むかどうか]
    sub heredoc_ops {
        my $line = shift;
        my @ops;
        while ($line =~ /(?<!<)<<(?!<)(-?)\s*(?:\x27([^\x27\n]*)\x27|"([^"\n]*)"|\\?([A-Za-z_][A-Za-z0-9_]*))/g) {
            my ($tabs, $tag) = ($1 eq "-", defined $2 ? $2 : defined $3 ? $3 : $4);
            push @ops, [$tag, $tabs, heredoc_to_shell(substr($line, 0, $-[0]))];
        }
        return @ops;
    }

    # ヒアドキュメントの本文の行を外す。本文の行(Issue の本文に書いた「gh issue create ...」
    # など)をコマンドとして読まないため。ただし、sh か bash が受けるヒアドキュメント
    # (bash <<EOF、sh -s <<EOF など)の本文はコマンドなので、外さずに読む
    sub strip_heredocs {
        my @out;
        my @pending;
        for my $line (split /\n/, shift, -1) {
            if (@pending) {
                my ($tag, $tabs, $keep) = @{ $pending[0] };
                my $l = $line;
                $l =~ s/\A\t+// if $tabs;
                if ($l eq $tag) {
                    shift @pending;
                    next;
                }
                next unless $keep;
            }
            push @out, $line;
            # 読む本文の中に書いたヒアドキュメントは、外側の本文の続きより先に終わる
            unshift @pending, heredoc_ops($line);
        }
        return join "\n", @out;
    }

    sub scan {
        my ($s, $depth) = @_;
        return if $depth > 4;
        $s = strip_heredocs($s);
        my @tok = parse_line($delim, "delimiters", $s);
        @tok = split /\s+/, $s unless @tok;
        my @seg;
        for my $w (@tok, ";") {
            next unless defined $w && length $w;
            # 改行も空白なので、区切りかどうかを先に見る
            if ($w =~ /^$sep$/) {
                segment(@seg);
                @seg = ();
                next;
            }
            next if $w =~ /^\s+$/;
            my $t = join " ", shellwords($w);
            $t = $w if $t eq "" && $w !~ /^(""|\x27\x27)$/;
            if ($t =~ /\s/) {
                if (@seg && $seg[-1] =~ /^-[a-z]*c$/) {
                    # sh -c / bash -lc の後ろの語は、それ自体を1つのコマンドとして見る
                    scan($t, $depth + 1);
                } elsif ($t =~ /(?:\$\(|`)(.*)\z/s) {
                    # 引用符でくくった "$(...)" の中も、1つのコマンドとして見る
                    scan($1, $depth + 1);
                }
            }
            push @seg, $t;
        }
    }

    scan($cmd, 0);
    exit 0 unless @found;

    # ---- このリポジトリとラベルの一覧のファイル ----

    sub git_out {
        my $fh;
        open($fh, "-|", "git", @_) or return undef;
        my $o = <$fh>;
        close $fh;
        return undef if $? || !defined $o;
        $o =~ s/\s+\z//;
        return length $o ? $o : undef;
    }

    # <owner>/<repo> を小文字で返す(owner/repo、host/owner/repo、https と git@ の URL)
    sub repo_key {
        my $s = shift;
        return undef unless defined $s;
        $s =~ s/\s+\z//;
        $s =~ s{/+\z}{};
        $s =~ s/\.git\z//i;
        my @p = grep { length } split m{[/:]}, $s;
        return undef if @p < 2;
        return lc "$p[-2]/$p[-1]";
    }

    my ($ctx_done, $labels_path, $this_repo);
    sub ctx {
        return if $ctx_done;
        $ctx_done = 1;
        my $dir;
        if (defined $cwd && length $cwd) {
            (my $c = $cwd) =~ tr{\\}{/};
            utf8::encode($c);
            $dir = git_out("-C", $c, "rev-parse", "--show-toplevel") if -d $c;
        }
        unless (defined $dir) {
            my $p = $ENV{CLAUDE_PROJECT_DIR};
            ($dir = $p) =~ tr{\\}{/} if defined $p && length $p;
        }
        return unless defined $dir;
        $labels_path = "$dir/.github/labels.json";
        $this_repo = repo_key(git_out("-C", $dir, "remote", "get-url", "origin"));
    }

    my ($loaded, $lab_err, @kinds, @areas);
    sub load {
        return if $loaded;
        $loaded = 1;
        ctx();
        unless (defined $labels_path) {
            $lab_err = "ファイルの場所が分かりません(作業フォルダがリポジトリの中でなく、CLAUDE_PROJECT_DIR もありません)";
            return;
        }
        my $shown = $labels_path;
        utf8::decode($shown);
        my $fh;
        unless (-f $labels_path && open($fh, "<:raw", $labels_path)) {
            $lab_err = "$shown がありません";
            return;
        }
        my $raw = <$fh>;
        close $fh;
        my $j = eval { JSON::PP::decode_json(defined $raw ? $raw : "") };
        unless (ref $j eq "HASH" && ref $j->{labels} eq "ARRAY") {
            $lab_err = "$shown を JSON として読めません";
            return;
        }
        for my $l (@{ $j->{labels} }) {
            next unless ref $l eq "HASH";
            next unless defined $l->{name} && !ref $l->{name} && length $l->{name};
            next unless defined $l->{group} && !ref $l->{group};
            push @kinds, $l if $l->{group} eq "kind";
            push @areas, $l if $l->{group} eq "area";
        }
        $lab_err = "$shown に group が kind のラベルが1つもありません" unless @kinds;
    }

    # area_required が false と書かれたときだけ、場所のラベルを要らないとする
    sub area_required {
        my $v = shift->{area_required};
        return !(JSON::PP::is_bool($v) && !$v);
    }

    sub text {
        my $v = shift;
        return (defined $v && !ref $v) ? $v : "";
    }

    # ---- 止める ----

    sub stop {
        my ($reason, $extra) = @_;
        load();
        my $s = "Issue の起票を止めました。\n理由: $reason\n";
        $s .= $extra if defined $extra;
        if (@kinds) {
            $s .= "\n種類のラベル(ちょうど1つを --label で付ける):\n";
            for my $l (@kinds) {
                $s .= "  - $l->{name}: " . text($l->{description})
                    . "(場所のラベル: " . (area_required($l) ? "要る" : "要らない") . ")\n";
                my $rule = text($l->{selection_rule});
                $s .= "      選ぶときの決まり: $rule\n" if length $rule;
            }
        }
        if (@areas) {
            $s .= "\n場所のラベル(種類のラベルが「要る」のとき、Issue が変える場所に当たるものをすべて --label で付ける):\n";
            $s .= "  - $_->{name}: " . text($_->{description}) . "\n" for @areas;
        }
        $s .= "\nラベルは、起票の決まり(.claude/skills/file-issue/SKILL.md の「ラベルの選び方」)に従って選んでください。\n";
        print $s;
        exit 0;
    }

    my %ic_value_long = map { $_ => 1 }
        qw(assignee body body-file label milestone project template title repo recover);
    my %ic_value_short = map { $_ => 1 } qw(a b F l m p T t R);

    for my $f (@found) {
        stop("gh api で Issue を作るコマンドは使えません。Issue は gh issue create で --label を付けて起票してください。")
            if $f->{type} eq "api";

        my @a = @{ $f->{args} };
        my (@labels, $repo, @blk, $help);
        for (my $i = 0; $i < @a; $i++) {
            my $t = $a[$i];
            last if $t eq "--";
            if ($t =~ /\A--([A-Za-z][\w-]*)(?:=(.*))?\z/s) {
                my ($n, $v) = ($1, $2);
                $v = $a[++$i] if $ic_value_long{$n} && !defined $v;
                push @labels, $v if $n eq "label" && defined $v;
                $repo = $v if $n eq "repo" && defined $v;
                push @blk, "--$n" if $n =~ /\A(?:template|recover|web|editor)\z/;
                $help = 1 if $n eq "help";
            } elsif ($t =~ /\A-([A-Za-z].*)\z/s) {
                my $s = $1;
                while (length $s) {
                    my $c = substr($s, 0, 1, "");
                    if ($ic_value_short{$c}) {
                        $s =~ s/\A=//;
                        my $v = length $s ? $s : $a[++$i];
                        push @labels, $v if $c eq "l" && defined $v;
                        $repo = $v if $c eq "R" && defined $v;
                        push @blk, "-T" if $c eq "T";
                        last;
                    }
                    push @blk, "-$c" if $c eq "w" || $c eq "e";
                    $help = 1 if $c eq "h";
                }
            }
        }
        # 使い方を出すだけのときは Issue を作らない
        next if $help;

        if (defined $repo) {
            ctx();
            my $k = repo_key($repo);
            next if defined $k && defined $this_repo && $k ne $this_repo;
        }

        if (@blk) {
            my %seen;
            my $flags = join "、", grep { !$seen{$_}++ } @blk;
            stop("$flags が付いています。コマンドに書かれていないラベルが付くか、ラベルを確かめられない形です。"
                . "--title と --body(または --body-file)と --label で起票してください。");
        }

        load();
        stop("ラベルの一覧のファイルを読めません($lab_err)。",
            "ラベルの一覧のファイルが読めるようになるまで起票せずに、このことを所有者に伝えてください。\n")
            if defined $lab_err;

        my %given;
        for my $v (@labels) {
            for my $n (split /,/, $v) {
                $n =~ s/\A\s+//;
                $n =~ s/\s+\z//;
                $given{lc $n} = 1 if length $n;
            }
        }
        my @k = grep { $given{ lc $_->{name} } } @kinds;
        if (@k == 0) {
            stop("種類のラベルが付いていません。種類のラベルをちょうど1つ付けてください。");
        } elsif (@k > 1) {
            stop("種類のラベルが " . scalar(@k) . " 個付いています(" . join("、", map { $_->{name} } @k)
                . ")。種類のラベルをちょうど1つ付けてください。");
        }
        if (area_required($k[0]) && !grep { $given{ lc $_->{name} } } @areas) {
            stop("種類のラベル $k[0]{name} は場所のラベルが要りますが、場所のラベルが付いていません。"
                . "Issue が変える場所に当たる場所のラベルを1つ以上付けてください。");
        }
    }
    exit 0;
' 2>/dev/null)

[ -z "$why" ] && exit 0

printf '%s\n' "$why" >&2
exit 2
