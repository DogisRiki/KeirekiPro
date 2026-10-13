#!/bin/bash
# =====================================================================
# check-issue-labels.sh のテスト
#
# 実行: bash .claude/hooks/tests/test-check-issue-labels.sh
# 一時フォルダに git のリポジトリを作って origin を設定し、.github/labels.json を置く。
# フックに Bash ツールの入力(JSON)を、cwd にそのフォルダを入れて渡し、
# 終了コード(0 = 通す / 2 = 止める)と、止めたときの標準エラーの文を確かめる。
# ラベルの一覧のファイルは、テストの中で作る小さなもの(リポジトリのファイルと同じ形)を使う。
# 前提: bash・perl(JSON::PP・Text::ParseWords)・git。
# =====================================================================
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/check-issue-labels.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# Windows の Git Bash では、git に渡すパスをドライブ文字の形にする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# フックには、テストで渡す cwd と CLAUDE_PROJECT_DIR だけからファイルを探させる
unset CLAUDE_PROJECT_DIR
# 一時フォルダより上のフォルダを、git がリポジトリとして見つけないようにする
export GIT_CEILING_DIRECTORIES="$WORK"

ORIGIN=https://github.com/DogisRiki/KeirekiPro.git

# labels_json <kind/bug の area_required> <足す種類のラベルの行(空なら足さない)>
labels_json() {
    cat <<EOF
{
  "labels": [
    {"name": "kind/bug", "group": "kind", "description": "今ある機能が本来の動きをしていないので、本来の動きに直す", "color": "d73a4a", "area_required": $1, "previous_names": ["bug"]},
    {"name": "kind/feature", "group": "kind", "description": "利用者や所有者が、今はできないことをできるようになる", "color": "0e8a16", "area_required": true},
    {"name": "kind/documentation", "group": "kind", "description": "人が読む文書だけを変える", "color": "0075ca", "area_required": true, "selection_rule": "README と doc/ の下の文書だけを変える Issue に付ける"},$2
    {"name": "retrospective", "group": "kind", "description": "ゲートすり抜けの振り返り", "color": "0e8a16", "area_required": false, "selection_rule": "振り返りの手順で起票する Issue にだけ付ける"},
    {"name": "area/app", "group": "area", "description": "利用者が使う画面・API・データベースの中身", "color": "f9d0c4"},
    {"name": "area/infra", "group": "area", "description": "アプリを動かす本番の AWS の環境", "color": "fef2c0"},
    {"name": "blocked", "group": "other", "description": "上流や外部要因で着手できない", "color": "b60205"}
  ]
}
EOF
}

# make_repo <フォルダ名> <origin の URL>
make_repo() {
    git init -q "$WORK/$1"
    git -C "$WORK/$1" remote add origin "$2"
    mkdir -p "$WORK/$1/.github"
}

make_repo main "$ORIGIN"
labels_json true "" >"$WORK/main/.github/labels.json"

make_repo ssh "git@github.com:DogisRiki/KeirekiPro.git"
labels_json true "" >"$WORK/ssh/.github/labels.json"

make_repo addtest "$ORIGIN"
labels_json true '
    {"name": "kind/test", "group": "kind", "description": "テスト用の種類", "color": "ededed", "area_required": true, "selection_rule": "テストのときだけ付ける"},' \
    >"$WORK/addtest/.github/labels.json"

make_repo bugnoarea "$ORIGIN"
labels_json false "" >"$WORK/bugnoarea/.github/labels.json"

make_repo nofile "$ORIGIN"
rmdir "$WORK/nofile/.github"

make_repo broken "$ORIGIN"
printf '{ "labels": [ {"name": "kind/bug", "group": ' >"$WORK/broken/.github/labels.json"

make_repo nokind "$ORIGIN"
printf '{"labels": [{"name": "area/app", "group": "area", "description": "x", "color": "f9d0c4"}]}' \
    >"$WORK/nokind/.github/labels.json"

# リポジトリの外のフォルダ
mkdir -p "$WORK/plain"

pass=0
fail=0
PROJ=""

