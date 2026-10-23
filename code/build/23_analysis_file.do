/* =============================================================================
   code/build/23_analysis_file.do

   Purpose: The analysis-ready file: one row per analysis-sample cycle (in_sample,
            outside special emphasis panels), with the renewal outcome, the cycle's
            attributes, the output controls, the investigator and institution
            controls, the fixed-effect groups, the four risk measures, novelty,
            the patent and citation outcomes, and the investigator traits. The
            measures are left unstandardized: each analysis standardizes them on its
            own estimation sample.

   Input:
     - ${data}/build/cycles.dta                (code/build/01_cycles.do)
     - ${data}/build/cycle_output.dta          (code/build/06_cycle_output.do)
     - ${data}/build/cycle_controls.dta        (code/build/04_cycle_controls.do)
     - ${data}/build/risk_tails.dta            (code/build/07_tails.do)
     - ${data}/build/risk_disruption.dta       (code/build/08_disruption.do)
     - ${data}/build/risk_pivoting.dta         (code/build/09_pivoting.do)
     - ${data}/build/risk_standout.dta         (code/build/12_standing_out.do)
     - ${data}/build/novelty_mesh.dta          (code/build/13_novelty_mesh.do, 13_novelty_mesh.py)
     - ${data}/build/novelty_text.dta          (code/build/14_novelty_text.do)
     - ${data}/build/cycle_patents.dta         (code/build/16_patents.do)
     - ${data}/build/cycle_commpot.dta         (code/build/18_commercial_potential.do)
     - ${data}/build/cycle_record.dta          (code/build/20_record_before_cycle.do)
     - ${data}/build/proposal_pivot.dta        (code/build/15_proposal_pivot.do)
     - ${data}/build/cycle_investigator.dta    (code/build/19_investigator_flags.do)
     - ${data}/build/cycle_cites.dta           (code/build/17_cycle_cites.do)
     - ${data}/build/cycle_breadth.dta         (code/build/22_breadth.do)
     - ${data}/build/cycle_concurrent.dta      (code/build/21_concurrent_grants.do)

   Output:
     - ${data}/output/nih_risk_analysis.dta    one row per setnb x project_number x cycle
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/23_analysis_file.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. The analysis sample and the cycle's attributes
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr span_start eval_year cycle_length gap_next
    renewed renewed_strict renewed_nolimit revival start_act start_atype has_t7
    first_is_renewal app_id ic irg_code female deg_year author_id new_ipfcode ipf_eval
    multi_pi in_sample sep using "${data}/build/cycles.dta", clear ;
keep if in_sample & sep != 1 ;
drop in_sample sep ;
display as result "=== analysis-sample cycles" ;
count ;
local n_sample = r(N) ;

/* -----------------------------------------------------------------------------
   2. Output controls, investigator and institution controls, risk measures
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/cycle_output.dta",
    keepusing(n_ackn n_noackn bin_ackn bin_noackn meanjif_all meanjif_ackn meanjif_noackn
              log_meanjif_all journal_hs_ackn journal_hs_noackn authority_partial) ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;

merge 1:1 setnb project_number cycle using "${data}/build/cycle_controls.dta" ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;

/* each measure exists for a subset of cycles: _merge == 1 means not defined */
merge 1:1 setnb project_number cycle using "${data}/build/risk_tails.dta" ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_disruption.dta" ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_pivoting.dta" ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_standout.dta" ;
drop if _merge == 2 ;
drop _merge ;

/* novelty (MeSH-pair age, textual), patent citations, commercial potential,
   citations, investigator attributes, the investigator's record before the
   cycle, the pivoting of the proposal; missing where not defined, except the
   patent counts, zero for a cycle with acknowledging papers that no patent
   cites */
