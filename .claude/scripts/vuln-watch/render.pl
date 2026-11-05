# =====================================================================
# 表示の文を組み立てるモジュール
#
# vuln-watch.pl の show が require で読み込む。呼び出し方は render_text(\%material, \@entries, \%result) だけで、
# 表示の文(Markdown)を文字の列で返す。
#   %material は material.json を読んだ値、@entries はすべての entries-<番号>.json の entries をつないだ一覧、
#   %result は判断の JSON(result.json)を読んだ値とする。
# 判断の JSON を確かめるのは show で、このモジュールは確かめたあとの値を受け取る。判断の無い項目があれば die する。
# 見出しの日付は、collected_at と window_from を UTC+9 で表した日付とする。
# このモジュールはファイルを読み書きしない。
# 前提: perl(Time::Local)
# =====================================================================
use strict;
use warnings;
use utf8;
use Time::Local qw(timegm);

my $RENDER_LIST_MAX = 5;     # CVE の番号と元の発表の URL を並べる数の上限
my $RENDER_TZ = 9 * 3600;    # 見出しの日付の時間帯(UTC+9)
my $RENDER_NO_RANK = 1e9;    # cvemon の rank を持たない項目を並べる値

# 「GitHub を読めなかった」の行に並べる、material.json の github の欄と名前
my @RENDER_GITHUB = ([ advisories_ok => 'GitHub の勧告' ], [ sbom_ok => 'backend の間接の依存' ], [ refs_ok => 'PR と Issue' ]);

