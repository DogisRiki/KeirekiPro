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

# イメージと terraform と AWS と CI の見本を、リポジトリの中の決まった場所に写す: place_more <リポジトリ>
place_more() {
    # 見本の Dockerfile は、Dockerfile で始まらない名前で置き、写すときに Dockerfile の名前に戻す。
    # このリポジトリの main を読むときに、見本の FROM が本物のイメージとして読まれないようにするためである
    mkdir -p "$1/docker/app" "$1/docker/db" "$1/terraform" "$1/.github/workflows" "$1/.github/actions"
    cp "$FIX/docker/app.dockerfile" "$1/docker/app/Dockerfile"
    cp "$FIX/docker/db.prod.dockerfile" "$1/docker/db/Dockerfile.prod"
    cp "$FIX/compose.yaml" "$1/"
    cp -r "$FIX/tf/." "$1/terraform/"
    cp "$FIX/terraform.lock.hcl" "$1/terraform/.terraform.lock.hcl"
    cp "$FIX/workflows/"* "$1/.github/workflows/"
    cp -r "$FIX/actions/." "$1/.github/actions/"
}

# git を静かに動かす: g <リポジトリ> <引数...>
g() { git -C "$@" >/dev/null 2>&1 || { echo "git の準備に失敗した: $*" >&2; exit 2; }; }

# 見本を main に置いて1回コミットする: commit_all <リポジトリ> <メッセージ>
commit_all() {
    g "$1" add -A
    g "$1" commit -q -m "$2"
}

