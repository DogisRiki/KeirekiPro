#!/bin/bash
# =====================================================================
# restore-after-compact.sh(圧縮の直後に作業の状態を差し込むフック)のテスト
#
# 実行: bash .claude/hooks/tests/test-restore-after-compact.sh
# 一時的な git のリポジトリを作り、spec.json・reviews/ の記録・tasks.md・並行作業の Issue の記録を置き、
# フックの入力の cwd にそのフォルダを渡して、標準出力と終了コードを確かめる。
# 本物のリポジトリの記録(.git/keirekipro-parallel)と git の設定には触れない。
# 設定と文書のテストは、このテストの場所から決めたリポジトリの最上位の .claude/settings.json・CLAUDE.md・
# .claude/skills/spec-review/SKILL.md・.claude/agents/spec-reviewer.md を読む(書き換えない)。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash からも Linux からも流せる。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR KP_SESSION_ID

HOOK="$(cd "$(dirname "$0")/.." && pwd)/restore-after-compact.sh"
TOP="$(cd "$(dirname "$0")/../../.." && pwd)"
SETTINGS="$TOP/.claude/settings.json"
CLAUDE_MD="$TOP/CLAUDE.md"
SPEC_REVIEW_SKILL="$TOP/.claude/skills/spec-review/SKILL.md"
SPEC_REVIEWER="$TOP/.claude/agents/spec-reviewer.md"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