merge 1:1 setnb project_number cycle using "${data}/build/novelty_mesh.dta",
    keepusing(agepair_cyclefrac agepair_cyclemean agesingle_cyclemean n_pair_inst) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/novelty_text.dta",
    keepusing(avg_new_phrase frac_new_phrase avg_new_word frac_new_word avg_new_word_comb
              frac_new_word_comb frac_new_phrase_comb semdist_mean n_scored n_semdist
              frac_new_phrase_oth) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_patents.dta",
    keepusing(pat_cites pharma_cites kpss_value pat_any pharma_any kpss_any) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_commpot.dta",
    keepusing(compot_mean n_compot) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_cites.dta",
    keepusing(cites5_ackn cites5_noackn next_n_ackn next_cites5_ackn) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_investigator.dta",
    keepusing(first_r01eq new_inv esi elite elite_ever name_freq_authority frac_pubs_nih n_career_pubs) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_record.dta",
    keepusing(pi_pubs_precycle pi_cites_precycle frac_noackn_nih frac_pubs_nih_pre n_pubs_nih_pre) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/proposal_pivot.dta",
    keepusing(frac_app_pair_new frac_app_single_new n_app_desc) ;
drop if _merge == 2 ;
drop _merge ;
/* investigator traits of Figure 5 and Appendix Table I1: breadth
   (breadth_pre defined when n_pre >= 5) and the investigator's other
   R01-equivalent grants, counted in the cycle's first year and in its
   evaluation year */
merge 1:1 setnb project_number cycle using "${data}/build/cycle_breadth.dta",
    keepusing(breadth_pre n_pre) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_concurrent.dta",
    keepusing(n_other_r01_start multi_r01_start n_other_r01 multi_r01) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
assert _N == `n_sample' ;

/* -----------------------------------------------------------------------------
   3. Keys for clustering, flags
   ----------------------------------------------------------------------------- */
gegen long inv_id   = group(setnb) ;
gegen long grant_id = group(project_number) ;
gen byte r29_r23   = inlist(start_act, "R29", "R23") ;
gen byte has_tails = spread_minmax_ackn  < . ;
gen byte has_disr  = di1nok_ackn_maxpctl < . ;
gen byte has_pivot = frac_setnb_pair     < . ;
gen byte has_so    = frac_icirg_pair     < . ;
gen byte has_all4  = has_tails & has_disr & has_pivot & has_so ;
gen byte has_nov   = agepair_cyclefrac < . ;

label var inv_id    "Investigator (numeric key of setnb), for clustering" ;
label var grant_id  "Grant (numeric key of project_number), for clustering" ;
label var r29_r23   "Cycle started by an R29 or R23 award (new-investigator mechanisms)" ;
label var has_tails "Tails defined" ;
label var has_disr  "Disruption defined" ;
label var has_pivot "Pivoting defined" ;
label var has_so    "Standing out defined" ;
label var has_all4  "All four risk measures defined" ;
label var has_nov   "Novelty (MeSH-pair age) defined" ;

label data "nih_risk analysis file: one row per analysis-sample cycle" ;
notes: Built `c(current_date)' by code/build/23_analysis_file.do. ;
order setnb project_number cycle inv_id grant_id renewed renewed_strict renewed_nolimit
      cycle_yr span_start eval_year cycle_length gap_next revival start_act start_atype
      r29_r23 has_t7 first_is_renewal app_id ic irg_code female deg_year author_id
      new_ipfcode ipf_eval multi_pi
      spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair
      has_tails has_disr has_pivot has_so has_all4 ;
gisid setnb project_number cycle ;
sort setnb project_number cycle ;
compress ;
save "${data}/output/nih_risk_analysis.dta", replace ;

/* -----------------------------------------------------------------------------
   4. First look
   ----------------------------------------------------------------------------- */
display as result "=== cycles with each measure, and with all four" ;
tabstat has_tails has_disr has_pivot has_so has_all4, stat(sum mean) ;
display as result "=== the measures by renewal (raw means)" ;
tabstat spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair, by(renewed) stat(mean sd n) ;
display as result "=== correlations among the measures, cycles with all four" ;
correlate spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair if has_all4 ;
display as result "=== renewal rate, investigators, grants" ;
summarize renewed ;
distinct inv_id grant_id ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/23_analysis_file.do */
