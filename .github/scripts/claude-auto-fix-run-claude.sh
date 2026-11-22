#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の edit ジョブで、Claude を1回動かし、結果を見分け、変更を差分に書き出すスクリプト
# (design.md の claude-auto-fix-run-claude.sh の節)
#
# 使い方: claude-auto-fix-run-claude.sh <材料のファイル> <差分の出力先>
#
# 環境変数:
#   CLAUDE_CODE_OAUTH_TOKEN  Claude の鍵(secrets.CLAUDE_CODE_OAUTH_TOKEN)。空なら Claude を動かさずに key にする
#   RUNNER_TEMP              設定のファイルと、空の HOME と CLAUDE_CONFIG_DIR を作るフォルダ(必須)
#   CAF_PROMPT               指示の文のファイル(既定は .github/claude-auto-fix/prompt.md)
#   CAF_TARGET_DIR           Claude に直させる作業のフォルダ(既定は今のフォルダの target)。
#                            Git のリポジトリで、起点のコードの差分は index に入れておく。
#                            このスクリプトは、index と作業のフォルダの違いだけを Claude の変更として書き出す
#
# 標準出力には、次の2行だけを書く。
#   outcome=<ok|key|unavailable|unfixed>
#   reason=<理由の種類>
# 理由の種類:
#   ok          changed            変更があり、差分を書き出した
#   key         key-missing        鍵が空だった
#               auth-failed        結果の文が Failed to authenticate で始まるか、api_error_status が 401
#   unavailable usage-limit        結果の文が You've hit your で始まるか、api_error_status が 429
#               timeout            30分で打ち切った
#               unreadable-result  結果の JSON を読めなかった
#               execution-error    error_during_execution か、そのほかの失敗
#   unfixed     max-turns          60往復で直し終えられなかった
#               no-change          変更が空だった
#               secret-in-diff     差分に鍵の値か sk-ant- で始まる文字列があった
# ok のときだけ差分の出力先にファイルを書き、そのほかのときは差分を捨てる。
#
# Claude の会話の記録と結果の JSON の本文は、標準出力にも標準エラーにも出さない(要件 5.1)。
# CLI は env -i で動かし、PATH と空の HOME と空の CLAUDE_CONFIG_DIR と鍵のほかの環境変数を渡さない。
# GitHub のトークンを Claude に渡さないためである(要件 3.3)。
# CLI の終わり方の番号は見分けに使わない。誤った鍵でも結果の JSON は出て、終わり方は 1 になるため
# (research.md の「Claude の CLI の結果の JSON の確認」)。
#
# 引数と環境の誤りは 2 で終わる。差分を書き出せないなどの、このスクリプトの中の失敗は 1 で終わる。
# =====================================================================
set -euo pipefail

usage() {
    echo "::error::claude-auto-fix-run-claude: $1" >&2
    echo "使い方: claude-auto-fix-run-claude.sh <材料のファイル> <差分の出力先>" >&2
    exit 2
}
fail() {
    echo "::error::claude-auto-fix-run-claude: $1" >&2
    exit 1
}
result() {
    printf 'outcome=%s\nreason=%s\n' "$1" "$2"
    exit 0
}