sub render_text {
    my ($material, $entries, $result) = @_;
    my %judged = map { $_->{key} => $_ } @{ $result->{entries} // [] };
    my $span = sprintf '(%sから%sまで)', _render_day($material->{window_from}), _render_day($material->{collected_at});
    my @failed = map { $_->{name} } @{ $material->{failed} // [] };
    my @failed_line = @failed ? ('取れなかった出どころ: ' . join('、', @failed)) : ();
    return join '', map { "$_\n" } "直近7日に出た脆弱性は無い。$span", @failed_line unless @$entries;

    my @lines = ("## 直近7日に出た脆弱性$span", @failed_line);
    my $github = $material->{github} // {};
    my @unread = map { $_->[1] } grep { !$github->{ $_->[0] } } @RENDER_GITHUB;
    if (@unread) {
        # 英数字で終わる名前(PR と Issue)のあとは、空白を置いてから「を」を続ける
        my $what = join '、', @unread;
        push @lines, 'GitHub を読めなかったので、' . $what . ($what =~ /[A-Za-z0-9]\z/ ? ' ' : '') . 'を調べていない。';
    }
    my $inventory = $material->{inventory} // {};
    push @lines, sprintf('main を取り込めなかったので、手元の main の写し(%s)の部品と比べた。', substr($inventory->{commit} // '', 0, 7))
        unless $inventory->{fetched};

    my (@repo, @pc, @others);
    for my $i (0 .. $#$entries) {
        my $e = $entries->[$i];
        my $j = $judged{ $e->{key} } // die "render.pl: 判断の JSON に無い項目: $e->{key}\n";
        my $item = { e => $e, j => $j, index => $i };
        my $verdict = $j->{verdict} // '';
        if ($verdict eq 'affected' || $verdict eq 'undeterminable') {
            push @repo, $item;
        } elsif (@{ $j->{pc} // [] }) {
            push @pc, $item;
        } else {
            push @others, $item;
        }
    }
    my $refs_ok = $github->{refs_ok} ? 1 : 0;
    if (@repo) {
        push @lines, '', '### このリポジトリの部品に影響がある脆弱性と、影響があるかを決められない脆弱性';
        push @lines, '', _render_detail($_, 1, $refs_ok) for _render_sort(1, @repo);
    }
    if (@pc) {
        push @lines, '', '### 開発者の PC で動くソフトの脆弱性';
        push @lines, '', _render_detail($_, 0, $refs_ok) for _render_sort(0, @pc);
    }
    if (@others) {
        push @lines, '', '### そのほかの脆弱性';
        push @lines, map { sprintf '- %s%s— %s — %s', $_->{j}{name}, _render_cves($_->{e}), $_->{j}{software}, $_->{e}{origins}[0] // '' }
            _render_sort(0, @others);
    }
    return join '', map { "$_\n" } @lines;
}

# 1つ目と2つ目の組の項目の行。$repo が真のときは、このリポジトリの部品についての行も書く
sub _render_detail {
    my ($item, $repo, $refs_ok) = @_;
    my ($e, $j) = @$item{qw(e j)};
    my $verdict = $j->{verdict} // '';
    my @lines = (
        "#### $j->{name}" . _render_cves($e),
        "- 起きる被害: $j->{damage}",
        '- 悪用: ' . _render_exploited($e, $j),
        '- 元の発表: ' . _render_list($e->{origins}, $e->{origins_total}),
    );
    if ($repo) {
        if ($verdict eq 'affected') {
            push @lines, _render_parts($e), "- 開発者がすること: $j->{action}";
        }
        my @refs = map { "#$_->{number}" } @{ $e->{refs} // [] };
        push @lines, '- すでに扱っている PR と Issue: ' . ($refs_ok ? join('、', @refs) : 'PR と Issue を読めなかった') if !$refs_ok || @refs;
        if ($verdict eq 'undeterminable') {
            push @lines, "- 影響があるかを決められない理由: $j->{reason}", "- 開発者が確かめる手順: $j->{check}";
        }
    }
    push @lines, map { "- PC で動くソフト: $_->{software} $_->{versions}、直った版: $_->{fixed}、確かめる手順: $_->{check}" } @{ $j->{pc} // [] };
    return @lines;
}

# 「影響を受ける部品」の行。in_range が真の部品ごとに1行書き、無ければコンテナの脆弱性の Issue の番号を書く
sub _render_parts {
    my ($e) = @_;
    my @in = grep { $_->{in_range} } @{ $e->{matches} // [] };
    return map {
        sprintf '- 影響を受ける部品: %s %s(%s)、直った版: %s', $_->{key}, join(', ', @{ $_->{repo_versions} // [] }), $_->{file} // '', $_->{fixed} // '分からない'
    } @in if @in;
    my @issues = map { "#$_->{number}" } grep { ($_->{kind} // '') eq 'issue' } @{ $e->{refs} // [] };
    return @issues ? ('- 影響を受ける部品: コンテナの脆弱性の Issue に書かれたイメージ(' . join('、', @issues) . ')') : ();
}

sub _render_exploited {
    my ($e, $j) = @_;
    return "確かめられている(CISA の一覧に $e->{kev} に載った)" if defined $e->{kev};
    return '確かめられていない' unless $j->{exploited};
    my $note = $j->{exploited_note};
    return defined $note && length $note ? "確かめられている($note)" : '確かめられている';
}

# 見出しの名前のあとの CVE の番号。番号が無ければ何も書かない
sub _render_cves {
    my ($e) = @_;
    my @cves = @{ $e->{cves} // [] };
    return @cves ? '(' . _render_list(\@cves) . ')' : '';
}

# 一覧の先頭の5件を「、」でつなぎ、残りがあれば「ほか N 件」を足す。$total は一覧の全体の数で、一覧より多いときに使う
sub _render_list {
    my ($list, $total) = @_;
    my @all = @{ $list // [] };
    my @shown = @all > $RENDER_LIST_MAX ? @all[ 0 .. $RENDER_LIST_MAX - 1 ] : @all;
    my $rest = (defined $total && $total > @all ? $total : scalar @all) - @shown;
    return join '、', @shown, ($rest > 0 ? ("ほか $rest 件") : ());
}

# 組の中の並び。$by_verdict が真のときは affected を先にする。どの組でも exploited を先に、そのあとを出どころの日付の
# 新しい順にし、日付を持たない項目(cvemon だけに載った項目)を最後に rank の順に並べる。同じなら材料の順にする
sub _render_sort {
    my ($by_verdict, @items) = @_;
    for my $item (@items) {
        my ($day, $rank) = ('', $RENDER_NO_RANK);
        for my $s (@{ $item->{e}{sources} // [] }) {
            if (($s->{source} // '') eq 'cvemon') {
                $rank = $s->{rank} if defined $s->{rank} && $s->{rank} < $rank;
            } elsif (($s->{published} // '') =~ /\A(\d{4}-\d{2}-\d{2})/) {
                $day = $1 if $1 gt $day;
            }
        }
        $item->{order} = {
            affected  => ($by_verdict && ($item->{j}{verdict} // '') eq 'affected') ? 1 : 0,
            exploited => $item->{j}{exploited} ? 1 : 0,
            day       => $day,
            rank      => length $day ? 0 : $rank,
        };
    }
    return sort {
        my ($x, $y) = ($a->{order}, $b->{order});
        $y->{affected} <=> $x->{affected}
            || $y->{exploited} <=> $x->{exploited}
            || $y->{day} cmp $x->{day}
            || $x->{rank} <=> $y->{rank}
            || $a->{index} <=> $b->{index}
    } @items;
}

# YYYY-MM-DDThh:mm:ssZ の時刻を、UTC+9 で表した日付にする。形が違えば先頭の日付の部分をそのまま使う
sub _render_day {
    my ($time) = @_;
    $time //= '';
    if ($time =~ /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z\z/) {
        my @t = gmtime(timegm($6, $5, $4, $3, $2 - 1, $1) + $RENDER_TZ);
        return sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3];
    }
    return $time =~ /\A(\d{4}-\d{2}-\d{2})/ ? $1 : $time;
}

1;
