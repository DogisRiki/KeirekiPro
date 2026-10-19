#!/bin/bash
# =====================================================================
# inject-writing-rules.sh(書き方の決まりの要点を渡すフック)のテスト
#
# 実行: bash .claude/hooks/tests/test-inject-writing-rules.sh
# CLAUDE_PROJECT_DIR を一時のフォルダに向け、そこに決まりのファイルを置いてフックを動かし、
# 標準出力と終了コードを確かめる。本物の決まりのファイルには触れない。
# 登録のテストは、このテストの場所から決めたリポジトリの最上位の .claude/settings.json を読む(書き換えない)。
# 前提: bash・perl(JSON::PP)。ホストの Git Bash からも Linux からも流せる。
# =====================================================================
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/inject-writing-rules.sh"
TOP="$(cd "$(dirname "$0")/../../.." && pwd)"
SETTINGS="$TOP/.claude/settings.json"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
PROJECT="$TMP_ROOT/project"
RULES="$PROJECT/.kiro/settings/rules/owner-writing.md"
UNREADABLE='[writing] 書き方の決まりのファイル .kiro/settings/rules/owner-writing.md を読めない'
HEADER='[writing] 所有者に送る文は、次の決まりで書き、送る前に自分で読み直す。例は .kiro/settings/rules/owner-writing.md にある。'
REST='残りの決まりは owner-writing.md を開いて読む'

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    rm -rf "$PROJECT"
    mkdir -p "$(dirname "$RULES")"
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# フックを動かし、標準出力を OUT に、終了コードを CODE に入れる
run_hook() {
    OUT=$(printf '{"prompt":"テスト"}' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK")
    CODE=$?
}

# 文字数(バイトではない)を数える
char_count() {
    printf '%s' "$1" | perl -CS -0777 -ne 'print length'
}

t_three_rules() {
    cat >"$RULES" <<'EOF'
# 所有者に送る文の書き方の決まり

## 送る前の読み直し

### 前置きの見出し

この見出しは決まりの節の外にあるので、書かない。

## 決まり

### 文ごとに主語と目的語を書く

Claude は、文ごとに、主語と目的語を書く。主語は動作をする人や物である。

**外れた文の例**(例の一覧の組40)

> 例の文その1。

### 造語を使わない

Claude は、造語を使わない。
所有者が知らない言葉は伝わらない。

**直した文の例**

> 例の文その2。

### 矢印でつながない

Claude は、手順を矢印でつながない

## 決まりと例を足すとき

### 手順の見出し

この見出しは決まりの節の外にあるので、書かない。
EOF
    run_hook
    local expected
    expected="$HEADER
- 文ごとに主語と目的語を書く: Claude は、文ごとに、主語と目的語を書く。
- 造語を使わない: Claude は、造語を使わない。
- 矢印でつながない: Claude は、手順を矢印でつながない"
    [ "$CODE" -eq 0 ] || die "終了コードが0でない: $CODE"
    [ "$OUT" = "$expected" ] || die "出力が違う:
$OUT"
    case "$OUT" in
        *例の文* | *主語は動作をする* | *所有者が知らない* | *前置きの見出し* | *手順の見出し*)
            die "決まりの名前と1文目のほかの文を書いた:
$OUT" ;;
    esac
}

t_no_file() {
    run_hook
    [ "$CODE" -eq 0 ] || die "終了コードが0でない: $CODE"
    [ "$OUT" = "$UNREADABLE" ] || die "出力が違う:
$OUT"
}

t_no_section() {
    cat >"$RULES" <<'EOF'
# 所有者に送る文の書き方の決まり

## 送る前の読み直し

### 文ごとに主語と目的語を書く

Claude は、文ごとに、主語と目的語を書く。
EOF
    run_hook
    [ "$CODE" -eq 0 ] || die "終了コードが0でない: $CODE"
    [ "$OUT" = "$UNREADABLE" ] || die "出力が違う:
$OUT"
}

t_over_limit() {
    {
        printf '## 決まり\n\n'
        local i
        for i in $(seq 1 200); do
            printf '### 決まりの名前その%d\n\n' "$i"
            printf 'Claude は、%d番目の決まりとして、とても長い文を、所有者に送る文の書き方の決まりの1文目として、何度も繰り返し書いて、九千字を超えるようにする。2文目は書かない。\n\n' "$i"
        done
    } >"$RULES"
    run_hook
    [ "$CODE" -eq 0 ] || die "終了コードが0でない: $CODE"
    local n last
    n=$(char_count "$OUT")
    [ "$n" -le 10000 ] || die "出力が1万字を超えた: $n 字"
    last=$(printf '%s\n' "$OUT" | tail -n 1)
    [ "$last" = "$REST" ] || die "最後の行が違う: $last"
    case "$OUT" in
        *その200:*) die "9千字を超えた分の行を書いた" ;;
    esac
}

# settings.json を JSON::PP で読み、UserPromptSubmit に、このフックを timeout 10 で呼ぶ項目が1つだけあるかを確かめる
t_registered() {
    local problems
    # perl が止まったときは、登録を確かめないまま合格にしないよう、テストの失敗にする
    if ! problems=$(perl -MJSON::PP -e '
        my ($file) = @ARGV;
        open my $fh, "<:raw", $file or do { print "settings.json が読めない: $file\n"; exit 0 };
        local $/; my $text = <$fh>; close $fh;
        my $s = eval { JSON::PP->new->utf8->decode($text) };
        unless (ref $s eq "HASH") { print "settings.json が JSON のオブジェクトとして読めない: $file\n"; exit 0 }
        my $hooks = $s->{hooks};
        my $ups = ref $hooks eq "HASH" ? $hooks->{UserPromptSubmit} : undef;
        unless (ref $ups eq "ARRAY") { print "hooks.UserPromptSubmit が配列でない\n"; exit 0 }
        my $want = q{bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/inject-writing-rules.sh"};
        my $n = 0;
        for my $e (@$ups) {
            next unless ref $e eq "HASH" && ref $e->{hooks} eq "ARRAY";
            for my $h (@{ $e->{hooks} }) {
                next unless ref $h eq "HASH" && ($h->{type} // "") eq "command";
                $n++ if ($h->{command} // "") eq $want && ($h->{timeout} // 0) == 10;
            }
        }
        print "UserPromptSubmit に、inject-writing-rules.sh を timeout 10 で呼ぶ項目が1つでない($n 個)\n"
            unless $n == 1;
    ' -- "$SETTINGS" 2>&1); then
        die "settings.json を確かめる perl が失敗した: $problems"
    fi
    [ -z "$problems" ] || die "$problems"
}

echo "--- 決まりの要点を渡す"
run_test "決まりが3つあるとき、3つの名前と1文目だけを書き、例の文を書かない" t_three_rules
echo "--- 決まりのファイルを読めないとき"
run_test "決まりのファイルが無いとき、読めないことの1行だけを書き、0で終わる" t_no_file
run_test "## 決まり の節が無いとき、読めないことの1行だけを書き、0で終わる" t_no_section
echo "--- 長さ"
run_test "9千字を超えるとき、出力が1万字を超えず、最後に残りを開くよう促す1行がある" t_over_limit
echo "--- 登録"
run_test "settings.json の UserPromptSubmit に、このフックが10秒の打ち切りで登録されている" t_registered

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
