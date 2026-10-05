#!/bin/bash
# =====================================================================
# session.sh(着手のときの調べと記録のスクリプト)のテスト
#
# 実行: bash .claude/scripts/parallel/tests/test-session.sh
# 一時的な git のリポジトリ(本体)と worktree を2つ作り、その中で session.sh を呼ぶ。
# docker は、呼ばれた引数を記録するだけの偽物(PATH の先頭に置く)に差し替える。
# 本物のリポジトリの記録(.git/keirekipro-parallel)と git の設定には触れない。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR KP_SESSION_ID

SESSION="$(cd "$(dirname "$0")/.." && pwd)/session.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- 偽物の docker
mkdir -p "$WORK/bin"
cat >"$WORK/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_DOCKER_LOG"
exit 0
EOF
chmod +x "$WORK/bin/docker"
# PATH は : 区切りなので、C: を含まない形のパスで先頭に置く
export PATH="$TMP_ROOT/bin:$PATH"
export FAKE_DOCKER_LOG="$WORK/docker.log"

# --- 一時的なリポジトリ(本体と worktree 2つ)
MAIN_DIR="$WORK/RepoMain"
WT_DIR="$WORK/RepoWT"
WT2_DIR="$WORK/RepoWT2"
GITC=(-c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
git init -q "$MAIN_DIR"
git -C "$MAIN_DIR" checkout -q -B main
mkdir -p "$MAIN_DIR/.kiro/specs/alpha"
printf '{"feature_name":"alpha","issue":10}\n' >"$MAIN_DIR/.kiro/specs/alpha/spec.json"
echo seed >"$MAIN_DIR/seed.txt"
git -C "$MAIN_DIR" add -A
git -C "$MAIN_DIR" "${GITC[@]}" commit -q -m seed
git -C "$MAIN_DIR" worktree add -q "$WT_DIR" -b feat/wt
git -C "$MAIN_DIR" worktree add -q "$WT2_DIR" -b feat/wt2
MAIN=$(git -C "$MAIN_DIR" rev-parse --show-toplevel)
WT=$(git -C "$WT_DIR" rev-parse --show-toplevel)
WT2=$(git -C "$WT2_DIR" rev-parse --show-toplevel)
STATE="$(git -C "$MAIN_DIR" rev-parse --path-format=absolute --git-common-dir)/keirekipro-parallel"
SEED_SHA=$(git -C "$MAIN_DIR" rev-parse HEAD)

# 記録の中で作業フォルダを比べる形(design.md の規則どおりに求める)
fid() {
    if [ "$(git -C "$MAIN_DIR" config --get core.ignorecase)" = true ]; then
        printf '%s' "$1" | tr 'A-Z' 'a-z'
    else
        printf '%s' "$1"
    fi
}
fkey() { fid "$(git -C "$1" rev-parse --show-toplevel)" | git hash-object --stdin | cut -c1-12; }

# ss <フォルダ> <引数>...: そのフォルダで session.sh を呼ぶ
ss() {
    local dir="$1"
    shift
    (cd "$dir" && bash "$SESSION" "$@")
}

# pj <JSON> <perl の式>: JSON を $d に読み、式の値を出す(配列と表は JSON、真偽は true/false、無ければ null)
pj() {
    printf '%s' "$1" | perl -MJSON::PP -e '
        local $/; my $d = JSON::PP->new->utf8->decode(<STDIN>);
        my $v = eval $ARGV[0]; die $@ if $@;
        if (!defined $v) { print "null" }
        elsif (JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
        elsif (ref $v) { print JSON::PP->new->utf8->canonical->encode($v) }
        else { utf8::encode($v) if utf8::is_utf8($v); print $v }
    ' "$2"
}

# 記録の下書き(session.sh の書き込みに頼らずに置く)
put_session() { # <session_id> <folder> <folder_key> <started_at>
    mkdir -p "$STATE/sessions"
    printf '{"folder":"%s","folder_key":"%s","last_seen":%s,"session_id":"%s","started_at":%s}\n' \
        "$2" "$3" "$(($4 + 5))" "$1" "$4" >"$STATE/sessions/$1.json"
}
put_issue() { # <N> <folder> <branch> <session_id> [<handed_over_from の JSON>]
    mkdir -p "$STATE/issues"
    printf '{"branch":"%s","folder":"%s","handed_over_from":%s,"issue":%s,"session_id":"%s","updated_at":1}\n' \
        "$3" "$2" "${5:-[]}" "$1" "$4" >"$STATE/issues/$1.json"
}
put_spec() { # <作業フォルダ> <spec の名前> <issue> [<additional_issues の JSON>]
    mkdir -p "$1/.kiro/specs/$2"
    printf '{"additional_issues":%s,"feature_name":"%s","issue":%s}\n' \
        "${4:-[]}" "$2" "$3" >"$1/.kiro/specs/$2/spec.json"
}

reset_state() {
    local d b
    rm -rf "$STATE"
    git -C "$MAIN_DIR" config --unset keirekipro.parallelSlots 2>/dev/null
    for d in "$MAIN_DIR" "$WT_DIR" "$WT2_DIR"; do
        git -C "$d" reset -q --hard
        git -C "$d" clean -fdq
    done
    # ブランチを最初のコミットに戻す(前のテストのコミットを持ち越さない)
    git -C "$MAIN_DIR" switch -q main 2>/dev/null
    git -C "$WT_DIR" switch -q feat/wt 2>/dev/null
    git -C "$WT2_DIR" switch -q feat/wt2 2>/dev/null
    for d in "$MAIN_DIR" "$WT_DIR" "$WT2_DIR"; do
        git -C "$d" reset -q --hard "$SEED_SHA"
    done
    for b in $(git -C "$MAIN_DIR" for-each-ref --format='%(refname)' refs/remotes refs/heads/feat/extra); do
        git -C "$MAIN_DIR" update-ref -d "$b"
    done
    : >"$FAKE_DOCKER_LOG"
    unset KP_SESSION_ID
}

# 失敗の理由を出して、そのテストを終える(テストは run_test のサブシェルで動く)
die() {
    printf '%s\n' "$*"
    exit 1
}

pass=0
fail=0
run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    reset_state
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# check-start を呼び、終了コード0と1行の JSON であることを確かめて JSON を出す
check_start() { # <フォルダ> <引数>...
    local out rc lines
    out=$(ss "$@" 2>/dev/null)
    rc=$?
    [ "$rc" = 0 ] || die "check-start の終了コード $rc"
    lines=$(printf '%s\n' "$out" | wc -l)
    [ "$lines" -eq 1 ] || die "check-start の出力が1行でない: $out"
    pj "$out" '1' >/dev/null 2>&1 || die "check-start の出力が JSON でない: $out"
    printf '%s' "$out"
}

# =====================================================================
# check-start: 同じ作業フォルダの別のセッション(要件5.1・5.2)
# =====================================================================
t_folder_conflict() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    # s-old は着手したセッション(Issueの記録がある)
    put_issue 77 "$MAIN" main s-old
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 200
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 50
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{folder_conflict}}')" = 1 ] || die "folder_conflict の数が1でない: $out"
    [ "$(pj "$out" '$d->{folder_conflict}[0]{session_id}')" = s-old ] || die "s-old が出ない: $out"
    [ "$(pj "$out" '$d->{folder_conflict}[0]{started_at}')" = 100 ] || die "started_at が違う: $out"
    [ "$(pj "$out" '$d->{folder_conflict}[0]{last_seen}')" = 105 ] || die "last_seen が違う: $out"
    # 別の作業フォルダのセッションは出ない
    out=$(check_start "$WT_DIR" check-start 42 --session s-wt) || die "$out"
    [ "$(pj "$out" '$d->{folder_conflict}')" = '[]' ] || die "worktree で folder_conflict が空でない: $out"
}