GITC=(-c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
REPO_DIR="$WORK/Repo"
OUTSIDE_DIR="$WORK/outside"
REPO=""
STATE=""

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

# 一時的なリポジトリを作り直す。main に古い spec を1つ置き、origin/main をそこに向けてから、
# ブランチ feat/sample を開く
reset_repo() {
    rm -rf "$REPO_DIR" "$OUTSIDE_DIR"
    mkdir -p "$OUTSIDE_DIR"
    git init -q "$REPO_DIR"
    git -C "$REPO_DIR" checkout -q -B main
    mkdir -p "$REPO_DIR/.kiro/specs/old-spec"
    write_spec_json old-spec 700 '[]' tasks-generated
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" "${GITC[@]}" commit -q -m seed
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD
    git -C "$REPO_DIR" checkout -q -b feat/sample
    REPO=$(git -C "$REPO_DIR" rev-parse --show-toplevel)
    STATE="$(git -C "$REPO_DIR" rev-parse --path-format=absolute --git-common-dir)/keirekipro-parallel"
}

commit_all() {
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" "${GITC[@]}" commit -q -m change
}

# spec.json を書く
write_spec_json() { # <feature> <issue> <additional_issues の JSON> <phase> [<review_model>]
    mkdir -p "$REPO_DIR/.kiro/specs/$1"
    perl -MJSON::PP -e '
        my ($file, $feature, $issue, $add, $phase, $model) = @ARGV;
        my $d = {
            feature_name => $feature,
            issue => 0 + $issue,
            additional_issues => JSON::PP->new->decode($add),
            language => "ja",
            phase => $phase,
            approvals => {
                requirements => { generated => JSON::PP::true, approved => JSON::PP::true },
                design => { generated => JSON::PP::true, approved => JSON::PP::false },
                tasks => { generated => JSON::PP::false, approved => JSON::PP::false },
            },
        };
        $d->{review_model} = $model if defined $model && length $model;
        open my $fh, ">:raw", $file or die "書けない: $file\n";
        print $fh JSON::PP->new->utf8->canonical->pretty->encode($d);
    ' -- "$REPO_DIR/.kiro/specs/$1/spec.json" "$1" "$2" "$3" "$4" "${5:-}"
}

# 審査の記録を置く。requirements は往復2で収束し対応も書いた。design は往復1の審査だけで、対応がまだ無い
write_reviews() { # <feature>
    local d="$REPO_DIR/.kiro/specs/$1/reviews"
    mkdir -p "$d"
    cat >"$d/requirements-review.md" <<'EOF'
# requirements のレビュー記録

## サイクル1 往復1(2026-10-17)

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| R1-1-1 | 中 | 要件1 | 内容 | 案 |

- 往復: 1回目 / 高0 中1 低0

## サイクル1 往復2(2026-10-17)

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| (なし) | | | | |

- 往復: 2回で収束 / 未解決: 0件
EOF
    cat >"$d/requirements-response.md" <<'EOF'
# requirements の指摘への対応

## サイクル1 往復1 への対応(2026-10-17)

| ID | 処置 | 内容 |
|---|---|---|
| R1-1-1 | 修正 | 直した |

## サイクル1 往復2 への対応(2026-10-17)

| ID | 処置 | 内容 |
|---|---|---|
EOF
    cat >"$d/design-review.md" <<'EOF'
# design のレビュー記録

## サイクル1 往復1(2026-10-17)

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 高 | 部品 | 内容 | 案 |

- 往復: 1回目 / 高1 中0 低0
EOF
}

write_tasks() { # <feature>
    cat >"$REPO_DIR/.kiro/specs/$1/tasks.md" <<'EOF'
# タスク

- [x] 1. 一つ目
- [x] 1.1 一つ目の中
- [ ] 2. 二つ目
  - [ ] 2.1 二つ目の中
- [ ] 3. 三つ目
EOF
}

# 並行作業の Issue の記録を置く
write_issue_record() { # <N> <作業フォルダ>
    mkdir -p "$STATE/issues"
    perl -MJSON::PP -e '
        my ($file, $n, $folder) = @ARGV;
        open my $fh, ">:raw", $file or die "書けない: $file\n";
        print $fh JSON::PP->new->utf8->canonical->encode({
            issue => 0 + $n, folder => $folder, branch => "feat/sample", session_id => "s-1",
            updated_at => 1700000000, handed_over_from => [],
        }), "\n";
    ' -- "$STATE/issues/$1.json" "$1" "$2"
}

write_session_record() { # <session_id> <作業フォルダ>
    mkdir -p "$STATE/sessions"
    perl -MJSON::PP -e '
        my ($file, $sid, $folder) = @ARGV;
        open my $fh, ">:raw", $file or die "書けない: $file\n";
        print $fh JSON::PP->new->utf8->canonical->encode({
            session_id => $sid, folder => $folder, folder_key => "abc", started_at => 1700000000,
            last_seen => 1700000000, responding => JSON::PP::false,
        }), "\n";
    ' -- "$STATE/sessions/$1.json" "$1" "$2"
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    reset_repo
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# フックの入力の JSON を作る
payload() { # <source> <cwd> [<追加のキー> <値>]...
    perl -MJSON::PP -e '
        my ($src, $cwd, @rest) = @ARGV;
        my %d = (hook_event_name => "SessionStart", session_id => "s-1", cwd => $cwd,
                 transcript_path => "/tmp/transcript.jsonl", source => $src);
        while (@rest) { my $k = shift @rest; $d{$k} = shift @rest; }
        print JSON::PP->new->canonical->encode(\%d);
    ' -- "$@"
}

# フックを呼ぶ。標準出力を $OUT、終了コードを $RC、additionalContext を $CTX に入れる
call_hook() { # <source> <cwd> [<追加のキー> <値>]...
    OUT=$(payload "$@" | bash "$HOOK" 2>"$WORK/stderr.txt")
    RC=$?
    CTX=$(printf '%s' "$OUT" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP->new->utf8->decode(<STDIN>) };
        exit 0 unless ref $d eq "HASH";
        my $c = $d->{hookSpecificOutput}{additionalContext} // "";
        utf8::encode($c); print $c;
    ' 2>/dev/null)
}

expect_rc0() {
    [ "$RC" = 0 ] || die "終了コードが0でない: $RC($(cat "$WORK/stderr.txt"))"
}

expect_silent() { # <場面>
    expect_rc0
    [ -z "$OUT" ] || die "$1 で何かを出している: $OUT"
}

expect_line() { # <固定文字列> <場面>
    printf '%s\n' "$CTX" | grep -qF -- "$1" || die "$2 が出ていない(「$1」が無い):
$CTX"
}

expect_no_line() { # <固定文字列> <場面>
    if printf '%s\n' "$CTX" | grep -qF -- "$1"; then
        die "$2 が出ている(「$1」がある):
$CTX"
    fi
}

# 1つの行に、すべての固定文字列が入っているか
expect_line_with() { # <場面> <固定文字列>...
    local what="$1" line ok
    shift
    while IFS= read -r line; do
        ok=1
        for s in "$@"; do
            case "$line" in
                *"$s"*) ;;
                *) ok=0 ;;
            esac
        done
        [ "$ok" = 1 ] && return 0
    done <<<"$CTX"
    die "$what が出ていない($* を含む行が無い):
$CTX"
}

