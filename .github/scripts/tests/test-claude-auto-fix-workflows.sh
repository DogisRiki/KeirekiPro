#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の2つのワークフローの組み立てを確かめる自動テスト
# (design.md の「テストの方針」の test-claude-auto-fix-workflows.sh の項)
#
# 対象ごとのワークフロー claude-auto-fix-target.yaml と、振り分けのワークフロー claude-auto-fix.yaml を
# yq で JSON に直して読み、ジョブごとの権限、秘密の値を渡すジョブと手順、ジョブの順番と if、
# 手順の順番と if、環境変数の渡し方、きっかけが設計のとおりであることを確かめる。
# このテストは振り分けのワークフローの dispatch ジョブでも流れ、0以外で終われば対象ごとの実行を起動しない。
#
# 環境変数:
#   CAF_TARGET_WORKFLOW_FILE    対象ごとのワークフロー(既定は .github/workflows/claude-auto-fix-target.yaml)
#   CAF_DISPATCH_WORKFLOW_FILE  振り分けのワークフロー(既定は .github/workflows/claude-auto-fix.yaml)
#   CAF_CODEQL_WORKFLOW_FILE    CodeQL のワークフロー(既定は .github/workflows/codeql.yaml)。init と analyze の版を比べる
#   KP_TEST_CASE                場合の名前を入れると、その場合だけを流す
#
# ワークフローの手順は id で見分ける。2つのワークフローは、次の id を使う。
#   prepare ジョブ: prepare(claude-auto-fix-prepare.sh を呼ぶ)、upload_trivy(成果物 trivy-results を上げる)
#   edit ジョブ: download_trivy、base(起点のコードを作り直す)、materials、run_claude
#   verify ジョブ: alert(最初の手順)、base、rebuild_tools_<名前>(作り直しの道具)、apply、
#     area_tools_<名前>(変わった領域の道具)、check、codeql_<名前>(codeql_init codeql_build codeql_analyze など)、confirm
#   verify-image ジョブ: base、final(final.patch を当てる)、scan_check
#     イメージは docker buildx build で、作業のフォルダの最上位から見た -f のパスと -t の名前で組み立て、
#     trivy image でその名前を調べて -o のファイルに結果を書く。scan_check は、2つの結果のファイルごとに
#     check-container-scan.sh を report で呼ぶ。このテストは、scan_check を、check-container-scan.sh を
#     差し替えたフォルダで実際に動かして確かめる
#   cooldown-push ジョブ: base、final。出力 sha に一時のブランチのコミットの SHA を出す。final は、環境変数 GH_TOKEN で
#     bot の PAT を受け取り、gh auth setup-git で git に資格情報を渡してから push する
#   cooldown-judge ジョブ: submitted(cooldown-submit が通ったかを確かめる)、judge_npm、judge_go、judge_ci_tool、
#     judge_ci_signature、judge、delete_branch
#     judge_npm judge_go judge_ci_tool は、スクリプトの終わり方を出力 rc に書く。judge は3つの rc と
#     judge_ci_signature の outcome を環境変数で受け取る。このテストは、この4つの手順を、
#     スクリプトを差し替えたフォルダで実際に動かして確かめる
#   ship ジョブ: base、ship
#   report ジョブ: record、upload_outcome、notify
#   cleanup ジョブ: cleanup(この実行の成果物のうち outcome のほかを消す。このテストは差し替えた gh で動かして確かめる)
#   振り分けのワークフローの dispatch ジョブ: dispatch(きっかけに合う形で claude-auto-fix-dispatch.sh を呼ぶ)
#   振り分けのワークフローの sweep ジョブ: sweep(claude-auto-fix-sweep.sh を呼ぶ)
#   このテストは、dispatch と sweep を、スクリプトを差し替えたフォルダで実際に動かして確かめる
#   対象ごとのワークフローの ref-check ジョブ: ref_check(::error:: の行を出して失敗する。ジョブの手順はこの1つだけ。
#     このテストは、この手順を実際に動かして確かめる)
#   振り分けのワークフローの run-branch ジョブの手順は、id ではなく、run の中身で見分ける。tests/test- を含む手順が
#   テストを流す手順で、claude-auto-fix-run-branch.sh を tests/ の外から呼ぶ手順がスクリプトを呼ぶ手順である
#   base と final は、RUNNER_TEMP の下の base.patch と final.patch を読む。このテストは、base と final と、
#   judge の4つの手順と scan_check と cleanup と、ほかのいくつかの手順を、使うコマンドを差し替えたフォルダで実際に動かす。
#   手順の中の ${{ 式 }} は、テストが決めた値で置き換え、== != && || ! と括弧を評価する。差し替えたコマンドは、
#   自分の名前と引数と環境変数を記録するので、呼ぶスクリプトの取り違えも見つかる
#
# 場合の名前:
#   対象ごとのワークフロー: target_on target_permissions target_secrets target_order target_skip_to_report
#     target_base target_tests_first target_prepare_trivy target_edit target_verify_order target_verify_outputs
#     target_verify_codeql target_verify_checkout target_verify_image target_report_steps target_job_results
#     target_cleanup target_timeouts target_cooldown_push_if target_cooldown_graph target_cooldown_pnpm
#     target_cooldown_judge target_cooldown_signature target_cooldown_signature_fail target_ref_branch target_cache
#   振り分けのワークフロー: dispatch_on dispatch_permissions dispatch_secrets dispatch_conditions dispatch_steps
#     dispatch_run_branch
#   cooldown の4つのジョブがそろってから通る場合(タスク 6.3): target_order target_base target_job_results
#     target_cooldown_push_if target_cooldown_graph target_cooldown_pnpm target_cooldown_judge
#     target_cooldown_signature target_cooldown_signature_fail
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TARGET="${CAF_TARGET_WORKFLOW_FILE:-$ROOT/.github/workflows/claude-auto-fix-target.yaml}"
DISPATCH="${CAF_DISPATCH_WORKFLOW_FILE:-$ROOT/.github/workflows/claude-auto-fix.yaml}"
CODEQL="${CAF_CODEQL_WORKFLOW_FILE:-$ROOT/.github/workflows/codeql.yaml}"
CASE="${KP_TEST_CASE:-}"
FAILED=0
RAN=0

command -v yq >/dev/null 2>&1 || { echo "yq がありません" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq がありません" >&2; exit 1; }

WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
check() { if [ "$2" = true ]; then ok "$1"; else ng "$1"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); echo "[$1]"; return 0; fi; return 1; }

# YAML を JSON に直す。読めないファイルは空のオブジェクトにし、場合ごとに失敗させる
TJ="$WORK/target.json"
DJ="$WORK/dispatch.json"
CJ="$WORK/codeql.json"
to_json() {
    if [ -f "$1" ] && yq -o=json '.' "$1" >"$2" 2>/dev/null && jq -e 'type == "object"' "$2" >/dev/null 2>&1; then
        return 0
    fi
    echo '{}' >"$2"
    echo "  読めないワークフロー: $1" >&2
    return 1
}
to_json "$TARGET" "$TJ"
to_json "$DISPATCH" "$DJ"
to_json "$CODEQL" "$CJ"

# 式の正規化: 前後の ${{ }} と、すべての空白を除く
# 無い値は空にする。false は "false" のまま残す(jq の // は false も無い値とみなすため使わない)
JQ_NORM='def norm: (if . == null then "" else tostring end) |gsub("^\\s*\\$\\{\\{"; "") | gsub("\\}\\}\\s*$"; "") | gsub("\\s+"; "");'

# ジョブの値を JSON の文字列で出す(無ければ空)
job_text() { jq -c --arg j "$2" '.jobs[$j] // empty' "$1"; }
# 手順の値を JSON の文字列で出す(無ければ空)
step_text() { jq -c --arg j "$2" --arg s "$3" 'first(.jobs[$j].steps[]? | select(.id == $s)) // empty' "$1"; }
# 手順の番号(無ければ -1)
step_idx() { jq -r --arg j "$2" --arg s "$3" '[.jobs[$j].steps[]?.id] | index($s) // -1' "$1"; }
# 手順の if を正規化して出す
step_if() { jq -r --arg j "$2" --arg s "$3" "$JQ_NORM"' first(.jobs[$j].steps[]? | select(.id == $s)) // {} | .if | norm' "$1"; }
# ジョブの if を正規化して出す
job_if() { jq -r --arg j "$2" "$JQ_NORM"' .jobs[$j].if | norm' "$1"; }
# 手順の env の値を正規化して出す
step_env() { jq -r --arg j "$2" --arg s "$3" --arg e "$4" "$JQ_NORM"' first(.jobs[$j].steps[]? | select(.id == $s)) // {} | .env[$e] | norm' "$1"; }
# 手順の with の値を正規化して出す
step_with() { jq -r --arg j "$2" --arg s "$3" --arg w "$4" "$JQ_NORM"' first(.jobs[$j].steps[]? | select(.id == $s)) // {} | .with[$w] | norm' "$1"; }
# ジョブの needs が、引数の名前をすべて含むか
needs_has() {
    local f=$1 j=$2
    shift 2
    jq -e --arg j "$j" --args '(.jobs[$j].needs // []) | (if type == "string" then [.] else . end) as $n
        | all($ARGS.positional[]; . as $x | $n | index($x) != null)' "$@" <"$f" >/dev/null 2>&1
}
# ジョブの権限が、渡した JSON と同じか
perm_is() { jq -e --arg j "$2" --argjson p "$3" '.jobs[$j].permissions == $p' "$1" >/dev/null 2>&1; }
# 文字列の中の、正規表現に一致するすべての部分を1行ずつ出す。grep -o は実装によって1行の中の2つ目からの一致を出さないため perl で数える
all_of() { perl -e 'print "$&\n" while $ARGV[0] =~ /$ARGV[1]/g' "$1" "$2"; }
# 文字列の中の、決まった文字列の数
count_of() { perl -e '$c = () = $ARGV[0] =~ /\Q$ARGV[1]\E/g; print $c' "$1" "$2"; }
# 括弧の中を除いた式に、|| が無いか
no_top_or() { perl -e '$_ = $ARGV[0]; 1 while s/\([^()]*\)//g; exit(/\|\|/ ? 1 : 0)' "$1"; }
# 1つ目の文字列が、2つ目の文字列を含むか
has() { grep -qF -- "$2" <<<"$1"; }
# 文字列が空でない1行だけか
one_line() { [ -n "$1" ] && [ "$(printf '%s\n' "$1" | wc -l)" -eq 1 ]; }
yes_if() { if "$@"; then echo true; else echo false; fi; }

# GITHUB_TOKEN を渡す書き方の数
token_count() { all_of "$1" 'github\s*(\.\s*token|\[\s*\x27token\x27\s*\])|secrets\s*(\.\s*GITHUB_TOKEN|\[\s*\x27GITHUB_TOKEN\x27\s*\])|toJSON\(\s*github\s*\)' | wc -l | tr -d ' '; }

