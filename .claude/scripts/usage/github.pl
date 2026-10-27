#!/usr/bin/env perl
# =====================================================================
# github.pl: GitHub に集計のコメントと、蓄積の一覧と、まだ答えていない直す案の索引を書く部品
#
# 呼び出し方:
#   perl github.pl reported <N>
#     Issue N に集計のコメントがあれば、そのコメントの URL を出して 0、無ければ 3 で終わる
#   perl github.pl list-read
#     一覧のすべての行を、数に戻して JSON の配列の1行で出す。一覧の Issue が無ければ [] を出す
#   perl github.pl list-add <行の JSON のファイル>
#     ファイルの行(list-read の出力と同じ形の配列)を一覧に足す。同じ Issue の行があれば置き換える
#   perl github.pl list-ensure <N>
#     一覧に Issue N の行が無ければ、Issue N の集計のコメントの最後の数字の行の JSON から行を作って足す
#   perl github.pl publish <N> --draft <下書きのディレクトリ> --findings <所見のファイル>
#     下書きの report.json と report.md と所見のファイルが集計のコメントの形だけからなることを確かめ、
#     所見の直す案の ID を issues/<N>.json の proposals_pending に書いてから、Issue N に集計のコメントを書く。
#     そのあと、案を案の索引に足し、一覧に行を足す。集計のコメントを書けたら、索引か一覧に書けなくても 0 で終わり、
#     {"failed":[書けなかった書き込み],"proposals":[案の ID],"url":<集計のコメントの URL>} の1行を出す
#   perl github.pl proposals-ensure <N>
#     issues/<N>.json の proposals_pending の案を案の索引に足す。足せたら proposals_pending を消す
#   perl github.pl proposals-open
#     案の索引の案を、[{"id","issue","text"}] の JSON の1行で出す。text は集計のコメントの所見の案の文である
#   perl github.pl proposal-remove <案の ID>
#     案を、案の索引と、その Issue の issues/<N>.json の proposals_pending から外す
#
# 一覧の行は、終了日の古い順に、終了日が同じなら Issue の番号の順に並べ、300行ごとのページに分ける。
# 1ページ目は一覧の Issue の本文に、2ページ目からは行頭が <!-- keirekipro-usage-list:v1 page=<k> --> の
# コメントに置く。行を足したら、待ってから一覧を読み直し、足した行が無ければ3回まで書き直す。
# 足せなかったときは、その Issue の issues/<N>.json に list_pending を残して 1 で終わる。
#
# 案の索引は、一覧の Issue の、行頭が <!-- keirekipro-usage-proposals:v1 page=<k> <JSON> --> のコメントに、
# 案を1,000件ずつ置く。案が無くなったページは [] にして残す。書いたら、一覧と同じく読み直して確かめる。
#
# gh は、開発者の PC の gh のトークンで、いまの作業フォルダのリポジトリ({owner}/{repo})を読み書きする。
# 印で見つけるコメントと、題名で見つける一覧の Issue は、リポジトリとの関係の欄(author_association)が
# OWNER か COLLABORATOR のものに限る(trusted)。公開のリポジトリでは誰でもコメントと Issue を書けるので、
# 印や題名だけでは、この部品が書いたものと見分けられないためである。
#
# 一覧の Issue は、題名が「AIの作業の集計の一覧」で、書き手の確認を通り、ロックしてある Issue のうち、
# 最小の番号の Issue である。見つけた番号は、手元の記録の置き場所の state.json の list_issue に置いて使う。
# 一覧の Issue を作る・閉じる・ロックするのは、書き込む呼び出しだけで、書き込む呼び出しは、最初に
# permissions.push を確かめる。手元の記録の置き場所は、<git の共通ディレクトリ>/keirekipro-usage/ である。
#
# 終了コード: 0 できた / 1 gh の呼び出しに失敗した / 3 集計のコメントが無い / 64 引数が違う
# 失敗したときは、標準エラーに日本語の1文で理由を残す。
# =====================================================================
use strict;
use warnings;
use JSON::PP ();
use File::Temp ();
use Encode ();
use Scalar::Util ();
use File::Basename ();

# 集計のコメントの1行目の印。あとに issue=<N> と空白が続く
use constant REPORT_MARK => '<!-- keirekipro-usage-report:v1';

# 集計のコメントの最後の数字の行の印。あとに空白と report.json を1行にしたものが続く
use constant DATA_MARK => '<!-- keirekipro-usage-data:v1';

# 一覧の続きのコメントの1行目の印。あとに page=<k> が続く
use constant LIST_PAGE_MARK => '<!-- keirekipro-usage-list:v1';

# 一覧の Issue の題名と、作るときの本文(行の無い一覧)
use constant LIST_TITLE => 'AIの作業の集計の一覧';
use constant LIST_HEAD => <<'END';
| Issue | spec | 終了日 | AIの作業時間 | トークン数 | 使用料 | 実装中に spec へ戻った回数 |
|---|---|---|---|---|---|---|
END
use constant LIST_INTRO => <<'END' . LIST_HEAD;
## AIの作業の集計の一覧

この一覧は、Issue ごとの AI の作業の集計を、終了日の古い順に1行ずつ並べたものである。Issue の列の番号から、その Issue の集計のコメントを開ける。「AIの作業時間」は、AI の会話のどれかが動いていた時間で、所有者の返事を待っていた時間と、使う量の上限で止まっていた時間を含まない。「トークン数」は、入力、キャッシュの書き込み、キャッシュの読み込み、出力の合計である。「使用料」は、トークン数を公表価格で換算した米ドルの額である。「実装中に spec へ戻った回数」は、実装の途中で要件、設計、タスクに戻って直した回数の合計である。300行を超えた行は、この Issue のコメントに続く。

END

# 1ページの行の数と、一覧に行を足すときに書き直す回数
use constant ROWS_PER_PAGE => 300;
use constant LIST_TRIES => 3;

# 一覧の行の、数えられない値と、価格が分からないモデルがあるときの使用料のあとに付ける文
use constant UNCOUNTABLE => '数えられない';
use constant USD_PARTIAL => '(価格が分からないモデルを除く)';

# 案の索引のコメントの1行目の印。あとに page=<k> と空白と案の JSON が続く。2行目は、コメントの用途を示す文である
use constant PROPOSALS_MARK => '<!-- keirekipro-usage-proposals:v1';
use constant PROPOSALS_NOTE => "このコメントは、所有者がまだ起票するかを答えていない直す案の番号を、AI が覚えておくためのものである。案の文は、番号の頭の Issue の集計のコメントの所見にある。\n";

# 案の索引の1つのコメントに置く案の数と、コメントの文字の数の上限
use constant PROPOSALS_PER_PAGE => 1000;
use constant COMMENT_MAX => 65536;

# 書き手として認めるリポジトリとの関係の欄の値
my %TRUSTED = map { $_ => 1 } qw(OWNER COLLABORATOR);

my %COMMANDS = (
    reported      => \&cmd_reported,
    'list-read'   => \&cmd_list_read,
    'list-add'    => \&cmd_list_add,
    'list-ensure' => \&cmd_list_ensure,
    publish            => \&cmd_publish,
    'proposals-ensure' => \&cmd_proposals_ensure,
    'proposals-open'   => \&cmd_proposals_open,
    'proposal-remove'  => \&cmd_proposal_remove,
);

my $JSON = JSON::PP->new->utf8->canonical;

# テストが do で読み込んだときは、呼び出しを動かさない
exit main(@ARGV) unless caller;

