package subclass_1;

use base qw(superclass_1);

sub import {
    shift->SUPER::import();
}

1;
