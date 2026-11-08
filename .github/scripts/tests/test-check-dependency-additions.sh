#!/usr/bin/env bash
# =====================================================================
# check-dependency-additions.sh の自動テスト(dependency-gate CI から実行)
#
# 一時gitリポジトリにbase/headを作り、終了コードを検証する。
#   0 = 緑(通過) / 1 = 赤(所有者の承認を要求)
# 併せて、Summaryへ出す報告の内容も検証する。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-dependency-additions.sh"
# 一時領域の確保に失敗したまま進むと rm -rf が意図しない絶対パスを対象にするため、
# ディレクトリが実在することを確認してから trap を設定する
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FAILED=0

# 開発環境の書き場所だけを持つ、CI の道具の版の書き場所の一覧のデータのファイル
write_data() {
    mkdir -p .github
    cat >.github/ci-tool-versions.json <<'EOF'
{
  "schema": 1,
  "tools": {
    "node": {
      "name": "Node.js",
      "ci": [],
      "dev": { "file": "docker/frontend/Dockerfile", "image": "node", "tag_suffix": "-bookworm-slim" }
    },
    "trivy": { "name": "Trivy", "ci": [] },
    "terraform": {
      "name": "Terraform",
      "ci": [],
      "dev": { "file": "docker/terraform/Dockerfile", "image": "hashicorp/terraform", "tag_suffix": "" }
    }
  }
}
EOF
}

seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo/backend/gradle/wrapper" "$WORK/repo/frontend"
    cd "$WORK/repo" || exit 1
    git init -q .
    printf "plugins {\n    id 'java'\n}\ndependencies {\n    implementation 'org.example:lib:1.0.0'\n}\n" >backend/build.gradle
    echo "rootProject.name = 'test'" >backend/settings.gradle
    echo "dependencies { implementation 'org.quality:only:1.0.0' }" >backend/gradle/quality.gradle
    echo "distributionUrl=https\://example.invalid/gradle-9.0.0-bin.zip" >backend/gradle/wrapper/gradle-wrapper.properties
    printf '[versions]\nlib = "1.0.0"\n' >backend/gradle/libs.versions.toml
    echo '{"dependencies":{"react":"^19.0.0"},"devDependencies":{}}' >frontend/package.json
    printf 'packages:\n  - .\n\noverrides:\n  follow-redirects: ">=1.16.0"\n' >frontend/pnpm-workspace.yaml
    printf "lockfileVersion: '9.0'\n\npackages:\n\n  react@19.0.0:\n    resolution: {integrity: sha512-aaa}\n\n  '@scope/dep@1.0.0':\n    resolution: {integrity: sha512-bbb}\n" >frontend/pnpm-lock.yaml
    # SEED_DATA=no のときは、分かれ目にデータのファイルを置かない(データのファイルを足す PR の形)
    [ "${SEED_DATA:-yes}" = yes ] && write_data
    mkdir -p docker/frontend docker/terraform
    printf 'FROM node:24.22.2-bookworm-slim@sha256:aaa\nRUN echo frontend\n' >docker/frontend/Dockerfile
    printf 'FROM ghcr.io/terraform-linters/tflint:v0.65.0@sha256:ttt AS tflint\n\nFROM hashicorp/terraform:1.17.1@sha256:bbb\nCOPY --from=tflint /usr/local/bin/tflint /usr/local/bin/tflint\n' >docker/terraform/Dockerfile
    git add -A && git commit -qm base
    BASE=$(git rev-parse HEAD)
}

# 失敗させるケースが本物のジョブSummaryへ追記されないよう、
# 検査対象のSummaryは捨てる(内容の検証は check_summary が行う)
# 使い方: check <期待exit> <所有者Approve> <説明> <変更を加える関数>
check() {
    local want="$1" approved="$2" name="$3" mutate="$4" got
    seed
    "$mutate"
    git add -A && git commit -qm head --allow-empty
    GITHUB_STEP_SUMMARY=/dev/null OWNER_APPROVED="$approved" bash "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s (期待 exit=%s / 実際 exit=%s)\n' "$name" "$want" "$got"
        FAILED=1
    fi
}

# 使い方: check_summary <期待する文字列> <期待しない文字列(空なら検査しない)> <説明> <変更を加える関数>
check_summary() {
    local want="$1" unwanted="$2" name="$3" mutate="$4" summary
    seed
    "$mutate"
    git add -A && git commit -qm head --allow-empty
    summary="$WORK/summary.md"
    : >"$summary"
    GITHUB_STEP_SUMMARY="$summary" OWNER_APPROVED=false \
        bash "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" >/dev/null 2>&1
    if ! grep -q "$want" "$summary"; then
        printf 'FAIL %s (Summaryに "%s" が無い)\n' "$name" "$want"
        FAILED=1
        return
    fi
    if [ -n "$unwanted" ] && grep -q "$unwanted" "$summary"; then
        printf 'FAIL %s (Summaryに "%s" が出てはいけない)\n' "$name" "$unwanted"
        FAILED=1
        return
    fi
    printf 'ok   %s\n' "$name"
}

