#!/usr/bin/env bash
# =====================================================================
# extract-decided-method.sh の自動テスト(codex-review の
# Test decided-method extraction の手順から実行)
#
# 一時ディレクトリに判定の基準の文書(spec.md)の見本を作ってスクリプトを呼び、
# 標準出力が期待と1バイトも違わないことと、終了コードを確かめる。
#   0  = 抜き出しが終わった(節が無いときと中身が空白だけのときは何も出さない)
#   64 = 引数の数が1つでない / 66 = 文書が無いか読めない
# 見本の1行目は、ワークフローが spec.md を書くときと同じく `# <題名>` にする。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/extract-decided-method.sh"
# 一時領域の確保に失敗したまま進むと rm -rf が意図しない絶対パスを対象にするため、
# ディレクトリが実在することを確認してから trap を設定する
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

DOC="$WORK/spec.md"
WANT="$WORK/want.txt"
OUT="$WORK/out.txt"
ERR_OUT="$WORK/err.txt"
CR=$(printf '\r')

fail() {
    printf 'FAIL %s (%s)\n' "$1" "$2"
    FAILED=1
}

# 使い方: check <説明>
# $DOC を引数に呼び、終了コードが0で、標準出力が $WANT と同じことを確かめる。
check() {
    local name="$1" got
    bash "$SCRIPT" "$DOC" >"$OUT" 2>"$ERR_OUT"
    got=$?
    if [ "$got" != 0 ]; then
        fail "$name" "期待 exit=0 / 実際 exit=$got"
        return
    fi
    if grep -q "$CR" "$OUT"; then
        fail "$name" "標準出力に \\r が残っている"
        return
    fi
    if ! cmp -s "$WANT" "$OUT"; then
        fail "$name" "標準出力が期待と違う。期待との差分は次のとおり"
        diff "$WANT" "$OUT" | sed 's/^/    /'
        return
    fi
    printf 'ok   %s\n' "$name"
}

# 使い方: check_error <説明> <期待する終了コード> [スクリプトに渡す引数...]
# 終了コードと、標準出力が空であることと、標準エラーが
# [extract-decided-method] で始まる1行であることを確かめる。
check_error() {
    local name="$1" want="$2" got lines first
    shift 2
    bash "$SCRIPT" "$@" >"$OUT" 2>"$ERR_OUT"
    got=$?
    if [ "$got" != "$want" ]; then
        fail "$name" "期待 exit=$want / 実際 exit=$got"
        return
    fi
    if [ -s "$OUT" ]; then
        fail "$name" "標準出力が空でない"
        return
    fi
    lines=$(awk 'END { print NR }' "$ERR_OUT")
    first=$(head -n 1 "$ERR_OUT")
    if [ "$lines" != 1 ]; then
        fail "$name" "標準エラーが1行でない(${lines}行)"
        return
    fi
    case "$first" in
        "[extract-decided-method]"*) ;;
        *)
            fail "$name" "標準エラーが [extract-decided-method] で始まらない"
            return
            ;;
    esac
    printf 'ok   %s\n' "$name"
}

# --- 見出しと項目2つ --------------------------------------------------------
cat >"$DOC" <<'EOF'
# 決めた方式のあるIssue

## 困っていること

- 困りごと

## 決めた方式

- 項目1
- 項目2

## どうなれば解決か

- 解決の形
EOF
printf -- '- 項目1\n- 項目2\n' >"$WANT"
check "見出しと項目2つから項目2つだけが出る(見出しの行と前後の空行は出ない)"

# --- 見出しが無い -----------------------------------------------------------
cat >"$DOC" <<'EOF'
# 見出しの無いIssue

## 困っていること

- 困りごと

## どうなれば解決か

- 解決の形
EOF
: >"$WANT"
check "見出しが無い文書では何も出ずに0で終わる"

# --- 似た見出し -------------------------------------------------------------
cat >"$DOC" <<'EOF'
# 似た見出しのIssue

## 決めた方式について

- 見出しの名前が違う

### 決めた方式

- 見出しの深さが違う
EOF
: >"$WANT"
check "名前か深さの違う見出しを節の始まりにしない"

# --- 中身が空行だけ ---------------------------------------------------------
printf '# 中身の無いIssue\n\n## 決めた方式\n\n   \n\n## どうなれば解決か\n\n- 解決の形\n' >"$DOC"
: >"$WANT"
check "見出しの中身が空行だけの文書では何も出ずに0で終わる"

# --- 節の終わりと3段目の見出し ---------------------------------------------
cat >"$DOC" <<'EOF'
# 小見出しのあるIssue

## 決めた方式

- 項目1

### 補足

- 項目2

## どうなれば解決か

- 解決の形
EOF
printf -- '- 項目1\n\n### 補足\n\n- 項目2\n' >"$WANT"
check "次の ## の見出しの手前で節が終わり、### の見出しは中身に含まれる"

cat >"$DOC" <<'EOF'
# 1段目の見出しで終わるIssue

## 決めた方式

- 項目1

# 別の大見出し

- 節の外
EOF
printf -- '- 項目1\n' >"$WANT"
check "1段目の # の見出しの手前で節が終わる"

