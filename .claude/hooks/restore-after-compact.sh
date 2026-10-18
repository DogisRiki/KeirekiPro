#!/bin/bash
# =====================================================================
# SessionStart(matcher compact)hook: 圧縮の直後に作業の状態を差し込む
#
# 会話が要約された(自動の圧縮か /compact)直後に、作業の状態をファイルから読み直し、
# additionalContext で会話に差し込む。読み直すもの:
#   作業フォルダ  入力の cwd から git -C <cwd> rev-parse --show-toplevel で決める
#   ブランチ      git branch --show-current
#   Issue の番号  lib.sh の kp_state_dir の下の issues/*.json のうち、folder がいまの作業フォルダ
#                 (kp_folder_id と同じ比べ方)の記録の issue
#   spec          .kiro/specs/*/spec.json のうち、issue か additional_issues に Issue の番号を含むもの。
#                 Issue の番号が分からないときは、git merge-base origin/main HEAD からの変更と、
#                 コミットしていない変更のうち、.kiro/specs/<feature>/ の下に触れた spec
#   spec ごとに   phase、approvals の各段階の generated と approved、review_model、
#                 reviews/{段階}-review.md の最後の「## サイクル<N> 往復<M>」の見出しと最終行、
#                 reviews/{段階}-response.md に同じ「## サイクル<N> 往復<M> への対応」があるか、
#                 tasks.md の「- [x]」と「- [ ]」の数
# そのあとに、Claude が続け方を誤らないための4つの決まりを足す。
# 動かない場面: 入力の source が compact でないとき、入力に agent_id があるとき(補助役の会話)。
# ファイルを読むだけで書かず、ネットワークに出ない。並行作業の記録(sessions/ と issues/)を書き換えない。
# 作業を止めない: git のリポジトリの外では何も出さない。spec.json を読めないとき、Issue の記録が無いとき、
# origin/main が無いときは、その項目を飛ばし、飛ばしたことを1行書く。終了コードはいつも0。
# 前提: bash と perl(JSON::PP)と git。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
# git status などが索引を書き直さないようにする(読むだけにする)
export GIT_OPTIONAL_LOCKS=0

payload=$(cat)

extract() {
    printf '%s' "$payload" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d eq "HASH";
        my $v = $d->{$ARGV[0]};
        if (defined $v && !ref $v) { utf8::encode($v) if utf8::is_utf8($v); print $v }
    ' -- "$1" 2>/dev/null
}

# 補助役の会話では差し込まない(差し込む決まりは親の会話のスキルの進め方を前提にしている)
[ -z "$(extract agent_id)" ] || exit 0
[ "$(extract source)" = compact ] || exit 0

