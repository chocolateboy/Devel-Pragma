package Devel::Pragma;

use 5.006;

use strict;
use warnings;

our $VERSION = '0.21';

use XSLoader;

use base qw(Exporter);

our @EXPORT_OK = qw(my_hints new_scope ccstash);
our @EXPORT_TAGS = (':all' => [ @EXPORT_OK ]);

XSLoader::load(__PACKAGE__, $VERSION);

sub my_hints() {
    # set HINT_LOCALIZE_HH (0x20000)
    $^H |= 0x20000;
    return \%^H;
}

sub new_scope(;$) {
    my $caller = shift || caller;
    my $hints = my_hints;

    # this is %^H as an integer - it changes as scopes are entered/exited i.e. it's a unique
    # identifier for the currently-compiling scope (the scope in which new_scope 
    # is called)
    #
    # we don't need to stack/unstack it in %^H as %^H itself takes care of that
    # note: we need to call this *after* %^H is referenced (and possibly autovivified) above
    #
    # every time new_scope is called, we write this scope ID to $^H{"Devel::Pragma::Scope::$caller"}.
    # if $^H{"Devel::Pragma::Scope::$caller"} == _scope() (i.e. the stored scope ID is the same as the
    # current scope ID), then we're augmenting the current scope; otherwise we're in a new scope - i.e.
    # a nested or outer scope that didn't previously "use MyPragma"

    my $current_scope = _scope();
    my $id = "Devel::Pragma::Scope::$caller";
    my $old_scope = exists($hints->{$id}) ? $hints->{$id} : 0;
    my $new_scope; # is this a scope in which new_scope has not previously been called?

    if ($current_scope == $old_scope) {
        $new_scope = 0;
    } else {
        $hints->{$id} = $current_scope;
        $new_scope = 1;
    }

    return $new_scope;
}

1;

__END__

=head1 NAME

Devel::Pragma - helper functions for developers of lexical pragmas

=head1 SYNOPSIS

  package MyPragma;

  use Devel::Pragma qw(my_hints ccstash new_scope);

  sub import {
      my ($class, %options) = @_;
      my $hints = my_hints;   # lexically-scoped %^H
      my $caller = ccstash(); # currently-compiling stash

      $hints->{MyPragma} = 1;

      if (new_scope($class)) {
          ...
      }
  }

=head1 DESCRIPTION

This module provides helper functions for developers of lexical pragmas. These can be used both in older versions of
perl (from 5.6.0), which have limited support for lexical pragmas, and in the most recent versions, which have improved
support.

In addition to the helper functions, this module applies a global fix that makes %^H lexically-scoped
rather than dynamically-scoped. Until perl change #33311, which isn't currently available in any stable
perl release, values set in %^H are visible in modules loaded by C<use>, C<require> and C<do FILE>.
This makes pragmas leak from the scope in which they're meant to be enabled into scopes in which
they're not. This module applies a fix which ensures that values in %^H no longer leak across file boundaries.

=head1 EXPORTS

Devel::Pragma exports the following functions on demand. They can all be imported at once by using the C<:all> tag. e.g.

    use Devel::Pragma qw(:all);

=head2 my_hints

C<my_hints> sets the appropriate flag to make %^H lexically-scoped, and returns a reference to %^H. More
precisely, it sets the flag in $^H that makes %^H copy and restore its values as scopes are entered and exited.
The fix that clears %^H before C<use>, C<require> and C<do FILE> statements is applied globally when
the Devel::Pragma module is first loaded.

=head2 new_scope

This function returns true if the currently-compiling scope differs from the scope being compiled the last
time C<new_scope> was called. Subsequent calls will return false while the same scope is being compiled.

C<new_scope> takes an optional parameter that is used to uniquely identify its caller. This should usually be
supplied as the pragma's class name unless C<new_scope> is called by a module that is not intended
to be subclassed. e.g.

    package MyPragma;

    sub import {
        my ($class, %options) = @_;

        if (new_scope($class)) {
            ...
        }
    }

If not supplied, the identifier defaults to the name of the calling package.

=head2 ccstash

This returns the name of the currently-compiling stash. It can be used as a replacement for the scalar form of
C<caller> to provide the name of the package in which C<use MyPragma> is called. Unlike C<caller> it
returns the same value regardless of the number of intervening calls before C<MyPragma::import>
is reached.

e.g. given a pragma:

    package MySuperPragma;

    use Devel::Hints qw(ccstash);

    sub import {
        my ($class, %options) = @_;
        my $caller = ccstash();

        no strict 'refs';

        *{"$caller\::whatever"} = ... ;
    }

and a subclass:

    package MySubPragma

    use base qw(MySuperPragma);

    sub import {
        my ($class, %options) = @_;
        $class->SUPER::import(...);
    }

and a script that uses the subclass:

    #!/usr/bin/env perl

    use MySubPragma;

- the C<ccstash> call in C<MySuperPragma::import> returns the name of the package that's being compiled when
the call to C<MySuperPragma::import> (via C<MySubPragma::import>) takes place i.e. C<main> in this case.

=head1 VERSION

0.21

=head1 SEE ALSO

=over

=item * L<pragma|pragma>

=item * L<perlpragma|perlpragma>

=item * L<perlvar|perlvar>

=item * L<B::Hooks::EndOfScope|B::Hooks::EndOfScope>

=item * L<Devel::Hints|Devel::Hints>

=item * http://tinyurl.com/45pwzo

=back

=head1 AUTHOR

chocolateboy <chocolate.boy@email.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2009 by chocolateboy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
