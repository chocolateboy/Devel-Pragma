#!/usr/bin/env perl

use strict;
use warnings;

no warnings 'portable'; # suppress "v-string in use/require non-portable" warnings

use if (-d 't'), lib => 't'; 

use Test::More tests => 25;
use Devel::Pragma qw(my_hints);
use File::Spec;

# make sure use VERSION still works OK
use 5;         
use 5.006;
use 5.006_000;
use 5.6.0;
use v5.6.0;

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
}

{
    BEGIN {
        my_hints();
        $^H{'Devel::Pragma::Test'} = 1;
    }

    BEGIN {
        require test_2;
    }

    BEGIN {
        is($^H{'Devel::Pragma::Test'}, 1, "compile-time require doesn't clobber %^H");
    }

    ok (test_2::test(), 'compile-time require');
}

{
    BEGIN {
        my_hints();
        $^H{'Devel::Pragma::Test'} = 1;
    }

    require test_3;

    ok (test_3::test(), 'runtime require');
}

{
    BEGIN {
        my_hints();
        $^H{'Devel::Pragma::Test'} = 1;
    }

    use test_4;

    BEGIN {
        is($^H{'Devel::Pragma::Test'}, 1, "use doesn't clobber %^H");
    }

    ok (test_4::test(), 'use');
}

{
    BEGIN {
        my_hints();
        $^H{'Devel::Pragma::Test'} = 1;
    }

    use test_4;

    BEGIN {
        is($^H{'Devel::Pragma::Test'}, 1, "reuse doesn't clobber %^H");
    }

    ok(test_4::test(), 'reuse');
}

{
    BEGIN {
        my_hints();
        $^H{'Devel::Pragma::Test'} = 1;
    }

    BEGIN {
        my $file = (-d 't') ? File::Spec->catfile('t', 'test_5.pm') : 'test_5.pm';
        do $file;
    }

    BEGIN {
        is($^H{'Devel::Pragma::Test'}, 1, "compile-time do FILE doesn't clobber %^H");
    }

    ok(test_5::test(), 'compile-time do FILE');
}

{
    BEGIN {
        my_hints();
        $^H{'Devel::Pragma::Test'} = 1;
    }

    my $file = (-d 't') ? File::Spec->catfile('t', 'test_6.pm') : 'test_6.pm';
    do $file;

    ok(test_6::test(), 'runtime do FILE');
}

eval {
    BEGIN {
        my_hints();
        $^H{'Devel::Pragma::Test'} = 1;
    }

    use test_7;

    BEGIN {
        is($^H{'Devel::Pragma::Test'}, 1, "eval block doesn't clobber %^H");
    }

    ok(test_7::test(), 'eval BLOCK');
};

ok(not($@), 'eval BLOCK OK');

eval q|
    {
        BEGIN {
            my_hints();
            $^H{'Devel::Pragma::Test'} = 1;
        }

        use test_8;

        BEGIN {
            is($^H{'Devel::Pragma::Test'}, 1, "eval EXPR doesn't clobber %^H");
        }

        ok(test_7::test(), 'eval EXPR');
    }
|;

ok(not($@), 'eval EXPR OK');

{
    {
        BEGIN {
            my_hints();
            $^H{'Devel::Pragma::Test'} = 1;
        }

        use test_9;

        BEGIN {
            is($^H{'Devel::Pragma::Test'}, 1, "scope: %^H isn't clobbered");
        }

        ok (test_9::test(), 'scope');

        {
            use test_10;

            BEGIN {
                is($^H{'Devel::Pragma::Test'}, 1, "nested scope: %^H isn't clobbered");
            }

            ok (test_10::test(), 'nested scope');
        }

        use test_11;

        BEGIN {
            is($^H{'Devel::Pragma::Test'}, 1, "scope again: %^H isn't clobbered");
        }

        ok (test_11::test(), 'scope again');
    }

    BEGIN {
        $^H{'Devel::Pragma::Test'} = 1;
    }

    use test_12;

    SKIP: {
        skip('patchlevel > 33311', 1) if ($already_fixed);
        ok (not(test_12::test()), 'outer scope');
    }
}

{
    BEGIN {
        $^H{'Devel::Pragma::Test'} = 1;
    }

    ok (my_hints->{'Devel::Pragma'}, 'returns a reference to %^H');
    ok (my_hints->{'Devel::Pragma'}, 'returns a reference to %^H when already in scope');
}
