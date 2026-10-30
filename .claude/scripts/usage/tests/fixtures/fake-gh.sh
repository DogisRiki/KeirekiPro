#!/usr/bin/env bash
# =====================================================================
# テストに使う偽の gh
#
# テストは、このファイルを一時フォルダに gh の名前で写し、その一時フォルダを
# PATH の先頭に置く。偽の gh は、$FAKE_GH_DIR のフォルダのファイルを GitHub の
# 代わりにする。前提: bash・perl(JSON::PP)。
#
# $FAKE_GH_DIR に置くファイル
# - db.json: GitHub の中身。無いときは空のリポジトリとして動く。書き込む呼び出しは、
#   このファイルを書き直す。欄は次のとおり
#   - repo: {"owner","name","push"}。push は repos/{owner}/{repo} の permissions.push
#   - viewer_association: 偽の gh が作る Issue とコメントの author_association(既定 OWNER)
#   - now: 偽の gh が書く時刻(既定はいまの協定世界時)
#   - issues: [{number,title,body,state("open"|"closed"),state_reason,closed_at,
#     locked,author_association,comments:[{id,body,author_association,created_at}], ...}]
#     gh issue view / list の --json は、state を大文字に、closedAt を closed_at から、
#     comments を gh の形に直して返し、ほかの欄は同じ名前の値をそのまま返す
#   - prs: [{number,state("OPEN"|"CLOSED"|"MERGED"),baseRefName,headRefName,body,
#     mergedAt,mergeCommit,commits, ...}]。gh pr list / view の --json は、同じ名前の値を
#     そのまま返す。baseRefName が無い PR は main に向けた PR とみなす。gh pr list の
#     --search は merged:>=<日付> の形だけを受け、mergedAt の日付がその日より前の PR を除く
#   - check_runs: {"<sha>": [{name,status,conclusion}, ...]}。無い sha は 422 で失敗する
# - fail: 1行に1つの perl の正規表現。呼ばれた引数を空白でつないだ文字列に当たると、
#   偽の gh は何もせずに 1 で終わる
#
# 偽の gh が書くファイル
# - calls.log: 呼ばれた引数を、1回の呼び出しにつき1行、空白でつないで書く
#
# 偽の gh は、答えられない呼び出し(知らないオプション、--jq など)を、2 で終わらせる。
# テストが偽の gh の答えない呼び出しに気づかないまま通ることを防ぐためである。
# --paginate は、ページごとの JSON を区切らずに続けて出す(本物の gh の --slurp 無しの形)。
# =====================================================================
: <<'__PERL__'
#!perl
use strict;
use warnings;
use JSON::PP;
use Encode qw(decode);
use Fcntl qw(:flock);
use POSIX qw(strftime);

my $JSON = JSON::PP->new->utf8->canonical;

sub unsupported {
    print STDERR "fake-gh: unsupported: $_[0]\n";
    exit 2;
}

sub fail_with {
    print STDERR "$_[0]\n";
    exit 1;
}

my $dir = $ENV{FAKE_GH_DIR};
unsupported('FAKE_GH_DIR is not set') unless defined $dir && length $dir;
my @args = @ARGV;

open my $lockfh, '>>', "$dir/.fake-gh.lock" or unsupported("cannot open $dir/.fake-gh.lock: $!");
flock $lockfh, LOCK_EX;

{
    open my $lg, '>>', "$dir/calls.log" or unsupported("cannot open $dir/calls.log: $!");
    print {$lg} join(' ', map { (my $s = $_) =~ s/\n/\\n/g; $s } @args), "\n";
    close $lg;
}

{
    my $joined = join ' ', @args;
    if (open my $f, '<', "$dir/fail") {
        while (my $re = <$f>) {
            chomp $re;
            $re =~ s/\r\z//;
            next if $re eq '' || $re =~ /\A#/;
            fail_with("fake-gh: forced failure ($re)") if $joined =~ /$re/;
        }
        close $f;
    }
}

