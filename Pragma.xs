#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS /* trap exceptions in mysubs_method and mysubs_method_named */
#include "XSUB.h"
#include "assert.h"

#define NEED_sv_2pv_flags
#include "ppport.h"

STATIC OP * devel_pragma_require(pTHX);
STATIC OP * (*old_require)(pTHX) = NULL;
STATIC void devel_pragma_enter(pTHX);
STATIC void devel_pragma_hash_copy(pTHX_ HV *const from, HV *const to);
STATIC void devel_pragma_leave(pTHX);

STATIC U32 DEVEL_PRAGMA_COMPILING = 0;

/* TODO: more recent perls have a dedicated Perl_hv_copy_hints_hv in hv.c */
STATIC void devel_pragma_hash_copy(pTHX_ HV *const from, HV *const to) {
    HE *entry;

    hv_iterinit(from);

    while ((entry = hv_iternext(from))) {
        const char * key;
        STRLEN len;
        key = HePV(entry, len);
        (void)hv_store(to, key, len, SvREFCNT_inc(newSVsv(HeVAL(entry))), HeHASH(entry));
    }
}

/*
 * much of this is copypasta from pp_require in pp_ctl.c
 *
 * the various checks that delegate to the original function (goto done) ensure
 * we only modify %^H for code paths that use it i.e. we only modify %^H for
 * cases that reach the fix in patch #33311
 */
STATIC OP * devel_pragma_require(pTHX) {
    /* <copypasta> */
    dSP;
    SV * sv;
    OP * o = NULL;
    HV *hh, *temp_hh;
    const char *name;
    STRLEN len;
    char * unixname;
    STRLEN unixlen;
#ifdef VMS
    int vms_unixname = 0;
#endif

    /*
     * if this is called at runtime, then the %^H for the COPs in the required file
     * was already cleared, so this is a no-op
     */
    if (!DEVEL_PRAGMA_COMPILING) { /* runtime; for some reason, IN_PERL_COMPILETIME doesn't work */
        goto done;
    }

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
    /* </copypasta> */

    /* 
     * after much trial and error, it turns out the most reliable and least obtrusive way to
     * prevent %^H leaking across require() is to hv_clear it before the call and to restore its values
     * (taking care to preserve any magic) afterwards
     */

    hh = GvHV(PL_hintgv); /* %^H */
    temp_hh = newHVhv(hh); /* copy %^H */
    hv_clear(hh); /* clear %^H */

    /* this module is itself lexically-scoped, and therefore is disabled across file boundaries */
    devel_pragma_leave(aTHX);

    {
        dXCPT; /* set up variables for try/catch */

        XCPT_TRY_START {
            o = CALL_FPTR(old_require)(aTHX);
        } XCPT_TRY_END

        XCPT_CATCH {
            devel_pragma_enter(aTHX); /* re-enable once the file has been compiled */
            devel_pragma_hash_copy(aTHX_ temp_hh, hh); /* restore %^H's values from the backup */

            hv_clear(temp_hh);
            hv_undef(temp_hh);

            XCPT_RETHROW;
        }
    }

    assert(DEVEL_PRAGMA_COMPILING == 0);
    devel_pragma_enter(aTHX); /* re-enable once the file has been compiled */
    assert(DEVEL_PRAGMA_COMPILING == 1);

    devel_pragma_hash_copy(aTHX_ temp_hh, hh); /* restore %^H's values from the backup */

    hv_clear(temp_hh);
    hv_undef(temp_hh);

    return o;

    done:
        return CALL_FPTR(old_require)(aTHX);
}

STATIC void devel_pragma_leave(pTHX) {
    if (DEVEL_PRAGMA_COMPILING != 1) {
        croak("Devel::Pragma: scope underflow");
    } else {
        assert(old_require);
        assert(old_require != devel_pragma_require);
        assert(PL_ppaddr[OP_REQUIRE] == devel_pragma_require);

        PL_ppaddr[OP_REQUIRE] = PL_ppaddr[OP_DOFILE] = old_require;
        DEVEL_PRAGMA_COMPILING = 0;
    }
}

STATIC void devel_pragma_enter(pTHX) {
    if (DEVEL_PRAGMA_COMPILING != 0) {
        croak("Devel::Pragma: scope overflow");
    } else {
        /*
         * capture the function in scope when this is called.
         * usually, this will be Perl_pp_require, though, in principle,
         * it could be a bespoke function spliced in by another module.
         */
        old_require = PL_ppaddr[OP_REQUIRE];
        assert(old_require != devel_pragma_require);
        PL_ppaddr[OP_REQUIRE] = PL_ppaddr[OP_DOFILE] = devel_pragma_require;
        DEVEL_PRAGMA_COMPILING = 1;
    }
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
xs_scope()
    PROTOTYPE:
    CODE:
        XSRETURN_UV(PTR2UV(GvHV(PL_hintgv)));

void
xs_enter()
    PROTOTYPE:
    CODE:
        devel_pragma_enter(aTHX);

void
xs_leave()
    PROTOTYPE:
    CODE:
        devel_pragma_leave(aTHX);
