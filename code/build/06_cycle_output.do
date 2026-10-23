/* =============================================================================
   code/build/06_cycle_output.do

   Purpose: The output controls of Table 2, one row per cycle, from the papers
            attributed to the cycle (code/build/03_cycle_papers.do) and their
            attributes (code/build/05_paper_attributes.do):
            - n_ackn, n_noackn: acknowledging papers and the investigator's other
              papers in the cycle's window; bin_ackn, bin_noackn group them in
              eleven bins (0, 1, 2, 3, 4, 5, 6-7, 8-10, 11-15, 16-20, 21+), whose
              indicators enter the regressions as controls;
            - meanjif_all (and _ackn, _noackn): mean impact factor of the papers
              with one; log_meanjif_all = ln(meanjif_all);
            - journal_hs_ackn, journal_hs_noackn: at least one paper of that kind
              in NEJM, Science, Cell or Nature.
            authority_partial flags cycles whose window runs past 2018, where
            Author-ity, and so n_noackn, is incomplete.

   Input:
     - ${data}/build/cycles.dta             (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta       (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta   (code/build/05_paper_attributes.do)

   Output:
     - ${data}/build/cycle_output.dta   one row per setnb x project_number x cycle
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/06_cycle_output.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* papers of each cycle, with their attributes */
use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(jif journal_hs) ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;

gen byte one_ackn  = ackn == 1 ;
gen byte one_noack = ackn == 0 ;
gen double jif_ackn   = jif if ackn == 1 ;
gen double jif_noackn = jif if ackn == 0 ;
gen byte hs_ackn   = journal_hs * (ackn == 1) ;
gen byte hs_noackn = journal_hs * (ackn == 0) ;
gcollapse (sum) n_ackn = one_ackn n_noackn = one_noack
          (mean) meanjif_all = jif meanjif_ackn = jif_ackn meanjif_noackn = jif_noackn
          (max) journal_hs_ackn = hs_ackn journal_hs_noackn = hs_noackn,
          by(setnb project_number cycle) ;
tempfile out ;
save `out' ;

/* every cycle of the cycle file, with zeros where it has no paper */
use setnb project_number cycle eval_year in_sample sep renewed using "${data}/build/cycles.dta", clear ;
merge 1:1 setnb project_number cycle using `out' ;
tab _merge ;
drop if _merge == 2 ;
assert _merge != 2 ;
drop _merge ;
foreach v in n_ackn n_noackn journal_hs_ackn journal_hs_noackn {;
    replace `v' = 0 if `v' == . ;
} ;
gen double log_meanjif_all = ln(meanjif_all) ;
gen byte authority_partial = eval_year > 2018 ;

/* the bins of the paper counts */
capture label drop npapers ;
label define npapers 0 "0" 1 "1" 2 "2" 3 "3" 4 "4" 5 "5" 6 "6-7" 8 "8-10" 11 "11-15" 16 "16-20" 21 "21+" ;
foreach k in ackn noackn {;
    gen byte bin_`k' = cond(n_`k' <= 5, n_`k', cond(n_`k' <= 7, 6, cond(n_`k' <= 10, 8,
                        cond(n_`k' <= 15, 11, cond(n_`k' <= 20, 16, 21))))) ;
    label values bin_`k' npapers ;
} ;

label var n_ackn            "Acknowledging papers in the cycle's window" ;
label var n_noackn          "The investigator's other papers in the window (Author-ity, through 2018)" ;
label var bin_ackn          "n_ackn in bins" ;
label var bin_noackn        "n_noackn in bins" ;
label var meanjif_all       "Mean impact factor of the cycle's papers with one" ;
label var meanjif_ackn      "Mean impact factor, acknowledging papers" ;
label var meanjif_noackn    "Mean impact factor, other papers" ;
label var log_meanjif_all   "ln(meanjif_all)" ;
label var journal_hs_ackn   "An acknowledging paper in NEJM, Science, Cell or Nature" ;
label var journal_hs_noackn "Another paper in NEJM, Science, Cell or Nature" ;
label var authority_partial "Window runs past 2018, where Author-ity ends" ;
keep setnb project_number cycle n_ackn n_noackn bin_ackn bin_noackn meanjif_all meanjif_ackn
     meanjif_noackn log_meanjif_all journal_hs_ackn journal_hs_noackn authority_partial
     in_sample sep renewed ;
label data "Cycle-level output controls, nih_risk" ;
notes: Built `c(current_date)' by code/build/06_cycle_output.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_output.dta", replace ;

/* first look, sample cycles */
keep if in_sample & sep != 1 ;
display as result "=== sample cycles: output controls by renewal" ;
tabstat n_ackn n_noackn meanjif_all journal_hs_ackn journal_hs_noackn authority_partial,
    by(renewed) stat(mean) ;
display as result "=== cycles without a paper with an impact factor (log_meanjif_all missing)" ;
count if log_meanjif_all == . ;
tab bin_ackn renewed, col ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/06_cycle_output.do */