# input <コマンド> <cwd(空なら欄を付けない)>
input() {
    printf '%s' "$1" | perl -MJSON::PP -e '
        local $/; my $c = <STDIN>;
        my %d = (hook_event_name => "PreToolUse", tool_name => "Bash", tool_input => {command => $c});
        $d{cwd} = $ARGV[0] if length $ARGV[0];
        print JSON::PP->new->encode(\%d)' -- "$2"
}

# run_hook: 標準入力をフックに渡す。PROJ が空でなければ CLAUDE_PROJECT_DIR に入れる
run_hook() {
    if [ -n "$PROJ" ]; then
        CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
    else
        bash "$HOOK"
    fi
}

# check <テスト名> <期待する終了コード> <cwd(空なら欄を付けない)> <コマンド> [<標準エラーに含まれるべき文>...]
# 止めるとき(2)は、標準エラーに「Issue の起票を止めました」が出ることも確かめる。
# 通すとき(0)は、標準エラーに何も出ないことも確かめる。
check() {
    local name="$1" want="$2" cwd="$3" cmd="$4" got err pat
    shift 4
    err=$(input "$cmd" "$cwd" | run_hook 2>&1 >/dev/null)
    got=$?
    if [ "$got" != "$want" ]; then
        fail=$((fail + 1))
        printf 'FAIL: %s: 期待 %s / 実際 %s: %s\n' "$name" "$want" "$got" "$(printf '%s' "$cmd" | head -1)"
        [ -n "$err" ] && printf '%s\n' "$err" | sed 's/^/    | /' | head -5
        return
    fi
    if [ "$want" = 2 ]; then
        set -- 'Issue の起票を止めました' "$@"
    elif [ -n "$err" ]; then
        fail=$((fail + 1))
        printf 'FAIL: %s: 通したのに標準エラーに文が出た: %s\n' "$name" "$cmd"
        return
    fi
    for pat in "$@"; do
        case "$err" in
            *"$pat"*) ;;
            *)
                fail=$((fail + 1))
                printf 'FAIL: %s: 標準エラーに「%s」が無い: %s\n' "$name" "$pat" "$cmd"
                printf '%s\n' "$err" | sed 's/^/    | /' | head -20
                return
                ;;
        esac
    done
    pass=$((pass + 1))
}

M="$WORK/main"

echo "--- 止める形"
T='ラベル無しを止める'
check "$T" 2 "$M" 'gh issue create --title t --body b' '種類のラベルが付いていません'
check "$T" 2 "$M" 'gh issue create --title "a b" --body-file body.md --assignee @me'
check "$T" 2 "$M" 'GH_TOKEN=invalid gh issue create --title t --body b'
check "$T" 2 "$M" 'git switch -c x && gh issue create --title t --body b 2>&1 | tail -1'
check "$T" 2 "$M" 'C:/Program\ Files/GitHub\ CLI/gh.exe issue create --title t --body b'
check "$T" 2 "$M" 'gh issue create --title t --body b --label blocked'
check "$T" 2 "$M" 'gh issue create --title t --body b --label area/app'
check "$T" 2 "$M" "gh issue create --title t --body \"\$(cat <<'EOF'
本文の --label kind/bug は値なので数えない
EOF
)\""
check "$T" 2 "$M" 'gh issue create --title a --body b --label kind/bug --label area/app; gh issue create --title c --body d'

T='gh issue new のラベル無しを止める'
check "$T" 2 "$M" 'gh issue new --title t --body b' '種類のラベルが付いていません'

T="url=\$(gh issue create ...) のラベル無しを止める"
check "$T" 2 "$M" "url=\$(gh issue create --title t --body b)" '種類のラベルが付いていません'
check "$T" 2 "$M" "url=\"\$(gh issue create --title t --body b)\""
check "$T" 2 "$M" "url=\`gh issue create --title t --body b\`"
check "$T" 2 "$M" "echo \"\$(gh issue create --title t --body b --label area/app)\""

T='sh -c の中のラベル無しを止める'
check "$T" 2 "$M" "sh -c 'gh issue create --title t --body b'" '種類のラベルが付いていません'
check "$T" 2 "$M" 'bash -c "cd x && gh issue create --title t --body b"'

