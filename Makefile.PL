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
    NAME          => 'Devel::Pragma',
    VERSION_FROM  => 'lib/Devel/Pragma.pm',
    PREREQ_PM     => {
        'Test::More' => '0'
    },
    ABSTRACT_FROM => 'lib/Devel/Pragma.pm',
    AUTHOR        => 'chocolateboy <chocolate.boy@email.com>',
    LIBS          => [''],
    DEFINE        => '',
    INC           => '-I.',
    # OPTIMIZE      => $optimize,
    OPTIMIZE      => '-g',
    ($ExtUtils::MakeMaker::VERSION >= 6.31 ? (LICENSE => 'perl') : ()),
);
