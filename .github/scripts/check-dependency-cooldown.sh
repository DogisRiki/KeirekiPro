#!/usr/bin/env bash
# =====================================================================
# 依存クールダウン検査(dependency-review CI から実行)
#
# 判定: このPRで新しく追加された maven のパッケージのうち、公開から一定時間を
#       経過していないものが1件でもあれば exit 1(赤)。全て経過していれば exit 0。
#       公開時刻を取得できないものが1件でもあれば exit 1(fail closed)。
#
# なぜ必要か:
#   frontend は pnpm の minimumReleaseAge がリゾルバレベルで公開直後の版を弾く。
#   backend にはこれに相当する標準機構が無い。Dependabot 経由の更新には Dependabot 自身の
#   既定クールダウンが効くが、エージェントが直接バージョンカタログを編集して公開直後の
#   パッケージを追加する経路には何も効かない。この穴を埋める。
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
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須)
#   COOLDOWN_HOURS(既定72) / NOW_EPOCH(テスト用の時刻固定)
#   MAVEN_CENTRAL_BASE / PLUGIN_PORTAL_BASE(テスト用の配布元差し替え)
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
: "${GH_TOKEN:?GH_TOKEN required}"

COOLDOWN_HOURS="${COOLDOWN_HOURS:-72}"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
MAVEN_CENTRAL_BASE="${MAVEN_CENTRAL_BASE:-https://repo1.maven.org/maven2}"
PLUGIN_PORTAL_BASE="${PLUGIN_PORTAL_BASE:-https://plugins.gradle.org/m2}"

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
COOLDOWN_SECONDS=$((COOLDOWN_HOURS * 3600))

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

# --- 追加されたパッケージの取得 -------------------------------------------------
# change_type=added かつ maven のものだけを見る。github-actions のエコシステムは
# アクション参照のSHA固定検査が別に担っているため対象にしない。
#
# 取得の失敗を握りつぶさない。失敗して空になったものを「追加なし」と扱うと、
# 比較APIがエラーを返す場合に静かに緑になる。fail closed の破れにあたる。
compare_out=""
if ! compare_out=$(gh api --paginate \
    "repos/${REPO}/dependency-graph/compare/${BASE_SHA}...${HEAD_SHA}" \
    --jq '.[] | select(.change_type == "added") | select(.ecosystem == "maven") | "\(.name)\t\(.version)"'); then
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

added=$(printf '%s' "$compare_out" | sort -u)

if [ -z "$added" ]; then
    echo "このPRで新しく追加された maven のパッケージはありません。"
    exit 0
fi

echo "追加されたパッケージ: $(printf '%s\n' "$added" | wc -l) 件"

# --- 公開時刻の取得 -------------------------------------------------------------
# HEADリクエストの Last-Modified を使う。Maven Central を先に引き、404 のときだけ
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

young=""    # クールダウン未満
unknown=""  # 公開時刻を取得できなかったもの
latest_clear=0

while IFS=$'\t' read -r name version; do
    [ -n "$name" ] || continue
    path=$(pom_path "$name" "$version")

    rc=0
    lm=$(head_last_modified "${MAVEN_CENTRAL_BASE}/${path}") || rc=$?
    if [ "$rc" -eq 2 ]; then
        rc=0
        lm=$(head_last_modified "${PLUGIN_PORTAL_BASE}/${path}") || rc=$?
    fi
    [ "$rc" -eq 0 ] || lm=""

    if [ -z "$lm" ]; then
        unknown+="- ${name}:${version}"$'\n'
        continue
    fi

    published=$(date -u -d "$lm" +%s 2>/dev/null || true)
    if [ -z "$published" ]; then
        unknown+="- ${name}:${version}(公開時刻の書式を解釈できません: ${lm})"$'\n'
        continue
    fi

    age=$((NOW_EPOCH - published))
    if [ "$age" -lt "$COOLDOWN_SECONDS" ]; then
        clear_at=$((published + COOLDOWN_SECONDS))
        [ "$clear_at" -gt "$latest_clear" ] && latest_clear=$clear_at
        young+="- ${name}:${version}(公開: $(date -u -d "@${published}" +'%Y-%m-%d %H:%M UTC'))"$'\n'
    fi
done <<<"$added"

# --- 報告 -----------------------------------------------------------------------
# 待てば解消する失敗と、人間の確認が要る失敗を区別できる形で出す。
if [ -z "$unknown" ] && [ -z "$young" ]; then
    echo "追加されたパッケージはすべて公開から ${COOLDOWN_HOURS} 時間を経過しています。"
    exit 0
fi

{
    if [ -n "$unknown" ]; then
        echo "### :warning: 公開時刻を取得できませんでした(判定不能)"
        echo ""
        echo "$unknown"
        echo "問い合わせ先: ${MAVEN_CENTRAL_BASE} / ${PLUGIN_PORTAL_BASE}"
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

exit 1
