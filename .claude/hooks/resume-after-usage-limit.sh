#!/bin/bash
# =====================================================================
# StopFailure / Stop hook(asyncRewake): 使う量の上限が戻ったら会話を再開させる
#
# 上限が戻る時刻まで背景で待ち、終了コード2で Claude を起こす(標準エラーの文が Claude に届く)。
# - StopFailure(error が rate_limit): Claude 自身が上限で断られた。上限の文は last_assistant_message にある
# - Stop: 子の Claude や補助役が上限に当たり、Claude が返答を終えた。上限の文は最後の返答の
#   道具の結果と知らせにある。最後の返答の文が「上限」か limit を含むときだけ扱う
# 上限の文の形(https://code.claude.com/docs/en/errors)は「You've hit your session limit · resets 3:45pm」
# 「You've hit your weekly limit · resets Mon 12:00am」。時刻はフックが動く PC の時刻の帯で読む。
# 起こす前に、会話が進んだ(所有者が話しかけた、Claude Code や Desktop が自分で続けた)かを会話の記録で
# 確かめ、進んでいれば何もしない。返答が終わるたびに待ち始めても、先に待ち始めたものは、あとの返答で
# 会話が進んだと見て起こさないので、ほかの Stop フックが返答を止めたとき(stop_hook_active)も同じに扱う。
# 所有者の1つの指示のあとに3回起こしたら、それ以上は起こさない。待つ時間の上限は settings.json の timeout。
# 前提: bash と perl(JSON::PP、Time::Local)。jqには依存しない。Windowsでは Git for Windows が提供する。
# =====================================================================
set -u

MARKER='[resume-after-usage-limit]'
MAX_WAKES=3
# 試験のための環境変数: 上限が戻ってから起こすまでの秒、記録の行数を数える前に待つ秒、時刻を見直す間隔の秒。
# ほかに RESUME_AFTER_LIMIT_NOW(時刻を読むときの「いま」の UNIX 秒)と RESUME_AFTER_LIMIT_DRY_RUN=1(待つ秒を出して終える)
margin=${RESUME_AFTER_LIMIT_MARGIN:-180}
settle=${RESUME_AFTER_LIMIT_SETTLE:-10}
poll=${RESUME_AFTER_LIMIT_POLL:-30}

payload=$(cat)

