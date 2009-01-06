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

#define NEED_sv_2pv_flags
#include "ppport.h"

static OP * (*old_require)(pTHX) = NULL;
static OP * my_require(pTHX);

/*
 * much of this is copypasta from pp_require in pp_ctl.c
 * this ensures we leave %^H intact unless absolutely necessary
 */
OP * my_require(pTHX) {
    dSP;
    SV * sv;
    OP * o;
    HV *old_hh, *new_hh;
    const char *name;
    STRLEN len;
    char * unixname;
    STRLEN unixlen;
#ifdef VMS
    int vms_unixname = 0;
#endif

    sv = TOPs;

    if (PL_op->op_type != OP_DOFILE) { 
        if (SvNIOKp(sv)) { /* exclude use 5 and use 5.008 &c. */
            goto done;
        }
                
#ifdef SvVOK
        if (SvVOK(sv)) { /* exclude use v5.008 and use 5.6.1 &c. */
            goto done;
        }
#endif

        if (!SvPOKp(sv)) { /* err on the side of caution */
            goto done;
        }
    }

    name = SvPV_const(sv, len);
    if (!(name && (len > 0) && *name)) {
        goto done;
    }

    TAINT_PROPER("require");

#ifdef VMS
    /* The key in the %ENV hash is in the syntax of file passed as the argument
     * usually this is in UNIX format, but sometimes in VMS format, which
     * can result in a module being pulled in more than once.
     * To prevent this, the key must be stored in UNIX format if the VMS
     * name can be translated to UNIX.
     */
    if ((unixname = tounixspec(name, NULL)) != NULL) {
        unixlen = strlen(unixname);
        vms_unixname = 1;
    }
    else
#endif
    {
        /* if not VMS or VMS name can not be translated to UNIX, pass it
         * through.
         */
        unixname = (char *) name;
        unixlen = len;
    }

    if (PL_op->op_type == OP_REQUIRE) {
        SV * const * const svp = hv_fetch(GvHVn(PL_incgv), unixname, unixlen, 0);
                                          
        if (svp) {
            if (*svp != &PL_sv_undef) {
                RETPUSHYES;
            } else {
                goto done;
            }
        }
    }

    /*
     * we need to set %^H to an empty hash rather than NULL as perl 5.10 has an assertion in scope.c
     * that expects it be non-NULL at scope's end
     */

    new_hh = newHV();
    old_hh = GvHV(PL_hintgv);

    SAVEHINTS();

    GvHV(PL_hintgv) = new_hh;

    o = CALL_FPTR(old_require)(aTHX);

    hv_clear(new_hh);
    hv_undef(new_hh);

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
    if (old_require != my_require) {
        PL_ppaddr[OP_REQUIRE] = PL_ppaddr[OP_DOFILE] = my_require;
    }

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