my $db;
if (-e "$dir/db.json") {
    open my $f, '<', "$dir/db.json" or unsupported("cannot read db.json: $!");
    local $/;
    $db = $JSON->decode(<$f>);
    close $f;
} else {
    $db = {};
}
$db->{repo} ||= { owner => 'owner', name => 'repo', push => JSON::PP::true };
$db->{issues} ||= [];
$db->{prs} ||= [];
my $OWNER = $db->{repo}{owner};
my $NAME = $db->{repo}{name};
my $VIEWER = $db->{viewer_association} // 'OWNER';

sub now { return $db->{now} // strftime('%Y-%m-%dT%H:%M:%SZ', gmtime) }

sub save {
    open my $f, '>', "$dir/db.json.tmp" or unsupported("cannot write db.json: $!");
    print {$f} JSON::PP->new->utf8->canonical->pretty->encode($db);
    close $f;
    rename "$dir/db.json.tmp", "$dir/db.json" or unsupported("cannot rename db.json: $!");
}

sub out { print $JSON->encode($_[0]), "\n" }

sub text { return decode('UTF-8', $_[0]) }

sub read_file {
    my ($p) = @_;
    open my $f, '<', $p or fail_with("open $p: no such file or directory");
    local $/;
    my $c = <$f>;
    close $f;
    return text($c);
}

# 引数を、値を取るオプション(%$valued)と値を取らないオプション(%$flags)と位置の引数に分ける
sub parse {
    my ($argv, $valued, $flags) = @_;
    my (%o, @pos);
    my @a = @$argv;
    while (@a) {
        my $x = shift @a;
        if ($x =~ /\A(--[\w-]+)=(.*)\z/s && exists $valued->{$1}) {
            push @{ $o{ $valued->{$1} } }, $2;
        } elsif (exists $valued->{$x}) {
            unsupported("missing value for $x") unless @a;
            push @{ $o{ $valued->{$x} } }, shift @a;
        } elsif (exists $flags->{$x}) {
            $o{ $flags->{$x} } = 1;
        } elsif ($x =~ /\A-/) {
            unsupported("option $x");
        } else {
            push @pos, $x;
        }
    }
    return (\%o, \@pos);
}

sub one { my ($o, $k) = @_; return $o->{$k} ? $o->{$k}[-1] : undef }

sub find_issue {
    my ($n) = @_;
    for my $i (@{ $db->{issues} }) { return $i if $i->{number} == $n }
    return undef;
}

sub find_pr {
    my ($n) = @_;
    for my $p (@{ $db->{prs} }) { return $p if $p->{number} == $n }
    return undef;
}

sub issue_url { return "https://github.com/$OWNER/$NAME/issues/$_[0]" }

sub all_comments { return map { @{ $_->{comments} || [] } } @{ $db->{issues} } }

sub new_comment {
    my ($issue, $body) = @_;
    my $id = 1000;
    for my $c (all_comments()) { $id = $c->{id} + 1 if $c->{id} >= $id }
    my $c = { id => $id, body => $body, author_association => $VIEWER, created_at => now() };
    push @{ $issue->{comments} }, $c;
    return $c;
}

sub can_comment {
    my ($issue) = @_;
    return 1 unless $issue->{locked};
    return scalar grep { $_ eq $VIEWER } qw(OWNER COLLABORATOR MEMBER);
}

sub comment_cli {
    my ($i, $c) = @_;
    return {
        id => $c->{id}, body => $c->{body}, authorAssociation => $c->{author_association},
        createdAt => $c->{created_at}, url => issue_url($i->{number}) . "#issuecomment-$c->{id}",
    };
}

sub issue_cli {
    my ($i, $fields) = @_;
    my %r;
    for my $k (@$fields) {
        if ($k eq 'state') { $r{$k} = uc $i->{state} }
        elsif ($k eq 'closedAt') { $r{$k} = $i->{closed_at} }
        elsif ($k eq 'url') { $r{$k} = issue_url($i->{number}) }
        elsif ($k eq 'comments') { $r{$k} = [ map { comment_cli($i, $_) } @{ $i->{comments} || [] } ] }
        else { $r{$k} = $i->{$k} }
    }
    return \%r;
}

sub pr_cli {
    my ($p, $fields) = @_;
    my %r;
    for my $k (@$fields) {
        $r{$k} = $k eq 'url' ? "https://github.com/$OWNER/$NAME/pull/$p->{number}" : $p->{$k};
    }
    return \%r;
}

sub comment_rest {
    my ($i, $c) = @_;
    return {
        id => $c->{id}, body => $c->{body}, author_association => $c->{author_association},
        created_at => $c->{created_at}, html_url => issue_url($i->{number}) . "#issuecomment-$c->{id}",
    };
}

sub issue_rest {
    my ($i) = @_;
    return {
        number => $i->{number}, title => $i->{title}, body => $i->{body}, state => $i->{state},
        state_reason => $i->{state_reason}, closed_at => $i->{closed_at},
        locked => $i->{locked} ? JSON::PP::true : JSON::PP::false,
        author_association => $i->{author_association}, html_url => issue_url($i->{number}),
        comments => scalar @{ $i->{comments} || [] },
    };
}

sub pr_rest {
    my ($p) = @_;
    my $state = $p->{state} eq 'OPEN' ? 'open' : 'closed';
    return {
        number => $p->{number}, title => $p->{title}, body => $p->{body}, state => $state,
        locked => JSON::PP::false, author_association => $p->{author_association} // 'OWNER',
        html_url => "https://github.com/$OWNER/$NAME/pull/$p->{number}",
        pull_request => { url => "https://api.github.com/repos/$OWNER/$NAME/pulls/$p->{number}" },
    };
}

sub json_fields {
    my ($o) = @_;
    my $j = one($o, 'json');
    unsupported('output without --json') unless defined $j;
    return [ split /,/, $j ];
}

sub limit_of { my $l = one($_[0], 'limit'); return defined $l ? $l : 30 }

# ---- gh issue ------------------------------------------------------------
sub cmd_issue {
    my ($sub, @rest) = @_;
    $sub //= '';
    if ($sub eq 'view') {
        my ($o, $pos) = parse(\@rest, { '--json' => 'json', '-R' => 'repo', '--repo' => 'repo' }, {});
        my $i = find_issue($pos->[0] // 0)
            or fail_with("GraphQL: Could not resolve to an issue or pull request with the number of " . ($pos->[0] // '') . ". (repository.issue)");
        out(issue_cli($i, json_fields($o)));
    } elsif ($sub eq 'list') {
        my ($o) = parse(\@rest, { '--json' => 'json', '--state' => 'state', '-s' => 'state', '--search' => 'search',
            '-S' => 'search', '--limit' => 'limit', '-L' => 'limit', '-R' => 'repo', '--repo' => 'repo' }, {});
        my $state = one($o, 'state') // 'open';
        unsupported("--state $state") unless $state =~ /\A(open|closed|all)\z/;
        my $since;
        if (defined(my $s = one($o, 'search'))) {
            ($since) = $s =~ /\Aclosed:>=(\d{4}-\d{2}-\d{2})\z/ or unsupported("--search $s");
        }
        my @r = grep {
            ($state eq 'all' || $_->{state} eq $state)
                && (!defined $since || (defined $_->{closed_at} && substr($_->{closed_at}, 0, 10) ge $since))
        } sort { $b->{number} <=> $a->{number} } @{ $db->{issues} };
        splice @r, limit_of($o) if @r > limit_of($o);
        my $f = json_fields($o);
        out([ map { issue_cli($_, $f) } @r ]);
    } elsif ($sub eq 'comment') {
        my ($o, $pos) = parse(\@rest, { '--body-file' => 'bodyfile', '-F' => 'bodyfile', '--body' => 'body', '-b' => 'body',
            '-R' => 'repo', '--repo' => 'repo' }, {});
        my $i = find_issue($pos->[0] // 0) or fail_with('GraphQL: Could not resolve to an issue or pull request');
        fail_with('GraphQL: Unable to create comment because issue is locked.') unless can_comment($i);
        my $body = defined one($o, 'bodyfile') ? read_file(one($o, 'bodyfile')) : text(one($o, 'body') // unsupported('comment without body'));
        my $c = new_comment($i, $body);
        save();
        print issue_url($i->{number}) . "#issuecomment-$c->{id}\n";
    } elsif ($sub eq 'edit') {
        my ($o, $pos) = parse(\@rest, { '--body-file' => 'bodyfile', '-F' => 'bodyfile', '--body' => 'body', '-b' => 'body',
            '--title' => 'title', '-t' => 'title', '-R' => 'repo', '--repo' => 'repo' }, {});
        my $i = find_issue($pos->[0] // 0) or fail_with('GraphQL: Could not resolve to an issue or pull request');
        $i->{body} = read_file(one($o, 'bodyfile')) if defined one($o, 'bodyfile');
        $i->{body} = text(one($o, 'body')) if defined one($o, 'body');
        $i->{title} = text(one($o, 'title')) if defined one($o, 'title');
        save();
        print issue_url($i->{number}), "\n";
    } elsif ($sub eq 'create') {
        my ($o) = parse(\@rest, { '--body-file' => 'bodyfile', '-F' => 'bodyfile', '--body' => 'body', '-b' => 'body',
            '--title' => 'title', '-t' => 'title', '-R' => 'repo', '--repo' => 'repo' }, {});
        my $title = one($o, 'title') // unsupported('create without --title');
        my $body = defined one($o, 'bodyfile') ? read_file(one($o, 'bodyfile')) : text(one($o, 'body') // '');
        my $n = 0;
        for my $x (@{ $db->{issues} }, @{ $db->{prs} }) { $n = $x->{number} if $x->{number} > $n }
        $n++;
        push @{ $db->{issues} }, {
            number => $n, title => text($title), body => $body, state => 'open', state_reason => undef,
            closed_at => undef, locked => JSON::PP::false, author_association => $VIEWER, comments => [],
        };
        save();
        print issue_url($n), "\n";
    } elsif ($sub eq 'close') {
        my ($o, $pos) = parse(\@rest, { '--reason' => 'reason', '-r' => 'reason', '--comment' => 'comment', '-c' => 'comment',
            '-R' => 'repo', '--repo' => 'repo' }, {});
        my $i = find_issue($pos->[0] // 0) or fail_with('GraphQL: Could not resolve to an issue or pull request');
        if ($i->{state} eq 'closed') {
            print STDERR "! Issue #$i->{number} is already closed\n";
            exit 0;
        }
        new_comment($i, text(one($o, 'comment'))) if defined one($o, 'comment');
        my $reason = one($o, 'reason') // 'completed';
        ($i->{state_reason} = lc $reason) =~ s/ /_/g;
        $i->{state} = 'closed';
        $i->{closed_at} = now();
        save();
        print STDERR "Closed issue #$i->{number}\n";
    } elsif ($sub eq 'lock') {
        my ($o, $pos) = parse(\@rest, { '--reason' => 'reason', '-r' => 'reason', '-R' => 'repo', '--repo' => 'repo' }, {});
        my $i = find_issue($pos->[0] // 0) or fail_with('GraphQL: Could not resolve to an issue or pull request');
        $i->{locked} = JSON::PP::true;
        save();
        print STDERR "Locked issue #$i->{number}\n";
    } else {
        unsupported("issue $sub");
    }
}

# ---- gh pr ---------------------------------------------------------------
sub cmd_pr {
    my ($sub, @rest) = @_;
    $sub //= '';
    if ($sub eq 'list') {
        my ($o) = parse(\@rest, { '--json' => 'json', '--state' => 'state', '-s' => 'state', '--base' => 'base', '-B' => 'base',
            '--head' => 'head', '-H' => 'head', '--search' => 'search', '-S' => 'search', '--limit' => 'limit', '-L' => 'limit',
            '-R' => 'repo', '--repo' => 'repo' }, {});
        my $state = one($o, 'state') // 'open';
        unsupported("--state $state") unless $state =~ /\A(open|merged|all)\z/;
        my ($base, $head) = (one($o, 'base'), one($o, 'head'));
        my $since;
        if (defined(my $s = one($o, 'search'))) {
            ($since) = $s =~ /\Amerged:>=(\d{4}-\d{2}-\d{2})\z/ or unsupported("--search $s");
        }
        my @r = grep {
            ($state eq 'all' || $_->{state} eq uc $state)
                && (!defined $since || (defined $_->{mergedAt} && substr($_->{mergedAt}, 0, 10) ge $since))
                && (!defined $base || ($_->{baseRefName} // 'main') eq $base)
                && (!defined $head || ($_->{headRefName} // '') eq $head)
        } sort { $b->{number} <=> $a->{number} } @{ $db->{prs} };
        splice @r, limit_of($o) if @r > limit_of($o);
        my $f = json_fields($o);
        out([ map { pr_cli($_, $f) } @r ]);
    } elsif ($sub eq 'view') {
        my ($o, $pos) = parse(\@rest, { '--json' => 'json', '-R' => 'repo', '--repo' => 'repo' }, {});
        my $p = find_pr($pos->[0] // 0) or fail_with('no pull requests found for ' . ($pos->[0] // ''));
        out(pr_cli($p, json_fields($o)));
    } else {
        unsupported("pr $sub");
    }
}

# ---- gh api --------------------------------------------------------------
sub field_value {
    my ($v, $typed) = @_;
    return read_file(substr $v, 1) if $typed && $v =~ /\A@/;
    if ($typed) {
        return JSON::PP::true if $v eq 'true';
        return JSON::PP::false if $v eq 'false';
        return undef if $v eq 'null';
        return $v + 0 if $v =~ /\A-?\d+\z/;
    }
    return text($v);
}

# 項目の並びを per_page ごとのページに分けて出す。$wrap はページを応答の形に直す
sub paged {
    my ($items, $q, $o, $wrap) = @_;
    my $per = $q->{per_page} // 30;
    my @pages;
    for (my $k = 0; $k < @$items; $k += $per) {
        my $end = $k + $per - 1;
        $end = $#$items if $end > $#$items;
        push @pages, [ @{$items}[ $k .. $end ] ];
    }
    @pages = ([]) unless @pages;
    @pages = ($pages[0]) unless $o->{paginate};
    my @bodies = map { $wrap ? $wrap->($_) : $_ } @pages;
    if ($o->{slurp}) {
        out(\@bodies);
    } else {
        print join('', map { $JSON->encode($_) } @bodies), "\n";
    }
}

sub cmd_api {
    my ($o, $pos) = parse(\@_, { '-X' => 'method', '--method' => 'method', '-F' => 'field', '--field' => 'field',
        '-f' => 'raw', '--raw-field' => 'raw', '-H' => 'header', '--header' => 'header' },
        { '--paginate' => 'paginate', '--slurp' => 'slurp' });
    my $path = $pos->[0] // unsupported('api without endpoint');
    unsupported('api with more than one endpoint') if @$pos > 1;
    my %body;
    for my $kv (@{ $o->{field} || [] }) {
        my ($k, $v) = $kv =~ /\A([^=]+)=(.*)\z/s or unsupported("-F $kv");
        $body{$k} = field_value($v, 1);
    }
    for my $kv (@{ $o->{raw} || [] }) {
        my ($k, $v) = $kv =~ /\A([^=]+)=(.*)\z/s or unsupported("-f $kv");
        $body{$k} = field_value($v, 0);
    }
    my $method = uc(one($o, 'method') // (%body ? 'POST' : 'GET'));
    $path =~ s{\A/}{};
    $path =~ s/\{owner\}/$OWNER/g;
    $path =~ s/\{repo\}/$NAME/g;
    my ($route, $query) = split /\?/, $path, 2;
    my %q = map { my ($k, $v) = split /=/, $_, 2; ($k => $v) } grep { length } split /&/, ($query // '');

    my $not_found = sub { fail_with("gh: Not Found (HTTP 404)") };
    $route =~ s{\Arepos/\Q$OWNER\E/\Q$NAME\E(?=/|\z)}{} or do {
        $route =~ m{\Arepos/[^/]+/[^/]+(/|\z)} ? $not_found->() : unsupported("api $method $path");
    };

    if ($method eq 'GET' && $route eq '') {
        out({ full_name => "$OWNER/$NAME", name => $NAME, owner => { login => $OWNER },
              permissions => { push => $db->{repo}{push} ? JSON::PP::true : JSON::PP::false } });
    } elsif ($method eq 'GET' && $route eq '/issues') {
        my $state = $q{state} // 'open';
        my @all = ((map { issue_rest($_) } @{ $db->{issues} }), (map { pr_rest($_) } @{ $db->{prs} }));
        my @r = grep { $state eq 'all' || $_->{state} eq $state } sort { $b->{number} <=> $a->{number} } @all;
        paged(\@r, \%q, $o);
    } elsif ($method eq 'GET' && $route =~ m{\A/issues/(\d+)\z}) {
        my $i = find_issue($1) or $not_found->();
        out(issue_rest($i));
    } elsif ($route =~ m{\A/issues/(\d+)/comments\z}) {
        my $i = find_issue($1) or $not_found->();
        if ($method eq 'GET') {
            paged([ map { comment_rest($i, $_) } @{ $i->{comments} || [] } ], \%q, $o);
        } elsif ($method eq 'POST') {
            fail_with('gh: Unable to create comment because issue is locked. (HTTP 403)') unless can_comment($i);
            defined $body{body} or fail_with('gh: Invalid request. (HTTP 422)');
            my $c = new_comment($i, $body{body});
            save();
            out(comment_rest($i, $c));
        } else {
            unsupported("api $method $path");
        }
    } elsif ($route =~ m{\A/issues/comments/(\d+)\z}) {
        my $id = $1;
        my ($i, $c);
        for my $x (@{ $db->{issues} }) {
            for my $y (@{ $x->{comments} || [] }) { ($i, $c) = ($x, $y) if $y->{id} == $id }
        }
        $c or $not_found->();
        if ($method eq 'GET') {
            out(comment_rest($i, $c));
        } elsif ($method eq 'PATCH') {
            defined $body{body} or fail_with('gh: Invalid request. (HTTP 422)');
            $c->{body} = $body{body};
            save();
            out(comment_rest($i, $c));
        } else {
            unsupported("api $method $path");
        }
    } elsif ($method eq 'GET' && $route =~ m{\A/commits/([^/]+)/check-runs\z}) {
        my $runs = ($db->{check_runs} || {})->{$1};
        fail_with("gh: No commit found for SHA: $1 (HTTP 422)") unless $runs;
        paged($runs, \%q, $o, sub { return { total_count => scalar @$runs, check_runs => $_[0] } });
    } else {
        unsupported("api $method $path");
    }
}

my $cmd = shift @args // '';
if ($cmd eq 'issue') { cmd_issue(@args) }
elsif ($cmd eq 'pr') { cmd_pr(@args) }
elsif ($cmd eq 'api') { cmd_api(@args) }
else { unsupported("command $cmd") }
exit 0;
__END__
__PERL__
exec perl -x "$0" "$@"
