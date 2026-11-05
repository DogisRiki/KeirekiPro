#!/bin/bash
# shellcheck disable=SC2016 # $d や $_ などは pj に渡す perl の式の変数で、シェルの変数ではない
# =====================================================================
# このリポジトリの部品の一覧を作るモジュール(inventory.pl)のテスト
#
# 実行: bash .claude/scripts/vuln-watch/tests/test-inventory.sh
# テストの場合ごとに、一時フォルダに、origin にする裸のリポジトリと、それを origin に持つ git のリポジトリを作り、
# 部品の見本(fixtures/test-inventory/)を main に置く。HOME を空の一時フォルダに替え、git のシステムの設定を読ませない。
# 前提: bash・perl(JSON::PP)・git
#
# 場合を選んで流す: KP_TEST_CASE='components head_fallback' bash .claude/scripts/vuln-watch/tests/test-inventory.sh
# 空白で区切った名前の場合だけを流す。どの場合にも合わない名前があれば、何も流さずに終了コード 2 で終わる
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
INVENTORY="$(cd "$HERE/.." && pwd)/inventory.pl"
FIX="$HERE/fixtures/test-inventory"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd -P; })

export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# 標準入力の JSON を $d に読み、perl の式を評価した値を出す: pj '<式>'
pj() {
    perl -MJSON::PP -e '
        my $d = JSON::PP->new->utf8->decode(do { local $/; <STDIN> });
        binmode STDOUT, ":encoding(UTF-8)";
        my $v = eval $ARGV[0];
        die $@ if $@;
        print defined $v ? $v : "<undef>";
    ' "$1"
}

# inventory_read を呼び、返した値を JSON で $CASE/out.json に書く
run_inventory() {
    perl -MJSON::PP -e '
        require $ARGV[0];
        print JSON::PP->new->utf8->canonical->encode(inventory_read($ARGV[1]));
    ' "$INVENTORY" "$CASE/repo" >"$CASE/out.json" 2>"$CASE/err.txt"
}

out() { pj "$1" <"$CASE/out.json"; }

# 部品の鍵ごとに「鍵=版,版」を並べる。一部だけの版の部品には ~ を付ける
COMPONENTS='join " ", map { my $c = $d->{components}{$_}; "$_=" . join(",", @{ $c->{versions} }) . ($c->{partial} ? "~" : "") } sort keys %{ $d->{components} }'
COMPONENTS_WANT='gradle-plugin:org.springframework.boot=4.1.2 maven:com.auth0:java-jwt=4.5.0 maven:org.mybatis.spring.boot:mybatis-spring-boot-starter=4.0.1 npm:@scope/alpha=1.2.3 npm:beta=2.0.0,2.1.0 npm:epsilon=5.0.0 npm:gamma=3.0.0 npm:pnpm=11.10.0 npm:react=19.0.0 runtime:java=21~ tool:gradle=9.8.2'

# 見本のファイルを、リポジトリの中の決まった場所に写す: place <リポジトリ>
place() {
    mkdir -p "$1/frontend" "$1/backend/gradle/wrapper"
    cp "$FIX/pnpm-lock.yaml" "$FIX/package.json" "$1/frontend/"
    cp "$FIX/libs.versions.toml" "$1/backend/gradle/"
    cp "$FIX/gradle-wrapper.properties" "$1/backend/gradle/wrapper/"
    cp "$FIX/build.gradle" "$1/backend/"
}

# git を静かに動かす: g <リポジトリ> <引数...>
g() { git -C "$@" >/dev/null 2>&1 || { echo "git の準備に失敗した: $*" >&2; exit 2; }; }

# 見本を main に置いて1回コミットする: commit_all <リポジトリ> <メッセージ>
commit_all() {
    g "$1" add -A
    g "$1" commit -q -m "$2"
}

# 場合ごとの一時フォルダを作り、HOME を替え、origin にする裸のリポジトリと、それを origin に持つリポジトリを作る
CASE_NO=0
newcase() {
    CASE_NO=$((CASE_NO + 1))
    CASE="$WORK/c$CASE_NO"
    mkdir -p "$CASE/home"
    export HOME="$CASE/home"
    git init -q --bare -b main "$CASE/origin.git" || exit 2
    git init -q -b main "$CASE/repo" || exit 2
    place "$CASE/repo"
    commit_all "$CASE/repo" fixture
    g "$CASE/repo" remote add origin "$CASE/origin.git"
    g "$CASE/repo" push -q origin main
    g "$CASE/repo" fetch -q origin
}

# origin の main だけを、別のリポジトリから書き換える: push_origin <書き換える perl の式> <ファイル>
push_origin() {
    rm -rf "$CASE/other"
    g "$CASE" clone -q "$CASE/origin.git" other
    perl -0pi -e "$1" "$CASE/other/$2"
    commit_all "$CASE/other" "change $2"
    g "$CASE/other" push -q origin main
}

