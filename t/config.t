#!/usr/bin/perl -w

use strict;
use Test::More tests => 2;
#use Test::More 'no_plan';

my $CLASS;
BEGIN {
    $CLASS = 'Pg::RollDump';
    use_ok $CLASS or die;
}

my %config = (
    directory   => undef,
    hard_link   => undef,
    hard_links  => 1,
    help        => undef,
    keep_days   => undef,
    keep_hours  => undef,
    keep_months => undef,
    keep_weeks  => undef,
    keep_years  => undef,
    man         => undef,
    pg_dump     => "pg_dump",
    verbose     => 0,
    version     => undef,
);

DEFAULTS: {
    local @ARGV = ();
    is_deeply $CLASS->_config, \%config, 'Should have default config';
}