[ $# -eq 2 ] || usage "引数は2つです(${#}個でした)"
MATERIALS="$1"
PATCH_OUT="$2"
[ -f "$MATERIALS" ] && [ -r "$MATERIALS" ] || usage "材料のファイルを読めません: ${MATERIALS}"
[ -n "$PATCH_OUT" ] || usage "差分の出力先が空です"
[ -n "${RUNNER_TEMP:-}" ] && [ -d "$RUNNER_TEMP" ] || usage "RUNNER_TEMP のフォルダがありません"
PROMPT="${CAF_PROMPT:-$(dirname "${BASH_SOURCE[0]}")/../claude-auto-fix/prompt.md}"
[ -f "$PROMPT" ] && [ -r "$PROMPT" ] || usage "指示の文のファイルを読めません: ${PROMPT}"
TARGET="${CAF_TARGET_DIR:-target}"
[ -d "$TARGET" ] || usage "作業のフォルダがありません: ${TARGET}"
TARGET=$(cd "$TARGET" && pwd)
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || usage "作業のフォルダが Git のリポジトリではありません: ${TARGET}"
CLAUDE_BIN=$(command -v claude) || usage "Claude の CLI が PATH にありません"
RT=$(cd "$RUNNER_TEMP" && pwd)
KEY="${CLAUDE_CODE_OAUTH_TOKEN:-}"

# 差分の出力先には、ok のときだけファイルを置く
rm -f -- "$PATCH_OUT"

[ -n "$KEY" ] || result key key-missing

W=$(mktemp -d "$RT/caf-claude.XXXXXX") || fail "一時のフォルダを作れません"
trap 'rm -rf -- "$W"' EXIT
mkdir "$W/home" "$W/config"

# 設定のファイル: 作業のフォルダの外の読み書きを、どの権限の形でも断る。
# deny は念のための重ねで、--tools に Bash を入れないので、Claude はコマンドを動かせない
jq -n --arg rt "$RT" '{
    disableAllHooks: true,
    permissions: {
        blockReadsOutsideWorkingDirectories: true,
        blockWritesOutsideWorkingDirectories: true,
        deny: ["Bash", "WebFetch", "WebSearch", "Read(//proc/**)", "Read(//sys/**)", ("Read(/" + $rt + "/**)")]
    }
}' >"$W/settings.json" || fail "設定のファイルを書けません"

cat -- "$PROMPT" "$MATERIALS" >"$W/input.txt" || fail "Claude に渡す文を作れません"

CLI_PATH="$(dirname "$CLAUDE_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
rc=0
(
    cd "$TARGET"
    exec timeout --kill-after=1m 30m env -i PATH="$CLI_PATH" HOME="$W/home" CLAUDE_CONFIG_DIR="$W/config" \
        CLAUDE_CODE_OAUTH_TOKEN="$KEY" "$CLAUDE_BIN" -p --output-format json \
        --tools Read,Edit,Write,Glob,Grep --strict-mcp-config --permission-mode acceptEdits --max-turns 60 \
        --setting-sources user --settings "$W/settings.json" \
        <"$W/input.txt" >"$W/result.json" 2>"$W/stderr.txt"
) || rc=$?

# timeout は、打ち切ると 124 で、TERM で止まらずに KILL したときは 137 で終わる
case "$rc" in
124 | 137) result unavailable timeout ;;
esac

verdict=$(jq -rs --arg auth "Failed to authenticate" --arg limit "You've hit your" '
    if length == 1 and (.[0] | type) == "object" and .[0].type == "result" then
        .[0] as $o
        | ($o.result | if type == "string" then . else "" end) as $text
        | if ($text | startswith($auth)) or $o.api_error_status == 401 then "key auth-failed"
          elif ($text | startswith($limit)) or $o.api_error_status == 429 then "unavailable usage-limit"
          elif $o.subtype == "success" and ($o.is_error != true) then "ok changed"
          elif $o.subtype == "error_max_turns" then "unfixed max-turns"
          else "unavailable execution-error" end
    else error("not a result") end' "$W/result.json" 2>/dev/null) || result unavailable unreadable-result

case "$verdict" in
"ok changed") ;;
"key auth-failed") result key auth-failed ;;
"unavailable usage-limit") result unavailable usage-limit ;;
"unfixed max-turns") result unfixed max-turns ;;
*) result unavailable execution-error ;;
esac

# Claude が新しく作ったファイルも差分に入るよう、まだ追っていないファイルを intent-to-add で index に載せる
git -C "$TARGET" ls-files -z --others --exclude-standard >"$W/untracked" || fail "追っていないファイルを読めません"
if [ -s "$W/untracked" ]; then
    git -C "$TARGET" add --intent-to-add --pathspec-from-file="$W/untracked" --pathspec-file-nul ||
        fail "新しいファイルを index に載せられません"
fi
git -C "$TARGET" diff --binary >"$W/claude.patch" || fail "差分を書き出せません"

[ -s "$W/claude.patch" ] || result unfixed no-change
if grep -qF -- "$KEY" "$W/claude.patch" || grep -q 'sk-ant-' "$W/claude.patch"; then
    result unfixed secret-in-diff
fi

mv -- "$W/claude.patch" "$PATCH_OUT" || fail "差分を出力先に置けません: ${PATCH_OUT}"
result ok changed
