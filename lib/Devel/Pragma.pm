package Devel::Pragma;

use 5.008;

use strict;
use warnings;

our $VERSION = '0.52';

use B::Hooks::EndOfScope;
use B::Hooks::OP::Annotation;
use B::Hooks::OP::Check;
use Carp qw(carp croak);
use Scalar::Util;
use XSLoader;

use base qw(Exporter);

our @EXPORT_OK = qw(my_hints new_scope ccstash scope fqname on_require);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

my $REQUIRE_KEY = 0;

XSLoader::load(__PACKAGE__, $VERSION);

# return a reference to the hints hash
sub my_hints() {
    # set HINT_LOCALIZE_HH (0x20000)
    $^H |= 0x20000;
    my $hints = \%^H;

    unless ($hints->{'Devel::Pragma'}) {
        $hints->{'Devel::Pragma'} = 1;
        xs_enter();
        on_scope_end \&xs_leave;
    }

    return $hints;
}

# make sure the "enable lexically-scoped %^H" flag is set (on by default in 5.10)
sub check_hints() {
    unless ($^H & 0x20000) {
        carp('Devel::Pragma: unexpected $^H (HINT_LOCALIZE_HH bit not set) - setting it now, but results may be unreliable');
    }
    return my_hints; # create it if it doesn't exist - in some perls, it starts out NULL
}

# return a unique integer ID for the current scope
sub scope() {
    check_hints;
    xs_scope();
}

