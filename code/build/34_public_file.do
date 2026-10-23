/* =============================================================================
   code/build/34_public_file.do

   Purpose: The public analysis file, nih_risk_public.dta, zipped in the
            package as data/nih_risk_public.zip: the one file that every
            do-file of code/analysis reads, with which every table and figure
            of the paper and its appendices can be reproduced without the raw
            sources. One row per cycle of the analysis file
            (code/build/23_analysis_file.do), and only the variables that the
            analysis uses (the local keepvars below), taken from
              - the analysis file;
              - the ten side files that appendix exhibits read (code/build/24
                to 33), merged on the cycle; where a side file repeats a
                variable of the analysis file (n_base_mesh), the analysis
                file's value is kept;
              - two blocks computed here from files that are not distributed:
                the median and the half-spreads of the citation percentiles of
                the cycle's acknowledging papers on which the investigator is
                first, last or single author (Appendix Table B1: n_own, o_med,
                o_up, o_lo), and the investigator's NIH funding over the whole
                grant file (Table 1a: car_r01, car_all, 0 for an investigator
                absent from it).
            The list of variables is the analysis code's: its literal names,
            the names it builds from macros, and its wildcards. A change to
            the analysis that uses another variable must add it here; a
            missing variable stops the analysis with r(111).
            The identifiers are generic. Investigators, grants, study sections
            and the institute x study section groups are numbered in a random
            order drawn with a fixed seed, so that clustering and fixed effects
            are unchanged while no row can be looked up by a person's or a
            grant's identifier. Dropped: the investigator's identifier in the
            grant file (setnb), the grant number (project_number), the
            application identifier (app_id), the Author-ity identifier
            (author_id, of which only a flag for its presence is kept,
            has_author_id), and the institution codes (new_ipfcode,
            ipf_eval).

   Input:
     - ${data}/output/nih_risk_analysis.dta   (code/build/23_analysis_file.do)
     - ${data}/build/risk_windows.dta, risk_lagged.dta, risk_fading.dta,
       risk_tail_projects.dta, risk_other.dta, cycle_collabteam.dta,
       risk_disruption_versions.dta, risk_standout_extras.dta,
       risk_pivoting_extras.dta, cycle_windows.dta   (code/build/24 to 33)
     - ${data}/build/cycle_papers.dta          (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta      (code/build/05_paper_attributes.do)
     - ${cgaf}/data/CGAF_all_2025_it.dta       NIH funding by investigator and
                                               year

   Output:
     - ${public}/nih_risk_public.dta, one row per cycle of the analysis file
     - ${public}/nih_risk_public.zip, the same, zipped: the file the package
       distributes (${public} is the package's data folder, config.do)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/34_public_file.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. The investigator's NIH funding over the whole grant file (Table 1a)
   ----------------------------------------------------------------------------- */
use setnb amount_it amount_R01_it using "${cgaf}/data/CGAF_all_2025_it.dta", clear ;
gcollapse (sum) car_r01 = amount_R01_it car_all = amount_it, by(setnb) ;
tempfile car ;
save `car' ;

/* -----------------------------------------------------------------------------
   2. The citation percentiles of the acknowledging papers on which the
      investigator is first, last or single author (Appendix Table B1)
   ----------------------------------------------------------------------------- */
use setnb project_number cycle pmid ackn author_seq nb_authrs using "${data}/build/cycle_papers.dta" if ackn == 1, clear ;
keep if author_seq == 1 | author_seq == nb_authrs ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5_pctl) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
keep if cite5_pctl < . ;
gcollapse (count) n_own = cite5_pctl (max) omax = cite5_pctl (min) omin = cite5_pctl
          (p50) omed = cite5_pctl, by(setnb project_number cycle) ;
gen double o_med = omed / 10 ;
gen double o_up  = (omax - omed) / 10 ;
gen double o_lo  = (omed - omin) / 10 ;
tempfile own ;
save `own' ;

/* -----------------------------------------------------------------------------
   3. The analysis file, the side files, and the two blocks
   ----------------------------------------------------------------------------- */
