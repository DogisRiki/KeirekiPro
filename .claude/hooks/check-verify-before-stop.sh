#!/bin/bash
# =====================================================================
# Stop hook: 品質ゲート未実行の注意喚起
#
# 未コミットの変更がある領域(frontend/backend/backend-go/terraform)について、
# 最終変更(epoch秒)より後に品質ゲートの完了コマンドが実行されて
# いなければ停止をブロックして注意喚起する(exit 2)。
# backend は Java 版、backend-go は Go 版の領域である。変わったファイルを Java 版と Go 版に
# 分ける見分け方は、ci.yaml の見分け backend_java と backend_go と同じにする。
# Go 版の領域は、作業フォルダに backend/go.mod があるときだけ当てる(無いときは Go 版の
# 品質チェックを動かせず、記録を書けないため)。マイグレーションのファイルは両方に当てる。
# ファイル一覧は git status --porcelain -z --untracked-files=all で取得する
# (日本語ファイル名が引用符でエスケープされ、更新時刻の比較が
# スキップされる問題を避けるため。また、git が追っていない新しいフォルダを
# フォルダの名前1つにまとめず、中のファイルごとに見分けるため)。
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
done < <(git status --porcelain -z --untracked-files=all 2>/dev/null)

[ "${#changed_paths[@]}" -eq 0 ] && exit 0

# Java 版のファイルか(ci.yaml の見分け backend_java と同じ形)
is_java_file() {
    case "$1" in
        backend/src/* | backend/gradle/* | backend/config/* | docker/backend/*) return 0 ;;
        backend/*/*) return 1 ;;
        backend/*.gradle | backend/gradlew*) return 0 ;;
    esac
    return 1
}

# Go 版のファイルか(ci.yaml の見分け backend_go と同じ形。backend/go.mod があるかは呼ぶ側で確かめる)
is_go_file() {
    case "$1" in
        backend/*.go | backend/api/* | backend/assets/* | docker/backend-go/*) return 0 ;;
        backend/src/main/resources/db/migration/* | backend/src/main/resources/mail/*) return 0 ;;
        backend/db/queries/*) return 0 ;;
        backend/go.mod | backend/go.sum | backend/Makefile | backend/sqlc.yaml) return 0 ;;
        backend/.golangci.yml | backend/.testcoverage.yml | backend/.gremlins.yaml) return 0 ;;
    esac
    return 1
}

# ファイルの更新時刻(epoch秒)を出す。取れなければ何も出さない
file_mtime() {
    local f="$1" mtime
    [ -e "$f" ] || return 0
    # 更新時刻の取得。GNU coreutils は -c %Y、BSD(macOS)は -f %m。
    # 取れなかったファイルを黙って飛ばすと、品質ゲート未実行の検知が
    # 無言で通るため、両方を試す。
    # GNUの -f は --file-system の意味になり数字以外を返すため、
    # epoch秒として使える値かを必ず確かめる
    mtime=$(stat -c %Y "$f" 2>/dev/null)
    case "$mtime" in
        '' | *[!0-9]*) mtime=$(stat -f %m "$f" 2>/dev/null) ;;
    esac
    case "$mtime" in
        '' | *[!0-9]*) return 0 ;;
    esac
    printf '%s' "$mtime"
}

has_go_mod=0
[ -f backend/go.mod ] && has_go_mod=1

# 領域ごとに、変わったファイルがあるか(touched_*)と、いちばん新しい更新時刻(latest_*)を求める。
# 変数の名前では、領域の名前の - を _ に替える(backend-go は backend_go)。
# 変数は名前を組み立てて読み書きするので、初めの値も printf -v で入れる
for v in frontend backend backend_go terraform; do
    printf -v "touched_$v" 0
    printf -v "latest_$v" 0
done
for p in "${changed_paths[@]}"; do
    hit=""
    case "$p" in
        frontend/*) hit="$hit frontend" ;;
        terraform/*) hit="$hit terraform" ;;
    esac
    is_java_file "$p" && hit="$hit backend"
    [ "$has_go_mod" = 1 ] && is_go_file "$p" && hit="$hit backend_go"
    [ -n "$hit" ] || continue
    mtime=$(file_mtime "$p")
    for v in $hit; do
        printf -v "touched_$v" 1
        [ -n "$mtime" ] || continue
        latest_var="latest_$v"
        if [ "$mtime" -gt "${!latest_var}" ]; then
            printf -v "latest_$v" '%s' "$mtime"
        fi
    done
done

pending_areas=""
for area in frontend backend backend-go terraform; do
    v=${area//-/_}
    touched_var="touched_$v"
    latest_var="latest_$v"
    [ "${!touched_var}" = 1 ] || continue

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

    if [ "${!latest_var}" -gt "$gate_run_at" ]; then
        pending_areas="$pending_areas $area"
    fi
done

pending_areas=${pending_areas# }
if [ -n "$pending_areas" ]; then
    areas=$(printf '%s' "$pending_areas" | sed 's/ /, /g')
    {
        echo "品質ゲート未実行の変更があります: $areas"
        echo "完了報告の前に、該当領域の verify(/verify-all)を実行してください。実行不要な理由がある場合はその旨を報告に含めてください。"
        echo "所有者に問いを出して答えを待っているときは、この返事の最後に、問いをもう一度全部書いてください。何について決めるのか、選べる答え、あなたの推奨を書き、答えを促すだけの文で済ませないでください。"
    } >&2
    exit 2
fi

exit 0
