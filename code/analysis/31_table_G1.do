/* =============================================================================
   code/analysis/31_table_G1.do

   Purpose: Appendix Table G1, the early and the late years of the cycle. For
            each measure, three columns on a common sample, each regressing
            renewal on one version of the measure: computed from all the
            cycle's acknowledging papers, from those of the first two years of
            its attributable span, and from those of its last two years. The
            control set is the same in the three columns: the base controls
            (control set 2 of code/programs/_spec.do), plus the grant output
            controls computed separately for the early window, the late window
            and the middle years (paper-count bins, log mean impact factor with
            an indicator for none, top-journal flags), and the flag for windows
            past 2018. Sample: cycles whose span is at least four years and
            where the measure is defined in all three versions. Tails and
            disruption in units of 10 percentile points, pivoting and standing
            out as fractions. Reports, by column, the one-SD effect, the
            standard deviation and the mean number of papers behind the
            measure.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)
       with the variables of risk_windows.dta (code/build/24_risk_windows.do)
   Output:
     - output/tables/table_G1.tex   Appendix Table G1 (written row by row)
     - estimates/table_G1_*.ster

   Note: a first argument of 0 (do code/analysis/31_table_G1.do 0) redraws
         the table from the saved estimates.
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

log using "logs/31_table_G1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 estimates the regressions; 0 reads the saved .ster files. A first
   argument overrides it */
local run_regs 1 ;
if "`1'" != "" local run_regs `1' ;

use "`afile'", clear ;
/* win_ok: the cycle has the windows of code/build/24_risk_windows.do */
display as result "=== analysis cycles with a span of at least four years" ;
count if win_ok ;

/* the three versions of each measure, tails and disruption in units of 10
   percentile points, pivoting and standing out as fractions; the window
   files name them tails, disr, pivot, so (_f, _e, _l) */
local vn1 "tails" ; local vn2 "disr" ; local vn3 "pivot" ; local vn4 "so" ;
local pn1 "n_tails" ; local pn2 "n_disr" ; local pn3 "n_piv" ; local pn4 "n_so" ;
forvalues j = 1/`nmeas' {;
    foreach s in f e l {;
        gen double r`j'_`s' = `vn`j''_`s' * cond(`j' <= 2, 10, 1) ;
        label variable r`j'_`s' "`l`j''" ;
    } ;
    /* the whole-cycle version is the stored measure */
    assert abs(r`j'_f - `m`j'' * cond(`j' <= 2, 10, 1)) < 1e-9 if win_ok & !missing(r`j'_f) ;
} ;

/* the control set, the same in every column: base controls and output
   controls by part of the cycle */
local xw "`x2' ljif_e ljif_l ljif_m" ;
local few "`fe2' bin_ackn_e bin_noackn_e bin_ackn_l bin_noackn_l bin_ackn_m bin_noackn_m
           hs_ackn_e hs_noackn_e hs_ackn_l hs_noackn_l hs_ackn_m hs_noackn_m
           nojif_e nojif_l nojif_m authority_partial" ;