# return a boolean indicating whether this is the first time "use MyPragma" has been called in this scope
sub new_scope(;$) {
    my $caller = shift || caller;

    check_hints;

    my $hints = my_hints();

    # this is %^H as an integer - it changes as scopes are entered/exited i.e. it's a unique
    # identifier for the currently-compiling scope (the scope in which new_scope 
    # is called)
    #
    # we don't need to stack/unstack it in %^H as %^H itself takes care of that
    # note: we need to call this *after* %^H is referenced (and possibly autovivified) above
    #
    # every time new_scope is called, we write this scope ID to $^H{"Devel::Pragma::Scope::$caller"}.
    # if $^H{"Devel::Pragma::Scope::$caller"} == scope() (i.e. the stored scope ID is the same as the
    # current scope ID), then we're augmenting the current scope; otherwise we're in a new scope - i.e.
    # a nested or outer scope that didn't previously "use MyPragma"

    my $current_scope = scope();
    my $id = "Devel::Pragma::Scope($caller)";
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

# given a short name (e.g. "foo"), expand it into a fully-qualified name with the caller's package prefixed
# e.g. "main::foo"
#
# if the name is already fully-qualified, return it unchanged
sub fqname ($;$) {
    my $name = shift;
    my ($package, $subname);

    $name =~ s{'}{::}g;

    if ($name =~ /::/) {
        ($package, $subname) = $name =~ m{^(.+)::(\w+)$};
    } else {
        my $caller = @_ ? shift : ccstash();
        ($package, $subname) = ($caller, $name);
    }

    return wantarray ? ($package, $subname) : "$package\::$subname";
}

# helper function: return true if $ref ISA $class - works with non-references, unblessed references and objects
sub _isa($$) {
    my ($ref, $class) = @_;
    return Scalar::Util::blessed($ref) ? $ref->isa($class) : ref($ref) eq $class;
}

# run registered callbacks before performing a compile-time require or do FILE
sub _pre_require($) {
    _callback(0, shift);
}

# run registered callbacks after performing a compile-time require or do FILE
sub _post_require($) {
    local $@; # if there was an exception on require, make sure we don't clobber it 
    _callback(1, shift)
}

# common code for pre- and post-require hooks
sub _callback($) {
    my ($index, $hints) = @_;

    if (my $hooks = $hints->{'Devel::Pragma(Hooks)'}) {
        for my $key (sort(keys(%$hooks))) {
            eval { $hooks->{$key}->[$index]->($hints) };

            if ($@) {
                my $stage = $index == 0 ? 'pre' : 'post';
                carp __PACKAGE__ . ": exception in $stage-require callback: $@";
            }
        }
    }
}

# register pre- and/or post-require hooks
# these are only called if the require occurs at compile-time
sub on_require($$) {
    my $hints = my_hints();

    for my $index (0 .. 1) {
        my $arg = $_[$index];
        my $ref = defined($arg) ? ref($arg) : '<undef>';

        croak(sprintf('%s: invalid arg %d; expected CODE, got %s', __PACKAGE__, $index + 1, $ref))
            unless ($arg and _isa($arg, 'CODE'));
    }

    $hints->{'Devel::Pragma(Hooks)'}->{++$REQUIRE_KEY} = [ @_ ];

    # return $REQUIRE_KEY;
    return;
}

# sub on_require_remove($) {
#     my $index = shift;
#     my $hints = my_hints();
#     my $hooks = $hints->{'Devel::Pragma(Hooks)'};
# 
#     croak(sprintf('%s: attempt to remove a non-existent require hook', __PACKAGE__))
#         unless ($hooks->{$index});
# 
#     delete $hooks->{$index};
# }

# make sure "enable lexically-scoped %^H" is set in older perls, and export the requested functions
sub import {
    my $class = shift;
    $^H |= 0x20000; # set HINT_LOCALIZE_HH (0x20000)
    $class->export_to_level(1, undef, @_);
}

1;

__END__

=head1 NAME

Devel::Pragma - helper functions for developers of lexical pragmas

=head1 SYNOPSIS

  package MyPragma;

  use Devel::Pragma qw(:all);

  sub import {
      my ($class, %options) = @_;
      my $hints = my_hints;   # lexically-scoped %^H
      my $caller = ccstash(); # currently-compiling stash

      unless ($hints->{MyPragma}) { # top-level
           $hints->{MyPragma} = 1;

           # disable/enable this pragma before/after compile-time requires
           on_require \&leave, \&enter;
      }

      if (new_scope($class)) {
          ...
      }

      my $scope_id = scope();
  }

=head1 DESCRIPTION

This module provides helper functions for developers of lexical pragmas. These can be used both in older versions of
perl (from 5.8.1), which have limited support for lexical pragmas, and in the most recent versions, which have improved
support.

=head1 EXPORTS

C<Devel::Pragma> exports the following functions on demand. They can all be imported at once by using the C<:all> tag. e.g.

    use Devel::Pragma qw(:all);

=head2 my_hints

Until perl change #33311, which isn't currently available in any stable
perl release, values set in %^H are visible in files compiled by C<use>, C<require> and C<do FILE>.
This makes pragmas leak from the scope in which they're meant to be enabled into scopes in which
they're not. C<my_hints> fixes that by making %^H lexically scoped i.e. it prevents %^H leaking
across file boundaries.

C<my_hints> installs versions of perl's C<require> and C<do FILE> builtins in the
currently-compiling scope which clear %^H before they execute and restore its values afterwards.
Thus it can be thought of a lexically-scoped backport of change #33311.

Note that C<my_hints> also sets the $^H bit that "localizes" (or in this case "lexicalizes") %^H.

The return value is a reference to %^H.

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

=head2 scope

This returns an integer that uniquely identifies the currently-compiling scope. It can be used to
distinguish or compare scopes.

A warning is issued if C<scope> (or C<new_scope>) is called in a context in which it doesn't make sense i.e. if the
scoped behaviour of C<%^H> has not been enabled - either by explicitly modifying C<$^H>, or by calling
C<use Devel::Pragma> or C<my_hints>.

=head2 ccstash

This returns the name of the currently-compiling stash. It can be used as a replacement for the scalar form of
C<caller> to provide the name of the package in which C<use MyPragma> is called. Unlike C<caller>, it
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

=head2 fqname

Given a subroutine name, usually supplied by the caller of the pragma's import method, this function returns
the name in package-qualified form. In addition, old-style C<'> separators are converted to new-style C<::>.

If the name contains no separators, then the optional calling package is prepended. If not supplied, the caller
defaults to the value returned by L<"ccstash">. If the name is already package-qualified,
then it is returned unchanged.

In list context, C<fqname> returns the package and unqualified subroutine name (e.g. 'main' and 'foo'), and in scalar
context it returns the package and sub name joined by '::' (e.g. 'main::foo').

e.g.

    package MyPragma;

    sub import {
        my ($class, @names) = @_;

        for my $name (@names) {
            my $fqname = fqname($name);
            say $fqname;
        }
    }

    package MySubPragma;

    use base qw(MyPragma);

    sub import { shift->SUPER::import(@_) }

    #!/usr/bin/env perl

    use MyPragma qw(foo Foo::Bar::baz Foo'Bar'baz Foo'Bar::baz);

    {
        package Some::Other::Package;

        use MySubPragma qw(quux);
    }

prints:

    main::foo
    Foo::Bar::baz
    Foo::Bar::baz
    Foo::Bar::baz
    Some::Other::Package::quux

=head2 on_require

This function allows pragmas to register pre- and post-C<require> (and C<do FILE>) callbacks.
These are called whenever C<require> or C<do FILE> OPs are executed at compile-time,
typically via C<use> statements.

C<on_require> takes two callbacks (i.e. anonymous subs or sub references), each of which is called
with a reference to C<%^H>. The first callback is called before C<require>, and the second is called
after C<require> has loaded and compiled its file. (If the file has already been loaded,
or the required value is a vstring rather than a file, then both the callbacks and the
clearance/restoration of C<%^H> are skipped.)

Multiple callbacks can be registered in a given scope, and they are called in the order in which they
are registered. Callbacks are unregistered automatically at the end of the (compilation of) the scope
in which they are registered.

C<on_require> callbacks can be used to disable/re-enable OP check hooks installed via
L<B::Hooks::OP::Check|B::Hooks::OP::Check> i.e. they can be used to make check hooks
lexically-scoped.

    package MyPragma;

    use Devel::Pragma qw(:all);

    sub import {
        my ($class, %args) = @_;
        my $hints = my_hints;

        unless ($hints->{MyPragma}) { # top-level
            $hints->{MyPragma} = 1;
            on_scope_end \&teardown;
            on_require \&teardown, \&setup;
            setup;
        }
    }

C<on_require> callbacks can also be used to rollback/restore lexical side-effects i.e. lexical features
whose scope extends beyond C<%^H> (like L<"my_hints">, C<on_require> implicitly renders C<%^H> lexically-scoped).

Fatal exceptions raised in C<on_require> callbacks are trapped and reported as warnings. If a fatal
exception is raised in the C<require> or C<do FILE> call, the post-C<require> callbacks are invoked
before that exception is thrown.

=head1 VERSION

0.52

=head1 SEE ALSO

=over

=item * L<pragma|pragma>

=item * L<perlpragma|perlpragma>

=item * L<perlvar|perlvar>

=item * L<B::Hooks::EndOfScope|B::Hooks::EndOfScope>

=item * L<B::Hooks::OP::Check|B::Hooks::OP::Check>

=item * L<B::Hooks::OP::PPAddr|B::Hooks::OP::PPAddr>

=item * L<B::Hooks::OP::Annotation|B::Hooks::OP::Annotation>

=item * L<Devel::Hints|Devel::Hints>

=item * http://tinyurl.com/45pwzo

=back

=head1 AUTHOR

chocolateboy <chocolate@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2009 by chocolateboy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