# ---------------------------------------------------------------------
# 場合
# ---------------------------------------------------------------------

case_components() {
    run_inventory
    check "frontend と backend の6行の部品の鍵が、表の版の列のとおりの版で読まれる。( の付記のある pnpm のキーと、同じ名前の2つの版が読まれる" \
        "$(out "$COMPONENTS")" "$COMPONENTS_WANT"
    check "部品ごとに、読んだファイルの場所を持つ" \
        "$(out 'join " ", map { join(",", @{ $d->{components}{$_}{files} }) } qw(npm:beta npm:pnpm maven:com.auth0:java-jwt gradle-plugin:org.springframework.boot tool:gradle runtime:java)')" \
        "frontend/pnpm-lock.yaml frontend/package.json backend/gradle/libs.versions.toml backend/gradle/libs.versions.toml backend/gradle/wrapper/gradle-wrapper.properties backend/build.gradle"
    check "importers と snapshots の下のキーは読まれない" "$(out 'exists $d->{components}{"npm:delta"} ? "delta" : "none"')" "none"
    check "origin/main を取り込み、その commit を読む" "$(out '"$d->{ref} $d->{commit} " . ($d->{fetched} ? "fetched" : "not-fetched")')" \
        "origin/main $(git -C "$CASE/origin.git" rev-parse main) fetched"
}

case_main_not_worktree() {
    # 作業フォルダのファイルを書き換え、手元の main にもコミットする。どちらも origin/main には入れない
    perl -0pi -e 's/JavaLanguageVersion\.of\(21\)/JavaLanguageVersion.of(25)/' "$CASE/repo/backend/build.gradle"
    perl -0pi -e 's/pnpm\@11\.10\.0/pnpm\@99.0.0/' "$CASE/repo/frontend/package.json"
    g "$CASE/repo" commit -q -m local frontend/package.json
    run_inventory
    check "作業フォルダのファイルと手元のコミットを変えても、一覧が変わらない" "$(out "$COMPONENTS")" "$COMPONENTS_WANT"

    push_origin 's/gradle-9\.8\.2-bin/gradle-9.9.0-bin/' backend/gradle/wrapper/gradle-wrapper.properties
    run_inventory
    check "origin/main のファイルを変えると、取り込んだあとの一覧が変わる" "$(out '$d->{components}{"tool:gradle"}{versions}[0]')" "9.9.0"
    check "取り込んだ origin/main の commit を返す" "$(out '"$d->{ref} $d->{commit} " . ($d->{fetched} ? "fetched" : "not-fetched")')" \
        "origin/main $(git -C "$CASE/origin.git" rev-parse main) fetched"
}

case_head_fallback() {
    # origin を持たないリポジトリ
    git init -q -b main "$CASE/solo" || exit 2
    place "$CASE/solo"
    perl -0pi -e 's/pnpm\@11\.10\.0/pnpm\@11.11.0/' "$CASE/solo/frontend/package.json"
    commit_all "$CASE/solo" solo
    perl -MJSON::PP -e 'require $ARGV[0]; print JSON::PP->new->utf8->canonical->encode(inventory_read($ARGV[1]))' \
        "$INVENTORY" "$CASE/solo" >"$CASE/out.json" 2>"$CASE/err.txt"
    check "origin/main が無いときは HEAD から読む。git fetch が失敗すると fetched が偽になる" \
        "$(out '"$d->{ref} $d->{commit} " . ($d->{fetched} ? "fetched" : "not-fetched") . " " . $d->{components}{"npm:pnpm"}{versions}[0]')" \
        "HEAD $(git -C "$CASE/solo" rev-parse HEAD) not-fetched 11.11.0"

    # origin の main を進めたあと、origin を取り込めなくする。手元の origin/main は古いまま残る
    old=$(git -C "$CASE/repo" rev-parse origin/main)
    push_origin 's/gradle-9\.8\.2-bin/gradle-9.9.0-bin/' backend/gradle/wrapper/gradle-wrapper.properties
    g "$CASE/repo" remote set-url origin "$CASE/nosuch.git"
    run_inventory
    check "git fetch が失敗すると、fetched を偽にして手元の origin/main を読む" \
        "$(out '"$d->{ref} $d->{commit} " . ($d->{fetched} ? "fetched" : "not-fetched") . " " . $d->{components}{"tool:gradle"}{versions}[0]')" \
        "origin/main $old not-fetched 9.8.2"
}

CASES='components main_not_worktree head_fallback'

# ---------------------------------------------------------------------
# 選んだ場合を流す
# ---------------------------------------------------------------------

selected=$CASES
if [ -n "${KP_TEST_CASE:-}" ]; then
    for want in $KP_TEST_CASE; do
        case " $CASES " in
        *" $want "*) ;;
        *)
            echo "どの場合にも合わない名前: $want" >&2
            exit 2
            ;;
        esac
    done
    selected=$KP_TEST_CASE
fi
for name in $selected; do
    newcase
    "case_$name"
done

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
