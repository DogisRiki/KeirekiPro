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

# 抑制の記録が読めないまま検査を通すと、何が許されているか分からないまま
# 緑になる。存在と形式をここで確かめる。
if [ ! -f "$SUPPRESSIONS_JSON" ]; then
    echo "::error::抑制の記録がありません: ${SUPPRESSIONS_JSON}"
    exit 2
fi
if ! jq -e '.suppressions | type == "array"' "$SUPPRESSIONS_JSON" >/dev/null 2>&1; then
    echo "::error::抑制の記録を解析できません、または suppressions が配列ではありません: ${SUPPRESSIONS_JSON}"
    exit 2
fi

# 壊れた出力と「脆弱性0件」を区別するため、先に骨格の存在を確かめる。
# .SchemaVersion と architecture はスキャンが成立していれば必ずある。
if ! jq -e 'has("SchemaVersion")' "$SCAN_JSON" >/dev/null 2>&1; then
    echo "::error::スキャン結果を解析できません、または SchemaVersion がありません: ${SCAN_JSON}"
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

# 検出された全件。fixable / severe の判定もここで付ける。
#   fixable = FixedVersion が存在し空文字列でない
#   severe  = Severity が CRITICAL または HIGH
detected=$(jq '[
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
]' "$SCAN_JSON")

# 出力するのは契約の5キーだけ。判定用のフラグは外に出さない。
printf '%s' "$detected" | jq '[.[] | {id, severity, pkgName, installedVersion, fixedVersion}]' >"$DETECTED_OUT"

blocking=$(printf '%s' "$detected" | jq '[.[] | select(.fixable and .severe)]')
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

# 全件を提示する。止めたものだけでなく、止めなかったものも出す。
# 止めなかったものこそ、あとで判断を見直す対象になる。
{
    echo "### コンテナイメージの脆弱性検査"
    echo ""
    echo "検出 ${detected_count} 件 / うちマージを止めるもの ${blocking_count} 件"
    echo ""
    if [ "$detected_count" -gt 0 ]; then
        echo "| ID | 深刻度 | パッケージ | 修正版 | 抑制 | 判定 |"
        echo "|---|---|---|---|---|---|"
        printf '%s' "$detected" | jq -r '
            .[]
            | "| \(.id) | \(.severity) | \(.pkgName) \(.installedVersion) | \(.fixedVersion // "なし") | なし | "
              + (if (.fixable and .severe) then "マージを止める" else "止めない" end)
              + " |"
        '
        echo ""
    fi
} >>"$SUMMARY"

echo "検出 ${detected_count} 件 / マージを止めるもの ${blocking_count} 件"

if [ "$blocking_count" -gt 0 ]; then
    echo "::error::修正版のある CRITICAL / HIGH の脆弱性が ${blocking_count} 件あります。"
    exit 1
fi
