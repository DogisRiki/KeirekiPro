#!/bin/bash
# =====================================================================
# 共通ライブラリ: spec-review の状態の走査
#
# check-spec-review-before-stop.sh と notify-spec-review.sh が source する。
# 両者で判定がずれないよう、走査は1箇所に置く。
#
# spec_review_scan <project_dir> は、レビューが必要な段階を1行1件で出力する。
#   <feature>|<stage>|<ブロック理由をカンマ区切り>|<未解決件数>
# ブロック理由が空なら、その段階はStop hookの停止対象ではない。
#
# 対象の判定: generated が true で、かつ人の承認が無い段階。
#   approved が true でない → 未承認
#   approved_by が空、または ':' を含む → 人の承認ではない
#     (auto:-y / auto:batch / unknown:pre-existing はいずれも ':' を含む)
#   phase が initialized の spec は対象外(/kiro-spec-init 直後)
# =====================================================================

# spec.json から値を取り出す。$1=ファイル $2... = キーの並び
_sr_json() {
    local f="$1"; shift
    perl -MJSON::PP -e '
        my $f = shift @ARGV;
        open my $fh, "<", $f or exit 0;
        local $/; my $d = eval { JSON::PP::decode_json(<$fh>) };
        exit 0 unless ref $d;
        my $v = $d;
        for my $k (@ARGV) { $v = eval { $v->{$k} }; last unless defined $v; }
        if (JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
        elsif (defined $v && !ref $v) { print $v }
    ' -- "$f" "$@" 2>/dev/null
}

# reviewファイルの最新サイクル・往復の節に現れる指摘IDを列挙する
_sr_latest_ids() {
    local f="$1"
    [ -f "$f" ] || return 0
    awk '/^## サイクル/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$f" \
        | grep -oE '\b[RDT][0-9]+-[0-9]+-[0-9]+\b' | sort -u
}

spec_review_scan() {
    local project_dir="$1"
    local specs_dir="$project_dir/.kiro/specs"
    [ -d "$specs_dir" ] || return 0

    local spec_json feature phase stage gen approved by
    local review response evidence blockers unresolved

    for spec_json in "$specs_dir"/*/spec.json; do
        [ -f "$spec_json" ] || continue
        feature=$(basename "$(dirname "$spec_json")")
        phase=$(_sr_json "$spec_json" phase)
        [ "$phase" = "initialized" ] && continue

        for stage in requirements design tasks; do
            gen=$(_sr_json "$spec_json" approvals "$stage" generated)
            [ "$gen" = "true" ] || continue

            approved=$(_sr_json "$spec_json" approvals "$stage" approved)
            by=$(_sr_json "$spec_json" approvals "$stage" approved_by)
            # 人の承認がある段階は対象外
            if [ "$approved" = "true" ] && [ -n "$by" ] && ! printf '%s' "$by" | grep -q ':'; then
                continue
            fi

            review="$project_dir/.kiro/specs/$feature/reviews/${stage}-review.md"
            response="$project_dir/.kiro/specs/$feature/reviews/${stage}-response.md"
            evidence="$project_dir/.claude/.state/spec-review/${feature}__${stage}.evidence"
            blockers=""
            unresolved=0

            # 1. レビューの実施と完了の印
            if [ ! -f "$review" ]; then
                blockers="レビュー未実施"
            else
                local marker
                marker=$(grep -v '^[[:space:]]*$' "$review" | tail -1 | tr -d '\r')
                printf '%s' "$marker" | grep -qE '^-[[:space:]]*往復:.*未解決:[[:space:]]*[0-9]+' \
                    || blockers="${blockers:+$blockers,}レビューが完了していない"
                unresolved=$(printf '%s' "$marker" | grep -oE '未解決:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
                [ -z "$unresolved" ] && unresolved=0
            fi

            # 2. 対応の記録と、最新往復の全指摘への処置
            if [ ! -f "$response" ]; then
                [ -f "$review" ] && blockers="${blockers:+$blockers,}対応の記録がない"
            elif [ -f "$review" ]; then
                local id missing fixed
                missing=""; fixed=""
                for id in $(_sr_latest_ids "$review"); do
                    if ! grep -q "$id" "$response"; then
                        missing="${missing:+$missing }$id"
                    elif grep "$id" "$response" | grep -q '修正'; then
                        fixed="${fixed:+$fixed }$id"
                    fi
                done
                [ -n "$missing" ] && blockers="${blockers:+$blockers,}未処置の指摘($missing)"
                # 最終往復に「修正」が残るのは、直した後に再レビューしていない状態
                [ -n "$fixed" ] && blockers="${blockers:+$blockers,}修正後の再レビューがない($fixed)"
            fi

            # 3. 証跡と、レビュー完了後の改変
            if [ ! -f "$evidence" ]; then
                blockers="${blockers:+$blockers,}証跡がない"
            elif [ -f "$review" ]; then
                local recorded current
                recorded=$(sed -n 's/^review_hash=//p' "$evidence" | head -1)
                if command -v sha256sum >/dev/null 2>&1; then
                    current=$(sha256sum "$review" | awk '{print $1}')
                else
                    current=$(cksum "$review" | awk '{print $1"-"$2}')
                fi
                [ -n "$recorded" ] && [ "$recorded" != "$current" ] \
                    && blockers="${blockers:+$blockers,}レビュー後にreviewファイルが変わっている"
            fi

            # 4. 本文がレビューより新しい(直したのにレビューし直していない)
            local body="$project_dir/.kiro/specs/$feature/${stage}.md"
            if [ -f "$body" ] && [ -f "$review" ] && [ "$body" -nt "$review" ]; then
                blockers="${blockers:+$blockers,}本文がレビューより新しい"
            fi

            printf '%s|%s|%s|%s\n' "$feature" "$stage" "$blockers" "$unresolved"
        done
    done
}
