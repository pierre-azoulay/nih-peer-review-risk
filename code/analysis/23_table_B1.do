/* =============================================================================
   code/analysis/23_table_B1.do

   Purpose: Appendix Table B1, the extreme tail outcomes measure taken apart
            into the level and the spread of citation outcomes. Its
            variables are the median, the upper half-spread (max minus
            median) and the lower half-spread (median minus min) of the
            citation percentiles of the cycle's acknowledging papers,
            computed on all of them (columns 1 to 5, the variables of
            risk_tail_projects.dta) and on the papers on which the
            investigator is first, last or single author only (columns 6 to
            10, computed here). In each panel: the range, max minus min,
            alone (the paper's extreme tail measure, for comparison), the
            range with the median, the upper half-spread alone, the lower one
            alone, and the median with both half-spreads. Grant output
            controls of Table 2, units of 10 percentile points. Both panels
            use the same cycles, those with at least three first- or
            last-author papers with a citation percentile, so that they
            differ only in the papers behind the measures. The log gives the
            number of these cycles and the correlations among the variables,
            which Appendix B's text quotes.

   Input:
     - ${public}/nih_risk_public.dta           (code/build/34_public_file.do)
       with the variables of risk_tail_projects.dta (code/build/27_tail_projects.do)
       and the first- or last-author percentiles, computed there from
       cycle_papers.dta and paper_attributes.dta (code/build/03, 05)

   Output:
     - output/tables/table_B1.tex   Table B1, written row by row
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

log using "logs/23_table_B1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* n_own, o_med, o_up, o_lo: the citation percentiles of the acknowledging
   papers on which the investigator is first, last or single author,
   computed in code/build/34_public_file.do from the papers of the cycle */
use "`afile'", clear ;
foreach v in tl_med tl_up tl_lo {;
    replace `v' = `v' * 10 ;
} ;
label variable o_med "Median, first- or last-author papers" ;
label variable o_up  "Max - median, first- or last-author papers" ;
label variable o_lo  "Median - min, first- or last-author papers" ;

/* cycles with at least three first- or last-author papers (and all-paper measures, mean impact factor) */
gen byte smp = n_own >= 3 & n_own < . & !missing(tl_med) & !missing(log_meanjif_all) ;
display as result "=== cycles with at least three first- or last-author papers with a percentile" ;
count if smp ;
summarize n_own n_tails if smp ;
correlate o_med o_up o_lo tl_med tl_up tl_lo if smp ;

/* Table B1: column 10 (first- or last-author papers, all three variables)
   fixes the sample */
local p1 "tl" ;
local p2 "o" ;
reghdfe `dv' o_med o_up o_lo `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
replace smp = e(sample) ;
nr_post ;
local N = e(N) ;
local ni = e(ninv) ;
local md = e(meandv) ;

/* in each panel: the range alone (the paper's measure, max minus min), the
   range with the median, each half-spread alone, then the median with both
   half-spreads */
