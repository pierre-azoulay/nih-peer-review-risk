/* =============================================================================
   code/build/01_cycles.do

   Purpose: Build the cycle file from the raw NIH grant-year records: one row per
            grant cycle whose starting award lists a single principal
            investigator, carried as setnb, with the evaluation year, the
            renewal outcome and the sample flags. The grants are the
            R01-equivalent research grants (activities R01, R37, R29 and R23)
            first funded from 1980 to 2015. Cycles are built at the grant level
            and numbered within the grant, whoever holds them. A cycle starts
            with a competing award (application type 1, 2 or 9); a change of
            grantee institution (type 7) continues the cycle; a cycle ends at
            its last payment year; renewal = the grant's next competing award
            within three fiscal years of the last payment (local lapse_max),
            whoever applies.
            A cycle enters if the competing award that starts it lists one PI
            and that PI holds every year of the cycle: co-PIs added during the
            cycle do not exclude it, a PI replaced during the cycle does. The
            cycle carries that PI and the PI's own characteristics (career,
            record, gender, degree). Three filters are tested on each cycle's
            own records, never on later ones: three distinct budget years; no
            record at an institution without a code, or at a firm, a national
            laboratory, a society or a foreign university; an application ID
            on the award that starts the cycle (it links the cycle to its study
            section). The institution is kept for the cycle's first year
            (new_ipfcode) and for its last year of payments (ipf_eval), which
            differ after a transfer. AM grants are linked to their DK or AR
            successors across the 1986 split of NIADDK. The outcome is observed
            only for cycles evaluated by 2022, renewed or not, so that the
            sample does not depend on the outcome.

   Input:
     - ${input}/cgaf_nih_risk.dta            grant-year records (FY1938 to 2025),
                                             with the investigator's gender
     - ${cgaf}/ccrd_app_id2project_num.dta   application-ID crosswalk
     - ${cgaf}/cgaf_study_sections_000.dta   study section by application
     - ${cgaf2008}/ipf_interm.dta            institution codes
     - ${pubmed_root}/authority/matchCGAF/matches2022/cnsldt_goodmatches.dta
                                             investigator to Author-ity ID

   Output:
     - ${data}/build/cycles.dta   one row per grant cycle, keyed setnb x
       project_number x cycle (cycle = the grant's cycle number)
     - ${data}/build/am_successor.dta   one row per AM grant linked across the
       1986 split: pn_am, pn_succ, ic_succ (read by code/build/02_ackn_links.do,
       code/build/21_concurrent_grants.do and code/build/33_outcome_windows.do)
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/01_cycles.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

local lapse_max 3 ;     /* renewed if the next competing award starts <= 3 FY after the last payment */
local first_lo  1980 ;  /* grants first funded 1980 ... */
local first_hi  2015 ;  /* ... to 2015 */
local data_end  2025 ;  /* last fiscal year in the grant records */
local acts `""R01", "R37", "R29", "R23""' ;

/* -----------------------------------------------------------------------------
   0. Application-ID crosswalks from the CCRD file, for the R01-equivalent
      activities (R01, R37, R29, R23): full project number and year to the
      application ID, with and without the grant suffix, kept only when the
      pair maps to a single application. They fill missing application IDs
      in section 1.
      egen nvals() is used rather than gegen nunique(), whose handling of
      missing values may differ.
   ----------------------------------------------------------------------------- */
use "${cgaf}/ccrd_app_id2project_num.dta", clear ;
drop if strpos(full_project_num, "HHS") > 0 ;
split full_project_num, parse("-") ;
capture drop if full_project_num3 != "" ;
keep if strpos(full_project_num, "R01") | strpos(full_project_num, "R37") |
        strpos(full_project_num, "R29") | strpos(full_project_num, "R23") ;
drop if strlen(full_project_num1) != 12 ;
tempfile tm1 tm2 ;
preserve ;
    keep full_project_num year app_id ;
    rename app_id app2_id ;
    bysort full_project_num year: egen nbapp = nvals(app2_id) ;
    keep if nbapp == 1 ;
    bysort full_project_num year: keep if _n == 1 ;
    keep full_project_num year app2_id ;
    save `tm1' ;
