package lexical1;

use strict;
use warnings;

{
    # try to contaminate lexical2
    # this should succeed (unless #33311 has been applied, in which case the test is skipped)
    # because Devel::Pragma is lexically-scoped, and doesn't leak its
    # fix beyond the calling scope (leak.t)

    BEGIN {
        $^H |= 0x20000;
        $^H{'Devel::Pragma::Leak'} = 1
    }

    use lexical2;
}

sub test { lexical2::test() }

1;
