#!/bin/bash
# =====================================================================
# PreToolUse(Bash) hook: mainブランチ保護
#
# mainブランチ上での git commit / git push、および強制pushを
# 実行前にブロックする(exit 2 = ブロック)。
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

# 強制pushは常にブロック
if printf '%s' "$command" | grep -Eq 'git[[:space:]]+push\b.*([[:space:]]--force([[:space:]]|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$))'; then
    echo "強制push(--force / -f)はブロックされています。履歴の書き換えが必要な場合は人間に相談してください。" >&2
    exit 2
fi

# git commit / git push はカレントブランチを確認
if printf '%s' "$command" | grep -Eq '(^|[[:space:]]|&&|;)git[[:space:]]+(commit|push)\b'; then
    cwd=$(extract cwd)
    cwd=${cwd//\\//}
    if [ -n "$cwd" ] && [ -d "$cwd" ]; then
        cd "$cwd" || exit 0
    fi
    branch=$(git branch --show-current 2>/dev/null)
    if [ "$branch" = "main" ]; then
        echo "mainブランチでのcommit/pushはブロックされています。.branch_name_template に従ってfeatureブランチを作成してください(例: git switch -c feat/xxx)。" >&2
        exit 2
    fi
    # mainへの直接push(他ブランチからの明示指定)もブロック
    if printf '%s' "$command" | grep -Eq 'git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+.*\bmain\b'; then
        echo "mainブランチへの直接pushはブロックされています。featureブランチをpushしてPR経由でマージしてください。" >&2
        exit 2
    fi
fi

exit 0