restore ;
gen suppyr_ = substr(full_project_num2, 1, 2) ;
replace full_project_num = full_project_num1 + "-" + suppyr_ ;
keep full_project_num year app_id ;
rename app_id app3_id ;
bysort full_project_num year: egen nbapp = nvals(app3_id) ;
keep if nbapp == 1 ;
bysort full_project_num year: keep if _n == 1 ;
keep full_project_num year app3_id ;
save `tm2' ;

/* -----------------------------------------------------------------------------
   1. Grant-year records of the R01-equivalent research grants, every PI kept
   ----------------------------------------------------------------------------- */
use setnb year fullname activity ic grantno apptype suppyr grnsufx app_id
    ipfcode totdol multi_pi pi_cntct pi_cntct_pbm deg_cgaf MDyear PhDyear
    hPhDyear using "${input}/cgaf_nih_risk.dta", clear ;
keep if inlist(activity, `acts') ;
gen str8 project_number = ic + grantno ;
destring apptype, gen(atype) force ;
drop if atype == . ;
display as result "records, R01/R37/R29/R23 with a valid application type: " _N ;

/* the 1986 split of NIADDK: in FY1986 institute AM became DK (NIDDK) and AR (NIAMS),
   and its grants carried on under the new code, almost always with the same serial.
   Since a grant is ic + grantno, every AM grant would end in 1985. Each AM grant takes
   the project number of its successor: the DK or AR grant with the same serial and the
   same investigator whose first record is in FY1986 to FY1988. The records keep their
   own ic (the application IDs below are filled with it); the cycle's ic is set in
   section 2. The crosswalk is saved for the stages that read the grant records or the
   link tables by ic + grantno. */
gegen int f_first = min(year), by(project_number) ;
preserve ;
    keep if inlist(ic, "DK", "AR") & inrange(f_first, 1986, 1988) ;
    keep setnb grantno project_number ic ;
    duplicates drop ;
    rename (project_number ic) (pn_succ ic_succ) ;
    tempfile succ ;
    save `succ' ;
restore ;
drop f_first ;
preserve ;
    keep if ic == "AM" ;
    keep setnb grantno project_number ;
    duplicates drop ;
    rename project_number pn_am ;
    joinby setnb grantno using `succ' ;
    keep pn_am pn_succ ic_succ ;
    duplicates drop ;
    gisid pn_am ;  /* one successor per AM grant */
    display as result "=== AM grants linked to a DK or AR successor" ;
    tab ic_succ ;
    label var pn_am   "AM grant (ic + grantno)" ;
    label var pn_succ "Its DK or AR successor, same serial and investigator, first record FY1986-88" ;
    label var ic_succ "Institute of the successor" ;
    sort pn_am ;
    compress ;
    save "${data}/build/am_successor.dta", replace ;
restore ;
rename project_number pn_am ;
merge m:1 pn_am using "${data}/build/am_successor.dta" ;
tab _merge ;
assert _merge != 2 ;
replace pn_am = pn_succ if _merge == 3 ;
drop _merge pn_succ ;
rename pn_am project_number ;
/* every record of a linked grant, AM and successor alike, carries the successor's institute */
bysort project_number (ic_succ): replace ic_succ = ic_succ[_N] ;
display as result "records of grants linked across the split: " ;
count if ic_succ != "" ;

/* grants first funded 1980 to 2015. Who holds the grant is tested on each cycle in
   section 3, not on the grant as a whole */
