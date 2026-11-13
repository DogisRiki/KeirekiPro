#!/usr/bin/perl
# =====================================================================
# agent-model.pl: 補助役が実際に動いたモデルを、補助役の会話の記録から読む
#
# 使い方:
#   perl .claude/scripts/spec-review/agent-model.pl --transcript <会話の記録のファイル>
#   perl .claude/scripts/spec-review/agent-model.pl --agent-id <agentId>
#
# --agent-id は、$HOME/.claude/projects と、Windows では $USERPROFILE/.claude/projects の下の
# <project>/<sessionId>/subagents/agent-<agentId>.jsonl を探す。2つの候補が同じフォルダなら1つに数え、
# 見つかったファイルが1つのときだけ読む。
#
# 読む行: type が assistant で、message.model が文字列で <synthetic> でない行のうち、最後の行。
# JSON として読めない行は飛ばす。
#
# 出力(標準出力に3行、この順):
#   model=<ID>      例 claude-fable-5-2
#   family=<系統>   例 fable(ID が claude-<系統>-<数>(-<数>)* の形でなければ空)
#   name=<名前>     例 Fable 5.2(ID がその形でなければ ID のまま)
# 読み取れなかったとき(ファイルが無い、読めない、当てはまる行が無い、--agent-id で
# 見つかったファイルが0か2以上)は、3行とも値を空にして出す。
#
# 終了コード: 読み取れたときと読み取れなかったときは0。
#   引数が足りない、知らない引数、agentId の形が違うときは2で、標準エラーに理由を1行出す。
#
# このスクリプトは、どの系統を受け入れるかを判定しない(判定は呼ぶ側が行う)。
# ほかのスクリプトを読み込まない。会話の記録を書き換えない。
# 前提: perl 5 と標準のモジュール(JSON::PP、File::Spec)。
# =====================================================================
use strict;
use warnings;
use JSON::PP ();
use File::Spec ();

sub usage_error {
    my ($msg) = @_;
    print STDERR "agent-model.pl: $msg\n";
    exit 2;
}

sub emit {
    my ($id) = @_;
    my ( $family, $name ) = ( '', '' );
    if ( defined $id && length $id ) {
        ( $family, $name ) = family_and_name($id);
    }
    else {
        $id = '';
    }
    print "model=$id\n";
    print "family=$family\n";
    print "name=$name\n";
    exit 0;
}

# ID から系統と表示の名前を作る
sub family_and_name {
    my ($id) = @_;
    my $core = $id;
    $core =~ s/\[[^\]]*\]\z//;    # 末尾の [1m] のような付記を外す
    $core =~ s/-\d{8}\z//;        # 末尾の -<8桁の日付> を外す
    if ( $core =~ /\Aclaude-([A-Za-z]+)((?:-\d+)+)\z/ ) {
        my $family = lc $1;
        my $digits = $2;
        $digits =~ s/\A-//;
        my $version = join '.', split /-/, $digits;
        return ( $family, ucfirst($family) . ' ' . $version );
    }
    return ( '', $id );
}

# 会話の記録から、最後に応答したモデルの ID を読む。読めなければ undef
sub last_model {
    my ($path) = @_;
    return undef unless defined $path && -f $path;
    open my $fh, '<:raw', $path or return undef;
    my $found;
    while ( my $line = <$fh> ) {
        next unless $line =~ /\S/;
        my $d = eval { JSON::PP::decode_json($line) };
        next unless ref $d eq 'HASH';
        next unless defined $d->{type} && !ref $d->{type} && $d->{type} eq 'assistant';
        my $m = $d->{message};
        next unless ref $m eq 'HASH';
        my $model = $m->{model};
        next unless defined $model && !ref $model;
        next if $model eq '<synthetic>' || $model eq '';
        $found = $model;
    }
    close $fh;
    return $found;
}

# フォルダを同じものとして数えるための鍵。Git Bash の perl では、同じフォルダでも
# HOME(/c/...)と USERPROFILE(C:\...)で書き方が違うので、stat の dev と ino で比べる
sub dir_key {
    my ($dir) = @_;
    my @s = stat $dir;
    return "$s[0]:$s[1]" if @s && $s[1];
    my $k = $dir;
    $k =~ s{\\}{/}g;
    $k =~ s{\A([A-Za-z]):}{'/' . lc($1)}e;
    $k =~ s{/+\z}{};
    return lc $k;
}

sub subdirs {
    my ($dir) = @_;
    opendir my $dh, $dir or return ();
    my @out;
    for my $e ( readdir $dh ) {
        next if $e eq '.' || $e eq '..';
        my $p = File::Spec->catdir( $dir, $e );
        push @out, $p if -d $p;
    }
    closedir $dh;
    return sort @out;
}

sub find_by_agent_id {
    my ($agent_id) = @_;
    my @roots;
    for my $base ( $ENV{HOME}, ( $^O eq 'MSWin32' || $^O eq 'cygwin' || $^O eq 'msys' ) ? $ENV{USERPROFILE} : () ) {
        next unless defined $base && length $base;
        my $root = File::Spec->catdir( $base, '.claude', 'projects' );
        push @roots, $root if -d $root;
    }
    my ( %seen, @found );
    for my $root (@roots) {
        next if $seen{ dir_key($root) }++;
        for my $project ( subdirs($root) ) {
            for my $session ( subdirs($project) ) {
                my $f = File::Spec->catfile( $session, 'subagents', "agent-$agent_id.jsonl" );
                push @found, $f if -f $f;
            }
        }
    }
    return @found == 1 ? $found[0] : undef;
}

my ( $transcript, $agent_id );
my @args = @ARGV;
usage_error('引数が足りない(--transcript <ファイル> か --agent-id <agentId> を1つ渡す)') unless @args;
while (@args) {
    my $a = shift @args;
    if ( $a eq '--transcript' || $a eq '--agent-id' ) {
        usage_error("$a の値が無い") unless @args;
        my $v = shift @args;
        if ( $a eq '--transcript' ) { $transcript = $v }
        else                        { $agent_id   = $v }
    }
    else {
        usage_error("知らない引数: $a");
    }
}
usage_error('--transcript と --agent-id は1つだけ渡す') if defined $transcript && defined $agent_id;

if ( defined $agent_id ) {
    usage_error("agentId の形が違う(英数字と _ と - だけ): $agent_id") unless $agent_id =~ /\A[A-Za-z0-9_-]+\z/;
    my $f = find_by_agent_id($agent_id);
    emit( defined $f ? last_model($f) : undef );
}
emit( last_model($transcript) );
