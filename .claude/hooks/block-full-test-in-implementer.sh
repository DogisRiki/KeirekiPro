#!/bin/bash
# =====================================================================
# PreToolUse(Bash) hook: 実装役のサブエージェントに、テストを全部流させない
#
# /kiro-impl が起動する実装役(サブエージェントの種類 kiro-implementer)が、
# 領域のテストを全部流すコマンドを打ったら、実行前に止めて(exit 2)理由を返す。
# 全部のテストと品質チェックは、タスクごとに審査役が流す(#546)。
# ほかのサブエージェントとメインのセッションのコマンドは、そのまま通す。
# どのサブエージェントかは、フックの入力の agent_type で見分ける
# (https://code.claude.com/docs/en/hooks の「Common input fields」)。
#
# 止めるコマンド(run-check.sh の後ろや sh -c '...' の中に書いたものも含む):
#   gradle(gradlew): check / build / pitest / jacocoTestReport /
#                    jacocoTestCoverageVerification のタスク、--tests を付けない test のタスク
#   vitest(pnpm test / npm test / pnpm vitest / npx vitest など):
#                    テストのファイルやディレクトリを指定しないもの、--coverage を付けたもの
#   pnpm run coverage、stryker
#
# 前提: bash と perl(JSON::PP・Text::ParseWords)。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
# =====================================================================
set -u

payload=$(cat)

