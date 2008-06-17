package Devel::Hints::Lexical;

use 5.006;

use strict;
use warnings;

our $VERSION = '0.03';

use XSLoader;
use Scope::Guard;

use base qw(Exporter);

our @EXPORT_OK = qw(lexicalize_hh);

XSLoader::load(__PACKAGE__, $VERSION);

sub lexicalize_hh() {
    my $package = __PACKAGE__;

    return if ((($^H & 0x120000) == 0x120000) && ($^H{$package}));

    my $guard = Scope::Guard->new(\&_leave);

    # set HINT_LOCALIZE_HH (0x20000) + an unused bit (0x100000) so that
    # this module (which can't use itself) can work around the %^H bug

    $^H |= 0x120000;
    $^H{$guard} = $guard;
    $^H{$package} = 1;

    _enter();
}

1;

__END__

=head1 NAME

Devel::Hints::Lexical - make %^H lexically-scoped

=head1 SYNOPSIS

  package MyPragma;

  use Devel::Hints::Lexical qw(lexicalize_hh);

  sub import {
      lexicalize_hh;
      $^H{MyPragma} = 1;
  }

=head1 DESCRIPTION

Until perl change #33311, which isn't currently available in any stable perl release, %^H is dynamically scoped,
rather than lexically-scoped. This means that values set in %^H are visible in modules loaded by C<use>.
This makes pragmas leak from the scope in which they're meant to be enabled to scopes in which they're
not. This module fixes that by making %^H lexically scoped i.e. it prevents %^H leaking across file boundaries.

=head1 FUNCTIONS

=head2 lexicalize_hh

Devel::Hints::Lexical exports one function, C<lexicalize_hh>. This function enables bespoke versions of perl's
C<require> and C<do EXPR> functions in the current scope which clear %^H before it executes and restores the
previous %^H afterwards. Thus it can be thought of a lexically-scoped backport of change #33311.

Note that C<lexicalize_hh> also sets the $^H bit that "localizes" (or in this case "lexicalizes") %^H.

=head1 VERSION

0.03

=head1 SEE ALSO

=over

=item * L<Devel::Hints|Devel::Hints>

=item * L<perlpragma|perlpragma>

=item * http://tinyurl.com/45pwzo

=back

=head1 AUTHOR

chocolateboy <chocolate.boy@email.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by chocolateboy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