T='種類のラベルのカンマ区切りの2つを止める'
check "$T" 2 "$M" 'gh issue create --title t --body b --label kind/bug,kind/feature --label area/app' '種類のラベルが 2 個' 'kind/bug' 'kind/feature'
check "$T" 2 "$M" 'gh issue create --title t --body b --label "kind/bug, kind/feature,area/app"' '種類のラベルが 2 個'

T='--label の重ね書きの2つを止める'
check "$T" 2 "$M" 'gh issue create --title t --body b --label kind/bug --label kind/feature --label area/app' '種類のラベルが 2 個'
check "$T" 2 "$M" 'gh issue create --title t --body b -l kind/bug -l retrospective'

T='area_required が true の種類で場所のラベル無しを止める'
check "$T" 2 "$M" 'gh issue create --title t --body b --label kind/bug' '種類のラベル kind/bug は場所のラベルが要りますが、場所のラベルが付いていません'
check "$T" 2 "$M" 'gh issue create --title t --body b --label kind/feature --label blocked'

T='ファイルが無いときに止める'
check "$T" 2 "$WORK/nofile" 'gh issue create --title t --body b --label kind/bug --label area/app' 'ラベルの一覧のファイルを読めません' '所有者に伝えて'

T='ファイルが壊れているときに止める'
check "$T" 2 "$WORK/broken" 'gh issue create --title t --body b --label kind/bug --label area/app' 'ラベルの一覧のファイルを読めません'
check "$T" 2 "$WORK/nokind" 'gh issue create --title t --body b --label kind/bug --label area/app' 'ラベルの一覧のファイルを読めません'

T='gh api で Issue を作るコマンドを止める'
check "$T" 2 "$M" 'gh api repos/o/r/issues -f title=x' 'gh api で Issue を作るコマンドは使えません'
check "$T" 2 "$M" 'gh api /repos/o/r/issues/ -F title=x -F labels[]=kind/bug'
check "$T" 2 "$M" 'gh api repos/{owner}/{repo}/issues --raw-field title=x'
check "$T" 2 "$M" 'gh api repos/o/r/issues --field=title=x'
check "$T" 2 "$M" 'gh api -X POST repos/o/r/issues --input body.json'
check "$T" 2 "$M" 'gh api --method post repos/o/r/issues'
check "$T" 2 "$M" "gh api graphql -f query='mutation{createIssue(input:{repositoryId:\"x\",title:\"t\"}){issue{number}}}'" 'gh api で Issue を作るコマンドは使えません'
check "$T" 2 "$WORK/nofile" 'gh api repos/o/r/issues -f title=x' 'gh api で Issue を作るコマンドは使えません'

T='--web と --template を止める'
for opt in --web -w '--template bug_report.md' '-T bug_report.md' '--template=bug_report.md' '--recover input.json' --editor -e; do
    check "$T" 2 "$M" "gh issue create --title t --body b --label kind/bug --label area/app $opt" 'ラベルを確かめられない形' '--title と --body'
done

echo "--- 通す形"
T='種類のラベル1つと場所のラベル1つを付けた起票を通す'
check "$T" 0 "$M" 'gh issue create --title t --body-file b.md --label kind/bug --label area/app'
check "$T" 0 "$M" 'gh issue create -t t -F b.md -l kind/bug -l area/app'
check "$T" 0 "$M" 'GH_TOKEN=x gh issue create --title "a b" --body b --label kind/bug --label area/app --label blocked'
check "$T" 0 "$M" "bash -c 'gh issue create --title t --body b --label kind/bug --label area/app'"
check "$T" 0 "$M" 'gh issue create --title t --body b --label kind/bug --label kind/bug --label area/app'
check "$T" 0 "$M" "gh issue create --title t --label kind/bug --label area/app --body \"\$(cat <<'EOF'
本文の1行目
gh issue create の話をする行
EOF
)\""
check "$T" 0 "$M" 'gh issue create --title a --body b --label kind/bug --label area/app && gh issue create --title c --body d --label retrospective'

T='場所のラベル2つを付けた起票を通す'
check "$T" 0 "$M" 'gh issue create --title t --body b --label kind/feature --label area/app --label area/infra'
check "$T" 0 "$M" 'gh issue create --title t --body b --label "kind/feature, area/app,area/infra"'

