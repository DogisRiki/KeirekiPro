#!/usr/bin/env bash
# =====================================================================
# 依存クールダウン検査(dependency-review CI から実行)
#
# 判定: このPRで新しく追加された maven と npm のパッケージのうち、公開から一定時間を
#       経過していないものが1件でもあれば exit 1(赤)。全て経過していれば exit 0。
#       公開時刻を取得できないものが1件でもあれば exit 1(fail closed)。
#
# なぜ必要か:
#   frontend は pnpm の minimumReleaseAge がリゾルバレベルで公開直後の版を弾く。
#   backend にはこれに相当する標準機構が無い。Dependabot 経由の更新には Dependabot 自身の
#   既定クールダウンが効くが、エージェントが直接バージョンカタログを編集して公開直後の
#   パッケージを追加する経路には何も効かない。この穴を埋める。
#   npm の部品も読むのは、脆弱性の修正の版を72時間待たずに入れるとき、pnpm の除外の欄に
#   足した版を、ほかの版と同じ判定に通すためである。
#
# なぜ依存グラフの差分比較を入力にするのか:
#   バージョンカタログやビルド定義を解析すると、推移的依存とBOM管理下の版が見えない。
#   差分比較APIは解決済みの追加パッケージを推移的依存まで含めて返す。加えて Gradle の
#   プラグインの成果物も maven のエコシステムとして含まれるため、backend で最も頻繁な
#   プラグインのバージョン更新も同じ経路で検査できる。
#
# なぜ検索APIを使わないのか:
#   search.maven.org の索引は正典より遅れる。公開済みの版が結果に現れない事象を
#   実際に観測した(org.slf4j:slf4j-api 2.0.18、2026-05-12公開)。判定に使うと
#   公開済みの版を「存在しない」と誤判定する。成果物への直接の問い合わせだけを使う。
#
# なぜ判定不能を赤にするのか:
#   判定できないまま通すと、検査があるのに守られていない状態が静かに続く。
#   ただし外部要因の赤はエージェントが自力で解消できないため、報告で区別する。
#
# 配布元が2つあるのは、プラグインの成果物が Maven Central に無い場合があるため。
# 実測で com.github.spotbugs.snom:spotbugs-gradle-plugin と gradle.plugin.* の
# 名前空間が Maven Central で 404 を返し、Gradle Plugin Portal 側に存在した。
#
# テスト: .github/scripts/tests/test-check-dependency-cooldown.sh
# 使い方: check-dependency-cooldown.sh <base_sha> <head_sha>
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須) / GITHUB_REPOSITORY_OWNER(必須) / PR_NUMBER(必須)
#   OWNER_APPROVED(既定 false。true のときだけ所有者の承認があるとみなす)
#   COOLDOWN_HOURS(既定72) / NOW_EPOCH(テスト用の時刻固定)
#   MAVEN_CENTRAL_BASE / PLUGIN_PORTAL_BASE / NPM_REGISTRY_BASE(テスト用の配布元差し替え)
#   PNPM_WORKSPACE_FILE(既定 frontend/pnpm-workspace.yaml)
#
# 公開から72時間経っていない版があるときの流れ(順に確かめ、止める版があればそこで赤にする):
#   1. 脆弱性の警告に照らす(cooldown-match-alerts.sh)。条件を満たさない版が1つでもあれば、
#      条件を満たす版も「ほかの版を待つ」として止める。このときは 2 から先に問い合わせない
#   2. 追加されたすべての部品を、悪意のある部品の一覧に照らす(cooldown-check-malware.sh)
#   3. 前の版と署名した者を比べる(cooldown-check-signer.sh)
#   4. frontend の版が pnpm の除外の欄にあるかを確かめる(cooldown-check-pnpm-exclude.sh)
#   5. 記録のコメントを書く(record-cooldown-exception.sh post)
#   6. 所有者の承認を確かめる
# 公開から72時間経っていない版が無いときは、記録のコメントがあれば 6 だけを確かめる。
# 記録のコメントがあるのは、前の head で72時間待たずに入れる版を記録した PR である。
# 止めたときは、GITHUB_STEP_SUMMARY に止めた部品の表(部品、版、公開日時、止めた理由、入るようになる時刻)を書き、
# 止めた部品ごとに ::error:: の行を標準出力に出す。/ship は、この行から止めた部品と時刻を読む。
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
OWNER="${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER required}"
PR_NUMBER="${PR_NUMBER:?PR_NUMBER required}"
: "${GH_TOKEN:?GH_TOKEN required}"
if [[ ! "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::PR_NUMBER が PR の番号の形ではありません: '${PR_NUMBER}'" >&2
    exit 1
fi

OWNER_APPROVED="${OWNER_APPROVED:-false}"
COOLDOWN_HOURS="${COOLDOWN_HOURS:-72}"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
# 呼ぶスクリプトも同じ配布元を見るように、環境に渡す
export MAVEN_CENTRAL_BASE="${MAVEN_CENTRAL_BASE:-https://repo1.maven.org/maven2}"
export PLUGIN_PORTAL_BASE="${PLUGIN_PORTAL_BASE:-https://plugins.gradle.org/m2}"
export NPM_REGISTRY_BASE="${NPM_REGISTRY_BASE:-https://registry.npmjs.org}"
PNPM_WORKSPACE_FILE="${PNPM_WORKSPACE_FILE:-frontend/pnpm-workspace.yaml}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
COOLDOWN_SECONDS=$((COOLDOWN_HOURS * 3600))
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- スナップショットの取り込み状況の確認 ---------------------------------------
# 比較APIは head 側のスナップショットがまだ取り込まれていない場合でも、エラーではなく
# 200 を返す。そのとき追加は0件に見えるため、この検査は静かに緑になる。
# 送信ジョブの完了とAPI側の取り込み完了は別で、この非同期性のために
# dependency-review 側では retry-on-snapshot-warnings を保険として入れている。
#
# APIは取り込み数の不一致を x-github-dependency-graph-snapshot-warnings ヘッダで
# 知らせる(base64)。実測では、警告が無いときもヘッダ自体は存在し値が空になる。
# 値が入っていれば差分が信用できないため、判定不能として赤にする。
# ヘッダの取得に失敗した場合も判定不能として赤にする。空にして続行すると
# 「警告なし」と区別がつかず、この確認自体が素通りする。
raw_headers=""
if ! raw_headers=$(gh api --include \
    "repos/${REPO}/dependency-graph/compare/${BASE_SHA}...${HEAD_SHA}" 2>/dev/null); then
    {
        echo "### :warning: スナップショットの状況を確認できませんでした(判定不能)"
        echo ""
        echo "比較APIの応答ヘッダを取得できませんでした。"
        echo "対象: \`repos/${REPO}/dependency-graph/compare/${BASE_SHA}...${HEAD_SHA}\`"
        echo ""
        echo "**外部要因による失敗です。時間の経過では解消しません。**"
        echo "APIの応答を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "比較APIの応答ヘッダを取得できませんでした(判定不能)。" >&2
    exit 1
fi

warn_b64=$(printf '%s' "$raw_headers" |
    sed -n '/^[Xx]-[Gg]ithub-[Dd]ependency-[Gg]raph-[Ss]napshot-[Ww]arnings:/p' |
    sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' | head -1)

if [ -n "$warn_b64" ]; then
    warn_text=$(printf '%s' "$warn_b64" | base64 -d 2>/dev/null || printf '%s' "$warn_b64")
    {
        echo "### :warning: 依存グラフのスナップショットが揃っていません(判定不能)"
        echo ""
        echo "$warn_text"
        echo ""
        echo "**この状態の差分は信用できないため判定しません。**"
        echo "送信ジョブの直後は取り込みが完了していないことがあります。"
        echo "少し置いてからこのチェックを再実行してください。"
        echo "繰り返し出る場合は送信ジョブの結果を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "スナップショットの取り込み数が一致しません(判定不能): ${warn_text}" >&2
    exit 1
fi

# --- 追加と削除のパッケージの取得 -----------------------------------------------
# change_type が added か removed で、maven か npm のものだけを見る。removed は前の版を
# 取り出すために読む。github-actions のエコシステムはアクション参照のSHA固定検査が
# 別に担っているため対象にしない。
#
# 取得の失敗を握りつぶさない。失敗して空になったものを「追加なし」と扱うと、
# 比較APIがエラーを返す場合に静かに緑になる。fail closed の破れにあたる。
#
# maven の座標は name ではなく package_url から取る。比較APIの name は artifactId を
# 小文字にして返すことがあり(例: biz.aQute.bnd:biz.aqute.bnd.annotation)、
# Maven Central のパスは大文字小文字を区別するため 404 になって判定不能で止まる。
# package_url(pkg:maven/<groupId>/<artifactId>@<version>)は元の表記を保っている。
# package_url が無いエントリと npm のエントリは name を使う。
compare_out=""
if ! compare_out=$(gh api --paginate \
    "repos/${REPO}/dependency-graph/compare/${BASE_SHA}...${HEAD_SHA}" \
    --jq '.[] | select(.change_type == "added" or .change_type == "removed")
        | select(.ecosystem == "maven" or .ecosystem == "npm")
        | "\(.change_type)\t\(.ecosystem)\t\(if .ecosystem == "maven" and ((.package_url // "") | startswith("pkg:maven/"))
             then (.package_url | ltrimstr("pkg:maven/") | sub("[@?#].*"; "") | sub("/"; ":"))
             else .name end)\t\(.version)"'); then
    {
        echo "### :warning: 追加パッケージの一覧を取得できませんでした(判定不能)"
        echo ""
        echo "依存グラフの差分比較に失敗しました。"
        echo "対象: \`repos/${REPO}/dependency-graph/compare/${BASE_SHA}...${HEAD_SHA}\`"
        echo ""
        echo "**外部要因による失敗です。時間の経過では解消しません。**"
        echo "head 側のスナップショットが送信されていない場合もここで失敗します。"
        echo "送信ジョブの結果と、APIの応答を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "依存グラフの差分比較に失敗しました(判定不能)。" >&2
    exit 1
fi

added=$(printf '%s\n' "$compare_out" | awk -F'\t' '$1 == "added" { print $2 "\t" $3 "\t" $4 }' | sort -u)
removed=$(printf '%s\n' "$compare_out" | awk -F'\t' '$1 == "removed" { print $2 "\t" $3 "\t" $4 }' | sort -u)

# --- 警告の API を読めるかの確認 -------------------------------------------------
# 公開から72時間経っていない版の有無によらず1回だけ読む。Dependabot の PR の実行でも
# 警告の API を使えることを、すべての版が72時間経った PR で確かめるためである。
# この確認の結果は、緑か赤かを変えない。
alerts_err=""
if alerts_err=$(gh api "repos/${REPO}/dependabot/alerts?per_page=1" 2>&1 >/dev/null); then
    {
        echo "脆弱性の警告を読めた"
        echo ""
    } >>"$SUMMARY"
else
    # gh は失敗したとき「gh: Not Found (HTTP 404)」の形の行を標準エラーに出す
    alerts_status=$(printf '%s' "$alerts_err" | grep -oE 'HTTP [0-9]{3}' | tail -1 | cut -d' ' -f2 || true)
    echo "::warning::脆弱性の警告を読めませんでした(HTTP ${alerts_status:-不明})。72時間待たずに入れる版の判定ができません。"
    {
        echo "脆弱性の警告を読めなかった(HTTP ${alerts_status:-不明})"
        echo ""
    } >>"$SUMMARY"
fi

# 追加が0件でも、前の head の記録のコメントがあれば所有者の承認を確かめるため、ここでは終えない
if [ -z "$added" ]; then
    echo "このPRで新しく追加された maven と npm のパッケージはありません。"
else
    echo "追加されたパッケージ: $(printf '%s\n' "$added" | wc -l) 件"
fi

# --- 公開時刻の取得 -------------------------------------------------------------
# maven: HEADリクエストの Last-Modified を使う。Maven Central を先に引き、404 のときだけ
# Gradle Plugin Portal へフォールバックする。404 以外の失敗でフォールバックすると、
# 一方の一時的な不調によって判定の根拠が黙って別の配布元へ移る。
# -L はリダイレクト追従。ヘッダは複数ブロック返るため最後の値を採る。
#
# 戻り値: 0=取得成功(標準出力にLast-Modified) / 2=404(存在しない) / 1=その他の失敗
head_last_modified() {
    local url="$1" out code
    out=$(curl -sSI -L --max-time 20 -w '\nHTTP_CODE:%{http_code}\n' "$url" 2>/dev/null) || return 1
    code=$(printf '%s' "$out" | tr -d '\r' | sed -n 's/^HTTP_CODE:\([0-9]*\)$/\1/p' | tail -1)
    case "$code" in
    200) ;;
    404) return 2 ;;
    *) return 1 ;;
    esac
    printf '%s' "$out" | tr -d '\r' | sed -n 's/^[Ll]ast-[Mm]odified:[[:space:]]*//p' | tail -1
}

pom_path() {
    local name="$1" version="$2" group artifact
    group="${name%%:*}"
    artifact="${name##*:}"
    printf '%s/%s/%s/%s-%s.pom' \
        "$(printf '%s' "$group" | tr '.' '/')" "$artifact" "$version" "$artifact" "$version"
}

# maven の公開時刻(Last-Modified の文字列)を標準出力に出す。読めなければ空を出す。
maven_published() {
    local path lm rc=0
    path=$(pom_path "$1" "$2")
    lm=$(head_last_modified "${MAVEN_CENTRAL_BASE}/${path}") || rc=$?
    if [ "$rc" -eq 2 ]; then
        rc=0
        lm=$(head_last_modified "${PLUGIN_PORTAL_BASE}/${path}") || rc=$?
    fi
    [ "$rc" -eq 0 ] || lm=""
    printf '%s' "$lm"
}

# npm: registry の部品の文書の time["<版>"] を使う。スコープ付きの名前の / は %2f にする。
# 名前は URL に入るので、npm の名前に使える文字だけを受け付ける。
# 公開時刻の文字列を標準出力に出す。読めなければ空を出す。
npm_published() {
    local name="$1" version="$2" code
    [[ "$name" =~ ^(@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+$ ]] || return 0
    # 前の部品の文書が残っていると、問い合わせに失敗したときにその time を読んでしまう
    rm -f "$TMP/npm.json"
    code=$(curl -sS -L --max-time 60 -o "$TMP/npm.json" -w '%{http_code}' \
        "${NPM_REGISTRY_BASE}/${name/\//%2f}" 2>/dev/null) || return 0
    [ "$code" = 200 ] || return 0
    jq -r --arg v "$version" '.time[$v] // empty | strings' "$TMP/npm.json" 2>/dev/null || true
}

# 前の版: 同じ ecosystem と同じ名前の removed のうち、版の数の大きさで最も高いもの
prior_version() {
    printf '%s\n' "$removed" | awk -F'\t' -v e="$1" -v n="$2" '$1 == e && $2 == n { print $3 }' |
        sort -V | tail -1
}

# 報告に出す部品の名前。npm は <名前>@<版>、maven は <groupId>:<artifactId>:<版>
label_of() {
    if [ "$1" = npm ]; then
        printf '%s@%s' "$2" "$3"
    else
        printf '%s:%s' "$2" "$3"
    fi
}

young=""    # クールダウン未満
unknown=""  # 公開時刻を取得できなかったもの
latest_clear=0
# クールダウン未満の版の一覧。各行は "<ecosystem>\t<名前>\t<版>\t<公開時刻のエポック秒>\t<報告の名前>"
: >"$TMP/young.tsv"
# 公開時刻を読めたすべての版の一覧。止めた部品の表に使う。各行は "<報告の名前>\t<名前>\t<版>\t<公開時刻のエポック秒>"
: >"$TMP/published.tsv"

while IFS=$'\t' read -r eco name version; do
    [ -n "$name" ] || continue
    prior=$(prior_version "$eco" "$name")
    echo "追加された部品: ${eco} ${name} ${version}(前の版: ${prior:-なし})"
    label=$(label_of "$eco" "$name" "$version")
    if [ "$eco" = npm ]; then
        lm=$(npm_published "$name" "$version")
    else
        lm=$(maven_published "$name" "$version")
    fi

    if [ -z "$lm" ]; then
        unknown+="- ${label}"$'\n'
        continue
    fi

    published=$(date -u -d "$lm" +%s 2>/dev/null || true)
    if [ -z "$published" ]; then
        unknown+="- ${label}(公開時刻の書式を解釈できません: ${lm})"$'\n'
        continue
    fi

    printf '%s\t%s\t%s\t%s\n' "$label" "$name" "$version" "$published" >>"$TMP/published.tsv"
    age=$((NOW_EPOCH - published))
    if [ "$age" -lt "$COOLDOWN_SECONDS" ]; then
        clear_at=$((published + COOLDOWN_SECONDS))
        [ "$clear_at" -gt "$latest_clear" ] && latest_clear=$clear_at
        young+="- ${label}(公開: $(date -u -d "@${published}" +'%Y-%m-%d %H:%M UTC'))"$'\n'
        printf '%s\t%s\t%s\t%s\t%s\n' "$eco" "$name" "$version" "$published" "$label" >>"$TMP/young.tsv"
    fi
done <<<"$added"

# --- 報告 -----------------------------------------------------------------------
# 待てば解消する失敗と、人間の確認が要る失敗を区別できる形で出す。
report_cooldown() {
    {
        if [ -n "$unknown" ]; then
            echo "### :warning: 公開時刻を取得できませんでした(判定不能)"
            echo ""
            echo "$unknown"
            echo "問い合わせ先: ${MAVEN_CENTRAL_BASE} / ${PLUGIN_PORTAL_BASE} / ${NPM_REGISTRY_BASE}"
            echo ""
            echo "**外部要因による失敗です。時間の経過では解消しません。**"
            echo "配布元の応答または応答形式を人間が確認してください。"
            echo ""
        fi
        if [ -n "$young" ]; then
            echo "### :hourglass: 公開から ${COOLDOWN_HOURS} 時間を経過していないパッケージ"
            echo ""
            echo "$young"
            echo "**待機が明ける時刻: $(date -u -d "@${latest_clear}" +'%Y-%m-%d %H:%M UTC')**"
            echo ""
            echo "時間の経過によって解消します。上記の時刻以降にこのチェックを再実行してください。"
            echo "件数が多い場合も、この時刻を過ぎれば全件が対象外になります。"
            echo ""
        fi
    } >>"$SUMMARY"

    if [ -n "$unknown" ]; then
        printf '公開時刻を取得できないパッケージがあります(判定不能):\n%s' "$unknown" >&2
    fi
    if [ -n "$young" ]; then
        printf '公開から %s 時間を経過していないパッケージがあります:\n%s' "$COOLDOWN_HOURS" "$young" >&2
        echo "待機が明ける時刻: $(date -u -d "@${latest_clear}" +'%Y-%m-%d %H:%M UTC')" >&2
    fi
}

# 所有者の承認を確かめる。承認があれば緑、無ければ赤で終える
# 使い方: owner_gate [記録のファイル]。記録のファイルを渡すと、承認待ちの表に版と理由になった警告を書く
owner_gate() {
    if [ "$OWNER_APPROVED" = true ]; then
        echo "所有者(${OWNER})の承認があります。"
        exit 0
    fi
    {
        echo "### :lock: 所有者の承認待ち"
        echo ""
        echo "この PR には、公開から ${COOLDOWN_HOURS} 時間待たずに入れる版の記録のコメントがあります。"
        echo "所有者(${OWNER})が承認すると、この検査は緑になります。"
        echo ""
        if [ -n "${1:-}" ]; then
            echo "| 部品 | 版 | 公開日時 | 理由になった警告 |"
            echo "|---|---|---|---|"
            # 部品の名前と版と警告の欄には縦棒が入らないので、表のマスとして逃がさない
            jq -r '.entries[]
                | "| \(.name) | \(.version) | \(.published_at | fromdate | strftime("%Y-%m-%d %H:%M UTC")) | \(
                    [.alerts[] | "[#\(.number)](\(.html_url)) \(.ghsa_id) \(.severity)"] | join("<br>")) |"' "$1"
        else
            echo "版と理由になった警告は、この PR の記録のコメントにあります。"
        fi
        echo ""
    } >>"$SUMMARY"
    echo "所有者(${OWNER})の承認待ちです。" >&2
    exit 1
}

# 記録のコメントを読み書きできないときは、承認の有無に関わらず赤で終える
record_failed() {
    {
        echo "### :warning: $1"
        echo ""
        echo "**外部要因による失敗です。** GitHub の API が戻ったあとに、このチェックを再実行してください。"
        echo ""
    } >>"$SUMMARY"
    echo "$1" >&2
    exit 1
}

if [ -n "$unknown" ]; then
    report_cooldown
    exit 1
fi

if [ ! -s "$TMP/young.tsv" ]; then
    echo "追加されたパッケージはすべて公開から ${COOLDOWN_HOURS} 時間を経過しています。"
    if ! rec=$(bash "$SCRIPT_DIR/record-cooldown-exception.sh" exists "$PR_NUMBER" </dev/null); then
        record_failed "記録のコメントを読めなかった"
    fi
    if [ "$rec" = "exists=true" ]; then
        owner_gate
    fi
    exit 0
fi

# --- 72時間待たずに入れる版の確かめ --------------------------------------------
# 止める版の一覧。各行は "<報告の名前>\t<理由の種類>\t<説明>"
: >"$TMP/blocked.tsv"

# 使い方: block <報告の名前> <理由の種類> [説明]
block() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$(printf '%s' "${3:-}" | tr '\t\n' '  ')" >>"$TMP/blocked.tsv"
}

# 使い方: block_all_young <理由の種類>。クールダウン未満の版をすべて止める
block_all_young() {
    local label
    while IFS=$'\t' read -r _ _ _ _ label; do
        block "$label" "$1"
    done <"$TMP/young.tsv"
}

# 理由の種類ごとの報告の文。警告に照らして条件を満たさなかった版は、公開からの時間を先に書く
reason_text() {
    local young_text="公開から${COOLDOWN_HOURS}時間経っていない"
    case "$1" in
    no-alert) echo "${young_text}。開いている脆弱性の警告が無い" ;;
    low-severity) echo "${young_text}。警告の深刻度が high でも critical でもない" ;;
    development) echo "${young_text}。警告が、開発のときだけ使う部品を示している" ;;
    no-scope) echo "${young_text}。警告に、本番で動くかが載っていない" ;;
    not-first-patched) echo "${young_text}。警告の最初の修正版ではない" ;;
    alerts-unreadable) echo "脆弱性の警告を読めなかった" ;;
    malicious) echo "悪意のある部品として公表されている" ;;
    malware-unknown) echo "悪意のある部品の一覧に照らせなかった" ;;
    different) echo "署名した者が前の版と違う" ;;
    no-new-signature) echo "前の版にある署名が、この版に無い" ;;
    signer-unknown) echo "署名を調べられなかった" ;;
    no-prior-version) echo "前の版が見つからない" ;;
    pnpm-exclude-missing) echo "除外の欄に、この版の要素が無い" ;;
    pnpm-exclude-unreadable) echo "除外の欄を読めなかった" ;;
    waiting-others) echo "この版は条件を満たすが、ほかの版を待つ" ;;
    *) echo "$young_text" ;;
    esac
}

