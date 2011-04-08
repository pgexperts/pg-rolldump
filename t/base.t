#!/usr/bin/perl -w

use strict;
use Test::More tests => 118;
#use Test::More 'no_plan';
use File::Spec::Functions qw(catdir catfile);
use File::Path qw(make_path remove_tree);
use Test::File;
use Test::MockModule;

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
    _rolldump
    _need_link
    _link_for
    _files_for
    _parse_date
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
    prefix          => 'foo',
    pg_dump_options => [qw(-U postgres)],
], "Create a $CLASS object";

ok my $dumpfile = $rd->dumpfile, 'Get dumpfile name';
like $dumpfile, qr{^foo-\d{4}\d{2}\d{2}-\d{2}\d{2}\d{2}[.]dmp$},
    'Dumpfile name should include the timestamp';
like $rd->{time}, qr/^\d{10,}$/, 'Should have cached the time';

is_deeply Pg::RollDump::_parse_date('20110324-181137'), {
    year  => 2011,
    month => 3,
    day   => 24,
    hour  => 18,
}, '_parse_date() should work';

is_deeply Pg::RollDump::_parse_date('20110324-181137.dmp'), {
    year  => 2011,
    month => 3,
    day   => 24,
    hour  => 18,
}, '_parse_date() should work for file name';

is_deeply Pg::RollDump::_parse_date('foo-20110324-181137.dmp'), {
    year  => 2011,
    month => 3,
    day   => 24,
    hour  => 18,
}, '_parse_date() should work for prefixed file name';

is_deeply Pg::RollDump::_parse_date(
    '20101219-194234Z/foo/20110324-181137'
), {
    year  => 2011,
    month => 3,
    day   => 24,
    hour  => 18,
}, '_parse_date() should parse only date from the end of the string';

is_deeply Pg::RollDump::_parse_date(
    '20101219-194234Z/foo/20110324-181137.dmp'
), {
    year  => 2011,
    month => 3,
    day   => 24,
    hour  => 18,
}, '_parse_date() should parse only date from the end of the file name';

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

# Disable rolldump.
my $mocker = Test::MockModule->new('Pg::RollDump');
$mocker->mock(_rolldump => sub { pass '_rolldump should be called'; shift });

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
    'The proper options should have been passed to pg_dump';

##############################################################################
# Test files_for()
$mocker->mock(dumpfile => '20110327-181137.dmp');
$rd->{time} = 1301249497;

is_deeply $rd->_files_for('days'), [], 'Should start with no daily files';

# Let's add three daily files.
make_path catdir($dir, 'days');
for my $day (24, 25, 26) {
    my $fn = catfile $dir, 'days', "201103${day}-181137.dmp";
    open my $fh, '>', $fn or die "Cannot open $fn: $!\n";
    print $fh 'whatever';
    close $fh;
}

is_deeply $rd->_files_for('days'), [
    map {
        catfile $dir, 'days', "201103${_}-181137.dmp"
    } qw(24 25 26)
], 'Should have the three files from _files_for(days)';

unlink $_ for map {
    catfile $dir, 'days', "201103${_}-181137.dmp"
} qw(24 25 26);

##############################################################################
# Test _need_link().
my $date =  {
    year  => 2011,
    month => 3,
    day   => 27,
    hour  => 18,
};

# Test need when no previous.
ok $rd->_need_link($_, $date, []), "Should need $_ link when no previous"
    for qw(hours days weeks months years);

# Test need measured from previous.
for my $spec (
    [ hours  => '20110327-171137' ],
    [ hours  => '20110327-161137' ],
    [ hours  => '20110227-181137' ],
    [ hours  => '20110227-221137' ],
    [ hours  => '20100327-181137' ],
    [ days   => '20110326-171137' ],
    [ days   => '20110301-171137' ],
    [ days   => '20110228-171137' ],
    [ days   => '20100326-171137' ],
    [ weeks  => '20100403-171137' ],
    [ weeks  => '20110320-171137' ],
    [ weeks  => '20110326-171137' ],
    [ months => '20110227-171137' ],
    [ months => '20110228-171137' ],
    [ months => '20100328-171137' ],
    [ months => '20110128-171137' ],
    [ years  => '20100327-171137' ],
    [ years  => '20090327-171137' ],
) {
    ok $rd->_need_link($spec->[0], $date, ["root/hour/$spec->[1].dmp"]),
        "Should need $spec->[0] link since $spec->[1]";
}

# Test don't need measured from previous.
for my $spec (
    [ hours  => '20110327-181137' ],
    [ hours  => '20110327-221137' ],
    [ hours  => '20110516-221137' ],
    [ days   => '20110327-171137' ],
    [ days   => '20110329-171137' ],
    [ days   => '20110426-171137' ],
    [ days   => '20120326-171137' ],
    [ weeks  => '20110327-171137' ],
    [ weeks  => '20110329-171137' ],
    [ weeks  => '20110403-171137' ],
    [ months => '20110327-171137' ],
    [ months => '20110301-171137' ],
    [ months => '20110427-171137' ],
    [ months => '20120327-171137' ],
    [ years  => '20110327-171137' ],
    [ years  => '20110227-171137' ],
    [ years  => '20120327-171137' ],
) {
    ok !$rd->_need_link($spec->[0], $date, ["root/hour/$spec->[1].dmp"]),
        "Should not need $spec->[0] link since $spec->[1]";
}

##############################################################################
# Test _link_for(). We need a file to link.
my $file = catfile $dir, 'hours', $rd->dumpfile;
open $fh, '>', $file or die "Cannot open $file: $!\n";
print $fh 'whatever';
ok !$rd->_link_for('hours', $file),
    'Should create no hourly link because the file already exists';

for my $interval (qw(days weeks months years)) {
    local $rd->{hard_links} = 1;
    make_path catdir $dir, $interval;
    my $dest = catfile $dir, $interval, $rd->dumpfile;
    file_not_exists_ok $dest, "$interval link should not exist";
    is $rd->_link_for($interval, $file), $dest,
        "Should create $interval file link";
    file_exists_ok $dest, "$interval link should now exist";
    link_count_is_ok $file, 2, "Original file should have 2 hard links";

    # Test copying.
    unlink $dest;
    $rd->{hard_links} = 0;
    is $rd->_link_for($interval, $file), $dest,
        "Should copy $interval file";
    file_exists_ok $dest, "$interval copy should now exist";
    link_count_is_ok $file, 1, "Original file should have 1 hard link";
}

##############################################################################
# Test _rolldump().
$mocker->unmock('_rolldump');

$mocker->mock(_link_for => 'newlink');
$rd->{keep_hours} = undef;

for my $interval (qw(hours days weeks months years)) {
    # Start out assuming everything needs a link.
    $mocker->mock(_need_link => 1);
    local $rd->{"keep_$interval"} = 2;
    my $old = catfile $dir, $interval, $rd->dumpfile;
    my @files = ($old, 'mumble');
    $mocker->mock(_files_for => \@files);
    file_exists_ok $old, "Old $interval file should exist";
    ok $rd->_rolldump($file), 'Roll the file';
    file_not_exists_ok $old, "Old $interval file should be gone";
    is_deeply \@files, [qw(mumble newlink )], 'File list should be two latest';

    # Now assume we don't need a link.
    $mocker->mock(_need_link => 0);
    ok $rd->_rolldump($file), 'Roll the files again';
    is_deeply \@files, [qw(mumble newlink )], 'File list should be unchanged';
}