gegen int g_first = min(year), by(project_number) ;
gegen int g_last  = max(year), by(project_number) ;
keep if inrange(g_first, `first_lo', `first_hi') ;
display as result "records of grants first funded `first_lo' to `first_hi': " _N ;

/* institutions: records without an institution code, or at a firm, a lab, a society
   or a foreign university (the codes below, in the authors' classification of
   institution types, variable aamc_id of the institution lookup). Flagged record by
   record and tested on each cycle's own records in section 3 */
merge m:1 ipfcode using "${cgaf2008}/ipf_interm.dta", keepusing(new_ipfcode aamc_id) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
gen byte bad_inst = new_ipfcode == . | inlist(aamc_id, 987, 990, 992, 994, 996, 997, 999) ;

/* fill missing application IDs from the CCRD crosswalks of section 0: first on the full
   project number with its suffix, then without it */
gen full_project_num = string(atype) + activity + ic + grantno + "-" + suppyr + grnsufx ;
merge m:1 full_project_num year using `tm1' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
replace app_id = app2_id if app_id == . & app2_id < . ;
replace full_project_num = string(atype) + activity + ic + grantno + "-" + suppyr ;
merge m:1 full_project_num year using `tm2' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
replace app_id = app3_id if app_id == . & app3_id < . ;
drop app2_id app3_id full_project_num ;

/* award types */
gen byte comp = inlist(atype, 1, 2, 9) ;     /* competing award: starts a cycle */
gen byte cont = inlist(atype, 4, 5, 7, 8) ;  /* continuation-type payment       */
gen byte t7   = atype == 7 ;

/* exact duplicates on the budget identifiers: keep one, by an explicit rule (lowest
   application ID, then the largest amount) rather than by whatever order the data are in */
gsort setnb project_number year suppyr apptype grnsufx app_id -totdol ;
duplicates drop setnb project_number year suppyr apptype grnsufx, force ;
display as result "=== records; records of multi-PI applications (multi_pi)" ;
count ;
count if multi_pi == 1 ;
tempfile recs ;
save `recs' ;

/* -----------------------------------------------------------------------------
   2. Grant-year panel and grant cycles
   ----------------------------------------------------------------------------- */
/* the grant's first record starts its first cycle even when it is not a competing award */
gen byte firstyr = year == g_first ;
gen long app_comp  = app_id if comp ;
gen long app_first = app_id if firstyr ;
gen byte pbm = pi_cntct_pbm == 1 & (comp | firstyr) ;
gen int atype_comp = atype if comp ;
gen str3 act_comp  = activity if comp ;
gen str3 act_first = activity if firstyr ;
/* collapse (firstnm) keeps the first non-missing value within a year, so the order of a
   year's records decides it (a transfer year has one record at each institution; a
   multi-PI year one record per PI). Make the order explicit: the competing award's
   record first, then by application type, support year, suffix, application ID and
   investigator. */
gen byte nocomp = !comp ;
sort project_number year nocomp atype suppyr grnsufx app_id setnb ;
drop nocomp ;
/* collapse, not gcollapse: string variables */
collapse (max) comp cont t7 pbm (firstnm) app_comp app_first atype_comp act_comp act_first
         (min) atype_min = atype
         (firstnm) ic ic_succ g_first g_last new_ipfcode aamc_id, by(project_number year) ;
/* a first year without a competing award takes its application and activity from any record that year */
replace app_comp = app_first if app_comp == . ;
replace act_comp = act_first if act_comp == "" ;
drop app_first act_first ;

bysort project_number (year): gen byte start = comp | _n == 1 ;
bysort project_number (year): gen int cycle = sum(start) ;
/* a start year that also carries a continuation payment is shared with the ending cycle */
bysort project_number (year): gen byte shared = start & cont & _n > 1 ;
gen byte first_noncomp = start & !comp ;  /* first record not a competing award */

/* cycle-level summaries */
bysort project_number cycle (year): gen int cycle_yr = year[1] ;
gegen int last_in = max(year), by(project_number cycle) ;
gegen byte has_t7 = max(t7), by(project_number cycle) ;
bysort project_number cycle (year): gen long app_id = app_comp[1] ;
bysort project_number cycle (year): gen int start_atype = atype_comp[1] ;
bysort project_number cycle (year): gen str3 start_act = act_comp[1] ;
bysort project_number cycle (year): gen byte start_shared = shared[1] ;
bysort project_number cycle (year): gen byte start_noncomp = first_noncomp[1] ;
bysort project_number cycle (year): gen byte start_atype_min = atype_min[1] ;
/* a competing or first-year record on which the contact investigator identified by
   name differs from the one identified by ID (pi_cntct_pbm) excludes the grant's
   cycles; no R01-equivalent record of these data carries the flag, so it removes none */
gegen byte any_pbm = max(pbm), by(project_number) ;
/* the institution in the cycle's last year of payments: after a transfer (type 7) it is the
   grant's new institution, the one that submits the renewal */
bysort project_number cycle (year): gen long ipf_eval = new_ipfcode[_N] ;

preserve ;
    keep project_number year cycle start shared ;
    tempfile panel ;
    save `panel' ;
restore ;

keep if start ;
keep project_number cycle cycle_yr last_in has_t7 app_id start_atype start_act
     start_shared start_noncomp start_atype_min any_pbm ic ic_succ g_first g_last
     new_ipfcode ipf_eval aamc_id ;

/* last payment year: the shared start year of the next cycle belongs to this one */
bysort project_number (cycle): gen int next_yr = cycle_yr[_n+1] ;
bysort project_number (cycle): gen byte next_shared = start_shared[_n+1] ;
bysort project_number (cycle): gen int next_atype = start_atype[_n+1] ;
gen int eval_year = last_in ;
replace eval_year = next_yr if next_shared == 1 ;
gen int span_start = cycle_yr + (start_shared == 1) ;  /* first year whose papers the cycle can receive */
gen int cycle_length = eval_year - cycle_yr + 1 ;
gen int gap_next = next_yr - eval_year ;               /* 0 shared, 1 no unpaid year, 2 one unpaid year ... */

/* the cycle's institute is the one in force in its evaluation year: AM through FY1985,
   the successor's from FY1986. Standing out's comparison cell is institute x study
   section x evaluation year, and the applications carry their own year's institute. */
gen byte am_link = ic_succ != "" ;
replace ic = cond(eval_year >= 1986, ic_succ, "AM") if am_link ;
drop ic_succ ;

/* renewal: the grant's next competing award, whoever applies */
gen byte renewed         = next_yr < . & gap_next <= `lapse_max' ;
gen byte renewed_strict  = next_yr < . & gap_next <= 1 ;
gen byte renewed_nolimit = next_yr < . ;
bysort project_number (cycle): gen byte revival = gap_next[_n-1] > `lapse_max' & gap_next[_n-1] < . ;
/* outcome observed only if the full renewal window lies inside the data. The test is on
   the evaluation year alone, renewed or not, so that the sample does not depend on the
   outcome */
gen byte censored = eval_year + `lapse_max' > `data_end' ;
/* a property of the grant, carried by each of its cycles: its cycle numbers are unknown
   when its first record is a competing renewal */
gen byte fir1 = cycle == 1 & inlist(start_atype, 2, 9) ;
gegen byte first_is_renewal = max(fir1), by(project_number) ;
drop fir1 ;
tempfile cyc ;
save `cyc' ;

/* -----------------------------------------------------------------------------
   3. The PI of each cycle, and the filters on the cycle's own records
   ----------------------------------------------------------------------------- */
use setnb project_number year suppyr comp atype grnsufx app_id totdol bad_inst
    fullname multi_pi pi_cntct deg_cgaf MDyear PhDyear hPhDyear using `recs', clear ;
merge m:1 project_number year using `panel' ;
assert _merge == 3 ;
drop _merge ;
/* pcycle: the cycle of the year panel, to which a start year belongs whole */
rename cycle pcycle ;
gen int cycle = pcycle ;
/* a record of a shared start year that is not the competing award belongs to the ending
   cycle, whose last payment it is */
replace cycle = cycle - 1 if start & shared & !comp ;
merge m:1 project_number cycle using `cyc', keepusing(cycle_yr start_noncomp) ;
assert _merge == 3 ;
drop _merge ;
/* the PIs of the cycle's start: those of its competing award, or of the grant's first
   records when its first record is not a competing award */
gen byte st = year == cycle_yr & (comp | start_noncomp) ;
preserve ;
    keep if st ;
    egen byte t = tag(project_number cycle setnb) ;
    gegen int n_start = total(t), by(project_number cycle) ;
    keep if t ;
    bysort project_number cycle (setnb): keep if _n == 1 ;
    gen P = setnb if n_start == 1 ;
    keep project_number cycle n_start P ;
    tempfile startpi ;
    save `startpi' ;
restore ;
merge m:1 project_number cycle using `startpi' ;
assert _merge == 3 ;
drop _merge ;
gen byte isP = setnb == P ;

/* the PI's characteristics, from the PI's own records of the cycle's first year, the
   competing award's record first (the order of section 2) */
preserve ;
    keep if st & isP ;
    gen byte nocomp = !comp ;
    sort project_number cycle year nocomp atype suppyr grnsufx app_id ;
    collapse (firstnm) fullname multi_pi pi_cntct deg_cgaf MDyear PhDyear hPhDyear,
             by(project_number cycle) ;
    tempfile pattr ;
    save `pattr' ;
restore ;

/* the PI's payments in the years of the cycle, the start year counted whole with the
   cycle it starts, as in the year panel */
preserve ;
    keep project_number pcycle setnb totdol ;
    rename pcycle cycle ;
    merge m:1 project_number cycle using `startpi', keepusing(P) ;
    assert _merge == 3 ;
    drop _merge ;
    keep if setnb == P ;
    gcollapse (sum) dollars = totdol, by(project_number cycle) ;
    tempfile dol ;
    save `dol' ;
restore ;

/* every year of the cycle has a record of its PI; its own budget years; its institutions */
egen byte t_y  = tag(project_number cycle year) ;
egen byte t_py = tag(project_number cycle year isP) ;
gen byte t_pyP = t_py * isP ;
egen byte t_s  = tag(project_number cycle suppyr) ;
replace t_s = 0 if suppyr == "" ;
gegen int n_years = total(t_y), by(project_number cycle) ;
gegen int p_years = total(t_pyP), by(project_number cycle) ;
gegen int nsupp   = total(t_s), by(project_number cycle) ;
gegen byte bad_cyc = max(bad_inst), by(project_number cycle) ;
egen byte t_c = tag(project_number cycle) ;
keep if t_c ;
keep project_number cycle n_start P n_years p_years nsupp bad_cyc ;
tempfile cpi ;
save `cpi' ;

/* -----------------------------------------------------------------------------
   4. One row per grant cycle with a single PI on its starting award
   ----------------------------------------------------------------------------- */
use `cyc', clear ;
merge 1:1 project_number cycle using `cpi' ;
assert _merge == 3 ;
drop _merge ;
merge 1:1 project_number cycle using `pattr' ;
assert _merge != 2 ;
drop _merge ;
merge 1:1 project_number cycle using `dol' ;
assert _merge != 2 ;
drop _merge ;
display as result "=== grant cycles, by the number of PIs on the award that starts them: all, and starting `first_lo' to `first_hi', outcome observed" ;
gen byte n_start_c = min(n_start, 3) ;
tab n_start_c ;
tab n_start_c if inrange(cycle_yr, `first_lo', `first_hi') & !censored & !start_noncomp ;
drop n_start_c ;
/* a cycle whose starting award lists several PIs has no PI to carry: it leaves the file */
drop if n_start != 1 ;
drop n_start ;
rename P setnb ;
replace dollars = 0 if dollars == . ;

gen byte pi_all_years = p_years == n_years ;   /* the starting PI holds every year    */
gen byte budget_ok = nsupp >= 3 ;              /* three distinct budget years of its own   */
gen byte inst_ok   = !bad_cyc ;                /* no record at an excluded institution     */
gen byte miss_app  = app_id == . ;             /* no application ID on its starting award  */
drop bad_cyc ;

/* -----------------------------------------------------------------------------
   5. Study section of the application that starts the cycle, from the
      study-section file. sep flags the special emphasis panels (codes starting with Z, and SSS, NCR, NSS,
      SRC, SRCA, SRCD), whose cycles the analysis sample excludes.
   ----------------------------------------------------------------------------- */
preserve ;
    use app_id study_section using "${cgaf}/cgaf_study_sections_000.dta", clear ;
    bysort app_id (study_section): keep if _n == 1 ;  /* explicit tie-break: first study section in sort order */
    tempfile ss1 ;
    save `ss1' ;
restore ;
merge m:1 app_id using `ss1', gen(m_ss1) ;
tab m_ss1 ;
drop if m_ss1 == 2 ;
drop m_ss1 ;
gen byte sep = substr(study_section, 1, 1) == "Z" |
    inlist(study_section, "SSS", "NCR", "NSS", "SRC", "SRCA", "SRCD") ;
replace sep = . if study_section == "" ;
rename study_section irg_code ;

/* -----------------------------------------------------------------------------
   6. The PI's attributes: Author-ity ID, gender, degree and degree year.
      Gender is the grant file's female, one value per investigator, a mix of
      Genni and the authors' own records.
   ----------------------------------------------------------------------------- */
preserve ;
    use setnb female using "${input}/cgaf_nih_risk.dta", clear ;
    bysort setnb (female): assert female == female[1] ;  /* one value per investigator, or none */
    by setnb: keep if _n == 1 ;
    tempfile g1 ;
    save `g1' ;
restore ;
merge m:1 setnb using "${pubmed_root}/authority/matchCGAF/matches2022/cnsldt_goodmatches.dta",
      keepusing(author_id) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge m:1 setnb using `g1' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;

egen deg_year = rmax(MDyear PhDyear hPhDyear) ;
rename deg_cgaf deg ;
replace deg = 1 if MDyear <  . & PhDyear == . & hPhDyear == . & deg == . ;
replace deg = 2 if MDyear == . & PhDyear <  . & hPhDyear == . & deg == . ;
replace deg = 3 if MDyear <  . & PhDyear <  . & hPhDyear == . & deg == . ;
replace deg = 4 if MDyear == . & PhDyear == . & hPhDyear <  . & deg == . ;
replace deg = 5 if MDyear <  . & PhDyear == . & hPhDyear <  . & deg == . ;
replace deg = 6 if MDyear == . & PhDyear <  . & hPhDyear <  . & deg == . ;
replace deg = 7 if MDyear <  . & PhDyear <  . & hPhDyear <  . & deg == . ;

/* -----------------------------------------------------------------------------
   7. Sample flags and save
   ----------------------------------------------------------------------------- */
/* the cycle: its single PI holds every year of it, and it passes the filters on its
   own records */
gen byte cycle_ok = pi_all_years & budget_ok & inst_ok & !miss_app & !any_pbm ;
/* the PI must be identified: an Author-ity ID (for the PI's papers), a degree and its
   year (for age and the degree groups), and a known gender */
gen byte inv_ok = !missing(author_id) & !missing(deg_year) & !missing(deg) & deg != 0 & !missing(female) ;
/* a first cycle whose first record is not a competing award has an unobserved start: excluded */
gen byte in_sample = cycle_ok & inv_ok & inrange(cycle_yr, `first_lo', `first_hi') & !censored & !start_noncomp ;

display as result "=== PIs of the analysis sample (sep != 1): gender" ;
egen byte tag_ps = tag(setnb) if in_sample & sep != 1 ;
tab female if tag_ps == 1, missing ;
drop tag_ps ;

label var cycle            "Cycle number within the grant (the grant's, whoever holds it)" ;
label var cycle_yr         "First year of the cycle (first payment)" ;
label var eval_year        "Evaluation year: last payment year of the cycle" ;
label var span_start       "First year whose papers the cycle can receive" ;
label var cycle_length     "eval_year - cycle_yr + 1" ;
label var gap_next         "The grant's next competing award's first year minus eval_year" ;
label var renewed          "Renewed: the grant's next competing award within `lapse_max' FY of last payment" ;
label var renewed_strict   "Renewed with no unpaid year" ;
label var renewed_nolimit  "Renewed at any distance" ;
label var revival          "Cycle starts after a gap longer than `lapse_max' FY" ;
label var censored         "Outcome not observable within the data" ;
label var has_t7           "Change of grantee institution (type 7) during the cycle" ;
label var new_ipfcode      "Institution in the cycle's first year" ;
label var ipf_eval         "Institution in the cycle's last year of payments" ;
label var first_is_renewal "Grant's first R01-equivalent record is a competing renewal" ;
label var start_act        "Activity code of the award that starts the cycle" ;
label var am_link          "Grant of institute AM continued under DK or AR after the 1986 split" ;
label var dollars          "The PI's payments in the cycle's years (start year counted with the cycle it starts)" ;
label var n_years          "Years of the cycle (its own records)" ;
label var p_years          "Years of the cycle with a record of its PI" ;
label var nsupp            "Distinct budget years of the cycle's own records" ;
label var pi_all_years     "The PI of the starting award holds every year of the cycle" ;
label var budget_ok        "At least three distinct budget years of the cycle's own" ;
label var inst_ok          "No record of the cycle at an excluded or uncoded institution" ;
label var miss_app         "No application ID on the award that starts the cycle" ;
label var cycle_ok         "Cycle has a single PI throughout and passes the filters on its own records" ;
label var inv_ok           "PI identified: Author-ity ID, degree, degree year, gender" ;
label var female           "Investigator is a woman" ;
label var in_sample        "Analysis sample: cycles starting 1980-2015, outcome observed, single PI, filters" ;

order setnb project_number cycle cycle_yr span_start eval_year cycle_length gap_next
      renewed renewed_strict renewed_nolimit revival censored in_sample cycle_ok inv_ok
      pi_all_years budget_ok inst_ok miss_app start_act start_atype has_t7
      first_is_renewal app_id irg_code sep ic ;
gisid setnb project_number cycle ;
gisid project_number cycle ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycles.dta", replace ;

/* -----------------------------------------------------------------------------
   8. First look
   ----------------------------------------------------------------------------- */
display as result "=== cycles, investigators and grants of the file" ;
count ;
distinct setnb project_number, joint ;
count if in_sample ;
display as result "=== the analysis sample (in_sample, sep != 1): cycles, investigators, grants, renewal" ;
count if in_sample & sep != 1 ;
distinct setnb if in_sample & sep != 1 ;
distinct project_number if in_sample & sep != 1 ;
summarize renewed if in_sample & sep != 1 ;
display as result "=== why cycles fall out (cycles starting `first_lo' to `first_hi', outcome observed, start observed)" ;
gen byte frame = inrange(cycle_yr, `first_lo', `first_hi') & !censored & !start_noncomp ;
tab cycle_ok inv_ok if frame ;
tab pi_all_years if frame ;
tab budget_ok if frame & pi_all_years ;
tab inst_ok if frame & pi_all_years & budget_ok ;
tab miss_app if frame & pi_all_years & budget_ok & inst_ok ;
display as result "=== short cycles (fewer than three budget years): first and later, renewal" ;
gen byte first_cyc = cycle == 1 ;
table (first_cyc) if frame & pi_all_years & inst_ok & !miss_app & inv_ok & !budget_ok, statistic(count renewed) statistic(mean renewed) nformat(%9.3f mean) ;
drop frame first_cyc ;
display as result "=== cycles of a PI who is not the grant's first (a successor), in the analysis sample" ;
bysort project_number (cycle): gen byte succ = setnb != setnb[1] ;
tab succ if in_sample & sep != 1 ;
drop succ ;
display as result "=== activity that starts the cycle (sample)" ;
tab start_act if in_sample ;
display as result "=== renewal (sample)" ;
summarize renewed renewed_strict renewed_nolimit revival if in_sample ;
tab gap_next if in_sample & gap_next < 10 ;
display as result "=== renewal rate by evaluation year (sample)" ;
tabstat renewed if in_sample, by(eval_year) stat(n mean) nototal ;
display as result "=== grants linked across the 1986 split: sample cycles by evaluation year and institute" ;
tab eval_year ic if in_sample & am_link & inrange(eval_year, 1982, 1990) ;
tabstat renewed if in_sample & am_link, by(eval_year) stat(n mean) nototal ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/01_cycles.do */
