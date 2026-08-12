#!/bin/bash
# =====================================================================
# PostToolUse(Bash) hook: 品質ゲート実行の記録
#
# 品質ゲートコマンドの実行を領域別に記録する(Stop hookの検知材料)。
# 状態は .claude/.state/ 配下(gitignore済み)に epoch秒 で保存する。
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
        print $v if defined $v && !ref $v;
    ' -- "$@" 2>/dev/null
}

command=$(extract tool_input command)
[ -z "$command" ] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-}"
[ -z "$project_dir" ] && project_dir=$(extract cwd)
[ -z "$project_dir" ] && exit 0
project_dir=${project_dir//\\//}
[ -d "$project_dir" ] || exit 0

state_dir="$project_dir/.claude/.state"
mkdir -p "$state_dir" 2>/dev/null || exit 0

area=""
case "$command" in
    *"frontend pnpm run coverage"*) area="frontend" ;;
    *"backend ./gradlew check"*) area="backend" ;;
    *"terraform checkov"*) area="terraform" ;;
esac

if [ -n "$area" ]; then
    date +%s >"$state_dir/gate-run-$area.txt"
fi

exit 0