local cols "f e l" ;
forvalues j = 1/`nmeas' {;
    capture drop smp ;
    gen byte smp = win_ok & !missing(r`j'_f) & !missing(r`j'_e) & !missing(r`j'_l) ;
    local c = 0 ;
    foreach s of local cols {;
        local ++c ;
        local nm "table_G1_`t`j''_`s'" ;
        if `run_regs' == 1 {;
            reghdfe `dv' r`j'_`s' `xw' if smp, absorb(`few') vce(cluster `clus') ;
            nr_post ;
            estimates save "estimates/`nm'", replace ;
        } ;
        else estimates use "estimates/`nm'" ;
        /* the first column fixes the sample of the other two (singletons) */
        if `c' == 1 & `run_regs' == 1 {;
            replace smp = e(sample) ;
        } ;
        if `c' == 1 & `run_regs' == 0 {;
            quietly reghdfe `dv' r`j'_`s' `xw' if smp, absorb(`few') vce(cluster `clus') ;
            replace smp = e(sample) ;
            estimates use "estimates/`nm'" ;
        } ;
        if `c' == 1 local N1 = e(N) ;
        assert e(N) == `N1' ;
        local b_`j'_`c'  = _b[r`j'_`s'] ;
        local se_`j'_`c' = _se[r`j'_`s'] ;
        quietly summarize r`j'_`s' if smp ;
        local sd_`j'_`c'  = r(sd) ;
        local sde_`j'_`c' = `b_`j'_`c'' * r(sd) ;
        quietly summarize `pn`j''_`s' if smp ;
        local np_`j'_`c'  = r(mean) ;
        local N_`j'    = e(N) ;
        local ninv_`j' = e(ninv) ;
        local mdv_`j'  = e(meandv) ;
    } ;
    display as result "`l`j'': N = " %9.0fc `N_`j'' "  mean renewal = " %5.3f `mdv_`j'' ;
    forvalues c = 1/3 {;
        display as result "   column `c': b = " %8.4f `b_`j'_`c'' " (" %6.4f `se_`j'_`c'' ")  one SD = "
            %7.4f `sde_`j'_`c'' "  SD = " %6.4f `sd_`j'_`c'' "  mean papers = " %5.2f `np_`j'_`c'' ;
    } ;
    display as result "   papers by part on this sample (acknowledging, other):" ;
    tabstat n_ackn_e n_ackn_m n_ackn_l n_noackn_e n_noackn_m n_noackn_l if smp, stat(mean) ;
    display as result "   correlation of the three versions on this sample:" ;
    pwcorr r`j'_f r`j'_e r`j'_l if smp ;
} ;
drop smp ;

/* -----------------------------------------------------------------------------
   Appendix Table G1, written row by row: one panel per measure
   ----------------------------------------------------------------------------- */
tempname fh ;
file open `fh' using "output/tables/table_G1.tex", write replace text ;
file write `fh' " & Full cycle & First two years & Last two years \\" _n ;
file write `fh' " & (1) & (2) & (3) \\" _n ;
file write `fh' "\midrule" _n ;
local pl1 "A" ; local pl2 "B" ; local pl3 "C" ; local pl4 "D" ;
forvalues j = 1/`nmeas' {;
    if `j' > 1 file write `fh' "\addlinespace" _n ;
    file write `fh' "\multicolumn{4}{l}{\textit{`pl`j''. `l`j''}} \\" _n ;
    local r1 "\quad Risk measure" ;
    local r2 "" ;
    local r3 "\quad Effect of one SD" ;
    local r4 "\quad Std.\ dev.\ of the measure" ;
    local r5 "\quad Mean papers behind the measure" ;
    forvalues c = 1/3 {;
        nr_star `b_`j'_`c'' `se_`j'_`c'' ;
        local vb  = strtrim(string(`b_`j'_`c'', "%7.4f")) ;
        local vse = strtrim(string(`se_`j'_`c'', "%6.4f")) ;
        local vsde = strtrim(string(`sde_`j'_`c'', "%7.4f")) ;
        local vsd = strtrim(string(`sd_`j'_`c'', "%6.3f")) ;
        local vnp = strtrim(string(`np_`j'_`c'', "%5.1f")) ;
        local r1 "`r1' & `vb'`r(star)'" ;
        local r2 "`r2' & (`vse')" ;
        local r3 "`r3' & `vsde'" ;
        local r4 "`r4' & `vsd'" ;
        local r5 "`r5' & `vnp'" ;
    } ;
    file write `fh' "`r1' \\" _n "`r2' \\" _n "`r3' \\" _n "`r4' \\" _n "`r5' \\" _n ;
    local vm = strtrim(string(`mdv_`j'', "%5.3f")) ;
    local vi = strtrim(string(`ninv_`j'', "%9.0fc")) ;
    local vc = strtrim(string(`N_`j'', "%9.0fc")) ;
    file write `fh' "\quad Mean of dependent variable & `vm' & `vm' & `vm' \\" _n ;
    file write `fh' "\quad Nb. of investigators & `vi' & `vi' & `vi' \\" _n ;
    file write `fh' "\quad Nb. of grant cycles & `vc' & `vc' & `vc' \\" _n ;
} ;
file close `fh' ;
type "output/tables/table_G1.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