forvalues g = 1/2 {;
    local v "`p`g''" ;
    local c0 = 5 * (`g' - 1) ;
    capture drop `v'_rg ;
    gen double `v'_rg = `v'_up + `v'_lo ;
    reghdfe `dv' `v'_rg `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
    local b`=`c0'+1'_rg = _b[`v'_rg] ;
    local s`=`c0'+1'_rg = _se[`v'_rg] ;
    reghdfe `dv' `v'_rg `v'_med `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
    foreach w in rg med {;
        local b`=`c0'+2'_`w' = _b[`v'_`w'] ;
        local s`=`c0'+2'_`w' = _se[`v'_`w'] ;
    } ;
    reghdfe `dv' `v'_up `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
    local b`=`c0'+3'_up = _b[`v'_up] ;
    local s`=`c0'+3'_up = _se[`v'_up] ;
    reghdfe `dv' `v'_lo `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
    local b`=`c0'+4'_lo = _b[`v'_lo] ;
    local s`=`c0'+4'_lo = _se[`v'_lo] ;
    reghdfe `dv' `v'_med `v'_up `v'_lo `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
    assert e(N) == `N' ;
    foreach w in med up lo {;
        local b`=`c0'+5'_`w' = _b[`v'_`w'] ;
        local s`=`c0'+5'_`w' = _se[`v'_`w'] ;
    } ;
    test `v'_up = `v'_lo ;
    local pv`g' = strtrim(string(r(p), "%5.3f")) ;
    /* log only: the sum of the two halves, the effect of widening both by 10
       points around the same median */
    lincom `v'_up + `v'_lo ;
} ;
correlate tl_rg tl_med o_rg o_med if smp ;
quietly summarize n_tails if smp ;
local np1 = strtrim(string(r(mean), "%4.1f")) ;
quietly summarize n_own if smp ;
local np2 = strtrim(string(r(mean), "%4.1f")) ;

/* the fragment; a dollar sign would read as a Stata global, so the math is
   written with \( \) */
tempname fh ;
file open `fh' using "output/tables/table_B1.tex", write replace text ;
file write `fh' " & \multicolumn{5}{c}{All publications} & & \multicolumn{5}{c}{First- or last-author publications} \\" _n ;
file write `fh' "\cmidrule(lr){2-6}\cmidrule(lr){8-12}" _n ;
file write `fh' " & (1) & (2) & (3) & (4) & (5) & & (6) & (7) & (8) & (9) & (10) \\" _n "\midrule" _n ;
local rl_rg  "Max \(-\) Min" ;
local rl_med "Median Citation Percentile" ;
local rl_up  "Max \(-\) Median" ;
local rl_lo  "Median \(-\) Min" ;
foreach w in rg med up lo {;
    local r1 "\multirow{2}{*}{`rl_`w''}" ;
    local r2 "" ;
    forvalues c = 1/10 {;
        if "`b`c'_`w''" != "" {;
            nr_star `b`c'_`w'' `s`c'_`w'' ;
            local vb = strtrim(string(`b`c'_`w'', "%7.4f")) ;
            local vs = strtrim(string(`s`c'_`w'', "%6.4f")) ;
            local r1 "`r1' & `vb'`r(star)'" ;
            local r2 "`r2' & (`vs')" ;
        } ;
        else {;
            local r1 "`r1' &" ;
            local r2 "`r2' &" ;
        } ;
        if `c' == 5 {;
            local r1 "`r1' &" ;
            local r2 "`r2' &" ;
        } ;
    } ;
    file write `fh' "`r1' \\" _n "`r2' \\" _n ;
    if "`w'" != "lo" file write `fh' "\addlinespace" _n ;
} ;
local vm = strtrim(string(`md', "%5.3f")) ;
local vn = strtrim(string(`N', "%9.0fc")) ;
local vi = strtrim(string(`ni', "%9.0fc")) ;
file write `fh' "\midrule" _n ;
file write `fh' "\(H_{0}\): max \(-\) median = median \(-\) min & & & & & \(p = `pv1'\) & & & & & & \(p = `pv2'\) \\" _n ;
file write `fh' "Mean nb. of publications behind the measures & `np1' & `np1' & `np1' & `np1' & `np1' & & `np2' & `np2' & `np2' & `np2' & `np2' \\" _n ;
file write `fh' "Mean of dependent variable & `vm' & `vm' & `vm' & `vm' & `vm' & & `vm' & `vm' & `vm' & `vm' & `vm' \\" _n ;
file write `fh' "Nb. of investigators & `vi' & `vi' & `vi' & `vi' & `vi' & & `vi' & `vi' & `vi' & `vi' & `vi' \\" _n ;
file write `fh' "Nb. of grant cycles & `vn' & `vn' & `vn' & `vn' & `vn' & & `vn' & `vn' & `vn' & `vn' & `vn' \\" _n ;
file close `fh' ;
type "output/tables/table_B1.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
