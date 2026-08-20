#!/usr/bin/env bash
# =====================================================================
# コンテナイメージのスキャン結果の判定
#
# 判定:
#   0 = マージを止める脆弱性が無い
#   1 = マージを止める脆弱性がある
#   2 = 入力が不正、または前提が一致しない
#
#   1 と 2 を分けるのは、呼び出し側が「脆弱性を検出した」と
#   「検査できなかった」を区別する必要があるため。週次の監視は前者では
#   Issueを操作して成功で終え、後者ではIssueを一切操作せず失敗させる。
#   2値に潰すと、検査不能を検出0件と取り違えてIssueを誤って閉じる。
#
# なぜ Trivy に判定させないか:
#   Trivy に抑制リストを渡すと、抑制された件が出力から消える。
#   それでは「全件を、抑制中かどうか区別できる形で提示する」を満たせない。
#   また .trivyignore.yaml は公式が EXPERIMENTAL と明記しており、
#   期限管理という中核の振る舞いを上流の実験的機能に預けることになる。
#   Trivy は検出だけを担い、何を許すかはこのスクリプトが決める。
#
# アーキテクチャの確認について:
#   Trivy の --platform はアサーションにならない。強制検証はコードに
#   あるが CLI に公開されておらず、単一アーキのイメージには黙って無視され、
#   不正な値を渡してもエラーにならない。tar 入力には一切適用されない。
#   検査対象が本番と同じ実行環境向けであることの機械的な保証は、
#   出力の .Metadata.ImageConfig.architecture の突き合わせだけ。
#
# 抑制のモードによる違い:
#   judge  抑制を判定に適用する(PRゲート)。記録の不備は終了コード2。
#   report 抑制を表示にのみ用い、判定には適用しない(週次)。記録の不備は
#          ::warning:: を残して続行し、「抑制」列を「取得できず」にする。
#          週次で止めると、再検査が完走しているのに起票が行われない状態が
#          生じる。抑制の妥当性はPRゲート側で必ず赤になるため、週次で
#          二重に止める必要が無い。
#
# 有効期限の解釈:
#   実行日(UTC)が expires 以前なら有効。expires と同じ日は有効とする。
#   YYYY-MM-DD は辞書順と時系列順が一致するため、比較は文字列で足りる。
#   形式と、実在する日付かどうかは jq 側で別に検証する。date に日付の
#   妥当性判定を任せると、GNU と busybox で受け付ける形が変わる。
#
# jq 上の注意:
#   .Results と .Vulnerabilities はいずれも omitempty でキーごと欠落しうる。
#   両階層に ? を付ける。脆弱性0件は Results 不在でも、Vulnerabilities を
#   持たない要素が残る形でも正常。
#   FixedVersion は "6.0.3.1, 5.2.4.3" のようにカンマ結合の複数版に
#   なりうるため、バージョンとしてパースせず非空判定にのみ使う。
#
# テスト: .github/scripts/tests/test-check-container-scan.sh
# 使い方: check-container-scan.sh <scan-json> <expected-arch> <suppressions-json> <apply-mode> <blocking-out> <detected-out>
#   apply-mode は judge(抑制を判定に適用)または report(表示にのみ用いる)
# =====================================================================
set -euo pipefail

# 引数不足を ${n:?} に任せると終了コード1になる。1 は「止めるものがある」を
# 意味し、週次はそれでIssue操作へ進む。検査が一度も走っていないのに
# 進む経路になるため、入力不正として2に倒す。
if [ "$#" -ne 6 ]; then
    echo "::error::引数は6個必要です: <scan-json> <expected-arch> <suppressions-json> <apply-mode> <blocking-out> <detected-out>"
    exit 2
fi

SCAN_JSON="${1}"
EXPECTED_ARCH="${2}"
SUPPRESSIONS_JSON="${3}"
APPLY_MODE="${4}"
BLOCKING_OUT="${5}"
DETECTED_OUT="${6}"
# GITHUB_STEP_SUMMARY が書けない場合は検査しない。Actions のランナーは
# 必ず書き込み可能なパスを設定するため、発生経路が無い。
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

case "$APPLY_MODE" in
    judge | report) ;;
    *)
        echo "::error::apply-mode は judge か report のいずれかです: ${APPLY_MODE}"
        exit 2
        ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq が見つかりません。この検査には jq が要ります。"
    exit 2
fi