extract() {
    printf '%s' "$payload" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d;
        my $v = $d->{$ARGV[0]};
        if (defined $v && JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
        elsif (defined $v && !ref $v) { binmode STDOUT, ":utf8"; print $v }
    ' -- "$1" 2>/dev/null
}

event=$(extract hook_event_name)
transcript=$(extract transcript_path)
transcript=${transcript//\\//}
last_message=$(extract last_assistant_message)

# 上限の文を探す。StopFailure は入力の文、Stop は最後の返答の道具の結果と知らせ
case "$event" in
    StopFailure)
        [ "$(extract error)" = "rate_limit" ] || exit 0
        limit_text=$last_message
        ;;
    Stop)
        printf '%s' "$last_message" | grep -qiE '上限|limit' || exit 0
        [ -f "$transcript" ] || exit 0
        limit_text=$(perl -MJSON::PP -e '
            binmode STDOUT, ":utf8";
            my @rows;
            while (my $line = <STDIN>) {
                my $d = eval { JSON::PP::decode_json($line) } or next;
                push @rows, $d if ($d->{type} // "") eq "user";
            }
            # 最後の返答の始まり: 道具の結果でない、補足(isMeta)でもない user の行
            my $start = 0;
            for my $i (0 .. $#rows) {
                my $c = $rows[$i]{message}{content};
                next if $rows[$i]{isMeta};
                next if ref $c eq "ARRAY" && grep { ref $_ && ($_->{type} // "") eq "tool_result" } @$c;
                $start = $i;
            }
            sub texts {
                my ($c) = @_;
                return ($c) unless ref $c;
                return map { texts($_) } @$c if ref $c eq "ARRAY";
                return (texts($c->{content} // ""), ($c->{text} // ()));
            }
            exit 0 unless @rows;
            # 返答の始まりの行は、知らせ(補助役の終わりなど)のときだけ読む。所有者の指示の文は読まない
            my $first = $rows[$start]{message}{content};
            $start++ unless !ref $first && $first =~ /^\s*<task-notification>/;
            print join("\n", map { texts($_->{message}{content}) } @rows[$start .. $#rows]);
        ' <"$transcript" 2>/dev/null)
        ;;
    *) exit 0 ;;
esac

# 上限が戻る時刻を読み、起こすまでの秒を出す。読めなければ何も出さない
delay=$(LIMIT_TEXT="$limit_text" perl -MTime::Local -e '
    use utf8;
    my $text = $ENV{LIMIT_TEXT} // "";
    utf8::decode($text);
    my $now = $ENV{RESUME_AFTER_LIMIT_NOW} || time;
    my $margin = $ARGV[0];
    my @hits = $text =~ /hit your (?:session|weekly|Opus|Sonnet) limit\s*\x{b7}\s*resets\s+([^\n(\\"]+)/gi;
    exit 0 unless @hits;
    my $when = $hits[-1];
    $when =~ s/\s+$//;
    my %mon = (jan=>0, feb=>1, mar=>2, apr=>3, may=>4, jun=>5, jul=>6, aug=>7, sep=>8, oct=>9, nov=>10, dec=>11);
    my %wday = (sun=>0, mon=>1, tue=>2, wed=>3, thu=>4, fri=>5, sat=>6);
    my ($m, $d, $wd);
    if ($when =~ /^([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(?:at\s+)?(.+)$/i && exists $mon{lc $1}) { ($m, $d, $when) = ($mon{lc $1}, $2, $3) }
    elsif ($when =~ /^([A-Za-z]{3})[a-z]*,?\s+(?:at\s+)?(.+)$/i && exists $wday{lc $1}) { ($wd, $when) = ($wday{lc $1}, $2) }
    $when =~ /^(\d{1,2})(?::(\d{2}))?\s*([ap]m)?$/i or exit 0;
    my ($h, $min, $ap) = ($1, $2 // 0, lc($3 // ""));
    $h = 0 if $ap eq "am" && $h == 12;
    $h += 12 if $ap eq "pm" && $h < 12;
    exit 0 if $h > 23 || $min > 59;
    my @lt = localtime($now);
    my $reset;
    if (defined $m) {
        $reset = eval { timelocal(0, $min, $h, $d, $m, $lt[5] + 1900) } // exit 0;
        $reset = eval { timelocal(0, $min, $h, $d, $m, $lt[5] + 1901) } // exit 0 if $reset < $now - 3600;
    } else {
        $reset = timelocal(0, $min, $h, $lt[3], $lt[4], $lt[5] + 1900);
        if (defined $wd) {
            $reset += 86400 * (($wd - $lt[6]) % 7);
            $reset += 7 * 86400 if $reset < $now - 3600;
        } elsif ($reset < $now - 3600) {
            $reset += 86400;
        }
    }
    # 戻る時刻を過ぎたばかり(1時間以内)なら、すぐには起こさず、余白の秒だけ待つ
    my $wake = $reset + $margin;
    print $wake > $now ? $wake - $now : $margin;
' -- "$margin" 2>/dev/null)

case "$delay" in
    '' | *[!0-9]*) exit 0 ;;
esac
[ "${RESUME_AFTER_LIMIT_DRY_RUN:-}" = 1 ] && { printf '%s\n' "$delay"; exit 0; }

# 止まった時点の記録の行数を控える(止まった返答の行が書き終わるのを待ってから数える)
sleep "$settle"
start_lines=0
[ -f "$transcript" ] && start_lines=$(wc -l <"$transcript" | tr -d ' ')

deadline=$(($(date +%s) + delay))
while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep "$poll"
done

if [ -f "$transcript" ]; then
    # 控えた行より後に user の行か、上限の失敗でない assistant の行があれば、会話が進んだので起こさない
    progressed=$(perl -MJSON::PP -e '
        my ($skip) = @ARGV; my $n = 0; my $hit = 0;
        while (my $line = <STDIN>) {
            next if ++$n <= $skip;
            my $d = eval { JSON::PP::decode_json($line) } or next;
            my $t = $d->{type} // "";
            $hit = 1 if $t eq "user" || ($t eq "assistant" && !$d->{isApiErrorMessage});
        }
        print $hit;
    ' -- "$start_lines" <"$transcript" 2>/dev/null)
    [ "$progressed" = 1 ] && exit 0

    # 所有者の最後の指示のあとに、このフックが何回起こしたかを数える
    wakes=$(perl -MJSON::PP -e '
        my ($marker) = @ARGV; my $count = 0;
        while (my $line = <STDIN>) {
            my $d = eval { JSON::PP::decode_json($line) } or next;
            next unless ($d->{type} // "") eq "user" && !$d->{isMeta};
            my $c = $d->{message}{content};
            if (ref $c eq "ARRAY") {
                next if grep { ref $_ && ($_->{type} // "") eq "tool_result" } @$c;
                $c = join "\n", map { ref $_ ? ($_->{text} // "") : $_ } @$c;
            }
            next if ref $c;
            if (index($c, $marker) >= 0) { $count++ }
            elsif ($c !~ /^\s*<task-notification>/) { $count = 0 }
        }
        print $count;
    ' -- "$MARKER" <"$transcript" 2>/dev/null)
    [ "${wakes:-0}" -ge "$MAX_WAKES" ] && exit 0
fi

{
    echo "$MARKER 使う量の上限が戻る時刻を過ぎました。上限で止まったところから作業を続けてください。"
    echo "上限で止まっていなかったとき、または続ける作業が無いときは、何もせずに返答を終えてください。"
} >&2
exit 2
