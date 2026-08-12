#!/bin/bash
# =====================================================================
# PreToolUse(Bash) hook: mainブランチ保護
#
# mainブランチ上での git commit / git push、および強制pushを
# 実行前にブロックする(exit 2 = ブロック)。
# git -C <path> commit/push の形式も捕捉する。
# 前提: Git for Windows(Git Bash同梱)。JSON解析は同梱perl(JSON::PP)を使用。
# =====================================================================
set -u

payload=$(cat)

extract() {
    printf '%s' "$payload" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d;
        my $v = $d;
        for my $k (@ARGV) { $v = eval { $v->{$k} }; last unless defined $v; }
        print $v if defined $v && !ref $v;
    ' -- "$@" 2>/dev/null
}

command=$(extract tool_input command)
[ -z "$command" ] && exit 0

# git -C <path> 形式のオプションを許容する共通パターン
GIT='git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?'

# 強制pushは常にブロック
if printf '%s' "$command" | grep -Eq "${GIT}push\b.*([[:space:]]--force([[:space:]]|\$)|--force-with-lease|[[:space:]]-f([[:space:]]|\$))"; then
    echo "強制push(--force / -f)はブロックされています。履歴の書き換えが必要な場合は人間に相談してください。" >&2
    exit 2
fi

# git commit / git push はカレントブランチを確認
if printf '%s' "$command" | grep -Eq "(^|[[:space:]]|&&|;)${GIT}(commit|push)\b"; then
    # -C <path> が指定されていればそのリポジトリのブランチを見る
    cpath=$(printf '%s' "$command" | perl -ne 'print $1 if /git\s+-C\s+(\S+)/' | head -1)
    if [ -n "$cpath" ]; then
        cpath=${cpath//\\//}
        branch=$(git -C "$cpath" branch --show-current 2>/dev/null)
    else
        cwd=$(extract cwd)
        cwd=${cwd//\\//}
        if [ -n "$cwd" ] && [ -d "$cwd" ]; then
            cd "$cwd" || exit 0
        fi
        branch=$(git branch --show-current 2>/dev/null)
    fi
    if [ "$branch" = "main" ]; then
        echo "mainブランチでのcommit/pushはブロックされています。.branch_name_template に従ってfeatureブランチを作成してください(例: git switch -c feat/xxx)。" >&2
        exit 2
    fi
    # mainへの直接push(他ブランチからの明示指定)もブロック
    if printf '%s' "$command" | grep -Eq "${GIT}push[[:space:]]+[^[:space:]]+[[:space:]]+.*\bmain\b"; then
        echo "mainブランチへの直接pushはブロックされています。featureブランチをpushしてPR経由でマージしてください。" >&2
        exit 2
    fi
fi

exit 0
