#!/bin/bash
# =====================================================================
# UserPromptSubmit hook: 所有者に送る文の書き方の決まりの要点を渡す
#
# 所有者が入力するたびに、.kiro/settings/rules/owner-writing.md の「## 決まり」の節から、
# 「### 」の見出しと、見出しの直後の段落の1文目(最初の「。」まで)を抜き出して標準出力に書く。
# 標準出力は、Claude が読める文脈として追加される。決まりの本文と例はファイルを開いて読む。
#
# 出力は1万字までのため、抜き出した文が9千字を超えたら、超えた分の行を書かず、
# 残りをファイルで読むよう促す1行を最後に書く。字数はバイトではなく文字で数える。
#
# 決まりのファイルが無いとき、「## 決まり」の節が無いとき、節に見出しが1つも無いときは、
# 読めないことの1行だけを書く。どの場合も0で終わり、所有者の入力を止めない。
#
# 前提: bash と perl。jqには依存しない。
# =====================================================================
set -u

# 入力は読み捨てる(このフックは所有者の入力を判定に使わない)
cat >/dev/null 2>&1

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rules="$project_dir/.kiro/settings/rules/owner-writing.md"
unreadable='[writing] 書き方の決まりのファイル .kiro/settings/rules/owner-writing.md を読めない'

if [ ! -f "$rules" ]; then
    printf '%s\n' "$unreadable"
    exit 0
fi

perl -CSD -Mutf8 -e '
    my ($file) = @ARGV;
    my $limit = 9000;
    open my $fh, "<:encoding(UTF-8)", $file or exit 1;
    my @lines = map { s/\r?\n\z//r } <$fh>;
    close $fh;

    # 「## 決まり」の節の行だけを取り出す
    my ($in, $found, @section) = (0, 0);
    for (@lines) {
        if (/^## /) {
            last if $in;
            if ($_ eq "## 決まり") { $in = 1; $found = 1; next; }
        }
        push @section, $_ if $in;
    }
    exit 1 unless $found;

    # 見出しごとに、直後の段落の1文目を取り出す
    my @rules;
    for (my $i = 0; $i < @section; $i++) {
        next unless $section[$i] =~ /^### (.+)$/;
        my $name = $1;
        my $j = $i + 1;
        $j++ while $j < @section && $section[$j] =~ /^\s*$/;
        my $para = "";
        while ($j < @section && $section[$j] !~ /^\s*$/ && $section[$j] !~ /^#/) {
            $para .= $section[$j];
            $j++;
        }
        my ($first) = $para =~ /^(.*?。)/;
        $first = $para unless defined $first;
        push @rules, "- $name: $first";
    }
    exit 1 unless @rules;

    my $out = "[writing] 所有者に送る文は、次の決まりで書き、送る前に自分で読み直す。例は .kiro/settings/rules/owner-writing.md にある。\n";
    for my $line (@rules) {
        if (length($out) + length($line) + 1 > $limit) {
            $out .= "残りの決まりは owner-writing.md を開いて読む\n";
            last;
        }
        $out .= "$line\n";
    }
    print $out;
' "$rules" || printf '%s\n' "$unreadable"

exit 0