# 出力先が書けないとリダイレクトが失敗して終了コード1になる。
# 1 は「止めるものがある」を意味するため、ここで2に倒す。
# Summary も同じ。未設定は /dev/null に逃がすが、設定されていて書けない
# 場合は表の追記でリダイレクトが失敗し、判定に関係なく1が漏れる。
if ! : >>"$SUMMARY" 2>/dev/null; then
    echo "::error::GITHUB_STEP_SUMMARY に書き込めません: ${SUMMARY}"
    exit 2
fi

for out in "$BLOCKING_OUT" "$DETECTED_OUT"; do
    # 空文字列は dirname が "." を返すため、ディレクトリ検査を素通りする。
    # ワークフローで変数が空展開する形はディレクトリ不在より起きやすい。
    if [ -z "$out" ]; then
        echo "::error::出力先が空です。"
        exit 2
    fi
    dir=$(dirname "$out")
    if [ ! -d "$dir" ] || [ ! -w "$dir" ]; then
        echo "::error::出力先に書き込めません: ${out}"
        exit 2
    fi
done

if [ ! -f "$SCAN_JSON" ]; then
    echo "::error::スキャン結果がありません: ${SCAN_JSON}"
    exit 2
fi

# ---------------------------------------------------------------------
# 抑制の記録の検証
#
# 抑制の記録が読めないまま検査を通すと、何が許されているか分からないまま
# 緑になる。judge では終了コード2に倒し、report では警告を残して
# 「取得できず」として続ける。
# ---------------------------------------------------------------------
SUPPRESSION_ERRORS=""

# 日付は jq 側で組み立て直して検証する。test() の正規表現だけでは
# 2026-13-45 のような実在しない日付を通してしまう。
# shellcheck disable=SC2016
SUPPRESSION_VALIDATION='
# $m は 1..12 に収まる前提で引く。負の添字は jq が末尾から数えるため、
# 呼び出し側の下限($m >= 1)が消えると 0 月が 12 月として通る。上限
# ($m <= 12)は範囲外参照が null を返し、日数比較が必ず偽になるため
# 結果としては重複した防御になる。読み手に範囲を示すために残す。
def days_in_month($y; $m):
    [31,
     (if (($y % 4 == 0) and ($y % 100 != 0)) or ($y % 400 == 0) then 29 else 28 end),
     31, 30, 31, 30, 31, 31, 30, 31, 30, 31][$m - 1];
