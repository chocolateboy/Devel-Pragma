package Devel::Hints::Lexical;

use 5.006;

use strict;
use warnings;

our $VERSION = '0.10';

use XSLoader;
use Scope::Guard;

use base qw(Exporter);

our @EXPORT_OK = qw(my_hints new_scope);

XSLoader::load(__PACKAGE__, $VERSION);

sub new_scope() {
    # this is %^H as an integer - it changes as scopes are entered/exited i.e. it's a unique
    # identifier for the currently compiling scope (the scope in which new_scope 
    # is called)
    #
    # we don't need to stack/unstack it in %^H as %^H itself takes care of that
    # note: we need to call this *after* %^H is referenced (and possibly autovivified) by my_hints
    #
    # every time new_scope is called, we write this scope ID to $^H{"Devel::Hints::Lexical::Scope::$caller"}.
    # if $^H{"Devel::Hints::Lexical::Scope::$caller"} == _scope() (i.e. the stored scope ID is the same as the
    # current scope ID), then we're augmenting the current scope; otherwise we're in a new scope - i.e.
    # a nested or outer scope that didn't previously "use MyPragma"

    # set HINT_LOCALIZE_HH (0x20000) + an unused bit (0x80000000) so that
    # this module (which can't use itself) can work around the %^H bug

    $^H |= 0x80020000;
    $^H{'Devel::Hints::Lexical'} = 1;

    my $current_scope = _scope();
    my $key = 'Devel::Hints::Lexical::Scope::' . caller;
    my $old_scope = exists($^H{$key}) ? $^H{$key} : 0;
    my $new_scope; # is this a scope in which new_scope has not previously been called?

    if ($current_scope == $old_scope) {
        $new_scope = 0;
    } else {
        $^H{$key} = $current_scope;
        $new_scope = 1;
    }

    return $new_scope;
}

sub my_hints() {
    if (new_scope) {
        my $guard = Scope::Guard->new(\&_leave);

        $^H{$guard} = $guard;

        _enter();
    }

    return \%^H;
}

1;

__END__

=head1 NAME

Devel::Hints::Lexical - lexical pragma utils

=head1 SYNOPSIS

  package MyPragma;

  use Devel::Hints::Lexical qw(my_hints);

  sub import {
      my $hints = my_hints;
      $hints->{MyPragma} = 1;
  }

=head1 DESCRIPTION

This module provides helper functions for developers of lexical pragmas. These can be used both in older versions of
perl (from 5.6.0), which have limited support for lexical pragmas, and in the most recent versions, which have improved
support.

=head1 EXPORTS

=head2 my_hints

Until perl change #33311, which isn't currently available in any stable perl release, %^H is dynamically-scoped,
rather than lexically-scoped. This means that values set in %^H are visible in modules loaded by C<use>.
This makes pragmas leak from the scope in which they're meant to be enabled into scopes in which they're
not. C<my_hints> fixes that by making %^H lexically scoped i.e. it prevents %^H leaking across file boundaries.

C<my_hints> installs versions of perl's C<require> and C<do EXPR> builtins in the
currently-compiling scope which clear %^H before they execute and restore the previous %^H afterwards.
Thus it can be thought of a lexically-scoped backport of change #33311.

Note that C<my_hints> also sets the $^H bit that "localizes" (or in this case "lexicalizes") %^H.

The return value is a reference to %^H.

=head2 new_scope

This function returns true if the currently-compiling scope differs from the scope being compiled the last
time C<new_scope> was called. Subsequent calls will return false while the same scope is being compiled.

=head1 VERSION

0.10

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
