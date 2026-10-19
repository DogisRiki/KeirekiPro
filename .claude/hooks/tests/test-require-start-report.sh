#!/bin/bash
# =====================================================================
# require-start-report.sh のテスト
#
# 実行: bash .claude/hooks/tests/test-require-start-report.sh
# 会話の記録(transcript)を作り、フックに Edit などの入力(JSON)を渡して、
# 終了コード(0 = 通す / 2 = 止める)を確かめる。止めたときは、理由が標準エラーに出ることも確かめる。
# 前提: bash・perl(JSON::PP)。
# =====================================================================
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/require-start-report.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/proj"
OUTSIDE="$WORK/scratchpad"
mkdir -p "$ROOT" "$OUTSIDE"

pass=0
fail=0

# 会話の記録の1行を作る。種類ごとに引数の形が違う。
#   start               : 利用者が /start #1 を打った行
#   meta <文>           : スキルの本文など、isMeta の利用者の行
#   result              : ツールの結果の行
#   user <文>           : 所有者が言った行
#   text <文>           : AIの文
#   skill <名前>        : AIが Skill を呼んだ行
#   edit                : AIが Edit を呼んだ行
line() {
    perl -MJSON::PP -e '
        my ($kind, $arg) = @ARGV;
        utf8::decode($arg) if defined $arg;
        my %d;
        if ($kind eq "start") {
            %d = (type => "user", message => {role => "user", content =>
                "<command-message>start</command-message>\n<command-name>/start</command-name>\n<command-args>#1</command-args>"});
        } elsif ($kind eq "meta") {
            %d = (type => "user", isMeta => JSON::PP::true, message => {role => "user", content => [{type => "text", text => $arg}]});
        } elsif ($kind eq "result") {
            %d = (type => "user", message => {role => "user", content => [{type => "tool_result", tool_use_id => "x", content => "ok"}]});
        } elsif ($kind eq "user") {
            %d = (type => "user", message => {role => "user", content => $arg});
        } elsif ($kind eq "text") {
            %d = (type => "assistant", message => {role => "assistant", content => [{type => "text", text => $arg}]});
        } elsif ($kind eq "skill") {
            %d = (type => "assistant", message => {role => "assistant", content => [{type => "tool_use", id => "s", name => "Skill", input => {skill => $arg}}]});
        } elsif ($kind eq "edit") {
            %d = (type => "assistant", message => {role => "assistant", content => [{type => "tool_use", id => "e", name => "Edit", input => {file_path => "a"}}]});
        }
        print JSON::PP->new->utf8->canonical->encode(\%d), "\n";
    ' -- "$@"
}

REPORT='## してほしいこと
何もしなくて大丈夫です。このまま実装を始めます。判断がおかしいと思ったら止めてください

## 判断: spec を作らずに実装する

## 理由
| 観点 | 当たるか | 根拠 |
|---|---|---|'

# expect <期待する終了コード> <説明> <記録のファイル> <書き換えるファイル> [欄=値 ...]
#   欄: tool(既定 Edit)、key(既定 file_path)、agent_id、cwd、project(既定 $ROOT。空なら CLAUDE_PROJECT_DIR を外す)
expect() {
    local want="$1" desc="$2" tp="$3" file="$4" got err
    shift 4
    local tool=Edit key=file_path agent='' cwd="$ROOT" project="$ROOT"
    local kv
    for kv in "$@"; do
        case "$kv" in
            tool=*) tool=${kv#tool=} ;;
            key=*) key=${kv#key=} ;;
            agent=*) agent=${kv#agent=} ;;
            cwd=*) cwd=${kv#cwd=} ;;
            project=*) project=${kv#project=} ;;
        esac
    done
    local input
    input=$(perl -MJSON::PP -e '
        my ($tool, $key, $file, $tp, $agent, $cwd) = @ARGV;
        my %d = (hook_event_name => "PreToolUse", tool_name => $tool,
                 tool_input => {$key => $file}, transcript_path => $tp, cwd => $cwd);
        $d{agent_id} = $agent if length $agent;
        print JSON::PP->new->encode(\%d)' -- "$tool" "$key" "$file" "$tp" "$agent" "$cwd")
    if [ -n "$project" ]; then
        err=$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$project" bash "$HOOK" 2>&1 >/dev/null)
    else
        err=$(printf '%s' "$input" | env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>&1 >/dev/null)
    fi
    got=$?
    if [ "$got" != "$want" ]; then
        fail=$((fail + 1))
        printf 'FAIL: 期待 %s / 実際 %s: %s\n' "$want" "$got" "$desc"
        return
    fi
    if [ "$want" = 2 ]; then
        case "$err" in
            *'/start の判断の報告が、所有者に見える返答の本文にまだありません'*'## 判断'*'## 理由'*'考え(thinking)の中に書いた報告は'*) ;;
            *)
                fail=$((fail + 1))
                printf 'FAIL: 止めた理由が標準エラーに無い: %s\n' "$desc"
                return
                ;;
        esac
    fi
    pass=$((pass + 1))
}

