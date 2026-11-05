# このリポジトリの部品の一覧を作るモジュール
#
# main のファイルを git show <commit>:<path> で読み、部品の鍵と版の一覧を返す。作業フォルダのファイルは読まない。
# どの作業フォルダでスキルを打っても、同じ一覧を使うためである。
#
# 呼び出し方: inventory_read($repo_root) は次の形を返す
#   {commit => <sha>, ref => "origin/main" か "HEAD", fetched => <真偽>,
#    components => {<鍵> => {versions => [...], files => [...], partial => <真偽>}}, sbom_ok => <真偽>}
# 初めに git fetch origin main を動かし、20秒で打ち切る。origin/main があればそれを読み、無ければ HEAD を読む。
# ファイルが無いか読めないときは、そのファイルの部品を一覧に入れずに続ける。
# 版が分からない部品は、versions を空の一覧にする。
# 最後に gh で GitHub の依存の一覧を20秒で打ち切って1回読み、pkg:maven/ の部品を足す。読めたかを sbom_ok に残す。
use strict;
use warnings;
use utf8;
use JSON::PP ();
use File::Spec ();
use POSIX qw(WNOHANG);

my $INVENTORY_FETCH_TIMEOUT = 20; # git fetch origin main を打ち切る秒数
my $INVENTORY_SBOM_TIMEOUT = 20;  # gh api の依存の一覧の呼び出しを打ち切る秒数
my $INVENTORY_SBOM_FILE = 'dependency-graph/sbom'; # 依存の一覧から足した部品の、読んだ場所

sub inventory_read {
    my ($repo_root) = @_;
    my $fetched = _inventory_run_limited($INVENTORY_FETCH_TIMEOUT, {}, 'git', '-C', $repo_root, 'fetch', '--quiet', 'origin', 'main') == 0;
    my $ref = 'origin/main';
    my $commit = _inventory_git($repo_root, 'rev-parse', '--verify', '--quiet', 'origin/main^{commit}');
    if (!defined $commit) {
        $ref = 'HEAD';
        $commit = _inventory_git($repo_root, 'rev-parse', '--verify', '--quiet', 'HEAD^{commit}');
    }
    my %components;
    my $inv = { commit => undef, ref => $ref, fetched => $fetched ? JSON::PP::true : JSON::PP::false, components => \%components, sbom_ok => JSON::PP::false };
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
    my @files = _inventory_files($repo_root, $inv->{commit});
    _inventory_images($show, $add, \@files);
    _inventory_terraform_lock($show, $add);
    _inventory_aws($show, $add, \@files);
    _inventory_ci($show, $add, \@files);
    $inv->{sbom_ok} = _inventory_sbom($repo_root, $add) ? JSON::PP::true : JSON::PP::false;

    for my $c (values %components) {
        $c->{partial} = $c->{partial} ? JSON::PP::true : JSON::PP::false;
    }
    return $inv;
}

