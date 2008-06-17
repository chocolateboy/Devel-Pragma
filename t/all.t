#!/usr/bin/env perl

use strict;
use warnings;

no warnings 'portable'; # suppress "v-string in use/require non-portable" warnings

use if (-d 't'), lib => 't'; 

use Test::More tests => 13;
use Devel::Hints::Lexical qw(my_hh);
use File::Spec;

# make sure use VERSION still works OK
use 5;         
use 5.006;
use 5.006_000;
use 5.6.0;
use v5.6.0;

my $already_fixed;

# we can't test brokenness as the tests may be
# run against bleadperls with change #33311 applied

{
    BEGIN {
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    BEGIN {
        use dhl_test_1;
        $already_fixed = dhl_test_1::test();
    }
}

{
    BEGIN {
        my_hh();
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    BEGIN {
	require dhl_test_2;
    }

    my $test = dhl_test_2::test();
    ok ($test, 'compile-time require');
}

{
    BEGIN {
        my_hh();
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    require dhl_test_3;

    my $test = dhl_test_3::test();
    ok ($test, 'runtime require');
}

{
    BEGIN {
        my_hh();
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    use dhl_test_4;

    my $test = dhl_test_4::test();
    ok ($test, 'use');
}

{
    BEGIN {
        my_hh();
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    use dhl_test_4;
    my $test = dhl_test_4::test();
    ok($test, 'reuse');
}

{
    BEGIN {
        my_hh();
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    BEGIN {
        my $file = (-d 't') ? File::Spec->catfile('t', 'dhl_test_5.pm') : 'dhl_test_5.pm';
        do $file;
    }

    my $test = dhl_test_5::test();
    ok($test, 'compile-time do FILE');
}

{
    BEGIN {
        my_hh();
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    BEGIN {
        my $file = (-d 't') ? File::Spec->catfile('t', 'dhl_test_6.pm') : 'dhl_test_6.pm';
        do $file;
    }

    my $test = dhl_test_6::test();
    ok($test, 'runtime do FILE');
}

eval {
    BEGIN {
        my_hh();
        $^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    use dhl_test_7;
    my $test = dhl_test_7::test();
    ok($test, 'eval BLOCK');
};

ok(not($@), 'eval BLOCK OK');

eval q|
    {
        BEGIN {
            my_hh();
            $^H{'Devel::Hints::Lexical::Test'} = 1;
        }

        use dhl_test_8;
        my $test = dhl_test_7::test();
        ok($test, 'eval EXPR');
    }
|;

ok(not($@), 'eval EXPR OK');

{
    {
        BEGIN {
            my_hh();
            $^H{'Devel::Hints::Lexical::Test'} = 1;
        }

        use dhl_test_9;

        my $test = dhl_test_9::test();
        ok ($test, 'scope');

        {
            use dhl_test_10;

            my $test = dhl_test_10::test();
            ok ($test, 'nested scope');
        }
    }

    BEGIN {
	$^H{'Devel::Hints::Lexical::Test'} = 1;
    }

    use dhl_test_11;

    my $test = dhl_test_11::test();

    SKIP: {
        skip('patchlevel > 33311', 1) if ($already_fixed);
        ok (not($test), 'outer scope');
    }
}
