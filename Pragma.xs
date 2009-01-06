/*
    context marshalling massively pessimizes extensions built for threaded perls e.g. Cygwin.

    define PERL_CORE rather than PERL_NO_GET_CONTEXT (see perlguts) because a) PERL_GET_NO_CONTEXT still incurs the
    overhead of an extra function call for each interpreter variable; and b) this is a drop-in replacement for a
    core op.
*/

#define PERL_CORE

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

static OP * (*old_require)(pTHX) = NULL;
static OP * my_require(pTHX);

OP * my_require(pTHX) {
    dSP;
    SV * sv;
    HV * hh, * new_hh;
    OP * o;

    sv = TOPs;

    if (SvNIOK(sv)) { /* exclude use 5 and use 5.008 &c. */
        goto done;
    }
            
#ifdef SvVOK
    if (SvVOK(sv)) { /* exclude use v5.008 and use 5.6.1 &c. */
        goto done;
    }
#endif

    /*
     * we need to set %^H to an empty hash rather than NULL as perl 5.10 has an assertion in scope.c
     * that expects it be non-NULL at scope's end
     */

    new_hh = newHV();
    hh = (HV *)SvREFCNT_inc((SV *)GvHV(PL_hintgv));

    SAVEHINTS();

    GvHV(PL_hintgv) = new_hh;

    o = CALL_FPTR(old_require)(aTHX);

    hv_clear(new_hh);
    hv_undef(new_hh);
    GvHV(PL_hintgv) = hh;

    return o;

    done:
    return CALL_FPTR(old_require)(aTHX);
}

MODULE = Devel::Pragma                PACKAGE = Devel::Pragma                

BOOT:
    /*
     * capture the function in scope when Devel::Pragma is bootstrapped.
     * usually, this will be Perl_pp_require, though, in principle,
     * it could be a bespoke function spliced in by another module.
     */
    old_require = PL_ppaddr[OP_REQUIRE];
    PL_ppaddr[OP_REQUIRE] = PL_ppaddr[OP_DOFILE] = my_require;

SV *
ccstash()
    PROTOTYPE:
    CODE:
        RETVAL = newSVpv(HvNAME(PL_curstash ? PL_curstash : PL_defstash), 0);
    OUTPUT:
        RETVAL

void
_scope()
    PROTOTYPE:
    CODE:
        XSRETURN_UV(PTR2UV(GvHV(PL_hintgv)));
