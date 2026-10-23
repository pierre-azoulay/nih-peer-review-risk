/* =============================================================================
   code/analysis/35_table_H1.do

   Purpose: Appendix Table H1, the four risk measures in one regression. On
            the cycles where all four measures and the mean journal impact
            factor are defined, the same cycles in every column: each measure
            alone (columns 1 to 4) and all four together (column 5), with the
            controls of Table 2, column 3 (the grant output controls). The
            measures are continuous, scaled as in Appendix Table I1 (tails and
            disruption in units of 10 percentile points, pivoting and standing
            out in fractions). Under each coefficient, its one-SD effect: the
            coefficient times the measure's standard deviation on the
            estimation sample. The log also gives each measure alone on its
            own sample (every cycle where it and the mean impact factor are
            defined), so that the effect of the common sample and the effect
            of the other three measures can be told apart (log only, not in
            the table).

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/tables/table_H1.tex   (rows only, written row by row)
     - estimates/table_H1_k3_joint.ster, table_H1_k3_c<1-4>.ster,
       table_H1_own_k3_<tag>.ster

   Note: a first argument of 0 (do code/analysis/35_table_H1.do 0) reads the
         saved estimates back, to redraw the table without re-estimating.
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

log using "logs/35_table_H1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 estimates the regressions, 0 reads the saved .ster files. A first
   argument overrides it */
local run_regs 1 ;
if "`1'" != "" local run_regs `1' ;

use "`afile'", clear ;

/* the measures, scaled as in Appendix Table I1
   (code/analysis/15_figure_5_table_I1.do) */
local allrm "" ;
forvalues j = 1/`nmeas' {;
    gen double rm_`t`j'' = `m`j'' * cond(`j' <= 2, 10, 1) ;
    label variable rm_`t`j'' "`l`j''" ;
    local allrm "`allrm' rm_`t`j''" ;
} ;

/* -------------------------------------------------------------------------
   1. The common sample: all four measures and the mean impact factor,
      fixed by the joint regression with the grant output controls (reghdfe
      also drops singletons and cycles with a missing control). Every other
      column of the table runs on exactly these cycles.
   ------------------------------------------------------------------------- */
display _newline as text "cycles with all four measures: " ;
count if has_all4 == 1 ;
display as text "... and a mean impact factor: " ;
count if has_all4 == 1 & !missing(log_meanjif_all) ;

if `run_regs' == 1 {;
    reghdfe `dv' `allrm' `x3' if has_all4 == 1 & !missing(log_meanjif_all),
        absorb(`fe3') vce(cluster `clus') ;
    gen byte smp = e(sample) ;
    nr_post ;
    estimates save "estimates/table_H1_k3_joint", replace ;
} ;
else {;
    estimates use "estimates/table_H1_k3_joint" ;
    gen byte smp = e(sample) ;
    /* e(sample) is not stored in a .ster file: rebuild it the same way */
    capture assert smp == 0 ;
    if _rc == 0 {;
        quietly reghdfe `dv' `allrm' `x3' if has_all4 == 1 & !missing(log_meanjif_all),
            absorb(`fe3') vce(cluster `clus') ;
        replace smp = e(sample) ;
    } ;
} ;
count if smp ;
local Ncommon = r(N) ;

/* the standard deviation of each measure on the common sample, and the
   correlations between the measures */
forvalues j = 1/`nmeas' {;
    quietly summarize rm_`t`j'' if smp ;
    local sd`j' = r(sd) ;
    display as text "`l`j'': mean " %7.4f r(mean) ", sd " %7.4f r(sd) ;
} ;
tabstat `dv' `allrm' if smp, stat(mean sd min max n) col(stat) ;
pwcorr `allrm' if smp ;

/* -------------------------------------------------------------------------
   2. Table H1: five regressions, grant output controls. k is the control
      set of _spec.do (3, the grant output controls). Column 5 is the joint
      regression of section 1.
   ------------------------------------------------------------------------- */
foreach k in 3 {;
    forvalues c = 1/5 {;
        if `c' <= 4 local rhs "rm_`t`c''" ;
        else        local rhs "`allrm'" ;
        local nm "table_H1_k`k'_c`c'" ;
        if `run_regs' == 1 {;
            if !(`k' == 3 & `c' == 5) {;
                reghdfe `dv' `rhs' `x`k'' if smp, absorb(`fe`k'') vce(cluster `clus') ;
                nr_post ;
                estimates save "estimates/`nm'", replace ;
            } ;
            else estimates use "estimates/table_H1_k3_joint" ;
        } ;
        else {;
            if !(`k' == 3 & `c' == 5) estimates use "estimates/`nm'" ;
            else                      estimates use "estimates/table_H1_k3_joint" ;
        } ;
        /* every column must use the common sample */
        assert e(N) == `Ncommon' ;
        local N_`k'_`c'    = e(N) ;
        local ninv_`k'_`c' = e(ninv) ;
        local ngr_`k'_`c'  = e(ngrant) ;
        local mdv_`k'_`c'  = e(meandv) ;
        forvalues j = 1/`nmeas' {;
            capture local b_`k'_`c'_`j'  = _b[rm_`t`j''] ;
            if _rc == 0 {;
                local se_`k'_`c'_`j' = _se[rm_`t`j''] ;
                local sde_`k'_`c'_`j' = `b_`k'_`c'_`j'' * `sd`j'' ;
            } ;
            else local b_`k'_`c'_`j' "" ;
        } ;
    } ;
} ;

