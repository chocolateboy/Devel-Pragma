# Devel::Pragma

[![Build Status](https://travis-ci.org/chocolateboy/Devel-Pragma.svg)](https://travis-ci.org/chocolateboy/Devel-Pragma)
[![CPAN Version](https://badge.fury.io/pl/Devel-Pragma.svg)](https://badge.fury.io/pl/Devel-Pragma)

<!-- toc -->

- [NAME](#name)
- [SYNOPSIS](#synopsis)
- [DESCRIPTION](#description)
- [EXPORTS](#exports)
  - [ccstash](#ccstash)
  - [fqname](#fqname)
  - [hints](#hints)
  - [new_scope](#new_scope)
  - [scope](#scope)
- [VERSION](#version)
- [SEE ALSO](#see-also)
- [AUTHOR](#author)
- [COPYRIGHT AND LICENSE](#copyright-and-license)

<!-- tocstop -->

# NAME

Devel::Pragma - helper functions for developers of lexical pragmas

# SYNOPSIS

```perl
package MyPragma;

use Devel::Pragma qw(:all);

sub import {
    my ($class, %options) = @_;
    my $hints  = hints;        # the builtin (%^H) used to implement lexical pragmas
    my $caller = ccstash();    # the name of the currently-compiling package (stash)

    unless ($hints->{MyPragma}) { # top-level
        $hints->{MyPragma} = 1;
    }

    if (new_scope($class)) {
        ...
    }

    my $scope_id = scope();
}
```

# DESCRIPTION

This module provides helper functions for developers of lexical pragmas (and a
few functions that may be useful to non-pragma developers as well).

Pragmas can be used both in older versions of perl (from 5.8.1), which had
limited support, and in the most recent versions, which have improved support.

# EXPORTS

Devel::Pragma exports the following functions on demand. They can all be
imported at once by using the `:all` tag. e.g.

```perl
use Devel::Pragma qw(:all);
```

## ccstash

Returns the name of the currently-compiling package (stash). It only works
inside code that's being `required`, either in a `BEGIN` block via `use` or at
runtime. In practice, its use should be restricted to compile-time i.e.
`import` methods and any other methods/functions that can be traced back to
`import`.

When called from code that isn't being `require`d, it returns undef.

It can be used as a replacement for the scalar form of `caller` to provide the
name of the package in which `use MyPragma` is called. Unlike `caller`, it
returns the same value regardless of the number of intervening calls before
`MyPragma::import` is reached.

```perl
package Caller;

use Callee;

package Callee;

use Devel::Pragma qw(ccstash);

sub import {
    A();
}

sub A() {
    B();
}

sub B {
    C();
}

sub C {
    say ccstash; # Caller
}
```

## fqname

Takes a subroutine name and an optional caller (package name). If no caller is
supplied, it defaults to [`ccstash`](#ccstash), which requires `fqname` to be
called from `import` (or a function/method that can be traced back to
`import`).

It returns the supplied name in package-qualified form. In addition, old-style
`'` separators are converted to new-style `::`.

If the name contains no separators, then the `caller`/`ccstash` package name is
prepended. If the name is already package-qualified, it is returned unchanged.

In list context, `fqname` returns the package and unqualified subroutine name
(e.g. "Foo::Bar" and "baz"), and in scalar context it returns the package and
sub name joined by "::" (e.g. "Foo::Bar::baz"). e.g.

```perl
package MyPragma::Loader;

use MyPragma (\&coderef, 'foo', 'MyPragmaLoader::bar');

package MyPragma;

sub import {
    my ($class, @listeners) = @_;
    my @subs;

    for my $listener (@listeners) {
        push @subs, handle_sub($listener);
    }
}

sub handle_sub {
    my $sub = shift

    if (ref($ub) eq 'CODE') {
        return $sub;
    } else {
        handle_name($sub);
    }
}

sub handle_name {
    my ($package, $name) = fqname($name); # uses ccstash e.g. foo -> MyPragma::Loader::foo
    my $sub = $package->can($name);
    die "no such sub: $package\::$name" unless ($sub);
    return $sub;
}
```

## hints

This function enables the scoped behaviour of the hints hash (`%^H`) and then
returns a reference to it.

The hints hash is a compile-time global variable (which is also available at
runtime in recent perls) that can be used to implement lexically-scoped
features and pragmas. This function provides a convenient way to access this
hash without the need to perform the bit-twiddling that enables it on older
perls. In addition, this module loads
[Lexical::SealRequireHints](https://metacpan.org/pod/Lexical::SealRequireHints),
which implements bugfixes that are required for the correct operation of the
hints hash on older perls (&lt; 5.12.0).

Typically, `hints` should be called from a pragma's `import` (and optionally
`unimport`) method:

```perl
package MyPragma;

use Devel::Pragma qw(hints);

sub import {
    my $class = shift;
    my $hints = hints;

    if ($hints->{MyPragma}) {
        # ...
    } else {
        $hints->{MyPragma} = ...;
    }

    # ...
}
```

## new_scope

This function returns true if the currently-compiling scope differs from the
scope being compiled the last time `new_scope` was called. Subsequent calls
will return false while the same scope is being compiled.

`new_scope` takes an optional parameter that is used to uniquely identify its
caller. This should usually be supplied as the pragma's class name unless
`new_scope` is called by a module that is not intended to be subclassed. e.g.

```perl
package MyPragma;

sub import {
    my ($class, %options) = @_;

    if (new_scope($class)) {
        ...
    }
}
```

If not supplied, the identifier defaults to the name of the calling package.

## scope

This returns an integer that uniquely identifies the currently-compiling scope.
It can be used to distinguish or compare scopes.

A warning is issued if `scope` (or `new_scope`) is called in a context in which
it doesn't make sense i.e. if the scoped behaviour of `%^H` has not been
enabled - either by explicitly modifying `$^H`, or by calling
[`hints`](#hints).

# VERSION

1.1.0

# SEE ALSO

- [Devel::Hints](https://metacpan.org/pod/Devel::Hints)
- [Lexical::Hints](https://metacpan.org/pod/Lexical::Hints)
- [Lexical::SealRequireHints](https://metacpan.org/pod/Lexical::SealRequireHints)
- [perlpragma](https://metacpan.org/pod/perlpragma)
- [pragma](https://metacpan.org/pod/pragma)
- [perl.perl5.porters - %^H affecting outside file scopes](https://tinyurl.com/45pwzo)

# AUTHOR

[chocolateboy](mailto:chocolate@cpan.org)

# COPYRIGHT AND LICENSE

Copyright © 2008-2020 by chocolateboy.

This is free software; you can redistribute it and/or modify it under the terms of the
[Artistic License 2.0](https://www.opensource.org/licenses/artistic-license-2.0.php).