# 表のマスに入れる文字列。縦棒は表の区切りと読まれないように逃がす
cell() {
    printf '%s' "$1" | sed 's/|/\\|/g'
}

# 止める版があれば、止めた版と理由を表で報告して赤で終える。
# 止めた版ごとに、部品と版と入るようになる時刻を書いた ::error:: の行を標準出力に出す
stop_if_blocked() {
    [ -s "$TMP/blocked.tsv" ] || return 0
    local label kind detail row name version published reason clear_at published_at
    local external=false malicious=false
    {
        echo "### :no_entry: ${COOLDOWN_HOURS}時間の待ちで止めた部品"
        echo ""
        echo "| 部品 | 版 | 公開日時 | 止めた理由 | 入るようになる時刻 |"
        echo "|---|---|---|---|---|"
    } >>"$SUMMARY"
    echo "${COOLDOWN_HOURS}時間の待ちで止めた部品があります:" >&2
    while IFS=$'\t' read -r label kind detail; do
        row=$(awk -F'\t' -v l="$label" '$1 == l { print $2 "\t" $3 "\t" $4; exit }' "$TMP/published.tsv")
        IFS=$'\t' read -r name version published <<<"$row"
        reason=$(reason_text "$kind")
        [ -z "$detail" ] || reason+="(${detail})"
        case "$kind" in
        alerts-unreadable | malware-unknown | signer-unknown)
            reason+="。外部のサービスに問い合わせられなかった"
            external=true
            ;;
        esac
        if [ -n "$published" ]; then
            published_at=$(date -u -d "@${published}" +'%Y-%m-%d %H:%M UTC')
            clear_at=$(date -u -d "@$((published + COOLDOWN_SECONDS))" +'%Y-%m-%d %H:%M UTC')
        else
            # 公開時刻を読めなかった版は先に赤で終えているので、ここに来るのは名前を照らせなかったときだけ
            name="$label" version="不明" published_at="不明" clear_at="不明"
        fi
        if [ "$kind" = malicious ]; then
            clear_at="入らない"
            malicious=true
        fi
        printf '| %s | %s | %s | %s | %s |\n' "$(cell "$name")" "$(cell "$version")" "$published_at" \
            "$(cell "$reason")" "$clear_at" >>"$SUMMARY"
        # ワークフローのコマンドの行では、% を %25 と書く
        printf '::error::%s時間の待ちで止めた部品: %s %s。理由: %s。入るようになる時刻: %s\n' \
            "$COOLDOWN_HOURS" "$name" "$version" "$reason" "$clear_at" | sed 's/%/%25/g'
        echo "- ${label}: ${reason}" >&2
    done <"$TMP/blocked.tsv"
    {
        echo ""
        if [ "$external" = true ]; then
            echo "**外部のサービスに問い合わせられなかった版があります。** 変更を作った人は、この失敗を自分では直せません。"
            echo "入るようになる時刻のあとか、外部のサービスが戻ったあとに、このチェックを再実行してください。"
            echo ""
        fi
        if [ "$malicious" = true ]; then
            echo "**悪意のある部品として公表されている部品があります。** その部品を変更から外してください。"
        else
            echo "**すべての版が入るようになる時刻: $(date -u -d "@${latest_clear}" +'%Y-%m-%d %H:%M UTC')**"
            echo ""
            echo "時間の経過によって解消します。上記の時刻以降にこのチェックを再実行してください。"
        fi
        echo ""
    } >>"$SUMMARY"
    exit 1
}