# --- コードブロック ---------------------------------------------------------
cat >"$DOC" <<'EOF'
# コードブロックのあるIssue

## 決めた方式

- 項目1

```markdown
## コードブロックの中の行
```

- 項目2

## どうなれば解決か
EOF
cat >"$WANT" <<'EOF'
- 項目1

```markdown
## コードブロックの中の行
```

- 項目2
EOF
check '節の中の ``` のコードブロックにある ## の行で節が終わらない'

cat >"$DOC" <<'EOF'
# チルダのコードブロックのあるIssue

## 決めた方式

~~~
# コードブロックの中の1段目の行
~~~
- 項目1
EOF
cat >"$WANT" <<'EOF'
~~~
# コードブロックの中の1段目の行
~~~
- 項目1
EOF
check '節の中の ~~~ のコードブロックにある # の行で節が終わらない'

cat >"$DOC" <<'EOF'
# 節の外にコードブロックのあるIssue

## 背景

~~~
## 決めた方式

- コードブロックの中の項目
~~~

## どうなれば解決か

- 解決の形
EOF
: >"$WANT"
check "節の外のコードブロックにある ## 決めた方式 の行を節の始まりにしない"

cat >"$DOC" <<'EOF'
# 節の外のコードブロックのあとに本物の節があるIssue

```
## 決めた方式
- コードブロックの中の項目
```

## 決めた方式

- 本物の項目
EOF
printf -- '- 本物の項目\n' >"$WANT"
check "コードブロックの中の見出しを飛ばし、そのあとの本物の節を抜き出す"

# --- CRLF と見出しの末尾の空白 ---------------------------------------------
printf '# CRLFのIssue\r\n\r\n## 決めた方式\r\n\r\n- 項目1\r\n- 項目2\r\n\r\n## どうなれば解決か\r\n\r\n- 解決の形\r\n' >"$DOC"
printf -- '- 項目1\n- 項目2\n' >"$WANT"
check "CRLF の文書から節を抜き出し、出力に \\r が残らない"

printf '# 末尾に空白のあるIssue\n\n## 決めた方式   \n\n- 項目1\n- 項目2\n\n## どうなれば解決か\n' >"$DOC"
printf -- '- 項目1\n- 項目2\n' >"$WANT"
check "見出しの行の末尾に空白がある文書から節を抜き出す"

printf '# CRLFで末尾に空白のあるIssue\r\n\r\n## 決めた方式  \r\n\r\n- 項目1\r\n- 項目2\r\n' >"$DOC"
printf -- '- 項目1\n- 項目2\n' >"$WANT"
check "CRLF で見出しの末尾に空白がある文書から節を抜き出し、出力に \\r が残らない"

# --- 節が文書の最後にある ---------------------------------------------------
# gh issue view の本文は最後の改行が無いことがあるため、最後の行に改行を付けない
printf '# 最後に節のあるIssue\n\n## 困っていること\n\n- 困りごと\n\n## 決めた方式\n\n- 項目1\n- 項目2' >"$DOC"
printf -- '- 項目1\n- 項目2\n' >"$WANT"
check "節が文書の最後にあるとき、文書の終わりまでを出す"

# --- 節が2つ ---------------------------------------------------------------
cat >"$DOC" <<'EOF'
# 節が2つあるIssue

## 決めた方式

- 項目A1
- 項目A2

## 困っていること

- 困りごと

## 決めた方式

- 項目B1

EOF
printf -- '- 項目A1\n- 項目A2\n\n- 項目B1\n' >"$WANT"
check "節が2つあるとき、2つの中身が文書の順に空行1つで区切って出る"

# 中身が空白だけの節は、区切りの空行も出さない(出力の先頭に空行を作らない)
printf '# 1つ目の節が空のIssue\n\n## 決めた方式\n\n   \n\n## 困っていること\n\n- 困りごと\n\n## 決めた方式\n\n- 項目B1\n' >"$DOC"
printf -- '- 項目B1\n' >"$WANT"
check "中身が空白だけの節のあとに中身のある節があるとき、2つ目の中身だけが出て先頭に空行が無い"

# --- 見出しの空白の数と種類、空白の無い # の行 ------------------------------
printf '# 空白が2つの見出しのIssue\n\n##  決めた方式\n\n- 項目1\n#タグ\n- 項目2\n\n## どうなれば解決か\n' >"$DOC"
printf -- '- 項目1\n#タグ\n- 項目2\n' >"$WANT"
check "## のあとの空白が2つの見出しを節の始まりにし、# のあとに空白の無い行で節が終わらない"

printf '# タブの見出しのIssue\n\n##\t決めた方式\n\n- 項目1\n\n## どうなれば解決か\n' >"$DOC"
printf -- '- 項目1\n' >"$WANT"
check "## のあとがタブの見出しを節の始まりにする"

# --- 引数と文書の誤り -------------------------------------------------------
check_error "引数が無いときは64で終わり、標準エラーに理由が出る" 64
check_error "引数が2つのときは64で終わり、標準エラーに理由が出る" 64 "$DOC" "$DOC"
check_error "文書が無いときは66で終わり、標準エラーに理由が出る" 66 "$WORK/no-such-spec.md"

if [ "$FAILED" -ne 0 ]; then
    echo "::error::extract-decided-method.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
