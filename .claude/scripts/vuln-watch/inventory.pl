# このリポジトリの部品の一覧を作るモジュール
#
# main のファイルを git show <commit>:<path> で読み、部品の鍵と版の一覧を返す。作業フォルダのファイルは読まない。
# どの作業フォルダでスキルを打っても、同じ一覧を使うためである。
#
# 呼び出し方: inventory_read($repo_root) は次の形を返す
#   {commit => <sha>, ref => "origin/main" か "HEAD", fetched => <真偽>,
#    components => {<鍵> => {versions => [...], files => [...], partial => <真偽>}}}
# 初めに git fetch origin main を動かし、20秒で打ち切る。origin/main があればそれを読み、無ければ HEAD を読む。
# ファイルが無いか読めないときは、そのファイルの部品を一覧に入れずに続ける。
use strict;
use warnings;
use utf8;
use JSON::PP ();
use File::Spec ();
use POSIX qw(WNOHANG);

my $INVENTORY_FETCH_TIMEOUT = 20; # git fetch origin main を打ち切る秒数

sub inventory_read {
    my ($repo_root) = @_;
    my $fetched = _inventory_run_limited($INVENTORY_FETCH_TIMEOUT, 'git', '-C', $repo_root, 'fetch', '--quiet', 'origin', 'main') == 0;
    my $ref = 'origin/main';
    my $commit = _inventory_git($repo_root, 'rev-parse', '--verify', '--quiet', 'origin/main^{commit}');
    if (!defined $commit) {
        $ref = 'HEAD';
        $commit = _inventory_git($repo_root, 'rev-parse', '--verify', '--quiet', 'HEAD^{commit}');
    }
    my %components;
    my $inv = { commit => undef, ref => $ref, fetched => $fetched ? JSON::PP::true : JSON::PP::false, components => \%components };
    return $inv unless defined $commit;
    ($inv->{commit}) = $commit =~ /\A([0-9a-f]+)/;
    return $inv unless defined $inv->{commit};

    my $show = sub { _inventory_show($repo_root, $inv->{commit}, $_[0]) };
    my $add = sub { _inventory_add(\%components, @_) };
    _inventory_pnpm_lock($show, $add);
    _inventory_package_json($show, $add);
    _inventory_libs_versions($show, $add);
    _inventory_gradle_wrapper($show, $add);
    _inventory_build_gradle($show, $add);

    for my $c (values %components) {
        $c->{partial} = $c->{partial} ? JSON::PP::true : JSON::PP::false;
    }
    return $inv;
}

# 部品の一覧に、鍵と版と読んだファイルを足す。同じ版と同じファイルは1回だけ持つ
sub _inventory_add {
    my ($components, $key, $version, $file, $partial) = @_;
    my $c = $components->{$key} //= { versions => [], files => [], partial => 0 };
    push @{ $c->{versions} }, $version unless grep { $_ eq $version } @{ $c->{versions} };
    push @{ $c->{files} }, $file unless grep { $_ eq $file } @{ $c->{files} };
    $c->{partial} = 1 if $partial;
}

# frontend/pnpm-lock.yaml の packages: の下のキー。'<名前>@<版>': と <名前>@<版>: を読み、版のあとの ( 以降の付記を除く
sub _inventory_pnpm_lock {
    my ($show, $add) = @_;
    my $file = 'frontend/pnpm-lock.yaml';
    my $text = $show->($file) // return;
    my $in = 0;
    for my $line (split /\r?\n/, $text) {
        if ($line =~ /\A([^\s#][^:]*):/) {
            $in = $1 eq 'packages';
            next;
        }
        next unless $in;
        next unless $line =~ /\A  (?:'([^']+)'|([^\s'#][^\s]*?)):\s*\z/;
        my $k = $1 // $2;
        $k =~ s/\(.*\z//s;
        my ($name, $version) = $k =~ /\A(.+?)\@([^\@]+)\z/ or next;
        $add->("npm:$name", $version, $file, 0);
    }
}

# frontend/package.json の packageManager の pnpm@<版>
sub _inventory_package_json {
    my ($show, $add) = @_;
    my $file = 'frontend/package.json';
    my $text = $show->($file) // return;
    my $json = eval { JSON::PP->new->decode($text) };
    return unless ref $json eq 'HASH' && defined $json->{packageManager} && !ref $json->{packageManager};
    my ($version) = $json->{packageManager} =~ /\Apnpm\@([^+\s]+)/ or return;
    $add->('npm:pnpm', $version, $file, 0);
}

# backend/gradle/libs.versions.toml の [libraries] と [plugins]。module か id と、version.ref か version を読む
sub _inventory_libs_versions {
    my ($show, $add) = @_;
    my $file = 'backend/gradle/libs.versions.toml';
    my $text = $show->($file) // return;
    my ($section, %versions, @entries) = ('');
    for my $line (split /\r?\n/, $text) {
        next if $line =~ /\A\s*(?:#|\z)/;
        if ($line =~ /\A\s*\[([^\]]+)\]/) {
            $section = $1;
            next;
        }
        if ($section eq 'versions') {
            $versions{$1} = $2 if $line =~ /\A\s*([\w.-]+)\s*=\s*"([^"]*)"/;
        } elsif ($section eq 'libraries' || $section eq 'plugins') {
            my ($body) = $line =~ /\A\s*[\w.-]+\s*=\s*\{(.*)\}/ or next;
            push @entries, [ $section, $body ];
        }
    }
    for my $e (@entries) {
        my ($section, $body) = @$e;
        my ($name) = $section eq 'libraries' ? $body =~ /\bmodule\s*=\s*"([^"]+)"/ : $body =~ /\bid\s*=\s*"([^"]+)"/;
        next unless defined $name;
        my $version;
        if ($body =~ /\bversion\.ref\s*=\s*"([^"]+)"/) {
            $version = $versions{$1};
        } elsif ($body =~ /\bversion\s*=\s*"([^"]+)"/) {
            $version = $1;
        }
        next unless defined $version && length $version;
        $add->(($section eq 'libraries' ? 'maven:' : 'gradle-plugin:') . $name, $version, $file, 0);
    }
}

