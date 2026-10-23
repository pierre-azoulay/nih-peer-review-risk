/* =============================================================================
   code/analysis/30_table_F1.do

   Purpose: is the penalty on risk taking steeper for novel work (Appendix F,
            novelty)? Table F1: for each of the four risk measures, on the
            cycles of its Table 2 sample where the share of new noun phrases
            (the headline measure of novelty) is defined, renewal on an
            indicator for high novelty (the share above its median within
            the evaluation year) alone (columns 1, 4, 7, 10), with the risk
            measure (2, 5, 8, 11), and with their interaction (3, 6, 9, 12).
            The risk measure is continuous, scaled as in Figure 5 and Table I1
            (code/analysis/15_figure_5_table_I1.do), centered at its mean on
            the regression's cycles; every regression has the grant output
            controls of Table 2 and standard errors clustered by investigator
            and by grant.
            The samples are fixed first, for each risk measure: Table 2's
            sample, and its cycles where the share of new noun phrases is
            defined, each by a regression of the risk measure alone on it, so
            that the regressions of Table F1 use exactly its cycles (no
            further singleton can be dropped); the log keeps both, whose
            coefficients on the risk measure the text compares, and the gap
            of high novelty in percent of the mean renewal rate. Every
            regression is saved whole.

   Input:
     - ${public}/nih_risk_public.dta         (code/build/34_public_file.do)

   Output:
     - output/tables/table_F1.tex (rows only, written row by row)
     - estimates/table_F1_base_<t>.ster and table_F1_oa_<t>_phr.ster (the
       regressions that fix the samples), estimates/table_F1_samples.dta
       (the samples), estimates/table_F1_o_<t>_phr_50.ster (columns 3, 6, 9,
       12), table_F1_t3a_<t>.ster and table_F1_t3b_<t>.ster (the other
       columns); <t> = tails disr pivot so

   Note: a first argument of 0 (do code/analysis/30_table_F1.do 0) reuses the
         saved estimates and samples and redraws the table.
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

log using "logs/30_table_F1.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate and save; 0 = reuse the saved estimates and samples */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

/* -----------------------------------------------------------------------------
   1. Data
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;

/* the four measures, scaled as in Figure 5 and Table I1
   (code/analysis/15_figure_5_table_I1.do): tails and disruption in units of
   10 percentile points, pivoting and standing out as fractions */
forvalues j = 1/`nmeas' {;
    gen double rm_`t`j'' = `m`j'' * cond(`j' <= 2, 10, 1) ;
    label variable rm_`t`j'' "`l`j''" ;
} ;

/* the headline measure of novelty, the share of new noun phrases */
local nv1 "frac_new_phrase_oth" ;  local nt1 "phr" ;   local nl1 "New noun phrases" ;
assert "`nv1'" == "`nov'" ;

/* high novelty: percentiles within evaluation year, computed once on every
   analysis cycle where the measure is defined, so that a cycle's group does
   not depend on the regression's sample; Table F1 uses the share of new noun
   phrases above its median (h50_phr) */
gquantiles np_phr = `nv1' if !missing(`nv1'), xtile nquantiles(100) by(`pctby') ;
gen byte h50_phr = (np_phr > 50) if !missing(np_phr) ;
gen byte has_phr = !missing(`nv1') ;

/* -----------------------------------------------------------------------------
   2. The samples. For each risk measure: Table 2's sample (the measure alone
      with the grant output controls, Table 2's linear check), and its cycles
      where the share of new noun phrases is defined (sown_<t>_phr), the
      sample of Table F1. Each sample is fixed by a regression of the measure
      alone on it (saved: the slope without the interaction), so that the
      regressions with the interaction use exactly its cycles (no further
      singleton can be dropped).
   ----------------------------------------------------------------------------- */
if `run_regs' {;
    forvalues j = 1/`nmeas' {;
        local t "`t`j''" ;
        reghdfe `dv' rm_`t' `x3', absorb(`fe3') vce(cluster `clus') ;
        gen byte sbase_`t' = e(sample) ;
        nr_post ;
        estimates save "estimates/table_F1_base_`t'.ster", replace ;
        forvalues n = 1/1 {;
            local nt "`nt`n''" ;
            reghdfe `dv' rm_`t' `x3' if sbase_`t' & has_`nt', absorb(`fe3') vce(cluster `clus') ;
            gen byte sown_`t'_`nt' = e(sample) ;
            nr_post ;
            estimates save "estimates/table_F1_oa_`t'_`nt'.ster", replace ;
        } ;
    } ;
    preserve ;
    keep inv_id grant_id cycle sbase_* sown_* ;
    compress ;
    sort inv_id grant_id cycle ;
    save "estimates/table_F1_samples.dta", replace ;
    restore ;
} ;
else {;
    merge 1:1 inv_id grant_id cycle using "estimates/table_F1_samples.dta" ;
    tab _merge ;
    assert _merge == 3 ;
    drop _merge ;
} ;

