/* =============================================================================
   code/analysis/28_table_D5.do

   Purpose: is the penalty on pivoting smaller when the pivot was proposed in
            the application that started the cycle, which a study section
            reviewed and NIH funded (Appendix D, which dissects pivoting)?
            The proposal measure is the share of the starting application's
            MeSH descriptors absent from the investigator's papers of the
            five years before the cycle (frac_app_single_new,
            code/build/15_proposal_pivot.do). It counts single descriptors,
            not pairs: machine tags of an abstract rarely reproduce the
            indexers' pairs on papers, so the pair share bunches near 1.

            Table D5 follows the design of Table D4
            (code/analysis/27_table_D4_figure_D3.do), with pivoting
            continuous, the grant output controls of Table 2 and the bins of
            baseline papers with MeSH (nprior_bin) of
            code/analysis/26_tables_D1_D3_figure_D1.do, clustered by
            investigator and grant:
              (1) pivoting, on Table 2's pivoting sample;
              (2) the same, on the cycles whose starting application has a
                  proposal measure;
              (3) adds an indicator for a pivot proposed in the application:
                  the proposal measure above its median among the cycles of
                  column 2 that start the same year (Table D4 splits
                  vibrancy the same way);
              (4) adds pivoting x the indicator, pivoting centered at its
                  mean on column 2's cycles, so that the coefficient on the
                  indicator is the gap at average pivoting.
            The penalty among proposed pivots (the sum of two coefficients)
            goes to the log for the text, not to a table row, as in Table D4.

   Input:
     - ${public}/nih_risk_public.dta         (code/build/34_public_file.do),
       which carries the proposal measures and n_base_mesh for the
       baseline bins

   Output:
     - output/tables/table_D5.tex (rows only, written row by row)
     - estimates/table_D5_c1.ster to table_D5_c4.ster, and
       estimates/table_D5_samples.dta (the samples of columns 1 and 4)

   Note: a first argument of 0 (do code/analysis/28_table_D5.do 0) reuses the
         saved estimates and samples, to redraw the table without
         re-estimating.
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

log using "logs/28_table_D5.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate and save; 0 = reuse the saved estimates. A first argument
   overrides it */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;
local pv "`m3'" ;
local ap "frac_app_single_new" ;

/* -----------------------------------------------------------------------------
   1. The analysis file, with the baseline bins of
      code/analysis/26_tables_D1_D3_figure_D1.do
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;

gen byte nprior_bin = 1 if n_base_mesh == 1 ;
replace nprior_bin = 2 if n_base_mesh == 2 ;
replace nprior_bin = 3 if inrange(n_base_mesh, 3, 4) ;
replace nprior_bin = 4 if inrange(n_base_mesh, 5, 9) ;
replace nprior_bin = 5 if inrange(n_base_mesh, 10, 19) ;
replace nprior_bin = 6 if inrange(n_base_mesh, 20, 49) ;
replace nprior_bin = 7 if n_base_mesh >= 50 & !missing(n_base_mesh) ;
assert !missing(nprior_bin) if !missing(`pv') ;

/* -----------------------------------------------------------------------------
   2. Regressions, Table D4's design
   ----------------------------------------------------------------------------- */
