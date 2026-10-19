#!/bin/bash
# =====================================================================
# PreToolUse(Edit|Write|NotebookEdit) hook: /start の判断の報告を書く前に、ファイルを書き換えさせない
#
# /start で spec が要らず問いも無いと判断したとき、AIは所有者の返事を待たずに実装を始める。
# その前に Step 6 の書式の報告(「## 判断」と「## 理由」の表)をチャットに書く決まりだが、
# 小さなIssueでは、報告を書かずに書き換えを始めることが続いた(#577)。
# このフックは、/start を受けてから所有者が次に何か言うまでの間に、
# 報告をまだ書いていないまま作業フォルダの中のファイルを書き換えようとしたら、止めて(exit 2)理由を返す。
#
# 見分け方(会話の記録 transcript_path を頭から読む):
#   - 利用者の行に <command-name>/start</command-name> がある、または AIが Skill で start を呼んだら、見張りを始める
#   - 見張りの間に、AIの文に「## 判断」と「## 理由」の見出しが出たら、報告を書いたとみなす
#   - 所有者が次に何か言ったら(問いの答え、次のコマンドなど)、見張りを終える
# 次のときは、そのまま通す。
#   - 作業フォルダ(CLAUDE_PROJECT_DIR か入力の cwd)の外のファイル(scratchpad など)
#   - サブエージェントの書き換え(入力に agent_id があるとき)
#   - 会話の記録を読めないとき
# フックの入力の欄は https://code.claude.com/docs/en/hooks の「Common input fields」と PreToolUse の節による。
#
# 前提: bash と perl(JSON::PP)。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
# =====================================================================
set -u

payload=$(cat)

printf '%s' "$payload" | perl -MJSON::PP -e '
    use strict;
    use warnings;
    use utf8;
    my $d = eval { JSON::PP->new->utf8->decode(do { local $/; <STDIN> }) };
    exit 0 unless ref $d eq "HASH";
    exit 0 if defined $d->{agent_id};

    my $norm = sub {
        my $p = shift;
        $p =~ s{\\}{/}g;
        $p =~ s{^/([a-zA-Z])/}{$1:/};
        $p =~ s{/+$}{};
        return lc $p;
    };
    my $ti = ref $d->{tool_input} eq "HASH" ? $d->{tool_input} : {};
    my $file = $ti->{file_path} // $ti->{notebook_path};
    exit 0 unless defined $file && !ref $file && length $file;
    $file = $norm->($file);
    my $inside = 0;
    for my $root ($ENV{CLAUDE_PROJECT_DIR}, $d->{cwd}) {
        next unless defined $root && !ref $root && length $root;
        my $r = $norm->($root);
        $inside = 1 if $file eq $r || index($file, "$r/") == 0;
    }
    exit 0 unless $inside;

    my $tp = $d->{transcript_path};
    exit 0 unless defined $tp && !ref $tp && length $tp;
    open(my $fh, "<:raw", $tp) or exit 0;
    my $json = JSON::PP->new->utf8;
    my ($watch, $judged, $reasoned) = (0, 0, 0);
    while (my $line = <$fh>) {
        # 記録は1行1件の詰めた JSON。関わりの無い行(ツールの結果、文の無いツールの呼び出し)は、
        # 読み解かずに飛ばす。大きな記録でも、ファイルを書き換えるたびに待たせないためである
        if (index($line, q{"type":"assistant"}) >= 0) {
            next unless index($line, q{"type":"text"}) >= 0 || index($line, q{"name":"Skill"}) >= 0;
        } elsif (index($line, q{"type":"user"}) >= 0) {
            next if index($line, q{"isMeta":true}) >= 0;
            next if index($line, q{"tool_result"}) >= 0
                && index($line, "<command-name>/start</command-name>") < 0;
        } else {
            next;
        }
        my $j = eval { $json->decode($line) };
        next unless ref $j eq "HASH";
        my $type = $j->{type} // "";
        my $c = ref $j->{message} eq "HASH" ? $j->{message}{content} : undef;
        if ($type eq "user") {
            next if $j->{isMeta};
            my $text;
            if (defined $c && !ref $c) {
                $text = $c;
            } elsif (ref $c eq "ARRAY") {
                my @t = map { $_->{text} // "" }
                    grep { ref $_ eq "HASH" && ($_->{type} // "") eq "text" } @$c;
                $text = join("\n", @t) if @t;
            }
            next unless defined $text && length $text;
            if (index($text, "<command-name>/start</command-name>") >= 0) {
                ($watch, $judged, $reasoned) = (1, 0, 0);
            } else {
                $watch = 0;
            }
        } elsif ($type eq "assistant" && ref $c eq "ARRAY") {
            for my $b (@$c) {
                next unless ref $b eq "HASH";
                my $bt = $b->{type} // "";
                if ($bt eq "tool_use" && ($b->{name} // "") eq "Skill"
                    && ref $b->{input} eq "HASH" && ($b->{input}{skill} // "") eq "start") {
                    ($watch, $judged, $reasoned) = (1, 0, 0);
                } elsif ($bt eq "text" && $watch) {
                    my $t = $b->{text} // "";
                    $judged = 1 if $t =~ /^#{1,3}\s*判断/m;
                    $reasoned = 1 if $t =~ /^#{1,3}\s*理由/m;
                }
            }
        }
    }
    close $fh;
    exit 0 unless $watch && !($judged && $reasoned);
    binmode STDERR, ":encoding(UTF-8)";
    print STDERR "/start の判断の報告が、所有者に見える返答の本文にまだありません。\n";
    print STDERR "ファイルを書き換える前に、.claude/skills/start/SKILL.md の Step 6 の書式の報告(「## してほしいこと」「## 判断」「## 理由」の表)を、省かずに返答の本文に書いてください。\n";
    print STDERR "考え(thinking)の中に書いた報告は、所有者に見えず、会話の記録にも残らないので、書いたことになりません。ツールを呼ぶ前に、所有者に見える文として出してください。\n";
    print STDERR "所有者は、この報告を読んで判断の誤りに気づき、実装を止めます。1文の知らせや、実装を終えたあとの報告は、この報告の代わりになりません。\n";
    exit 2;
'
