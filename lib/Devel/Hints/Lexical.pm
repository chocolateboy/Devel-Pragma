package Devel::Hints::Lexical;

use 5.006;

use strict;
use warnings;

our $VERSION = '0.08';

use XSLoader;
use Scope::Guard;

use base qw(Exporter);

our @EXPORT_OK = qw(lexicalize_hh my_hh my_hints);

XSLoader::load(__PACKAGE__, $VERSION);

sub my_hints() {
    my $package = __PACKAGE__;

    return if ((($^H & 0x80020000) == 0x80020000) && ($^H{$package}));

    my $guard = Scope::Guard->new(\&_leave);

    # set HINT_LOCALIZE_HH (0x20000) + an unused bit (0x80000000) so that
    # this module (which can't use itself) can work around the %^H bug

    $^H |= 0x80020000;
    $^H{$guard} = $guard;
    $^H{$package} = 1;

    _enter();

    return \%^H;
}

BEGIN { *lexicalize_hh = *my_hh = \&my_hints }

1;

__END__

=head1 NAME

Devel::Hints::Lexical - make %^H lexically-scoped

=head1 SYNOPSIS

  package MyPragma;

  use Devel::Hints::Lexical qw(my_hints);

  sub import {
      my $hints = my_hints;
      $hints->{MyPragma} = 1;
  }

=head1 DESCRIPTION

Until perl change #33311, which isn't currently available in any stable perl release, %^H is dynamically-scoped,
rather than lexically-scoped. This means that values set in %^H are visible in modules loaded by C<use>.
This makes pragmas leak from the scope in which they're meant to be enabled into scopes in which they're
not. This module fixes that by making %^H lexically scoped i.e. it prevents %^H leaking across file boundaries.

=head1 FUNCTIONS

=head2 my_hints

C<Devel::Hints::Lexical> exports one function, which can be called or imported as either C<my_hints>, C<my_hh>, or
C<lexicalize_hh>. This function installs versions of perl's C<require> and C<do EXPR> builtins in the
currently-compiling scope which clear %^H before they execute and restore the previous %^H afterwards.
Thus it can be thought of a lexically-scoped backport of change #33311.

Note that C<my_hints> also sets the $^H bit that "localizes" (or in this case "lexicalizes") %^H.

The return value is a reference to %^H.

=head1 VERSION

0.08

=head1 SEE ALSO

=over

=item * L<perlpragma|perlpragma>

=item * L<perlvar|perlvar>

=item * L<Devel::Hints|Devel::Hints>

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
