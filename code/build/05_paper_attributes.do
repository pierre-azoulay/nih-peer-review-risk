/* =============================================================================
   code/build/05_paper_attributes.do

   Purpose: Paper-level attributes for every paper the project can use: the papers
            linked by RePORTER to the cycle file's grants and every Author-ity paper
            of its investigators (so the papers published before a grant's first
            cycle, on which the lagged risk measures of code/build/25_lagged_risk.do
            rest, are covered too).
            - cite5, cite5_pctl: OpenAlex citations from PubMed papers through the
              end of the fifth year after publication (through 2025 for papers
              published after 2020), and its midrank percentile (0 to 100) within
              publication year among all PubMed papers with an OpenAlex record.
              A paper with an OpenAlex record but no row in the citation panel has
              never been cited and counts as 0; a paper without an OpenAlex record
              has no value.
            - di1_nok, di1_nok_pctl: the disruption index DI_1^nok and its midrank
              percentile within publication year, as shipped with the index (defined
              when the paper has references inside PubMed and at least one citer).
            - jif: the journal's impact factor (long-run JCR value); missing when the
              journal has none (the source codes those as 0).
            - journal_hs: published in one of four highly selective journals,
              NEJM, Science, Cell and Nature, identified by their ISO abbreviation.

   Input:
     - ${data}/build/cycles.dta                (code/build/01_cycles.do)
     - ${data}/build/ackn_links_unchecked.dta  (code/build/02_ackn_links.do)
     - ${data}/build/cycle_papers.dta          (code/build/03_cycle_papers.do),
                                               for the coverage check only
     - ${pubmed_root}/authority/authority_pmids_clean.dta
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_jif_2025.dta,
       overall_journals_2025.dta
     - ${pubmed_root}/WoS/oaid_x_pmid_2026.dta                     OpenAlex records
     - ${pubmed_root}/WoS/panel_cites_pubmed2pubmed_openalex_2026.dta  citation panel
     - ${pubmed_root}/disruption_index/di_index_pubmed2025.dta

   Output:
     - ${data}/build/paper_attributes.dta   one row per pmid
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/05_paper_attributes.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. The project's papers
   ----------------------------------------------------------------------------- */
use author_id using "${data}/build/cycles.dta", clear ;
drop if author_id == "" ;
bysort author_id: keep if _n == 1 ;
tempfile invid ;
save `invid' ;
use author_id pmid using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `invid' ;
tab _merge ;
keep if _merge == 3 ;
keep pmid ;
bysort pmid: keep if _n == 1 ;
tempfile set1 ;
save `set1' ;
use pmid using "${data}/build/ackn_links_unchecked.dta", clear ;
bysort pmid: keep if _n == 1 ;
merge 1:1 pmid using `set1' ;
tab _merge ;
keep pmid ;
display as result "=== the project's papers (linked or by an investigator)" ;
count ;
tempfile papers ;
save `papers' ;

/* -----------------------------------------------------------------------------
   2. Citations through the fifth year after publication, ranked within year
   ----------------------------------------------------------------------------- */
/* the stock in year min(pubyear + 5, 2025), from the panel (papers ever cited) */
use pmid pubyear year stk_cites if year == min(pubyear + 5, 2025)
    using "${pubmed_root}/WoS/panel_cites_pubmed2pubmed_openalex_2026.dta", clear ;
gisid pmid ;
rename stk_cites cite5 ;
keep pmid cite5 ;
tempfile panel ;
save `panel' ;