why=$(printf '%s' "$payload" | perl -MJSON::PP -MText::ParseWords -e '
    use strict;
    use warnings;
    local $/;
    my $d = eval { JSON::PP::decode_json(<STDIN>) };
    exit 0 unless ref $d eq "HASH";
    my $agent = $d->{agent_type};
    exit 0 unless defined $agent && !ref $agent && $agent eq "kiro-implementer";
    my $cmd = eval { $d->{tool_input}{command} };
    exit 0 unless defined $cmd && !ref $cmd;

    my %gradle_full = map { $_ => 1 }
        qw(check build pitest jacocoTestReport jacocoTestCoverageVerification);
    my %gradle_value_opt = map { $_ => 1 }
        qw(-p --project-dir -x --exclude-task -b --build-file -c --settings-file
           -g --gradle-user-home -I --init-script --tests --console --warning-mode);
    my %vitest_value_opt = map { $_ => 1 }
        qw(-t --testNamePattern -c --config --project -r --root --dir --reporter
           --outputFile --shard --environment --pool --mode);
    my %pm_value_opt = map { $_ => 1 } qw(-C --dir --filter -F --prefix -w --workspace);

    sub base { my $t = shift; $t =~ s{.*[/\\]}{}; return $t; }

    sub gradle_hit {
        my @a = @_;
        my $has_tests = grep { $_ eq "--tests" || /^--tests=/ } @a;
        for (my $i = 0; $i < @a; $i++) {
            my $t = $a[$i];
            if ($gradle_value_opt{$t}) { $i++; next; }
            next if $t =~ /^-/;
            (my $task = $t) =~ s/.*://;
            return "gradle の $t のタスク" if $gradle_full{$task};
            return "--tests を付けない gradle の $t のタスク" if $task eq "test" && !$has_tests;
        }
        return undef;
    }

    sub vitest_hit {
        my @a = @_;
        return "--coverage を付けた vitest" if grep { /^--coverage(\b|=|\.)/ } @a;
        my $files = 0;
        for (my $i = 0; $i < @a; $i++) {
            my $t = $a[$i];
            if ($vitest_value_opt{$t}) { $i++; next; }
            next if $t =~ /^-/;
            next if $i == 0 && $t =~ /^(run|watch|dev|related)$/;
            $files++;
        }
        return $files ? undef : "テストのファイルを指定しない vitest";
    }

    # パッケージマネージャ(pnpm / npm / yarn / npx など)の後ろを見る
    sub pm_hit {
        my ($pm, @a) = @_;
        my $i = 0;
        while ($i < @a && $a[$i] =~ /^-/) { $i += $pm_value_opt{$a[$i]} ? 2 : 1; }
        return undef if $i >= @a;
        my $sub = $a[$i++];
        if ($pm !~ /^(npx|pnpx|bunx)$/ && $sub =~ /^(run|run-script|exec|dlx|x)$/) {
            while ($i < @a && $a[$i] =~ /^-/) { $i += $pm_value_opt{$a[$i]} ? 2 : 1; }
            return undef if $i >= @a;
            $sub = $a[$i++];
        }
        my @rest = @a[$i .. $#a];
        @rest = grep { $_ ne "--" } @rest;
        return "$pm の coverage" if $sub eq "coverage";
        return "stryker(変異テスト)" if $sub eq "stryker";
        return vitest_hit(@rest) if $sub =~ /^(test|test:watch|vitest)$/;
        return undef;
    }

    sub segment_hit {
        # リダイレクト(> out.txt、2>&1 など)は、テストのファイルの指定と取り違えないよう外す
        my @t;
        for (my $i = 0; $i < @_; $i++) {
            if ($_[$i] =~ /^\d*(?:>>?|<|&>)$/) { $i++; next; }
            next if $_[$i] =~ /^\d*(?:>>?|<|&>)/;
            push @t, $_[$i];
        }
        for (my $i = 0; $i < @t; $i++) {
            my $b = base($t[$i]);
            my @rest = @t[$i + 1 .. $#t];
            return gradle_hit(@rest) if $b =~ /^(gradlew|gradlew\.bat|gradle)$/;
            return pm_hit($b, @rest) if $b =~ /^(pnpm|npm|yarn|npx|pnpx|bunx)$/;
            return vitest_hit(grep { $_ ne "--" } @rest) if $b eq "vitest";
            return "stryker(変異テスト)" if $b eq "stryker";
        }
        return undef;
    }

    # コマンドの区切り(&& || ; | & 改行)。2>&1 の & は区切りにしない
    my $sep = q{\s*(?:&&|\|\||(?<![<>])&(?!>)|[;|\n])\s*};
    # parse_line は区切りの正規表現を括弧でくくらずに埋め込むので、こちらでくくる
    my $delim = q{(?:} . $sep . q{|\s+)};

    sub scan {
        my ($s, $depth) = @_;
        return undef if $depth > 4;
        my @tok = parse_line($delim, "delimiters", $s);
        @tok = split /\s+/, $s unless @tok;
        my @seg;
        for my $w (@tok, ";") {
            next unless defined $w && length $w;
            # 改行も空白なので、区切りかどうかを先に見る
            if ($w =~ /^$sep$/) {
                my $h = segment_hit(@seg);
                return $h if defined $h;
                @seg = ();
                next;
            }
            next if $w =~ /^\s+$/;
            my $t = join " ", shellwords($w);
            $t = $w if $t eq "" && $w !~ /^(""|\x27\x27)$/;
            # sh -c / bash -lc の後ろの語は、それ自体を1つのコマンドとして見る
            if ($t =~ /\s/ && @seg && $seg[-1] =~ /^-[a-z]*c$/) {
                my $h = scan($t, $depth + 1);
                return $h if defined $h;
            }
            push @seg, $t;
        }
        return undef;
    }

    my $hit = scan($cmd, 0);
    print $hit if defined $hit;
' 2>/dev/null)

[ -z "$why" ] && exit 0

cat >&2 <<EOF
実装役(kiro-implementer)は、テストを全部流すコマンドを打てません(止めたもの: ${why})。
足したテストと、変えたコードに関係するテストだけを流してください。例:
  bash .claude/scripts/parallel/run-check.sh backend ./gradlew test --tests 'com.example.keirekipro.<パッケージ>.<クラス>'
  bash .claude/scripts/parallel/run-check.sh frontend pnpm test src/<テストのファイル>
全部のテストと品質チェック(/verify-frontend /verify-backend)は、タスクごとに審査役が流します。
EOF
exit 2
