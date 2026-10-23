/* =============================================================================
   code/build/17_cycle_cites.do

   Purpose: citations to each cycle's papers, and the next cycle's output.
            Citations are the five-year OpenAlex citations of
            paper_attributes.dta (cite5), the window of the tails measure, so
            that papers of every year are counted over the same horizon: the
            citations to the acknowledging papers enter Tables 1b and 1d, those
            to the investigator's other papers of the cycle Table 1b. The next
            cycle is cycle + 1 of the same investigator and grant, whatever
            its sample status: it is taken from the cycle file, not from the
            analysis sample, so that the next cycle's output is defined
            whenever that cycle exists, in the analysis sample or not, and is
            zero when that cycle has no acknowledging paper.

   Input:
     - ${data}/build/cycles.dta             (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta       (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta   (code/build/05_paper_attributes.do)

   Output:
     - ${data}/build/cycle_cites.dta, one row per cycle: n_ackn_all,
       cites5_ackn, cites5_noackn, and next_n_ackn, next_cites5_ackn (the next
       cycle's acknowledging papers and their citations; missing when the
       grant has no next cycle)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/17_cycle_cites.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
gen byte one = 1 ;
gen double c_ack = cite5 if ackn == 1 ;
gen double c_oth = cite5 if ackn == 0 ;
gen byte o_ack = ackn == 1 ;
gcollapse (sum) n_ackn_all = o_ack cites5_ackn = c_ack cites5_noackn = c_oth,
    by(setnb project_number cycle) ;
tempfile pc ;
save `pc' ;

use setnb project_number cycle using "${data}/build/cycles.dta", clear ;
merge 1:1 setnb project_number cycle using `pc' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
foreach v in n_ackn_all cites5_ackn cites5_noackn {;
    replace `v' = 0 if missing(`v') ;
} ;

/* the next cycle of the same investigator and grant */
sort setnb project_number cycle ;
by setnb project_number: gen next_n_ackn      = n_ackn_all[_n+1]  if cycle[_n+1] == cycle + 1 ;
by setnb project_number: gen next_cites5_ackn = cites5_ackn[_n+1] if cycle[_n+1] == cycle + 1 ;

label variable n_ackn_all       "Acknowledging papers in the cycle window" ;
label variable cites5_ackn      "Five-year citations to the cycle's acknowledging papers" ;
label variable cites5_noackn    "Five-year citations to the investigator's other papers of the cycle" ;
label variable next_n_ackn      "Acknowledging papers of the next cycle (missing if none)" ;
label variable next_cites5_ackn "Five-year citations to the next cycle's acknowledging papers" ;
summarize ;

gisid setnb project_number cycle ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_cites.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