t_folder_conflict_without_session() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_session s-new "$MAIN" "$(fkey "$MAIN_DIR")" 200
    # 同じ作業フォルダにIssueの記録があるので、どちらも作業中
    put_issue 77 "$MAIN" main s-old
    # --session が無いときは、いまの作業フォルダのいちばん古い記録を自分とみなして除く
    out=$(check_start "$MAIN_DIR" check-start 42) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{session_id} } @{$d->{folder_conflict}}')" = s-new ] \
        || die "--session が無いときの folder_conflict が s-new だけでない: $out"
    # 環境変数 KP_SESSION_ID でも渡せる
    out=$(KP_SESSION_ID=s-new check_start "$MAIN_DIR" check-start 42) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{session_id} } @{$d->{folder_conflict}}')" = s-old ] \
        || die "KP_SESSION_ID=s-new のときの folder_conflict が s-old だけでない: $out"
}

t_end_clears_conflict() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_issue 77 "$MAIN" main s-old
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 200
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{folder_conflict}}')" = 1 ] || die "end の前に folder_conflict が出ない: $out"
    ss "$MAIN_DIR" end s-old || die "end の終了コード $?"
    [ ! -f "$STATE/sessions/s-old.json" ] || die "end のあとも s-old の記録が残っている"
    [ -f "$STATE/sessions/s-me.json" ] || die "end が自分の記録まで消した"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{folder_conflict}')" = '[]' ] || die "end のあとも folder_conflict が空でない: $out"
}

