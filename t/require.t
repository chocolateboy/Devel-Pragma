#!/usr/bin/env perl

use strict;
use warnings;

use lib qw(t/lib);
use vars qw($COUNTER $ERR);

use Test::More tests => 24;

# when tests fail here, it tends to be because one or more of them hasn't run, for whatever reason, rather than failures
# thus each test is numbered sequentially so that tests that haven't executed can easily be tracked down

{
    use Devel::Pragma qw(on_require);

    BEGIN { $COUNTER = 1 }

    BEGIN {
        on_require(
            sub { ok($COUNTER < 3, 'test 1: pre-require callback called at compile-time ' . $COUNTER) },
            sub { ok($COUNTER < 3, 'test 2: post-require callback called at compile-time ' . $COUNTER); ++$COUNTER },
        );
    }

    use require_1;
    use require_1; # make sure requiring an already required module doesn't trigger another callback
    BEGIN { is(require_1::test(), 'require_1', 'test 3: require_1 loaded') }

    use require_2;
    use require_2; # make sure requiring an already required module doesn't trigger another callback
    BEGIN { is(require_2::test(), 'require_2', 'test 4: require_2 loaded') }

    BEGIN { is($COUNTER, 3, 'test 5: callbacks called twice') }

    require require_3; # runtime require should not be hooked
    is(require_3::test(), 'require_3', 'test 6: require_3 loaded');
}

{
    use Devel::Pragma qw(:all);

    BEGIN { hints->{'PRE_REQUIRE_EXCEPTION_CAUGHT'} = 1 }

    BEGIN {
        on_require(
            sub { die "pre-require exception" },
            sub { },
        );
    }

    BEGIN {
        local $SIG{__WARN__} =  sub {
            like($_[0],
                 qr{Devel::Pragma: exception in pre-require callback: pre-require exception},
                 'test 7: exception in pre-require callback raises warning'
             );
        };

        eval 'use require_4';
        eval 'use require_4'; # make sure requiring an already required module doesn't trigger another callback
    }

    BEGIN {
        is(require_4::test(), 'require_4', 'test 8: require_4 loaded');
        is(hints->{'PRE_REQUIRE_EXCEPTION_CAUGHT'}, 1, 'test 9: exception in pre-require callback caught');
    }
}

{
    use Devel::Pragma qw(:all);

    BEGIN { hints->{'POST_REQUIRE_EXCEPTION_CAUGHT'} = 1 }

    BEGIN {
        on_require(
            sub { },
            sub { die "post-require exception" },
        );
    }

    BEGIN {
        local $SIG{__WARN__} = sub {
            like($_[0],
                 qr{Devel::Pragma: exception in post-require callback: post-require exception},
                 'test 10: exception in post-require callback raises warning'
             );
        };

        eval 'use require_5';
        eval 'use require_5'; # make sure requiring an already required module doesn't trigger another callback
    }

    BEGIN {
        is(require_5::test(), 'require_5', 'test 11: require_5 loaded');
        is(hints->{'POST_REQUIRE_EXCEPTION_CAUGHT'}, 1, 'test 12: exception in post-require callback caught');
    }
}

{
    use Devel::Pragma qw(:all);

    BEGIN { hints->{'CLEANUP_AFTER_NESTED_EXCEPTION'} = 1 }

    BEGIN {
        on_require(
            sub { },
            sub {
                pass('test 13: post-require callback still called after require fails');
                die 'nested exception'
            }
        );
    }

    BEGIN {
        local $SIG{__WARN__} = sub {
            like($_[0],
                 qr{Devel::Pragma: exception in post-require callback: nested exception},
                 'test 14: post-require callback exception after require exception raises warning'
             );
        };

        eval 'use DevelPragmaNoSuchFile';
        $ERR = $@; # BEGIN blocks don't appear to propagate $@
    }

    like($ERR, qr{^Can't locate DevelPragmaNoSuchFile.pm}, 'test 15: nested require raises a fatal exception');

    BEGIN { is(hints->{'CLEANUP_AFTER_NESTED_EXCEPTION'}, 1, 'test 16: %^H value still set after nested exception') }
}

{
    use Devel::Pragma qw(:all);

    BEGIN { $COUNTER = 0 }

    BEGIN {
        on_require(
            sub { is(++$COUNTER, 1, 'test 17: first pre-require callback called first') },
            sub { is(++$COUNTER, 3, 'test 18: first post-require callback called first') },
        );
    }

    BEGIN {
        on_require(
            sub { is(++$COUNTER, 2, 'test 19: second pre-require callback called second') },
            sub { is(++$COUNTER, 4, 'test 20: second post-require callback called second') },
        );
    }

    use require_6;
    BEGIN { is(require_6::test(), 'require_6', 'test 21: require_6 loaded') }
}

# make sure the callbacks aren't called out of scope
use require_7;
BEGIN { is(require_7::test(), 'require_7', 'test 22: require_7 loaded') }