m_none() { echo "# comment" >>README.md; }
m_src_only() { mkdir -p backend/src && echo "class A {}" >backend/src/A.java; }
m_front_src_only() { mkdir -p frontend/src && echo "export const a = 1;" >frontend/src/a.ts; }
m_dep_add() { sed -i "s|^dependencies {|dependencies {\n    implementation 'org.new:dep:1.0.0'|" backend/build.gradle; }
m_dep_bump() { sed -i 's|org.example:lib:1.0.0|org.example:lib:2.0.0|' backend/build.gradle; }
m_comment_only() { echo "// コメントのみ" >>backend/build.gradle; }
m_settings() { echo "// settings の変更" >>backend/settings.gradle; }
m_quality() { echo "// quality.gradle の変更" >>backend/gradle/quality.gradle; }
m_kts_new() { echo 'plugins { kotlin("jvm") }' >backend/build.gradle.kts; }
m_catalog_edit() { sed -i 's|lib = "1.0.0"|lib = "2.0.0"|' backend/gradle/libs.versions.toml; }
m_wrapper() { sed -i 's|gradle-9.0.0-bin.zip|gradle-9.1.0-bin.zip|' backend/gradle/wrapper/gradle-wrapper.properties; }
m_npm_add() { sed -i 's|"react":"\^19.0.0"|"react":"^19.0.0","new-pkg":"^1.0.0"|' frontend/package.json; }
# 変更ファイル一覧を数百KBにする。パイプ経由で判定しているとSIGPIPEで見落とす
m_npmrc_add_many() { m_npmrc_add; d="frontend/src/$(printf 'x%.0s' $(seq 1 120))"; mkdir -p "$d"; for i in $(seq 1 2000); do echo x >"$d/f$i.ts"; done; }
m_npm_bump() { sed -i 's|\^19.0.0|^19.1.0|' frontend/package.json; }
m_lock_only() { sed -i 's|react@19.0.0|react@19.1.0|' frontend/pnpm-lock.yaml; }
m_workspace_override() { sed -i 's|follow-redirects: ">=1.16.0"|follow-redirects: ">=1.16.0"\n  evil: "npm:totally-different@1.0.0"|' frontend/pnpm-workspace.yaml; }
m_npmrc_add() { echo "minimum-release-age=0" >frontend/.npmrc; }
m_pnpmfile_add() { echo "module.exports = { hooks: {} };" >frontend/.pnpmfile.cjs; }
m_dev_node() { sed -i 's|node:24.22.2-bookworm-slim@sha256:aaa|node:24.23.0-bookworm-slim@sha256:ccc|' docker/frontend/Dockerfile; }
m_dev_tf() { sed -i 's|hashicorp/terraform:1.17.1@sha256:bbb|hashicorp/terraform:1.17.2@sha256:ddd|' docker/terraform/Dockerfile; }
m_dev_digest() {
    sed -i 's|@sha256:aaa|@sha256:ccc|' docker/frontend/Dockerfile
    sed -i 's|@sha256:bbb|@sha256:ddd|' docker/terraform/Dockerfile
}
m_tflint() { sed -i 's|tflint:v0.65.0@sha256:ttt|tflint:v0.66.0@sha256:uuu|' docker/terraform/Dockerfile; }
# 分かれ目に無いデータのファイルを足し、Dockerfile は digest だけを変える
m_add_data() { write_data; m_dev_digest; }
m_dev_no_from() { sed -i 's|^FROM hashicorp/terraform:|FROM example/terraform:|' docker/terraform/Dockerfile; }
# Go 版の品質チェックとコード生成の設定。分かれ目には無いので、どれも新しく作る変更になる
m_go_makefile() { printf 'check:\n\tgo test ./...\n' >backend/Makefile; }
m_go_golangci() { printf 'version: "2"\n' >backend/.golangci.yml; }
m_go_testcoverage() { printf 'threshold:\n  total: 93\n' >backend/.testcoverage.yml; }
m_go_gremlins() { printf 'unleash:\n  threshold:\n    efficacy: 80\n' >backend/.gremlins.yaml; }
m_go_oapi() { mkdir -p backend/api && printf 'package: gen\n' >backend/api/oapi-codegen.yaml; }
m_go_sqlc() { printf 'version: "2"\n' >backend/sqlc.yaml; }
# 承認の対象の外の Go のファイル(依存のバージョン宣言とコード)
m_go_mod() { printf 'module example.com/backend\n\ngo 1.26\n' >backend/go.mod; printf '' >backend/go.sum; }
m_go_src() { mkdir -p backend/internal/a && printf 'package a\n' >backend/internal/a/a.go; }
# 承認の対象のファイルと同じ名前でも、置き場所が違えば対象にしない
m_go_makefile_nested() { mkdir -p backend/tools && printf 'all:\n' >backend/tools/Makefile; }