t_folder_conflict_idle_ignored() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 200
    # ほかの作業フォルダのIssueの記録は、いまの作業フォルダのセッションを作業中にしない
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 50
    put_issue 78 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{folder_conflict}')" = '[]' ] || die "着手していないセッションが folder_conflict に出た: $out"
}

t_end_rejects_path() {
    local rc
    mkdir -p "$STATE/sessions"
    echo '{}' >"$STATE/keep.json"
    ss "$MAIN_DIR" end ../keep >/dev/null 2>&1
    rc=$?
    [ "$rc" != 0 ] || die "パスを含むIDを受け付けた"
    [ -f "$STATE/keep.json" ] || die "記録の置き場所の外のファイルを消した"
}

# =====================================================================
# check-start: Issueの作りかけ(要件4.1・4.2)
# =====================================================================
t_leftover_other_worktree_spec() {
    local out
    put_spec "$WT_DIR" beta 42
    # その作業フォルダのセッションの記録が無いとき: active_session は null
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{leftovers}}')" = 1 ] || die "leftovers の数が1でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$WT" ] || die "folder が worktree でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{is_self}')" = false ] || die "is_self が偽でない: $out"
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = spec ] || die "kinds が spec でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{branch}')" = feat/wt ] || die "branch が feat/wt でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}')" = null ] || die "記録が無いのに active_session が null でない: $out"
    # その作業フォルダに作業中のセッションの記録があるとき: active_session にその記録が出る
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 77 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{session_id}')" = s-wt ] || die "active_session に s-wt が出ない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{started_at}')" = 300 ] || die "active_session の started_at が違う: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{last_seen}')" = 305 ] || die "active_session の last_seen が違う: $out"
    # 作業中でない(Issueの記録に同じ session_id も同じ folder も無い)セッションは active_session に出ない
    rm -f "$STATE/issues/77.json"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}')" = null ] || die "作業中でないセッションが active_session に出た: $out"
}

t_leftover_committed_spec_ignored() {
    local out
    put_spec "$WT_DIR" beta 42
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m beta
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "コミット済みの spec が leftovers に出た: $out"
    # コミット済みでも、直してまだコミットしていなければ出る
    printf '{"feature_name":"beta","issue":42,"phase":"x"}\n' >"$WT_DIR/.kiro/specs/beta/spec.json"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$WT" ] || die "直した spec が leftovers に出ない: $out"
}

t_leftover_additional_issue() {
    local out
    put_spec "$WT2_DIR" gamma 5 '[42]'
    put_spec "$WT_DIR" delta 43
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{folder} } @{$d->{leftovers}}')" = "$WT2" ] \
        || die "additional_issues に 42 を含む spec だけが出ていない: $out"
}

t_leftover_self() {
    local out
    put_spec "$MAIN_DIR" beta 42
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 100
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{leftovers}}')" = 1 ] || die "leftovers の数が1でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$MAIN" ] || die "folder がいまの作業フォルダでない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{is_self}')" = true ] || die "is_self が真でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}')" = null ] || die "自分が active_session に出た: $out"
}

t_leftover_own_claim_excluded() {
    local out
    put_spec "$MAIN_DIR" beta 42
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 100
    ss "$MAIN_DIR" claim 42 --branch main --session s-me || die "claim の終了コード $?"
    # Issueの記録の folder がいまの作業フォルダで session_id が自分なら、自分の作りかけとして除く
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "自分の作りかけが leftovers に出た: $out"
    # 別のセッションから見ると、作りかけとして出る
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-other) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{is_self}')" = true ] || die "別のセッションから見て is_self の作りかけが出ない: $out"
    # コミットしていない spec は、コミットしていない変更でもある
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = spec,changes,branch ] || die "kinds が spec,changes,branch でない: $out"
}