cwd=$(extract cwd)
[ -n "$cwd" ] || exit 0
cwd=${cwd//\\//}
[ -d "$cwd" ] || exit 0
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$top" ] || exit 0
cd "$top" 2>/dev/null || exit 0
top=${top//\\//}

lines=()
add() { lines+=("$1"); }

add "[compact] 会話が要約された。ファイルから読み直した作業の状態は次のとおり。"
add "- 作業フォルダ: $top"
branch=$(git branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
    add "- ブランチ: $branch"
else
    add "- ブランチ: 開いていない(detached HEAD)"
fi

# --- Issue の番号(並行作業の Issue の記録から)
issues=""
issues_read=0
lib="$(dirname "$0")/../scripts/parallel/lib.sh"
# shellcheck source=.claude/scripts/parallel/lib.sh
if [ -f "$lib" ] && . "$lib" 2>/dev/null; then
    # lib.sh の関数は失敗すると exit 69 で終わるので、サブシェルで呼ぶ
    if state=$(kp_state_dir 2>/dev/null) && me=$(kp_folder_id 2>/dev/null); then
        issues_read=1
        ic=$(git config --get core.ignorecase 2>/dev/null)
        issues=$(perl -MJSON::PP -e '
            my ($dir, $me, $ic) = @ARGV;
            sub norm { my $p = $_[0] // ""; $p =~ tr/A-Z/a-z/ if $ic eq "true"; $p }
            opendir my $dh, $dir or exit 0;
            my %found;
            for my $name (sort readdir $dh) {
                next unless $name =~ /\.json\z/;
                open my $fh, "<:raw", "$dir/$name" or next;
                local $/; my $text = <$fh>; close $fh;
                my $d = eval { JSON::PP->new->utf8->decode($text) };
                next unless ref $d eq "HASH";
                my $folder = $d->{folder};
                next unless defined $folder && !ref $folder && length $folder;
                utf8::encode($folder) if utf8::is_utf8($folder);
                next unless norm($folder) eq $me;
                my $n = $d->{issue};
                next unless defined $n && !ref $n && $n =~ /\A[0-9]+\z/;
                $found{0 + $n} = 1;
            }
            print join(" ", sort { $a <=> $b } keys %found);
        ' -- "$state/issues" "$me" "$ic" 2>/dev/null)
    fi
fi
if [ -n "$issues" ]; then
    add "- Issue: #${issues// / #}"
elif [ "$issues_read" = 1 ]; then
    add "- Issue の記録(並行作業の issues/<N>.json)に、この作業フォルダのものが無いので、Issue の番号を飛ばした。代わりに、ブランチで変えた spec を出す"
else
    add "- Issue の記録(並行作業の issues/<N>.json)を読めないので、Issue の番号を飛ばした。代わりに、ブランチで変えた spec を出す"
fi

# --- Issue の番号が分からないときに使う、ブランチで変えたファイルの一覧
changed=""
if [ -z "$issues" ]; then
    if git rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 \
        && base=$(git merge-base origin/main HEAD 2>/dev/null); then
        changed=$(git -c core.quotepath=false diff --name-only "$base" HEAD -- .kiro/specs 2>/dev/null)
    else
        add "- origin/main が無いので、ブランチでコミットした spec の変更を飛ばした(コミットしていない変更だけを見る)"
    fi
    changed+=$'\n'$(git -c core.quotepath=false diff --name-only HEAD -- .kiro/specs 2>/dev/null)
    changed+=$'\n'$(git -c core.quotepath=false ls-files --others --exclude-standard -- .kiro/specs 2>/dev/null)
fi

# --- spec ごとの状態
spec_lines=$(printf '%s\n' "$changed" | perl -MJSON::PP -e '
    my ($top, $issues) = @ARGV;
    binmode STDOUT;
    my @issues = grep { /\A[0-9]+\z/ } split " ", $issues;
    my %want = map { (0 + $_) => 1 } @issues;
    sub bytes { my $v = shift; return "" unless defined $v; utf8::encode($v) if utf8::is_utf8($v); $v }
    sub flag { my $v = shift; return "(無し)" unless defined $v; JSON::PP::is_bool($v) ? ($v ? "true" : "false") : bytes($v) }
    sub load {
        open my $fh, "<:raw", $_[0] or return undef;
        local $/; my $text = <$fh>; close $fh;
        my $d = eval { JSON::PP->new->utf8->decode($text) };
        return ref $d eq "HASH" ? $d : undef;
    }
    sub read_lines {
        open my $fh, "<:raw", $_[0] or return ();
        my @l = <$fh>; close $fh;
        s/\r?\n\z// for @l;
        return @l;
    }
    my @features;
    if (@issues) {
        opendir my $dh, "$top/.kiro/specs" or exit 0;
        @features = sort grep { !/\A\./ && -d "$top/.kiro/specs/$_" } readdir $dh;
    } else {
        local $/; my $text = <STDIN> // "";
        my %seen;
        for (split /\n/, $text) { $seen{$1} = 1 if m{\A\.kiro/specs/([^/]+)/} }
        @features = sort keys %seen;
        print "- ブランチで変えた spec は無い\n" unless @features;
    }
    my $matched = 0;
    for my $f (@features) {
        my $rel = ".kiro/specs/$f/spec.json";
        my $file = "$top/$rel";
        if (!-f $file) {
            print "- $rel が無いので、spec $f を飛ばした\n" unless @issues;
            next;
        }
        my $d = load($file);
        if (!$d) {
            print "- $rel を読めないので、spec $f を飛ばした\n";
            next;
        }
        if (@issues) {
            my @nums = ($d->{issue});
            push @nums, @{ $d->{additional_issues} } if ref $d->{additional_issues} eq "ARRAY";
            next unless grep { defined $_ && !ref $_ && /\A#?([0-9]+)\z/ && $want{0 + $1} } @nums;
        }
        $matched++;
        print "- spec: $f(.kiro/specs/$f/)phase: ", flag($d->{phase}), "\n";
        my $model = defined $d->{review_model} ? bytes($d->{review_model}) : "書かれていない";
        print "- spec $f の審査役のモデル(review_model): $model\n";
        my $ap = ref $d->{approvals} eq "HASH" ? $d->{approvals} : {};
        for my $stage (qw(requirements design tasks)) {
            my $st = ref $ap->{$stage} eq "HASH" ? $ap->{$stage} : {};
            print "- spec $f の段階 $stage: generated=", flag($st->{generated}), " approved=", flag($st->{approved}), "\n";
        }
        for my $stage (qw(requirements design tasks)) {
            my $rv = "$top/.kiro/specs/$f/reviews/$stage-review.md";
            if (!-f $rv) {
                print "- spec $f の段階 $stage の審査の記録は無い(reviews/$stage-review.md が無い。往復は始まっていない)\n";
                next;
            }
            my @l = read_lines($rv);
            my ($cycle, $round);
            for (@l) { ($cycle, $round) = ($1, $2) if /\A## サイクル([0-9]+) 往復([0-9]+)(?! への対応)/ }
            my ($last) = grep { /\S/ } reverse @l;
            $last = "(空)" unless defined $last;
            if (!defined $cycle) {
                print "- spec $f の段階 $stage の審査: reviews/$stage-review.md に「## サイクル<N> 往復<M>」の見出しが無い。review.md の最終行: $last\n";
                next;
            }
            my $rs = "$top/.kiro/specs/$f/reviews/$stage-response.md";
            my $has = grep { /\A## サイクル$cycle 往復$round への対応/ } read_lines($rs);
            print "- spec $f の段階 $stage の審査: 最後の往復は「サイクル$cycle 往復$round」、対応の記録: ",
                ($has ? "あり" : "なし"), "、review.md の最終行: $last\n";
        }
        my $tk = "$top/.kiro/specs/$f/tasks.md";
        if (-f $tk) {
            my ($done, $open) = (0, 0);
            for (read_lines($tk)) {
                $done++ if /\A\s*- \[[xX]\]/;
                $open++ if /\A\s*- \[ \]/;
            }
            print "- spec $f の tasks.md: 完了 $done / 未完了 $open\n";
        } else {
            print "- spec $f の tasks.md は無い\n";
        }
    }
    if (@issues && !$matched) {
        print "- Issue ", join(" ", map { "#$_" } @issues), " の spec は無い(.kiro/specs/*/spec.json の issue と additional_issues に無い)\n";
    }
' -- "$top" "$issues" 2>/dev/null)
while IFS= read -r l; do
    [ -n "$l" ] && add "$l"
done <<<"$spec_lines"

# --- Claude への決まり
add "決まり1: 要約に実行中のスキルが書かれていれば、そのスキルの .claude/skills/<名前>/SKILL.md を Read で全文読み直してから続ける。圧縮のあとは、スキルの本文が先頭の5,000トークンまでしか戻らないため"
add "決まり2: ここに書かれたことと要約に書かれたことを、所有者に尋ね直さない"
add "決まり3: 要約とここに書かれたことが食い違うときは、ここに書かれたこと(ファイルの状態)を正とする"
add "決まり4: /spec-review の往復の途中なら、/spec-review の SKILL.md の「会話が要約されたあとに続けるとき」の節に従う"

printf '%s\n' "${lines[@]}" | perl -MJSON::PP -e '
    local $/; my $ctx = <STDIN>;
    $ctx =~ s/\n\z//;
    utf8::decode($ctx);
    print JSON::PP->new->utf8->canonical->encode({
        hookSpecificOutput => {
            hookEventName => "SessionStart",
            additionalContext => $ctx,
        },
    }), "\n";
' 2>/dev/null

exit 0
