/* =============================================================================
   code/build/08_disruption.do

   Purpose: The disruption measure, one row per cycle: the highest within-year
            percentile of the disruption index DI_1^nok among the cycle's
            acknowledging papers (and the mean, as an alternative), rescaled to
            0-1. It is the second of the paper's four risk measures. Defined
            when at least one acknowledging paper has a defined index.

   Input:
     - ${data}/build/cycle_papers.dta       (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta   (code/build/05_paper_attributes.do)
     - ${data}/build/cycles.dta             (code/build/01_cycles.do), for the
                                            first look only

   Output:
     - ${data}/build/risk_disruption.dta   setnb project_number cycle n_disr
                                           di1nok_ackn_maxpctl di1nok_ackn_meanpctl (0-1)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/08_disruption.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta" if ackn == 1, clear ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(di1_nok_pctl) ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;
keep if di1_nok_pctl < . ;
gcollapse (count) n_disr = di1_nok_pctl (max) di1nok_ackn_maxpctl = di1_nok_pctl
          (mean) di1nok_ackn_meanpctl = di1_nok_pctl, by(setnb project_number cycle) ;
replace di1nok_ackn_maxpctl  = di1nok_ackn_maxpctl / 100 ;
replace di1nok_ackn_meanpctl = di1nok_ackn_meanpctl / 100 ;

label var n_disr               "Acknowledging papers with a defined disruption index" ;
label var di1nok_ackn_maxpctl  "Disruption: max within-year percentile of DI_1^nok, ackn. papers (0-1)" ;
label var di1nok_ackn_meanpctl "Mean within-year percentile of DI_1^nok, acknowledging papers (0-1)" ;
label data "Disruption measure by cycle, nih_risk" ;
notes: Built `c(current_date)' by code/build/08_disruption.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_disruption.dta", replace ;

/* first look, sample cycles */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta", keepusing(in_sample sep renewed) ;
tab _merge ;
drop if _merge == 1 ;
keep if in_sample & sep != 1 ;
display as result "=== sample cycles with a disruption measure, and the measure by renewal" ;
count if di1nok_ackn_maxpctl < . ;
tabstat di1nok_ackn_maxpctl di1nok_ackn_meanpctl, by(renewed) stat(mean sd n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/08_disruption.do */
