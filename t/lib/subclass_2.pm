package subclass_2;

use base qw(superclass_2);

sub import {
    shift->SUPER::import();
}

1;
