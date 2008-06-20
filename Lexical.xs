#define PERL_CORE

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

static OP * (*old_ck_require)(pTHX_ OP * o) = NULL;
static OP * devel_hints_lexical_ck_require(pTHX_ OP * o);
static OP * devel_hints_lexical_require(pTHX);

static U32 DEVEL_HINTS_LEXICAL_SCOPE_DEPTH = 0;

static OP * devel_hints_lexical_ck_require(pTHX_ OP * o) {
    HV * table;
    SV ** svp;

    o = CALL_FPTR(old_ck_require)(aTHX_ o); /* call the original checker */

    /* make sure it's still a require; the original checker may have turned it into an OP_ENTERSUB */
    if (!((o->op_type == OP_REQUIRE) || (o->op_type == OP_DOFILE))) {
        goto done;
    }

    /*
     * unlike %^H, $^H is lexically scoped
     *
     * check for HINT_LOCALIZE_HH (0x80020000) + an unused bit (0x80000000) so that this module
     * (which can't use itself) can work around the %^H bug
     */

    if ((PL_hints & 0x80020000) != 0x80020000) {
        goto done;
    }

    if (o->op_flags & OPf_KIDS) { 
        SVOP * const kid = (SVOP*)cUNOPo->op_first;

        if (kid->op_type == OP_CONST) { /* weed out use VERSION */
            SV * const sv = kid->op_sv;

            if (SvNIOK(sv)) { /* exclude use 5 and use 5.008 &c. */
                goto done;
            }
#ifdef SvVOK
            if (SvVOK(sv)) { /* exclude use v5.008 and use 5.6.1 &c. */
                goto done;
            }
#endif
        }
    }

    /* if Devel::Hints::Lexical is in scope, splice in our version of require */
    if ((table = GvHV(PL_hintgv)) && (svp = hv_fetch(table, "Devel::Hints::Lexical", 21, FALSE)) && *svp && SvOK(*svp)) {
        o->op_ppaddr = devel_hints_lexical_require;
    }

    done:
    return o;
}

static OP * devel_hints_lexical_require(pTHX) {
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
    hh = GvHV(PL_hintgv);
    GvHV(PL_hintgv) = new_hh;
    o = PL_ppaddr[cUNOP->op_type](aTHX);
    hv_clear(new_hh);
    hv_undef(new_hh);
    GvHV(PL_hintgv) = hh;
    return o;

    done:
    return PL_ppaddr[cUNOP->op_type](aTHX);
}

MODULE = Devel::Hints::Lexical                PACKAGE = Devel::Hints::Lexical                

void
_enter()
    PROTOTYPE:
    CODE:
        if (DEVEL_HINTS_LEXICAL_SCOPE_DEPTH > 0) {
            ++DEVEL_HINTS_LEXICAL_SCOPE_DEPTH;
        } else {
            DEVEL_HINTS_LEXICAL_SCOPE_DEPTH = 1;
            /*
             * capture the checker in scope when Devel::Hints::Lexical is used.
             * usually, this will be Perl_ck_require, though, in principle,
             * it could be a bespoke checker spliced in by another module.
             */
            old_ck_require = PL_check[OP_REQUIRE];
            PL_check[OP_REQUIRE] = PL_check[OP_DOFILE] = devel_hints_lexical_ck_require;
        }

void
_leave()
    PROTOTYPE:
    CODE:
        if (DEVEL_HINTS_LEXICAL_SCOPE_DEPTH == 0) {
            Perl_warn(aTHX_ "scope underflow\n");
        }

        if (DEVEL_HINTS_LEXICAL_SCOPE_DEPTH > 1) {
            --DEVEL_HINTS_LEXICAL_SCOPE_DEPTH;
        } else {
            DEVEL_HINTS_LEXICAL_SCOPE_DEPTH = 0;
            PL_check[OP_REQUIRE] = PL_check[OP_DOFILE] = old_ck_require;
        }

void
END()
    PROTOTYPE:
    CODE:
        if (old_ck_require) { /* make sure we got as far as initializing it */
            PL_check[OP_REQUIRE] = PL_check[OP_DOFILE] = old_ck_require;
        }
