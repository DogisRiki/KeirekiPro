#!/bin/bash
# =====================================================================
# PreToolUse(Bash) hook: mainブランチ保護と、commit / push の書き方の固定
#
# mainブランチ上での git commit / git push、および強制pushを
# 実行前にブロックする(exit 2 = ブロック)。
# git と commit / push の間に git の全体の指定(-C <path>、-c <name>=<value>、
# --git-dir=<path>、--no-pager など)を置いた形も捕捉する。
# mainへの直接pushは、push の行き先が main か refs/heads/main のときだけ止め、
# 名前に main を含むほかのブランチ(feat/main-page など)は止めない。
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

# git と、commit / push の間に置ける git の全体の指定を読み飛ばす共通パターン(perl の正規表現)。
# 引数を別の語で取る指定(-C -c --git-dir --work-tree --namespace --attr-source --config-env)は
# 引数ごと読み飛ばす。引数は、引用符で囲んだ空白入りの形も読み飛ばす。
# それ以外の - で始まる語(--no-pager、-P、--git-dir=<path> など)は1語として読み飛ばす。
# 指定の一覧: https://git-scm.com/docs/git#_options
GIT_RE='git((?:\s+(?:(?:-C|-c|--git-dir|--work-tree|--namespace|--attr-source|--config-env)\s+(?:"[^"]*"|\x27[^\x27]*\x27|[^\s"\x27;&|]+)+|-[^\s;&|]*))*)\s+'
export GIT_RE

# コマンドの文字列が、perl の正規表現 $1 に当たるかを返す(0 = 当たる)。
# 正規表現の中の {GIT} は GIT_RE に置き換え、行ごとに ^ と $ を当てる。
matches() {
    printf '%s' "$command" | perl -e '
        local $/; my $c = <STDIN>;
        my $re = $ARGV[0]; $re =~ s/\{GIT\}/$ENV{GIT_RE}/g;
        exit($c =~ /$re/m ? 0 : 1);
    ' -- "$1"
}

# 強制pushは常にブロック
if matches '{GIT}push\b.*(?:\s--force(?:\s|$)|--force-with-lease|\s-f(?:\s|$))'; then
    echo "強制push(--force / -f)はブロックされています。履歴の書き換えが必要な場合は人間に相談してください。" >&2
    exit 2
fi

# git commit / git push はカレントブランチを確認
if matches '(?:^|\s|&&|;){GIT}(?:commit|push)\b'; then
    # -C <path> が指定されていればそのリポジトリのブランチを見る。
    # -C を2つ以上並べたときは、git と同じく、相対の場所を前の場所につなげる。
    cpath=$(printf '%s' "$command" | perl -e '
        local $/; my $c = <STDIN>; my $g = $ENV{GIT_RE};
        exit 0 unless $c =~ /(?:^|\s|&&|;)$g(?:commit|push)\b/m;
        my $opts = $1; my $p = "";
        while ($opts =~ /(?:^|\s)-C\s+((?:"[^"]*"|\x27[^\x27]*\x27|[^\s"\x27;&|]+)+)/g) {
            (my $d = $1) =~ s/["\x27]//g;
            $p = ($p eq "" || $d =~ m{\A(?:/|[A-Za-z]:|\\)}) ? $d : "$p/$d";
        }
        print $p;
    ')
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
    # mainへの直接push(他ブランチからの明示指定)もブロック。
    # push の後ろの語のうち、行き先が main か refs/heads/main の語
    # (main、+main、HEAD:main、x:refs/heads/main など)だけを見る。
    to_main=$(printf '%s' "$command" | perl -e '
        local $/; my $c = <STDIN>; my $g = $ENV{GIT_RE};
        while ($c =~ /(?:^|\s|&&|;)${g}push\b([^\n;&|)]*)/mg) {
            for my $t (split /\s+/, $2) {
                $t =~ s/["\x27]//g;
                if ($t =~ m{(?:\A\+?|:)(?:refs/)?(?:heads/)?main\z}) { print "main"; exit 0 }
            }
        }
    ')
    if [ "$to_main" = "main" ]; then
        echo "mainブランチへの直接pushはブロックされています。featureブランチをpushしてPR経由でマージしてください。" >&2
        exit 2
    fi
fi

# commit / push の書き方を固定する。
# コマンドの先頭か区切り(&& || ; | 改行 ( { $( ` と、sh -c の引用符の直後)に
# git commit / git push があるときだけ調べる。区切りの後の do / then / if /
# command / env / time などの前置きと、変数の代入(X=1)は読み飛ばす。
# git と commit / push の間の git の全体の指定も読み飛ばして見つける。
# 引用符の中の文字列(grep "git push" など)は対象にしない。
# コマンドの文字を見るだけなので、安全境界ではない(別のプログラムの中から
# 起動する push などは見逃す)。目的は、形のずれによる事故を止めること。
verdict=$(printf '%s' "$command" | perl -e '
    local $/; my $c = <STDIN>;
    my $git = qr/$ENV{GIT_RE}(?:commit|push)\b/;
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