# 部品の一覧に、鍵と版と読んだファイルを足す。同じ版と同じファイルは1回だけ持つ。
# 版が undef のときは、版を足さずに鍵とファイルだけを足す(版が分からない部品)
sub _inventory_add {
    my ($components, $key, $version, $file, $partial) = @_;
    my $c = $components->{$key} //= { versions => [], files => [], partial => 0 };
    push @{ $c->{versions} }, $version if defined $version && !grep { $_ eq $version } @{ $c->{versions} };
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

# イメージのリポジトリとタグを読み、image:<リポジトリ> の鍵に足す。
# 版は、タグの先頭の数字と点の並び(頭の v を除く)。点を持たない数だけのときは一部だけの版にする。
# タグが無いか、数字で始まらないときは、版が分からない部品にする
sub _inventory_image {
    my ($add, $ref, $file) = @_;
    return if $ref =~ /\$/;
    $ref =~ s/\@.*\z//s;
    my ($repo, $tag) = $ref =~ m{\A(.+?)(?::([^:/]+))?\z} or return;
    my ($version, $partial);
    if (defined $tag && $tag =~ /\Av?(\d+(?:\.\d+)*)/) {
        $version = $1;
        $partial = $version !~ /\./;
    }
    $add->("image:$repo", $version, $file, $partial);
}

# git ls-tree で見つけた Dockerfile* の FROM と、compose.yaml の image: を読む。
# 前の段階の名前と scratch と、変数で書いた FROM は飛ばす
sub _inventory_images {
    my ($show, $add, $files) = @_;
    for my $file (grep { m{(?:\A|/)Dockerfile[^/]*\z} } @$files) {
        my $text = $show->($file) // next;
        my %stages;
        for my $line (split /\r?\n/, $text) {
            my ($ref, $alias) = $line =~ /\A\s*FROM\s+(?:--\S+\s+)*(\S+)(?:\s+AS\s+(\S+))?/i or next;
            _inventory_image($add, $ref, $file) unless lc $ref eq 'scratch' || $stages{ lc $ref };
            $stages{ lc $alias } = 1 if defined $alias;
        }
    }
    my $file = 'compose.yaml';
    my $text = $show->($file) // return;
    for my $line (split /\r?\n/, $text) {
        _inventory_image($add, $1, $file) if $line =~ /\A\s*image:\s*["']?([^"'\s#]+)/;
    }
}

# terraform/.terraform.lock.hcl の provider "<host>/<namespace>/<name>" の version
sub _inventory_terraform_lock {
    my ($show, $add) = @_;
    my $file = 'terraform/.terraform.lock.hcl';
    my $text = $show->($file) // return;
    my $provider;
    for my $line (split /\r?\n/, $text) {
        if ($line =~ m{\Aprovider\s+"(?:[^"/]+/)*([^"/]+/[^"/]+)"}) {
            $provider = $1;
        } elsif ($line =~ /\A\}/) {
            undef $provider;
        } elsif (defined $provider && $line =~ /\A\s*version\s*=\s*"([^"]+)"/) {
            $add->("terraform-provider:$provider", $1, $file, 0);
        }
    }
}

# terraform/ の *.tf の resource "aws_<サービス>_..."。aws_db_instance は aws:rds にする。
# aws:rds は engine_version を、aws:elasticache は major_engine_version を、一部だけの版にする。ほかは版が分からない部品にする
my %INVENTORY_AWS_VERSION_ATTR = (rds => 'engine_version', elasticache => 'major_engine_version');

sub _inventory_aws {
    my ($show, $add, $files) = @_;
    for my $file (grep { m{\Aterraform/(?:.+/)?[^/]+\.tf\z} } @$files) {
        my $text = $show->($file) // next;
        my $service;
        for my $line (split /\r?\n/, $text) {
            if ($line =~ /\Aresource\s+"aws_([a-z0-9]+)(?:_([a-z0-9_]+))?"/) {
                $service = ($1 eq 'db' && ($2 // '') eq 'instance') ? 'rds' : $1;
                $add->("aws:$service", undef, $file, 0);
            } elsif ($line =~ /\A\}/) {
                undef $service;
            } elsif (defined $service && defined(my $attr = $INVENTORY_AWS_VERSION_ATTR{$service})) {
                $add->("aws:$service", $1, $file, 1) if $line =~ /\A\s*\Q$attr\E\s*=\s*"([^"]+)"/;
            }
        }
    }
}

