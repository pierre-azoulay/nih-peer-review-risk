/* =============================================================================
   code/analysis/33_table_G3.do

   Purpose: Appendix Table G3, the persistence of risk taking across the
            cycles of a grant, estimated in six versions:
                                 year only   base controls   base + output
              pooled             V1          V2              V3
              anchored, cycle 1  V4          V5              V6
            Each measure is residualized on the stated controls and the
            residual z-scored, on the cycles of investigator-grants with at
            least two cycles where the measure is defined (multi-PI cycles and
            grants first observed at a renewal dropped). Then, for each lag k
            = 1 to 4, the z-score at cycle c + k is regressed on the z-score at
            cycle c: every pair k apart (pooled) or only the pair starting at
            the grant's first cycle (anchored), with the panel set on the
            grant's actual cycle number, so a missing cycle leaves a gap.
            Standard errors clustered by grant. The three purges use the same
            cycles (those with a mean impact factor too), so that the
            versions differ only by what is purged. No investigator fixed
            effects.
            Table G3 prints the pooled versions with year effects only (V1)
            and with all the controls of Table 2 (V3), the lags in columns;
            the six versions go to the log.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/tables/table_G3.tex   Appendix Table G3 (written row by row)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set processors 4 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

log using "logs/33_table_G3.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use "`afile'", clear ;
keep if multi_pi == 0 & cycle_nb < . ;
egen long pid = group(inv_id grant_id) ;
xtset pid cycle_nb ;

/* the three purges: year only, base controls, base and output controls */
local fey "new_eval_year" ;   local xy "" ;
local feb "`fe2'" ;           local xb "`x2'" ;
local feo "`fe3'" ;           local xo "`x3'" ;

tempname pf ;
tempfile res ;
postfile `pf' byte(meas ver lag) double(b se) long(npair ngrant) using `res', replace ;

forvalues j = 1/`nmeas' {;
    /* the cycles: measure and mean impact factor defined, in investigator-
       grants with at least two such cycles */
    capture drop smp cnt ;
    gen byte smp = !missing(`m`j'') & !missing(log_meanjif_all) ;
    gegen cnt = total(smp), by(pid) ;
    replace smp = 0 if cnt < 2 ;
    display as result "`l`j'': " _continue ;
    count if smp ;
    local p = 0 ;
    foreach u in y b o {;
        local ++p ;
        capture drop e z ;
        if "`u'" == "y" reghdfe `m`j'' if smp, absorb(`fey') residuals(e) ;
        else            reghdfe `m`j'' `x`u'' if smp, absorb(`fe`u'') residuals(e) ;
        quietly summarize e if smp ;
        gen double z = (e - r(mean)) / r(sd) if smp ;
        forvalues k = 1/4 {;
            /* pooled: V1 to V3 */
            quietly regress F`k'.z z, vce(cluster grant_id) ;
            post `pf' (`j') (`p') (`k') (_b[z]) (_se[z]) (e(N)) (e(N_clust)) ;
            /* anchored at the first cycle: V4 to V6 */
            quietly regress F`k'.z z if cycle_nb == 1, vce(cluster grant_id) ;
            post `pf' (`j') (`p' + 3) (`k') (_b[z]) (_se[z]) (e(N)) (e(N_clust)) ;
        } ;
    } ;
} ;
postclose `pf' ;

use `res', clear ;
label define meas 1 "`l1'" 2 "`l2'" 3 "`l3'" 4 "`l4'", replace ;
label values meas meas ;
sort meas lag ver ;
list meas lag ver b se npair ngrant, sepby(meas lag) noobs ;

tempname fh ;

/* -------------------------------------------------------------------------
   Appendix Table G3: pooled only, year effects only (V1) and all the
   controls of Table 2 (V3); rows a measure and a version, columns the lags;
   the pairs of V3 in a row of their own (V1 has slightly more, since the
   residualization on the controls drops cycles alone in their fixed-effect
   cells)
   ------------------------------------------------------------------------- */
file open `fh' using "output/tables/table_G3.tex", write replace text ;
file write `fh' " & \multicolumn{4}{c}{Cycles apart} \\" _n ;
file write `fh' "\cmidrule(lr){2-5}" _n ;
file write `fh' " & 1 & 2 & 3 & 4 \\" _n ;
file write `fh' "\midrule" _n ;
forvalues j = 1/`nmeas' {;
    if `j' > 1 file write `fh' "\addlinespace" _n ;
    file write `fh' "\multicolumn{5}{l}{\textit{`l`j''}} \\" _n ;
    foreach v in 1 3 {;
        local r1 = cond(`v' == 1, "\quad Year effects only", "\quad All controls of Table 2") ;
        local r2 "" ;
        forvalues k = 1/4 {;
            quietly summarize b if meas == `j' & lag == `k' & ver == `v', meanonly ;
            local bb = r(mean) ;
            quietly summarize se if meas == `j' & lag == `k' & ver == `v', meanonly ;
            local ss = r(mean) ;
            nr_star `bb' `ss' ;
            local vb = strtrim(string(`bb', "%6.3f")) ;
            local vs = strtrim(string(`ss', "%5.3f")) ;
            local r1 "`r1' & `vb'`r(star)'" ;
            local r2 "`r2' & (`vs')" ;
        } ;
        file write `fh' "`r1' \\" _n "`r2' \\" _n ;
    } ;
    local r3 "\quad Pairs of cycles" ;
    forvalues k = 1/4 {;
        quietly summarize npair if meas == `j' & lag == `k' & ver == 3, meanonly ;
        local vn = strtrim(string(r(mean), "%9.0fc")) ;
        local r3 "`r3' & `vn'" ;
    } ;
    file write `fh' "`r3' \\" _n ;
} ;
file close `fh' ;
type "output/tables/table_G3.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
