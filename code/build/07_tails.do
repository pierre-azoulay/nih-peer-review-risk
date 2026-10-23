/* =============================================================================
   code/build/07_tails.do

   Purpose: The tails measure, one row per cycle: the spread between the most and
            the least cited of the cycle's acknowledging papers, each paper's
            citations expressed as a percentile within its publication year
            (cite5_pctl, OpenAlex citations through the fifth year after
            publication), rescaled to 0-1. It is the first of the paper's four
            risk measures. Defined when at least two acknowledging papers have a
            percentile: a spread needs two papers.

   Input:
     - ${data}/build/cycle_papers.dta       (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta   (code/build/05_paper_attributes.do)
     - ${data}/build/cycles.dta             (code/build/01_cycles.do), for the
                                            first look only

   Output:
     - ${data}/build/risk_tails.dta   setnb project_number cycle n_tails
                                      spread_minmax_ackn max_pctl_ackn min_pctl_ackn
                                      p50_pctl_ackn (all on a 0-1 scale)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/07_tails.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta" if ackn == 1, clear ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5_pctl) ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;
keep if cite5_pctl < . ;
gcollapse (count) n_tails = cite5_pctl (max) max_pctl_ackn = cite5_pctl
          (min) min_pctl_ackn = cite5_pctl (p50) p50_pctl_ackn = cite5_pctl,
          by(setnb project_number cycle) ;
foreach v in max_pctl_ackn min_pctl_ackn p50_pctl_ackn {;
    replace `v' = `v' / 100 ;
    replace `v' = . if n_tails < 2 ;
} ;
gen double spread_minmax_ackn = max_pctl_ackn - min_pctl_ackn ;

label var n_tails            "Acknowledging papers with a citation percentile" ;
label var spread_minmax_ackn "Tails: max minus min citation percentile, acknowledging papers (0-1)" ;
label var max_pctl_ackn      "Highest citation percentile, acknowledging papers (0-1)" ;
label var min_pctl_ackn      "Lowest citation percentile, acknowledging papers (0-1)" ;
label var p50_pctl_ackn      "Median citation percentile, acknowledging papers (0-1)" ;
label data "Tails measure by cycle, nih_risk" ;
notes: Built `c(current_date)' by code/build/07_tails.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_tails.dta", replace ;

/* first look, sample cycles */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta", keepusing(in_sample sep renewed) ;
tab _merge ;
drop if _merge == 1 ;
keep if in_sample & sep != 1 ;
display as result "=== sample cycles with a tails measure, and the measure by renewal" ;
count if spread_minmax_ackn < . ;
tabstat spread_minmax_ackn max_pctl_ackn min_pctl_ackn, by(renewed) stat(mean sd n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/07_tails.do */
