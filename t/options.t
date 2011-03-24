#!/usr/bin/perl -w

use strict;
use Test::More tests => 32;
#use Test::More 'no_plan';
use Pg::RollDump;
use Test::MockModule;

my %defaults = (
    hard_links  => 1,
    help        => undef,
    keep_days   => undef,
    keep_hours  => undef,
    keep_months => undef,
    keep_weeks  => undef,
    keep_years  => undef,
    man         => undef,
    pg_dump     => 'pg_dump',
    verbose     => 0,
    version     => undef,
);

ERRORS: {
    my $mocker = Test::MockModule->new('Pg::RollDump');
    my @params;
    $mocker->mock( _pod2usage => sub { shift; @params = @_; die; });

    # Make sure --output-dir is required.
    local @ARGV;
    eval { Pg::RollDump->_getopts };
    is_deeply \@params, ['-message' => "Missing required --output-dir option"],
        'No options should trigger --output-dir error';

    # Make sure an interval option is required.
    @ARGV = qw(--dir whatever);
    eval { Pg::RollDump->_getopts };
    is_deeply \@params, ['-message' => "Missing required interval option. Specify one or more of:
    --keep-hours
    --keep-days
    --keep-weeks
    --keep-months
    --keep-years"],
        'No options should trigger --output-dir error';
}

DIRECTORY: {
    local $defaults{keep_hours} = 2;
    local @ARGV = qw(--dir /path/to/backup -h 2);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        directory => '/path/to/backup',
    }, 'Should have expected options with --dir';

    @ARGV = qw(--output-dir /path/to/backup -h 2);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        directory => '/path/to/backup',
    }, 'Should have expected options with --directory';

    @ARGV = qw(-o /path/to/backup -h 2);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        directory => '/path/to/backup',
    }, 'Should have expected options with --directory';
}

INTERVALS: {
    for my $spec (
        [ hours  => 4 ],
        [ days   => 5 ],
        [ weeks  => 6 ],
        [ months => 7 ],
        [ years  => 8 ],
    ) {
        local $defaults{directory} = 'whatever';
        local @ARGV = ('-o', 'whatever', "--keep-$spec->[0]", $spec->[1]);
        is_deeply +Pg::RollDump->_getopts, {
            %defaults,
            "keep_$spec->[0]" => $spec->[1],
        }, "Should have expected options with --keep-$spec->[0] $spec->[1]";

        @ARGV = ('-o', 'whatever', "--$spec->[0]", $spec->[1]);
        is_deeply +Pg::RollDump->_getopts, {
            %defaults,
            "keep_$spec->[0]" => $spec->[1],
        }, "Should have expected options with --$spec->[0] $spec->[1]";

        my $letter = substr $spec->[0], 0, 1;
        @ARGV = ('-o', 'whatever', "-$letter", $spec->[1]);
        is_deeply +Pg::RollDump->_getopts, {
            %defaults,
            "keep_$spec->[0]" => $spec->[1],
        }, "Should have expected options with -$letter $spec->[1]";
    }
}

HARDLINKS: {
    local $defaults{keep_hours} = 2;
    local $defaults{directory} = 'whatever';

    local @ARGV = qw(--dir whatever -h 2 --hard-links);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
    }, "Should have expected options with --nohard-links";

    @ARGV = qw(--dir whatever -h 2 --nohard-links);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        hard_links => 0,
    }, "Should have expected options with --nohard-links";

    @ARGV = qw(--dir whatever -h 2 --no-hard-links);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        hard_links => 0,
    }, "Should have expected options with --no-hard-links";
}

VERBOSE: {
    local $defaults{keep_hours} = 2;
    local $defaults{directory} = 'whatever';

    local @ARGV = qw(--dir whatever -h 2 --verbose);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        verbose => 1,
    }, "Should have expected options with --verbose";

    @ARGV = qw(--dir whatever -h 2 --verbose --verbose);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        verbose => 2,
    }, "Should have expected options with --verbose --verbose";

    @ARGV = qw(--dir whatever -h 2 -V);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        verbose => 1,
    }, "Should have expected options with -V";

    @ARGV = qw(--dir whatever -h 2 -V -V);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        verbose => 2,
    }, "Should have expected options with -V -V";

    @ARGV = qw(--dir whatever -h 2 -VV);
    is_deeply +Pg::RollDump->_getopts, {
        %defaults,
        verbose => 2,
    }, "Should have expected options with -VV";
}

HELP: {
    my $mocker = Test::MockModule->new('Pg::RollDump');
    my @params;
    $mocker->mock( _pod2usage => sub { shift; @params = @_; die; });

    local @ARGV = ('--help');
    eval { Pg::RollDump->_getopts };
    is_deeply \@params, ['-exitval' => 0], 'Should get proper exit for --help';

    @ARGV = ('-H');
    eval { Pg::RollDump->_getopts };
    is_deeply \@params, ['-exitval' => 0], 'Should get proper exit for -H';

    @ARGV = ('--man');
    eval { Pg::RollDump->_getopts };
    is_deeply \@params, ['-sections' => '.+', '-exitval' => 0],
        'Should get proper exit for --man';

    @ARGV = ('-M');
    eval { Pg::RollDump->_getopts };
    is_deeply \@params, ['-sections' => '.+', '-exitval' => 0],
        'Should get proper exit for -M';
}
