#!/usr/bin/perl -w

use strict;
use Test::More tests => 1;
#use Test::More 'no_plan';

my $CLASS;
BEGIN {
    $CLASS = 'Pg::RollDump';
    use_ok $CLASS or die;
}
