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

#ifndef HvRITER_set
#  define HvRITER_set(hv,r)        (HvRITER(hv) = r)
#endif
#ifndef HvEITER_set
#  define HvEITER_set(hv,r)        (HvEITER(hv) = r)
#endif

#ifndef HvRITER_get
#  define HvRITER_get HvRITER
#endif
#ifndef HvEITER_get
#  define HvEITER_get HvEITER
#endif

static OP * (*old_require)(pTHX) = NULL;
static OP * my_require(pTHX);
static void dp_restore_hh(pTHX_ HV *const hh, HV *const temp_hh);
static U32 SCOPE_DEPTH = 0;

/* TODO: more recent perls have a dedicated Perl_hv_copy_hints_hv in hv.c */
static void dp_restore_hh(pTHX_ HV *const hh, HV *const temp_hh) {
    HE *entry;
    const I32 riter = HvRITER_get(temp_hh);
    HE * const eiter = HvEITER_get(temp_hh);

    hv_iterinit(temp_hh);

    while ((entry = hv_iternext(temp_hh))) {
        (void)hv_store(hh, HeKEY(entry), HeKLEN(entry), newSVsv(HeVAL(entry)), HeHASH(entry));
    }

    HvRITER_set(temp_hh, riter);
    HvEITER_set(temp_hh, eiter);

    hv_clear(temp_hh);
    hv_undef(temp_hh);
}

/*
 * much of this is copypasta from pp_require in pp_ctl.c
 *
 * the various checks that delegate to the original function (goto done) ensure
 * we only modify %^H for code paths that use it i.e. we only modify %^H for
 * cases that reach the fix in patch #33311
 */
OP * my_require(pTHX) {
    dSP;
    SV * sv;
    OP * o;
    HV *hh, *temp_hh;
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
     * after much trial and error, it turns out the most reliable and least obtrusive way to
     * prevent %^H leaking across require() is to hv_clear it before the call and to restore its values
     * (taking care to preserve any magic) afterwards
     */
    hh = GvHV(PL_hintgv);
#ifdef hv_copy_hints_hv
    temp_hh = hv_copy_hints_hv(aTHX_ hh);
#else
#ifdef Perl_hv_copy_hints_hv
    temp_hh = Perl_hv_copy_hints_hv(aTHX_ hh);
#else
#ifdef newHVhv
    temp_hh = newHVhv(hh);
#else
    temp_hh = Perl_newHVhv(aTHX_ hh);
#endif
#endif
#endif
        
    hv_clear(hh); /* clear %^H */

    o = CALL_FPTR(old_require)(aTHX);

    dp_restore_hh(aTHX_ hh, temp_hh); /* restore %^H's values from the backup */

    return o;

    done:
    return CALL_FPTR(old_require)(aTHX);
}

MODULE = Devel::Pragma                PACKAGE = Devel::Pragma                

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

void
_enter()
    PROTOTYPE:
    CODE:
        if (SCOPE_DEPTH > 0) {
            ++SCOPE_DEPTH;
        } else {
            SCOPE_DEPTH = 1;
            /*
             * capture the function in scope when this is called.
             * usually, this will be Perl_pp_require, though, in principle,
             * it could be a bespoke function spliced in by another module.
             */
            if (PL_ppaddr[OP_REQUIRE] != my_require) {
                old_require = PL_ppaddr[OP_REQUIRE];
                PL_ppaddr[OP_REQUIRE] = PL_ppaddr[OP_DOFILE] = my_require;
            }
        }

void
_leave()
    PROTOTYPE:
    CODE:
        if (SCOPE_DEPTH == 0) {
            Perl_warn(aTHX_ "Devel::Pragma: scope underflow");
        }

        if (SCOPE_DEPTH > 1) {
            --SCOPE_DEPTH;
        } else {
            SCOPE_DEPTH = 0;
            PL_ppaddr[OP_REQUIRE] = PL_ppaddr[OP_DOFILE] = old_require;
        }
