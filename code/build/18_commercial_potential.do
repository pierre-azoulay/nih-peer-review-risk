/* =============================================================================
   code/build/18_commercial_potential.do

   Purpose: the commercial potential of each cycle's acknowledging papers, for
            Tables 1e and 3: the mean, over the cycle's acknowledging papers
            that have a score, of Masclans' commercial-potential index
            (compot, the probability that a patent will cite the paper;
            consolidated_comm_pot_2026.dta). The index covers papers published
            from 1990, so cycles whose papers all predate it have no value.

   Input:
     - ${data}/build/cycle_papers.dta   (code/build/03_cycle_papers.do)
     - ${pubmed_root}/reliance_on_science/comm_pot/consolidated_comm_pot_2026.dta
       commercial-potential index of PubMed papers (Masclans)

   Output:
     - ${data}/build/cycle_commpot.dta, one row per cycle with an
       acknowledging paper: compot_mean (missing when no paper is scored),
       n_compot (scored acknowledging papers)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/18_commercial_potential.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use setnb project_number cycle pmid pubyear ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
drop ackn ;
gisid setnb project_number cycle pmid ;
merge m:1 pmid using "${pubmed_root}/reliance_on_science/comm_pot/consolidated_comm_pot_2026.dta",
    keepusing(compot) ;
tab _merge ;
drop if _merge == 2 ;
gen byte scored = (_merge == 3) & !missing(compot) ;
drop _merge ;
display as text "acknowledging papers with a score, by publication decade:" ;
gen int decade = 10 * floor(pubyear / 10) ;
tabstat scored, by(decade) stat(mean n) ;
summarize compot, detail ;

gcollapse (mean) compot_mean = compot (sum) n_compot = scored, by(setnb project_number cycle) ;
replace compot_mean = . if n_compot == 0 ;
label variable compot_mean "Mean commercial potential of the scored acknowledging papers (Masclans)" ;
label variable n_compot    "Acknowledging papers with a commercial-potential score" ;
count if n_compot > 0 ;
display as text "cycles with a scored paper: " r(N) " of " _N ;
summarize compot_mean, detail ;

sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_commpot.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