# 1. 脆弱性の警告に照らす
jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {ecosystem: .[0], name: .[1], version: .[2]})' \
    "$TMP/young.tsv" >"$TMP/young.json"
if ! bash "$SCRIPT_DIR/cooldown-match-alerts.sh" "$TMP/young.json" >"$TMP/alerts.json" </dev/null ||
    ! jq -r '.[] | [(if .ecosystem == "npm" then "\(.name)@\(.version)" else "\(.name):\(.version)" end),
            (if .eligible == true then "waiting-others" else .reason end),
            (if (.first_patched | length) > 0 then "最初の修正版: " + (.first_patched | join(", ")) else "" end)]
        | @tsv' "$TMP/alerts.json" >"$TMP/alerts.tsv" 2>/dev/null; then
    block_all_young alerts-unreadable
    stop_if_blocked
fi
# 条件を満たさない版があるときだけ止める。条件を満たす版は、ほかの版を待つとして並べる
if awk -F'\t' '$2 != "waiting-others" { found = 1 } END { exit !found }' "$TMP/alerts.tsv"; then
    cat "$TMP/alerts.tsv" >>"$TMP/blocked.tsv"
    stop_if_blocked
fi

# 2. 追加されたすべての部品を、悪意のある部品の一覧に照らす
printf '%s\n' "$added" |
    jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {ecosystem: .[0], name: .[1], version: .[2]})' \
        >"$TMP/added.json"
