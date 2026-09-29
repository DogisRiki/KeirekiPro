#!/bin/bash
# =====================================================================
# PreToolUse(Bash) hook: mainブランチ保護と、commit / push の書き方の固定
#
# mainブランチ上での git commit / git push、および強制pushを
# 実行前にブロックする(exit 2 = ブロック)。
# git -C <path> commit/push の形式も捕捉する。
#
# あわせて、git commit / git push は次の形の単独のコマンドだけを通す。
#   git commit -F <メッセージのファイル>
#   git push -u origin <ブランチ名>
#   git push origin <ブランチ名>
# この形は .claude/settings.json の許可ルール(Bash(git commit *) /
# Bash(git push -u origin *) / Bash(git push origin *))にそのまま当たる。
# 形がずれると許可ルールに当たらず、auto mode の判定に回って止められる
# ことがある(2026-09-28 と 09-29 に `git push -q -u origin` で発生)。
# 他のコマンドと && などでつないだ場合も、全体が判定に回る。
#
# 前提: bash と perl(JSON::PP)。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
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

# commit / push の書き方を固定する。
# コマンドの先頭か区切り(&& || ; | 改行 ( { $( ` と、sh -c の引用符の直後)に
# git commit / git push があるときだけ調べる。区切りの後の do / then / if /
# command / env / time などの前置きと、変数の代入(X=1)は読み飛ばす。
# 引用符の中の文字列(grep "git push" など)は対象にしない。
# コマンドの文字を見るだけなので、安全境界ではない(別のプログラムの中から
# 起動する push などは見逃す)。目的は、形のずれによる事故を止めること。
verdict=$(printf '%s' "$command" | perl -e '
    local $/; my $c = <STDIN>;
    my $git = qr/git(?:\s+-C\s+\S+)?\s+(commit|push)\b/;
    my $sep = qr/\A|&&|\|\||[;|\n(`{]|\$\(|\b(?:ba|z)?sh\s+-c\s+["\x27]/;
    my $pre = qr/(?:(?:do|then|else|elif|if|while|until|!|command|builtin|exec|env|time|nice|nohup|xargs)\s+(?:-\S+\s+)*)*/;
    exit 0 unless $c =~ /(?:$sep)\s*$pre(?:\w+=\S*\s+)*$git/;
    my $t = $c; $t =~ s/\A\s+//; $t =~ s/\s+\z//;
    exit 0 if $t =~ /\Agit commit -F (?:"[^"\n]+"|\x27[^\x27\n]+\x27|[^\s"\x27;&|`\$()<>]+)\z/;
    exit 0 if $t =~ /\Agit push (?:-u )?origin [A-Za-z0-9._\/-]+\z/;
    print "ng";
')
if [ "$verdict" = "ng" ]; then
    cat >&2 <<'MSG'
git commit / git push は、次の形の単独のコマンドで実行してください(他のコマンドと && ; | でつながない、オプションを足さない)。
  git commit -F <メッセージのファイル>
  git push -u origin <ブランチ名>
  git push origin <ブランチ名>
この形は .claude/settings.json の許可ルールにそのまま当たります。形がずれると auto mode の判定に回り、止められることがあります。
git add や git log などは、別のコマンドとして先に(または後に)実行してください。
MSG
    exit 2
fi

exit 0
