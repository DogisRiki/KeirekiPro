#!/usr/bin/env bash
# =====================================================================
# Gradle wrapper の配布物検査(guardrails CI から実行)
#
# 判定: 配布元のホストが公式でない、公表チェックサムと一致しない、または
#       チェックサムの項目が存在しない場合に exit 1(赤)。
#       wrapper 関連の変更が差分に無ければ、外部への問い合わせを行わず exit 0。
#
# なぜ必要か:
#   wrapper はビルドの実行環境そのものを取得する。差し替えられると、以降の
#   すべての検査が信用できなくなる。アクション参照のSHA固定検査と目的が同じで、
#   「ビルドが取得する外部成果物の同一性」を守る。
#
# なぜホストの検査が要るのか:
#   gradle-wrapper.properties の validateDistributionUrl は wrapper タスクの実行時に
#   URLを検証する設定であり、チェックインされたファイルをビルド時に検証するものではない。
#   ホストの固定も行わない。
#
# なぜチェックサムの検査が要るのか:
#   Gradle 自身のチェックサム検証は配布物のダウンロード時にしか行われない。実測で、
#   誤った値を入れてもキャッシュ済みの環境では素通りし、キャッシュを削除して初めて
#   照合されて停止することを確認した。値そのものが書き換えられた場合を捉えるには、
#   公表値と突き合わせるこの検査が要る。
#
#   ただしホストの検査とチェックサムの検査は信頼の根が同じである。配布元が侵害されれば
#   両方が同時に偽装される。実質的に効いているのはホストの固定であり、この検査は
#   手作業による書き換えとの不整合を検知するものと位置づける。
#
# なぜ jar を見ないのか:
#   jar の公式チェックサムとの照合は gradle/actions/wrapper-validation が行う。
#   ホモグリフ偽装されたファイル名の探索を含むため、そちらに任せる。
#
# なぜ実行条件を自分で判定するのか:
#   条件を付けないと全PRが毎回 services.gradle.org へ問い合わせることになり、
#   fail closed と組み合わさって外部ホストの不調時にすべてのPRが赤になる。
#   wrapper の変更頻度は年数回であり、常時照会する必要がない。
#
#   条件に jar の変更を含めるのは、wrapper のディレクトリ外に置かれた偽装ファイルを
#   取りこぼさないため。jar がコミットされるのは wrapper 以外に事実上無い。
#
# テスト: .github/scripts/tests/test-check-gradle-wrapper.sh
# 使い方: check-gradle-wrapper.sh <base_sha> <head_sha>
#   環境変数 GRADLE_DIST_HOST(既定 services.gradle.org。テスト用に差し替える)
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"

OFFICIAL_HOST="${GRADLE_DIST_HOST:-services.gradle.org}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")

# --- 実行条件の判定 -------------------------------------------------------------
# wrapper のディレクトリ配下の変更、または jar の追加・変更があるときだけ検査する。
#
# git diff の失敗は握りつぶさない。失敗して空になったものを「対象外」と扱うと、
# 差分が取れないときに検査ごと素通りする。set -e により赤で止める。
# 後段の grep の || true は、一致なしが正常系(対象外)であるため残す。
changed=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA")
relevant=$(printf '%s\n' "$changed" | grep -E '(^|/)gradle/wrapper/|\.jar$' || true)

# 実行条件をワークフローへ渡す。jar の照合も同じ条件で動かす必要があるため、
# 条件をワークフロー側にも書くと判定が2箇所に分かれて食い違う。ここだけを根拠にする。
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    if [ -n "$relevant" ]; then
        echo "relevant=true" >>"$GITHUB_OUTPUT"
    else
        echo "relevant=false" >>"$GITHUB_OUTPUT"
    fi
fi

if [ -z "$relevant" ]; then
    echo "wrapper 関連の変更がないため、配布元への問い合わせを行いません。"
    exit 0
fi

echo "wrapper 関連の変更を検出したため検査します:"
printf '%s\n' "$relevant"

# --- 検査対象の列挙 -------------------------------------------------------------
# 複数プロジェクトに増えても取りこぼさないよう、追跡下の全 wrapper 設定を対象にする。
targets=$(git ls-files | grep -E '(^|/)gradle/wrapper/gradle-wrapper\.properties$' || true)

detected=""

if [ -z "$targets" ]; then
    detected+="- gradle-wrapper.properties が1つも見つかりません。削除された場合、"$'\n'
    detected+="  配布物の同一性を検証する手段が失われます"$'\n'
fi

# --- 検査 -----------------------------------------------------------------------
for f in $targets; do
    # プロパティファイルではコロンが \: と書かれるため戻す
    dist_url=$(sed -n 's/^distributionUrl=//p' "$f" | tail -1 | sed 's/\\:/:/g')
    dist_sum=$(sed -n 's/^distributionSha256Sum=//p' "$f" | tail -1)

    if [ -z "$dist_url" ]; then
        detected+="- ${f}: distributionUrl がありません"$'\n'
        continue
    fi

    # 検査1: 配布元のホストが公式であること
    host=$(printf '%s' "$dist_url" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')
    if [ "$host" != "$OFFICIAL_HOST" ]; then
        detected+="- ${f}: 配布元のホストが公式ではありません(${host})。"$'\n'
        detected+="  期待するホスト: ${OFFICIAL_HOST}"$'\n'
        continue
    fi

    # 検査2: チェックサムの項目が存在すること
    if [ -z "$dist_sum" ]; then
        detected+="- ${f}: distributionSha256Sum がありません。"$'\n'
        detected+="  この項目が無いと依存更新の自動化がチェックサムを管理せず、"$'\n'
        detected+="  バージョンだけが進んで検証が成立しなくなります"$'\n'
        continue
    fi

    # 検査3: 公表値と一致すること(リダイレクト追従が必須)
    official=$(curl -sSL --max-time 20 "${dist_url}.sha256" 2>/dev/null | tr -d '[:space:]' || true)
    if ! printf '%s' "$official" | grep -qE '^[0-9a-f]{64}$'; then
        detected+="- ${f}: 公表チェックサムを取得できません(${dist_url}.sha256)。"$'\n'
        detected+="  外部要因による失敗です"$'\n'
        continue
    fi
    if [ "$dist_sum" != "$official" ]; then
        detected+="- ${f}: チェックサムが公表値と一致しません。"$'\n'
        detected+="  設定値: ${dist_sum}"$'\n'
        detected+="  公表値: ${official}"$'\n'
        continue
    fi

    echo "${f}: 配布元と公表チェックサムの一致を確認しました。"
done

if [ -z "$detected" ]; then
    exit 0
fi

{
    echo "### :no_entry: Gradle wrapper の検査に失敗しました"
    echo ""
    echo "$detected"
    echo "**時間の経過では解消しません。** 設定の修正、または配布元の応答の確認が要ります。"
    echo ""
} >>"$SUMMARY"

printf 'Gradle wrapper の検査に失敗しました:\n%s' "$detected" >&2
exit 1