/* the results in the log, one line per coefficient */
display _newline as text "Table H1: coefficient (se) [one-SD effect], common sample of `Ncommon' cycles" ;
foreach k in 3 {;
    display _newline as text "Output controls" ;
    forvalues j = 1/`nmeas' {;
        display as text %-24s "`l`j''" _continue ;
        foreach c in `j' 5 {;
            display as result "  " %8.4f `b_`k'_`c'_`j'' " (" %6.4f `se_`k'_`c'_`j'' ") [" %7.4f `sde_`k'_`c'_`j'' "]" _continue ;
        } ;
        display "" ;
    } ;
} ;

/* -------------------------------------------------------------------------
   3. Each measure alone on its own sample (log only): the cycles where the
      measure and the mean impact factor are defined, grant output controls.
      The branch for k other than 3 is not run.
   ------------------------------------------------------------------------- */
display _newline as text "Each measure alone, own sample: coefficient (se) [one-SD effect on that sample]" ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    capture drop osmp ;
    foreach k in 3 {;
        local nm "table_H1_own_k`k'_`t'" ;
        if `run_regs' == 1 {;
            if `k' == 3 reghdfe `dv' rm_`t' `x3' if !missing(rm_`t') & !missing(log_meanjif_all), absorb(`fe3') vce(cluster `clus') ;
            else        reghdfe `dv' rm_`t' `x2' if osmp, absorb(`fe2') vce(cluster `clus') ;
            nr_post ;
            estimates save "estimates/`nm'", replace ;
        } ;
        else {;
            estimates use "estimates/`nm'" ;
            if `k' == 3 quietly reghdfe `dv' rm_`t' `x3' if !missing(rm_`t') & !missing(log_meanjif_all), absorb(`fe3') vce(cluster `clus') ;
        } ;
        if `k' == 3 gen byte osmp = e(sample) ;
        quietly summarize rm_`t' if osmp ;
        local ossd = r(sd) ;
        display as text %-24s "`l`j''" cond(`k' == 2, " base  ", " output") as result
            "  " %8.4f _b[rm_`t'] " (" %6.4f _se[rm_`t'] ") [" %7.4f _b[rm_`t'] * `ossd' "]"
            "  N = " %9.0fc e(N) "  mean dv = " %5.3f e(meandv) "  sd = " %6.4f `ossd' ;
    } ;
} ;
drop osmp ;

/* -------------------------------------------------------------------------
   4. The fragment of Table H1, written row by row
   ------------------------------------------------------------------------- */
tempname fh ;
file open `fh' using "output/tables/table_H1.tex", write replace text ;
/* the last column's header in one cell spanning both header rows, its two
   lines at ordinary spacing and centered between the rules. The -0.5ex
   offsets the space the cmidrule adds */
file write `fh' " & \multicolumn{4}{c}{Each measure alone} & & All four & \multirow{2}{*}[-0.5ex]{{\renewcommand{\arraystretch}{1.0}\begin{tabular}{@{}c@{}}S.D. of\\ measure\end{tabular}}} \\" _n ;
file write `fh' "\cmidrule(lr){2-5}\cmidrule(lr){7-7}" _n ;
file write `fh' " & (1) & (2) & (3) & (4) & & (5) & \\" _n ;
file write `fh' "\midrule" _n ;
foreach k in 3 {;
    forvalues j = 1/`nmeas' {;
        local r1 "\quad `l`j''" ;
        local r2 "" ;
        local r3 "" ;
        forvalues c = 1/5 {;
            if `c' == 5 {;
                local r1 "`r1' &" ;
                local r2 "`r2' &" ;
                local r3 "`r3' &" ;
            } ;
            if "`b_`k'_`c'_`j''" != "" {;
                nr_star `b_`k'_`c'_`j'' `se_`k'_`c'_`j'' ;
                local vb  = strtrim(string(`b_`k'_`c'_`j'', "%7.4f")) ;
                local vse = strtrim(string(`se_`k'_`c'_`j'', "%6.4f")) ;
                local vsd = strtrim(string(`sde_`k'_`c'_`j'', "%7.4f")) ;
                local r1 "`r1' & `vb'`r(star)'" ;
                local r2 "`r2' & (`vse')" ;
                local r3 "`r3' & {\footnotesize [`vsd']}" ;
            } ;
            else {;
                local r1 "`r1' &" ;
                local r2 "`r2' &" ;
                local r3 "`r3' &" ;
            } ;
        } ;
        file write `fh' "`r1' & `: display %5.3f `sd`j''' \\" _n ;
        file write `fh' "`r2' & \\" _n ;
        file write `fh' "`r3' & \\" _n ;
    } ;
} ;
file write `fh' "\midrule" _n ;
local rm "Mean of dependent variable" ;
local ri "Nb. of investigators" ;
local rg "Nb. of grants" ;
local rn "Nb. of grant cycles" ;
forvalues c = 1/5 {;
    if `c' == 5 {;
        local rm "`rm' &" ;
        local ri "`ri' &" ;
        local rg "`rg' &" ;
        local rn "`rn' &" ;
    } ;
    local rm "`rm' & `: display %5.3f `mdv_3_`c'''" ;
    local ri "`ri' & `: display %9.0fc `ninv_3_`c'''" ;
    local rg "`rg' & `: display %9.0fc `ngr_3_`c'''" ;
    local rn "`rn' & `: display %9.0fc `N_3_`c'''" ;
} ;
file write `fh' "`rm' & \\" _n "`ri' & \\" _n "`rg' & \\" _n "`rn' & \\" _n ;
file close `fh' ;
type "output/tables/table_H1.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
