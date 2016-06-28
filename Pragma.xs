#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_sv_2pv_flags
#include "ppport.h"

MODULE = Devel::Pragma                PACKAGE = Devel::Pragma

SV *
ccstash()
    PROTOTYPE:
    CODE:
        if (PL_curstash) { /* compile time */
            RETVAL = newSVpv(HvNAME(PL_curstash), 0);
        } else { /* runtime: return undef */
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

void
xs_scope()
    PROTOTYPE:
    CODE:
        XSRETURN_UV(PTR2UV(GvHV(PL_hintgv)));
