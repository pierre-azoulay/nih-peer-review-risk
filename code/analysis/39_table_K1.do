/* =============================================================================
   code/analysis/39_table_K1.do

   Purpose: Appendix Table K1, the penalty and the scarcity of money at the
            institute: does the penalty vary with how competitive funding
            is? Scarcity is measured by the renewal rate of the cycle's
            institute and evaluation year, leave-one-out (the cycle's own
            outcome never enters its regressor), over every cycle of the
            analysis file, missing in institute-years with fewer than 10
            cycles. For each measure, entered as a continuous regressor
            (tails and disruption in units of 10 percentile points, pivoting
            and standing out in fractions), with the grant output controls
            of Table 2, column 3, on the same cycles: (1) the measure alone,
            and (2) the measure, the standardized rate (rate_z, mean 0 and
            SD 1 on the estimation sample) and their interaction, the
            measure centered at its mean in the interaction. One-SD effects
            in brackets. The measure with the rate but no interaction is in
            the log.
            Also logged, for the text of Appendix K: the cells
            (institute-years, cycles per cell), the SD of the rate across
            institute-years and across years, and the renewal rate by
            evaluation year.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/tables/table_K1.tex   (rows only, written row by row)
     - estimates/table_K1_d1_<tag>.ster, estimates/table_K1_d2_<tag>.ster

   Note: a first argument of 0 reads the saved estimates back instead of
         re-estimating. A regression whose .ster file is missing is
         estimated in either case.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set processors 3 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

log using "logs/39_table_K1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 re-estimates and saves the .ster files, 0 reads them back. The default
   is 1. A first argument of 0 sets it to 0
   (do code/analysis/39_table_K1.do 0). The regressions are estimated
   whenever their .ster files are missing. */
args runarg ;
local run_regs 1 ;
if "`runarg'" == "0" local run_regs 0 ;

use `dv' ic eval_year new_eval_year `m1' `m2' `m3' `m4' `x3' `fe3' inv_id grant_id
    using "`afile'", clear ;

/* ---------------------------------------------------------------------------
   1. The renewal rate of the institute-year, leave-one-out
   --------------------------------------------------------------------------- */

/* the cells: institute x evaluation year of the fixed effects (1980 and 1981
   pooled with 1982), over every cycle of the analysis file */