T='ラベルの大文字と小文字の違いを通す'
check "$T" 0 "$M" 'gh issue create --title t --body b --label Kind/Bug --label AREA/APP'

T='--label=kind/bug の形を通す'
check "$T" 0 "$M" 'gh issue create --title t --body b --label=kind/bug --label=area/app'
check "$T" 0 "$M" 'gh issue create --title t --body b -l=kind/bug -larea/app'

T="url=\$(gh issue create ... --label kind/bug --label area/app) を通す"
check "$T" 0 "$M" "url=\$(gh issue create --title t --body b --label kind/bug --label area/app)"
check "$T" 0 "$M" "url=\$(gh issue create --title t --body b --label kind/bug --label area/app) && echo \"\$url\""
check "$T" 0 "$M" "url=\"\$(gh issue create --title t --body b --label kind/bug --label area/app)\""

T='area_required が false の種類だけの起票を通す'
check "$T" 0 "$M" 'gh issue create --title t --body b --label retrospective'

T='-R でほかのリポジトリへの起票を通す'
check "$T" 0 "$M" 'gh issue create -R other/repo --title t --body b'
check "$T" 0 "$M" 'gh issue create --repo=github.com/someone/else --title t --body b --web'
check "$T" 0 "$WORK/ssh" 'gh issue create --repo other/repo --title t --body b'
check "$T" 0 "$WORK/nofile" 'gh issue -R other/repo create --title t --body b'

T='-R でこのリポジトリを指す起票は止める'
check "$T" 2 "$M" 'gh issue create -R DogisRiki/KeirekiPro --title t --body b' '種類のラベルが付いていません'
check "$T" 2 "$M" 'gh issue create --repo dogisriki/keirekipro --title t --body b'
check "$T" 2 "$WORK/ssh" 'gh issue create -R https://github.com/DogisRiki/KeirekiPro.git --title t --body b'
check "$T" 2 "$WORK/ssh" 'gh issue create -R github.com/DogisRiki/KeirekiPro --title t --body b'

T='gh と issue の間の -R でこのリポジトリを指すラベル無しの起票を止める'
check "$T" 2 "$M" 'gh -R DogisRiki/KeirekiPro issue create -t t -b b' '種類のラベルが付いていません'
check "$T" 2 "$M" 'gh --repo DogisRiki/KeirekiPro issue create -t t -b b'
check "$T" 2 "$M" 'gh --repo=dogisriki/keirekipro issue new -t t -b b'
check "$T" 2 "$WORK/ssh" 'gh -RDogisRiki/KeirekiPro issue create -t t -b b'

T='gh と issue の間の -R でほかのリポジトリを指す起票を通す'
check "$T" 0 "$M" 'gh -R other/repo issue create -t t -b b'
check "$T" 0 "$M" 'gh --repo other/repo issue create -t t -b b'
check "$T" 0 "$M" 'gh --repo=other/repo issue new -t t -b b'
check "$T" 0 "$WORK/nofile" 'gh -Rother/repo issue create -t t -b b'

T='gh issue edit --add-label を通す'
check "$T" 0 "$M" 'gh issue edit 12 --add-label kind/bug'
check "$T" 0 "$M" 'gh issue edit 12 --remove-label bug --add-label kind/bug,area/app'
check "$T" 0 "$M" 'gh issue comment 12 --body "gh issue create を使う"'

T='gh issue list を通す'
check "$T" 0 "$M" 'gh issue list --label kind/bug'
check "$T" 0 "$M" 'gh issue view 12 --json labels'
check "$T" 0 "$M" 'gh issue create --help'

T='gh api の -X GET の読み取りを通す'
check "$T" 0 "$M" 'gh api repos/o/r/issues -X GET -f state=open'
check "$T" 0 "$M" 'gh api --method GET repos/o/r/issues -F per_page=100'
check "$T" 0 "$M" 'gh api repos/o/r/issues'
check "$T" 0 "$M" 'gh api -X POST repos/o/r/issues/12/comments -f body=x'
check "$T" 0 "$M" 'gh api -X PATCH repos/o/r/issues/12 -f state=closed'
check "$T" 0 "$M" "gh api graphql -f query='query{repository(owner:\"o\",name:\"r\"){id}}'"

