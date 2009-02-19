#!/usr/bin/env perl

use strict;
use warnings;

use if (-d 't'), lib => 't';
use vars qw($COUNTER);

use Test::More tests => 24;

{
    use Devel::Pragma qw(on_require);

    use vars qw($COUNTER);

    BEGIN { $COUNTER = 1 }

    BEGIN {
        on_require(
            sub { ok($COUNTER < 3, 'pre-require callback called at compile-time ' . $COUNTER) },
            sub { ok($COUNTER < 3, 'post-require callback called at compile-time ' . $COUNTER); ++$COUNTER },
        );
    }

    use require_1;
    use require_1; # make sure requiring an already required module doesn't trigger another callback
    BEGIN { is(require_1::test(), 'require_1', 'require_1 loaded') }

    use require_2;
    use require_2; # make sure requiring an already required module doesn't trigger another callback
    BEGIN { is(require_2::test(), 'require_2', 'require_2 loaded') }

    BEGIN { is($COUNTER, 3, 'callbacks called twice') }

    require require_3; # runtime require should not be hooked
    is(require_3::test(), 'require_3', 'require_3 loaded');
}

{
    use Devel::Pragma qw(:all);

    BEGIN { my_hints->{'PRE_REQUIRE_EXCEPTION_CAUGHT'} = 1 }

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
                 'pre-require callback exception raises warning'
             );
        };

        eval 'use require_4';
        eval 'use require_4'; # make sure requiring an already required module doesn't trigger another callback
    }

    BEGIN {
        is(require_4::test(), 'require_4', 'require_4 loaded');
        is(my_hints->{'PRE_REQUIRE_EXCEPTION_CAUGHT'}, 1, 'exception in pre-require callback caught');
    }
}

{
    use Devel::Pragma qw(:all);

    BEGIN { my_hints->{'POST_REQUIRE_EXCEPTION_CAUGHT'} = 1 }

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
                 'post-require callback exception raises warning'
             );
        };

        eval 'use require_5';
        eval 'use require_5'; # make sure requiring an already required module doesn't trigger another callback
    }

    BEGIN {
        is(require_5::test(), 'require_5', 'require_5 loaded');
        is(my_hints->{'POST_REQUIRE_EXCEPTION_CAUGHT'}, 1, 'exception in post-require callback caught');
    }
}

{
    use Devel::Pragma qw(:all);

    use vars qw($ERR);

    BEGIN { my_hints->{'CLEANUP_AFTER_NESTED_EXCEPTION'} = 1 }

    BEGIN {
        on_require(
            sub { },
            sub {
                pass('post-require callback still called after require fails');
                die 'nested exception'
            }
        );
    }

    BEGIN {
        local $SIG{__WARN__} = sub {
            like($_[0],
                 qr{Devel::Pragma: exception in post-require callback: nested exception},
                 'post-require callback exception after require exception raises warning'
             );
        };

        eval 'use DevelPragmaNoSuchFile';
        $ERR = $@; # BEGIN blocks don't appear to propagate $@
    }

    like($ERR, qr{^Can't locate DevelPragmaNoSuchFile.pm}, 'nested require raises a fatal exception');

    BEGIN { is(my_hints->{'CLEANUP_AFTER_NESTED_EXCEPTION'}, 1, '%^H value still set after nested exception') }
}

{
    use Devel::Pragma qw(:all);

    BEGIN { $COUNTER = 0 }

    BEGIN {
        on_require(
            sub { is(++$COUNTER, 1, 'first pre-require callback called first') },
            sub { is(++$COUNTER, 3, 'first post-require callback called first') },
        );
    }

    BEGIN {
        on_require(
            sub { is(++$COUNTER, 2, 'second post-require callback called second') },
            sub { is(++$COUNTER, 4, 'second post-require callback called second') },
        );
    }

    use require_6;
    BEGIN { is(require_6::test(), 'require_6', 'require_6 loaded') }
}

# make sure the callbacks aren't called out of scope
use require_7;
BEGIN { is(require_7::test(), 'require_7', 'require_7 loaded') }