gegen long cell = group(ic new_eval_year) ;
gegen double cell_sum = total(`dv'), by(cell) ;
gegen long   cell_n   = count(`dv'), by(cell) ;
gen double rate = (cell_sum - `dv') / (cell_n - 1) if cell_n >= 10 ;
label variable rate "Leave-one-out renewal rate of the institute-year" ;

display as text _newline "cycles by cell size: share in cells with fewer than 10 cycles" ;
gen byte small = cell_n < 10 ;
tab small ;
display as text "cycles per cell, cycle-weighted (the cell of a typical cycle)" ;
summarize cell_n, detail ;

/* the cells themselves: one row per institute-year */
preserve ;
    gcollapse (mean) crate = `dv' (count) n = `dv', by(ic new_eval_year cell) ;
    display as text _newline "institute-years, all and with 10 cycles or more" ;
    count ;
    count if n >= 10 ;
    display as text "cycles per institute-year (cells with 10 or more), unweighted" ;
    summarize n if n >= 10, detail ;
    display as text "SD of the renewal rate across institute-years (cells with 10 or more), unweighted" ;
    summarize crate if n >= 10 ;
    local sd_cell = r(sd) ;
    /* the SD of the institute-year rate around its year's mean */
    gegen double yrate_c = mean(crate) if n >= 10, by(new_eval_year) ;
    gen double crate_w = crate - yrate_c ;
    display as text "SD of the institute-year rate around its year's mean (cells with 10 or more)" ;
    summarize crate_w ;
    local sd_within = r(sd) ;
    display as text "institute-years with 10 cycles or more, by evaluation year" ;
    tab new_eval_year if n >= 10 ;
restore ;

preserve ;
    gcollapse (mean) yrate = `dv' (count) n = `dv', by(new_eval_year) ;
    display as text _newline "renewal rate by evaluation year (new_eval_year), every cycle of the analysis file" ;
    list new_eval_year yrate n, noobs sep(5) ;
    display as text "SD of the renewal rate across years, unweighted, 1982 to 2019 (years with 1,000 cycles or more)" ;
    summarize yrate if n >= 1000 ;
    local sd_year = r(sd) ;
restore ;
display as text "renewal rate by raw evaluation year (eval_year)" ;
tabstat `dv', by(eval_year) stat(mean n) ;
display as result "SD across institute-years: " %5.3f `sd_cell'
    "   within year: " %5.3f `sd_within' "   across years: " %5.3f `sd_year' ;

display as text "rate defined, by evaluation year from 2017" ;
tabstat rate if new_eval_year >= 2017, by(new_eval_year) stat(mean n) ;

/* the measures, scaled as in Appendix Table I1
   (code/analysis/15_figure_5_table_I1.do) */
forvalues j = 1/`nmeas' {;
    gen double rm_`t`j'' = `m`j'' * cond(`j' <= 2, 10, 1) ;
} ;

/* generic names, so that the eight columns share their rows */
gen double rm = . ;
gen double rate_z = . ;
gen double ix = . ;
label variable rm "Risk measure" ;
label variable rate_z "Renewal rate of the institute-year" ;
label variable ix "Risk measure \(\times\) renewal rate of the institute-year" ;

/* ---------------------------------------------------------------------------
   2. The regressions of Table K1
   --------------------------------------------------------------------------- */

eststo clear ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    replace rm = rm_`t' ;

    /* the sample: cycles of the regression of renewal on the measure, the
       raw rate and their interaction with the grant output controls
       (singletons depend only on the fixed effects, so the raw rate gives
       the same cycles as rate_z) */
    capture drop smp ;
    replace ix = rm * rate ;
    quietly reghdfe `dv' rm ix rate `x3' if !missing(rate), absorb(`fe3') vce(cluster `clus') ;
    gen byte smp = e(sample) ;
    summarize rate if smp ;
    local mrate = r(mean) ;
    local srate = r(sd) ;
    replace rate_z = (rate - `mrate') / `srate' ;
    /* the measure's SD on these cycles, for the brackets of Table K1, and its
       mean, to center it in the interaction */
    quietly summarize rm if smp ;
    local sdm_`j' = r(sd) ;
    local mm_`j'  = r(mean) ;

    /* Table K1, grant output controls, on the same cycles: (1) the measure
       alone, as it enters Appendix Table I1, (2) the measure, the rate and
       their interaction, with the measure centered at its mean on these
       cycles in the interaction, so that the rate's coefficient is its
       association with renewal at the measure's mean (uncentered, it would
       be the association at a measure of zero). The measure's coefficient
       and the interaction do not depend on the centering. Log only: the
       measure with the rate but no interaction, to see whether the rate
       changes the penalty. */
    capture drop ixc ;
    gen double ixc = (rm - `mm_`j'') * rate_z ;
    capture confirm file "estimates/table_K1_d2_`t'.ster" ;
    if `run_regs' == 1 | _rc {;
        reghdfe `dv' rm rate_z ixc `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
        nr_post ;
        estadd scalar sdrate = `srate' ;
        estimates save "estimates/table_K1_d2_`t'.ster", replace ;
    } ;
    else {;
        estimates use "estimates/table_K1_d2_`t'.ster" ;
    } ;
    eststo d2_`t' ;
    capture confirm file "estimates/table_K1_d1_`t'.ster" ;
    if `run_regs' == 1 | _rc {;
        reghdfe `dv' rm `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
        nr_post ;
        estadd scalar sdrate = `srate' ;
        estimates save "estimates/table_K1_d1_`t'.ster", replace ;
    } ;
    else {;
        estimates use "estimates/table_K1_d1_`t'.ster" ;
    } ;
    eststo d1_`t' ;
    local bd1 = _b[rm] ;
    quietly reghdfe `dv' rm rate_z `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
    display as result "Table K1, `t': the measure alone " %7.4f `bd1' "; with the rate, no interaction "
        %7.4f _b[rm] " (" %6.4f _se[rm] "), rate " %7.4f _b[rate_z] " (" %6.4f _se[rate_z] "); N " %9.0fc e(N) ;
    drop smp ;
} ;

/* ---------------------------------------------------------------------------
   3. Appendix Table K1, written row by row: for each measure, (1) the
      measure alone and (2) the measure, the renewal rate of the
      institute-year and their interaction, the measure centered in the
      interaction (grant output controls), on the same cycles. Under the
      measure and the interaction, in brackets, the coefficient times the
      measure's SD on these cycles. The rate is standardized, so its
      coefficient is already per SD.
   --------------------------------------------------------------------------- */
tempname fh ;
file open `fh' using "output/tables/table_K1.tex", write replace text ;
file write `fh' " & \multicolumn{2}{c}{`l1'} & & \multicolumn{2}{c}{`l2'} & & \multicolumn{2}{c}{`l3'} & & \multicolumn{2}{c}{`l4'} \\" _n ;
file write `fh' "\cmidrule(lr){2-3}\cmidrule(lr){5-6}\cmidrule(lr){8-9}\cmidrule(lr){11-12}" _n ;
file write `fh' " & (1) & (2) & & (3) & (4) & & (5) & (6) & & (7) & (8) \\" _n ;
file write `fh' "\midrule" _n ;
local Mrow "Risk measure" ; local Mse "" ; local Msd "" ;
local Rrow "Renewal rate of the institute-year" ; local Rse "" ;
local Xrow "Risk measure \(\times\) renewal rate of the institute-year" ; local Xse "" ; local Xsd "" ;
local mrow "Mean of dependent variable" ;
local srow "SD of the institute-year renewal rate" ;
local irow "Nb. of investigators" ;
local nrow "Nb. of grant cycles" ;
local arow "Adjusted \(R^2\)" ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    if `j' > 1 {;
        foreach r in Mrow Mse Msd Rrow Rse Xrow Xse Xsd mrow srow irow nrow arow {;
            local `r' "``r'' &" ;
        } ;
    } ;
    foreach m in d1 d2 {;
        estimates restore `m'_`t' ;
        nr_star `=_b[rm]' `=_se[rm]' ;
        local Mrow "`Mrow' & `=strtrim(string(_b[rm], "%7.4f"))'`r(star)'" ;
        local Mse  "`Mse' & (`=strtrim(string(_se[rm], "%6.4f"))')" ;
        local Msd  "`Msd' & {\footnotesize [`=strtrim(string(_b[rm] * `sdm_`j'', "%7.4f"))']}" ;
        if "`m'" == "d1" {;
            local Rrow "`Rrow' & " ;
            local Rse  "`Rse' & " ;
            local Xrow "`Xrow' & " ;
            local Xse  "`Xse' & " ;
            local Xsd  "`Xsd' & " ;
        } ;
        else {;
            nr_star `=_b[rate_z]' `=_se[rate_z]' ;
            local Rrow "`Rrow' & `=strtrim(string(_b[rate_z], "%7.4f"))'`r(star)'" ;
            local Rse  "`Rse' & (`=strtrim(string(_se[rate_z], "%6.4f"))')" ;
            nr_star `=_b[ixc]' `=_se[ixc]' ;
            local Xrow "`Xrow' & `=strtrim(string(_b[ixc], "%7.4f"))'`r(star)'" ;
            local Xse  "`Xse' & (`=strtrim(string(_se[ixc], "%6.4f"))')" ;
            local Xsd  "`Xsd' & {\footnotesize [`=strtrim(string(_b[ixc] * `sdm_`j'', "%7.4f"))']}" ;
        } ;
        local mrow "`mrow' & `=strtrim(string(e(meandv), "%5.3f"))'" ;
        local srow "`srow' & `=strtrim(string(e(sdrate), "%5.3f"))'" ;
        local irow "`irow' & `=strtrim(string(e(ninv), "%9.0fc"))'" ;
        local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
        local arow "`arow' & `=strtrim(string(e(r2_a), "%6.4f"))'" ;
    } ;
} ;
file write `fh' "`Mrow' \\" _n "`Mse' \\" _n "`Msd' \\" _n "\addlinespace" _n ;
file write `fh' "`Rrow' \\" _n "`Rse' \\" _n "\addlinespace" _n ;
file write `fh' "`Xrow' \\" _n "`Xse' \\" _n "`Xsd' \\" _n "\midrule" _n ;
file write `fh' "`mrow' \\" _n "`srow' \\" _n "`irow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
file close `fh' ;
type "output/tables/table_K1.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
