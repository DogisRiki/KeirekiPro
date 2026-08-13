#!/usr/bin/env bash
# =====================================================================
# 依存パッケージ追加の検知(dependency-gate CI から実行)
#
# 「追加」のみを人間ゲートにする。既存依存のバージョン更新は検知しない
# (週次の自動更新レーンを妨げないため)。
#
# 判定:
#   依存追加なし                        -> exit 0(緑)
#   依存追加あり + 所有者Approveなし     -> exit 1(赤)
#   依存追加あり + 所有者Approveあり     -> exit 0(緑)
#
# 走査対象:
#   - frontend/package.json(dependencies + devDependencies)
#   - backend/**/*.gradle と *.gradle.kts(quality.gradle を除く全gradleファイル。
#     新規gradleファイル経由の依存追加も検知する)
#     依存座標に加え、プラグインの適用も対象。Gradleプラグインはビルド時に
#     任意のコードを実行するため、依存ライブラリと同格に扱う。
#   - backend/**/*.versions.toml(version catalog)
#     キーだけでなく参照先(module / id)も比較する。既存キーの差し替えを見逃さないため。
#
# テスト: .github/scripts/tests/test-check-dependency-additions.sh
#
# 環境変数:
#   OWNER_APPROVED : "true" ならリポジトリ所有者のApprove済み
#
# 使い方: check-dependency-additions.sh <base_sha> <head_sha>
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
OWNER_APPROVED="${OWNER_APPROVED:-false}"

# fail-closed: 解析ツールが無い環境で黙って合格させない
if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq が見つかりません。依存追加の判定ができないため fail-closed で失敗します。"
    exit 1
fi

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")

additions=""

# --- frontend/package.json: dependencies + devDependencies のキー集合を比較 ---
pkg_keys() {
    jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' 2>/dev/null | sort -u
}

if git diff --name-only "$MERGE_BASE" "$HEAD_SHA" | grep -q '^frontend/package\.json$'; then
    base_keys=$(git show "$MERGE_BASE:frontend/package.json" | pkg_keys || true)
    head_keys=$(git show "$HEAD_SHA:frontend/package.json" | pkg_keys || true)
    new_npm=$(comm -13 <(echo "$base_keys") <(echo "$head_keys") || true)
    if [ -n "$new_npm" ]; then
        additions+="[frontend/package.json]"$'\n'"$new_npm"$'\n'
    fi
fi

# 指定リビジョンの backend 配下の対象ファイルを連結して標準出力に流す
# 使い方: cat_backend_files <ref> <ファイル名の正規表現>
cat_backend_files() {
    local ref="$1"
    local pattern="$2"
    git ls-tree -r --name-only "$ref" -- backend 2>/dev/null |
        grep -E "$pattern" |
        grep -v '^backend/gradle/quality\.gradle$' |
        while IFS= read -r f; do
            git show "$ref:$f" 2>/dev/null || true
        done
}

# 引用符で囲まれた最後の値だけを取り出す
last_quoted() {
    grep -oE "['\"][^'\"]+['\"]$" | tr -d "'\""
}

GRADLE_FILE_RE='\.gradle(\.kts)?$'
CATALOG_FILE_RE='\.versions\.toml$'

# --- backend/**/*.gradle: 依存座標(group:artifact)の集合を比較 ---
gradle_coords() {
    # implementation 'group:artifact:version' / classpath / platform(...) 等から
    # group:artifact を抽出する(バージョン部は無視 = 更新は追加扱いにしない)
    grep -oE "(implementation|api|compileOnly|runtimeOnly|developmentOnly|annotationProcessor|testImplementation|testCompileOnly|testRuntimeOnly|testAnnotationProcessor|classpath)[^'\"]*['\"][^'\"]+['\"]" 2>/dev/null |
        last_quoted |
        awk -F: 'NF >= 2 { print $1 ":" $2 }' |
        sort -u
}

