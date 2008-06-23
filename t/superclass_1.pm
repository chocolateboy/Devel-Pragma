package superclass_1;

use Devel::Pragma qw(ccstash);

my $test;

sub import { $test = ccstash() }
sub test { $test }

1;
