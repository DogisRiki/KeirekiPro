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
# 作業フォルダは入力の cwd の git の最上位(git -C <cwd> rev-parse --show-toplevel)で決め、
# cwd が無いとき、または cwd から決まらない(git のリポジトリの外、無いディレクトリ)ときは、
# CLAUDE_PROJECT_DIR の git の最上位を使う。CLAUDE_PROJECT_DIR はセッションを始めた場所のまま
# 変わらないので、worktree で作業するセッションはそれぞれの作業フォルダの変更と記録を見る。
# 品質ゲートが通った記録(その作業フォルダの .claude/.state/gate-run-<領域>.txt)は
# .claude/scripts/parallel/run-check.sh だけが書く。
# cwd からも CLAUDE_PROJECT_DIR からも作業フォルダが決まらないときだけ通す。
# 無限ループ防止のため stop_hook_active のときは常に通す。
# 前提: bash と perl(JSON::PP)。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

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

# 与えたディレクトリの git の最上位を出す。決まらなければ終了コード1
toplevel_of() {
    local dir="${1//\\//}" top
    [ -n "$dir" ] && [ -d "$dir" ] || return 1
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
    top=${top//\\//}
    [ -n "$top" ] || return 1
    printf '%s' "$top"
}

# 作業フォルダ: 入力の cwd の git の最上位。cwd が無いときと、cwd から決まらないとき
# (Claude が作業フォルダの外へ cd したままなど)は、CLAUDE_PROJECT_DIR の git の最上位を使う
project_dir=$(toplevel_of "$(extract cwd)") \
    || project_dir=$(toplevel_of "${CLAUDE_PROJECT_DIR:-}") \
    || exit 0
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
        # 更新時刻の取得。GNU coreutils は -c %Y、BSD(macOS)は -f %m。
        # 取れなかったファイルを黙って飛ばすと、品質ゲート未実行の検知が
        # 無言で通るため、両方を試す。
        # GNUの -f は --file-system の意味になり数字以外を返すため、
        # epoch秒として使える値かを必ず確かめる
        mtime=$(stat -c %Y "$f" 2>/dev/null)
        case "$mtime" in
            ''|*[!0-9]*) mtime=$(stat -f %m "$f" 2>/dev/null) ;;
        esac
        case "$mtime" in
            ''|*[!0-9]*) continue ;;
        esac
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