/* the universe: PubMed papers 1975 to 2025 with an OpenAlex record */
use pmid using "${pubmed_root}/WoS/oaid_x_pmid_2026.dta", clear ;
bysort pmid: keep if _n == 1 ;
tempfile oa ;
save `oa' ;
use pmid year using "${pubmed_root}/pubmed/pubmed_universe_2025.dta", clear ;
bysort pmid: keep if _n == 1 ;
rename year pubyear ;
keep if inrange(pubyear, 1975, 2025) ;
merge 1:1 pmid using `oa' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
merge 1:1 pmid using `panel' ;
tab _merge ;
drop if _merge == 2 ;
display as result "=== PubMed 1975-2025 with an OpenAlex record: in the citation panel (3) or never cited (1)" ;
tab _merge ;
replace cite5 = 0 if _merge == 1 ;
drop _merge ;
/* midrank percentile within publication year, ties averaged */
bysort pubyear (cite5): gen long pos = _n ;
gegen double mid = mean(pos), by(pubyear cite5) ;
gegen long n_year = count(pmid), by(pubyear) ;
gen double cite5_pctl = 100 * (mid - 0.5) / n_year ;
gen byte cite5_years = min(5, 2025 - pubyear) ;
keep pmid cite5 cite5_pctl cite5_years ;
merge 1:1 pmid using `papers' ;
tab _merge ;
drop if _merge == 1 ;
drop _merge ;
tempfile cites ;
save `cites' ;

/* -----------------------------------------------------------------------------
   3. Disruption, impact factor, journal
   ----------------------------------------------------------------------------- */
use pmid di1_nok di1_nok_byyear_midrank using "${pubmed_root}/disruption_index/di_index_pubmed2025.dta", clear ;
merge 1:1 pmid using `papers' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
rename di1_nok_byyear_midrank di1_nok_pctl ;
tempfile dis ;
save `dis' ;

use pmid jif has_jif using "${pubmed_root}/pubmed/overall_jif_2025.dta", clear ;
merge 1:1 pmid using `papers' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
replace jif = . if has_jif != 1 ;
keep pmid jif ;
tempfile jif ;
save `jif' ;

use pmid journal_name using "${pubmed_root}/pubmed/overall_journals_2025.dta", clear ;
merge 1:1 pmid using `papers' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
decode journal_name, gen(jname) ;
gen byte journal_hs = inlist(jname, "N Engl J Med", "Science", "Cell", "Nature") ;
display as result "=== the four highly selective journals among the project's papers" ;
tab jname if journal_hs ;
keep pmid journal_hs ;
tempfile jnl ;
save `jnl' ;

/* -----------------------------------------------------------------------------
   4. Assemble and save
   ----------------------------------------------------------------------------- */
use `papers', clear ;
merge 1:1 pmid using `cites' ;
tab _merge ;
drop _merge ;
merge 1:1 pmid using `dis' ;
tab _merge ;
drop _merge ;
merge 1:1 pmid using `jif' ;
tab _merge ;
drop _merge ;
merge 1:1 pmid using `jnl' ;
tab _merge ;
drop _merge ;
replace journal_hs = 0 if journal_hs == . ;

label var cite5        "OpenAlex citations from PubMed papers through pubyear+5 (through 2025 if later)" ;
label var cite5_pctl   "Midrank percentile of cite5 within publication year, 0-100" ;
label var cite5_years  "Years of citations observed (5, fewer for papers after 2020)" ;
label var di1_nok      "Disruption index DI_1^nok" ;
label var di1_nok_pctl "Midrank percentile of di1_nok within publication year, 0-100" ;
label var jif          "Journal impact factor (long-run JCR), missing if none" ;
label var journal_hs   "Published in NEJM, Science, Cell or Nature" ;
label data "Paper attributes for the nih_risk papers" ;
notes: Built `c(current_date)' by code/build/05_paper_attributes.do. ;
order pmid cite5 cite5_pctl cite5_years di1_nok di1_nok_pctl jif journal_hs ;
sort pmid ;
compress ;
save "${data}/build/paper_attributes.dta", replace ;

/* coverage among the acknowledging papers attributed to cycles */
use pmid ackn pubyear using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
bysort pmid: keep if _n == 1 ;
merge 1:1 pmid using "${data}/build/paper_attributes.dta" ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
gen byte has_cite = cite5_pctl < . ;
gen byte has_di   = di1_nok_pctl < . ;
gen byte has_jif  = jif < . ;
gen decade = 10 * floor(pubyear / 10) ;
display as result "=== acknowledging papers in a cycle window: share with each attribute, by decade" ;
tabstat has_cite has_di has_jif journal_hs, by(decade) stat(mean) ;
display as result "=== their citation percentiles: mean and quartiles" ;
summarize cite5_pctl di1_nok_pctl, detail ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/05_paper_attributes.do */