/* -----------------------------------------------------------------------------
   4. Columns 3, 6, 9 and 12 of Table F1: for each risk measure, on its
      cycles where the share of new noun phrases is defined (sample o, the
      measure's own sample; n = 1, the share of new noun phrases; p = 50, the
      median), renewal on the
      centered measure (risk), the high-novelty
      indicator (hinov) and their interaction (riskxhi). The coefficient on
      risk is the slope among the other cycles; risk + riskxhi the slope
      among cycles of high novelty; hinov the gap at the measure's mean. The
      names are the same in every regression, the file name identifies it.
   ----------------------------------------------------------------------------- */
if `run_regs' {;
    foreach s in o {;
        forvalues j = 1/`nmeas' {;
            local t "`t`j''" ;
            forvalues n = 1/1 {;
                local nt "`nt`n''" ;
                local smp "sown_`t'_`nt'" ;
                quietly summarize rm_`t' if `smp' ;
                local mr = r(mean) ;
                local sr = r(sd) ;
                local ns = r(N) ;
                capture drop risk ;
                gen double risk = rm_`t' - `mr' ;
                foreach p in 50 {;
                    capture drop hinov riskxhi ;
                    gen byte hinov = h`p'_`nt' ;
                    gen double riskxhi = risk * hinov ;
                    quietly reghdfe `dv' risk hinov riskxhi `x3' if `smp', absorb(`fe3') vce(cluster `clus') ;
                    assert e(N) == `ns' ;
                    nr_post ;
                    estadd scalar mrisk = `mr' ;
                    estadd scalar sdrisk = `sr' ;
                    quietly summarize hinov if e(sample) ;
                    estadd scalar shgrp = r(mean) ;
                    estadd scalar cut = `p' ;
                    estadd local measure "`t'" ;
                    estadd local novelty "`nt'" ;
                    estadd local sampname "`s'" ;
                    estimates save "estimates/table_F1_`s'_`t'_`nt'_`p'.ster", replace ;
                    display as text "`s' `t' `nt' `p': interaction " %8.4f _b[riskxhi] " (" %7.4f _se[riskxhi] "), slope among the others " %8.4f _b[risk] ", N " %8.0fc e(N) ;
                } ;
            } ;
        } ;
    } ;
    capture drop risk hinov riskxhi ;
} ;

/* -----------------------------------------------------------------------------
   5. Table F1: the headline measure of novelty, new noun phrases above the
      median, on each risk measure's cycles where it is defined. For each
      risk measure, on the same cycles, (1) the high-novelty indicator alone,
      (2) with the risk measure, (3) with their interaction, the measure
      centered at its mean on these cycles; column 3 is the regression of
      section 4, read back from its saved estimates. Columns 1 and 2 are
      estimated whenever their files are missing, so that a run with a first
      argument of 0 adds them without re-estimating the others.
   ----------------------------------------------------------------------------- */
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    local smp "sown_`t'_phr" ;
    local miss = 0 ;
    capture confirm file "estimates/table_F1_t3a_`t'.ster" ;
    if _rc local miss = 1 ;
    capture confirm file "estimates/table_F1_t3b_`t'.ster" ;
    if _rc local miss = 1 ;
    if `run_regs' | `miss' {;
        quietly summarize rm_`t' if `smp' ;
        local mr = r(mean) ;
        local sr = r(sd) ;
        local ns = r(N) ;
        capture drop risk hinov riskxhi ;
        gen double risk = rm_`t' - `mr' ;
        gen byte hinov = h50_phr ;
        quietly summarize hinov if `smp' ;
        local sh = r(mean) ;
        reghdfe `dv' hinov `x3' if `smp', absorb(`fe3') vce(cluster `clus') ;
        assert e(N) == `ns' ;
        nr_post ;
        estadd scalar mrisk = `mr' ;
        estadd scalar sdrisk = `sr' ;
        estadd scalar shgrp = `sh' ;
        estimates save "estimates/table_F1_t3a_`t'.ster", replace ;
        reghdfe `dv' risk hinov `x3' if `smp', absorb(`fe3') vce(cluster `clus') ;
        assert e(N) == `ns' ;
        nr_post ;
        estadd scalar mrisk = `mr' ;
        estadd scalar sdrisk = `sr' ;
        estadd scalar shgrp = `sh' ;
        estimates save "estimates/table_F1_t3b_`t'.ster", replace ;
        capture drop risk hinov ;
    } ;
} ;