T='ヒアドキュメントの本文の行はコマンドとして読まない'
check "$T" 0 "$M" "gh issue create --title t --body-file - --label kind/bug --label area/app <<'EOF'
gh issue create --title 本文の中の例
EOF"
check "$T" 0 "$M" "cat <<-EOF >b.md
	gh issue create --title 本文の中の例
	EOF
gh issue create --title t --body-file b.md --label kind/bug --label area/app"
check "$T" 2 "$M" "cat <<EOF >b.md
本文
EOF
gh issue create --title t --body-file b.md" '種類のラベルが付いていません'
check "$T" 2 "$M" "cat <<-EOF >b.md
	本文
	EOF
gh issue create --title t --body-file b.md" '種類のラベルが付いていません'

T='bash <<EOF の本文のラベル無しの起票を止める'
check "$T" 2 "$M" "bash <<'EOF'
gh issue create --title t --body b
EOF" '種類のラベルが付いていません'
check "$T" 2 "$M" "cd x && /usr/bin/bash <<EOF
echo start
gh issue new --title t --body b
EOF"
check "$T" 2 "$M" "bash.exe -s <<\"EOF\" 2>&1
gh issue create --title t --body b --label kind/bug
EOF" '場所のラベルが付いていません'
check "$T" 2 "$M" "bash <<A; cat <<B
gh issue create --title t --body b
A
gh issue create --title 本文の中の例
B" '種類のラベルが付いていません'
check "$T" 2 "$M" "cat <<A; bash <<B
gh issue create --title 本文の中の例 --label kind/bug --label area/app
A
gh issue create --title t --body b
B" '種類のラベルが付いていません'
check "$T" 0 "$M" "bash <<'EOF'
gh issue create --title t --body b --label kind/bug --label area/app
EOF"
check "$T" 0 "$M" "bash <<'EOF'
cat <<'INNER' >b.md
gh issue create --title 本文の中の例
INNER
gh issue create --title t --body-file b.md --label retrospective
EOF"

T='sh -s <<EOF の本文のラベル無しの起票を止める'
check "$T" 2 "$M" "sh -s <<EOF
gh issue create --title t --body b
EOF" '種類のラベルが付いていません'
check "$T" 2 "$M" "sh <<-EOF
	gh issue create --title t --body b
	EOF"
check "$T" 2 "$M" "GH_TOKEN=x sh -s -- a <<'EOF'
gh api repos/o/r/issues -f title=x
EOF" 'gh api で Issue を作るコマンドは使えません'

T='cat <<EOF の本文の gh issue create の行では止めない'
check "$T" 0 "$M" "cat <<EOF >b.md
gh issue create --title 本文の中の例
EOF"
check "$T" 0 "$M" "gh issue create --title t --label retrospective --body \"\$(cat <<'EOF'
gh issue create --title 本文の中の例
EOF
)\""
check "$T" 0 "$M" "tee b.md <<'EOF' | bash -c 'cat >/dev/null'
gh issue create --title 本文の中の例
EOF"

T='Issue を作らないコマンドを通す'
check "$T" 0 "$M" 'echo "gh issue create --title t"'
check "$T" 0 "$M" 'grep -rn "gh issue create" .claude'
check "$T" 0 "$M" 'git status'
check "$T" 0 "$WORK/nofile" 'gh pr create --title t --body b'

echo "--- ファイルに従うこと"
T='kind/test を足したファイルで kind/test の起票を通す'
check "$T" 0 "$WORK/addtest" 'gh issue create --title t --body b --label kind/test --label area/app'
check "$T" 2 "$M" 'gh issue create --title t --body b --label kind/test --label area/app' '種類のラベルが付いていません'

T='kind/bug の area_required を false に変えたファイルで場所のラベル無しの起票を通す'
check "$T" 0 "$WORK/bugnoarea" 'gh issue create --title t --body b --label kind/bug'
check "$T" 2 "$M" 'gh issue create --title t --body b --label kind/bug' '場所のラベルが付いていません'