# backend/gradle/wrapper/gradle-wrapper.properties の distributionUrl の gradle-<版>-
sub _inventory_gradle_wrapper {
    my ($show, $add) = @_;
    my $file = 'backend/gradle/wrapper/gradle-wrapper.properties';
    my $text = $show->($file) // return;
    my ($version) = $text =~ /^distributionUrl=[^\n]*?gradle-(\d[^\/\s]*?)-(?:bin|all)\.zip/m or return;
    $add->('tool:gradle', $version, $file, 0);
}

# backend/build.gradle の JavaLanguageVersion.of(<版>)。主の版の番号だけなので、一部だけの版になる
sub _inventory_build_gradle {
    my ($show, $add) = @_;
    my $file = 'backend/build.gradle';
    my $text = $show->($file) // return;
    my ($version) = $text =~ /JavaLanguageVersion\.of\(\s*(\d+)\s*\)/ or return;
    $add->('runtime:java', $version, $file, 1);
}

# git show <commit>:<path> の中身を文字列で返す。ファイルが無いか、UTF-8 として読めないときは undef を返す
sub _inventory_show {
    my ($repo_root, $commit, $path) = @_;
    my $raw = _inventory_git($repo_root, 'show', "$commit:$path");
    return undef unless defined $raw && utf8::decode($raw);
    return $raw;
}

# git -C <repo_root> <引数...> を動かし、標準出力を返す。失敗したときは undef を返す。標準エラーは捨てる
sub _inventory_git {
    my ($repo_root, @args) = @_;
    my $pid = open(my $fh, '-|');
    return undef unless defined $pid;
    if (!$pid) {
        open STDERR, '>', File::Spec->devnull;
        exec('git', '-C', $repo_root, @args) or POSIX::_exit(127);
    }
    binmode $fh;
    my $out = do { local $/; <$fh> };
    close $fh;
    return $? == 0 ? ($out // '') : undef;
}

# コマンドを動かし、決めた秒数で打ち切る。終了コードを返し、打ち切ったときと動かせなかったときは -1 を返す。
# 標準入力と標準出力と標準エラーは捨て、git が認証を尋ねて止まらないようにする
sub _inventory_run_limited {
    my ($seconds, @cmd) = @_;
    my $pid = fork;
    return -1 unless defined $pid;
    if (!$pid) {
        my $null = File::Spec->devnull;
        open STDIN, '<', $null;
        open STDOUT, '>', $null;
        open STDERR, '>', $null;
        $ENV{GIT_TERMINAL_PROMPT} = '0';
        exec(@cmd) or POSIX::_exit(127);
    }
    my $deadline = time + $seconds;
    while (time < $deadline) {
        return $? >> 8 if waitpid($pid, WNOHANG) == $pid;
        select(undef, undef, undef, 0.1);
    }
    kill 'TERM', $pid;
    for (1 .. 20) {
        return -1 if waitpid($pid, WNOHANG) == $pid;
        select(undef, undef, undef, 0.1);
    }
    kill 'KILL', $pid;
    waitpid($pid, 0);
    return -1;
}

1;