# --- 承認を要求しないもの --------------------------------------------------------
check 0 false "依存定義以外のみの変更" m_none
check 0 false "backendのソースのみの変更" m_src_only
check 0 false "frontendのソースのみの変更" m_front_src_only

# バージョン宣言の変更は #182 で機械の関門に置き換えたため承認を求めない。
# 落としてはいけない変更は dependency-review / dependency-cooldown / gradle-wrapper が担う
check 0 false "version catalog の編集" m_catalog_edit
check 0 false "gradle-wrapper.properties の変更" m_wrapper
check 0 false "npm依存の追加" m_npm_add
check 0 false "npm依存のバージョン更新のみ" m_npm_bump
check 0 false "pnpm-lock.yaml のみの変更" m_lock_only

# --- 承認を要求するもの ----------------------------------------------------------
check 1 false "build.gradle への依存追加" m_dep_add
check 1 false "build.gradle のバージョン更新のみ" m_dep_bump
check 1 false "build.gradle のコメントのみの変更" m_comment_only
check 1 false "settings.gradle の変更" m_settings
check 1 false "quality.gradle の変更" m_quality
check 1 false "build.gradle.kts の追加" m_kts_new
check 1 false "pnpm-workspace.yaml の overrides 変更" m_workspace_override
check 1 false ".npmrc の追加" m_npmrc_add
check 1 false ".pnpmfile.cjs の追加" m_pnpmfile_add
check 1 false ".npmrc の追加(変更ファイルが大量)" m_npmrc_add_many

# --- 所有者のApprove済み ---------------------------------------------------------
check 0 true "build.gradle の変更 + 所有者Approve済み" m_dep_add
check 0 true "pnpm-workspace.yaml の変更 + 所有者Approve済み" m_workspace_override

# --- 報告の内容 ------------------------------------------------------------------
check_summary "pnpm-workspace.yaml" "" "対象のファイル名がSummaryに出る" m_workspace_override
# lockfile からパッケージ名を抽出する報告は、lockfile が対象外になったため無くなった
check_summary "build.gradle" "新しく現れたパッケージ" "報告の節は残っていない" m_dep_add

# --- 開発環境の Node.js と Terraform の版 -----------------------------------------
# 開発環境の版だけを変える PR は .github/ を変えないので、CODEOWNERS では承認が要らない。
# この検知が、その PR に所有者の承認を求める
check 1 false "開発環境の Node.js の FROM のタグの版の変更を検知し、所有者の承認が無ければ失敗する" m_dev_node
check 1 false "開発環境の Terraform の FROM のタグの版の変更を検知する" m_dev_tf
check 0 true "所有者の承認があれば通る" m_dev_node
check 0 false "digest だけの変更を検知しない" m_dev_digest
check 0 false "tflint の FROM の行の変更を検知しない" m_tflint
SEED_DATA=no check 0 false "分かれ目にデータのファイルが無く、FROM の行を変えない PR で検知しない" m_add_data
check 1 false "開発環境の FROM の行を読めなければ、承認を求める" m_dev_no_from
check_summary "docker/frontend/Dockerfile: Node.js の版 24.22.2 を 24.23.0 に変更" "" "変えた開発環境の版が Summary に出る" m_dev_node

# --- Go 版の品質チェックとコード生成の設定 ---------------------------------------
# 品質チェックとコード生成の指定を、所有者の承認なしに緩められないようにする(要件3の受入基準3)
check 1 false ".testcoverage.yml の変更を承認の対象にする" m_go_testcoverage
check 1 false "Makefile の変更を承認の対象にする" m_go_makefile
check 1 false ".golangci.yml の変更を承認の対象にする" m_go_golangci
check 1 false ".gremlins.yaml の変更を承認の対象にする" m_go_gremlins
check 1 false "api/oapi-codegen.yaml の変更を承認の対象にする" m_go_oapi
check 1 false "sqlc.yaml の変更を承認の対象にする" m_go_sqlc
check 0 true ".testcoverage.yml の変更は所有者の承認があれば通る" m_go_testcoverage
check 0 false "go.mod と go.sum の変更は承認の対象にしない" m_go_mod
check 0 false "Go のコードの変更は承認の対象にしない" m_go_src
check 0 false "backend の直下でない Makefile は承認の対象にしない" m_go_makefile_nested
check_summary "backend/.testcoverage.yml" "" "変えた Go 版の設定のファイル名が Summary に出る" m_go_testcoverage

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-dependency-additions.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