# --- backend/**/*.gradle: プラグインの適用の集合を比較 ---
gradle_plugin_ids() {
    # Groovy DSL と Kotlin DSL の双方の記法を対象にする。version 部は含めない
    # (バージョン更新を追加扱いにしないため)。
    local src
    src=$(cat)
    {
        # id 'org.foo' / id("org.foo")
        printf '%s\n' "$src" | grep -oE "\bid[[:space:]]*\(?[[:space:]]*['\"][^'\"]+['\"]" | last_quoted || true
        # apply plugin: 'org.foo' / apply(plugin = "org.foo")
        printf '%s\n' "$src" | grep -oE "\bapply[[:space:]]*\(?[[:space:]]*plugin[[:space:]]*[:=][[:space:]]*['\"][^'\"]+['\"]" | last_quoted || true
        # kotlin("jvm") : Kotlin DSL のプラグイン記法
        printf '%s\n' "$src" | grep -oE "\bkotlin[[:space:]]*\([[:space:]]*['\"][^'\"]+['\"]" | last_quoted | sed 's|^|kotlin:|' || true
        # alias(libs.plugins.foo) : version catalog 経由の適用
        printf '%s\n' "$src" | grep -oE "\balias[[:space:]]*\([[:space:]]*[A-Za-z0-9_.]+" | grep -oE "[A-Za-z0-9_.]+$" | sed 's|^|alias:|' || true
    } | sort -u
}

# --- backend/**/*.versions.toml: version catalog の宣言の集合を比較 ---
catalog_entries() {
    # [libraries] [plugins] [bundles] の各エントリを「キー=参照先」の形で取り出す。
    # バージョン指定は取り除くため、更新は追加扱いにならない。一方で既存キーの
    # 参照先の差し替え(別プラグインへの置換など)は差分として現れる。
    # 表形式が複数行にまたがる場合、行ごとの断片になるが、参照先の変更は検知される。
    awk '
        /^[[:space:]]*\[/ { section = $0; gsub(/[][[:space:]]/, "", section); next }
        (section == "libraries" || section == "plugins" || section == "bundles") &&
        /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/ {
            key = $0; sub(/[[:space:]]*=.*/, "", key); gsub(/[[:space:]]/, "", key)
            val = $0; sub(/^[^=]*=[[:space:]]*/, "", val)
            gsub(/version\.ref[[:space:]]*=[[:space:]]*"[^"]*"/, "", val)
            gsub(/version[[:space:]]*=[[:space:]]*"[^"]*"/, "", val)
            gsub(/version[[:space:]]*=[[:space:]]*\{[^}]*\}/, "", val)
            if (val ~ /^"[^"]*"[[:space:]]*,?$/) {
                gsub(/["[:space:],]/, "", val)
                n = split(val, p, ":")
                if (n == 3) { val = p[1] ":" p[2] }
                else if (n == 2 && section == "plugins") { val = p[1] }
            }
            gsub(/[[:space:],]/, "", val)
            print section "/" key "=" val
        }
    ' 2>/dev/null | sort -u
}

# base と head の集合を比較し、増えた要素があれば additions に積む
# 使い方: collect_additions <見出し> <ファイル名の正規表現> <抽出関数名>
collect_additions() {
    local label="$1"
    local file_re="$2"
    local extractor="$3"
    local changed base_set head_set added

    changed=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA" |
        grep -E "^backend/.*$file_re" |
        grep -v '^backend/gradle/quality\.gradle$' || true)
    [ -n "$changed" ] || return 0

    base_set=$(cat_backend_files "$MERGE_BASE" "$file_re" | "$extractor" || true)
    head_set=$(cat_backend_files "$HEAD_SHA" "$file_re" | "$extractor" || true)
    added=$(comm -13 <(echo "$base_set") <(echo "$head_set") || true)
    if [ -n "$added" ]; then
        additions+="[$label]"$'\n'"$added"$'\n'
    fi
}

collect_additions "backend/**/*.gradle 依存座標" "$GRADLE_FILE_RE" gradle_coords
collect_additions "backend/**/*.gradle プラグイン" "$GRADLE_FILE_RE" gradle_plugin_ids
collect_additions "backend/**/*.versions.toml" "$CATALOG_FILE_RE" catalog_entries

if [ -z "$additions" ]; then
    echo "依存パッケージの追加なし。"
    exit 0
fi

{
    echo "### :package: 依存パッケージの追加を検出"
    echo ""
    echo '```'
    echo "$additions"
    echo '```'
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ "$OWNER_APPROVED" = "true" ]; then
    echo "依存追加を検出しましたが、リポジトリ所有者のApprove済みのため通過します。"
    echo "$additions"
    exit 0
fi

echo "::error::依存パッケージの追加が検出されました。リポジトリ所有者のApproveレビュー後にこのチェックは緑になります。"
echo "$additions"
exit 1