display as result _newline "=== Table F1: new noun phrases above the median, alone (a), with the risk measure (b), with the interaction (c)" ;
local models "" ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    estimates use "estimates/table_F1_t3a_`t'.ster" ;
    estimates store t3a_`t' ;
    estimates use "estimates/table_F1_t3b_`t'.ster" ;
    estimates store t3b_`t' ;
    estimates use "estimates/table_F1_o_`t'_phr_50.ster" ;
    estimates store t3c_`t' ;
    local models "`models' t3a_`t' t3b_`t' t3c_`t'" ;
} ;
esttab `models', keep(hinov risk riskxhi) order(hinov risk riskxhi) b(%7.4f) se(%7.4f)
    star(+ 0.10 * 0.05 ** 0.01) stats(N meandv shgrp ninv r2_a, fmt(%9.0fc %5.3f %5.3f %9.0fc %6.4f)) ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    estimates restore t3a_`t' ;
    local h1 = _b[hinov] ;
    estimates restore t3b_`t' ;
    local h2 = _b[hinov] ;
    estimates restore t3c_`t' ;
    local h3 = _b[hinov] ;
    display as text "`t': high novelty " %7.4f `h1' " alone, " %7.4f `h2' " with the measure ("
        %5.1f 100 * (`h2' - `h1') / `h1' "%), " %7.4f `h3' " with the interaction, at the measure's mean; in percent of the mean renewal rate "
        %5.1f 100 * `h1' / e(meandv) ", " %5.1f 100 * `h2' / e(meandv) ", " %5.1f 100 * `h3' / e(meandv) ;
} ;

/* the table, written row by row in Table J1's layout: under the risk
   measure and the interaction, in brackets, the coefficient times the
   measure's s.d. on these cycles */
tempname fh ;
file open `fh' using "output/tables/table_F1.tex", write replace text ;
file write `fh' " & \multicolumn{3}{c}{`l1'} & & \multicolumn{3}{c}{`l2'} & & \multicolumn{3}{c}{`l3'} & & \multicolumn{3}{c}{`l4'} \\" _n ;
file write `fh' "\cmidrule(lr){2-4}\cmidrule(lr){6-8}\cmidrule(lr){10-12}\cmidrule(lr){14-16}" _n ;
file write `fh' " & (1) & (2) & (3) & & (4) & (5) & (6) & & (7) & (8) & (9) & & (10) & (11) & (12) \\" _n ;
file write `fh' "\midrule" _n ;
local Hrow "High novelty" ; local Hse "" ;
local Rrow "Risk measure" ; local Rse "" ; local Rsd "" ;
local Xrow "Risk measure \(\times\) high novelty" ; local Xse "" ; local Xsd "" ;
local mrow "Mean of dependent variable" ;
local srow "Share of cycles of high novelty" ;
local irow "Nb.\ of investigators" ;
local nrow "Nb.\ of grant cycles" ;
local arow "Adjusted \(R^2\)" ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    if `j' > 1 {;
        foreach r in Hrow Hse Rrow Rse Rsd Xrow Xse Xsd mrow srow irow nrow arow {;
            local `r' "``r'' &" ;
        } ;
    } ;
    foreach m in t3a t3b t3c {;
        estimates restore `m'_`t' ;
        nr_star `=_b[hinov]' `=_se[hinov]' ;
        local Hrow "`Hrow' & `=strtrim(string(_b[hinov], "%7.4f"))'`r(star)'" ;
        local Hse  "`Hse' & (`=strtrim(string(_se[hinov], "%6.4f"))')" ;
        if "`m'" == "t3a" {;
            local Rrow "`Rrow' & " ;
            local Rse  "`Rse' & " ;
            local Rsd  "`Rsd' & " ;
        } ;
        else {;
            nr_star `=_b[risk]' `=_se[risk]' ;
            local Rrow "`Rrow' & `=strtrim(string(_b[risk], "%7.4f"))'`r(star)'" ;
            local Rse  "`Rse' & (`=strtrim(string(_se[risk], "%6.4f"))')" ;
            local Rsd  "`Rsd' & {\footnotesize [`=strtrim(string(_b[risk] * e(sdrisk), "%7.4f"))']}" ;
        } ;
        if "`m'" != "t3c" {;
            local Xrow "`Xrow' & " ;
            local Xse  "`Xse' & " ;
            local Xsd  "`Xsd' & " ;
        } ;
        else {;
            nr_star `=_b[riskxhi]' `=_se[riskxhi]' ;
            local Xrow "`Xrow' & `=strtrim(string(_b[riskxhi], "%7.4f"))'`r(star)'" ;
            local Xse  "`Xse' & (`=strtrim(string(_se[riskxhi], "%6.4f"))')" ;
            local Xsd  "`Xsd' & {\footnotesize [`=strtrim(string(_b[riskxhi] * e(sdrisk), "%7.4f"))']}" ;
        } ;
        local mrow "`mrow' & `=strtrim(string(e(meandv), "%5.3f"))'" ;
        local srow "`srow' & `=strtrim(string(e(shgrp), "%5.3f"))'" ;
        local irow "`irow' & `=strtrim(string(e(ninv), "%9.0fc"))'" ;
        local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
        local arow "`arow' & `=strtrim(string(e(r2_a), "%6.4f"))'" ;
    } ;
} ;
file write `fh' "`Hrow' \\" _n "`Hse' \\" _n "\addlinespace" _n ;
file write `fh' "`Rrow' \\" _n "`Rse' \\" _n "`Rsd' \\" _n "\addlinespace" _n ;
file write `fh' "`Xrow' \\" _n "`Xse' \\" _n "`Xsd' \\" _n "\midrule" _n ;
file write `fh' "`mrow' \\" _n "`srow' \\" _n "`irow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
file close `fh' ;
type "output/tables/table_F1.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/analysis/30_table_F1.do */