t_leftover_branch_without_spec() {
    local out
    put_issue 43 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 43 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{leftovers}}')" = 1 ] || die "leftovers の数が1でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$WT" ] || die "folder が worktree でない: $out"
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = branch ] || die "kinds が branch でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{branch}')" = feat/wt ] || die "branch が違う: $out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[]' ] || die "開かれているブランチが branch_only に出た: $out"
    # コミットしていない変更があれば changes も付く
    echo change >"$WT_DIR/work.txt"
    out=$(check_start "$MAIN_DIR" check-start 43 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = changes,branch ] || die "kinds が changes,branch でない: $out"
    # ほかのIssueの番号では出ない
    out=$(check_start "$MAIN_DIR" check-start 44 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "ほかのIssueの番号で leftovers が出た: $out"
}

t_leftover_handed_over_excluded() {
    local out
    put_spec "$WT_DIR" beta 42
    put_spec "$MAIN_DIR" beta 42
    put_issue 42 "$MAIN" main s-me "[\"$WT\"]"
    out=$(check_start "$WT2_DIR" check-start 42 --session s-wt2) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{folder} } @{$d->{leftovers}}')" = "$MAIN" ] \
        || die "handed_over_from の作業フォルダが除かれていない: $out"
}

t_branch_only() {
    local out
    git -C "$MAIN_DIR" branch -q feat/extra "$SEED_SHA"
    put_issue 42 "" feat/extra ""
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[{"branch":"feat/extra","where":"local"}]' ] || die "ローカルのブランチが出ない: $out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "どこでも開かれていないブランチが leftovers に出た: $out"
    git -C "$MAIN_DIR" branch -q -D feat/extra
    git -C "$MAIN_DIR" update-ref refs/remotes/origin/feat/extra "$SEED_SHA"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[{"branch":"feat/extra","where":"remote"}]' ] || die "リモートのブランチが出ない: $out"
    git -C "$MAIN_DIR" update-ref -d refs/remotes/origin/feat/extra
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[]' ] || die "どこにも無いブランチが branch_only に出た: $out"
}

# =====================================================================
# check-start: 作業中のセッションの数(要件3.6)
# =====================================================================
t_capacity() {
    local out
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_issue 51 "$MAIN" main s-me
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 200
    put_issue 50 "$WT" feat/wt s-wt
    # Issueの記録の無いセッション(着手していない)は作業中に数えない
    put_session s-idle "$WT2" "$(fkey "$WT2_DIR")" 300
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{capacity}{limit}')" = 1 ] || die "limit が1でない: $out"
    [ "$(pj "$out" '$d->{capacity}{active}')" = "[{\"folder\":\"$WT\",\"issue\":50,\"last_seen\":205}]" ] \
        || die "active が自分以外の作業中のセッションだけでない: $out"
    git -C "$MAIN_DIR" config keirekipro.parallelSlots 2
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{capacity}{limit}')" = 2 ] || die "設定の数が limit に出ない: $out"
    # 同じ folder のIssueの記録があれば、session_id が違っても作業中とみなす
    put_issue 52 "$WT2" feat/wt2 ""
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{issue} } @{$d->{capacity}{active}}')" = 50,52 ] \
        || die "同じ folder のIssueの記録があるセッションが active に出ない: $out"
}