if `run_regs' {;
    /* (1) Table 2's pivoting sample */
    reghdfe `dv' `pv' `x3' if !missing(`pv'), absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    gen byte s1 = e(sample) ;
    nr_post ;
    estimates save "estimates/table_D5_c1", replace ;

    /* the cycles with a proposal measure, and the proposed pivots: above the
       median among the cycles that start the same year */
    gen byte asmp = s1 & !missing(`ap') ;
    /* the two samples, saved with the estimates: estimates use does not restore
       e(sample) on the data, and the tables step needs them */
    preserve ;
        keep inv_id grant_id cycle s1 asmp ;
        sort inv_id grant_id cycle ;
        compress ;
        save "estimates/table_D5_samples.dta", replace ;
    restore ;
    gegen double med = median(`ap') if asmp, by(cycle_yr) ;
    gen byte proposed = `ap' > med if asmp ;
    quietly summarize `pv' if asmp ;
    gen double pvc = `pv' - r(mean) if asmp ;
    gen double pv_x_prop = pvc * proposed ;

    /* (2) the same on the cycles with a proposal measure */
    reghdfe `dv' `pv' `x3' if asmp, absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    nr_post ;
    estimates save "estimates/table_D5_c2", replace ;
    local n2 = e(N) ;

    /* (3) the indicator, without the interaction */
    reghdfe `dv' `pv' proposed `x3' if asmp, absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    assert e(N) == `n2' ;
    nr_post ;
    estimates save "estimates/table_D5_c3", replace ;

    /* (4) the interaction, pivoting centered. The penalty among proposed
       pivots, the sum of two coefficients, is for the text and the log only */
    reghdfe `dv' pvc proposed pv_x_prop `x3' if asmp, absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    assert e(N) == `n2' ;
    nr_post ;
    lincom pvc + pv_x_prop ;
    estadd scalar bprop    = r(estimate) ;
    estadd scalar bprop_se = r(se) ;
    estimates save "estimates/table_D5_c4", replace ;
} ;
else {;
    merge 1:1 inv_id grant_id cycle using "estimates/table_D5_samples.dta", keepusing(s1 asmp) ;
    tab _merge ;
    assert _merge == 3 ;
    drop _merge ;
    gegen double med = median(`ap') if asmp, by(cycle_yr) ;
    gen byte proposed = `ap' > med if asmp ;
    quietly summarize `pv' if asmp ;
    gen double pvc = `pv' - r(mean) if asmp ;
    gen double pv_x_prop = pvc * proposed ;
} ;

/* -----------------------------------------------------------------------------
   3. Descriptives for the text (log)
   ----------------------------------------------------------------------------- */
display as result "=== cycles of column 1, and with a proposal measure" ;
count if s1 ;
local a = r(N) ;
count if asmp ;
display as result "share with a proposal measure: " %6.4f r(N) / `a' ;
display as result "=== the proposal measure and realized pivoting, column 2's cycles" ;
summarize `ap' `pv' if asmp, detail ;
correlate `ap' `pv' if asmp ;
display as result "=== realized pivoting, proposed and other pivots" ;
tabstat `pv' `ap' if asmp, by(proposed) stat(mean sd n) ;
display as result "=== the median of the proposal measure by start year (first and last years)" ;
tabstat `ap' if asmp, by(cycle_yr) stat(p50 n) ;

/* -----------------------------------------------------------------------------
   4. Table D5, row by row (Table D4's layout, adjusted R2 last)
   ----------------------------------------------------------------------------- */
eststo clear ;
forvalues c = 1/4 {;
    estimates use "estimates/table_D5_c`c'" ;
    eststo c`c' ;
} ;
esttab c1 c2 c3 c4, keep(`pv' pvc proposed pv_x_prop) b(%6.4f) se(%6.4f) star(+ 0.10 * 0.05 ** 0.01)
    nomtitles noobs stats(bprop bprop_se meandv r2_a ninv N, fmt(%6.4f %6.4f %6.3f %6.4f %9.0fc %9.0fc))
    title("Table D5 (bprop: the penalty among proposed pivots, for the text)") ;

local vl1 "Pivoting" ;
local vl2 "Pivot proposed in the application" ;
local vl3 "Pivoting \(\times\) pivot proposed in the application" ;
local vv1 "`pv'" ;
local vv2 "proposed" ;
local vv3 "pv_x_prop" ;
tempname fh ;
file open `fh' using "output/tables/table_D5.tex", write replace ;
file write `fh' " & (1) & (2) & (3) & (4) \\" _n ;
file write `fh' "\midrule" _n ;
forvalues v = 1/3 {;
    local r1 "`vl`v''" ;
    local r2 "" ;
    forvalues c = 1/4 {;
        estimates restore c`c' ;
        local b = . ;
        capture local b = _b[`vv`v''] ;
        /* column 4 enters pivoting centered (pvc) */
        if `b' == . & `v' == 1 {;
            capture local b = _b[pvc] ;
        } ;
        if `b' < . {;
            local se = . ;
            capture local se = _se[`vv`v''] ;
            if `se' == . local se = _se[pvc] ;
            nr_star `b' `se' ;
            local r1 "`r1' & `: display %6.3f `b''`r(star)'" ;
            local r2 "`r2' & (`: display %5.3f `se'')" ;
        } ;
        else {;
            local r1 "`r1' & " ;
            local r2 "`r2' & " ;
        } ;
    } ;
    file write `fh' "`r1' \\" _n ;
    file write `fh' "`r2' \\" _n ;
} ;
file write `fh' "\midrule" _n ;
local rs "Sample" ;
local rm "Mean of dependent variable" ;
local rn "Nb. of grant cycles" ;
local ri "Nb. of investigators" ;
local ra "Adjusted \(R^2\)" ;
forvalues c = 1/4 {;
    estimates restore c`c' ;
    local rs = cond(`c' == 1, "`rs' & Table 2", "`rs' & Application measured") ;
    local mv : display %5.3f e(meandv) ;
    local nv : display %12.0fc e(N) ;
    local iv : display %12.0fc e(ninv) ;
    local av : display %6.4f e(r2_a) ;
    local nv = strtrim("`nv'") ;
    local iv = strtrim("`iv'") ;
    local rm "`rm' & `mv'" ;
    local rn "`rn' & `nv'" ;
    local ri "`ri' & `iv'" ;
    local ra "`ra' & `av'" ;
} ;
file write `fh' "`rs' \\" _n ;
file write `fh' "`rm' \\" _n ;
file write `fh' "`rn' \\" _n ;
file write `fh' "`ri' \\" _n ;
file write `fh' "`ra' \\" _n ;
file close `fh' ;
type "output/tables/table_D5.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/analysis/28_table_D5.do */
