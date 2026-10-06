#!/bin/bash
# =====================================================================
# Git Bash の引数の書き換えを止める変数(.claude/settings.json の env の MSYS2_ARG_CONV_EXCL)が働いているかを確かめるテスト
#
# 実行: bash .claude/hooks/tests/test-path-conversion.sh
# 次の4つの場合を確かめる。
#   場合1: settings.json の env の MSYS2_ARG_CONV_EXCL が * である
#   場合2: その値を入れて git に渡した引数が、書いたとおりの文字で git に届く
#   場合3: 変数を外すと書き換わる(場合2が書き換えを見分けられること。Windows の Git Bash のときだけ)
#   場合4: Claude Code の Bash ツールから流したとき、いまのシェルの MSYS2_ARG_CONV_EXCL が * である
# ファイルを書かず、git の設定も変えない。
# 前提: bash・perl(JSON::PP)・git。
# =====================================================================
set -u

SETTINGS="$(dirname "$0")/../../settings.json"

pass=0
fail=0

ok() {
    pass=$((pass + 1))
    printf 'ok: %s\n' "$1"
}

ng() { # <場合の名前> <理由>
    fail=$((fail + 1))
    printf 'FAIL: %s\n' "$1"
    printf '    %s\n' "$2"
}

skip() { # <場合の名前> <理由>
    printf 'skip: %s: 確かめない(%s)\n' "$1" "$2"
}

# ---------------------------------------------------------------------
# 場合1: settings.json の env の MSYS2_ARG_CONV_EXCL を読む
CASE1="場合1: settings.json の env の MSYS2_ARG_CONV_EXCL が * である"
excl=""
if [ ! -f "$SETTINGS" ]; then
    ng "$CASE1" "settings.json が無い: $SETTINGS"
elif ! excl=$(perl -MJSON::PP -e '
        local $/;
        open my $fh, "<", $ARGV[0] or die "読めない: $!\n";
        my $d = eval { JSON::PP->new->decode(<$fh>) };
        die "JSON として読めない: $@" unless defined $d;
        die "最上位がオブジェクトでない\n" unless ref $d eq "HASH";
        die "env が無い\n" unless ref $d->{env} eq "HASH";
        die "env に MSYS2_ARG_CONV_EXCL が無い\n" unless exists $d->{env}{MSYS2_ARG_CONV_EXCL};
        my $v = $d->{env}{MSYS2_ARG_CONV_EXCL};
        die "MSYS2_ARG_CONV_EXCL が文字列でない\n" if !defined $v || ref $v;
        print $v;
    ' -- "$SETTINGS" 2>&1); then
    ng "$CASE1" "$excl"
    excl=""
elif [ "$excl" != "*" ]; then
    ng "$CASE1" "値が * でない: '$excl'"
else
    ok "$CASE1"
fi

# ---------------------------------------------------------------------
# 場合2: 場合1で読んだ値を入れて、git に引数を渡す
# git は Windows では MSYS でないプログラムなので、受け取った引数をそのまま表示させれば書き換えが起きたかが分かる。
# いまのシェルの MSYS_NO_PATHCONV で通ってしまわないよう、MSYS_NO_PATHCONV は外す。
CASE2="場合2: settings.json の値で、git に引数が書いたとおりの文字で届く"
want2=" '/kiro-spec-quick' '--title=/kiro-spec-quick' '/a:/b' '/foo:/bar'"
if [ -n "$excl" ]; then
    got2=$(env -u MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL="$excl" \
        git rev-parse --sq-quote /kiro-spec-quick --title=/kiro-spec-quick /a:/b /foo:/bar 2>&1)
else
    got2=$(env -u MSYS_NO_PATHCONV -u MSYS2_ARG_CONV_EXCL \
        git rev-parse --sq-quote /kiro-spec-quick --title=/kiro-spec-quick /a:/b /foo:/bar 2>&1)
fi
if [ "$got2" = "$want2" ]; then
    ok "$CASE2"
else
    ng "$CASE2" "期待 [$want2] / 実際 [$got2]"
fi

# ---------------------------------------------------------------------
# 場合3: 変数を外すと書き換わる(場合2が書き換えを見分けられることを確かめる)
CASE3="場合3: 変数を外すと git に書き換わった文字が届く"
case "$(uname -s)" in
    MINGW* | MSYS*)
        got3=$(env -u MSYS2_ARG_CONV_EXCL -u MSYS_NO_PATHCONV git rev-parse --sq-quote /kiro-spec-quick 2>&1)
        if [ "$got3" != " '/kiro-spec-quick'" ]; then
            ok "$CASE3"
        else
            ng "$CASE3" "変数を外しても書き換わらなかった: [$got3]"
        fi
        ;;
    *)
        skip "$CASE3" "Windows の Git Bash でないため"
        ;;
esac

# ---------------------------------------------------------------------
# 場合4: Claude Code の Bash ツールから流したとき、いまのシェルに値が届いている
CASE4="場合4: いまのシェルの MSYS2_ARG_CONV_EXCL が * である"
if [ -n "${CLAUDECODE+x}" ]; then
    if [ "${MSYS2_ARG_CONV_EXCL-}" = "*" ]; then
        ok "$CASE4"
    else
        ng "$CASE4" "いまのシェルの値: '${MSYS2_ARG_CONV_EXCL-<設定なし>}'"
    fi
else
    skip "$CASE4" "Claude Code の外で流したため"
fi

echo
echo "成功 ${pass} 件 / 失敗 ${fail} 件"
[ "$fail" -eq 0 ]