# =====================================================================
# claim
# =====================================================================
t_claim() {
    local f got
    put_session s-me "$WT" "$(fkey "$WT_DIR")" 100
    ss "$WT_DIR" claim 42 --branch feat/wt --session s-me || die "claim の終了コード $?"
    f="$STATE/issues/42.json"
    [ -f "$f" ] || die "issues/42.json が無い"
    got=$(pj "$(cat "$f")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}, scalar @{$d->{handed_over_from}}')
    [ "$got" = "42|$WT|feat/wt|s-me|0" ] || die "記録の中身が違う: $(cat "$f")"
    case "$(pj "$(cat "$f")" '$d->{updated_at}')" in '' | *[!0-9]*) die "updated_at が UNIX 秒でない: $(cat "$f")" ;; esac
    # すでにあれば folder branch session_id updated_at を書き直し、handed_over_from は残す
    put_issue 42 "$WT2" feat/old s-old "[\"$WT2\"]"
    ss "$MAIN_DIR" claim 42 --branch main --session s-new || die "2回目の claim の終了コード $?"
    got=$(pj "$(cat "$f")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}, @{$d->{handed_over_from}}')
    [ "$got" = "42|$MAIN|main|s-new|$WT2" ] || die "書き直した記録が違う: $(cat "$f")"
    [ "$(pj "$(cat "$f")" '$d->{updated_at}')" != 1 ] || die "updated_at が書き直されていない"
    # --session が無いときは、いまの作業フォルダのいちばん古い記録のID
    ss "$WT_DIR" claim 43 --branch feat/wt || die "--session の無い claim の終了コード $?"
    [ "$(pj "$(cat "$STATE/issues/43.json")" '$d->{session_id}')" = s-me ] || die "--session が無いときのIDが違う"
}

t_claim_usage() {
    local rc
    ss "$MAIN_DIR" claim 42 >/dev/null 2>&1
    rc=$?
    [ "$rc" != 0 ] || die "--branch の無い claim を受け付けた"
    ss "$MAIN_DIR" claim abc --branch x >/dev/null 2>&1
    rc=$?
    [ "$rc" != 0 ] || die "数でないIssueの番号を受け付けた"
    [ ! -d "$STATE/issues" ] || [ -z "$(ls "$STATE/issues")" ] || die "誤った呼び方で記録を書いた"
}

# =====================================================================
# spec-names(要件1.1)
# =====================================================================
t_spec_names() {
    local out
    put_spec "$WT_DIR" beta 42
    put_spec "$WT2_DIR" gamma 43
    out=$(ss "$MAIN_DIR" spec-names) || die "spec-names の終了コード $?"
    [ "$out" = "$(printf 'alpha\nbeta\ngamma')" ] || die "spec の名前の一覧が違う: $out"
    # worktree から呼んでも同じ
    out=$(ss "$WT2_DIR" spec-names) || die "spec-names の終了コード $?"
    [ "$out" = "$(printf 'alpha\nbeta\ngamma')" ] || die "worktree から呼んだ一覧が違う: $out"
}

# =====================================================================
# prune(この小タスクでは呼べて何もしない)と docker
# =====================================================================
t_prune_callable() {
    put_session s-x "$WT" "$(fkey "$WT_DIR")" 100
    ss "$MAIN_DIR" prune || die "prune の終了コード $?"
    [ -f "$STATE/sessions/s-x.json" ] || die "prune が記録を消した"
}

t_no_docker_in_check_start() {
    local out
    put_spec "$WT_DIR" beta 42
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    ss "$MAIN_DIR" claim 42 --branch main --session s-me || die "claim が失敗した"
    ss "$MAIN_DIR" spec-names >/dev/null || die "spec-names が失敗した"
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "docker が呼ばれた: $(cat "$FAKE_DOCKER_LOG")"
}

echo "--- check-start: 同じ作業フォルダの別のセッション(要件5.1・5.2)"
run_test "同じ作業フォルダに別の作業中のセッションの記録があると folder_conflict に出る" t_folder_conflict
run_test "同じ作業フォルダの、Issueの記録の無いセッション(着手していない記録)は folder_conflict に出ない" t_folder_conflict_idle_ignored
run_test "--session が無いときは、いまの作業フォルダのいちばん古い記録を自分として除く" t_folder_conflict_without_session
run_test "end のあとの check-start では folder_conflict が空になる" t_end_clears_conflict
run_test "end はパスを含むIDを受け付けない" t_end_rejects_path

echo "--- check-start: Issueの作りかけ(要件4.1・4.2)"
run_test "別の worktree のコミットしていない spec が leftovers に出て、セッションの記録の有無が active_session に出る" t_leftover_other_worktree_spec
run_test "コミット済みの spec は leftovers に出ない" t_leftover_committed_spec_ignored
run_test "additional_issues に N を含む spec も leftovers に出る" t_leftover_additional_issue
run_test "いまの作業フォルダの作りかけは is_self が真で出る" t_leftover_self
run_test "自分が claim した作りかけは leftovers に出ない" t_leftover_own_claim_excluded
run_test "spec の無いIssueもIssueの記録のブランチで見つかる" t_leftover_branch_without_spec
run_test "handed_over_from の作業フォルダは leftovers に出ない" t_leftover_handed_over_excluded
run_test "どこでも開かれていないIssueのブランチが branch_only に出る" t_branch_only

echo "--- check-start: 作業中のセッションの数(要件3.6)"
run_test "capacity に自分以外の作業中のセッションが出る" t_capacity

echo "--- claim・spec-names・prune"
run_test "claim がIssueの記録を書き、すでにあれば書き直す" t_claim
run_test "claim は誤った呼び方で記録を書かない" t_claim_usage
run_test "spec-names がほかの worktree の spec の名前も出す" t_spec_names
run_test "prune は呼べて、記録を変えない" t_prune_callable
run_test "check-start・claim・spec-names は docker を呼ばない" t_no_docker_in_check_start

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
