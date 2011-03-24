#!/usr/bin/perl -w

use strict;
use Test::More tests => 2;
#use Test::More 'no_plan';

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
    _pod2usage
    _getopts
);

