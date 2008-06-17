use 5.006;

use ExtUtils::MakeMaker;
use Config;

my $optimize;

if ($Config{gccversion}) {
    $optimize = '-O3 -Wall';
} elsif ($Config{osname} eq 'MSWin32') {
    $optimize = '-O2 -W4';
} else {
    $optimize = $Config{optimize};
}

# older MakeMakers don't correctly assess whether if.pm is installed
eval 'require "if.pm"';

if ($@) {
    warn "Warning: prerequisite if 0 not found", $/;
    exit 0;
}

WriteMakefile(
    NAME          => 'Devel::Hints::Lexical',
    VERSION_FROM  => 'lib/Devel/Hints/Lexical.pm',
    PREREQ_PM     => {
        'Scope::Guard' => '0.03',
        'Test::More'   => '0'
    },
    ABSTRACT_FROM => 'lib/Devel/Hints/Lexical.pm',
    AUTHOR        => 'chocolateboy <chocolate.boy@email.com>',
    LIBS          => [''],
    DEFINE        => '',
    INC           => '-I.',
    OPTIMIZE      => $optimize,
    ($ExtUtils::MakeMaker::VERSION >= 6.31 ? (LICENSE => 'perl') : ()),
);
