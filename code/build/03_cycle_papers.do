/* =============================================================================
   code/build/03_cycle_papers.do

   Purpose: Attribute papers to grant cycles, building one file of investigator
            x grant x cycle x paper pairs, for two kinds of papers:
            - acknowledging papers: the links that pass the author check
              (code/build/02_ackn_links.do);
            - non-acknowledging papers: the investigator's other papers in
              Author-ity, English original research with at most 20 authors,
              that do not acknowledge the cycle's own grant (they may acknowledge
              her other grants, or none).
              When Author-ity lists the investigator twice on a paper, the lower
              author position is kept. These papers feed the output controls.
            A paper published in year y belongs to the cycle of the same grant
            whose window, span_start to eval_year, contains y. The windows of a
            grant's cycles do not overlap, so a paper belongs to at most one cycle
            per grant; papers published before a grant's first cycle, in unpaid
            years between cycles, or after its last evaluation year belong to none.
            Author-ity ends in 2018, so non-acknowledging papers are complete only
            for windows that end by 2018.

   Input:
     - ${data}/build/cycles.dta                     (code/build/01_cycles.do)
     - ${data}/build/ackn_links.dta                 (code/build/02_ackn_links.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity, author_id x pmid
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_nb_of_authors_2025.dta

   Output:
     - ${data}/build/cycle_papers.dta   setnb project_number cycle pmid ackn pubyear
                                        author_seq nb_authrs, one row per pair
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/03_cycle_papers.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycle windows
   ----------------------------------------------------------------------------- */
use setnb project_number cycle span_start eval_year author_id using "${data}/build/cycles.dta", clear ;
/* the windows of a grant's cycles must not overlap */
bysort setnb project_number (cycle): gen byte overlap = _n > 1 & span_start <= eval_year[_n-1] ;
assert overlap == 0 ;
drop overlap ;
preserve ;
    keep setnb author_id ;
    drop if author_id == "" ;
    bysort setnb author_id: keep if _n == 1 ;
    tempfile inv ;
    save `inv' ;
    keep author_id ;
    bysort author_id: keep if _n == 1 ;
    tempfile invid ;
    save `invid' ;
restore ;
keep setnb project_number cycle span_start eval_year ;
tempfile win ;
save `win' ;

/* -----------------------------------------------------------------------------
   2. Acknowledging papers
   ----------------------------------------------------------------------------- */
use setnb project_number pmid pubyear author_seq nb_authrs using "${data}/build/ackn_links.dta", clear ;
local n_links = _N ;
joinby setnb project_number using `win' ;
keep if pubyear >= span_start & pubyear <= eval_year ;
drop span_start eval_year ;
gen byte ackn = 1 ;
gisid setnb project_number pmid ;
display as result "=== acknowledging links (investigator, grant, paper): all, and in a cycle window" ;
display as result "    `n_links'" ;
count ;
tempfile ack ;
save `ack' ;

/* -----------------------------------------------------------------------------
   3. Non-acknowledging papers
   ----------------------------------------------------------------------------- */
/* paper filters, one row per PMID: English original research, publication year, authors */
use pmid orgnl using "${pubmed_root}/pubmed/overall_typology_2025.dta", clear ;
gcollapse (max) orgnl, by(pmid) ;
tempfile typ ;
save `typ' ;
use pmid eng using "${pubmed_root}/pubmed/overall_language_2025.dta", clear ;
gcollapse (max) eng, by(pmid) ;
tempfile lng ;
save `lng' ;
use pmid year using "${pubmed_root}/pubmed/pubmed_universe_2025.dta", clear ;
bysort pmid: keep if _n == 1 ;
rename year pubyear ;
merge 1:1 pmid using `typ' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using `lng' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using "${pubmed_root}/pubmed/overall_nb_of_authors_2025.dta", keepusing(nb_authrs) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
keep if orgnl == 1 & eng == 1 & nb_authrs <= 20 ;
keep pmid pubyear nb_authrs ;
tempfile pm ;
save `pm' ;

/* papers acknowledging each of the investigator's grants: a paper is left out
   of a cycle's non-acknowledging papers only if it acknowledges that cycle's
   own grant */
use setnb project_number pmid using "${data}/build/ackn_links.dta", clear ;
bysort setnb project_number pmid: keep if _n == 1 ;
gen byte linked = 1 ;
tempfile linked ;
save `linked' ;

/* the investigators' Author-ity papers */
use author_id pmid author_postn using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `invid' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
/* the same author listed twice on a paper: keep the lower position */
bysort author_id pmid (author_postn): keep if _n == 1 ;
merge m:1 pmid using `pm' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
display as result "=== Author-ity papers of the investigators: English original research, at most 20 authors" ;
count ;
joinby author_id using `inv' ;
drop author_id ;
rename author_postn author_seq ;
joinby setnb using `win' ;
keep if pubyear >= span_start & pubyear <= eval_year ;
drop span_start eval_year ;
merge m:1 setnb project_number pmid using `linked' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
display as result "=== papers of a cycle window acknowledging the cycle's own grant (excluded here)" ;
count if linked == 1 ;
drop if linked == 1 ;
drop linked ;
gen byte ackn = 0 ;
gisid setnb project_number pmid ;
display as result "=== non-acknowledging papers in a cycle window (investigator, grant, paper)" ;
count ;

/* -----------------------------------------------------------------------------
   4. Both kinds, saved
   ----------------------------------------------------------------------------- */
append using `ack' ;
gisid setnb project_number cycle pmid ;
label var ackn       "Paper acknowledges the grant (author check passed)" ;
label var pubyear    "Publication year, PubMed 2025" ;
label var author_seq "Investigator's position in the author list" ;
label var nb_authrs  "Number of authors" ;
label data "Papers attributed to grant cycles, nih_risk" ;
notes: Built `c(current_date)' by code/build/03_cycle_papers.do. ;
order setnb project_number cycle pmid ackn pubyear author_seq nb_authrs ;
sort setnb project_number cycle pmid ;
compress ;
save "${data}/build/cycle_papers.dta", replace ;
display as result "=== paper-cycle pairs, by kind" ;
tab ackn ;

/* -----------------------------------------------------------------------------
   5. First look: papers per sample cycle
   ----------------------------------------------------------------------------- */
gen byte one = 1 ;
gcollapse (sum) n_pairs = one, by(setnb project_number cycle ackn) ;
reshape wide n_pairs, i(setnb project_number cycle) j(ackn) ;
rename (n_pairs0 n_pairs1) (n_noackn n_ackn) ;
tempfile cnt ;
save `cnt' ;
use setnb project_number cycle in_sample sep renewed eval_year using "${data}/build/cycles.dta", clear ;
merge 1:1 setnb project_number cycle using `cnt' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
replace n_ackn   = 0 if n_ackn == . ;
replace n_noackn = 0 if n_noackn == . ;
keep if in_sample & sep != 1 ;
display as result "=== sample cycles: acknowledging and other papers per cycle, by renewal" ;
tabstat n_ackn n_noackn, by(renewed) stat(mean p50 n) ;
display as result "=== other papers per cycle by evaluation year (Author-ity ends in 2018)" ;
tabstat n_ackn n_noackn if eval_year >= 2010, by(eval_year) stat(mean) nototal ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/03_cycle_papers.do */
