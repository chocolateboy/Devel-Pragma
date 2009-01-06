#!/usr/bin/env perl

use strict;
use warnings;

use if (-d 't'), lib => 't';

use Test::More tests => 1;

# Confirm that values in %^H leak across file boundaries prior to patchlevel 33311 if Devel::Pragma is not used

# we can't assume brokenness as the tests may be
# run against bleadperls with change #33311 applied
my $already_fixed;

{
    BEGIN {
        $^H{'Devel::Pragma::Test'} = 1;
    }

    BEGIN {
        use test_1;
        $already_fixed = test_1::test();
    }

    use test_12;

    SKIP: {
        skip('patchlevel > 33311', 1) if ($already_fixed);
        ok (not(test_12::test()), '%^H leaks across file boundaries if Devel::Pragma is not used');
    }
}