if bash "$SCRIPT_DIR/cooldown-check-malware.sh" "$TMP/added.json" >"$TMP/malware.json" </dev/null &&
    jq -r '.[] | select(.result != "clean")
        | [(if .ecosystem == "npm" then "\(.name)@\(.version)" else "\(.name):\(.version)" end),
           (if .result == "malicious" then "malicious" else "malware-unknown" end),
           ([.advisories[] | "\(.id) \(.summary) \(.url)"] | join("、"))]
        | @tsv' "$TMP/malware.json" >"$TMP/malware.tsv" 2>/dev/null; then
    cat "$TMP/malware.tsv" >>"$TMP/blocked.tsv"
else
    block_all_young malware-unknown
fi
stop_if_blocked

# 3. 前の版と署名した者を比べる
while IFS=$'\t' read -r eco name version _ label; do
    prior=$(prior_version "$eco" "$name")
    if [ -z "$prior" ]; then
        block "$label" no-prior-version
        continue
    fi
    out=$(bash "$SCRIPT_DIR/cooldown-check-signer.sh" "$eco" "$name" "$prior" "$version" </dev/null) || out=""
    result=$(printf '%s\n' "$out" | sed -n 's/^result=//p' | head -1)
    detail=$(printf '%s\n' "$out" | sed -n 's/^detail=//p' | head -1)
    case "$result" in
    same | no-prior-signature) ;;
    different | no-new-signature) block "$label" "$result" "$detail" ;;
    *) block "$label" signer-unknown "$detail" ;;
    esac
