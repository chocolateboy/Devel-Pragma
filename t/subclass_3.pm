package subclass_3;

use base qw(superclass_3);

sub import {
    shift->SUPER::import();
}

1;
