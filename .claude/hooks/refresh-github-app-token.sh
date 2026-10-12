#!/bin/bash
# =====================================================================
# SessionStart / UserPromptSubmit / PreToolUse(Bash) hook:
# Claude の手元の gh の GitHub App のトークンを入れ替える
#
# .claude/scripts/github-app/refresh-token.sh を --force を付けずに呼ぶだけである。
# 期限まで10分以上あれば refresh-token.sh は何もしないので、毎回呼んでも発行は期限の前の1回で済む。
# PreToolUse でも呼ぶのは、長い作業の途中でトークンが切れないようにするためである。
#   SessionStart / UserPromptSubmit  入れ替えに失敗したら、理由を標準出力に出す
#                                    (終了コード0の標準出力は Claude の会話に載る。
#                                    https://code.claude.com/docs/en/hooks の「Exit code 0」)
#   PreToolUse                       何も出さない
# refresh-token.sh の場所は CLAUDE_PROJECT_DIR から組み立てる(テストは CLAUDE_PROJECT_DIR を
# 一時的なディレクトリに向けて、偽物の refresh-token.sh を呼ばせる)。
# 作業を止めない: 終了コードはいつも0にする。refresh-token.sh が無い作業フォルダ(この仕組みより前の
# ブランチ)では何もしない。
# 前提: bash と perl(JSON::PP)。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
# =====================================================================
set -u

payload=$(cat)

event=$(printf '%s' "$payload" | perl -MJSON::PP -e '
    local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
    exit 0 unless ref $d eq "HASH";
    my $v = $d->{hook_event_name};
    print $v if defined $v && !ref $v;
' 2>/dev/null)

case "$event" in
    SessionStart | UserPromptSubmit | PreToolUse) ;;
    *) exit 0 ;;
esac

project=${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}
script="${project//\\//}/.claude/scripts/github-app/refresh-token.sh"
[ -f "$script" ] || exit 0

# GH_CONFIG_DIR は .claude/settings.local.json の env で入る。フックの処理に env が届かないときに備え、
# 環境に無ければ settings.local.json の env.GH_CONFIG_DIR を読んで渡す(環境にあれば、そちらを使う)
local_settings="${project//\\//}/.claude/settings.local.json"
if [ -z "${GH_CONFIG_DIR:-}" ] && [ -f "$local_settings" ]; then
    dir=$(perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d eq "HASH" && ref $d->{env} eq "HASH";
        my $v = $d->{env}{GH_CONFIG_DIR};
        print $v if defined $v && !ref $v;
    ' <"$local_settings" 2>/dev/null)
    if [ -n "$dir" ]; then
        export GH_CONFIG_DIR="$dir"
    fi
fi

if reason=$(bash "$script" 2>&1 >/dev/null </dev/null); then
    exit 0
else
    rc=$?
fi

if [ "$event" != PreToolUse ]; then
    # 会話に載る量を抑える(Claude Code は標準出力を10,000文字で切る)。文字の途中で切らないよう文字の数で切る
    printf 'GitHub App のトークンを入れ替えられなかった(refresh-token.sh の終了コード %s): %s\n' \
        "$rc" "$(printf '%s' "${reason:-理由の出力なし}" | perl -CS -0777 -ne 'print substr($_, 0, 2000)' 2>/dev/null)"
fi
exit 0
