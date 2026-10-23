/* =============================================================================
   code/analysis/36_table_H2.do

   Purpose: Appendix Table H2, Oster's delta. For each measure, entered as one
            continuous regressor, with the grant output controls of Table 2,
            column 3: the coefficient (reghdfe, clustered by investigator and
            grant), and Oster's (2019) delta from psacalc with
            Rmax = 1.3 x R2, after areg with institute x study section
            absorbed and the other fixed effects as indicators. Tails and
            disruption are in units of 10 percentile points, pivoting and
            standing out in fractions. The log also gives delta with
            Rmax = 1, quoted in a footnote of Appendix H on the dependence on
            Rmax (not in the table).

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/tables/table_H2.tex   (rows only, written directly: no esttab)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

log using "logs/36_table_H2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use "`afile'", clear ;

/* the fixed effects of each column as indicators, institute x study section
   absorbed by areg */
local ind2 "female i.deg_cat agepi_* i.new_eval_year i.new_cycle_length no_pi_priorgrants" ;
local ind3 "`ind2' journal_hs_ackn journal_hs_noackn i.bin_ackn i.bin_noackn authority_partial" ;

/* significance stars: nr_star, in code/programs/_programs.do */

tempname fh ;
file open `fh' using "output/tables/table_H2.tex", write replace ;
file write `fh' " & Coefficient estimate & Oster's \(\delta\) \\" _n ;
file write `fh' "\midrule" _n ;

forvalues j = 1/`nmeas' {;
    local m "`m`j''" ;
    capture drop z smp ;
    gen double z = `m' * cond(`j' <= 2, 10, 1) ;

    /* the cycles of Table 2, column 3 */
    quietly reghdfe `dv' z `x3', absorb(`fe3') vce(cluster `clus') ;
    gen byte smp = e(sample) ;

    forvalues k = 3/3 {;
        quietly reghdfe `dv' z `x`k'' if smp, absorb(`fe`k'') vce(cluster `clus') ;
        local b`k' = _b[z] ;
        local s`k' = _se[z] ;
        local n`k' = e(N) ;
        quietly areg `dv' z `x`k'' `ind`k'' if smp, absorb(ic_irg) vce(cluster inv_id) ;
        local rmax = 1.3 * e(r2) ;
        psacalc delta z, rmax(`rmax') ;
        local d`k' = r(delta) ;
        /* the same delta with Rmax = 1, log only (psacalc restores the
           areg estimates after each call) */
        psacalc delta z, rmax(1) ;
        local d1_`k' = r(delta) ;
        display as result "`t`j'' column `k': b = " %8.4f `b`k'' " (" %6.4f `s`k'' ")  delta = " %8.3f `d`k''
            "  Rmax = " %6.4f `rmax' "  N = " `n`k'' ;
        display as result "`t`j'' column `k': delta with Rmax = 1: " %8.3f `d1_`k'' ;
        nr_star `b`k'' `s`k'' ;
        local st`k' "`r(star)'" ;
    } ;

    file write `fh' "\multirow{2}{*}{`l`j''} & " %7.4f (`b3') "`st3' & " %7.3f (`d3') " \\" _n ;
    file write `fh' " & (" %6.4f (`s3') ") & \\" _n ;
    if `j' < `nmeas' file write `fh' "\addlinespace" _n ;
} ;
file close `fh' ;
type "output/tables/table_H2.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
