/* =============================================================================
   code/analysis/21_table_A2.do

   Purpose: Appendix Table A2: do the cycles that produced no acknowledging
            publication come from investigators with riskier records? Their
            own risk cannot be measured, but the lagged risk of Appendix G
            can (risk_lagged.dta: the investigator's record before the grant
            for first cycles, the grant's previous cycle for later ones). For
            each measure, the lag is regressed on an indicator for a cycle
            without an acknowledging paper, with the base controls of Table 2
            (no grant output controls), bins of the lag's paper count by
            first and later cycles and the later-cycle indicator, as in the
            persistence regressions (code/analysis/32_table_G2.do). The grant
            output controls cannot enter: their bins of acknowledging papers
            contain the paperless indicator. Lags in units of 10 percentile
            points for tails and disruption, as fractions for pivoting and
            standing out. Among the base controls, the investigator's career
            citations are counted through the year before the cycle starts
            (pi_cites_precycle, code/build/20_record_before_cycle.do), not
            through the year before the evaluation
            (log_pi_careercites_evalyr): the latter includes citations to the
            cycle's acknowledging papers, which a cycle without an
            acknowledging paper cannot have, so it partly records the outcome
            that defines the regressor. The regressions on first and later
            cycles apart are in the log.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)
       with the variables of risk_lagged.dta (code/build/25_lagged_risk.do)
   Output:
     - output/tables/table_A2.tex       Table A2, written row by row
     - estimates/table_A2_<measure>.ster
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

log using "logs/21_table_A2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use "`afile'", clear ;
gen byte later = cycle_nb >= 2 if cycle_nb < . ;
gen byte paperless = n_ackn == 0 ;

/* the base controls with career citations at the start of the cycle */
gen double log_pi_cites_start = ln(pi_cites_precycle + 1) ;
label variable log_pi_cites_start "ln(career citations through cycle_yr - 1 + 1)" ;
local x2s : subinstr local x2 "log_pi_careercites_evalyr" "log_pi_cites_start", count(local nsub) ;
assert `nsub' == 1 ;
display as text "base controls used here: `x2s'" ;
correlate log_pi_cites_start log_pi_careercites_evalyr ;
tabstat log_pi_cites_start log_pi_careercites_evalyr, by(paperless) stat(mean) ;
label variable paperless "Cycle with no acknowledging paper" ;

display as result "=== paperless cycles, by first and later cycles" ;
tab later paperless, row ;

local vn1 "tails" ; local vn2 "disr" ; local vn3 "pivot" ; local vn4 "so" ;
forvalues j = 1/`nmeas' {;
    local v "`vn`j''" ;
    gen double L`j' = lag_`v' * cond(`j' <= 2, 10, 1) ;
    gen byte bl`j' = cond(n_lag_`v' <= 2, n_lag_`v', cond(n_lag_`v' <= 4, 3, cond(n_lag_`v' <= 9, 5,
                     cond(n_lag_`v' <= 19, 10, cond(n_lag_`v' <= 49, 20, 50))))) ;
    egen int lc`j' = group(bl`j' later) ;
    reghdfe L`j' paperless `x2s' if !missing(L`j') & later < ., absorb(`fe2' lc`j') vce(cluster `clus') ;
    nr_post ;
    estimates save "estimates/table_A2_`t`j''", replace ;
    local b_`j'  = _b[paperless] ;
    local se_`j' = _se[paperless] ;
    local N_`j'  = e(N) ;
    quietly count if e(sample) & paperless ;
    local np_`j' = r(N) ;
    quietly summarize L`j' if e(sample) & !paperless ;
    local mo_`j' = r(mean) ;
    local sdo_`j' = r(sd) ;
    display as result "`l`j'': paperless " %7.4f `b_`j'' " (" %6.4f `se_`j'' "), mean lag of other cycles "
        %6.3f `mo_`j'' " (sd " %6.3f `sdo_`j'' "); N " %7.0fc `N_`j'' ", paperless " %6.0fc `np_`j'' ;
    /* the same, first and later cycles apart (log only) */
    reghdfe L`j' paperless `x2s' if !missing(L`j') & later == 0, absorb(`fe2' lc`j') vce(cluster `clus') ;
    display as result "   first cycles: " %7.4f _b[paperless] " (" %6.4f _se[paperless] ")" ;
    reghdfe L`j' paperless `x2s' if !missing(L`j') & later == 1, absorb(`fe2' lc`j') vce(cluster `clus') ;
    display as result "   later cycles: " %7.4f _b[paperless] " (" %6.4f _se[paperless] ")" ;
} ;

/* the fragment of Table A2 */
tempname fh ;
file open `fh' using "output/tables/table_A2.tex", write replace text ;
file write `fh' " & (1) & (2) & (3) & (4) \\" _n ;
file write `fh' " & `l1' & `l2' & `l3' & `l4' \\" _n ;
file write `fh' "\midrule" _n ;
local r1 "Cycle with no acknowledging publication" ;
local r2 "" ;
local r3 "Mean of lagged risk, other cycles" ;
local r4 "Std.\ dev.\ of lagged risk, other cycles" ;
local r5 "Nb. of grant cycles" ;
local r6 "Nb. of cycles with no acknowledging publication" ;
forvalues j = 1/`nmeas' {;
    nr_star `b_`j'' `se_`j'' ;
    local vb  = strtrim(string(`b_`j'', "%7.4f")) ;
    local vse = strtrim(string(`se_`j'', "%6.4f")) ;
    local vm  = strtrim(string(`mo_`j'', "%6.3f")) ;
    local vsd = strtrim(string(`sdo_`j'', "%6.3f")) ;
    local vn  = strtrim(string(`N_`j'', "%9.0fc")) ;
    local vnp = strtrim(string(`np_`j'', "%9.0fc")) ;
    local r1 "`r1' & `vb'`r(star)'" ;
    local r2 "`r2' & (`vse')" ;
    local r3 "`r3' & `vm'" ;
    local r4 "`r4' & `vsd'" ;
    local r5 "`r5' & `vn'" ;
    local r6 "`r6' & `vnp'" ;
} ;
file write `fh' "`r1' \\" _n "`r2' \\" _n "\midrule" _n "`r3' \\" _n "`r4' \\" _n "`r5' \\" _n "`r6' \\" _n ;
file close `fh' ;
type "output/tables/table_A2.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
