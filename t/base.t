#!/usr/bin/perl -w

use strict;
#use Test::More tests => 2;
use Test::More 'no_plan';
use File::Spec::Functions qw(catdir catfile);
use File::Path qw(make_path remove_tree);
use Test::File;

my $CLASS;
BEGIN {
    $CLASS = 'Pg::RollDump';
    use_ok $CLASS or die;
}

can_ok $CLASS, qw(
    new
    go
    run
    pg_dump
    pg_dump_options
    directory
    keep_hours
    keep_days
    keep_weeks
    keep_months
    keep_years
    hard_links
    verbose
    dumpfile
    _pod2usage
    _getopts
);

# Find our test pg_dump program.
my $pg_dump = 'test_pg_dump';
$pg_dump .= '.bat' if $^O eq 'MSWin32';
$pg_dump = -e catfile(qw(t scripts), $pg_dump)
    ? catfile(qw(t scripts), $pg_dump)
    : catfile(qw(t bin), $pg_dump);

# Where should we put the dumps?
my $dir = catdir qw(t dump);
END { remove_tree $dir };

# Fire 'er up!
my $rd = new_ok $CLASS, [
    directory       => $dir,
    keep_hours      => 2,
    pg_dump         => $pg_dump,
    pg_dump_options => [qw(-U postgres)],
], "Create a $CLASS object";

ok my $dumpfile = $rd->dumpfile, 'Get dumpfile name';
like $dumpfile, qr{^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z[.]dump$},
    'Dumpfile name should include the timestamp';

# We should get error for non-existent directory.
local $@;
eval { $rd->run };
like $@, qr/Directory $dir does not exist/,
    'Should be error for missing directory';

# We should get an error for a non-directory directory.
open my $fh, '>', $dir or die "Cannot open $dir: $!\n";
print $fh 'whatever';
close $fh;
eval { $rd->run };
like $@, qr/$dir is not a directory/,
    'Should be error for invalid directory';
remove_tree $dir;

# Okay, create the directory now for realz.
make_path $dir;
ok $rd->run, 'Run the backup!';

file_exists_ok "t/dump/hours/$dumpfile", 'Dump file should now exist';
my $fn = catfile qw(t dump hours), $dumpfile;
is do {
    open my $fh, '<', $fn or die "Cannot open $fn: $!\n";
    local $/;
    <$fh>;
}, "-U\npostgres\n--file\n$fn\n",