# 記録の置き場所の sessions/ と issues/ の中身を1つの文字列にまとめる(名前と中身)
snapshot_state() {
    perl -e '
        my $dir = shift;
        for my $sub (qw(sessions issues)) {
            opendir my $dh, "$dir/$sub" or next;
            for my $name (sort grep { !/\A\.\.?\z/ } readdir $dh) {
                open my $fh, "<:raw", "$dir/$sub/$name" or next;
                local $/; my $text = <$fh>; close $fh;
                my @s = stat "$dir/$sub/$name";
                print "$sub/$name\t$s[9]\n$text\n";
            }
        }
    ' -- "$STATE"
}

# 典型の場面: Issue #901 の記録があり、spec sample-spec がその Issue のもの
setup_typical() {
    write_spec_json sample-spec 901 '[]' design-generated opus
    write_reviews sample-spec
    write_tasks sample-spec
    write_spec_json other-spec 902 '[]' requirements-generated
    write_spec_json reopened-spec 800 '[901]' tasks-generated
    commit_all
    write_issue_record 901 "$REPO"
    write_issue_record 902 "$WORK/elsewhere"
}

# ---------------------------------------------------------------------

t_compact_outputs_state() {
    local ev first
    setup_typical
    call_hook compact "$REPO"
    expect_rc0
    ev=$(printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; my $d = JSON::PP->new->utf8->decode(<STDIN>); print $d->{hookSpecificOutput}{hookEventName}') \
        || die "標準出力が JSON でない: $OUT"
    [ "$ev" = SessionStart ] || die "hookEventName が SessionStart でない: $OUT"
    first=$(printf '%s\n' "$CTX" | head -n 1)
    [ "$first" = "[compact] 会話が要約された。ファイルから読み直した作業の状態は次のとおり。" ] \
        || die "1行目が決まりの文でない: $first"
    expect_line_with "作業フォルダ" "作業フォルダ" "$REPO"
    expect_line_with "ブランチ" "ブランチ" "feat/sample"
    expect_line_with "Issue の番号" "Issue" "#901"
    expect_no_line "#902" "ほかの作業フォルダの Issue"
    expect_line_with "spec の名前と段階" "sample-spec" "phase" "design-generated"
    expect_line_with "審査役のモデル" "sample-spec" "review_model" "opus"
    expect_line_with "requirements の承認" "sample-spec" "requirements" "generated=true" "approved=true"
    expect_line_with "design の承認" "sample-spec" "design" "generated=true" "approved=false"
    expect_line_with "requirements の審査の最後の往復と対応の有無" "sample-spec" "requirements" "サイクル1 往復2" "対応の記録: あり"
    expect_line_with "requirements の審査の最終行" "sample-spec" "requirements" "- 往復: 2回で収束 / 未解決: 0件"
    expect_line_with "design の審査の最後の往復と対応の有無" "sample-spec" "design" "サイクル1 往復1" "対応の記録: なし"
    expect_line_with "tasks の審査の記録が無いこと" "sample-spec" "tasks" "審査の記録は無い"
    expect_line_with "タスクの完了の数" "sample-spec" "tasks.md" "完了 2" "未完了 3"
    expect_line_with "additional_issues に Issue を含む spec" "reopened-spec" "phase" "tasks-generated"
    expect_no_line "other-spec" "ほかの Issue の spec"
    expect_no_line "old-spec" "Issue に関係しない spec"
}

t_rules_in_output() {
    setup_typical
    call_hook compact "$REPO"
    expect_rc0
    expect_line_with "スキルの SKILL.md を読み直す決まり" "実行中のスキル" ".claude/skills/<名前>/SKILL.md" "Read" "全文読み直して"
    expect_line_with "所有者に尋ね直さない決まり" "所有者に尋ね直さない"
    expect_line_with "ファイルの状態を正とする決まり" "食い違う" "ファイルの状態)を正とする"
    expect_line_with "/spec-review の決め直しの節を指す決まり" "/spec-review" "会話が要約されたあとに続けるとき"
}

t_no_issue_record_uses_branch_changes() {
    # コミットした spec と、コミットしていない新しい spec。old-spec は main にあり、ブランチでは変えていない
    write_spec_json branch-spec 950 '[]' requirements-generated
    write_tasks branch-spec
    commit_all
    write_spec_json uncommitted-spec 951 '[]' initialized
    call_hook compact "$REPO"
    expect_rc0
    expect_line_with "Issue の記録が無いことを飛ばした行" "Issue の記録" "飛ばした"
    expect_line_with "ブランチで変えた spec" "branch-spec" "phase" "requirements-generated"
    expect_line_with "コミットしていない spec" "uncommitted-spec" "phase" "initialized"
    expect_line_with "ブランチで変えた spec のタスクの数" "branch-spec" "tasks.md" "完了 2" "未完了 3"
    expect_no_line "old-spec" "ブランチで変えていない spec"
    # 下のフォルダから呼ばれても、絞り込みのパスを最上位から解く
    mkdir -p "$REPO_DIR/sub/dir"
    call_hook compact "$REPO/sub/dir"
    expect_rc0
    expect_line_with "下のフォルダから呼んだときのブランチで変えた spec" "branch-spec" "phase" "requirements-generated"
    expect_line_with "下のフォルダから呼んだときのコミットしていない spec" "uncommitted-spec" "phase" "initialized"
}

t_no_origin_main_skips_branch_changes() {
    write_spec_json branch-spec 950 '[]' requirements-generated
    commit_all
    git -C "$REPO_DIR" update-ref -d refs/remotes/origin/main
    call_hook compact "$REPO"
    expect_rc0
    expect_line_with "origin/main が無いことを飛ばした行" "origin/main" "飛ばした"
}

t_startup_outputs_nothing() {
    setup_typical
    call_hook startup "$REPO"
    expect_silent "source が startup のとき"
    call_hook resume "$REPO"
    expect_silent "source が resume のとき"
    call_hook "" "$REPO"
    expect_silent "source が空のとき"
}

t_outside_git_outputs_nothing() {
    call_hook compact "$OUTSIDE_DIR"
    expect_silent "git のリポジトリの外"
    call_hook compact "$WORK/no-such-dir"
    expect_silent "無いフォルダ"
    OUT=$(printf 'not json' | bash "$HOOK" 2>"$WORK/stderr.txt")
    RC=$?
    expect_silent "JSON でない入力"
}

t_broken_spec_json() {
    setup_typical
    printf '{ "issue": 901, broken' >"$REPO_DIR/.kiro/specs/sample-spec/spec.json"
    call_hook compact "$REPO"
    expect_rc0
    [ -n "$CTX" ] || die "spec.json が壊れているときに何も出していない: $OUT"
    expect_line_with "壊れた spec.json を飛ばした行" ".kiro/specs/sample-spec/spec.json" "飛ばした"
    [ "$(printf '%s\n' "$CTX" | grep -cF 'sample-spec')" = 1 ] \
        || die "壊れた spec について飛ばしたことの1行のほかにも出ている:
$CTX"
    expect_line_with "壊れていない spec" "reopened-spec" "phase" "tasks-generated"
}

t_agent_id_outputs_nothing() {
    setup_typical
    call_hook compact "$REPO" agent_id agent-123 agent_type general-purpose
    expect_silent "入力に agent_id があるとき"
}

t_state_records_unchanged() {
    local before after
    setup_typical
    write_session_record s-1 "$REPO"
    write_session_record s-2 "$WORK/elsewhere"
    before=$(snapshot_state)
    [ -n "$before" ] || die "記録の置き場所の写しが空: $STATE"
    sleep 1
    call_hook compact "$REPO"
    expect_rc0
    after=$(snapshot_state)
    [ "$before" = "$after" ] || die "sessions/ か issues/ が書き換わった:
--- 前
$before
--- 後
$after"
    # 記録の置き場所に新しいものを作っていない
    [ "$(find "$STATE" | sort)" = "$(printf '%s\n' "$STATE" "$STATE/issues" "$STATE/issues/901.json" \
        "$STATE/issues/902.json" "$STATE/sessions" "$STATE/sessions/s-1.json" "$STATE/sessions/s-2.json" | sort)" ] \
        || die "記録の置き場所に新しいものができた: $(find "$STATE")"
}

t_subdir_cwd() {
    setup_typical
    mkdir -p "$REPO_DIR/sub/dir"
    call_hook compact "$REPO/sub/dir"
    expect_rc0
    expect_line_with "下のディレクトリから呼んでも Issue の番号" "Issue" "#901"
    expect_line_with "下のディレクトリから呼んでも spec" "sample-spec" "phase"
}

# ---------------------------------------------------------------------
# 設定と文書のテスト。リポジトリの最上位のファイルを読むだけで、書き換えない

# settings.json を JSON::PP で読み、<確かめること> の問題を1行ずつ出す。問題が無ければ何も出さない
settings_problems() { # <window|session_start|no_model>
    perl -MJSON::PP -e '
        my ($file, $mode) = @ARGV;
        open my $fh, "<:raw", $file or do { print "settings.json が読めない: $file\n"; exit 0 };
        local $/; my $text = <$fh>; close $fh;
        my $s = eval { JSON::PP->new->utf8->decode($text) };
        unless (ref $s eq "HASH") { print "settings.json が JSON のオブジェクトとして読めない: $file\n"; exit 0 }
        if ($mode eq "window") {
            my $env = $s->{env};
            unless (ref $env eq "HASH" && exists $env->{CLAUDE_CODE_AUTO_COMPACT_WINDOW}) {
                print "env に CLAUDE_CODE_AUTO_COMPACT_WINDOW が無い\n"; exit 0;
            }
            my $enc = JSON::PP->new->allow_nonref->encode($env->{CLAUDE_CODE_AUTO_COMPACT_WINDOW});
            print "env の CLAUDE_CODE_AUTO_COMPACT_WINDOW が文字列の \"250000\" でない: $enc\n"
                unless $enc eq q{"250000"};
        } elsif ($mode eq "session_start") {
            my $hooks = $s->{hooks};
            my $ss = ref $hooks eq "HASH" ? $hooks->{SessionStart} : undef;
            unless (ref $ss eq "ARRAY") { print "hooks.SessionStart が配列でない\n"; exit 0 }
            my $want_compact = q{bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/restore-after-compact.sh"};
            my $want_registry = q{bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/session-registry.sh"};
            my ($compact, $registry) = (0, 0);
            for my $e (@$ss) {
                next unless ref $e eq "HASH" && ref $e->{hooks} eq "ARRAY";
                for my $h (@{ $e->{hooks} }) {
                    next unless ref $h eq "HASH" && ($h->{type} // "") eq "command";
                    my $c = $h->{command} // "";
                    $compact++ if defined $e->{matcher} && $e->{matcher} eq "compact"
                        && $c eq $want_compact && ($h->{timeout} // 0) == 10;
                    $registry++ if !exists $e->{matcher} && $c eq $want_registry;
                }
            }
            print "SessionStart に、matcher compact で restore-after-compact.sh を timeout 10 で呼ぶ項目が1つでない($compact 個)\n"
                unless $compact == 1;
            print "SessionStart に、matcher の無い session-registry.sh の項目が無い\n" unless $registry >= 1;
        } elsif ($mode eq "no_model") {
            for my $k (qw(model effortLevel)) {
                print "settings.json に $k のキーがある\n" if exists $s->{$k};
            }
        } else {
            print "確かめることの名前が違う: $mode\n";
        }
    ' -- "$SETTINGS" "$1"
}

# 文書を読み、<確かめること> の問題を1行ずつ出す。問題が無ければ何も出さない
#   heading <ファイル> <見出しの行>: frontmatter のあとの本文に、その行がそのままある
#   model <ファイル> <model の値>: frontmatter の model の行が「model: <値>」である
#   compact <ファイル> <項目>...: 「# Compact instructions」の節に、項目ごとに、| で区切った言葉をすべて含む
#     「- 」の行がある。「- 」の行の数が項目の数と同じ。項目が「=」で始まるときは、節のどこかにその言葉がある
doc_problems() { # <heading|model|compact> <ファイル> <引数>...
    perl -e '
        my ($mode, $file, @args) = @ARGV;
        open my $fh, "<:raw", $file or do { print "読めない: $file\n"; exit 0 };
        my @lines = map { s/\r?\n\z//r } <$fh>;
        close $fh;
        my (@front, @body);
        if (@lines && $lines[0] eq "---") {
            my $i = 1;
            $i++ while $i < @lines && $lines[$i] ne "---";
            @front = @lines[1 .. $i - 1];
            @body = @lines[$i + 1 .. $#lines];
        } else {
            @body = @lines;
        }
        if ($mode eq "heading") {
            print "本文に見出し「$args[0]」が無い: $file\n" unless grep { $_ eq $args[0] } @body;
        } elsif ($mode eq "model") {
            my @m = grep { /\Amodel:/ } @front;
            print "frontmatter の model の行が「model: $args[0]」でない: @m\n"
                unless @m == 1 && $m[0] eq "model: $args[0]";
        } elsif ($mode eq "compact") {
            my ($in, @sec) = (0);
            for (@body) {
                if ($_ eq "# Compact instructions") { $in = 1; next }
                last if $in && /\A# /;
                push @sec, $_ if $in;
            }
            unless ($in) { print "「# Compact instructions」の節が無い: $file\n"; exit 0 }
            my @bullets = grep { /\A- / } @sec;
            my $items = 0;
            for my $item (@args) {
                if ($item =~ /\A=(.*)\z/s) {
                    my $w = $1;
                    print "節に「$w」が無い\n" unless grep { index($_, $w) >= 0 } @sec;
                    next;
                }
                $items++;
                my @words = split /\|/, $item;
                my $hit = grep { my $l = $_; !grep { index($l, $_) < 0 } @words } @bullets;
                print "節に、「" . join("」「", @words) . "」をすべて含む「- 」の行が無い\n" unless $hit;
            }
            print "節の「- 」の行の数が " . scalar(@bullets) . " で、項目の数 $items と違う\n"
                unless @bullets == $items;
        } else {
            print "確かめることの名前が違う: $mode\n";
        }
    ' -- "$@"
}

expect_no_problems() { # <問題の出力>
    [ -z "$1" ] || die "$1"
}

t_settings_compact_window() {
    expect_no_problems "$(settings_problems window)"
}

t_settings_session_start() {
    expect_no_problems "$(settings_problems session_start)"
}

t_settings_no_model_keys() {
    expect_no_problems "$(settings_problems no_model)"
    expect_no_problems "$(doc_problems model "$SPEC_REVIEWER" claude-fable-5-1)"
}

t_claude_md_compact_instructions() {
    expect_no_problems "$(doc_problems compact "$CLAUDE_MD" \
        '実行中のスキルの名前|手順のどこにいるか|Step の番号' \
        'Issue の番号|spec の名前と段階|作業のブランチ|PR の番号' \
        '/spec-review|CYCLE|ROUND|CHANGED|受け入れた指摘|却下した指摘|直さなかった外れ|Opus 5.5' \
        '/kiro-impl|検査のコマンド一式|REJECTED|debug の補助役を動かした回数' \
        '/ship|同じ失敗が続いた回数' \
        '答えを待っている問いの全文|まだ Issue の本文か spec.json に書いていないもの' \
        '所有者が会話で伝えたこと|まだ作業に使っていないもの' \
        '補助役の会話なら|識別の欄の全部|FEATURE・STAGE・CYCLE・ROUND・REVIEW_FILE|判定' \
        '=要約のそれ以外の部分を短くする' \
        '=審査役・点検役・確認役に渡す材料(spec の本文、差分の全文)を要約で置き換えない')"
}

t_spec_review_resume_section() {
    expect_no_problems "$(doc_problems heading "$SPEC_REVIEW_SKILL" '### 会話が要約されたあとに続けるとき')"
}

t_spec_reviewer_compact_rule() {
    expect_no_problems "$(doc_problems heading "$SPEC_REVIEWER" '## 会話が要約されたとき')"
}

# ---------------------------------------------------------------------

echo "--- 圧縮のあとに作業の状態を差し込む(要件3.1・3.2・3.3)"
run_test "compact のとき、ブランチ・Issue の番号・spec の段階・審査の最後の往復と対応の有無・タスクの完了の数が出る" t_compact_outputs_state
run_test "Issue の記録が無いとき、ブランチで変えた spec が出る" t_no_issue_record_uses_branch_changes
run_test "出力に、実行中のスキルの SKILL.md を読み直す決まりと、ファイルの状態を正とする決まりと、/spec-review の決め直しの節を指す決まりと、所有者に尋ね直さない決まりが入る" t_rules_in_output
run_test "cwd が下のディレクトリでも、最上位を作業フォルダにする" t_subdir_cwd

echo "--- 所有者への問いを増やさない(要件5.4)"
run_test "並行作業の記録の sessions/ と issues/ が書き換わらない" t_state_records_unchanged

echo "--- 動かない場面と、作業を止めない"
run_test "source が startup のとき何も出さない" t_startup_outputs_nothing
run_test "入力に agent_id があるとき何も出さない" t_agent_id_outputs_nothing
run_test "git のリポジトリの外で何も出さない" t_outside_git_outputs_nothing
run_test "spec.json が壊れていても終了コード0で、飛ばしたことを1行書く" t_broken_spec_json
run_test "origin/main が無いとき、ブランチで変えた spec を飛ばしたことを書く" t_no_origin_main_skips_branch_changes

echo "--- 全員に同じく効く設定(要件1.1・2.1・2.2・2.3・4.1・5.1・5.2・5.3)"
run_test "settings.json の env の CLAUDE_CODE_AUTO_COMPACT_WINDOW が \"250000\"" t_settings_compact_window
run_test "SessionStart に matcher compact で restore-after-compact.sh を呼ぶ項目があり、matcher の無い session-registry.sh の項目が残っている" t_settings_session_start
run_test "settings.json に model と effortLevel のキーが無く、spec-reviewer.md の model が claude-fable-5-1 のまま" t_settings_no_model_keys

echo "--- 要約のあとに作業を続けるための文書(要件2.3・3.1・3.2・3.3・4.3)"
run_test "CLAUDE.md に # Compact instructions の節があり、8つの項目の言葉が入っている" t_claude_md_compact_instructions
run_test "spec-review の SKILL.md に「会話が要約されたあとに続けるとき」の節がある" t_spec_review_resume_section
run_test "spec-reviewer.md に要約されたときの決まりがある" t_spec_reviewer_compact_rule

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
