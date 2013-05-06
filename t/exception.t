#!/usr/bin/env perl

use strict;
use warnings;

use vars qw($ERR);

use Test::More tests => 3;

{
    use Devel::Pragma qw(hints);

    BEGIN { hints->{'Devel::Pragma::Test::Exception'} = 1 }
    BEGIN { is(hints->{'Devel::Pragma::Test::Exception'}, 1, '%^H value set before require') }
    BEGIN { eval 'use DevelPragmaNoSuchFile'; $ERR = $@ }; # BEGIN blocks don't appear to propagate $@

    like($ERR, qr{^Can't locate DevelPragmaNoSuchFile.pm}, 'require raised an exception');

    BEGIN { is(hints->{'Devel::Pragma::Test::Exception'}, 1, '%^H value still set after require exception') }
}