echo "--- ファイルを読む場所"
T='cwd がリポジトリの中のフォルダならリポジトリの最上位のファイルを読む'
check "$T" 0 "$M/.github" 'gh issue create --title t --body b --label kind/bug --label area/app'
check "$T" 2 "$M/.github" 'gh issue create --title t --body b --label kind/bug'

T='cwd の区切りが \ でも読む'
check "$T" 0 "${M//\//\\}" 'gh issue create --title t --body b --label kind/bug --label area/app'
check "$T" 2 "${M//\//\\}" 'gh issue create --title t --body b --label kind/bug'

T='cwd がリポジトリの外なら CLAUDE_PROJECT_DIR の下のファイルを読む'
PROJ="$WORK/bugnoarea"
check "$T" 0 "$WORK/plain" 'gh issue create --title t --body b --label kind/bug'
check "$T" 0 "" 'gh issue create --title t --body b --label kind/bug'
check "$T" 2 "$WORK/plain" 'gh issue create --title t --body b' '種類のラベルが付いていません'

T='cwd がリポジトリなら CLAUDE_PROJECT_DIR を見ない'
check "$T" 2 "$WORK/nofile" 'gh issue create --title t --body b --label kind/bug' 'ラベルの一覧のファイルを読めません'
PROJ=""

T='cwd も CLAUDE_PROJECT_DIR も無いときに止める'
check "$T" 2 "$WORK/plain" 'gh issue create --title t --body b --label kind/bug --label area/app' 'ラベルの一覧のファイルを読めません'
check "$T" 2 "" 'gh issue create --title t --body b --label kind/bug --label area/app' 'ラベルの一覧のファイルを読めません'

echo "--- 止めたときの文"
T='止めたときの文に種類のラベルの一覧と場所のラベルの一覧が出る'
check "$T" 2 "$M" 'gh issue create --title t --body b' \
    'kind/bug: 今ある機能が本来の動きをしていないので、本来の動きに直す(場所のラベル: 要る)' \
    'kind/feature: 利用者や所有者が、今はできないことをできるようになる(場所のラベル: 要る)' \
    'kind/documentation: 人が読む文書だけを変える(場所のラベル: 要る)' \
    '選ぶときの決まり: README と doc/ の下の文書だけを変える Issue に付ける' \
    'retrospective: ゲートすり抜けの振り返り(場所のラベル: 要らない)' \
    '選ぶときの決まり: 振り返りの手順で起票する Issue にだけ付ける' \
    'area/app: 利用者が使う画面・API・データベースの中身' \
    'area/infra: アプリを動かす本番の AWS の環境' \
    '.claude/skills/file-issue/SKILL.md の「ラベルの選び方」'
check "$T" 2 "$WORK/addtest" 'gh issue create --title t --body b' \
    'kind/test: テスト用の種類(場所のラベル: 要る)' '選ぶときの決まり: テストのときだけ付ける'
check "$T" 2 "$WORK/bugnoarea" 'gh issue create --title t --body b' \
    'kind/bug: 今ある機能が本来の動きをしていないので、本来の動きに直す(場所のラベル: 要らない)'
# そのほかのラベルは一覧に出さない
err=$(input 'gh issue create --title t --body b' "$M" | run_hook 2>&1 >/dev/null)
case "$err" in
    *blocked*)
        fail=$((fail + 1))
        printf 'FAIL: %s: そのほかのラベル blocked が一覧に出た\n' "$T"
        ;;
    *) pass=$((pass + 1)) ;;
esac

echo "--- 入力が読めないとき"
T='入力が JSON でないときに通す'
got=$(printf 'not json' | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$got" = 0 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf 'FAIL: %s: 期待 0 / 実際 %s\n' "$T" "$got"
fi
T='コマンドの欄が無いときに通す'
got=$(printf '{"tool_input":{},"cwd":"%s"}' "$M" | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$got" = 0 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf 'FAIL: %s: 期待 0 / 実際 %s\n' "$T" "$got"
fi

echo
echo "結果: ${pass} 件成功 / ${fail} 件失敗"
[ "$fail" -eq 0 ]
