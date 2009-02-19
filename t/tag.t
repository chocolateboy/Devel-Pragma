#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;
use Devel::Pragma qw(:all);

ok(defined &ccstash, 'ccstash is exported by :all');
ok(defined &scope, 'scope is exported by :all');
ok(defined &new_scope, 'new_scope is exported by :all');
ok(defined &my_hints, 'my_hints is exported by :all');
ok(defined &fqname, 'fqname is exported by :all');
ok(defined &on_require, 'on_require is exported by :all');
