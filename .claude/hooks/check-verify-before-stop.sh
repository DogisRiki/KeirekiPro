#!/bin/bash
# =====================================================================
# Stop hook: 品質ゲート未実行の注意喚起
#
# 未コミットの変更がある領域(frontend/backend/terraform)について、
# 最終変更(epoch秒)より後に品質ゲートの完了コマンドが実行されて
# いなければ停止をブロックして注意喚起する(exit 2)。
# ファイル一覧は git status --porcelain -z で取得する
# (日本語ファイル名が引用符でエスケープされ、更新時刻の比較が
# スキップされる問題を避けるため)。
# 無限ループ防止のため stop_hook_active のときは常に通す。
# 前提: Git for Windows(Git Bash同梱)。JSON解析は同梱perl(JSON::PP)を使用。
# =====================================================================
set -u

payload=$(cat)

extract() {
    printf '%s' "$payload" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d;
        my $v = $d;
        for my $k (@ARGV) { $v = eval { $v->{$k} }; last unless defined $v; }
        if (defined $v && !ref $v) { print $v }
        elsif (defined $v && JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
    ' -- "$@" 2>/dev/null
}

# Stop hookからの継続中は再ブロックしない(無限ループ防止)
stop_active=$(extract stop_hook_active)
case "$stop_active" in
    true | 1) exit 0 ;;
esac

project_dir="${CLAUDE_PROJECT_DIR:-}"
[ -z "$project_dir" ] && project_dir=$(extract cwd)
[ -z "$project_dir" ] && exit 0
project_dir=${project_dir//\\//}
[ -d "$project_dir" ] || exit 0
cd "$project_dir" || exit 0

state_dir="$project_dir/.claude/.state"

# NUL区切りで変更ファイル一覧を取得する(リネームは新パスの直後に旧パスが続くため読み飛ばす)
changed_paths=()
skip_next=0
while IFS= read -r -d '' entry; do
    if [ "$skip_next" = 1 ]; then
        skip_next=0
        continue
    fi
    status=${entry:0:2}
    path=${entry:3}
    case "$status" in
        R* | C*) skip_next=1 ;;
    esac
    [ -n "$path" ] && changed_paths+=("$path")
done < <(git status --porcelain -z 2>/dev/null)

[ "${#changed_paths[@]}" -eq 0 ] && exit 0

pending_areas=""
for area in frontend backend terraform; do
    area_files=()
    for p in "${changed_paths[@]}"; do
        case "$p" in
            "$area"/*) area_files+=("$p") ;;
        esac
    done
    [ "${#area_files[@]}" -eq 0 ] && continue

    stamp_file="$state_dir/gate-run-$area.txt"
    if [ ! -f "$stamp_file" ]; then
        pending_areas="$pending_areas $area"
        continue
    fi

    gate_run_at=$(cat "$stamp_file" 2>/dev/null)
    case "$gate_run_at" in
        '' | *[!0-9]*)
            # epoch秒として読めない(旧形式・破損)場合はスタンプ無し扱い
            pending_areas="$pending_areas $area"
            continue
            ;;
    esac

    latest_change=0
    for f in "${area_files[@]}"; do
        [ -e "$f" ] || continue
        mtime=$(stat -c %Y "$f" 2>/dev/null) || continue
        if [ "$mtime" -gt "$latest_change" ]; then
            latest_change=$mtime
        fi
    done

    if [ "$latest_change" -gt "$gate_run_at" ]; then
        pending_areas="$pending_areas $area"
    fi
done

pending_areas=${pending_areas# }
if [ -n "$pending_areas" ]; then
    areas=$(printf '%s' "$pending_areas" | sed 's/ /, /g')
    {
        echo "品質ゲート未実行の変更があります: $areas"
        echo "完了報告の前に、該当領域の verify(/verify-all)を実行してください。実行不要な理由がある場合はその旨を報告に含めてください。"
    } >&2
    exit 2
fi

exit 0