# .github/workflows/*.y*ml と .github/actions/**/action.y*ml の node-version と TRIVY_VERSION と codex-version と、
# uses: <owner>/<repo>[/<path>]@<sha> # v<版> の注記の版。注記の無い uses: は版が分からない部品にする
sub _inventory_ci {
    my ($show, $add, $files) = @_;
    my @ci = grep { m{\A\.github/workflows/[^/]+\.ya?ml\z} || m{\A\.github/actions/(?:.+/)?action\.ya?ml\z} } @$files;
    my %tools = ('node-version' => 'ci:node', TRIVY_VERSION => 'ci:trivy', 'codex-version' => 'npm:@openai/codex');
    for my $file (@ci) {
        my $text = $show->($file) // next;
        for my $line (split /\r?\n/, $text) {
            if ($line =~ /(?:\A|[\s-])(node-version|TRIVY_VERSION|codex-version):\s*["']?v?(\d[\w.+-]*)/) {
                $add->($tools{$1}, $2, $file, 0);
            } elsif ($line =~ m{\buses:\s*["']?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(?:/[^\@\s"']*)?\@[0-9a-fA-F]{40}\b["']?(?:\s+#\s*v?(\d[\w.+-]*))?}) {
                $add->("action:$1/$2", $3, $file, 0);
            }
        }
    }
}

# gh api repos/{owner}/{repo}/dependency-graph/sbom を、決めた秒数で打ち切って1回呼ぶ。
# externalRefs の purl が pkg:maven/ で始まる部品だけを maven:<group>:<artifact> の鍵に足す。
# 呼べたかどうか(sbom_ok)を返す
sub _inventory_sbom {
    my ($repo_root, $add) = @_;
    my $out;
    my $rc = _inventory_run_limited($INVENTORY_SBOM_TIMEOUT, { dir => $repo_root, out => \$out },
        'gh', 'api', 'repos/{owner}/{repo}/dependency-graph/sbom');
    return 0 unless $rc == 0;
    my $json = eval { JSON::PP->new->utf8->decode($out) };
    return 0 unless ref $json eq 'HASH' && ref $json->{sbom} eq 'HASH' && ref $json->{sbom}{packages} eq 'ARRAY';
    for my $package (@{ $json->{sbom}{packages} }) {
        next unless ref $package eq 'HASH' && ref $package->{externalRefs} eq 'ARRAY';
        for my $ref (@{ $package->{externalRefs} }) {
            next unless ref $ref eq 'HASH' && ($ref->{referenceType} // '') eq 'purl';
            my $purl = $ref->{referenceLocator};
            next unless defined $purl && !ref $purl;
            my ($group, $artifact, $version) = $purl =~ m{\Apkg:maven/([^/?#\@]+)/([^/?#\@]+)(?:\@([^?#]+))?} or next;
            s/%([0-9A-Fa-f]{2})/chr hex $1/ge for grep { defined } $group, $artifact, $version;
            $add->("maven:$group:$artifact", $version, $INVENTORY_SBOM_FILE, 0);
        }
    }
    return 1;
}

# commit のすべてのファイルの場所を返す。読めないときは空の一覧を返す
sub _inventory_files {
    my ($repo_root, $commit) = @_;
    my $raw = _inventory_git($repo_root, 'ls-tree', '-r', '-z', '--name-only', $commit);
    return () unless defined $raw && utf8::decode($raw);
    return grep { length } split /\0/, $raw;
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

# コマンドを動かし、決めた秒数で打ち切る: _inventory_run_limited(<秒数>, {dir => <フォルダ>, out => \$出力}, <コマンド...>)
# 終了コードを返す。シグナルで終わったときと、打ち切ったときと、動かせなかったときは -1 を返す。
# dir があれば、そのフォルダでコマンドを動かす。out があれば、標準出力をそこに入れる。無ければ標準出力を捨てる。
# 標準入力と標準エラーは捨て、git と gh が認証を尋ねて止まらないようにする
sub _inventory_run_limited {
    my ($seconds, $opt, @cmd) = @_;
    my ($r, $w);
    if ($opt->{out}) {
        pipe($r, $w) or return -1;
    }
    my $pid = fork;
    if (!defined $pid) {
        close $r if $r;
        close $w if $w;
        return -1;
    }
    if (!$pid) {
        my $null = File::Spec->devnull;
        open STDIN, '<', $null;
        if ($w) {
            close $r;
            open STDOUT, '>&', $w;
        } else {
            open STDOUT, '>', $null;
        }
        open STDERR, '>', $null;
        $ENV{GIT_TERMINAL_PROMPT} = '0';
        $ENV{GH_PROMPT_DISABLED} = '1';
        POSIX::_exit(127) if defined $opt->{dir} && !chdir $opt->{dir};
        exec(@cmd) or POSIX::_exit(127);
    }
    close $w if $w;
    my $buf = '';
    my $deadline = time + $seconds;
    while (time < $deadline) {
        if ($r) {
            # 子が標準出力を閉じるまで読む。パイプが詰まって子が止まらないよう、終わりを待つ前に読み切る
            my $rin = '';
            vec($rin, fileno($r), 1) = 1;
            next unless select(my $rout = $rin, undef, undef, 0.1) > 0;
            my $n = sysread($r, $buf, 65536, length $buf);
            next if !defined $n && $! == POSIX::EINTR();
            if (!$n) {
                close $r;
                undef $r;
            }
            next;
        }
        if (waitpid($pid, WNOHANG) == $pid) {
            ${ $opt->{out} } = $buf if $opt->{out};
            return $? == 0 ? 0 : (($? >> 8) || -1);
        }
        select(undef, undef, undef, 0.1);
    }
    close $r if $r;
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