IN="$ROOT/src/a.ts"

echo "--- 止める形"
T="$WORK/t1.jsonl"
{ line start; line meta 'Base directory for this skill'; line result; line result; line text 'ブランチを作って記録しました。'; } > "$T"
expect 2 '報告を書かずに書き換える' "$T" "$IN"
expect 2 'Write でも止める' "$T" "$IN" tool=Write
expect 2 'NotebookEdit の notebook_path でも止める' "$T" "$ROOT/n.ipynb" tool=NotebookEdit key=notebook_path
expect 2 'CLAUDE_PROJECT_DIR が無ければ cwd で作業フォルダを決める' "$T" "$IN" project=
expect 2 'CLAUDE_PROJECT_DIR の中なら cwd の外でも止める' "$T" "$IN" cwd="$OUTSIDE"

T="$WORK/t2.jsonl"
{ line start; line text '## 判断: spec を作らずに実装する'; } > "$T"
expect 2 '「## 判断」だけで「## 理由」が無い' "$T" "$IN"

T="$WORK/t3.jsonl"
{ line start; line text 'spec 無しの判断です。実装に入ります。'; line edit; line result; } > "$T"
expect 2 '1文の知らせだけ' "$T" "$IN"

T="$WORK/t4.jsonl"
{ line skill start; line meta 'Base directory for this skill'; line result; } > "$T"
expect 2 'AIが Skill で start を呼んだあと、報告が無い' "$T" "$IN"

T="$WORK/t5.jsonl"
{ line start; line text "$REPORT"; line user 'ありがとう'; line start; line result; } > "$T"
expect 2 '前の /start には報告があり、次の /start には無い' "$T" "$IN"

T="$WORK/t6.jsonl"
{ line start; line text '判断と理由はあとで書きます'; } > "$T"
expect 2 '見出しでない「判断」「理由」の語は報告に数えない' "$T" "$IN"

echo "--- 通す形"
T="$WORK/t7.jsonl"
{ line user 'このファイルを直して'; line result; } > "$T"
expect 0 '/start の無い会話' "$T" "$IN"

T="$WORK/t8.jsonl"
{ line start; line result; line text "$REPORT"; line result; } > "$T"
expect 0 '報告を書いたあと' "$T" "$IN"

T="$WORK/t9.jsonl"
{ line start; line text '## 判断: spec を作らずに実装する'; line result; line text '## 理由
| 観点 | 当たるか | 根拠 |'; } > "$T"
expect 0 '「## 判断」と「## 理由」が別の文に分かれている' "$T" "$IN"

T="$WORK/t10.jsonl"
{ line start; line result; line text '問いがあります。'; line user '全部推奨で'; line result; } > "$T"
expect 0 '所有者が次に何か言ったあと' "$T" "$IN"

T="$WORK/t11.jsonl"
{ line start; line result; } > "$T"
expect 0 '作業フォルダの外(scratchpad)のファイル' "$T" "$OUTSIDE/body.md"
expect 0 '作業フォルダと名前の頭だけ同じフォルダ' "$T" "${ROOT}2/a.ts"
expect 0 'サブエージェントの書き換え' "$T" "$IN" agent=abc123
expect 0 '会話の記録が無い' "$WORK/none.jsonl" "$IN"
expect 0 'Skill で start 以外を呼んでも見張りを始めない' "$WORK/t7.jsonl" "$IN"

T="$WORK/t12.jsonl"
{ line skill verify-all; line result; } > "$T"
expect 0 'start 以外のスキル' "$T" "$IN"

echo "--- Windows のパスの形"
T="$WORK/t1.jsonl"
WIN_ROOT='C:/Users/me/proj'
expect 2 '逆スラッシュと大文字小文字の違いを同じフォルダとみなす' "$T" 'c:\USERS\me\proj\src\a.ts' project="$WIN_ROOT" cwd="$WIN_ROOT"
expect 2 '/c/ の形の作業フォルダ' "$T" 'C:\Users\me\proj\src\a.ts' project='/c/Users/me/proj' cwd='/c/Users/me/proj'
expect 0 'ほかのドライブ' "$T" 'D:\Users\me\proj\src\a.ts' project="$WIN_ROOT" cwd="$WIN_ROOT"

echo "合格 $pass / 不合格 $fail"
[ "$fail" = 0 ]