# 長さを先に見る。jq の正規表現は Oniguruma で、$ が末尾の改行の手前にも
# マッチするため、末尾に改行の付いた日付が形式検証を素通りする。抑制が
# 成立したうえ、表の行が途中で折れて「判定」列が消える。
def is_date($s):
    ($s | type) == "string"
    and ($s | length) == 10
    and ($s | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
    and (($s[0:4] | tonumber) as $y
         | ($s[5:7] | tonumber) as $m
         | ($s[8:10] | tonumber) as $d
         | $m >= 1 and $m <= 12
           and $d >= 1 and $d <= days_in_month($y; $m));
def missing($v):
    ($v | type) != "string" or $v == "";
[
    (.suppressions | to_entries[]
        | (.key + 1) as $n
        | .value as $s
        | if ($s | type) != "object" then
              "\($n) 件目: オブジェクトではありません"
          else
              (if missing($s.id) then "\($n) 件目: id が無い、または空です" else empty end),
              (if missing($s.reason) then "\($n) 件目: reason が無い、または空です" else empty end),
              (if missing($s.expires) then
                   "\($n) 件目: expires が無い、または空です"
               elif (is_date($s.expires) | not) then
                   "\($n) 件目: expires が YYYY-MM-DD の実在する日付ではありません: \($s.expires)"
               else empty end)
          end),
    ([.suppressions[] | select(type == "object") | .id | select(type == "string" and . != "")]
        | group_by(.) | map(select(length > 1) | .[0])[]
        | "id が重複しています: \(.)")
] | .[]
'

validate_suppressions() {
    local problems
    if [ ! -f "$SUPPRESSIONS_JSON" ]; then
        SUPPRESSION_ERRORS="抑制の記録がありません: ${SUPPRESSIONS_JSON}"
        return 1
    fi
    if ! jq -e '.suppressions | type == "array"' "$SUPPRESSIONS_JSON" >/dev/null 2>&1; then
        SUPPRESSION_ERRORS="抑制の記録を解析できません、または suppressions が配列ではありません: ${SUPPRESSIONS_JSON}"
        return 1
    fi
    if ! problems=$(jq -r "$SUPPRESSION_VALIDATION" "$SUPPRESSIONS_JSON" 2>/dev/null); then
        SUPPRESSION_ERRORS="抑制の記録を検証できません: ${SUPPRESSIONS_JSON}"
        return 1
    fi
    if [ -n "$problems" ]; then
        SUPPRESSION_ERRORS="$problems"
        return 1
    fi
    return 0
}

# 抑制の記録を id => expires の対応表にする。null は「取得できず」を表す。
SUPPRESSION_MAP='null'
if validate_suppressions; then
    SUPPRESSION_MAP=$(jq -c '[.suppressions[] | {key: .id, value: .expires}] | from_entries' "$SUPPRESSIONS_JSON")
elif [ "$APPLY_MODE" = "judge" ]; then
    while IFS= read -r line; do
        echo "::error::抑制の記録が不正です: ${line}"
    done <<<"$SUPPRESSION_ERRORS"
    exit 2
else
    while IFS= read -r line; do
        echo "::warning::抑制の記録が不正です: ${line}"
    done <<<"$SUPPRESSION_ERRORS"
    echo "::warning::抑制の状態を「取得できず」として検査を続けます。"
fi

# 壊れた出力と「脆弱性0件」を区別するため、先に骨格の存在を確かめる。
# .SchemaVersion と architecture はスキャンが成立していれば必ずある。
if ! jq -e 'has("SchemaVersion")' "$SCAN_JSON" >/dev/null 2>&1; then
    echo "::error::スキャン結果を解析できません、または SchemaVersion がありません: ${SCAN_JSON}"
    exit 2
fi

# .Results 自体が配列でないと .Results[]? が黙って空になり、検出0件の緑と
# 区別が付かない。要素の型崩れは ::warning:: で足りるが、器の型崩れは
# 全件を取りこぼすため入力不正に倒す。
if ! jq -e '(has("Results") | not) or (.Results | type == "array")' "$SCAN_JSON" >/dev/null 2>&1; then
    echo "::error::スキャン結果の Results が配列ではありません: ${SCAN_JSON}"
    exit 2
fi

# Metadata や ImageConfig が非オブジェクトだと、素直に辿ると jq が
# 終了コード5で落ちる。? を挟んで入力不正として2に倒す。
actual_arch=$(jq -r '(.Metadata? | .ImageConfig? | .architecture? // "") | tostring' "$SCAN_JSON")
if [ -z "$actual_arch" ]; then
    echo "::error::検査対象のアーキテクチャが記録されていません。"
    exit 2
fi
if [ "$actual_arch" != "$EXPECTED_ARCH" ]; then
    echo "::error::検査対象のアーキテクチャが期待と一致しません。期待=${EXPECTED_ARCH} 実際=${actual_arch}"
    {
        echo "### コンテナイメージの脆弱性検査"
        echo ""
        echo ":no_entry: **検査対象のアーキテクチャが期待と一致しません。**"
        echo ""
        echo "| 項目 | 値 |"
        echo "|---|---|"
        echo "| 期待 | \`${EXPECTED_ARCH}\` |"
        echo "| 実際 | \`${actual_arch}\` |"
        echo ""
        echo "本番と別の実行環境向けのイメージを検査している。"
        echo ""
    } >>"$SUMMARY"
    exit 2
fi

TODAY=$(date -u +%Y-%m-%d)

# 検出された全件。fixable / severe / 抑制の状態 / 合否もここで付ける。
#   fixable  = FixedVersion が存在し空文字列でない
#   severe   = Severity が CRITICAL または HIGH
#   supState = unavailable(記録が読めない)/ none / active(有効期限内)/ expired
#   blocking = fixable かつ severe かつ、judge では有効期限内の抑制が無いもの
# shellcheck disable=SC2016
detected=$(jq --argjson sup "$SUPPRESSION_MAP" --arg today "$TODAY" --arg mode "$APPLY_MODE" '[
    .Results[]? | select(type == "object")
    | .Vulnerabilities[]? | select(type == "object")
    | {
        id: .VulnerabilityID,
        severity: .Severity,
        pkgName: .PkgName,
        installedVersion: .InstalledVersion,
        fixedVersion: (if (.FixedVersion // "") == "" then null else .FixedVersion end)
      }
    | . + {
        fixable: (.fixedVersion != null),
        severe: (.severity == "CRITICAL" or .severity == "HIGH")
      }
    | . + (
        if $sup == null then
            {supState: "unavailable", supExpires: null}
        else
            (if (.id | type) == "string" then $sup[.id] else null end) as $e
            | if $e == null then {supState: "none", supExpires: null}
              elif $e >= $today then {supState: "active", supExpires: $e}
              else {supState: "expired", supExpires: $e}
              end
        end
      )
    | . + {
        blocking: (
            .fixable and .severe
            and ($mode != "judge" or .supState != "active")
        )
      }
]' "$SCAN_JSON")

# 出力するのは契約の5キーだけ。判定用のフラグは外に出さない。
printf '%s' "$detected" | jq '[.[] | {id, severity, pkgName, installedVersion, fixedVersion}]' >"$DETECTED_OUT"

blocking=$(printf '%s' "$detected" | jq '[.[] | select(.blocking)]')
printf '%s' "$blocking" | jq '[.[] | {id, severity, pkgName, installedVersion, fixedVersion}]' >"$BLOCKING_OUT"

detected_count=$(printf '%s' "$detected" | jq 'length')

# Severity が無い要素は severe にならず「止めない」側へ落ちる。
# 実物の Trivy は必ず埋める(未知は UNKNOWN)ため、欠落は
# スキーマの変更を疑うべき事象。静かに素通りさせない。
# 期待した型でない要素は判定から落としている。実物の Trivy は必ず
# オブジェクトを出すため、落ちること自体がスキーマの変更を疑うべき事象。
# 無言で捨てると検出0件の緑と区別がつかない。
dropped=$(jq '
    ([.Results[]? | select(type != "object")] | length)
    + ([.Results[]? | select(type == "object") | .Vulnerabilities[]? | select(type != "object")] | length)
' "$SCAN_JSON")
if [ "$dropped" -gt 0 ]; then
    echo "::warning::期待した形でない要素を ${dropped} 件除外しました。Trivy の出力形式が変わった可能性があります。"
fi

no_severity=$(printf '%s' "$detected" | jq '[.[] | select(.severity == null)] | length')
if [ "$no_severity" -gt 0 ]; then
    echo "::warning::Severity を持たない脆弱性が ${no_severity} 件あります。Trivy の出力形式が変わった可能性があります。"
fi
blocking_count=$(printf '%s' "$blocking" | jq 'length')

# 有効期限内の抑制で止めなかった件は、期限が来れば赤に戻る。
# 何件がその状態かを実行ログに残す。
if [ "$APPLY_MODE" = "judge" ]; then
    suppressed_count=$(printf '%s' "$detected" | jq '[.[] | select(.fixable and .severe and .supState == "active")] | length')
    if [ "$suppressed_count" -gt 0 ]; then
        echo "::notice::有効期限内の抑制により ${suppressed_count} 件を止めていません。"
    fi
fi

# 全件を提示する。止めたものだけでなく、止めなかったものも出す。
# 止めなかったものこそ、あとで判断を見直す対象になる。
{
    echo "### コンテナイメージの脆弱性検査"
    echo ""
    echo "検出 ${detected_count} 件 / うちマージを止めるもの ${blocking_count} 件"
    echo ""
    if [ "$APPLY_MODE" = "report" ]; then
        echo "このモードでは抑制を判定に用いない。「抑制」列は状態の表示のみ。"
        echo ""
    fi
    if [ "$detected_count" -gt 0 ]; then
        echo "| ID | 深刻度 | パッケージ | 修正版 | 抑制 | 判定 |"
        echo "|---|---|---|---|---|---|"
        printf '%s' "$detected" | jq -r '
            .[]
            | (if .supState == "unavailable" then "取得できず"
               elif .supState == "active" then "有効期限内(\(.supExpires) まで)"
               elif .supState == "expired" then "期限切れ(\(.supExpires))"
               else "なし" end) as $suppression
            | "| \(.id) | \(.severity) | \(.pkgName) \(.installedVersion) | \(.fixedVersion // "なし") | \($suppression) | "
              + (if .blocking then "マージを止める" else "止めない" end)
              + " |"
        '
        echo ""
    fi
} >>"$SUMMARY"

echo "検出 ${detected_count} 件 / マージを止めるもの ${blocking_count} 件"

# 注釈の種別はモードで変える。終了コード1の意味はどちらも同じだが、
# 呼び出し側での扱いが違う。judge はこの件数がそのままジョブの失敗になるため
# ::error:: が実態と一致する。report は終了コード1でもジョブを成功で終える
# 設計であり、成功した run に ::error:: が並ぶと、週次の点検で結論と注釈が
# 食い違って読める。
if [ "$blocking_count" -gt 0 ]; then
    if [ "$APPLY_MODE" = "judge" ]; then
        echo "::error::修正版のある CRITICAL / HIGH の脆弱性が ${blocking_count} 件あります。"
    else
        echo "::warning::修正版のある CRITICAL / HIGH の脆弱性が ${blocking_count} 件あります。"
    fi
    exit 1
fi