# 正規化した式の、括弧の外の && で区切った項を、そのままの形で1行ずつ出す(括弧の中の && では区切らない)
top_conj() {
    perl -e 'my @ch = split //, $ARGV[0]; my ($d, $c, @o) = (0, "");
        for (my $i = 0; $i < @ch; $i++) {
            my $x = $ch[$i]; $d++ if $x eq "("; $d-- if $x eq ")";
            if ($d == 0 && $x eq "&" && ($ch[$i + 1] // "") eq "&") { push @o, $c; $c = ""; $i++; next }
            $c .= $x;
        }
        push @o, $c; print "$_\n" for @o' "$1"
}
# 正規化した式が、2つ目の文字列を、括弧の外の && の項として持つか
conj_has() { top_conj "$1" | grep -qxF -- "$2"; }
# 正規化した式の、括弧の外の && の項が、2つ目から先の引数とちょうど同じか(順は問わない)
conj_is() {
    local e=$1
    shift
    [ "$(top_conj "$e" | sort)" = "$(printf '%s\n' "$@" | sort)" ]
}
# 正規化した式が、「(2つ目 || 3つ目)」を、どちらの順でも、括弧の外の && の項として持つか
conj_has_or() { conj_has "$1" "($2||$3)" || conj_has "$1" "($3||$2)"; }
# ジョブの if が、前のジョブの結果を読む形か。always() と failure() を使わず、括弧の外に || が無く、
# cancelled() を、括弧の外の && の項の !cancelled() としてだけ使う
job_if_ok() {
    perl -e '$_ = $ARGV[0]; exit 1 if /always\(\)|failure\(\)/; my $c = () = /cancelled\(\)/g;
        1 while s/\([^()]*\)/\x01/g; exit 1 if /\|\|/;
        my $n = grep { $_ eq "!cancelled\x01" } split /&&/; exit($c == $n ? 0 : 1)' "$1"
}

# ジョブの run の中の docker buildx build ごとに、「Dockerfile、イメージの名前、組み立ての文脈」をタブで区切って1行ずつ出す。
# Dockerfile は -f と --file と --file= の値、イメージの名前は -t と --tag と --tag= の値か、--output の dest= の値。
# 引用符と先頭の ./ を除く
build_lines() {
    jq -r --arg j "$1" '.jobs[$j].steps[]?.run // empty' "$TJ" | perl -e '
        local $/; $_ = <STDIN>; s/\\\n/ /g; s/\$\{\{\s*(.*?)\s*\}\}/\${{$1}}/g;
        sub cl { my $v = shift; $v =~ s/["\x27]//g; $v =~ s/^\.\///; return $v }
        for (split /\n/) {
            next unless /docker\s+buildx\s+build\s/;
            my @t = split " "; my ($f, $tag, $pf) = ("", "", "");
            for my $i (0 .. $#t) {
                my $n = $i < $#t ? $t[$i + 1] : "";
                $pf = $n if $t[$i] eq "--platform";
                $pf = $1 if $t[$i] =~ /^--platform=(.*)/;
                $f = $n if $t[$i] eq "-f" || $t[$i] eq "--file";
                $f = $1 if $t[$i] =~ /^--file=(.*)/;
                $tag = $n if $t[$i] eq "-t" || $t[$i] eq "--tag";
                $tag = $1 if $t[$i] =~ /^--tag=(.*)/;
                my $o = $t[$i] eq "--output" || $t[$i] eq "-o" ? $n : ($t[$i] =~ /^--output=(.*)/ ? $1 : "");
                $tag = $1 if $o =~ /(?:^|,)dest=([^,]*)/;
            }
            print join("\t", cl($f), cl($tag), cl($t[-1]), cl($pf)), "\n";
        }'
}
# ジョブの docker buildx build のうち、2つ目の引数の Dockerfile を使うものの、組み立ての文脈を出す
build_ctx() { build_lines "$1" | awk -F'\t' -v f="$2" '$1 == f { print $3 }'; }
# ジョブの docker buildx build のうち、2つ目の引数の Dockerfile を使うものの、イメージの名前を出す
build_tag() { build_lines "$1" | awk -F'\t' -v f="$2" '$1 == f { print $2 }'; }
# ジョブの docker buildx build のうち、2つ目から先の引数のそれぞれの Dockerfile を使うものが、1つずつだけあり、
# どれも --platform linux/arm64 か
arm_builds() {
    local j=$1 f
    shift
    for f in "$@"; do
        [ "$(build_lines "$j" | awk -F'\t' -v f="$f" '$1 == f { print $4 }')" = linux/arm64 ] || return 1
    done
}
# ジョブの、2つ目の引数の Dockerfile から作ったイメージを Trivy で調べた結果のファイルを、canon_path でそろえて出す
trivy_out_of() {
    local t
    t=$(build_tag "$1" "$2")
    one_line "$t" || return 0
    trivy_lines "$1" | awk -F'\t' -v t="$t" '$2 == t { print $1 }' | while IFS= read -r p; do canon_path "$p"; echo; done
}

# パスの書き方をそろえる。${{ runner.temp }} と $RUNNER_TEMP と ${RUNNER_TEMP} を RUNNER_TEMP にし、引用符を除く
canon_path() { perl -e '$_ = $ARGV[0]; s/\$\{\{\s*runner\.temp\s*\}\}|\$\{RUNNER_TEMP\}|\$RUNNER_TEMP/RUNNER_TEMP/g; s/["\x27]//g; s/\/+$//; print' "$1"; }

# ジョブの run の中の trivy の行ごとに、「結果を書くファイル、調べるイメージ」をタブで区切って1行ずつ出す。
# 結果を書くファイルは -o と --output と --output= の値。調べるイメージは --input と --input= の値か、行の最後の語
trivy_lines() {
    jq -r --arg j "$1" '.jobs[$j].steps[]?.run // empty' "$TJ" | perl -e '
        local $/; $_ = <STDIN>; s/\\\n/ /g; s/\$\{\{\s*(.*?)\s*\}\}/\${{$1}}/g;
        sub cl { my $v = shift; $v =~ s/["\x27]//g; $v =~ s/^\.\///; return $v }
        for (split /\n/) {
            next unless /(?:^|[\s;&|(])trivy\s/;
            my @t = split " "; my ($o, $in) = ("", $t[-1]);
            for my $i (0 .. $#t) {
                my $n = $i < $#t ? $t[$i + 1] : "";
                $o = $n if $t[$i] eq "-o" || $t[$i] eq "--output";
                $o = $1 if $t[$i] =~ /^--output=(.*)/;
                $in = $n if $t[$i] eq "--input";
                $in = $1 if $t[$i] =~ /^--input=(.*)/;
            }
            print cl($o), "\t", cl($in), "\n";
        }'
}
# Trivy が結果を書くファイルのパスを、1行ずつ出す
trivy_outputs() { trivy_lines "$1" | cut -f1; }

# 文字列の中の ${{ 式 }} を、引数の「式=値」の対応で置き換えて出す。式は空白を除いて比べる。
# 対応の無い式があれば 1 で終わる
subst_expr() {
    perl -e 'my ($s, @m) = @ARGV; my %m = map { split /=/, $_, 2 } @m; my $bad = 0; our (@T, $i);
        sub tru { my $v = shift; ref $v ? $$v : (defined $v && $v ne "") }
        sub str { my $v = shift; ref $v ? ($$v ? "true" : "false") : ($v // "") }
        sub pk { $T[$i] // "" }
        sub orx { my $v = andx(); while (pk() eq "||") { $i++; my $r = andx(); $v = tru($v) ? $v : $r } $v }
        sub andx { my $v = cmpx(); while (pk() eq "&&") { $i++; my $r = cmpx(); $v = tru($v) ? $r : $v } $v }
        sub cmpx { my $v = un(); if (pk() eq "==" || pk() eq "!=") { my $op = $T[$i++]; my $r = un();
                my $eq = lc(str($v)) eq lc(str($r)); $v = \(($op eq "==") == $eq ? 1 : 0) } $v }
        sub un { my $t = $T[$i++] // ""; if ($t eq "!") { return \(tru(un()) ? 0 : 1) }
            if ($t eq "(") { my $v = orx(); $bad = 1 unless ($T[$i++] // "") eq ")"; return $v }
            if ($t =~ /^\x27(.*)\x27$/s) { (my $x = $1) =~ s/\x27\x27/\x27/g; return $x }
            return \1 if $t eq "true"; return \0 if $t eq "false"; return undef if $t eq "null";
            if ($t =~ /^[A-Za-z_][A-Za-z0-9_.-]*$/ && exists $m{$t}) { return $m{$t} }
            $bad = 1; return "" }
        sub r { my $e = shift; (my $k = $e) =~ s{\s+}{}g; return $m{$k} if exists $m{$k};
            @T = (); $i = 0; pos($e) = 0;
            push @T, $1 while $e =~ /\G\s*(\x27(?:[^\x27]|\x27\x27)*\x27|==|!=|&&|\|\||!|\(|\)|[A-Za-z_][A-Za-z0-9_.-]*)/gc;
            unless ($e =~ /\G\s*$/gc) { $bad = 1; return "" }
            my $v = orx(); $bad = 1 if $i != @T; return str($v) }
        $s =~ s/\$\{\{(.*?)\}\}/r($1)/ges; print $s; exit $bad' "$@"
}

# 使い方: run_step <ジョブ> <手順の id> <作業のフォルダ> <式=値>...
# 手順の env と run の中の式を置き換え、作業のフォルダの中の手順の working-directory で、
# Actions の run と同じ bash の形で動かす。GITHUB_WORKSPACE は作業のフォルダ、RUNNER_TEMP はその中の rt、
# GITHUB_OUTPUT はその中の out、GITHUB_REPOSITORY は o/r、GITHUB_RUN_ID は RUN0 にする。終わり方は手順の終わり方で、手順が無ければ 98、対応の無い式があれば 99 で終わる
run_step() {
    local job=$1 sid=$2 dir=$3 st wd run k v
    shift 3
    st=$(step_text "$TJ" "$job" "$sid")
    [ -n "$st" ] || return 98
    wd=$(jq -r '."working-directory" // "."' <<<"$st")
    local vars=()
    while IFS=$'\t' read -r k v; do
        [ -n "$k" ] || continue
        v=$(subst_expr "$v" "$@") || return 99
        vars+=("$k=$v")
    done < <(jq -r '.env // {} | to_entries[] | "\(.key)\t\(.value | tostring)"' <<<"$st")
    run=$(subst_expr "$(jq -r '.run // ""' <<<"$st")" "$@") || return 99
    (cd "$dir/$wd" && env "${vars[@]}" GITHUB_WORKSPACE="$dir" RUNNER_TEMP="$dir/rt" GITHUB_OUTPUT="$dir/out" \
        GITHUB_PATH="$dir/github_path" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=RUN0 PATH="$dir/bin:$PATH" \
        bash --noprofile --norc -eo pipefail -c "$run")
}

# 使い方: stub_tree <名前> <偽のコマンドのパス>...
# $WORK/<名前> に、rt と bin と、偽のコマンドを置いたフォルダを作り、パスを出す。偽のコマンドは、
# 自分の名前と引数と、いくつかの環境変数をタブで区切って stub_log に1行足し、stub_rc_<名前> に書いた数(無ければ0)で終わる
stub_tree() {
    local d="$WORK/$1" s
    shift
    rm -rf "$d" && mkdir -p "$d/rt" "$d/bin" "$d/target" "$d/.github/scripts" || return 1
    for s in "$@"; do
        mkdir -p "$d/$(dirname "$s")"
        cat >"$d/$s" <<'EOF'
#!/usr/bin/env bash
n=$(basename "$0")
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$PWD" "$*" "${COOLDOWN_MODE:-}" "${PNPM_WORKSPACE_FILE:-}" "${GH_TOKEN:-}" \
    "${CI_TOOL_CHANGED_FILE:-}" "${GITHUB_PATH:-}" "${TRIVY_RESULTS_DIR:-}" "${EDIT_OUTCOME:-}|${JOB_RESULTS:-}" >>"$GITHUB_WORKSPACE/stub_log"
if [ "$n" = gh ]; then
    q=""; p=""
    for a in "$@"; do case "$p" in --jq | -q) q=$a ;; esac; case "$a" in --jq=*) q=${a#--jq=} ;; esac; p=$a; done
    j=$(cat "$GITHUB_WORKSPACE/gh_json" 2>/dev/null || echo '{}')
    if [ -n "$q" ]; then jq -r "$q" <<<"$j"; else printf '%s\n' "$j"; fi
fi
exit "$(cat "$GITHUB_WORKSPACE/stub_rc_$n" 2>/dev/null || echo 0)"
EOF
        chmod +x "$d/$s"
    done
    echo "$d"
}

# 使い方: patch_paths <ジョブ> <手順の id> <ファイルの名前>
# 手順の中で、RUNNER_TEMP の下の、ファイルの名前で終わるパスを、canon_path でそろえて1行ずつ出す。
# 正規表現の \x24 は $ の文字(perl が読む)
patch_paths() {
    all_of "$(step_text "$TJ" "$1" "$2")" '(\x24\{\{\s*runner\.temp\s*\}\}|\x24\{RUNNER_TEMP\}|\x24RUNNER_TEMP)/[A-Za-z0-9_./-]*'"$3" |
        while IFS= read -r p; do canon_path "$p"; echo; done | sort -u
}

# 使い方: patch_run <ジョブ> <手順の id> <ファイルの名前> <中身> <式=値>...
# 偽の git と gh を置いたフォルダで、手順の中のパスに中身を書いたファイルを置いて手順を動かし、手順の終わり方で終わる。
# git と gh の呼び方は、フォルダの stub_log に1行ずつ残る。secrets.BOT_GITHUB_TOKEN は BOT0 に置き換える
# (どのジョブのどの手順に現れてよいかは、target_secrets が数で確かめる)
patch_run() {
    local j=$1 s=$2 f=$3 body=$4 pd p
    shift 4
    pd=$(stub_tree patch bin/git bin/gh) || return 97
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        p=$(scan_path "$pd" "$p")
        mkdir -p "$(dirname "$p")" && printf '%s' "$body" >"$p"
    done < <(patch_paths "$j" "$s" "$f")
    : >"$pd/stub_log"
    run_step "$j" "$s" "$pd" "runner.temp=$pd/rt" "github.workspace=$pd" secrets.BOT_GITHUB_TOKEN=BOT0 "$@" >/dev/null 2>&1
}
# patch_run の git と gh の引数を1行ずつ出す
git_calls() { cut -f3 "$WORK/patch/stub_log"; }
# 使い方: final_bad <ジョブ>
# ジョブの final の手順を、final.patch の SHA-256 が verify の出力と同じときと違うときで動かし、
# 同じときに通って final.patch を当て、違うときに失敗するのでなければ、外れの名前を出す
final_bad() {
    local j=$1 h e
    h=$(printf 'F\n' | sha256sum | cut -d' ' -f1)
    [ -n "$(patch_paths "$j" final final.patch)" ] || { echo " パス"; return; }
    patch_run "$j" final final.patch $'F\n' "needs.verify.outputs.final_sha256=$h" inputs.kind=container inputs.key=KEY0
    e=$?
    { [ "$e" -eq 0 ] && git_calls | grep -E '(^| )apply( |$)' | grep -q 'final\.patch'; } || echo " 同じSHA-256"
    patch_run "$j" final final.patch $'F\n' "needs.verify.outputs.final_sha256=0000" inputs.kind=container inputs.key=KEY0
    case "$?" in 0 | 97 | 98 | 99) echo " 違うSHA-256" ;; esac
}

# cooldown の判定の手順を動かすフォルダを作り、パスを出す。3つの判定のスクリプトは、
# 今のフォルダと引数と環境変数を stub_log に書き、stub_rc に書いた数で終わる偽のスクリプトに差し替える
judge_tree() {
    local d s
    d=$(stub_tree judge .github/scripts/check-dependency-cooldown.sh .github/scripts/check-go-release-age.sh \
        .github/scripts/check-ci-tool-release-age.sh .github/scripts/install-verified-node.sh .github/scripts/install-verified-trivy.sh \
        .github/scripts/install-verified-codex.sh .github/scripts/install-verified-terraform.sh) || return 1
    cp "$HERE/lib-claude-auto-fix.sh" "$d/.github/scripts/" || return 1
    echo "$d"
}

# 使い方: judge_outcomes <judge_tree のフォルダ>
# 標準入力の行「judge_npm の rc、judge_go の rc、judge_ci_tool の rc、judge_ci_signature の outcome、期待」ごとに
# judge の手順を動かし、期待と違った行を出す。期待の fail は手順が失敗すること。rc の - は空の値
judge_outcomes() {
    local jd=$1 a b c sg exp e got
    while read -r a b c sg exp; do
        [ -n "$a" ] || continue
        [ "$a" != - ] || a=""
        : >"$jd/out"
        run_step cooldown-judge judge "$jd" "steps.judge_npm.outputs.rc=$a" "steps.judge_go.outputs.rc=$b" \
            "steps.judge_ci_tool.outputs.rc=$c" "steps.judge_ci_signature.outcome=$sg" >/dev/null 2>&1
        e=$?
        got=$(sed -n 's/^result=//p' "$jd/out")
        case "$exp:$e" in
        fail:0 | fail:98 | fail:99) echo "$a,$b,$c,$sg" ;;
        fail:*) ;;
        *:0) [ "$got" = "$exp" ] || echo "$a,$b,$c,$sg" ;;
        *) echo "$a,$b,$c,$sg" ;;
        esac
    done
}

# verify-image の scan_check の手順を動かすフォルダを作り、パスを出す。check-container-scan.sh は、
# 1つ目と3つ目の引数の絶対のパスと、2つ目と4つ目の引数をタブで区切って stub_log に1行足し、
# 1つ目の引数が stub_hit に書いたパスなら stub_det の中身を、ほかは [] を6つ目の引数のファイルに書き、
# 5つ目の引数のファイルに [] を書いて、stub_rc に書いた数で終わる偽のスクリプトに差し替える
scan_tree() {
    local d="$WORK/scan"
    rm -rf "$d" && mkdir -p "$d/.github/scripts" "$d/rt" || return 1
    cat >"$d/.github/scripts/check-container-scan.sh" <<'EOF'
#!/usr/bin/env bash
p=$(realpath -m "$1")
printf '%s\t%s\t%s\t%s\n' "$p" "$2" "$(realpath -m "$3")" "$4" >>"$GITHUB_WORKSPACE/stub_log"
if [ "$p" = "$(cat "$GITHUB_WORKSPACE/stub_hit")" ]; then cat "$GITHUB_WORKSPACE/stub_det" >"$6"; else echo '[]' >"$6"; fi
echo '[]' >"$5"
exit "$(cat "$GITHUB_WORKSPACE/stub_rc")"
EOF
    echo "$d"
}

# 使い方: scan_path <scan_tree のフォルダ> <canon_path でそろえたパス>
# ワークフローの中のパスを、scan_tree のフォルダの中の絶対のパスにして出す
scan_path() {
    case "$2" in
    RUNNER_TEMP/*) echo "$1/rt/${2#RUNNER_TEMP/}" ;;
    /*) echo "$2" ;;
    *) echo "$1/$2" ;;
    esac
}

# 使い方: scan_run <scan_tree のフォルダ> <偽のスクリプトの終わり方> <脆弱性を出すファイルの絶対のパスか -> <出す脆弱性の ID>
# 入力 key を CVE-2099-0001 にして scan_check の手順を動かし、手順の終わり方で終わる
scan_run() {
    local sd=$1
    echo "$2" >"$sd/stub_rc"
    echo "$3" >"$sd/stub_hit"
    printf '[{"id":"%s","severity":"HIGH","pkgName":"p","installedVersion":"1","fixedVersion":"2"}]\n' "$4" >"$sd/stub_det"
    : >"$sd/stub_log"
    run_step verify-image scan_check "$sd" "inputs.key=CVE-2099-0001" "runner.temp=$sd/rt" "github.workspace=$sd" >/dev/null 2>&1
}

TARGET_JOBS='["prepare","edit","verify","verify-image","cooldown-push","cooldown-generate","cooldown-submit","cooldown-judge","ship","report","cleanup"]'
RESULT_JOBS=(prepare edit verify verify-image cooldown-push cooldown-generate cooldown-submit cooldown-judge ship)
# 専用のブランチの実行だけで動くジョブの if が、括弧の外の && の項として持つ条件(正規化した形)
RUN_REF="github.ref=='refs/heads/claude-auto-fix/run'"

# ---------------------------------------------------------------------
# 対象ごとのワークフロー
# ---------------------------------------------------------------------

if want target_on; then
    check "きっかけは workflow_dispatch だけである" "$(jq '(.on | keys) == ["workflow_dispatch"]' "$TJ")"
    # head は、reason が red-check のときに、後始末のスクリプトが PR の head の SHA の先頭12文字を渡す入力である。
    # 表示名の末尾の @<head の SHA の先頭12文字> は、入力からしか作れないため、設計の6つの入力に足した
    check "入力は kind key reason pr checks detail head の7つである" \
        "$(jq '(.on.workflow_dispatch.inputs // {} | keys) == ["checks","detail","head","key","kind","pr","reason"]' "$TJ")"
    check "入力 head は省いてよく、既定は空である" \
        "$(jq '(.on.workflow_dispatch.inputs.head // {}) as $h | ($h.required // false | tostring) == "false" and ($h.default // "") == ""' "$TJ")"
    rn=$(jq -r '."run-name" // ""' "$TJ")
    check "表示名に claude-auto-fix と kind と key と red-check の扱いと、red-check のときの pr と head がある" \
        "$(if has "$rn" "claude-auto-fix" && has "$rn" "inputs.kind" && has "$rn" "inputs.key" && has "$rn" "red-check" && has "$rn" "inputs.pr" && has "$rn" "inputs.head"; then echo true; else echo false; fi)"
    # 後始末のスクリプトは、lib-claude-auto-fix.sh の target_names が作る表示名
    # 「claude-auto-fix <kind> <key> pr#<pr>@<head>」で同じ実行を探すので、表示名の式の形を1つに決める。
    # 式の中の演算子と括弧と区切りの前後の空白だけを除いて比べる
    rn_norm=$(jq -r '."run-name" // "" | gsub("\\$\\{\\{\\s*"; "${{") | gsub("\\s*\\}\\}"; "}}")
        | gsub("\\s*(?<o>==|&&|\\|\\||,|\\(|\\))\\s*"; .o)' "$TJ")
    check "表示名は claude-auto-fix <kind> <key> で、red-check のときだけ末尾に ' pr#<pr>@<head>' を足す(表示名: $rn)" \
        "$([ "$rn_norm" = "claude-auto-fix \${{inputs.kind}} \${{inputs.key}}\${{inputs.reason=='red-check'&&format(' pr#{0}@{1}',inputs.pr,inputs.head)||''}}" ] && echo true || echo false)"
    check "同時実行の組が claude-auto-fix-target-<kind>-<key> で、動いている実行を止めない" \
        "$(jq '(.concurrency.group // "" | gsub("\\s+"; "")) == "claude-auto-fix-target-${{inputs.kind}}-${{inputs.key}}"
            and (.concurrency["cancel-in-progress"] | tostring) == "false"' "$TJ")"
fi

if want target_permissions; then
    check "ワークフローの既定の権限が無いか contents: read だけである" \
        "$(jq '.permissions == null or .permissions == {} or .permissions == {"contents":"read"}' "$TJ")"
    check "どのジョブも権限を書いている" \
        "$(jq '[.jobs // {} | to_entries[] | select((.value.permissions | type) != "object")] | length == 0' "$TJ")"
    check "prepare の権限" "$(yes_if perm_is "$TJ" prepare \
        '{"contents":"read","issues":"read","pull-requests":"read","checks":"read","security-events":"read","vulnerability-alerts":"read"}')"
    check "edit の権限" "$(yes_if perm_is "$TJ" edit \
        '{"contents":"read","security-events":"read","actions":"read","pull-requests":"read","issues":"read","vulnerability-alerts":"read"}')"
    check "edit に書き込みの権限が無い" \
        "$(jq '(.jobs.edit.permissions // {"x":"write"}) | [.[] | select(. != "read")] | length == 0' "$TJ")"
    check "verify の権限" "$(yes_if perm_is "$TJ" verify '{"contents":"read","security-events":"read"}')"
    check "verify-image の権限" "$(yes_if perm_is "$TJ" verify-image '{"contents":"read"}')"
    check "ship の権限" "$(yes_if perm_is "$TJ" ship '{"contents":"read"}')"
    check "report の権限" "$(yes_if perm_is "$TJ" report \
        '{"contents":"read","issues":"write","pull-requests":"read","actions":"read"}')"
    check "cleanup の権限" "$(yes_if perm_is "$TJ" cleanup '{"actions":"write"}')"
fi

if want target_secrets; then
    all=$(jq -c '.' "$TJ")
    names=$(all_of "$all" 'secrets[^A-Za-z0-9_]?[A-Za-z0-9_]*' | sort -u | tr '\n' ' ')
    bad=$(all_of "$all" 'secrets[^A-Za-z0-9_]?[A-Za-z0-9_]*' |
        grep -vxE 'secrets\.(CLAUDE_CODE_OAUTH_TOKEN|BOT_GITHUB_TOKEN|GITHUB_TOKEN)' | sort -u | tr '\n' ' ')
    check "秘密の値は CLAUDE_CODE_OAUTH_TOKEN と BOT_GITHUB_TOKEN と GITHUB_TOKEN だけである(見つかった: $names)" \
        "$([ -z "$bad" ] && echo true || echo false)"
    rc=$(step_text "$TJ" edit run_claude)
    n_all=$(count_of "$all" CLAUDE_CODE_OAUTH_TOKEN)
    n_rc=$(count_of "$rc" CLAUDE_CODE_OAUTH_TOKEN)
    check "secrets.CLAUDE_CODE_OAUTH_TOKEN は edit ジョブの run_claude の手順にだけ現れる(全体 $n_all、手順 $n_rc)" \
        "$([ "$n_all" -gt 0 ] && [ "$n_all" = "$n_rc" ] && echo true || echo false)"
    check "run_claude の手順の CLAUDE_CODE_OAUTH_TOKEN は secrets.CLAUDE_CODE_OAUTH_TOKEN である" \
        "$([ "$(step_env "$TJ" edit run_claude CLAUDE_CODE_OAUTH_TOKEN)" = secrets.CLAUDE_CODE_OAUTH_TOKEN ] && echo true || echo false)"
    sh=$(step_text "$TJ" ship ship)
    n_all=$(count_of "$all" BOT_GITHUB_TOKEN)
    n_sh=$(count_of "$sh" BOT_GITHUB_TOKEN)
    n_cp=$(count_of "$(step_text "$TJ" cooldown-push final)" BOT_GITHUB_TOKEN)
    check "secrets.BOT_GITHUB_TOKEN は ship ジョブの ship の手順と cooldown-push ジョブの final の手順にだけ現れる(全体 $n_all、ship $n_sh、cooldown-push $n_cp)" \
        "$([ "$n_sh" -gt 0 ] && [ "$n_cp" -gt 0 ] && [ "$n_all" = "$((n_sh + n_cp))" ] && echo true || echo false)"
    check "ship と cooldown-push の手順の GH_TOKEN は secrets.BOT_GITHUB_TOKEN である" \
        "$([ "$(step_env "$TJ" ship ship GH_TOKEN)" = secrets.BOT_GITHUB_TOKEN ] && [ "$(step_env "$TJ" cooldown-push final GH_TOKEN)" = secrets.BOT_GITHUB_TOKEN ] && echo true || echo false)"
    ed=$(job_text "$TJ" edit)
    mt=$(step_text "$TJ" edit materials)
    n_ed=$(token_count "$ed")
    n_mt=$(token_count "$mt")
    check "edit ジョブでは GITHUB_TOKEN を materials の手順にだけ渡す(ジョブ $n_ed、手順 $n_mt)" \
        "$([ "$n_mt" -gt 0 ] && [ "$n_ed" = "$n_mt" ] && echo true || echo false)"
    n_vi=$(token_count "$(job_text "$TJ" verify-image)")
    n_sj=$(token_count "$(job_text "$TJ" ship)")
    n_cj=$(token_count "$(job_text "$TJ" cooldown-push)")
    check "verify-image と ship と cooldown-push に GITHUB_TOKEN を渡さない(verify-image $n_vi、ship $n_sj、cooldown-push $n_cj)" \
        "$([ "$n_vi" = 0 ] && [ "$n_sj" = 0 ] && [ "$n_cj" = 0 ] && echo true || echo false)"
    check "ワークフローとジョブの env に秘密の値とトークンが無い" \
        "$(jq '[.env, (.jobs // {} | .[] | .env)] | tojson | test("secrets|github\\.token") | not' "$TJ")"
    check "prepare edit verify verify-image ship の checkout が persist-credentials: false である" \
        "$(jq '[.jobs | (.prepare, .edit, .verify, ."verify-image", .ship) | .steps[]?
            | select((.uses // "") | startswith("actions/checkout@"))] as $c
            | ($c | length) > 0 and all($c[]; (.with["persist-credentials"] | tostring) == "false")' "$TJ")"
    # cooldown-push も checkout の認証を残さず、push の手順で bot の PAT を使う
    check "すべてのジョブの checkout が、cooldown-push と cooldown-generate と cooldown-judge を含めて、persist-credentials: false である" \
        "$(jq 'def co: .steps[]? | select((.uses // "") | startswith("actions/checkout@"));
            ([.jobs."cooldown-push" | co] | length) > 0 and ([.jobs."cooldown-generate" | co] | length) > 0 and ([.jobs."cooldown-judge" | co] | length) > 1
            and all(.jobs[] | co; (.with["persist-credentials"] | tostring) == "false")' "$TJ")"
fi

if want target_order; then
    check "ジョブは ref-check と、prepare から cleanup までの12である" \
        "$(jq --argjson j "$TARGET_JOBS" '(.jobs // {} | keys | sort) == ($j + ["ref-check"] | sort)' "$TJ")"
    check "edit は prepare のあと" "$(yes_if needs_has "$TJ" edit prepare)"
    check "verify は edit のあと" "$(yes_if needs_has "$TJ" verify prepare edit)"
    check "verify-image は verify のあと" "$(yes_if needs_has "$TJ" verify-image prepare verify)"
    check "cooldown-push は verify と verify-image のあと" "$(yes_if needs_has "$TJ" cooldown-push prepare verify verify-image)"
    check "cooldown-generate は cooldown-push のあと" "$(yes_if needs_has "$TJ" cooldown-generate cooldown-push)"
    check "cooldown-submit は cooldown-generate のあと" "$(yes_if needs_has "$TJ" cooldown-submit cooldown-push cooldown-generate)"
    check "cooldown-judge は cooldown-submit のあと" "$(yes_if needs_has "$TJ" cooldown-judge prepare cooldown-push cooldown-submit)"
    check "ship は verify と verify-image と cooldown-judge のあと" \
        "$(yes_if needs_has "$TJ" ship prepare verify verify-image cooldown-judge)"
    check "report は prepare から ship までのすべてのあと" "$(yes_if needs_has "$TJ" report "${RESULT_JOBS[@]}")"
    check "cleanup は report のあと" "$(yes_if needs_has "$TJ" cleanup report)"
    i=$(job_if "$TJ" cooldown-push)
    check "cooldown-push は、verify が ok で cooldown が true で、verify-image が通ったか飛ばされたときだけ動く" \
        "$(if conj_has "$i" "!cancelled()" && conj_has "$i" "needs.verify.outputs.outcome=='ok'" && conj_has "$i" "needs.verify.outputs.cooldown=='true'" && conj_has_or "$i" "needs.verify-image.result=='success'" "needs.verify-image.result=='skipped'"; then echo true; else echo false; fi)"
    check "cooldown-generate は cooldown-push が通ったときだけ動く" \
        "$(yes_if conj_has "$(job_if "$TJ" cooldown-generate)" "needs.cooldown-push.result=='success'")"
    check "cooldown-submit は cooldown-generate が通ったときだけ動く" \
        "$(yes_if conj_has "$(job_if "$TJ" cooldown-submit)" "needs.cooldown-generate.result=='success'")"
    check "cooldown-judge は cooldown-push が通ったときに動く" \
        "$(yes_if conj_has "$(job_if "$TJ" cooldown-judge)" "needs.cooldown-push.result=='success'")"
    i=$(job_if "$TJ" ship)
    check "ship は、verify が ok で、verify-image が通ったか飛ばされ、cooldown が要らないか cooldown-judge が ship を出したときだけ動く" \
        "$(if conj_has "$i" "!cancelled()" && conj_has "$i" "needs.verify.outputs.outcome=='ok'" && conj_has_or "$i" "needs.verify-image.result=='success'" "needs.verify-image.result=='skipped'" && conj_has_or "$i" "needs.verify.outputs.cooldown!='true'" "needs.cooldown-judge.outputs.result=='ship'"; then echo true; else echo false; fi)"
    bad=""
    for j in cooldown-push cooldown-generate cooldown-submit cooldown-judge; do job_if_ok "$(job_if "$TJ" "$j")" || bad="$bad $j"; done
    check "cooldown の4つのジョブの if が always() と failure() を使わず、括弧の外に || が無く、cancelled() を !cancelled() の && の項としてだけ使う(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    check "cooldown の4つのジョブの打ち切りは20分である" \
        "$(jq '[.jobs | (."cooldown-push", ."cooldown-generate", ."cooldown-submit", ."cooldown-judge") | ."timeout-minutes" | tostring] == ["20","20","20","20"]' "$TJ")"
fi

if want target_skip_to_report; then
    check "prepare の outcome は prepare の手順の出力である" \
        "$(yes_if has "$(jq -r "$JQ_NORM"' .jobs.prepare.outputs.outcome | norm' "$TJ")" "steps.prepare.outputs.outcome")"
    check "edit の outcome は run_claude の手順の出力である" \
        "$(yes_if has "$(jq -r "$JQ_NORM"' .jobs.edit.outputs.outcome | norm' "$TJ")" "steps.run_claude.outputs.outcome")"
    check "edit は prepare が結果を出さなかったときだけ動く" "$(yes_if conj_has "$(job_if "$TJ" edit)" "needs.prepare.outputs.outcome==''")"
    check "verify は edit が ok を出したときだけ動く" "$(yes_if conj_has "$(job_if "$TJ" verify)" "needs.edit.outputs.outcome=='ok'")"
    i=$(job_if "$TJ" verify-image)
    check "verify-image は種類が container で verify が ok を出したときだけ動く" \
        "$(if conj_has "$i" "inputs.kind=='container'" && conj_has "$i" "needs.verify.outputs.outcome=='ok'"; then echo true; else echo false; fi)"
    check "ship は verify が ok を出したときだけ動く" "$(yes_if conj_has "$(job_if "$TJ" ship)" "needs.verify.outputs.outcome=='ok'")"
    # verify の check の手順が ok を出したあとに、CodeQL の手順か confirm の手順が失敗するか、ジョブが打ち切られると、
    # verify の出力 outcome は ok のまま残る。ship の if は !cancelled() を持つので、ジョブの結果も別に読む
    check "ship は verify ジョブが通ったときだけ動く" "$(yes_if conj_has "$(job_if "$TJ" ship)" "needs.verify.result=='success'")"
    # cooldown-judge は、出力 result が ship でも、ブランチを消せないかスナップショットを送れていないと失敗する
    check "ship は、cooldown が要らないか cooldown-judge ジョブが通ったときだけ動く" \
        "$(yes_if conj_has_or "$(job_if "$TJ" ship)" "needs.verify.outputs.cooldown!='true'" "needs.cooldown-judge.result=='success'")"
    bad=""
    for j in edit verify verify-image; do
        case "$(job_if "$TJ" "$j")" in *"()"*) bad="$bad $j" ;; esac
    done
    check "edit verify verify-image の if は状態の関数を使わず、前のジョブがすべて通ったときだけ動く(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    bad=""
    for j in edit verify verify-image ship; do job_if_ok "$(job_if "$TJ" "$j")" || bad="$bad $j"; done
    check "edit verify verify-image ship の if が always() と failure() を使わず、括弧の外に || が無く、cancelled() を !cancelled() の && の項としてだけ使う(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    check "report の if が always() と github.ref == 'refs/heads/claude-auto-fix/run' を && でつないだ形である(if: $(job_if "$TJ" report))" \
        "$(yes_if conj_is "$(job_if "$TJ" report)" "always()" "$RUN_REF")"
    check "report は prepare edit verify verify-image ship のあと" "$(yes_if needs_has "$TJ" report prepare edit verify verify-image ship)"
fi

if want target_base; then
    # 使い方: base_run <inputs.reason> <base.patch の中身> <base_sha256>。$j の base の手順を patch_run で動かす
    base_run() {
        patch_run "$j" base base.patch "$2" "inputs.reason=$1" needs.prepare.outputs.base_sha=BASE0 needs.prepare.outputs.main_sha=MAIN0 \
            "needs.prepare.outputs.base_sha256=$3"
    }
    for jb in edit:materials verify:apply verify-image:final cooldown-push:final ship:ship; do
        j=${jb%%:*}
        s=${jb#*:}
        bi=$(step_idx "$TJ" "$j" base)
        si=$(step_idx "$TJ" "$j" "$s")
        bad=""
        hp=$(printf 'P\n' | sha256sum | cut -d' ' -f1)
        he=$(printf '' | sha256sum | cut -d' ' -f1)
        [ -n "$(patch_paths "$j" base base.patch)" ] || bad="$bad パス"
        base_run trigger $'P\n' "$hp"
        e=$?
        g=$(git_calls)
        { [ "$e" -eq 0 ] && grep -q MAIN0 <<<"$g" && ! grep -q BASE0 <<<"$g" &&
            awk '/MAIN0/ { m = NR } /(^| )apply( |$)/ && /base\.patch/ && m && NR > m { a = 1 } END { exit !a }' <<<"$g"; } || bad="$bad trigger"
        base_run red-check '' "$he"
        e=$?
        g=$(git_calls)
        { [ "$e" -eq 0 ] && grep -q BASE0 <<<"$g" && ! grep -q MAIN0 <<<"$g"; } || bad="$bad red-check"
        for r in trigger red-check; do
            base_run "$r" $'P\n' 0000
            case "$?" in 0 | 97 | 98 | 99) bad="$bad $r:SHA-256の違いを見逃す" ;; esac
        done
        check "$j の base の手順が red-check では base_sha を、そのほかでは main_sha を checkout して base.patch を当て、SHA-256 が base_sha256 と違えば失敗する(外れ:${bad:- なし})" \
            "$([ -z "$bad" ] && echo true || echo false)"
        check "$j の base の手順は $s の手順より前にある" "$([ "$bi" -ge 0 ] && [ "$si" -gt "$bi" ] && echo true || echo false)"
    done
fi

if want target_tests_first; then
    # どのジョブでも、claude-auto-fix-<名前>.sh を呼ぶ手順の前に、tests/test-claude-auto-fix-<名前>.sh を流す手順がある
    jq -r '.jobs // {} | to_entries[] | .key as $j | (.value.steps // []) | to_entries[]
        | "\($j)\t\(.key)\t\(.value.run // "" | gsub("\n"; " "))"' "$TJ" >"$WORK/runs.tsv"
    miss=$(perl -F'\t' -lane '
        my ($j, $i, $r) = @F; $r //= "";
        while ($r =~ /tests\/test-claude-auto-fix-([a-z-]+)\.sh/g) { $t{"$j $1"} //= $i }
        while ($r =~ /(?<![-\w])claude-auto-fix-([a-z-]+)\.sh/g) { push @c, [$j, $i, $1] }
        END { for (@c) { my ($j, $i, $n) = @$_; my $k = "$j $n"; print "$j:$n" unless defined $t{$k} && $t{$k} < $i } }
    ' "$WORK/runs.tsv" | sort -u | tr '\n' ' ')
    calls=$(grep -cE '(^|[^-[:alnum:]_])claude-auto-fix-[a-z-]+\.sh' "$WORK/runs.tsv")
    check "スクリプトを呼ぶ前にそのテストを流す(足りない: ${miss:-なし})" \
        "$([ -z "$miss" ] && [ "$calls" -gt 0 ] && echo true || echo false)"
    # 今ある検査のスクリプトも、呼ぶジョブの中で、呼ぶ手順より前の手順でそのテストを流す
    miss=$(perl -F'\t' -lane '
        my ($j, $i, $r) = @F; $r //= "";
        my $n = qr/check-(?:trivy-version|container-scan|dependency-snapshot|dependency-cooldown|go-release-age|ci-tool-release-age)/;
        while ($r =~ /(?<![-\w])test-($n)\.sh/g) { $t{"$j $1"} //= $i }
        while ($r =~ /(?<![-\w])($n)\.sh/g) { push @c, [$j, $i, $1] }
        END { for (@c) { my ($j, $i, $n) = @$_; my $k = "$j $n"; print "$j:$n" unless defined $t{$k} && $t{$k} < $i } }
    ' "$WORK/runs.tsv" | sort -u | tr '\n' ' ')
    check "check-trivy-version.sh などの今ある検査のスクリプトも、呼ぶ前にそのテストを流す(足りない: ${miss:-なし})" \
        "$([ -z "$miss" ] && echo true || echo false)"
fi

if want target_prepare_trivy; then
    pj=$(job_text "$TJ" prepare)
    check "prepare の prepare の手順が claude-auto-fix-prepare.sh を呼ぶ" "$(yes_if has "$(step_text "$TJ" prepare prepare)" "claude-auto-fix-prepare.sh")"
    td=$(step_env "$TJ" prepare prepare TRIVY_RESULTS_DIR)
    check "prepare の手順に TRIVY_RESULTS_DIR を渡す" "$([ -n "$td" ] && [ "$td" != null ] && echo true || echo false)"
    check "種類が container のとき、ランナーが ubuntu-24.04-arm で、2つの本番の Dockerfile から linux/arm64 で組み立てる" \
        "$(if [ "$(subst_expr "$(jq -r ".jobs.prepare.\"runs-on\" // \"\"" "$TJ")" inputs.kind=container)" = ubuntu-24.04-arm ] && arm_builds prepare docker/backend/Dockerfile.prod docker/backend-go/Dockerfile.prod && has "$pj" "verified-trivy"; then echo true; else echo false; fi)"
    pv=$(jq -r '[.jobs.prepare.steps[]? | (.uses // "" | test("verified-trivy"))] | index(true) // -1' "$TJ")
    check "prepare で、verified-trivy の手順が、Trivy で調べる scan の手順より前にある" \
        "$([ "$pv" -ge 0 ] && [ "$pv" -lt "$(step_idx "$TJ" prepare scan)" ] && echo true || echo false)"
    check "2つのイメージを、文脈 ./backend で組み立てる" \
        "$(if [ "$(build_ctx prepare docker/backend/Dockerfile.prod)" = backend ] && [ "$(build_ctx prepare docker/backend-go/Dockerfile.prod)" = backend ]; then echo true; else echo false; fi)"
    tdir=$(canon_path "$(jq -r '.jobs.prepare.steps[]? | select(.id == "prepare") | .env.TRIVY_RESULTS_DIR // ""' "$TJ")")
    touts=$(trivy_outputs prepare | while IFS= read -r p; do canon_path "$p"; echo; done | sort | tr '\n' ' ')
    check "Trivy の結果を、TRIVY_RESULTS_DIR の最上位の trivy-java.json と trivy-go.json に書く(書く先: ${touts:-なし})" \
        "$(if [ -n "$tdir" ] && [ "$touts" = "$tdir/trivy-go.json $tdir/trivy-java.json " ]; then echo true; else echo false; fi)"
    check "docker/backend/Dockerfile.prod のイメージの結果を trivy-java.json に、docker/backend-go/Dockerfile.prod のイメージの結果を trivy-go.json に書く" \
        "$(if [ -n "$tdir" ] && [ "$(trivy_out_of prepare docker/backend/Dockerfile.prod)" = "$tdir/trivy-java.json" ] && [ "$(trivy_out_of prepare docker/backend-go/Dockerfile.prod)" = "$tdir/trivy-go.json" ]; then echo true; else echo false; fi)"
    check "成果物 trivy-results を保存の期間1日で、種類が container のときに上げる" \
        "$(if [ "$(step_with "$TJ" prepare upload_trivy name)" = trivy-results ] && [ "$(step_with "$TJ" prepare upload_trivy retention-days)" = 1 ] && has "$(step_if "$TJ" prepare upload_trivy)" "inputs.kind=='container'" && has "$(jq -r ".jobs.prepare.steps[]? | select(.id == \"upload_trivy\") | .uses // \"\"" "$TJ")" "actions/upload-artifact@"; then echo true; else echo false; fi)"
    check "成果物のフォルダは TRIVY_RESULTS_DIR と同じで、2つのファイルが最上位にある" \
        "$([ -n "$td" ] && [ "$(step_with "$TJ" prepare upload_trivy path)" = "$td" ] && echo true || echo false)"
fi

if want target_edit; then
    check "種類が container のとき、成果物 trivy-results を受け取る" \
        "$(if [ "$(step_with "$TJ" edit download_trivy name)" = trivy-results ] && has "$(step_if "$TJ" edit download_trivy)" "inputs.kind=='container'"; then echo true; else echo false; fi)"
    td=$(step_env "$TJ" edit materials TRIVY_RESULTS_DIR)
    check "materials の手順に、受け取ったフォルダを TRIVY_RESULTS_DIR で渡す" \
        "$([ -n "$td" ] && [ "$td" != null ] && [ "$(step_with "$TJ" edit download_trivy path)" = "$td" ] && echo true || echo false)"
    mt=$(step_text "$TJ" edit materials)
    md=$(stub_tree materials .github/scripts/claude-auto-fix-materials.sh)
    bad=""
    for k in dependabot codeql container; do
        : >"$md/stub_log"
        run_step edit materials "$md" "inputs.kind=$k" inputs.key=KEY0 inputs.reason=trigger inputs.pr= inputs.checks=ICHECKS0 \
            inputs.detail=DETAIL0 needs.prepare.outputs.checks=PCHECKS0 github.token=TOKEN0 "runner.temp=$md/rt" "github.workspace=$md" >/dev/null 2>&1
        e=$?
        ar=$(cut -f3 "$md/stub_log")
        want_c=ICHECKS0 not_c=PCHECKS0
        [ "$k" != dependabot ] || { want_c=PCHECKS0 not_c=ICHECKS0; }
        { [ "$e" -eq 0 ] && [ "$(wc -l <"$md/stub_log")" -eq 1 ] && [ "$(cut -f1 "$md/stub_log")" = claude-auto-fix-materials.sh ] &&
            grep -qw "$want_c" <<<"$ar" && ! grep -qw "$not_c" <<<"$ar"; } || bad="$bad $k"
    done
    check "materials の手順が、種類が dependabot のときは prepare の出力 checks を、ほかでは入力 checks を claude-auto-fix-materials.sh に渡す(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    check "materials の手順が claude-auto-fix-materials.sh を、run_claude の手順が claude-auto-fix-run-claude.sh を、この順に呼ぶ" \
        "$(if has "$mt" "claude-auto-fix-materials.sh" && has "$(step_text "$TJ" edit run_claude)" "claude-auto-fix-run-claude.sh" && [ "$(step_idx "$TJ" edit run_claude)" -gt "$(step_idx "$TJ" edit materials)" ] && [ "$(step_idx "$TJ" edit materials)" -ge 0 ]; then echo true; else echo false; fi)"
    check "verified-claude で CLI を入れる" "$(yes_if has "$(job_text "$TJ" edit)" "verified-claude")"
fi

if want target_verify_order; then
    # 手順の id から段を決め、段が順に並ぶことを確かめる
    order=$(jq -r '[.jobs.verify.steps[]?.id // ""
        | if . == "alert" then 0 elif startswith("rebuild_tools") then 1 elif . == "apply" then 2
          elif startswith("area_tools") then 3 elif . == "check" then 4 elif startswith("codeql_") then 5
          elif . == "confirm" then 6 else empty end] | map(tostring) | join(" ")' "$TJ")
    check "手順が alert、作り直しの道具、apply、変わった領域の道具、check、CodeQL、confirm の順に並ぶ(段: $order)" \
        "$(jq -n --arg o "$order" '($o | split(" ") | map(select(. != "") | tonumber)) as $a
            | ($a | length) > 0 and $a == ($a | sort) and ([range(0; 7)] - $a | length) == 0')"
    bad=""
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        i=$(step_if "$TJ" verify "$s")
        case "$s" in
        area_tools*) p="steps.apply.outputs.outcome==''" ;;
        codeql_*) p="steps.check.outputs.outcome=='ok'" ;;
        esac
        if [ "$i" != "$p" ] && [ "${i#"$p"&&}" = "$i" ]; then bad="$bad $s"; continue; fi
        no_top_or "$i" || { bad="$bad $s"; continue; }
        case "$i" in *'always()'* | *'cancelled()'* | *'failure()'*) bad="$bad $s" ;; esac
        case "$s" in codeql_*) has "$i" "inputs.kind=='codeql'" || bad="$bad $s" ;; esac
    done < <(jq -r '.jobs.verify.steps[]?.id // "" | select(startswith("area_tools") or startswith("codeql_"))' "$TJ")
    check "変わった領域の道具は apply が通ったときだけ、CodeQL は check が ok で種類が codeql のときだけ動く(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    check "check は apply が通ったときだけ動く" "$([ "$(step_if "$TJ" verify check)" = "steps.apply.outputs.outcome==''" ] && echo true || echo false)"
    check "confirm は check が ok を出したときだけ動く" "$([ "$(step_if "$TJ" verify confirm)" = "steps.check.outputs.outcome=='ok'" ] && echo true || echo false)"
    check "alert は種類が codeql のときだけ動く" "$([ "$(step_if "$TJ" verify alert)" = "inputs.kind=='codeql'" ] && echo true || echo false)"
    check "apply は if を持たず、いつも動く" "$([ "$(step_idx "$TJ" verify apply)" -ge 0 ] && [ -z "$(step_if "$TJ" verify apply)" ] && echo true || echo false)"
    check "apply check confirm の手順が claude-auto-fix-verify.sh のそれぞれの形を呼ぶ" \
        "$(if has "$(step_text "$TJ" verify apply)" "claude-auto-fix-verify.sh apply" && has "$(step_text "$TJ" verify check)" "claude-auto-fix-verify.sh check" && has "$(step_text "$TJ" verify confirm)" "claude-auto-fix-verify.sh confirm"; then echo true; else echo false; fi)"
fi

if want target_verify_outputs; then
    out() { jq -r --arg o "$1" "$JQ_NORM"' .jobs.verify.outputs[$o] | norm' "$TJ"; }
    check "出力 outcome は、最後に動いた形の outcome である" \
        "$([ "$(out outcome)" = "steps.confirm.outputs.outcome||steps.check.outputs.outcome||steps.apply.outputs.outcome" ] && echo true || echo false)"
    check "出力 cooldown は apply の手順の出力である" "$([ "$(out cooldown)" = "steps.apply.outputs.cooldown" ] && echo true || echo false)"
    check "出力 final_sha256 は apply の手順の出力 sha256 である" "$([ "$(out final_sha256)" = "steps.apply.outputs.sha256" ] && echo true || echo false)"
fi

if want target_verify_codeql; then
    al=$(step_text "$TJ" verify alert)
    check "alert は verify ジョブの最初の手順である" "$([ "$(step_idx "$TJ" verify alert)" = 0 ] && echo true || echo false)"
    ad=$(stub_tree alert bin/gh)
    echo '{"number":7,"state":"open","rule":{"id":"R0"},"most_recent_instance":{"category":"C0","location":{"path":"P0"}}}' >"$ad/gh_json"
    run_step verify alert "$ad" inputs.key=7 inputs.kind=codeql github.token=TOKEN0 "runner.temp=$ad/rt" "github.workspace=$ad" >/dev/null 2>&1
    e=$?
    check "alert が、入力 key の警告の rule_id と path と category を \$RUNNER_TEMP/codeql-alert.json に書く" \
        "$(if [ "$e" -eq 0 ] && grep -q 'code-scanning/alerts/7\( \|$\)' <(cut -f3 "$ad/stub_log") && [ "$(cut -f6 "$ad/stub_log" | sort -u)" = TOKEN0 ] &&
            jq -e '{rule_id, path, category} == {"rule_id":"R0","path":"P0","category":"C0"}' "$ad/rt/codeql-alert.json" >/dev/null 2>&1 &&
            [ "$(find "$ad/rt" -type f | wc -l)" -eq 1 ]; then echo true; else echo false; fi)"
    vj=$(job_text "$TJ" verify)
    n_vj=$(token_count "$vj")
    n_al=$(token_count "$al")
    check "verify ジョブでは GITHUB_TOKEN を alert の手順にだけ渡す(ジョブ $n_vj、手順 $n_al)" \
        "$([ "$n_al" -gt 0 ] && [ "$n_vj" = "$n_al" ] && echo true || echo false)"
    cq_init=$(jq -r 'first(.jobs[]?.steps[]? | .uses // "" | select(startswith("github/codeql-action/init@"))) // "none"' "$CJ")
    cq_an=$(jq -r 'first(.jobs[]?.steps[]? | .uses // "" | select(startswith("github/codeql-action/analyze@"))) // "none"' "$CJ")
    check "codeql_init が codeql.yaml と同じ版の init に source-root: target を渡す" \
        "$(if [ "$(step_with "$TJ" verify codeql_init source-root)" = target ] && [ "$(jq -r ".jobs.verify.steps[]? | select(.id == \"codeql_init\") | .uses" "$TJ")" = "$cq_init" ]; then echo true; else echo false; fi)"
    check "codeql_build が working-directory: target で動く" \
        "$([ "$(jq -r '.jobs.verify.steps[]? | select(.id == "codeql_build") | ."working-directory" // ""' "$TJ")" = target ] && echo true || echo false)"
    sarif=$(step_with "$TJ" verify codeql_analyze output)
    # checkout_path は ${{ }} の後ろに文字が続くため、正規化せずに空白だけを除いて比べる
    cpath=$(jq -r '.jobs.verify.steps[]? | select(.id == "codeql_analyze") | .with.checkout_path // "" | gsub("\\s+"; "")' "$TJ")
    check "codeql_analyze が codeql.yaml と同じ版の analyze に checkout_path: target のパスを渡し、上げずに SARIF を書く" \
        "$(if [ "$cpath" = "\${{github.workspace}}/target" ] && [ "$(step_with "$TJ" verify codeql_analyze upload)" = never ] && [ "$(step_with "$TJ" verify codeql_analyze upload-database)" = false ] && has "$sarif" "codeql-sarif" && [ "$(jq -r ".jobs.verify.steps[]? | select(.id == \"codeql_analyze\") | .uses" "$TJ")" = "$cq_an" ]; then echo true; else echo false; fi)"
    check "init、ビルド、analyze の順に並ぶ" \
        "$(if [ "$(step_idx "$TJ" verify codeql_init)" -ge 0 ] && [ "$(step_idx "$TJ" verify codeql_build)" -gt "$(step_idx "$TJ" verify codeql_init)" ] && [ "$(step_idx "$TJ" verify codeql_analyze)" -gt "$(step_idx "$TJ" verify codeql_build)" ]; then echo true; else echo false; fi)"
    check "confirm に CODEQL_SARIF_DIR として analyze の出力のフォルダを渡す" \
        "$([ -n "$sarif" ] && [ "$(step_env "$TJ" verify confirm CODEQL_SARIF_DIR)" = "$sarif" ] && echo true || echo false)"
fi

if want target_verify_checkout; then
    check "target/ を fetch-depth: 0 で1回だけ checkout する" \
        "$(jq '[.jobs.verify.steps[]? | select((.uses // "" | startswith("actions/checkout@")) and .with.path == "target")] as $c
            | ($c | length) == 1 and ($c[0].with["fetch-depth"] | tostring) == "0"' "$TJ")"
    ci=$(jq -r '[.jobs.verify.steps[]? | (.uses // "" | startswith("actions/checkout@")) and .with.path == "target"] | index(true) // -1' "$TJ")
    check "target/ の checkout、base、apply の順に並ぶ" \
        "$(if [ "$ci" -ge 0 ] && [ "$(step_idx "$TJ" verify base)" -gt "$ci" ] && [ "$(step_idx "$TJ" verify apply)" -gt "$(step_idx "$TJ" verify base)" ]; then echo true; else echo false; fi)"
    check "依存のキャッシュを保存しない" \
        "$(jq '[.jobs.verify.steps[]? | select(
            (.uses // "" | test("^actions/cache(/save)?@"))
            or ((.uses // "" | startswith("actions/setup-go@")) and ((.with.cache | tostring) != "false"))
            or ((.with.cache // false | tostring) as $c | $c != "false" and $c != ""))] | length == 0' "$TJ")"
fi

if want target_verify_image; then
    vi=$(job_text "$TJ" verify-image)
    check "ランナーが ubuntu-24.04-arm で、2つの本番の Dockerfile から linux/arm64 で組み立て、Trivy で調べる" \
        "$(if [ "$(jq -r ".jobs.\"verify-image\".\"runs-on\" // \"\"" "$TJ")" = "ubuntu-24.04-arm" ] && arm_builds verify-image target/docker/backend/Dockerfile.prod target/docker/backend-go/Dockerfile.prod && has "$vi" "verified-trivy"; then echo true; else echo false; fi)"
    check "final の手順が final.patch の SHA-256 を verify の出力と比べ、同じときだけ当てる(外れ:$(final_bad verify-image))" \
        "$([ -z "$(final_bad verify-image)" ] && echo true || echo false)"
    check "2つのイメージを、final.patch を当てた target/ の Dockerfile から、文脈 target/backend で組み立てる" \
        "$(if [ "$(build_ctx verify-image target/docker/backend/Dockerfile.prod)" = target/backend ] && [ "$(build_ctx verify-image target/docker/backend-go/Dockerfile.prod)" = target/backend ] && [ -z "$(build_ctx verify-image docker/backend/Dockerfile.prod)" ] && [ -z "$(build_ctx verify-image docker/backend-go/Dockerfile.prod)" ]; then echo true; else echo false; fi)"
    bi=$(jq -r '[.jobs."verify-image".steps[]? | (.run // "" | test("docker\\s+buildx\\s+build"))] | to_entries | map(select(.value) | .key) | map(tostring) | join(" ")' "$TJ")
    fi_=$(step_idx "$TJ" verify-image final)
    si=$(step_idx "$TJ" verify-image scan_check)
    check "イメージを組み立てる手順は final のあと、scan_check の前にある(番号: ${bi:-なし})" \
        "$(jq -n --arg b "$bi" --argjson f "$fi_" --argjson s "$si" '($b | split(" ") | map(select(. != "") | tonumber)) as $a | ($a | length) > 0 and $f >= 0 and ($a | all(. > $f and . < $s))')"
    jtag=$(build_tag verify-image target/docker/backend/Dockerfile.prod)
    gtag=$(build_tag verify-image target/docker/backend-go/Dockerfile.prod)
    tl=$(trivy_lines verify-image)
    jout=$(awk -F'\t' -v t="$jtag" '$2 == t { print $1 }' <<<"$tl")
    gout=$(awk -F'\t' -v t="$gtag" '$2 == t { print $1 }' <<<"$tl")
    check "2つのイメージに別の名前を付け、それぞれを Trivy で1回だけ調べて、別のファイルに結果を書く(java: ${jtag:-なし} → ${jout:-なし}、go: ${gtag:-なし} → ${gout:-なし})" \
        "$(if one_line "$jtag" && one_line "$gtag" && [ "$jtag" != "$gtag" ] && one_line "$jout" && one_line "$gout" && [ "$(canon_path "$jout")" != "$(canon_path "$gout")" ]; then echo true; else echo false; fi)"
    ti=$(jq -r '[.jobs."verify-image".steps[]? | (.run // "" | test("(^|\n|[ \t;&|(])trivy[ \t]"))] | to_entries | map(select(.value) | .key) | map(tostring) | join(" ")' "$TJ")
    vt=$(jq -r '[.jobs."verify-image".steps[]? | (.uses // "" | test("verified-trivy"))] | index(true) // -1' "$TJ")
    check "Trivy で調べる手順は、verified-trivy とイメージを組み立てる手順のあと、scan_check までにある(番号: ${ti:-なし})" \
        "$(jq -n --arg t "$ti" --arg b "$bi" --argjson v "$vt" --argjson s "$si" '($t | split(" ") | map(select(. != "") | tonumber)) as $a | ($b | split(" ") | map(select(. != "") | tonumber)) as $c | ($a | length) > 0 and ($c | length) > 0 and $v >= 0 and ($a | all(. > $v and . >= ($c | max) and . <= $s))')"
    sd=$(scan_tree)
    while IFS= read -r p; do
        [ -z "$p" ] || mkdir -p "$(dirname "$(scan_path "$sd" "$(canon_path "$p")")")"
    done < <(trivy_outputs verify-image)
    ja=$(realpath -m "$(scan_path "$sd" "$(canon_path "$jout")")")
    ga=$(realpath -m "$(scan_path "$sd" "$(canon_path "$gout")")")
    scan_run "$sd" 0 - CVE-2099-0001
    e=$?
    want=$(printf '%s\tarm64\t%s\treport\n' "$ja" "$sd/.github/container-scan-suppressions.json" "$ga" "$sd/.github/container-scan-suppressions.json" | sort)
    check "scan_check の手順が、2つの Trivy の結果ごとに、check-container-scan.sh を arm64 と .github/container-scan-suppressions.json と report で呼ぶ" \
        "$([ "$e" -eq 0 ] && [ "$(sort "$sd/stub_log")" = "$want" ] && echo true || echo false)"
    bad=""
    while read -r rc hit id exp name; do
        [ -n "$rc" ] || continue
        case "$hit" in java) hit=$ja ;; go) hit=$ga ;; esac
        scan_run "$sd" "$rc" "$hit" "$id"
        e=$?
        case "$exp:$e" in
        pass:0 | fail:[1-9] | fail:[1-9][0-9] | fail:[1-9][0-9][0-9]) [ "$e" -ne 98 ] && [ "$e" -ne 99 ] || bad="$bad $name" ;;
        *) bad="$bad $name" ;;
        esac
    done <<'EOF'
1 - CVE-2099-0001 pass 止める脆弱性がほかにある
0 java CVE-2099-00010 pass 似たIDだけがある
0 java CVE-2099-0001 fail javaのイメージにある
0 go CVE-2099-0001 fail goのイメージにある
1 java CVE-2099-0001 fail 止める脆弱性として出る
2 - CVE-2099-0001 fail 結果を読めない
EOF
    check "scan_check の手順が、入力 key と同じ ID の脆弱性が2つのイメージのどちらかに残るときと、結果を読めないときだけ失敗する(違った場合:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
fi

if want target_report_steps; then
    r=$(step_idx "$TJ" report record)
    u=$(step_idx "$TJ" report upload_outcome)
    n=$(step_idx "$TJ" report notify)
    check "record、成果物 outcome を上げる手順、notify の順に並ぶ" "$([ "$r" -ge 0 ] && [ "$u" -gt "$r" ] && [ "$n" -gt "$u" ] && echo true || echo false)"
    check "record の手順が claude-auto-fix-report.sh record を呼び、JOB_RESULTS を受け取る" \
        "$(if has "$(step_text "$TJ" report record)" "claude-auto-fix-report.sh record" && jr=$(step_env "$TJ" report record JOB_RESULTS) && [ -n "$jr" ] && [ "$jr" != null ] && has "$jr" "needs.prepare.result"; then echo true; else echo false; fi)"
    check "upload_outcome の手順が成果物 outcome を、保存の期間7日で上げる" \
        "$(if [ "$(step_with "$TJ" report upload_outcome name)" = outcome ] && [ "$(step_with "$TJ" report upload_outcome retention-days)" = 7 ] && has "$(jq -r ".jobs.report.steps[]? | select(.id == \"upload_outcome\") | .uses // \"\"" "$TJ")" "actions/upload-artifact@"; then echo true; else echo false; fi)"
    # record に渡す OUTCOME は、最も後ろで結果を出したジョブの outcome である。edit と verify の ok は途中の結果なので渡さず、
    # どのジョブも結果を出していなければ空にする(record が JOB_RESULTS から決める)。
    # cooldown-judge の出力 result は、ジョブが通り、blocked のときだけ結果にする(ship は ship に進むこと、fail と
    # ジョブの失敗は、record が JOB_RESULTS から決める)。
    # 1行は「prepare edit verify cooldown-judge の出力 result cooldown-judge のジョブの結果 ship 期待」で、- は空を表す
    oe=$(jq -r '.jobs.report.steps[]? | select(.id == "record") | .env.OUTCOME // ""' "$TJ")
    bad=""
    while read -r p e v c cj s want_o; do
        [ -n "$p" ] || continue
        got=$(subst_expr "$oe" "needs.prepare.outputs.outcome=${p#-}" "needs.edit.outputs.outcome=${e#-}" \
            "needs.verify.outputs.outcome=${v#-}" "needs.cooldown-judge.outputs.result=${c#-}" \
            "needs.cooldown-judge.result=${cj#-}" "needs.ship.outputs.outcome=${s#-}") || got="式を読めない"
        [ "$got" = "${want_o#-}" ] || bad="$bad $p,$e,$v,$c,$cj,$s=>${got:-空}"
    done <<'EOF'
gone - - - skipped - gone
- unavailable - - skipped - unavailable
- key - - skipped - key
- unfixed - - skipped - unfixed
- ok unfixed - skipped - unfixed
- ok blocked - skipped - blocked
- ok ok - skipped - -
- ok ok - skipped pr pr
- ok ok - skipped skipped skipped
- ok ok - skipped unfixed unfixed
- ok - - - - -
- - - - - - -
- ok ok blocked success - blocked
- ok ok blocked failure - -
- ok ok blocked cancelled - -
- ok ok ship success pr pr
- ok ok ship success - -
- ok ok ship failure - -
- ok ok fail failure - -
EOF
    check "record の手順の OUTCOME が、最も後ろで結果を出したジョブの outcome で、edit と verify の ok と cooldown-judge の ship と fail を渡さない(外れ:${bad:- なし})" \
        "$([ -n "$oe" ] && [ "$oe" != null ] && [ -z "$bad" ] && echo true || echo false)"
    rd=$(stub_tree report .github/scripts/claude-auto-fix-report.sh)
    run_step report notify "$rd" needs.edit.outputs.outcome=EO0 steps.record.outputs.result=RR0 inputs.kind=codeql inputs.key=KEY0 \
        github.token=TOKEN0 "runner.temp=$rd/rt" "github.workspace=$rd" >/dev/null 2>&1
    e=$?
    check "notify の手順が、EDIT_OUTCOME に edit の結果を、引数に record の結果を渡して claude-auto-fix-report.sh notify を呼ぶ" \
        "$(if [ "$e" -eq 0 ] && [ "$(wc -l <"$rd/stub_log")" -eq 1 ] && [ "$(cut -f1 "$rd/stub_log")" = claude-auto-fix-report.sh ] &&
            [ "$(cut -f3 "$rd/stub_log" | cut -d' ' -f1-2)" = "notify RR0" ] && [ "$(cut -f10 "$rd/stub_log" | cut -d'|' -f1)" = EO0 ]; then echo true; else echo false; fi)"
fi

if want target_job_results; then
    jr=$(step_env "$TJ" report record JOB_RESULTS)
    miss=""
    for j in "${RESULT_JOBS[@]}"; do
        grep -qE "needs(\\.$j|\\['$j'\\])\\.result" <<<"$jr" || miss="$miss $j"
    done
    check "JOB_RESULTS に、cooldown の4つのジョブを含む prepare から ship までのすべての結果が入る(足りない:${miss:- なし})" \
        "$([ -z "$miss" ] && echo true || echo false)"
    jmaps=()
    for j in "${RESULT_JOBS[@]}"; do jmaps+=("needs.$j.result=r-$j"); done
    jv=$(subst_expr "$(jq -r '.jobs.report.steps[]? | select(.id == "record") | .env.JOB_RESULTS // ""' "$TJ")" "${jmaps[@]}")
    check "JOB_RESULTS は、ジョブの名前ごとにそのジョブの結果を入れた JSON である" \
        "$(jq -n --argjson v "${jv:-null}" '$ARGS.positional | map({(.): ("r-" + .)}) | add | . == $v' --args "${RESULT_JOBS[@]}" 2>/dev/null || echo false)"
    check "report の needs に、そのすべてのジョブがある" "$(yes_if needs_has "$TJ" report "${RESULT_JOBS[@]}")"
fi

if want target_cleanup; then
    check "cleanup は report のあとに、always() と github.ref == 'refs/heads/claude-auto-fix/run' を && でつないだ if で動く(if: $(job_if "$TJ" cleanup))" \
        "$(if needs_has "$TJ" cleanup report && conj_is "$(job_if "$TJ" cleanup)" "always()" "$RUN_REF"; then echo true; else echo false; fi)"
    check "cleanup の権限は actions: write だけである" "$(yes_if perm_is "$TJ" cleanup '{"actions":"write"}')"
    cd_=$(stub_tree cleanup bin/gh)
    echo '{"artifacts":[{"name":"outcome","id":101},{"name":"trivy-results","id":102},{"name":"base-patch","id":103}]}' >"$cd_/gh_json"
    run_step cleanup cleanup "$cd_" github.token=TOKEN0 github.run_id=RUN0 "runner.temp=$cd_/rt" "github.workspace=$cd_" >/dev/null 2>&1
    e=$?
    dl=$(cut -f3 "$cd_/stub_log" | grep -E '(^| )DELETE( |$)' | grep -oE 'artifacts/[0-9]+' | sort | tr '\n' ' ')
    check "cleanup の手順が、成果物 outcome のほかの成果物をすべて消し、outcome を残す(消した: ${dl:-なし})" \
        "$(if [ "$e" -eq 0 ] && [ "$dl" = "artifacts/102 artifacts/103 " ] && grep -q 'repos/o/r/actions/runs/RUN0/artifacts' "$cd_/stub_log" && [ "$(cut -f6 "$cd_/stub_log" | sort -u)" = TOKEN0 ]; then echo true; else echo false; fi)"
fi

if want target_timeouts; then
    check "打ち切りは prepare 45、edit 40、verify 120、verify-image 60、ship 15、report 15、cleanup 10 分である" \
        "$(jq '[.jobs | (.prepare, .edit, .verify, ."verify-image", .ship, .report, .cleanup) | ."timeout-minutes" | tostring]
            == ["45","40","120","60","15","15","10"]' "$TJ")"
fi

if want target_cooldown_push_if; then
    check "cooldown-push の if が verify の出力 cooldown を読む" \
        "$(yes_if conj_has "$(job_if "$TJ" cooldown-push)" "needs.verify.outputs.cooldown=='true'")"
    check "cooldown-push は verify ジョブが通ったときだけ動く" \
        "$(yes_if conj_has "$(job_if "$TJ" cooldown-push)" "needs.verify.result=='success'")"
    # 一時のブランチの名前は fix/claude-auto-fix-cooldown-<kind>-<key のスラグ> で、出力 branch に同じ名前を出す
    patch_run cooldown-push final final.patch $'F\n' "needs.verify.outputs.final_sha256=$(printf 'F\n' | sha256sum | cut -d' ' -f1)" \
        inputs.kind=go-module inputs.key=golang.org/x/net@V0.1
    e=$?
    pb=$(sed -n 's/^branch=//p' "$WORK/patch/out" 2>/dev/null)
    check "cooldown-push が一時のブランチ fix/claude-auto-fix-cooldown-<種類>-<key のスラグ> に push し、その名前を出力 branch に出す(出力: ${pb:-なし})" \
        "$(if [ "$e" -eq 0 ] && [ "$pb" = fix/claude-auto-fix-cooldown-go-module-golang-org-x-net-v0-1 ] && git_calls | grep -E '(^| )push( |$)' | grep -qF "refs/heads/$pb" && [ "$(jq -r "$JQ_NORM"' .jobs."cooldown-push".outputs.branch | norm' "$TJ")" = steps.final.outputs.branch ] && [ "$(jq -r "$JQ_NORM"' .jobs."cooldown-push".outputs.sha | norm' "$TJ")" = steps.final.outputs.sha ]; then echo true; else echo false; fi)"
    # GitHub は .github/workflows/ を変えるコミットを GITHUB_TOKEN で push させないので、bot の PAT で push する。
    # gh auth setup-git が GH_TOKEN の PAT を git に渡したあとに、git push が同じ GH_TOKEN のもとで動くこと
    ga=$(awk -F'\t' '$1 == "gh" && $3 == "auth setup-git" && $6 == "BOT0" && !g { g = NR }
        $1 == "git" && $3 ~ /(^| )push( |$)/ { p = NR; t = $6 } END { if (g && p > g && t == "BOT0") print "yes" }' "$WORK/patch/stub_log" 2>/dev/null)
    check "cooldown-push の final の手順が、GH_TOKEN の bot の PAT で gh auth setup-git を動かしてから push する" \
        "$([ "$e" -eq 0 ] && [ "$ga" = yes ] && echo true || echo false)"
    check "cooldown-push の権限は contents: read だけである" "$(yes_if perm_is "$TJ" cooldown-push '{"contents":"read"}')"
    cp=$(job_text "$TJ" cooldown-push)
    check "cooldown-push が final.patch を確かめて当て、一時のブランチ fix/claude-auto-fix-cooldown- に push する" \
        "$(if has "$cp" "fix/claude-auto-fix-cooldown-" && has "$(step_text "$TJ" cooldown-push final)" "needs.verify.outputs.final_sha256"; then echo true; else echo false; fi)"
    check "cooldown-push の final の手順が final.patch の SHA-256 を verify の出力と比べ、同じときだけ当てて push する(外れ:$(final_bad cooldown-push))" \
        "$(if [ -z "$(final_bad cooldown-push)" ] && { patch_run cooldown-push final final.patch $'F\n' "needs.verify.outputs.final_sha256=$(printf 'F\n' | sha256sum | cut -d' ' -f1)" inputs.kind=container inputs.key=KEY0 github.run_id=RUN0; git_calls | grep -E '(^| )push( |$)' | grep -q 'fix/claude-auto-fix-cooldown-'; }; then echo true; else echo false; fi)"
fi

if want target_cooldown_graph; then
    for j in cooldown-generate cooldown-submit; do
        mode=generate-and-upload
        [ "$j" = cooldown-submit ] && mode=download-and-submit
        env=$(jq -c --arg j "$j" "$JQ_NORM"' (.jobs[$j].env // {}) + (first(.jobs[$j].steps[]? | select(.uses // "" | startswith("gradle/actions/dependency-submission@"))) // {} | .env // {})
            | map_values(norm)' "$TJ")
        check "$j が dependency-submission を $mode で動かし、GITHUB_DEPENDENCY_GRAPH_SHA と GITHUB_DEPENDENCY_GRAPH_REF を渡す" \
            "$(jq --arg j "$j" --arg m "$mode" --argjson e "$env" '
                (first(.jobs[$j].steps[]? | select(.uses // "" | startswith("gradle/actions/dependency-submission@"))) // {} | .with["dependency-graph"]) == $m
                and (($e.GITHUB_DEPENDENCY_GRAPH_SHA // "") | length) > 0
                and (($e.GITHUB_DEPENDENCY_GRAPH_REF // "") | contains("refs/heads/"))' "$TJ")"
        gm=(needs.cooldown-push.outputs.sha=SHA0 needs.cooldown-push.outputs.branch=BR0)
        genv() { jq -r --arg j "$j" --arg k "$1" '((.jobs[$j].env // {}) + (first(.jobs[$j].steps[]? | select(.uses // "" | startswith("gradle/actions/dependency-submission@"))) // {} | .env // {}))[$k] // ""' "$TJ"; }
        check "$j の GITHUB_DEPENDENCY_GRAPH_SHA は一時のブランチの SHA、GITHUB_DEPENDENCY_GRAPH_REF は refs/heads/<一時のブランチ> である" \
            "$(if [ "$(subst_expr "$(genv GITHUB_DEPENDENCY_GRAPH_SHA)" "${gm[@]}")" = SHA0 ] && [ "$(subst_expr "$(genv GITHUB_DEPENDENCY_GRAPH_REF)" "${gm[@]}")" = refs/heads/BR0 ]; then echo true; else echo false; fi)"
    done
    cr=$(subst_expr "$(jq -r '[.jobs."cooldown-generate".steps[]? | select(.uses // "" | startswith("actions/checkout@")) | .with.ref // ""] | .[0] // ""' "$TJ")" "${gm[@]}")
    check "cooldown-generate は一時のブランチを checkout する(ref: ${cr:-なし})" \
        "$(case "$cr" in BR0 | refs/heads/BR0 | SHA0) echo true ;; *) echo false ;; esac)"
    check "cooldown-generate の権限は contents: read だけで、本番の部品の組と除外の設定を渡す" \
        "$(jq '.jobs."cooldown-generate".permissions == {"contents":"read"}
            and ([.jobs."cooldown-generate" | (.env // {}), (.steps[]? | select(.uses // "" | startswith("gradle/actions/dependency-submission@")) | .env // {})]
                 | add | .DEPENDENCY_GRAPH_RUNTIME_INCLUDE_CONFIGURATIONS) == "productionRuntimeClasspath"
            and (first(.jobs."cooldown-generate".steps[]? | select(.uses // "" | startswith("gradle/actions/dependency-submission@"))) // {}
                 | .with["dependency-graph-exclude-configurations"]) == "detachedConfiguration[0-9]+"' "$TJ")"
    # dependency-review の generate ジョブと同じく、Java を入れてからスナップショットを作り、空のスナップショットを送らない
    gi=$(jq -r '[.jobs."cooldown-generate".steps[]? | (.uses // "" | startswith("gradle/actions/dependency-submission@"))] | index(true) // -1' "$TJ")
    ji=$(jq -r '[.jobs."cooldown-generate".steps[]? | (.uses // "" | startswith("actions/setup-java@"))] | index(true) // -1' "$TJ")
    rd=$(jq -r "$JQ_NORM"' first(.jobs."cooldown-generate".steps[]? | select(.uses // "" | startswith("gradle/actions/dependency-submission@"))) // {} | .with["dependency-graph-report-dir"] | norm' "$TJ")
    si=$(jq -r '[.jobs."cooldown-generate".steps[]? | (.run // "" | test("(^|[^-\\w])check-dependency-snapshot\\.sh"))] | index(true) // -1' "$TJ")
    sr=$(jq -r --argjson i "$si" "$JQ_NORM"' if $i >= 0 then .jobs."cooldown-generate".steps[$i].run | norm else "" end' "$TJ")
    check "cooldown-generate が、Java を入れてからスナップショットを作り、作ったあとに check-dependency-snapshot.sh に出力先のフォルダを渡して、空でないことを確かめる" \
        "$(if [ "$ji" -ge 0 ] && [ "$gi" -gt "$ji" ] && [ "$si" -gt "$gi" ] && [ -n "$rd" ] && has "$sr" "$rd"; then echo true; else echo false; fi)"
    # この実行が保存したキャッシュをほかのワークフローの実行に読ませないため、キャッシュを読み書きさせない
    check "cooldown-generate の dependency-submission が cache-disabled: true でキャッシュを読み書きしない" \
        "$(jq '(first(.jobs."cooldown-generate".steps[]? | select(.uses // "" | startswith("gradle/actions/dependency-submission@"))) // {}
            | .with["cache-disabled"] | tostring) == "true"' "$TJ")"
    check "cooldown-submit の権限は contents: write だけで、checkout しない" \
        "$(jq '.jobs."cooldown-submit".permissions == {"contents":"write"}
            and ([.jobs."cooldown-submit".steps[]? | select(.uses // "" | startswith("actions/checkout@"))] | length) == 0' "$TJ")"
fi

if want target_cooldown_pnpm; then
    np=$(step_text "$TJ" cooldown-judge judge_npm)
    check "judge_npm が check-dependency-cooldown.sh に PNPM_WORKSPACE_FILE=target/frontend/pnpm-workspace.yaml と COOLDOWN_MODE=predict を渡す" \
        "$(if has "$np" "check-dependency-cooldown.sh" && { [ "$(step_env "$TJ" cooldown-judge judge_npm PNPM_WORKSPACE_FILE)" = target/frontend/pnpm-workspace.yaml ] || has "$np" "PNPM_WORKSPACE_FILE=target/frontend/pnpm-workspace.yaml"; } && { [ "$(step_env "$TJ" cooldown-judge judge_npm COOLDOWN_MODE)" = predict ] || has "$np" "COOLDOWN_MODE=predict"; } && has "$np" "needs.prepare.outputs.main_sha"; then echo true; else echo false; fi)"
fi

if want target_cooldown_judge; then
    check "cooldown-judge の権限は contents: write と vulnerability-alerts: read である" \
        "$(yes_if perm_is "$TJ" cooldown-judge '{"contents":"write","vulnerability-alerts":"read"}')"
    check "一時のブランチを target/ に checkout する" \
        "$(jq '[.jobs."cooldown-judge".steps[]? | select((.uses // "" | startswith("actions/checkout@")) and .with.path == "target")] | length == 1' "$TJ")"
    cr=$(subst_expr "$(jq -r '[.jobs."cooldown-judge".steps[]? | select((.uses // "" | startswith("actions/checkout@")) and .with.path == "target") | .with.ref // ""] | .[0] // ""' "$TJ")" \
        needs.cooldown-push.outputs.sha=SHA0 needs.cooldown-push.outputs.branch=BR0)
    check "target/ に checkout するのは一時のブランチである(ref: ${cr:-なし})" \
        "$(case "$cr" in BR0 | refs/heads/BR0 | SHA0) echo true ;; *) echo false ;; esac)"
    ni=$(step_idx "$TJ" cooldown-judge judge_npm)
    ti=$(jq -r '[.jobs."cooldown-judge".steps[]? | .run // "" | (contains("test-check-dependency-cooldown.sh") and contains("test-lib-claude-auto-fix.sh"))] | index(true) // -1' "$TJ")
    check "判定の手順の前に、dependency-cooldown のテストと test-lib-claude-auto-fix.sh を流す" \
        "$([ "$ti" -ge 0 ] && [ "$ni" -gt "$ti" ] && echo true || echo false)"
    # スナップショットを送れていないと maven の差を判定できないので、cooldown-submit ジョブが通っていなければ、
    # 判定の手順は動かしたうえで、このジョブを失敗にする
    si=$(step_idx "$TJ" cooldown-judge submitted)
    sd=$(stub_tree submitted)
    bad=""
    for r in success failure skipped cancelled; do
        run_step cooldown-judge submitted "$sd" "needs.cooldown-submit.result=$r" "runner.temp=$sd/rt" "github.workspace=$sd" >/dev/null 2>&1
        e=$?
        case "$r:$e" in success:0) ;; success:* | *:0 | *:98 | *:99) bad="$bad $r:$e" ;; esac
    done
    check "判定の手順の前に、cooldown-submit ジョブが通ったかを確かめ、通っていなければ失敗する(外れ:${bad:- なし})" \
        "$([ "$si" -ge 0 ] && [ "$ni" -gt "$si" ] && [ -z "$bad" ] && echo true || echo false)"
    # 3つの判定の手順を、スクリプトを偽のスクリプトに差し替えたフォルダで動かす
    jd=$(judge_tree)
    jmap=("needs.prepare.outputs.main_sha=MAIN0" "needs.cooldown-push.outputs.sha=HEAD0" "github.token=TOKEN0"
        "secrets.GITHUB_TOKEN=TOKEN0" "runner.temp=$jd/rt" "github.workspace=$jd")
    bad=""
    for s in judge_npm judge_go judge_ci_tool; do
        coe=$(jq -r --arg s "$s" '.jobs."cooldown-judge".steps[]? | select(.id == $s) | ."continue-on-error" | tostring' "$TJ")
        case "$s" in judge_npm) rcs="0 1 2 3" ;; *) rcs="0 1 2" ;; esac
        for n in $rcs; do
            for x in check-dependency-cooldown.sh check-go-release-age.sh check-ci-tool-release-age.sh; do echo "$n" >"$jd/stub_rc_$x"; done
            : >"$jd/out"
            run_step cooldown-judge "$s" "$jd" "${jmap[@]}" >/dev/null 2>&1
            e=$?
            got=$(sed -n 's/^rc=//p' "$jd/out")
            if [ "$got" != "$n" ] || [ "$e" = 98 ] || [ "$e" = 99 ] || { [ "$e" != 0 ] && [ "$coe" != true ]; }; then bad="$bad $s:$n"; fi
        done
    done
    check "3つの判定の手順が、スクリプトの終わり方を出力 rc に書き、ジョブを止めない(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    bad=""
    for s in judge_npm judge_go judge_ci_tool; do
        for x in check-dependency-cooldown.sh check-go-release-age.sh check-ci-tool-release-age.sh; do echo 0 >"$jd/stub_rc_$x"; done
        : >"$jd/out"
        : >"$jd/stub_log"
        run_step cooldown-judge "$s" "$jd" "${jmap[@]}" >/dev/null 2>&1
        nm="" pw="" ar="" cm="" pn="" tk="" cf=""
        [ "$(wc -l <"$jd/stub_log")" -eq 1 ] && IFS=$'\037' read -r nm pw ar cm pn tk cf _ < <(tr '\t' '\037' <"$jd/stub_log")
        pn=${pn#"$jd"/}
        case "$s" in
        judge_npm) [ "$nm" = check-dependency-cooldown.sh ] || bad="$bad $s:name" ;;
        judge_go) [ "$nm" = check-go-release-age.sh ] || bad="$bad $s:name" ;;
        judge_ci_tool) [ "$nm" = check-ci-tool-release-age.sh ] || bad="$bad $s:name" ;;
        esac
        case "$s" in
        judge_npm)
            if ! { [ "$pw" = "$jd" ] && [ "$ar" = "MAIN0 HEAD0" ] && [ "$cm" = predict ] && [ "$pn" = target/frontend/pnpm-workspace.yaml ]; }; then bad="$bad $s"; fi
            ;;
        judge_go)
            if ! { [ "$pw" = "$jd/target" ] && [ "$ar" = "MAIN0 HEAD0" ] && [ "$tk" = TOKEN0 ]; }; then bad="$bad $s"; fi
            ;;
        judge_ci_tool)
            if ! { [ "$pw" = "$jd/target" ] && [ "$ar" = "MAIN0 HEAD0" ] && [ "$cm" = predict ] && [ "$tk" = TOKEN0 ] && [ "$cf" = "$jd/rt/ci-tool-changed.tsv" ]; }; then bad="$bad $s"; fi
            ;;
        esac
    done
    check "judge_npm は最上位で COOLDOWN_MODE=predict と PNPM_WORKSPACE_FILE を、judge_go は target/ の中で GH_TOKEN を、judge_ci_tool は target/ の中で GH_TOKEN と COOLDOWN_MODE=predict と CI_TOOL_CHANGED_FILE を渡し、どれも main_sha と一時のブランチの SHA を引数に渡す(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    bad=""
    for s in judge_npm judge_go judge_ci_tool judge; do
        i=$(step_if "$TJ" cooldown-judge "$s")
        [ "$i" = '!cancelled()' ] || [ "$i" = 'always()' ] || bad="$bad $s"
    done
    check "3つの判定の手順と judge が、前の手順の終わり方によらず動く(外れ:${bad:- なし})" "$([ -z "$bad" ] && echo true || echo false)"
    bad=$(judge_outcomes "$jd" <<'EOF' | tr '\n' ' '
0 0 0 skipped ship
3 0 0 success ship
0 0 0 success ship
1 0 0 skipped blocked
0 1 0 skipped blocked
0 0 1 skipped blocked
1 1 1 skipped blocked
2 0 0 skipped fail
0 2 0 skipped fail
0 0 2 skipped fail
1 2 0 skipped fail
- 0 0 skipped fail
EOF
    )
    check "judge の手順が、3つの rc を cooldown_outcome に渡し、ship と blocked を出力 result に書き、fail では失敗する(外れ: ${bad:-なし})" \
        "$(if has "$(step_text "$TJ" cooldown-judge judge)" "cooldown_outcome" && [ -z "$bad" ]; then echo true; else echo false; fi)"
    order=""
    for s in judge_npm judge_go judge_ci_tool judge_ci_signature judge delete_branch; do order="$order $(step_idx "$TJ" cooldown-judge "$s")"; done
    check "判定の手順、署名の確かめ、judge、ブランチを消す手順の順に並ぶ(番号:$order)" \
        "$(jq -n --arg o "$order" '($o | split(" ") | map(select(. != "") | tonumber)) as $a | ($a | min) >= 0 and $a == ($a | sort) and ($a | unique | length) == ($a | length)')"
    check "ブランチを消す手順は always() で動く" "$([ "$(step_if "$TJ" cooldown-judge delete_branch)" = 'always()' ] && echo true || echo false)"
    dd=$(stub_tree delete bin/gh)
    run_step cooldown-judge delete_branch "$dd" needs.cooldown-push.outputs.branch=fix/claude-auto-fix-cooldown-npm-a github.token=TOKEN0 \
        "runner.temp=$dd/rt" "github.workspace=$dd" >/dev/null 2>&1
    e=$?
    dl=$(awk -F'\t' '$1 == "gh" && $3 ~ /(^| )DELETE( |$)/ && $3 ~ /repos\/o\/r\/git\/refs\/heads\/fix\/claude-auto-fix-cooldown-npm-a( |$)/ && $6 == "TOKEN0"' "$dd/stub_log" | wc -l)
    check "ブランチを消す手順が、一時のブランチを GITHUB_TOKEN で消す" \
        "$([ "$e" -eq 0 ] && [ "$dl" -eq 1 ] && echo true || echo false)"
    check "出力 result は judge の手順の出力である" \
        "$([ "$(jq -r "$JQ_NORM"' .jobs."cooldown-judge".outputs.result | norm' "$TJ")" = steps.judge.outputs.result ] && echo true || echo false)"
fi

if want target_cooldown_signature; then
    check "judge_ci_signature が、check-ci-tool-release-age.sh が0で終わったときに動き、ジョブを止めない" \
        "$(if conj_has "$(step_if "$TJ" cooldown-judge judge_ci_signature)" "steps.judge_ci_tool.outputs.rc=='0'" && [ "$(jq -r ".jobs.\"cooldown-judge\".steps[]? | select(.id == \"judge_ci_signature\") | .\"continue-on-error\" | tostring" "$TJ")" = true ]; then echo true; else echo false; fi)"
    jd=$(judge_tree)
    sig_run() {
        printf '%b' "$1" >"$jd/rt/ci-tool-changed.tsv"
        echo "$2" >"$jd/stub_rc_install-verified-node.sh"
        echo "$3" >"$jd/stub_rc_install-verified-trivy.sh"
        : >"$jd/stub_log"
        rm -f "$jd/github_path"
        run_step cooldown-judge judge_ci_signature "$jd" "runner.temp=$jd/rt" "github.workspace=$jd" "github.token=TOKEN0" >/dev/null 2>&1
    }
    bad=""
    sig_run 'node\t24.0.1\ntrivy\t0.77.0\n' 0 0
    e=$?
    calls=$(cut -f1,3 "$jd/stub_log" | sort)
    { [ "$e" -eq 0 ] && [ "$calls" = "$(printf 'install-verified-node.sh\t24.0.1\ninstall-verified-trivy.sh\t0.77.0')" ]; } || bad="$bad 2つの版"
    # 2つの呼び方の GITHUB_PATH が、どちらも空でなく、手順の GITHUB_PATH と違い、手順の GITHUB_PATH に何も書かれない
    [ "$(cut -f8 "$jd/stub_log" | grep -cvxF -e "$jd/github_path" -e '')" -eq 2 ] && [ ! -s "$jd/github_path" ] || bad="$bad GITHUB_PATH"
    for c in '0 1' '1 0'; do
        read -r c1 c2 <<<"$c"
        sig_run 'node\t24.0.1\ntrivy\t0.77.0\n' "$c1" "$c2"
        e=$?
        case "$e" in 0 | 98 | 99) bad="$bad 失敗を見逃す($c)" ;; esac
    done
    sig_run '' 0 0
    e=$?
    { [ "$e" -eq 0 ] && [ ! -s "$jd/stub_log" ]; } || bad="$bad 空のファイル"
    check "judge_ci_signature が、ci-tool-changed.tsv の版ごとに install-verified-<道具>.sh を使い捨ての GITHUB_PATH で呼び、どれかが失敗すれば失敗する(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
fi

if want target_cooldown_signature_fail; then
    jd=$(judge_tree)
    bad=$(judge_outcomes "$jd" <<'EOF' | tr '\n' ' '
0 0 0 failure blocked
3 0 0 failure blocked
0 0 0 skipped ship
EOF
    )
    check "judge の手順が、署名を確かめられなかったときに3つ目の終わり方を1にして blocked を出す(外れ: ${bad:-なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
fi

if want target_ref_branch; then
    check "ref-check ジョブの if が github.ref != 'refs/heads/claude-auto-fix/run' で、権限を持たず、1分で打ち切られる(if: $(job_if "$TJ" ref-check))" \
        "$(if [ "$(job_if "$TJ" ref-check)" = "github.ref!='refs/heads/claude-auto-fix/run'" ] &&
            jq -e '.jobs["ref-check"] as $r | ($r | type) == "object" and $r.permissions == {} and ($r."timeout-minutes" | tostring) == "1"' "$TJ" >/dev/null 2>&1; then echo true; else echo false; fi)"
    bad=""
    for j in $(jq -r '.jobs // {} | keys[] | select(. != "ref-check")' "$TJ"); do
        conj_has "$(job_if "$TJ" "$j")" "$RUN_REF" || bad="$bad $j"
    done
    check "ほかのすべてのジョブの if が github.ref == 'refs/heads/claude-auto-fix/run' を含む(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && [ "$(jq '.jobs // {} | length' "$TJ")" -gt 1 ] && echo true || echo false)"
    # ref_check の手順を、main で起動された実行の値で動かす。手順は ref_check の1つだけで、checkout も、ほかのアクションも使わない
    rd=$(stub_tree ref_check)
    run_step ref-check ref_check "$rd" github.ref=refs/heads/main github.ref_name=main github.event_name=workflow_dispatch \
        "runner.temp=$rd/rt" "github.workspace=$rd" >"$WORK/ref_check.out" 2>&1
    e=$?
    el=$(grep -E '^::error::' "$WORK/ref_check.out" | grep -F 'claude-auto-fix/run' | grep -F 'claude-auto-fix.yaml')
    check "ref-check ジョブの手順が、専用のブランチで起動されていないことと claude-auto-fix.yaml を起動することを書いた ::error:: の行を出して0以外で終わる(終わり方 $e)" \
        "$(if [ "$e" -ne 0 ] && [ "$e" -ne 98 ] && [ "$e" -ne 99 ] && [ -n "$el" ] &&
            jq -e '[.jobs["ref-check"].steps[]?] | length == 1 and .[0].id == "ref_check" and (.[0] | has("uses") | not)' "$TJ" >/dev/null 2>&1; then echo true; else echo false; fi)"
    lb=$(bash -c '. "$1" >/dev/null 2>&1 </dev/null; printf "%s" "${CAF_RUN_BRANCH:-}"' _ "$HERE/lib-claude-auto-fix.sh")
    yb=$(jq -r '.jobs // {} | .[] | .if // "" | tostring' "$TJ" | while IFS= read -r l; do all_of "$l" 'refs/heads/[A-Za-z0-9_./-]+'; done |
        sed 's|^refs/heads/||' | sort -u | tr '\n' ' ')
    check "YAML に書いたブランチの名前が lib-claude-auto-fix.sh の CAF_RUN_BRANCH と同じである(YAML: ${yb:-なし}、CAF_RUN_BRANCH: ${lb:-なし})" \
        "$([ -n "$lb" ] && [ "$yb" = "$lb " ] && echo true || echo false)"
fi

if want target_cache; then
    # ジョブの名前(空ならすべてのジョブ)の、uses が2つ目の引数で始まる手順の配列
    JQ_ST='def st(j; p): [(if j == "" then (.jobs // {} | .[]) else .jobs[j] end) | .steps[]? | select((.uses // "") | startswith(p))];'
    cache_check() { check "$1" "$(jq "$JQ_ST $2" "$TJ" 2>/dev/null || echo false)"; }
    cache_check "verify ジョブの setup-go のすべての手順に cache: false が渡される" \
        '(st("verify"; "actions/setup-go@") | length) > 0 and all(st(""; "actions/setup-go@")[]; (.with.cache | tostring) == "false")'
    cache_check "verify ジョブの golangci-lint-action に skip-cache: true が渡される" \
        '(st("verify"; "golangci/golangci-lint-action@") | length) > 0
            and all(st(""; "golangci/golangci-lint-action@")[]; (.with["skip-cache"] | tostring) == "true")'
    for j in cooldown-generate cooldown-submit; do
        cache_check "$j ジョブの dependency-submission に cache-disabled: true が渡される" \
            "(st(\"$j\"; \"gradle/actions/dependency-submission@\") | length) > 0
                and all(st(\"$j\"; \"gradle/actions/dependency-submission@\")[]; (.with[\"cache-disabled\"] | tostring) == \"true\")"
    done
    cache_check "setup-java のすべての手順と pnpm/action-setup にキャッシュの入力が無い" \
        '(st(""; "actions/setup-java@") | length) > 0 and (st(""; "pnpm/action-setup@") | length) > 0
            and all((st(""; "actions/setup-java@") + st(""; "pnpm/action-setup@"))[]; .with // {} | keys | any(test("cache"; "i")) | not)'
    cache_check "どのジョブにも actions/cache の手順が無い" \
        '[.jobs // {} | .[] | .steps[]? | select((.uses // "") | test("^actions/cache(/|@)"))] | length == 0'
    cache_check "どのジョブにも type=gha が無い" '.jobs // {} | tojson | test("type\\s*=\\s*gha") | not'
    for s in init analyze; do
        cache_check "CodeQL の $s に CODEQL_OVERLAY_DATABASE_MODE: none が渡される" \
            "(st(\"\"; \"github/codeql-action/$s@\") | length) > 0
                and all(st(\"\"; \"github/codeql-action/$s@\")[]; (.env.CODEQL_OVERLAY_DATABASE_MODE | tostring) == \"none\")"
    done
    cache_check "CodeQL の init に trap-caching: false が渡される" \
        '(st(""; "github/codeql-action/init@") | length) > 0 and all(st(""; "github/codeql-action/init@")[]; (.with["trap-caching"] | tostring) == "false")'
    cache_check "CodeQL の init に dependency-caching が無い" \
        '(st(""; "github/codeql-action/init@") | length) > 0 and all(st(""; "github/codeql-action/init@")[]; .with // {} | has("dependency-caching") | not)'
fi

# ---------------------------------------------------------------------
# 振り分けのワークフロー
# ---------------------------------------------------------------------

DISPATCH_WATCH='["Audit Weekly","Backend Vulnerability Fix","Frontend Transitive Vulnerability Fix","Scheduled Container Image Vulnerability Scan"]'

if want dispatch_on; then
    check "きっかけは workflow_run と schedule と workflow_dispatch だけである" \
        "$(jq '(.on | keys) == ["schedule","workflow_dispatch","workflow_run"]' "$DJ")"
    check "workflow_run は4つのワークフローの completed である" \
        "$(jq --argjson w "$DISPATCH_WATCH" '(.on.workflow_run.workflows | sort) == $w and .on.workflow_run.types == ["completed"]' "$DJ")"
    check "定期実行は cron 17 * * * * だけである" "$(jq '.on.schedule == [{"cron":"17 * * * *"}]' "$DJ")"
    check "workflow_dispatch に入力が無い" \
        "$(jq '(.on | has("workflow_dispatch")) and ((.on.workflow_dispatch // {}) | (.inputs // {}) == {})' "$DJ")"
    check "同時実行の組が無い" "$(jq '.concurrency == null and ([.jobs // {} | .[] | .concurrency] | all(. == null))' "$DJ")"
fi

if want dispatch_permissions; then
    check "ワークフローの既定の権限は contents: read だけである" "$(jq '.permissions == {"contents":"read"}' "$DJ")"
    check "ジョブは run-branch と dispatch と sweep である" "$(jq '(.jobs // {} | keys) == ["dispatch","run-branch","sweep"]' "$DJ")"
    check "dispatch の権限" "$(yes_if perm_is "$DJ" dispatch \
        '{"contents":"read","actions":"write","issues":"read","pull-requests":"read","checks":"read","security-events":"read","vulnerability-alerts":"read"}')"
    check "sweep の権限" "$(yes_if perm_is "$DJ" sweep \
        '{"contents":"write","actions":"write","issues":"write","pull-requests":"write","checks":"read","security-events":"read","vulnerability-alerts":"read"}')"
fi

if want dispatch_secrets; then
    all=$(jq -c '.' "$DJ")
    check "secrets.CLAUDE_CODE_OAUTH_TOKEN が現れない" "$(if ! has "$all" "CLAUDE_CODE_OAUTH_TOKEN"; then echo true; else echo false; fi)"
    # run-branch ジョブの、claude-auto-fix-run-branch.sh を tests/ の外から呼ぶ手順
    rbs=$(jq -c 'first(.jobs["run-branch"].steps[]? | select((.run // "") | test("(^|[^-[:alnum:]_])claude-auto-fix-run-branch\\.sh"))) // empty' "$DJ")
    n_all=$(count_of "$all" BOT_GITHUB_TOKEN)
    n_rb=$(count_of "$rbs" BOT_GITHUB_TOKEN)
    [ -n "$rbs" ] || rbs='{}'
    gt=$(jq -r "$JQ_NORM"' .env.GH_TOKEN | norm' <<<"$rbs")
    check "secrets.BOT_GITHUB_TOKEN は run-branch ジョブの claude-auto-fix-run-branch.sh を呼ぶ手順にだけ現れる(全体 $n_all、手順 $n_rb、手順の GH_TOKEN: ${gt:-なし})" \
        "$([ "$n_rb" -gt 0 ] && [ "$n_all" = "$n_rb" ] && [ "$gt" = secrets.BOT_GITHUB_TOKEN ] && echo true || echo false)"
    bad=$(all_of "$all" 'secrets[^A-Za-z0-9_]?[A-Za-z0-9_]*' | grep -vxE 'secrets\.(GITHUB_TOKEN|BOT_GITHUB_TOKEN)' | sort -u | tr '\n' ' ')
    check "秘密の値は GITHUB_TOKEN と BOT_GITHUB_TOKEN のほかに無い(外れ: ${bad:-なし})" "$([ -z "$bad" ] && echo true || echo false)"
fi

if want dispatch_conditions; then
    # ジョブの if を jq の式に直して、きっかけごとに動くかを決める。
    # 読めるのは、文字列、文脈の名前、== != && || と括弧だけである。ほかの書き方は読めないとして失敗にする
    runs() {
        local job=$1 ctx=$2 e
        e=$(jq -r --arg j "$job" '.jobs[$j].if // "" | tostring' "$DJ")
        e=$(perl -0pe 's/^\s*\$\{\{\s*//s; s/\s*\}\}\s*$//s' <<<"$e")
        [ -n "$e" ] || { echo true; return; }
        if perl -e '$_ = $ARGV[0]; s/\x27[^\x27]*\x27//g; exit((/!(?!=)/ || /[A-Za-z_]\s*\(/ || /[^\sA-Za-z0-9_.=!&|()]/) ? 1 : 0)' "$e"; then
            :
        else
            echo unreadable
            return
        fi
        e=$(perl -pe 's{\x27([^\x27]*)\x27|(&&)|(\|\|)|\b(true|false|null)\b|([A-Za-z_][A-Za-z0-9_.]*)}{defined $1 ? "\"$1\"" : defined $2 ? " and " : defined $3 ? " or " : defined $4 ? $4 : ".$5"}ge' <<<"$e")
        jq -n --argjson c "$ctx" "\$c | ($e) | if . == \"\" or . == null or . == false then false else true end" 2>/dev/null || echo unreadable
    }
    wr() { jq -nc --arg n "$1" --arg c "$2" '{github: {event_name: "workflow_run", event: {workflow_run: {name: $n, conclusion: $c}}}}'; }
    ev() { jq -nc --arg e "$1" '{github: {event_name: $e, event: {}}}'; }
    bad=""
    expect_runs() { local got; got=$(runs "$1" "$2"); [ "$got" = "$3" ] || bad="$bad [$1 $4: $got]"; }
    expect_runs dispatch "$(ev schedule)" true "schedule"
    expect_runs sweep "$(ev schedule)" true "schedule"
    expect_runs dispatch "$(ev workflow_dispatch)" true "workflow_dispatch"
    expect_runs sweep "$(ev workflow_dispatch)" false "workflow_dispatch"
    for w in "Frontend Transitive Vulnerability Fix" "Backend Vulnerability Fix"; do
        expect_runs dispatch "$(wr "$w" failure)" true "$w failure"
        expect_runs dispatch "$(wr "$w" success)" false "$w success"
        expect_runs dispatch "$(wr "$w" cancelled)" false "$w cancelled"
        expect_runs sweep "$(wr "$w" failure)" false "$w failure"
    done
    for w in "Audit Weekly" "Scheduled Container Image Vulnerability Scan"; do
        expect_runs dispatch "$(wr "$w" success)" true "$w success"
        expect_runs dispatch "$(wr "$w" failure)" true "$w failure"
        expect_runs sweep "$(wr "$w" success)" false "$w success"
    done
    check "定期実行で dispatch と sweep が動き、手での起動では dispatch だけが動き、vuln-fix の2つは failure のときだけ dispatch が動く(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
fi

if want dispatch_steps; then
    check "dispatch のランナーは ubuntu-24.04 である" "$(jq '.jobs.dispatch."runs-on" == "ubuntu-24.04"' "$DJ")"
    check "dispatch と sweep の打ち切りは30分である" \
        "$(jq '[.jobs | (.dispatch, .sweep) | ."timeout-minutes" | tostring] == ["30","30"]' "$DJ")"
    idx_of() { jq -r --arg j "$1" --arg p "$2" '[.jobs[$j].steps[]? | .run // "" | test($p)] | index(true) // -1' "$DJ"; }
    d=$(idx_of dispatch '(^|[^-[:alnum:]_])claude-auto-fix-dispatch\.sh')
    s=$(idx_of sweep '(^|[^-[:alnum:]_])claude-auto-fix-sweep\.sh')
    bad=""
    for t in test-claude-auto-fix-workflows test-claude-auto-fix-dispatch test-lib-claude-auto-fix; do
        i=$(idx_of dispatch "tests/$t\\.sh")
        { [ "$i" -ge 0 ] && [ "$d" -gt "$i" ]; } || bad="$bad dispatch:$t"
    done
    for t in test-claude-auto-fix-sweep test-lib-claude-auto-fix; do
        i=$(idx_of sweep "tests/$t\\.sh")
        { [ "$i" -ge 0 ] && [ "$s" -gt "$i" ]; } || bad="$bad sweep:$t"
    done
    check "スクリプトを呼ぶ前に、ワークフローのテストとスクリプトのテストと共通の関数のテストを流す(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    tb=$(jq -r '[.jobs | (.dispatch, .sweep) | .steps[]? | .run // "" | select(test("tests/test-"))] | .[]' "$DJ" |
        sed 's/[[:space:]]*$//' | grep -vxE 'bash \.github/scripts/tests/test-[a-z-]+\.sh( && bash \.github/scripts/tests/test-[a-z-]+\.sh)*' | tr '\n' ' ')
    check "テストの手順は、テストを bash で呼んで && でつなぐだけで、失敗を握りつぶさない(外れ: ${tb:-なし})" "$([ -z "$tb" ] && echo true || echo false)"
    check "テストが失敗したら、スクリプトの手順を動かさない" \
        "$(jq '([.jobs | (.dispatch, .sweep) | .steps[]? | select(((.run // "") | test("tests/test-")) and ((."continue-on-error" // false) | tostring) != "false")] | length == 0)
            and ([.jobs | (.dispatch, .sweep) | .steps[]? | select((.run // "") | test("claude-auto-fix-(dispatch|sweep)\\.sh")) | select(.if != null and .if != "")] | length == 0)
            and ([.jobs | (.dispatch, .sweep) | .steps[]?] | length > 0)' "$DJ")"
    # dispatch の手順を、2つのスクリプトを差し替えたフォルダで、きっかけごとに動かす。
    # workflow_run は trigger、workflow_dispatch は manual、schedule は retry で呼び、ほかのきっかけでは呼ばずに失敗する
    dd=$(stub_tree dispatch .github/scripts/claude-auto-fix-dispatch.sh .github/scripts/claude-auto-fix-sweep.sh)
    bad=""
    for p in workflow_run:trigger workflow_dispatch:manual schedule:retry push:-; do
        evn=${p%%:*}
        wm=${p#*:}
        : >"$dd/stub_log"
        (TJ=$DJ run_step dispatch dispatch "$dd" "github.event_name=$evn" github.token=TOKEN0 secrets.GITHUB_TOKEN=TOKEN0 \
            "github.event.workflow_run.name=W0" github.event.workflow_run.id=RID0 >/dev/null 2>&1)
        e=$?
        if [ "$wm" = - ]; then
            { [ "$e" -ne 0 ] && [ "$e" -ne 98 ] && [ "$e" -ne 99 ] && [ ! -s "$dd/stub_log" ]; } || bad="$bad $evn:$e"
        else
            { [ "$e" -eq 0 ] && [ "$(wc -l <"$dd/stub_log")" -eq 1 ] && [ "$(cut -f1 "$dd/stub_log")" = claude-auto-fix-dispatch.sh ] &&
                [ "$(cut -f3 "$dd/stub_log")" = "$wm" ] && [ "$(cut -f6 "$dd/stub_log")" = TOKEN0 ]; } || bad="$bad $evn:$e"
        fi
    done
    check "dispatch の手順が、workflow_run では trigger、workflow_dispatch では manual、schedule では retry を引数にし、GH_TOKEN に GITHUB_TOKEN を渡して claude-auto-fix-dispatch.sh を呼び、ほかのきっかけでは呼ばずに失敗する(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
    check "dispatch の手順が、TRIGGER_WORKFLOW にきっかけのワークフローの名前を、TRIGGER_RUN_ID にきっかけの実行の ID を渡す" \
        "$(if [ "$(step_env "$DJ" dispatch dispatch TRIGGER_WORKFLOW)" = github.event.workflow_run.name ] &&
            [ "$(step_env "$DJ" dispatch dispatch TRIGGER_RUN_ID)" = github.event.workflow_run.id ]; then echo true; else echo false; fi)"
    : >"$dd/stub_log"
    (TJ=$DJ run_step sweep sweep "$dd" github.token=TOKEN0 secrets.GITHUB_TOKEN=TOKEN0 >/dev/null 2>&1)
    e=$?
    check "sweep の手順が、引数なしで、GH_TOKEN に GITHUB_TOKEN を渡して claude-auto-fix-sweep.sh を呼ぶ" \
        "$(if [ "$e" -eq 0 ] && [ "$(wc -l <"$dd/stub_log")" -eq 1 ] && [ "$(cut -f1 "$dd/stub_log")" = claude-auto-fix-sweep.sh ] &&
            [ -z "$(cut -f3 "$dd/stub_log")" ] && [ "$(cut -f6 "$dd/stub_log")" = TOKEN0 ]; then echo true; else echo false; fi)"
    check "checkout は persist-credentials: false である" \
        "$(jq '[.jobs | (.dispatch, .sweep) | .steps[]? | select((.uses // "") | startswith("actions/checkout@"))] as $c
            | ($c | length) == 2 and all($c[]; (.with["persist-credentials"] | tostring) == "false")' "$DJ")"
fi

if want dispatch_run_branch; then
    check "dispatch ジョブと sweep ジョブが needs: [run-branch] を持つ" \
        "$(if needs_has "$DJ" dispatch run-branch && needs_has "$DJ" sweep run-branch; then echo true; else echo false; fi)"
    # run-branch ジョブは、どのきっかけでも動くので if を持たない。テストの手順にも、ジョブの env にも、秘密の値とトークンを渡さない
    check "run-branch ジョブが if を持たず、権限が contents: read だけで、checkout が persist-credentials: false で、テストを流す手順に秘密の値が無く、5分で打ち切られる" \
        "$(jq '.jobs["run-branch"] as $r | ($r | type) == "object" and ($r | has("if") | not)
            and $r.permissions == {"contents":"read"} and ($r."timeout-minutes" | tostring) == "5"
            and ($r.env // {} | tojson | test("secrets|github\\.token") | not)
            and ([$r.steps[]? | select((.uses // "") | startswith("actions/checkout@"))] as $c
                | ($c | length) > 0 and all($c[]; (.with["persist-credentials"] | tostring) == "false"))
            and ([$r.steps[]? | select((.run // "") | test("tests/test-"))] as $t
                | ($t | length) > 0 and all($t[]; tojson | test("secrets|github\\.token") | not))' "$DJ" 2>/dev/null || echo false)"
    # テストの手順が失敗したら、run-branch ジョブはスクリプトを呼ばずに止まる
    rb_idx() { jq -r --arg p "$1" '[.jobs["run-branch"].steps[]? | .run // "" | test($p)] | index(true) // -1' "$DJ"; }
    s=$(rb_idx '(^|[^-[:alnum:]_])claude-auto-fix-run-branch\.sh')
    bad=""
    for t in test-claude-auto-fix-run-branch test-lib-claude-auto-fix; do
        i=$(rb_idx "tests/$t\\.sh")
        { [ "$i" -ge 0 ] && [ "$s" -gt "$i" ]; } || bad="$bad 順番:$t"
    done
    jq -e '[.jobs["run-branch"].steps[]? | select((.run // "") | test("tests/test-")) | select(has("if") or has("continue-on-error"))]
        | length == 0' "$DJ" >/dev/null 2>&1 || bad="$bad if/continue-on-error"
    tb=$(jq -r '[.jobs["run-branch"].steps[]? | .run // "" | select(test("tests/test-"))] | .[]' "$DJ" |
        sed 's/[[:space:]]*$//' | grep -vxE 'bash \.github/scripts/tests/test-[a-z-]+\.sh( && bash \.github/scripts/tests/test-[a-z-]+\.sh)*' | tr '\n' ' ')
    [ -z "$tb" ] || bad="$bad テストの呼び方:$tb"
    check "run-branch ジョブが、テストを流す手順のあとに claude-auto-fix-run-branch.sh を呼び、テストを流す手順に if と continue-on-error が無い(外れ:${bad:- なし})" \
        "$([ -z "$bad" ] && echo true || echo false)"
fi

if [ "$RAN" -eq 0 ]; then
    echo "知らない場合の名前です: $CASE" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "失敗した確かめがあります" >&2
    exit 1
fi
echo "すべての確かめが通りました($RAN の場合)"
