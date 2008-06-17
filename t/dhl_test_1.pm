package dhl_test_1;

use strict;
use warnings;

our $test;

# 0 for failure if the key has leaked
# 1 for success if it hasn't
BEGIN { $test = exists($^H{'Devel::Hints::Lexical::Test'}) ? 0 : 1 }

sub test() { $test }

1;
