package superclass_3;

use Devel::Pragma qw(ccstash);

my $test;

sub import { $test = ccstash() }
sub test { $test }

1;
