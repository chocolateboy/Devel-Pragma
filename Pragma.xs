#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS /* trap exceptions in pp_require */
#include "XSUB.h"

#define NEED_sv_2pv_flags
#include "ppport.h"

#include "hook_op_check.h"
#include "hook_op_annotation.h"

#define DEVEL_PRAGMA_ON_REQUIRE_KEY "Devel::Pragma::on_require"

#define DEVEL_PRAGMA_ON_REQUIRE_ENABLED(table, svp)                                                         \
    ((PL_hints & 0x20000) &&                                                                                \
    PL_hintgv &&                                                                                            \
    (table = GvHV(PL_hintgv)) &&                                                                            \
    (svp = hv_fetch(table, DEVEL_PRAGMA_ON_REQUIRE_KEY, sizeof(DEVEL_PRAGMA_ON_REQUIRE_KEY) - 1, FALSE)) && \
    *svp &&                                                                                                 \
    SvOK(*svp))

STATIC OP * devel_pragma_check_require(pTHX_ OP * o, void *user_data);
STATIC OP * devel_pragma_require(pTHX);
STATIC void devel_pragma_call(pTHX_ const char * const callback, HV * const hv);
STATIC void devel_pragma_enable_check_hooks();

STATIC hook_op_check_id devel_pragma_check_do_file_id = 0;
STATIC hook_op_check_id devel_pragma_check_require_id = 0;
STATIC OPAnnotationGroup DEVEL_PRAGMA_ANNOTATIONS = NULL;
STATIC U32 DEVEL_PRAGMA_CHECK_HOOKS_ENABLED = 0;

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

    if (!DEVEL_PRAGMA_ON_REQUIRE_ENABLED(table, svp)) {
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

    op_annotate(DEVEL_PRAGMA_ANNOTATIONS, o, NULL, NULL);
    o->op_ppaddr = devel_pragma_require;

    done:
        return o;
}

/* much of this is copypasta from pp_require in pp_ctl.c */
STATIC OP * devel_pragma_require(pTHX) {
    /* <copypasta> */
    dSP;
    SV * sv;
    HV *hh, *copy_of_hh;
    const char *name;
    STRLEN len;
    char * unixname;
    STRLEN unixlen;
#ifdef VMS
    int vms_unixname = 0;
#endif
    /* </copypasta> */

    OP * o = NULL;
    /* used as a boolean to determine whether any require callbacks are registered */
    SV ** callbacks = NULL;
    /* we always need this (to get the ppaddr to delegate to) so define it upfront */
    OPAnnotation *annotation = op_annotation_get(DEVEL_PRAGMA_ANNOTATIONS, PL_op);

    /* <copypasta> */
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

        if (svp) { /* already loaded: see pp_require */
            goto done;
        }
    }
    /* </copypasta> */

    hh = GvHV(PL_hintgv); /* %^H */
    copy_of_hh = newHVhv(hh); /* create a snapshot of %^H */
    callbacks = hv_fetchs(copy_of_hh, "Devel::Pragma::on_require", FALSE);

    /* make sure the on_require callbacks are still defined i.e. this is not being called at runtime */
    if (!callbacks) {
        hv_clear(copy_of_hh);
        hv_undef(copy_of_hh);
        goto done;
    }

    devel_pragma_call(aTHX_ "Devel::Pragma::_pre_require", copy_of_hh); /* invoke the pre-require callbacks */

    {
        dXCPT; /* set up variables for try/catch */

        XCPT_TRY_START {
            o = annotation->op_ppaddr(aTHX);
        } XCPT_TRY_END

        XCPT_CATCH {
            devel_pragma_call(aTHX_ "Devel::Pragma::_post_require", copy_of_hh); /* invoke the post-require callbacks */

            hv_clear(copy_of_hh);
            hv_undef(copy_of_hh);

            XCPT_RETHROW;
        }
    }

    devel_pragma_call(aTHX_ "Devel::Pragma::_post_require", copy_of_hh); /* invoke the post-require callbacks */

    hv_clear(copy_of_hh);
    hv_undef(copy_of_hh);

    return o;

    done:
        return annotation->op_ppaddr(aTHX);
}

STATIC void devel_pragma_enable_check_hooks() {
    if (DEVEL_PRAGMA_CHECK_HOOKS_ENABLED != 1) {
        devel_pragma_check_do_file_id = hook_op_check(OP_DOFILE, devel_pragma_check_require, NULL);
        devel_pragma_check_require_id = hook_op_check(OP_REQUIRE, devel_pragma_check_require, NULL);

        /* work around B::Hooks::OP::Check issue on 5.8.1 */
        SvREFCNT_inc(devel_pragma_check_do_file_id);
        SvREFCNT_inc(devel_pragma_check_require_id);

        DEVEL_PRAGMA_CHECK_HOOKS_ENABLED = 1;
    }
}

MODULE = Devel::Pragma                PACKAGE = Devel::Pragma

BOOT:
    DEVEL_PRAGMA_ANNOTATIONS = op_annotation_group_new();
    devel_pragma_enable_check_hooks();

void
DESTROY(SV * sv)
    PROTOTYPE:$
    CODE:
        PERL_UNUSED_VAR(sv); /* silence warning */
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