done <"$TMP/young.tsv"
stop_if_blocked

# 4. frontend の版が pnpm の除外の欄にあるかを確かめる
jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | select(.[0] == "npm") | {name: .[1], version: .[2]})' \
    "$TMP/young.tsv" >"$TMP/npm-young.json"
if [ "$(jq length "$TMP/npm-young.json")" -gt 0 ]; then
    if bash "$SCRIPT_DIR/cooldown-check-pnpm-exclude.sh" "$PNPM_WORKSPACE_FILE" "$TMP/npm-young.json" \
        >"$TMP/pnpm.json" </dev/null &&
        jq -r '.[] | select(.present != true) | ["\(.name)@\(.version)", "pnpm-exclude-missing", "足す1行: `\(.line)`"]
            | @tsv' "$TMP/pnpm.json" >"$TMP/pnpm.tsv" 2>/dev/null; then
        cat "$TMP/pnpm.tsv" >>"$TMP/blocked.tsv"
    else
        jq -r '.[] | ["\(.name)@\(.version)", "pnpm-exclude-unreadable", ""] | @tsv' \
            "$TMP/npm-young.json" >>"$TMP/blocked.tsv"
    fi
fi
stop_if_blocked

# 5. 記録のコメントを書く。同じ head の記録が既にあれば、record-cooldown-exception.sh が重ねない
jq -R -s -c --slurpfile alerts "$TMP/alerts.json" --argjson pr "$PR_NUMBER" --arg head "$HEAD_SHA" \
    --arg at "$(date -u -d "@${NOW_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)" '
    $alerts[0] as $al
    | {schema: 1, pr: $pr, head: $head, recorded_at: $at,
       entries: [split("\n")[] | select(length > 0) | split("\t") as $f
           | {ecosystem: $f[0], name: $f[1], version: $f[2],
              published_at: ($f[3] | tonumber | todate),
              alerts: [$al[] | select(.ecosystem == $f[0] and .name == $f[1] and .version == $f[2]) | .alerts[]]}]}' \
    "$TMP/young.tsv" >"$TMP/record.json"
if ! bash "$SCRIPT_DIR/record-cooldown-exception.sh" post "$PR_NUMBER" "$HEAD_SHA" "$TMP/record.json" </dev/null; then
    record_failed "記録のコメントを書けなかった"
fi

# 6. 所有者の承認を確かめる
owner_gate "$TMP/record.json"
