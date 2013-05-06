#!/usr/bin/env perl

use strict;
use warnings;

use lib qw(t/lib);

use Test::More tests => 5;

use subclass_1;

Test::More::is(subclass_1->test, 'main', 'default main');

package main;

use subclass_2;

Test::More::is(subclass_2->test, 'main', 'explicit main');

package Some::Other::Package;

use subclass_3;

Test::More::is(subclass_3->test, 'Some::Other::Package', 'new package');

{
    package nested;

    use subclass_4;

    Test::More::is(subclass_4->test, 'nested', 'nested package');
}

use subclass_5;

Test::More::is(subclass_5->test, 'Some::Other::Package', 'back to previous package');
