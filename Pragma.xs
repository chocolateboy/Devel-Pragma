#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS /* trap exceptions in pp_require */
#include "XSUB.h"

#define NEED_sv_2pv_flags
#include "ppport.h"

#include "hook_op_check.h"
#include "hook_op_annotation.h"

#define DEVEL_PRAGMA_KEY "Devel::Pragma"

#define DEVEL_PRAGMA_ENABLED(table, svp)                                            \
    ((PL_hints & 0x20000) &&                                                        \
    (table = GvHV(PL_hintgv)) &&                                                    \
    (svp = hv_fetch(table, DEVEL_PRAGMA_KEY, strlen(DEVEL_PRAGMA_KEY), FALSE)) &&   \
    *svp &&                                                                         \
    SvOK(*svp))

STATIC OP * devel_pragma_check_require(pTHX_ OP * o, void *user_data);
STATIC OP * devel_pragma_require(pTHX);
STATIC void devel_pragma_call(pTHX_ const char * const callback, HV * const hv);
STATIC void devel_pragma_enter(pTHX);
STATIC void devel_pragma_hash_copy(pTHX_ HV *const from, HV *const to);
STATIC void devel_pragma_leave(pTHX);

STATIC hook_op_check_id devel_pragma_check_do_file_id = 0;
STATIC hook_op_check_id devel_pragma_check_require_id = 0;
STATIC OPAnnotationGroup DEVEL_PRAGMA_ANNOTATIONS = NULL;
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

STATIC void devel_pragma_call(pTHX_ const char * const callback, HV * const hv) {
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newRV_inc((SV *)hv)));
    PUTBACK;

    call_pv(callback, G_DISCARD);

    FREETMPS;
    LEAVE;
}

STATIC OP * devel_pragma_check_require(pTHX_ OP * o, void *user_data) {
    HV * table;
    SV ** svp;

    PERL_UNUSED_VAR(user_data);

    if (!DEVEL_PRAGMA_ENABLED(table, svp)) {
        goto done;
    }

    /* make sure it's still a require; the previous checker may have turned it into something else */
    if (!((o->op_type == OP_REQUIRE) || (o->op_type == OP_DOFILE))) {
        goto done;
    }

    /* <copypasta-ish> */
    if (o->op_type != OP_DOFILE) {
        if (o->op_flags & OPf_KIDS) { 
            SVOP * const kid = (SVOP*)cUNOPo->op_first;

            if (kid->op_type == OP_CONST) { /* weed out use VERSION */
                SV * const sv = kid->op_sv;

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
        }
    }
    /* </copypasta-ish> */

    (void)op_annotation_new(DEVEL_PRAGMA_ANNOTATIONS, o, NULL, NULL);
    o->op_ppaddr = devel_pragma_require;

    done:
        return o;
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
    HV *hh, *temp_hh;
    const char *name;
    STRLEN len;
    char * unixname;
    STRLEN unixlen;
#ifdef VMS
    int vms_unixname = 0;
#endif
    /* </copypasta> */

    OP * o = NULL;
    /* used as a boolean to determine whether any require callbacks are registered */;
    SV ** callbacks = NULL;
    OPAnnotation *annotation = op_annotation_get(DEVEL_PRAGMA_ANNOTATIONS, PL_op);

    /* <copypasta> */
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
            if (*svp == &PL_sv_undef) {
                goto done;
            } else {
                RETPUSHYES;
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
    hv_clear(hh); /* clear %^H (and ensure callbacks don't have access to the original) */

    callbacks = hv_fetchs(temp_hh, "Devel::Pragma(Hooks)", FALSE);

    if (callbacks) {
        devel_pragma_call(aTHX_ "Devel::Pragma::_pre_require", temp_hh); /* invoke the pre-require callbacks */
    }

    /*
     * this module is itself lexically-scoped, and therefore is disabled across file boundaries
     * we could eat our own dog food and do this in perl via on_require, but that's an unnecessary
     * slow down if no other callbacks are registered
     * */
    devel_pragma_leave(aTHX);

    {
        dXCPT; /* set up variables for try/catch */

        XCPT_TRY_START {
            o = CALL_FPTR(annotation->op_ppaddr)(aTHX);
        } XCPT_TRY_END

        XCPT_CATCH {
            devel_pragma_enter(aTHX); /* re-enable once the file has been compiled */
            devel_pragma_hash_copy(aTHX_ temp_hh, hh); /* restore %^H's values from the backup */

            if (callbacks) {
                devel_pragma_call(aTHX_ "Devel::Pragma::_post_require", temp_hh); /* invoke the post-require callbacks */
            }

            hv_clear(temp_hh);
            hv_undef(temp_hh);

            XCPT_RETHROW;
        }
    }

    devel_pragma_enter(aTHX); /* re-enable once the file has been compiled */
    devel_pragma_hash_copy(aTHX_ temp_hh, hh); /* restore %^H's values from the backup */

    if (callbacks) {
        devel_pragma_call(aTHX_ "Devel::Pragma::_post_require", temp_hh); /* invoke the post-require callbacks */
    }

    hv_clear(temp_hh);
    hv_undef(temp_hh);

    return o;

    done:
        return CALL_FPTR(annotation->op_ppaddr)(aTHX);
}

STATIC void devel_pragma_enter(pTHX) {
    if (DEVEL_PRAGMA_COMPILING != 0) {
        croak("Devel::Pragma: scope overflow");
    } else {
        DEVEL_PRAGMA_COMPILING = 1;
        devel_pragma_check_do_file_id = hook_op_check(OP_DOFILE, devel_pragma_check_require, NULL);
        devel_pragma_check_require_id = hook_op_check(OP_REQUIRE, devel_pragma_check_require, NULL);
        /* work around B::Hooks::OP::Check issue on 5.8.1 */
        SvREFCNT_inc(devel_pragma_check_do_file_id);
        SvREFCNT_inc(devel_pragma_check_require_id);
    }
}

STATIC void devel_pragma_leave(pTHX) {
    if (DEVEL_PRAGMA_COMPILING != 1) {
        croak("Devel::Pragma: scope underflow");
    } else {
        DEVEL_PRAGMA_COMPILING = 0;
        hook_op_check_remove(OP_DOFILE, devel_pragma_check_do_file_id);
        hook_op_check_remove(OP_REQUIRE, devel_pragma_check_require_id);
    }
}

MODULE = Devel::Pragma                PACKAGE = Devel::Pragma                

BOOT:
    DEVEL_PRAGMA_ANNOTATIONS = op_annotation_group_new();

void
END()
    CODE:
        if (DEVEL_PRAGMA_ANNOTATIONS) { /* make sure it was initialised */
            op_annotation_group_free(aTHX_ DEVEL_PRAGMA_ANNOTATIONS);
        }

SV *
ccstash()
    PROTOTYPE:
    CODE:
        /* FIXME: this should probably croak or return NULL at runtime */
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