# 場合ごとの一時フォルダを作り、偽の gh を gh の名前で写して PATH の先頭に置き、HOME を替え、origin にする裸のリポジトリと、それを origin に持つリポジトリを作る
ORIG_PATH=$PATH
CASE_NO=0
newcase() {
    CASE_NO=$((CASE_NO + 1))
    CASE="$WORK/c$CASE_NO"
    mkdir -p "$CASE/home" "$CASE/bin" "$CASE/gh"
    cp "$FIX/../fake-gh.sh" "$CASE/bin/gh"
    chmod +x "$CASE/bin/gh"
    # PATH は : で区切るので、C:/ の形でなく、bash の形の場所を置く
    export PATH="$TMP_ROOT/c$CASE_NO/bin:$ORIG_PATH"
    if [ "$(command -v gh)" != "$TMP_ROOT/c$CASE_NO/bin/gh" ]; then
        echo "偽の gh が PATH の先頭にない: $(command -v gh)" >&2
        exit 2
    fi
    # 依存の一覧の見本は置かない。偽の gh は、見本が無い呼び出しに 2 で終わる
    export KP_FAKE_GH_DIR="$CASE/gh"
    unset KP_FAKE_GH_FAIL
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

# 見本のイメージと terraform と AWS と CI のファイルを origin の main に足す
push_more() {
    place_more "$CASE/repo"
    commit_all "$CASE/repo" more
    g "$CASE/repo" push -q origin main
}

# KP_SEL の正規表現に合う鍵だけを COMPONENTS の形で並べる
COMPONENTS_SEL='join " ", map { my $c = $d->{components}{$_}; "$_=" . join(",", @{ $c->{versions} }) . ($c->{partial} ? "~" : "") } grep { /$ENV{KP_SEL}/ } sort keys %{ $d->{components} }'

case_images_ci() {
    push_more
    run_inventory
    check "イメージと terraform と AWS と CI の5行の部品の鍵が、表の版の列のとおりの版で読まれる。21-jdk が partial になり、trixie-slim の版が分からないものになる" \
        "$(KP_SEL='^(?:image|terraform-provider|ci|action):|^npm:\@openai/' out "$COMPONENTS_SEL")" \
        "action:actions/checkout=7.0.1 action:actions/setup-node= action:aws-actions/configure-aws-credentials=6.3.0 action:docker/setup-buildx-action=4.4.1 ci:node=24.22.2,24.22.3 ci:trivy=0.76.1 image:debian= image:docker=29~ image:eclipse-temurin=21~ image:ghcr.io/terraform-linters/tflint=0.65.0 image:postgres=17.11 image:valkey/valkey=8.0.12 npm:@openai/codex=0.166.0 terraform-provider:hashicorp/aws=5.100.0 terraform-provider:hashicorp/random=3.8.0"
    check "5行の部品ごとに、読んだファイルの場所を持つ" \
        "$(out 'join " ", map { join(",", @{ $d->{components}{$_}{files} }) } qw(image:eclipse-temurin image:postgres image:docker terraform-provider:hashicorp/aws ci:node action:actions/checkout npm:@openai/codex)')" \
        "docker/app/Dockerfile docker/db/Dockerfile.prod compose.yaml terraform/.terraform.lock.hcl .github/workflows/ci.yaml,.github/workflows/review.yml .github/workflows/ci.yaml,.github/workflows/review.yml .github/workflows/review.yml"
    check "前の段階の名前と scratch と変数の FROM は、イメージの鍵にならない" \
        "$(KP_SEL='^image:(?:builder|scratch|test|empty|\$)' out "$COMPONENTS_SEL")" ""
    check "frontend と backend の6行の部品は変わらない" \
        "$(KP_SEL='^(?:npm:(?!\@openai/)|maven:|gradle-plugin:|tool:|runtime:)' out "$COMPONENTS_SEL")" "$COMPONENTS_WANT"
}

case_aws() {
    push_more
    run_inventory
    check "aws_db_instance の resource が aws:rds の鍵になり、aws:rds と aws:elasticache が engine_version と major_engine_version の一部だけの版で読まれる。ほかの aws: の鍵は版が分からないものになる" \
        "$(KP_SEL='^aws:' out "$COMPONENTS_SEL")" \
        "aws:db= aws:elasticache=8~ aws:rds=17~ aws:s3= aws:security="
    check "AWS の部品ごとに、resource を読んだファイルの場所を持つ" \
        "$(out 'join " ", map { join(",", @{ $d->{components}{$_}{files} }) } qw(aws:rds aws:elasticache aws:s3)')" \
        "terraform/modules/rds/main.tf terraform/modules/cache/main.tf terraform/main.tf"
}

case_sbom() {
    cp "$FIX/sbom.json" "$CASE/gh/sbom.json"
    run_inventory
    check "偽の gh の依存の一覧から、pkg:maven/ の部品だけが足される。gh を失敗させると sbom_ok が偽になる(依存の一覧を読めた場合)" \
        "$(KP_SEL='^(?:maven|npm):' out "$COMPONENTS_SEL") $(out '$d->{sbom_ok} ? "sbom_ok" : "sbom_ng"')" \
        "maven:com.auth0:java-jwt=4.5.0 maven:org.mybatis.spring.boot:mybatis-spring-boot-starter=4.0.1 maven:org.yaml:snakeyaml=2.4 npm:@scope/alpha=1.2.3 npm:beta=2.0.0,2.1.0 npm:epsilon=5.0.0 npm:gamma=3.0.0 npm:pnpm=11.10.0 npm:react=19.0.0 sbom_ok"
    check "依存の一覧から足した部品は、依存の一覧を読んだことを場所に持つ" \
        "$(out 'join " ", map { join(",", @{ $d->{components}{$_}{files} }) } qw(maven:org.yaml:snakeyaml maven:com.auth0:java-jwt)')" \
        "dependency-graph/sbom backend/gradle/libs.versions.toml,dependency-graph/sbom"
    check "pkg:github と pkg:githubactions の部品は足されない" \
        "$(KP_SEL='checkout|example' out "$COMPONENTS_SEL")" ""

    export KP_FAKE_GH_FAIL=sbom
    run_inventory
    check "偽の gh の依存の一覧から、pkg:maven/ の部品だけが足される。gh を失敗させると sbom_ok が偽になる(gh を失敗させた場合)" \
        "$(out '(exists $d->{components}{"maven:org.yaml:snakeyaml"} ? "snakeyaml" : "none") . " " . ($d->{sbom_ok} ? "sbom_ok" : "sbom_ng")')" "none sbom_ng"
    unset KP_FAKE_GH_FAIL
    printf '{"sbom": ' >"$CASE/gh/sbom.json"
    run_inventory
    check "依存の一覧が JSON として読めないときも sbom_ok が偽になり、ほかの部品は読まれる" \
        "$(out '($d->{sbom_ok} ? "sbom_ok" : "sbom_ng") . " " . $d->{components}{"npm:pnpm"}{versions}[0]')" "sbom_ng 11.10.0"
}

CASES='components main_not_worktree head_fallback images_ci aws sbom'

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