use "${data}/output/nih_risk_analysis.dta", clear ;
local n_cycles = _N ;
local s1  "risk_windows" ;
local s2  "risk_lagged" ;
local s3  "risk_fading" ;
local s4  "risk_tail_projects" ;
local s5  "risk_other" ;
local s6  "cycle_collabteam" ;
local s7  "risk_disruption_versions" ;
local s8  "risk_standout_extras" ;
local s9  "risk_pivoting_extras" ;
local s10 "cycle_windows" ;
forvalues i = 1/10 {;
    display as result "=== `s`i''" ;
    merge 1:1 setnb project_number cycle using "${data}/build/`s`i''.dta" ;
    tab _merge ;
    /* Appendix Table G1 needs to know which cycles have the windows */
    if `i' == 1 gen byte win_ok = _merge == 3 ;
    drop if _merge == 2 ;
    drop _merge ;
} ;
merge 1:1 setnb project_number cycle using `own' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge m:1 setnb using `car' ;
tab _merge ;
drop if _merge == 2 ;
replace car_r01 = 0 if _merge == 1 ;
replace car_all = 0 if _merge == 1 ;
drop _merge ;
assert _N == `n_cycles' ;
gisid setnb project_number cycle ;

/* -----------------------------------------------------------------------------
   4. Generic identifiers: each key numbered in a random order (fixed seed),
      drawn on its distinct values sorted by the original key, so that the
      numbering is the same at every run on the same data
   ----------------------------------------------------------------------------- */
set seed 20261022 ;
tempfile base ;
save `base' ;

/* investigators */
keep setnb ;
gduplicates drop ;
sort setnb ;
gen double u = runiform() ;
sort u ;
gen long inv_g = _n ;
keep setnb inv_g ;
gisid setnb ;
gisid inv_g ;
tempfile k_inv ;
save `k_inv' ;

/* grants */
use project_number using `base', clear ;
gduplicates drop ;
sort project_number ;
gen double u = runiform() ;
sort u ;
gen long grant_g = _n ;
keep project_number grant_g ;
gisid project_number ;
gisid grant_g ;
tempfile k_grant ;
save `k_grant' ;

/* study sections (an empty code stays empty) */
use irg_code using `base' if irg_code != "", clear ;
gduplicates drop ;
sort irg_code ;
gen double u = runiform() ;
sort u ;
gen str4 irg_g = "S" + string(_n, "%03.0f") ;
keep irg_code irg_g ;
gisid irg_code ;
gisid irg_g ;
tempfile k_irg ;
save `k_irg' ;

/* institute x study section groups (a missing group stays missing) */
use ic_irg using `base' if !missing(ic_irg), clear ;
gduplicates drop ;
sort ic_irg ;
gen double u = runiform() ;
sort u ;
gen long icirg_g = _n ;
keep ic_irg icirg_g ;
gisid ic_irg ;
gisid icirg_g ;
tempfile k_icirg ;
save `k_icirg' ;

use `base', clear ;
merge m:1 setnb using `k_inv' ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
merge m:1 project_number using `k_grant' ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
merge m:1 irg_code using `k_irg' ;
tab _merge ;
assert _merge == 3 if irg_code != "" ;
assert _merge == 1 if irg_code == "" ;
drop if _merge == 2 ;
drop _merge ;
replace irg_g = "" if irg_code == "" ;
merge m:1 ic_irg using `k_icirg' ;
tab _merge ;
assert _merge == 3 if !missing(ic_irg) ;
assert _merge == 1 if  missing(ic_irg) ;
drop if _merge == 2 ;
drop _merge ;

gen byte has_author_id = author_id != "" ;
drop setnb project_number app_id author_id new_ipfcode ipf_eval inv_id grant_id irg_code ic_irg ;
rename inv_g   inv_id ;
rename grant_g grant_id ;
rename irg_g   irg_code ;
rename icirg_g ic_irg ;

/* -----------------------------------------------------------------------------
   5. The variables the analysis uses, and no other: the literal names of
      code/analysis and code/programs, the names they build from macros
      (the outcomes _aft and _dur of Tables 3 and L1, the lagged measures of
      Tables A2 and G2, the projects of Table B2, the windows of Table G1,
      the other work of Tables G4 and G5), and their wildcards (agepi_*,
      tl_lo_btw_*, tl_lo_wth_*)
   ----------------------------------------------------------------------------- */
local keepvars "
    inv_id grant_id cycle renewed cycle_yr span_start eval_year
    cycle_length ic female deg_year multi_pi spread_minmax_ackn
    di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair has_all4 n_ackn
    n_noackn meanjif_ackn meanjif_noackn journal_hs_ackn journal_hs_noackn
    log_meanjif_all authority_partial bin_ackn bin_noackn
    log_amount_allgrants log_pi_careercites_evalyr log_pi_priorgrants_all
    no_pi_priorgrants agepi_under5 agepi_5t10 agepi_10t15 agepi_15t20
    agepi_20t25 agepi_25t30 agepi_30t35 agepi_35t40 agepi_40plus deg_cat
    new_eval_year new_cycle_length cycle_nb n_tails n_disr
    frac_setnb_pair_near frac_setnb_pair_far n_base_mesh nb_abs
    agepair_cyclefrac semdist_mean frac_new_phrase_comb
    frac_new_phrase_oth pat_cites pharma_cites kpss_value compot_mean
    cites5_ackn cites5_noackn new_inv elite elite_ever name_freq_authority
    frac_pubs_nih_pre pi_cites_precycle pi_pubs_precycle frac_noackn_nih
    frac_app_single_new breadth_pre n_pre multi_r01_start n_tails_e
    tails_e n_disr_e disr_e pivot_e n_piv_e so_e n_so_e n_tails_f tails_f
    n_disr_f disr_f pivot_f n_piv_f so_f n_so_f n_tails_l tails_l n_disr_l
    disr_l pivot_l n_piv_l so_l n_so_l n_ackn_e n_noackn_e hs_ackn_e
    hs_noackn_e n_ackn_l n_noackn_l hs_ackn_l hs_noackn_l n_ackn_m
    n_noackn_m hs_ackn_m hs_noackn_m nojif_e ljif_e bin_ackn_e
    bin_noackn_e nojif_l ljif_l bin_ackn_l bin_noackn_l nojif_m ljif_m
    bin_ackn_m bin_noackn_m win_ok n_lag_tails n_lag_disr lag_tails
    lag_disr lag_pivot n_lag_pivot lag_so n_lag_so vib_pre tl_med tl_up
    tl_lo nproj_m3 single_m3 nproj_m5 single_m5 nproj_m7 single_m7
    nproj_fa single_fa tl_lo_btw_m3 tl_lo_wth_m3 multi_m3 tl_lo_btw_m5
    tl_lo_wth_m5 multi_m5 tl_lo_btw_m7 tl_lo_wth_m7 multi_m7 tl_lo_btw_fa
    tl_lo_wth_fa multi_fa ow_tails ow_disr ow_pivot og_tails og_disr
    og_pivot n_ow_tails n_ow_disr n_ow_mesh n_og_tails n_og_disr n_og_mesh
    team_dist n_fout_mesh dmax_base dmax_di1 dmax_d5n dmax_di5 dmax_w5
    dmax_w10 dmax_nslf dmax_orgnl dmax_ge5 dmax_ge10 dmax_ge20 dmax_cit
    dmax_ref dmax_fl dn_base dmean dshq dshd drawmax c_p50 c_atmax so_own
    so_est so_new so_near so_far so_plac so_plac1 so_noct so_new1 so_new10
    piv_sh piv_un has_base ct_share ct_share_sh plac_small frac_setnb_mesh
    far_both_new cos_dissim_setnb piv_distance piv_distance_noct
    next_revival n_pubs_dur n_pubs_aft cites5_dur cites5_aft pat_cites_dur
    pat_cites_aft pharma_cites_dur pharma_cites_aft kpss_value_dur
    kpss_value_aft compot_mean_dur compot_mean_aft n_grpat_dur n_grpat_aft
    n_own o_med o_up o_lo car_r01 car_all irg_code ic_irg has_author_id" ;
keep `keepvars' ;

/* -----------------------------------------------------------------------------
   6. Labels, order, save
   ----------------------------------------------------------------------------- */
label var inv_id        "Investigator (generic identifier, random order), for clustering" ;
label var grant_id      "Grant (generic identifier, random order), for clustering" ;
label var irg_code      "Study section (generic code, random order)" ;
label var ic_irg        "Institute x study section (generic code, random order)" ;
label var has_author_id "The investigator has an Author-ity identifier" ;
label var win_ok        "The cycle has the windows of code/build/24_risk_windows.do" ;
label var car_r01       "Investigator's NIH R01-equivalent funding, all years of the grant file" ;
label var car_all       "Investigator's NIH funding, all years of the grant file" ;
label var n_own         "First- or last-author acknowledging papers with a citation percentile" ;
label var o_med         "Median, first- or last-author papers (10 percentile points)" ;
label var o_up          "Max - median, first- or last-author papers (10 percentile points)" ;
label var o_lo          "Median - min, first- or last-author papers (10 percentile points)" ;

notes drop _all ;
label data "nih_risk public analysis file: one row per analysis-sample cycle, generic identifiers" ;
notes: Built `c(current_date)' by code/build/34_public_file.do. ;
order inv_id grant_id cycle ;
gisid inv_id grant_id cycle ;
sort inv_id grant_id cycle ;
compress ;
save "${public}/nih_risk_public.dta", replace ;
local here "`c(pwd)'" ;
cd "${public}" ;
zipfile nih_risk_public.dta, saving(nih_risk_public.zip, replace) ;
cd "`here'" ;

/* -----------------------------------------------------------------------------
   7. First look: the size of the file, and no identifier left
   ----------------------------------------------------------------------------- */
describe, short ;
distinct inv_id grant_id irg_code ic_irg ic ;
foreach v in setnb project_number app_id author_id new_ipfcode ipf_eval {;
    capture confirm variable `v', exact ;
    assert _rc != 0 ;
} ;
display as result "=== string variables of the public file" ;
ds, has(type string) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