sub main {
    my ($cmd, @args) = @_;
    my $run = defined $cmd ? $COMMANDS{$cmd} : undef;
    return usage() unless $run;
    return guarded($run, @args);
}

# 呼び出しを動かし、die したら標準エラーに理由を1行で残して 1 を返す
sub guarded {
    my ($run, @args) = @_;
    my $rc = eval { $run->(@args) };
    return $rc if defined $rc;
    (my $why = $@ // '') =~ s/\s+/ /g;
    $why =~ s/ \z//;
    print STDERR "github.pl: $why\n";
    return 1;
}

sub usage {
    print STDERR "usage: perl github.pl reported <N>\n",
        "       perl github.pl list-read\n",
        "       perl github.pl list-add <行の JSON のファイル>\n",
        "       perl github.pl list-ensure <N>\n",
        "       perl github.pl publish <N> --draft <下書きのディレクトリ> --findings <所見のファイル>\n",
        "       perl github.pl proposals-ensure <N>\n",
        "       perl github.pl proposals-open\n",
        "       perl github.pl proposal-remove <案の ID>\n";
    return 64;
}

# 書き手が所有者か共同作業者のものかを、Issue かコメントの応答の関係の欄で確かめる
sub trusted {
    my ($obj) = @_;
    my $assoc = ref $obj eq 'HASH' ? $obj->{author_association} : undef;
    return defined $assoc && !ref $assoc && $TRUSTED{$assoc} ? 1 : 0;
}

# gh を呼び、標準出力をそのまま返す。失敗したら、gh の標準エラーの最後の行を添えて、日本語の1文で die する
sub gh {
    my (@args) = @_;
    my @what = grep { !/\A-/ } @args;
    splice @what, 3 if @what > 3;
    return command("gh @what", 'gh', @args);
}

# コマンドを呼び、標準出力をそのまま返す。失敗したら、「<$what> に失敗した」に
# コマンドの標準エラーの最後の行を添えて die する。コマンドの標準エラーは、そのままは出さない
sub command {
    my ($what, @cmd) = @_;
    my $errf = File::Temp->new;
    open(my $saved, '>&', \*STDERR) or die "標準エラーを控えられなかった($!)\n";
    open(STDERR, '>', $errf->filename) or die "$cmd[0] の標準エラーの置き場所を開けなかった($!)\n";
    my $ph;
    my $started = open($ph, '-|', @cmd);
    my $why = $!;
    my $out;
    if ($started) {
        binmode $ph;
        local $/;
        $out = <$ph>;
        close $ph;
    }
    my $rc = $?;
    open(STDERR, '>&', $saved) or die "標準エラーを戻せなかった($!)\n";
    die "$cmd[0] を起動できなかった($why)\n" unless $started;
    if ($rc) {
        my $last = '';
        if (open my $ef, '<', $errf->filename) {
            while (my $l = <$ef>) { $last = $l if $l =~ /\S/ }
            close $ef;
        }
        $last =~ s/\s+/ /g;
        $last =~ s/\A | \z//g;
        die "$what に失敗した" . (length $last ? "($last)" : '') . "\n";
    }
    return $out // '';
}

# gh api --paginate の出力(ページごとの JSON の配列が区切らずに続く)を、項目の並び1つにする
sub gh_api_list {
    my ($path) = @_;
    my $out = gh('api', '--paginate', $path);
    my $json = JSON::PP->new->utf8;
    my @pages = eval { $json->incr_parse($out) };
    die "gh api $path の出力を JSON として読めなかった\n" if $@;
    my $rest = $json->incr_text;
    die "gh api $path の出力を JSON として読めなかった\n" if defined $rest && $rest =~ /\S/;
    my @items;
    for my $p (@pages) {
        die "gh api $path の出力が配列でなかった\n" unless ref $p eq 'ARRAY';
        push @items, @$p;
    }
    return \@items;
}

# Issue N のコメントのうち、書き手の確認を通るものだけを返す
sub trusted_comments {
    my ($n) = @_;
    return [ grep { trusted($_) } @{ gh_api_list("repos/{owner}/{repo}/issues/$n/comments") } ];
}

# gh api の1つの JSON の応答を読む
sub gh_api_one {
    my ($path) = @_;
    my $out = gh('api', $path);
    my $r = eval { $JSON->decode($out) };
    die "gh api $path の出力を JSON として読めなかった\n" unless defined $r;
    return $r;
}

sub issue_number {
    my ($s) = @_;
    return defined $s && !ref $s && $s =~ /\A[1-9][0-9]{0,9}\z/ ? $s : undef;
}

sub is_true {
    my ($v) = @_;
    return JSON::PP::is_bool($v) && $v ? 1 : 0;
}

# 書き込む呼び出しが最初に呼ぶ。gh のアカウントがリポジトリに書き込めなければ die する
sub require_push {
    my $r = gh_api_one('repos/{owner}/{repo}');
    my $perm = ref $r eq 'HASH' && ref $r->{permissions} eq 'HASH' ? $r->{permissions}{push} : undef;
    die "gh のアカウントがリポジトリに書き込む権限(permissions.push)を持たないので、書かなかった\n" unless is_true($perm);
    return 1;
}

# ---- 手元の記録 ----------------------------------------------------------

my $STATE_DIR;

# 手元の記録の置き場所 <git の共通ディレクトリ>/keirekipro-usage を返す。無ければ作る
sub state_dir {
    return $STATE_DIR if defined $STATE_DIR;
    my $common = command('git の共通ディレクトリを求めること', 'git', 'rev-parse', '--path-format=absolute', '--git-common-dir');
    $common =~ s/\r?\n\z//;
    die "git の共通ディレクトリを求められなかった\n" unless $common =~ /\S/ && $common !~ /\n/;
    my $d = "$common/keirekipro-usage";
    for my $x ($d, "$d/issues") {
        next if -d $x;
        mkdir $x or -d $x or die "$x を作れなかった($!)\n";
    }
    return $STATE_DIR = $d;
}

# JSON のファイルを読む。無いときと、オブジェクトとして読めないときは、空のオブジェクトを返す
sub read_json_file {
    my ($f) = @_;
    open(my $fh, '<:raw', $f) or return {};
    local $/;
    my $s = <$fh>;
    close $fh;
    my $d = eval { $JSON->decode($s // '') };
    return ref $d eq 'HASH' ? $d : {};
}

# JSON のファイルを読み直し、$edit で欄を替え、一時ファイルに書いてから名前を替えて置き換える。
# 読み直してから替えるので、ほかの部品が書いたほかの欄は残る
sub update_json_file {
    my ($f, $edit) = @_;
    my $d = read_json_file($f);
    $edit->($d);
    my $tmp = "$f.tmp.$$";
    open(my $fh, '>:raw', $tmp) or die "$tmp に書けなかった($!)\n";
    my $ok = print $fh $JSON->encode($d), "\n";
    $ok = close($fh) && $ok;
    if (!$ok || !rename($tmp, $f)) {
        my $why = $!;
        unlink $tmp;
        die "$f に書けなかった($why)\n";
    }
    return 1;
}

sub saved_list_issue {
    return issue_number(read_json_file(state_dir() . '/state.json')->{list_issue});
}

sub save_list_issue {
    my ($n) = @_;
    update_json_file(state_dir() . '/state.json', sub { $_[0]{list_issue} = $n + 0 });
}

# issues/<N>.json に、一覧か案の索引に書けなかった印(list_pending か proposals_pending)を書く
sub mark_pending {
    my ($n, $key) = @_;
    update_json_file(state_dir() . "/issues/$n.json", sub { $_[0]{$key} = JSON::PP::true });
}

# ---- 一覧の Issue --------------------------------------------------------

sub is_list_issue {
    my ($i) = @_;
    return 0 unless ref $i eq 'HASH' && !exists $i->{pull_request} && trusted($i) && defined issue_number($i->{number});
    my $t = $i->{title};
    return defined $t && !ref $t && Encode::encode('UTF-8', $t) eq LIST_TITLE ? 1 : 0;
}

# state.json の list_issue が、書き手の確認を通り、ロックしてある Issue を指していれば、その番号を返す
sub checked_saved_list_issue {
    my $n = saved_list_issue();
    return undef unless defined $n;
    my $i = eval { gh_api_one("repos/{owner}/{repo}/issues/$n") };
    return ref $i eq 'HASH' && !exists $i->{pull_request} && trusted($i) && is_true($i->{locked}) ? $n : undef;
}

# すべての Issue から一覧の Issue を探し、ロックしてあるものとしていないものの、最小の番号の Issue を返す
sub scan_list_issues {
    my ($locked, $unlocked);
    for my $i (@{ gh_api_list('repos/{owner}/{repo}/issues?state=all&per_page=100') }) {
        next unless is_list_issue($i);
        if (is_true($i->{locked})) {
            $locked = $i if !$locked || $i->{number} < $locked->{number};
        } else {
            $unlocked = $i if !$unlocked || $i->{number} < $unlocked->{number};
        }
    }
    return ($locked, $unlocked);
}

# 読むだけの呼び出しが使う。ロックしてある一覧の Issue の番号か、無ければ undef を返す。
# 一覧の Issue を作らない。閉じることも、ロックすることもしない
sub list_issue_for_read {
    my $n = checked_saved_list_issue();
    return $n if defined $n;
    my ($locked) = scan_list_issues();
    return undef unless $locked;
    save_list_issue($locked->{number});
    return $locked->{number};
}

# 書き込む呼び出しが使う。一覧の Issue の番号を返す。無ければ作り、閉じ、ロックする。
# ロックしていない一覧の Issue があれば、新しく作らずに、閉じていなければ閉じ、ロックだけをやり直す
sub list_issue_for_write {
    my $n = checked_saved_list_issue();
    return $n if defined $n;
    my ($locked, $unlocked) = scan_list_issues();
    if ($locked) {
        $n = $locked->{number};
    } else {
        my $open = 1;
        if ($unlocked) {
            $n = $unlocked->{number};
            $open = 0 if ($unlocked->{state} // '') eq 'closed';
        } else {
            $n = create_list_issue();
        }
        gh('issue', 'close', $n, '--reason', 'not planned') if $open;
        gh('issue', 'lock', $n);
    }
    save_list_issue($n);
    return $n;
}

sub create_list_issue {
    my $body = File::Temp->new;
    binmode $body;
    print $body LIST_INTRO;
    close $body or die "一覧の Issue の本文を一時ファイルに書けなかった($!)\n";
    my $out = gh('issue', 'create', '--title', LIST_TITLE, '--body-file', $body->filename);
    my ($n) = $out =~ m{/issues/([1-9][0-9]*)\s*\z};
    die "作った一覧の Issue の番号を gh の出力から読めなかった\n" unless defined $n;
    return $n;
}

# 一覧に行を足す呼び出しが使う。一覧の Issue を用意できなければ、行を足す Issue ごとに list_pending を残して die する
sub list_issue_for_rows {
    my (@ns) = @_;
    my $list = eval { list_issue_for_write() };
    return $list if defined $list;
    my $why = $@;
    mark_pending($_, 'list_pending') for @ns;
    die $why;
}

# issues/<N>.json に印があれば消す。ファイルが無いときは作らない
sub clear_pending {
    my ($n, $key) = @_;
    my $f = state_dir() . "/issues/$n.json";
    return unless -e $f && exists read_json_file($f)->{$key};
    update_json_file($f, sub { delete $_[0]{$key} });
}

# ---- 一覧の行 ------------------------------------------------------------
# 一覧の行は、次の欄のハッシュで持つ。list-read はこの形を出し、list-add はこの形を読む。
# issue / url(集計のコメント)/ spec(真偽)/ end_date / work_sec / tokens / usd / impl_spec_back /
# usd_partial(真偽。価格が分からないモデルがあるとき真)。work_sec から impl_spec_back は null(数えられない)を取る

sub group3 {
    my ($s) = @_;
    1 while $s =~ s/\A(\d+)(\d{3})/$1,$2/;
    return $s;
}

sub fmt_time {
    my ($sec) = @_;
    return UNCOUNTABLE unless defined $sec;
    my $m = int($sec / 60 + 0.5);
    my ($h, $mm) = (int($m / 60), $m % 60);
    return $h ? "${h}時間${mm}分" : "${mm}分";
}

sub fmt_tokens {
    my ($n) = @_;
    return defined $n ? group3(sprintf '%d', $n) : UNCOUNTABLE;
}

# 小数2桁に四捨五入する。2進数の小数の誤差で 0.5 セントを切り捨てないよう、わずかに足す
sub fmt_usd {
    my ($usd, $partial) = @_;
    return UNCOUNTABLE unless defined $usd;
    my $cents = int($usd * 100 + 0.5 + 1e-6);
    return sprintf('$%s.%02d', group3(int($cents / 100)), $cents % 100) . ($partial ? USD_PARTIAL : '');
}

sub fmt_count {
    my ($n) = @_;
    return defined $n ? "$n" : UNCOUNTABLE;
}

sub format_row {
    my ($r) = @_;
    return '| ' . join(' | ', "[#$r->{issue}]($r->{url})", ($r->{spec} ? 'あり' : '無し'), $r->{end_date},
        fmt_time($r->{work_sec}), fmt_tokens($r->{tokens}), fmt_usd($r->{usd}, $r->{usd_partial}),
        fmt_count($r->{impl_spec_back})) . ' |';
}

# 一覧の1行(バイトの文字列)を、行のハッシュに戻す。一覧の行の形でなければ undef を返す
sub parse_row {
    my ($line) = @_;
    my $u = UNCOUNTABLE;
    my ($n, $url, $spec, $date, $time, $tok, $usd, $back) = $line =~ m{\A\| \[#([1-9][0-9]*)\]\((\S+)\) \| (あり|無し) \| ([0-9]{4}-[0-9]{2}-[0-9]{2}) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|\s*\z}
        or return undef;
    my %r = (issue => $n + 0, url => $url, spec => $spec eq 'あり' ? JSON::PP::true : JSON::PP::false, end_date => $date,
        usd_partial => JSON::PP::false);
    if ($time eq $u) { $r{work_sec} = undef }
    elsif ($time =~ /\A(?:([1-9][0-9]*)時間)?([0-9]+)分\z/) { $r{work_sec} = (($1 // 0) * 60 + $2) * 60 }
    else { return undef }
    if ($tok eq $u) { $r{tokens} = undef }
    elsif ($tok =~ /\A[0-9]{1,3}(?:,[0-9]{3})*\z/) { ($r{tokens} = $tok) =~ s/,//g; $r{tokens} += 0 }
    else { return undef }
    if ($usd eq $u) { $r{usd} = undef }
    elsif ($usd =~ /\A\$([0-9]{1,3}(?:,[0-9]{3})*)\.([0-9]{2})(\Q${\USD_PARTIAL}\E)?\z/) {
        my ($int, $cent, $partial) = ($1, $2, $3);
        $int =~ s/,//g;
        $r{usd} = "$int.$cent" + 0;
        $r{usd_partial} = JSON::PP::true if $partial;
    } else { return undef }
    if ($back eq $u) { $r{impl_spec_back} = undef }
    elsif ($back =~ /\A(?:0|[1-9][0-9]*)\z/) { $r{impl_spec_back} = $back + 0 }
    else { return undef }
    return eval { check_row(\%r) };
}

sub nonneg {
    my ($v, $int) = @_;
    return 0 unless defined $v && !ref $v && Scalar::Util::looks_like_number($v) && $v >= 0 && $v < 1e15;
    return !$int || $v == int($v) ? 1 : 0;
}

# 行のハッシュを確かめ、欄をそろえた写しを返す。一覧に書くのは、この形の値だけである
sub check_row {
    my ($r) = @_;
    die "一覧の行がオブジェクトでない\n" unless ref $r eq 'HASH';
    my $n = issue_number($r->{issue});
    die "一覧の行の issue が正しくない\n" unless defined $n;
    my $url = $r->{url};
    die "Issue $n の行の url が、その Issue の集計のコメントの URL でない\n"
        unless defined $url && !ref $url && $url =~ m{\Ahttps://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/\Q$n\E#issuecomment-[1-9][0-9]*\z};
    die "Issue $n の行の spec が真偽でない\n" unless JSON::PP::is_bool($r->{spec});
    die "Issue $n の行の end_date が年-月-日でない\n" unless defined $r->{end_date} && !ref $r->{end_date} && $r->{end_date} =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/;
    my %c = (issue => $n + 0, url => $url, spec => $r->{spec} ? JSON::PP::true : JSON::PP::false, end_date => $r->{end_date});
    for my $k (qw(work_sec tokens usd impl_spec_back)) {
        my $v = $r->{$k};
        die "Issue $n の行の $k が正しくない\n" if defined $v && !nonneg($v, $k eq 'tokens' || $k eq 'impl_spec_back');
        $c{$k} = defined $v ? $v + 0 : undef;
    }
    my $p = $r->{usd_partial};
    die "Issue $n の行の usd_partial が真偽でない\n" if defined $p && !JSON::PP::is_bool($p);
    $c{usd_partial} = $p ? JSON::PP::true : JSON::PP::false;
    return \%c;
}

# 集計の JSON(report.json の形)と集計のコメントの URL から、行のハッシュを作る
sub row_from_report {
    my ($d, $url, $n) = @_;
    die "Issue $n の集計の JSON がオブジェクトでない\n" unless ref $d eq 'HASH' && ref $d->{totals} eq 'HASH';
    my $issue = issue_number($d->{issue});
    die "Issue $n の集計の JSON の issue が $n でない\n" unless defined $issue && $issue == $n;
    my $t = $d->{totals};
    my $b = ref $d->{rework} eq 'HASH' ? $d->{rework}{impl_spec_back} : undef;
    my $back;
    if (ref $b eq 'HASH') {
        my @v = map { $b->{$_} } qw(requirements design tasks);
        if (!grep { !nonneg($_, 1) } @v) { $back = 0; $back += $_ for @v }
    }
    my $unknown = $t->{usd_unknown_models};
    return check_row({ issue => $n, url => $url, spec => $d->{spec}, end_date => $d->{end_date},
        work_sec => $t->{work_sec}, tokens => $t->{tokens}, usd => $t->{usd}, impl_spec_back => $back,
        usd_partial => ref $unknown eq 'ARRAY' && @$unknown ? JSON::PP::true : JSON::PP::false });
}

# ---- 一覧の読み書き ------------------------------------------------------

sub bytes_of {
    my ($s) = @_;
    return '' unless defined $s && !ref $s;
    $s = Encode::encode('UTF-8', $s);
    $s =~ s/\r\n/\n/g;
    return $s;
}

# 一覧の Issue の本文と、書き手の確認を通るページのコメントを読む。行は、本文、ページの番号の順、
# 同じ番号ならコメントの古い順に読み、同じ Issue の行が2つあれば先の行を使う
sub read_list {
    my ($list) = @_;
    my $issue = gh_api_one("repos/{owner}/{repo}/issues/$list");
    my %cur = (body => bytes_of(ref $issue eq 'HASH' ? $issue->{body} : undef), pages => []);
    for my $c (@{ trusted_comments($list) }) {
        my $body = bytes_of($c->{body});
        my ($k) = $body =~ /\A\Q${\LIST_PAGE_MARK}\E page=([1-9][0-9]*) -->/ or next;
        next unless $k >= 2 && defined issue_number($c->{id});
        push @{ $cur{pages} }, { k => $k, id => $c->{id}, body => $body };
    }
    @{ $cur{pages} } = sort { $a->{k} <=> $b->{k} || $a->{id} <=> $b->{id} } @{ $cur{pages} };
    my (%seen, @rows);
    for my $text ($cur{body}, map { $_->{body} } @{ $cur{pages} }) {
        for my $line (split /\n/, $text) {
            my $r = parse_row($line) or next;
            push @rows, $r unless $seen{ $r->{issue} }++;
        }
    }
    $cur{rows} = \@rows;
    return \%cur;
}

sub sort_rows {
    return sort { $a->{end_date} cmp $b->{end_date} || $a->{issue} <=> $b->{issue} } @_;
}

sub page_text {
    my ($k, @lines) = @_;
    return LIST_PAGE_MARK . " page=$k -->\n\n### 一覧の続き(${k}ページ目)\n\n" . LIST_HEAD . join('', map { "$_\n" } @lines);
}

sub body_file {
    my ($text) = @_;
    my $f = File::Temp->new;
    binmode $f;
    print $f $text;
    close $f or die "一覧の本文を一時ファイルに書けなかった($!)\n";
    return $f;
}

# 行を並べ、ページに分け、変わった本文とページのコメントだけを書き直し、足りないページのコメントを書く。
# 同じ番号のページのコメントがいくつもあるときは、古いものを使い、ほかのものを行の無いページにする。
# 何かを書いたら真を返す
sub write_list {
    my ($list, $cur, $rows) = @_;
    my @lines = map { format_row($_) } sort_rows(@$rows);
    my @pages;
    push @pages, [ splice @lines, 0, ROWS_PER_PAGE ] while @lines;
    my $wrote = 0;
    my $body = LIST_INTRO . join('', map { "$_\n" } @{ shift(@pages) || [] });
    if ($body ne $cur->{body}) {
        my $f = body_file($body);
        gh('issue', 'edit', $list, '--body-file', $f->filename);
        $wrote = 1;
    }
    my %used;
    for my $c (@{ $cur->{pages} }) {
        my $want = $used{ $c->{k} }++ || $c->{k} - 2 > $#pages ? page_text($c->{k}) : page_text($c->{k}, @{ $pages[ $c->{k} - 2 ] });
        next if $want eq $c->{body};
        my $f = body_file($want);
        gh('api', '-X', 'PATCH', "repos/{owner}/{repo}/issues/comments/$c->{id}", '-F', 'body=@' . $f->filename);
        $wrote = 1;
    }
    for my $i (0 .. $#pages) {
        my $k = $i + 2;
        next if $used{$k};
        my $f = body_file(page_text($k, @{ $pages[$i] }));
        gh('issue', 'comment', $list, '--body-file', $f->filename);
        $wrote = 1;
    }
    return $wrote;
}

# 一覧を読み直す前に待つ秒数。テストだけが環境変数で短くする
sub test_secs {
    my ($name, $default) = @_;
    my $v = $ENV{$name};
    return defined $v && $v =~ /\A[0-9]+(?:\.[0-9]+)?\z/ ? $v : $default;
}

sub list_reread_secs { return test_secs(q(KP_USAGE_TEST_LIST_REREAD), 10) }

sub list_reread_wait {
    my $s = list_reread_secs();
    select(undef, undef, undef, $s) if $s > 0;
}

# 一覧に行を足す。同じ Issue の行は置き換える。書いたら待ってから読み直し、足した行がすべてあれば 1 を返す。
# 無ければ、読み直した一覧に足し直す。LIST_TRIES 回やっても無ければ die する
sub write_rows {
    my ($list, $rows, $cur) = @_;
    my %want = map { format_row($_) => 1 } @$rows;
    for (1 .. LIST_TRIES) {
        $cur ||= read_list($list);
        my %add = map { $_->{issue} => $_ } @$rows;
        my @all = ((grep { !$add{ $_->{issue} } } @{ $cur->{rows} }), values %add);
        return 1 unless write_list($list, $cur, \@all);
        list_reread_wait();
        $cur = read_list($list);
        my %have = map { format_row($_) => 1 } @{ $cur->{rows} };
        return 1 unless grep { !$have{$_} } keys %want;
    }
    die LIST_TRIES . "回書き直しても、一覧に足した行が残らなかった\n";
}

# 行を足す。足せたら行の Issue ごとの list_pending を消し、足せなければ list_pending を残して die する
sub add_rows {
    my ($rows) = @_;
    my %seen;
    my @ns = grep { !$seen{$_}++ } map { $_->{issue} } @$rows;
    my $list = list_issue_for_rows(@ns);
    my $ok = eval { write_rows($list, $rows) };
    if (!$ok) {
        my $why = $@;
        mark_pending($_, 'list_pending') for @ns;
        die $why;
    }
    clear_pending($_, 'list_pending') for @ns;
    return 0;
}

# Issue N の集計のコメント(書き手の確認を通り、1行目がその Issue の印のもの)のうち、最初のものを返す
sub report_comment {
    my ($n) = @_;
    my $head = REPORT_MARK . " issue=$n ";
    for my $c (@{ trusted_comments($n) }) {
        my $body = $c->{body};
        return $c if defined $body && !ref $body && index($body, $head) == 0;
    }
    return undef;
}

sub comment_url {
    my ($c) = @_;
    my $url = $c->{html_url};
    die "集計のコメントの URL が応答に無かった\n" unless defined $url && !ref $url;
    return $url;
}

# Issue N の集計のコメントの最後の数字の行の JSON から、一覧の行を作る
sub report_row {
    my ($n) = @_;
    my $c = report_comment($n) or die "Issue $n に集計のコメントが無いので、一覧の行を作れなかった\n";
    my $mark = DATA_MARK;
    my @data = bytes_of($c->{body}) =~ /^\Q$mark\E (\{.*\}) -->[ \t]*$/mg;
    die "Issue $n の集計のコメントに数字の行が無い\n" unless @data;
    my $d = eval { $JSON->decode($data[-1]) };
    die "Issue $n の集計のコメントの数字の行を JSON として読めなかった\n" unless defined $d;
    return row_from_report($d, comment_url($c), $n);
}

sub cmd_reported {
    my (@args) = @_;
    my $n = @args == 1 ? issue_number($args[0]) : undef;
    return usage() unless defined $n;
    my $c = report_comment($n) or return 3;
    print comment_url($c), "\n";
    return 0;
}

sub cmd_list_read {
    my (@args) = @_;
    return usage() if @args;
    my $list = list_issue_for_read();
    print $JSON->encode(defined $list ? [ sort_rows(@{ read_list($list)->{rows} }) ] : []), "\n";
    return 0;
}

sub cmd_list_add {
    my (@args) = @_;
    return usage() unless @args == 1;
    open(my $fh, '<:raw', $args[0]) or die "$args[0] を読めなかった($!)\n";
    my $text = do { local $/; <$fh> };
    close $fh;
    my $in = eval { $JSON->decode($text // '') };
    die "$args[0] が、行の JSON の配列でない\n" unless ref $in eq 'ARRAY' && @$in;
    my $rows = [ map { check_row($_) } @$in ];
    require_push();
    return add_rows($rows);
}

sub cmd_list_ensure {
    my (@args) = @_;
    my $n = @args == 1 ? issue_number($args[0]) : undef;
    return usage() unless defined $n;
    require_push();
    my $list = list_issue_for_rows($n);
    my $ok = eval {
        my $cur = read_list($list);
        (grep { $_->{issue} == $n } @{ $cur->{rows} }) ? 1 : write_rows($list, [ report_row($n) ], $cur);
    };
    if (!$ok) {
        my $why = $@;
        mark_pending($n, 'list_pending');
        die $why;
    }
    clear_pending($n, 'list_pending');
    return 0;
}

# ---- 集計のコメントの形の確かめ -------------------------------------------
# github.pl は、集計のコメントに、design の「データの形」の節の形の値だけを置く。形に無い値があれば、何も書かずに die する

# 段階ごとの表の段階の名前
sub stage_names {
    return ('着手の判断', '要件', '要件の審査', '設計', '設計の審査', 'タスク', 'タスクの審査', '実装',
        '実装中の spec の直し', '出荷とレビュー対応', 'その他', '合計');
}

# 全体の合計の表の5行の項目の名前と、値の形の名前
sub total_items {
    return (['AIの作業時間', 'time'], ['トークン数', 'num'], ['使用料', 'usd'],
        ['使う量の上限で止まった回数', 'count'], ['使う量の上限で止まっていた時間', 'time']);
}

# 往復と手戻りの表の項目の名前
sub rework_items {
    return ('spec の審査役との往復', '承認の前に、所有者が spec の直しを求めた', 'spec を作る途中で、前の段階に戻って直した',
        '実装の途中で、spec に戻って直した', '実装したコードに、タスクごとの確認役が問題を見つけ、コードを直した',
        'PR の Codex レビューとの往復', 'PR を出したあと、CI の自動チェックが失敗し、コードを直した',
        '同じ失敗を3回続けて直せず、AI が作業を止めて所有者に報告した', '実装の途中で、Issue を分けた',
        'spec 無しで始め、実装の途中で spec に切り替えた', '200行の検査で PR が止まった',
        '自動レビューが、Issue の決めた方式から外れたとして PR を止めた');
}

# 注記の文。<MODELS> はモデルの ID を「、」で区切ったもの、<N> は回数に替わる
sub note_texts {
    return (
        'この Issue は、仕組みが入る前に着手した。「数えられない」と書いた項目は、数えるための印を作業の途中で残す仕組みが、着手のときにまだ無かった項目である。',
        '会話の記録の一部を読めなかった。Claude は、この Issue の作業の一部を、仕組みが入る前の設定で始めた会話で行った。「数えられない」と書いた項目は、その会話では、数えるための印が残らなかった項目である。',
        '会話の記録の一部を読めなかった。仕組みは、この集計を、読めた分だけで数えた。そのため、作業時間とトークン数と使用料は、実際より少ないことがある。往復と手戻りの表の「数えられない」の項目は、読めなかった会話から数える項目である。',
        '<MODELS>の公表価格が分からないため、仕組みは、このモデルの使用料を数えていない。全体の合計と段階ごとの表の使用料は、このモデルの分を除いた額である。',
        '会話が再開したきっかけのうち、仕組みが種類を見分けられなかったものが <N>回あった。仕組みは、見分けられなかったきっかけの前の時間を、外の仕組みを待っていた時間として、作業時間と待ち時間に数えた。そのため、作業時間と待ち時間は、実際より長いことがある。',
    );
}

# データのファイルの roles の役割の名前
sub config_roles {
    my $f = File::Basename::dirname(__FILE__) . '/usage-config.json';
    my $roles = read_json_file($f)->{roles};
    die "$f の roles を読めなかった\n" unless ref $roles eq 'HASH';
    my @v = map { ref $_ eq 'HASH' ? values %$_ : $_ } values %$roles;
    return map { bytes_of($_) } grep { defined && !ref } @v;
}

# モデルの ID の形。report.pl が、モデルの分からない応答に付ける「不明」も受ける。
# 会話の記録のモデルの ID には、`:` を含むもの(Bedrock の ID の末尾の版など)がある
sub model_id_re { return '(?:不明|[A-Za-z0-9][A-Za-z0-9._:\[\]-]{0,99})' }

sub is_model_id {
    my ($s) = @_;
    my $re = model_id_re();
    return defined $s && !ref $s && $s =~ /\A$re\z/ ? 1 : 0;
}

# モデルごとの表の役割の名前。本体の会話、別に起こしたセッション、データのファイルの役割の名前、補助役の種類の名前(agent_type)、
# report.pl が agent_type の無い補助役に付ける「補助役」のどれかである。agent_type の字は extract.pl が残す字と同じにする
sub is_role {
    my ($s) = @_;
    return 0 unless defined $s && !ref $s;
    return 1 if $s =~ /\A[A-Za-z0-9_.:\[\]-]{1,64}\z/;
    return scalar grep { $_ eq $s } ('本体の会話', '別に起こしたセッション', '補助役', config_roles());
}

sub in_set {
    my ($s, @set) = @_;
    return 0 unless defined $s && !ref $s;
    return scalar grep { $_ eq $s } @set;
}

# 値 $v が形 $s に合うかを返す。形は、値を確かめる関数か、要素の形を1つ持つ配列か、欄ごとの形を持つハッシュである。
# ハッシュの形は、欄の過不足を許さない
sub fits {
    my ($v, $s) = @_;
    return $s->($v) ? 1 : 0 if ref $s eq 'CODE';
    if (ref $s eq 'ARRAY') {
        return 0 unless ref $v eq 'ARRAY';
        return (grep { !fits($_, $s->[0]) } @$v) ? 0 : 1;
    }
    return 0 unless ref $v eq 'HASH' && keys %$v == keys %$s;
    for my $k (keys %$s) {
        return 0 unless exists $v->{$k} && fits($v->{$k}, $s->{$k});
    }
    return 1;
}

# report.json の形。数えられない値は null を取る
sub report_schema {
    my ($n) = @_;
    my $int = sub { nonneg($_[0], 1) };
    my $num = sub { nonneg($_[0], 0) };
    my $int0 = sub { !defined $_[0] || nonneg($_[0], 1) };
    my $num0 = sub { !defined $_[0] || nonneg($_[0], 0) };
    my $bool = sub { JSON::PP::is_bool($_[0]) };
    my $bool0 = sub { !defined $_[0] || JSON::PP::is_bool($_[0]) };
    my $date = sub { defined $_[0] && !ref $_[0] && $_[0] =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/ };
    my $spec_stage = sub { in_set(bytes_of($_[0]), qw(requirements design tasks)) };
    my $tri = { requirements => $int, design => $int, tasks => $int };
    my $tri0 = sub { !defined $_[0] || fits($_[0], $tri) };
    my $back = [ { from => $spec_stage, to => $spec_stage } ];
    # 往復と手戻りの行。数えられない行の名前は、この行の名前のどれかである
    my $rework = { spec_review_rounds => $tri0, owner_fix => $tri0, spec_back => sub { !defined $_[0] || fits($_[0], $back) },
        impl_spec_back => $tri0, task_rejected => $int0, codex_rounds => $int0, ci_fix => $int0, same_failure => $int0,
        split => $bool0, switch_to_spec => $int0, size_check_stops => $int0, decided_method_stops => $int0 };
    return {
        v => sub { nonneg($_[0], 1) && $_[0] == 1 },
        issue => sub { nonneg($_[0], 1) && $_[0] == $n },
        prs => [ sub { defined issue_number($_[0]) } ],
        spec => $bool,
        start_date => $date,
        end_date => $date,
        totals => { work_sec => $num0, wait_sec => $num0, concurrent_sec => $num0, tokens => $int0, usd => $num0,
            usd_unknown_models => [ sub { is_model_id(bytes_of($_[0])) } ], limit_count => $int0, limit_sec => $num0 },
        stages => [ { name => sub { in_set(bytes_of($_[0]), stage_names()) }, work_sec => $num0, wait_sec => $num0,
            concurrent_sec => $num0, tokens => $int0, usd => $num0 } ],
        models => [ { model => sub { is_model_id(bytes_of($_[0])) }, role => sub { is_role(bytes_of($_[0])) }, in => $int0, cw => $int0, cr => $int0, out => $int0, usd => $num0 } ],
        rework => $rework,
        uncountable => [ sub { exists $rework->{ bytes_of($_[0]) } } ],
        partial_records => $bool,
        unknown_turns => $int,
        prices => { source => sub { defined $_[0] && !ref $_[0] && $_[0] =~ m{\Ahttps://[A-Za-z0-9.-]+(?:/[A-Za-z0-9._~/-]*)?\z} },
            checked_on => $date },
    };
}

# ファイルをバイトのまま読み、行の終わりを \n にそろえ、最後の改行を除いて返す
sub read_text {
    my ($f) = @_;
    open(my $fh, '<:raw', $f) or die "$f を読めなかった($!)\n";
    my $s = do { local $/; <$fh> } // '';
    close $fh;
    $s =~ s/\r\n/\n/g;
    $s =~ s/\n+\z//;
    return $s;
}

sub read_report_json {
    my ($f, $n) = @_;
    my $d = eval { $JSON->decode(read_text($f)) };
    die "$f を JSON として読めなかった\n" unless defined $d;
    die "$f に、集計の JSON の形に無い値がある\n" unless fits($d, report_schema($n));
    return $d;
}

# 表の1行のマスを返す。表の行の形でなければ空の並びを返す
sub cells {
    my ($line) = @_;
    return () unless $line =~ /\A\| (.*) \|\z/;
    return split / \| /, $1, -1;
}

# report.md の形を確かめる。形に無い行があれば die する
sub check_report_md {
    my ($md, $n) = @_;
    my $u = UNCOUNTABLE;
    my $p = USD_PARTIAL;
    my $date = qr/[0-9]{4}-[0-9]{2}-[0-9]{2}/;
    my $count = qr/(?:0|[1-9][0-9]*)/;
    my %v = (
        time => qr/\A(?:(?:[1-9][0-9]*時間)?(?:[0-9]|[1-5][0-9])分|\Q$u\E)\z/,
        num => qr/\A(?:(?:0|[1-9][0-9]{0,2}(?:,[0-9]{3})*)|\Q$u\E)\z/,
        usd => qr/\A(?:\$(?:0|[1-9][0-9]{0,2}(?:,[0-9]{3})*)\.[0-9]{2}(?:\Q$p\E)?|\Q$u\E)\z/,
        count => qr/\A(?:$count|\Q$u\E)\z/,
    );
    my $stg = qr/(?:要件|設計|タスク)/;
    my $rework = qr/\A(?:$count|要件 $count、設計 $count、タスク $count|[1-9][0-9]*\(${stg}から${stg}へ [1-9][0-9]*(?:、${stg}から${stg}へ [1-9][0-9]*)*\)|有|無し|\Q$u\E)\z/;
    my @b = split /\n\n/, $md, -1;
    my $bad = sub { die "report.md の$_[0]が、集計のコメントの形でない\n" };
    my $table = sub {
        my ($block, $head, $what) = @_;
        my @l = split /\n/, $block, -1;
        $bad->($what) unless @l >= 2 && $l[0] eq $head && $l[1] eq '|' . ('---|' x (() = $head =~ / \|/g));
        return @l[ 2 .. $#l ];
    };
    $bad->('見出し') unless @b >= 12 && $b[0] eq '## AIの作業の集計';
    my @r = $table->($b[1], '| 開始日 | 終了日 | spec | PR |', '最初の表');
    $bad->('最初の表') unless @r == 1 && $r[0] =~ /\A\| $date \| $date \| (?:あり|無し) \| #[1-9][0-9]*(?:、#[1-9][0-9]*)* \|\z/;
    $bad->('全体の合計の見出し') unless $b[2] eq '### 全体の合計';
    @r = $table->($b[3], '| 項目 | 値 |', '全体の合計の表');
    my @t = total_items();
    $bad->('全体の合計の表') unless @r == @t;
    for my $i (0 .. $#t) {
        my @c = cells($r[$i]);
        $bad->('全体の合計の表') unless @c == 2 && $c[0] eq $t[$i][0] && $c[1] =~ $v{ $t[$i][1] };
    }
    $bad->('段階ごとの見出し') unless $b[4] eq '### 段階ごと';
    for my $line ($table->($b[5], '| 段階 | AIの作業時間 | そのうち待ち時間 | 審査役などが同時に動いた時間 | トークン数 | 使用料 |', '段階ごとの表')) {
        my @c = cells($line);
        $bad->('段階ごとの表') unless @c == 6 && in_set($c[0], stage_names()) && $c[1] =~ $v{time} && $c[2] =~ $v{time}
            && $c[3] =~ $v{time} && $c[4] =~ $v{num} && $c[5] =~ $v{usd};
    }
    $bad->('モデルごとの見出し') unless $b[6] eq '### モデルごと';
    for my $line ($table->($b[7], '| モデル | 役割 | 入力 | キャッシュの書き込み | キャッシュの読み込み | 出力 | 使用料 |', 'モデルごとの表')) {
        my @c = cells($line);
        $bad->('モデルごとの表') unless @c == 7 && is_model_id($c[0]) && is_role($c[1])
            && !grep({ $_ !~ $v{num} } @c[ 2 .. 5 ]) && ($c[6] =~ $v{usd} || $c[6] eq '価格が分からない');
    }
    $bad->('往復と手戻りの見出し') unless $b[8] eq '### 往復と手戻り';
    for my $line ($table->($b[9], '| 項目 | 回数 |', '往復と手戻りの表')) {
        my @c = cells($line);
        $bad->('往復と手戻りの表') unless @c == 2 && in_set($c[0], rework_items()) && $c[1] =~ $rework;
    }
    $bad->('価格の見出し') unless $b[10] eq '### 価格';
    $bad->('価格の文') unless $b[11] =~ m{\A使用料は、https://[A-Za-z0-9.-]+(?:/[A-Za-z0-9._~/-]*)? の公表価格で換算した。価格を確かめた日は $date である。\z};
    return 1 if @b == 12;
    $bad->('注記') unless @b == 14 && $b[12] eq '### 注記';
    my @notes = map {
        my $re = quotemeta $_;
        my $id = model_id_re();
        $re =~ s/\\<MODELS\\>/$id(?:、$id)*/;
        $re =~ s/\\<N\\>/[1-9][0-9]*/;
        qr/\A- $re\z/;
    } note_texts();
    for my $line (split /\n/, $b[13], -1) {
        $bad->('注記') unless grep { $line =~ $_ } @notes;
    }
    return 1;
}

# 所見のファイルの形を確かめ、直す案の ID を返す。所見は、箇条の行と、1つの「### 直す案」の見出しと、
# その下の「- [<N>-<連番>] <案の文>」の行と、空の行だけからなる。HTML のコメントの印を含む行は書かない
sub check_findings {
    my ($text, $n) = @_;
    my ($props, $bullets, @ids) = (0, 0);
    for my $line (split /\n/, $text) {
        next if $line eq '';
        die "所見のファイルに、HTML のコメントの印がある\n" if $line =~ /<!--|-->/;
        if ($line eq '### 直す案') {
            die "所見のファイルに、直す案の見出しが2つある\n" if $props++;
            next;
        }
        if ($props) {
            my ($i, $k) = $line =~ /\A- \[([1-9][0-9]*)-([1-9][0-9]*)\] \S/
                or die "所見のファイルの直す案の行が、「- [<Issue の番号>-<連番>] <案の文>」の形でない\n";
            die "所見のファイルの直す案の ID が、$n-1 から順に振られていない\n" unless $i == $n && $k == @ids + 1;
            push @ids, "$n-$k";
        } else {
            die "所見のファイルに、箇条でない行がある\n" unless $line =~ /\A- \S/;
            $bullets++;
        }
    }
    die "所見のファイルに、目立つ点の箇条が無い\n" unless $bullets;
    die "所見のファイルの直す案の見出しの下に、案が無い\n" if $props && !@ids;
    return @ids;
}

# ---- 案の索引 ------------------------------------------------------------

# 案の ID を Issue の番号と連番に分ける。ID の形でなければ空の並びを返す
sub proposal_id {
    my ($s) = @_;
    return defined $s && !ref $s && $s =~ /\A([1-9][0-9]{0,9})-([1-9][0-9]{0,5})\z/ ? ($1, $2) : ();
}

sub sort_ids {
    my %seen;
    return map { $_->[2] } sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }
        map { [ proposal_id($_), $_ ] } grep { !$seen{$_}++ } @_;
}

sub proposals_text {
    my ($k, @ids) = @_;
    my $json = $JSON->encode([ map { { id => $_, issue => (proposal_id($_))[0] + 0 } } @ids ]);
    return PROPOSALS_MARK . " page=$k $json -->\n" . PROPOSALS_NOTE;
}

# 一覧の Issue の、書き手の確認を通る案の索引のコメントを読む。案は、ページの番号の順、同じ番号ならコメントの古い順に読む。
# ID の形でない案と、ID の頭と issue が合わない案は読まない
sub read_index {
    my ($list) = @_;
    my @pages;
    for my $c (@{ trusted_comments($list) }) {
        my $body = bytes_of($c->{body});
        my ($k, $json) = $body =~ /\A\Q${\PROPOSALS_MARK}\E page=([1-9][0-9]*) (\[[^\n]*\]) -->(?:\n|\z)/ or next;
        next unless defined issue_number($c->{id});
        my $arr = eval { $JSON->decode($json) };
        push @pages, { k => $k, id => $c->{id}, body => $body, entries => ref $arr eq 'ARRAY' ? $arr : [] };
    }
    @pages = sort { $a->{k} <=> $b->{k} || $a->{id} <=> $b->{id} } @pages;
    my @ids;
    for my $e (map { @{ $_->{entries} } } @pages) {
        next unless ref $e eq 'HASH';
        my ($i) = proposal_id($e->{id});
        push @ids, $e->{id} if defined $i && nonneg($e->{issue}, 1) && $e->{issue} == $i;
    }
    return { pages => \@pages, ids => [ sort_ids(@ids) ] };
}

# 案を Issue の番号と連番の順に並べ、1,000件ごとのページに分け、変わったページのコメントだけを書き直し、
# 足りないページのコメントを書く。案が無くなったページと、同じ番号の2つ目のページは、[] にして残す。何かを書いたら真を返す
sub write_index {
    my ($list, $cur, $ids) = @_;
    my @rest = sort_ids(@$ids);
    my @pages;
    push @pages, [ splice @rest, 0, PROPOSALS_PER_PAGE ] while @rest;
    my ($wrote, %used) = (0);
    for my $c (@{ $cur->{pages} }) {
        my $want = $used{ $c->{k} }++ || $c->{k} - 1 > $#pages ? proposals_text($c->{k}) : proposals_text($c->{k}, @{ $pages[ $c->{k} - 1 ] });
        next if $want eq $c->{body};
        my $f = body_file($want);
        gh('api', '-X', 'PATCH', "repos/{owner}/{repo}/issues/comments/$c->{id}", '-F', 'body=@' . $f->filename);
        $wrote = 1;
    }
    for my $i (0 .. $#pages) {
        next if $used{ $i + 1 };
        my $f = body_file(proposals_text($i + 1, @{ $pages[$i] }));
        gh('issue', 'comment', $list, '--body-file', $f->filename);
        $wrote = 1;
    }
    return $wrote;
}

# 案の索引に案を足し、案を外す。書いたら待ってから読み直し、足した案がすべてあり、外した案が無ければ 1 を返す。
# そうでなければ、読み直した索引に足し直す。LIST_TRIES 回やってもそうならなければ die する
sub write_proposals {
    my ($list, $add, $remove) = @_;
    my %rm = map { $_ => 1 } @$remove;
    my $cur;
    for (1 .. LIST_TRIES) {
        $cur ||= read_index($list);
        return 1 unless write_index($list, $cur, [ grep { !$rm{$_} } @{ $cur->{ids} }, @$add ]);
        list_reread_wait();
        $cur = read_index($list);
        my %have = map { $_ => 1 } @{ $cur->{ids} };
        return 1 unless (grep { !$have{$_} } @$add) || (grep { $have{$_} } @$remove);
    }
    die LIST_TRIES . "回書き直しても、案の索引が書いたとおりにならなかった\n";
}

# 案を索引に足す。足せたら proposals_pending を消し、足せなければ proposals_pending を残して die する
sub add_proposals {
    my ($n, @ids) = @_;
    write_proposals(list_issue_for_write(), \@ids, []);
    clear_pending($n, 'proposals_pending');
    return 1;
}

# Issue N の集計のコメントの所見の直す案の文を、ID ごとに返す
sub proposal_texts {
    my ($n) = @_;
    my $c = report_comment($n) or return {};
    my ($in, %t) = (0);
    for my $line (split /\n/, bytes_of($c->{body})) {
        if ($line =~ /\A### /) { $in = $line eq '### 直す案'; next }
        next unless $in;
        my ($id, $text) = $line =~ /\A- \[([1-9][0-9]*-[1-9][0-9]*)\] (\S.*)\z/ or next;
        $t{$id} //= Encode::decode('UTF-8', $text);
    }
    return \%t;
}

sub cmd_publish {
    my (@args) = @_;
    my $n = issue_number(shift @args);
    my %o;
    while (@args >= 2 && $args[0] =~ /\A--(draft|findings)\z/ && !exists $o{$1}) {
        shift @args;
        $o{$1} = shift @args;
    }
    return usage() unless defined $n && !@args && exists $o{draft} && exists $o{findings};
    my $d = read_report_json("$o{draft}/report.json", $n);
    my $md = read_text("$o{draft}/report.md");
    my $findings = read_text($o{findings});
    check_report_md($md, $n);
    my @ids = check_findings($findings, $n);
    my $body = REPORT_MARK . " issue=$n -->\n\n$md\n\n### 所見\n\n$findings\n\n" . DATA_MARK . ' ' . $JSON->encode($d) . " -->\n";
    die "集計のコメントが " . COMMENT_MAX . " 文字を超える\n" if length(Encode::decode('UTF-8', $body)) > COMMENT_MAX;
    require_push();
    # 前に書けなかった集計の案が残っていても、いまの所見の案だけにする
    if (@ids) { update_json_file(state_dir() . "/issues/$n.json", sub { $_[0]{proposals_pending} = [@ids] }) }
    else { clear_pending($n, 'proposals_pending') }
    my $f = body_file($body);
    my $out = gh('issue', 'comment', $n, '--body-file', $f->filename);
    my ($url) = $out =~ m{(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/\Q$n\E#issuecomment-[1-9][0-9]*)};
    $url //= eval { comment_url(report_comment($n) // die "\n") };
    my @failed;
    push @failed, 'proposals' if @ids && !eval { add_proposals($n, @ids) };
    if (!defined $url || !eval { add_rows([ row_from_report($d, $url, $n) ]); 1 }) {
        mark_pending($n, 'list_pending');
        push @failed, 'list';
    }
    print $JSON->encode({ url => $url, proposals => \@ids, failed => \@failed }), "\n";
    return 0;
}

sub cmd_proposals_ensure {
    my (@args) = @_;
    my $n = @args == 1 ? issue_number($args[0]) : undef;
    return usage() unless defined $n;
    require_push();
    my $p = read_json_file(state_dir() . "/issues/$n.json")->{proposals_pending};
    my @ids = grep { my ($i) = proposal_id($_); defined $i && $i == $n } ref $p eq 'ARRAY' ? @$p : ();
    if (!@ids) {
        clear_pending($n, 'proposals_pending');
        return 0;
    }
    add_proposals($n, @ids);
    return 0;
}

sub cmd_proposals_open {
    my (@args) = @_;
    return usage() if @args;
    my $list = list_issue_for_read();
    my (@out, %texts);
    for my $id (defined $list ? @{ read_index($list)->{ids} } : ()) {
        my ($i) = proposal_id($id);
        $texts{$i} //= proposal_texts($i);
        push @out, { id => $id, issue => $i + 0, text => $texts{$i}{$id} };
    }
    print $JSON->encode(\@out), "\n";
    return 0;
}

sub cmd_proposal_remove {
    my (@args) = @_;
    my ($n) = @args == 1 ? proposal_id($args[0]) : ();
    return usage() unless defined $n;
    my $id = $args[0];
    require_push();
    my $f = state_dir() . "/issues/$n.json";
    if (-e $f && ref read_json_file($f)->{proposals_pending} eq 'ARRAY') {
        update_json_file($f, sub {
            my @rest = grep { $_ ne $id } @{ $_[0]{proposals_pending} };
            if (@rest) { $_[0]{proposals_pending} = \@rest } else { delete $_[0]{proposals_pending} }
        });
    }
    my $list = list_issue_for_read();
    write_proposals($list, [], [$id]) if defined $list;
    return 0;
}
