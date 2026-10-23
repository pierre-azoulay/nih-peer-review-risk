/* =============================================================================
   code/build/33_outcome_windows.do

   Purpose: The downstream outcomes of each cycle in windows defined on the
            papers acknowledging the grant on which the investigator is an
            author, for Tables 1e and 3 (code/analysis/11_tables_1e_3.do),
            which use the window after the cycle's last payment:
              _dur   published from span_start to eval_year, the cycle's
                     papers as code/build/03_cycle_papers.do attributes them
              _aft   published from eval_year + 1 to eval_year + 5, whichever
                     cycle they belong to, or none (a paper published after a
                     grant's last payment belongs to no cycle)
              _both  the two together
              _a3    published from eval_year + 1 to eval_year + 3 (a check)
            In each window, six outcomes, built as in code/build/16_patents.do,
            17_cycle_cites.do and 18_commercial_potential.do:
              n_pubs        papers
              cites5        their five-year citations (cite5)
              pat_cites     patent citations (paper-patent pairs, Reliance on
                            Science 2026, confidence 6 or more)
              pharma_cites  the pairs whose patent is in the Russet Book
              kpss_value    the KPSS value of the distinct citing patents,
                            millions of 2023 dollars (a patent citing papers
                            of both windows counts once in _both)
              compot_mean   mean commercial potential of the scored papers
                            (n_compot: the scored papers)
            And the patents of the grant in the same windows (n_grpat_dur,
            _aft, _both, _a3): the patents that NIH RePORTER links to an
            R01-equivalent grant (R01, R37, R29, R23; the old NIADDK numbers
            mapped to their successors), counted by the year their
            application was filed (PatentsView). Tables 1e and 3 use the
            after window: five of the six outcomes (all but n_pubs) and the
            patents of the grant.
            Also, for the log, the after-window papers attributed to the
            next cycle by renewal (n_aft_next), to a revival cycle
            (n_aft_rev), to a later cycle by renewal (n_aft_later), and to no
            cycle (n_aft_none). And next_revival, the flag for a grant whose
            next cycle is a revival (the grant's next competing award starts
            more than three fiscal years after this cycle's last payment),
            with which Tables 1e and 3 keep grants revived later out of the
            non-renewed cycles.
            The during window must reproduce n_ackn, cites5_ackn, pat_cites,
            pharma_cites, kpss_value and compot_mean on every cycle, or the
            do-file stops. It runs after code/build/23_analysis_file.do, whose
            analysis file it reads for the last section only. Its output stays
            apart from the analysis file: 11_tables_1e_3.do merges it in.

   Input:
     - ${data}/build/cycles.dta, am_successor.dta   (code/build/01_cycles.do)
     - ${data}/build/ackn_links.dta                 (code/build/02_ackn_links.do)
     - ${data}/build/paper_attributes.dta           (code/build/05_paper_attributes.do)
     - ${data}/build/cycle_output.dta (code/build/06_cycle_output.do),
       cycle_patents.dta (code/build/16_patents.do), cycle_cites.dta
       (code/build/17_cycle_cites.do), cycle_commpot.dta
       (code/build/18_commercial_potential.do), for the check
     - ${cpi}   CPI-U, monthly (FRED CPIAUCSL), shipped with the package
     - ${pubmed_root}/reliance_on_science/pmid2patent_2026.dta, kpss/KPSS_2023.csv,
       comm_pot/consolidated_comm_pot_2026.dta
     - ${pubmed_root}/russet_book/russet_patents.dta
     - ${cgaf}/raw/patents/Patents.csv   NIH RePORTER patent links (the
       version of 14 October 2026)
     - ${pubmed_root}/reliance_on_science/g_application.tsv   PatentsView,
       February 2026: filing dates
     - ${data}/output/nih_risk_analysis.dta   (code/build/23_analysis_file.do),
       for the last section only

   Output:
     - ${data}/build/cycle_windows.dta, one row per cycle of the cycle file
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/33_outcome_windows.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* the windows, in the order of the output's variables */
local nw 4 ;
local w1 "dur" ;
local w2 "aft" ;
local w3 "both" ;
local w4 "a3" ;

/* -----------------------------------------------------------------------------
   1. KPSS values in 2023 dollars (as code/build/16_patents.do, section 1),
      from the copy of the CPI series shipped with the package, ${cpi}
   ----------------------------------------------------------------------------- */
tempfile cpiraw kpssraw ;
#delimit cr
python:
import pandas as pd
from sfi import Macro, SFIToolkit
c = pd.read_csv(Macro.getGlobal("cpi"))
c.columns = ["date", "cpi"]
c["date"] = pd.to_datetime(c["date"])
c["year"] = c["date"].dt.year
c["month"] = c["date"].dt.month
SFIToolkit.display("CPIAUCSL from " + str(c["date"].min().date()) + " to " + str(c["date"].max().date()))
c[["year", "month", "cpi"]].to_stata(Macro.getLocal("cpiraw"), write_index=False, version=118)
src = Macro.getGlobal("pubmed_root") + "/reliance_on_science/kpss/KPSS_2023.csv"
k = pd.read_csv(src, usecols=["patent_num", "issue_date", "xi_nominal"])
k.to_stata(Macro.getLocal("kpssraw"), write_index=False, version=118)
end
#delimit ;
use `cpiraw', clear ;
gegen double cpi_2023 = max(cond(year == 2023, cpi, .)) ;
gen double inflation_adj = cpi / cpi_2023 ;
keep year month inflation_adj ;
gisid year month ;
tempfile cpi ;
save `cpi' ;

use `kpssraw', clear ;
rename patent_num patent ;
gen int year  = floor(issue_date / 10000) ;
gen int month = floor(mod(issue_date, 10000) / 100) ;
drop if year < 1950 ;
merge m:1 year month using `cpi' ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;
gen double kpss = xi_nominal / inflation_adj ;
keep patent kpss ;
gisid patent ;
tempfile kpss ;
save `kpss' ;

/* -----------------------------------------------------------------------------
   2. The attributes of every paper with an acknowledging link
   ----------------------------------------------------------------------------- */
use patent using "${pubmed_root}/russet_book/russet_patents.dta" if !missing(patent), clear ;
gisid patent ;
gen byte pharma = 1 ;
tempfile pharma ;
save `pharma' ;

use pmid using "${data}/build/ackn_links.dta", clear ;
gduplicates drop ;
tempfile apids ;
save `apids' ;

/* paper-patent pairs, as in code/build/16_patents.do */
use pmid patent cnfdnc_score using "${pubmed_root}/reliance_on_science/pmid2patent_2026.dta", clear ;
merge m:1 pmid using `apids' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
keep if cnfdnc_score >= 6 ;
drop cnfdnc_score ;
merge m:1 patent using `pharma' ;
tab _merge ;
drop if _merge == 2 ;
replace pharma = 0 if _merge == 1 ;
drop _merge ;
merge m:1 patent using `kpss' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
tempfile pairs ;
save `pairs' ;
gen byte one = 1 ;
gcollapse (sum) npat = one npharma = pharma, by(pmid) ;
tempfile ppat ;
save `ppat' ;

/* one row per paper: citations, patent pairs, commercial potential */
use `apids', clear ;
merge 1:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using `ppat' ;
assert _merge != 2 ;
drop _merge ;
replace npat = 0 if missing(npat) ;
replace npharma = 0 if missing(npharma) ;
merge 1:1 pmid using "${pubmed_root}/reliance_on_science/comm_pot/consolidated_comm_pot_2026.dta",
    keepusing(compot) ;
tab _merge ;
drop if _merge == 2 ;
gen byte scored = (_merge == 3) & !missing(compot) ;
drop _merge ;
gisid pmid ;
tempfile paper ;
save `paper' ;

/* -----------------------------------------------------------------------------
   3. Each cycle's papers in the windows
   ----------------------------------------------------------------------------- */
use setnb project_number cycle span_start eval_year revival gap_next using "${data}/build/cycles.dta", clear ;
sort setnb project_number cycle ;
/* the grant's next cycle is a revival: the grant's next competing award starts more
   than three fiscal years after this cycle's last payment (lapse_max of
   code/build/01_cycles.do). gap_next is the grant's, whoever holds its next cycle,
   which may be another PI or a team, whose cycles the cycle file does not hold */
gen byte next_revival = gap_next > 3 & gap_next < . ;
drop gap_next ;
tempfile cyc ;
save `cyc' ;
keep setnb project_number cycle revival ;
rename (cycle revival) (att_cycle att_revival) ;
tempfile attrev ;
save `attrev' ;
use setnb project_number cycle span_start eval_year using `cyc', clear ;
tempfile win ;
save `win' ;

/* the cycle each link belongs to, if any (code/build/03_cycle_papers.do,
   section 2) */
use setnb project_number pmid pubyear using "${data}/build/ackn_links.dta", clear ;
joinby setnb project_number using `win' ;
keep if pubyear >= span_start & pubyear <= eval_year ;
keep setnb project_number pmid cycle ;
rename cycle att_cycle ;
gisid setnb project_number pmid ;
tempfile att ;
save `att' ;

/* cycle x paper, for the papers in a window */
use setnb project_number pmid pubyear using "${data}/build/ackn_links.dta", clear ;
joinby setnb project_number using `win' ;
gen int k = pubyear - eval_year ;
gen byte w_dur  = pubyear >= span_start & pubyear <= eval_year ;
gen byte w_aft  = inrange(k, 1, 5) ;
gen byte w_a3   = inrange(k, 1, 3) ;
keep if w_dur | w_aft ;
gen byte w_both = 1 ;
merge m:1 setnb project_number pmid using `att' ;
tab _merge ;
assert _merge != 2 ;
drop _merge ;
merge m:1 setnb project_number att_cycle using `attrev', keepusing(att_revival) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
/* after-window papers by the cycle they belong to: the next cycle by renewal,
   a revival (for a non-renewed cycle, any later cycle is one or follows one),
   a later cycle by renewal, none */
gen byte a_next  = w_aft & att_cycle == cycle + 1 & att_revival == 0 ;
gen byte a_rev   = w_aft & att_cycle > cycle & att_cycle < . & att_revival == 1 ;
gen byte a_later = w_aft & att_cycle > cycle + 1 & att_cycle < . & att_revival == 0 ;
gen byte a_none  = w_aft & missing(att_cycle) ;
assert a_next + a_rev + a_later + a_none == w_aft ;
gisid setnb project_number cycle pmid ;
merge m:1 pmid using `paper' ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
display as result "=== cycle x paper rows in a window: during, after (1 to 5 years), after (1 to 3 years)" ;
tabstat w_dur w_aft w_a3, stat(sum) ;
display as result "=== after-window papers, by years after the last payment" ;
tab k if w_aft ;
tempfile cp ;
save `cp' ;

/* counts, citations, patent pairs, commercial potential, by window */
local clist "" ;
forvalues i = 1/`nw' {;
    local w "`w`i''" ;
    gen double c_`w'  = cite5 if w_`w' ;
    gen double p_`w'  = npat if w_`w' ;
    gen double h_`w'  = npharma if w_`w' ;
    gen float  cp_`w' = compot if w_`w' ;  /* float, as compot: the mean of 18_commercial_potential.do is a float */
    gen byte   s_`w'  = scored & w_`w' ;
    local clist "`clist' n_pubs_`w' = w_`w' cites5_`w' = c_`w' pat_cites_`w' = p_`w' pharma_cites_`w' = h_`w' n_compot_`w' = s_`w'" ;
} ;
gcollapse (sum) `clist' n_aft_next = a_next n_aft_rev = a_rev n_aft_later = a_later n_aft_none = a_none
          (mean) compot_mean_dur = cp_dur compot_mean_aft = cp_aft compot_mean_both = cp_both compot_mean_a3 = cp_a3,
    by(setnb project_number cycle) ;
forvalues i = 1/`nw' {;
    replace compot_mean_`w`i'' = . if n_compot_`w`i'' == 0 ;
} ;
tempfile sums ;
save `sums' ;

/* KPSS: each distinct citing patent once per cycle and window */
use setnb project_number cycle pmid w_dur w_aft w_both w_a3 using `cp', clear ;
joinby pmid using `pairs' ;
keep setnb project_number cycle patent kpss w_dur w_aft w_both w_a3 ;
tempfile cpp ;
save `cpp' ;
forvalues i = 1/`nw' {;
    local w "`w`i''" ;
    use `cpp' if w_`w', clear ;
    bysort setnb project_number cycle patent: keep if _n == 1 ;
    gcollapse (sum) kpss_value_`w' = kpss, by(setnb project_number cycle) ;
    tempfile kv`i' ;
    save `kv`i'' ;
} ;

/* the patents of the grant: the patents NIH RePORTER links to an R01-equivalent
   grant, by the year their application was filed (PatentsView), counted in the
   same windows. DuckDB reads the two files (the application table is 437 MB) */
tempfile grraw ;
#delimit cr
python:
import duckdb
from sfi import Macro, SFIToolkit
pat = Macro.getGlobal("cgaf") + "/raw/patents/Patents.csv"
app = Macro.getGlobal("pubmed_root") + "/reliance_on_science/g_application.tsv"
q1 = "SELECT DISTINCT substr(PROJECT_ID, 4, 8) AS project_number, CAST(PATENT_ID AS VARCHAR) AS patent_id FROM read_csv('" + pat + "', header=true, all_varchar=true) WHERE substr(PROJECT_ID, 1, 3) IN ('R01', 'R37', 'R29', 'R23')"
q2 = "SELECT patent_id, min(TRY_CAST(substr(filing_date, 1, 4) AS INTEGER)) AS fyear FROM read_csv('" + app + "', delim='\t', header=true, all_varchar=true) GROUP BY patent_id"
sql = "WITH l AS (" + q1 + "), a AS (" + q2 + ") SELECT l.project_number, l.patent_id, a.fyear FROM l LEFT JOIN a USING (patent_id) ORDER BY l.project_number, l.patent_id"
con = duckdb.connect()
try:
    df = con.execute(sql).df()
finally:
    con.close()
df.to_stata(Macro.getLocal("grraw"), write_index=False, version=118)
SFIToolkit.display("RePORTER links of R01-equivalent grants: " + str(len(df)))
end
#delimit ;
use `grraw', clear ;
display as result "=== the patents of the grant: filing years (missing or outside 1950 to 2026 dropped)" ;
replace fyear = . if fyear < 1950 | fyear > 2026 ;
count if missing(fyear) ;
drop if missing(fyear) ;
/* the old NIADDK numbers take their successor's, as the cycle file does
   (code/build/01_cycles.do) */
rename project_number pn_am ;
merge m:1 pn_am using "${data}/build/am_successor.dta", keepusing(pn_succ) ;
tab _merge ;
drop if _merge == 2 ;
gen str8 project_number = cond(_merge == 3, pn_succ, pn_am) ;
drop _merge pn_am pn_succ ;
gduplicates drop project_number patent_id, force ;
summarize fyear ;
tempfile grpat ;
save `grpat' ;
use setnb project_number cycle span_start eval_year using `cyc', clear ;
joinby project_number using `grpat' ;
gen int k = fyear - eval_year ;
gen byte g_dur  = fyear >= span_start & fyear <= eval_year ;
gen byte g_aft  = inrange(k, 1, 5) ;
gen byte g_a3   = inrange(k, 1, 3) ;
gen byte g_both = g_dur | g_aft ;
gcollapse (sum) n_grpat_dur = g_dur n_grpat_aft = g_aft n_grpat_both = g_both n_grpat_a3 = g_a3,
    by(setnb project_number cycle) ;
tempfile gps ;
save `gps' ;

/* every cycle of the cycle file; zero where no paper falls in a window */
use setnb project_number cycle next_revival using `cyc', clear ;
merge 1:1 setnb project_number cycle using `gps' ;
assert _merge != 2 ;
drop _merge ;
foreach v in n_grpat_dur n_grpat_aft n_grpat_both n_grpat_a3 {;
    replace `v' = 0 if missing(`v') ;
} ;
merge 1:1 setnb project_number cycle using `sums' ;
assert _merge != 2 ;
drop _merge ;
forvalues i = 1/`nw' {;
    merge 1:1 setnb project_number cycle using `kv`i'' ;
    assert _merge != 2 ;
    drop _merge ;
} ;
forvalues i = 1/`nw' {;
    local w "`w`i''" ;
    foreach v in n_pubs cites5 pat_cites pharma_cites kpss_value n_compot {;
        replace `v'_`w' = 0 if missing(`v'_`w') ;
    } ;
} ;
foreach v in n_aft_next n_aft_rev n_aft_later n_aft_none {;
    replace `v' = 0 if missing(`v') ;
} ;

/* -----------------------------------------------------------------------------
   4. Check: the during window reproduces the stored outcomes on every cycle
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/cycle_output.dta", keepusing(n_ackn) ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_cites.dta", keepusing(cites5_ackn) ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_patents.dta", keepusing(pat_cites pharma_cites kpss_value) ;
tab _merge ;
assert _merge != 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_commpot.dta", keepusing(compot_mean) ;
tab _merge ;
assert _merge != 2 ;
drop _merge ;
foreach v in pat_cites pharma_cites kpss_value {;
    replace `v' = 0 if missing(`v') ;
} ;
display as result "=== check: the during window against the stored outcomes (every count must be 0)" ;
count if n_pubs_dur != n_ackn ;
local e1 = r(N) ;
count if reldif(cites5_dur, cites5_ackn) > 1e-9 ;
local e2 = r(N) ;
count if pat_cites_dur != pat_cites ;
local e3 = r(N) ;
count if pharma_cites_dur != pharma_cites ;
local e4 = r(N) ;
count if reldif(kpss_value_dur, kpss_value) > 1e-9 ;
local e5 = r(N) ;
count if !(missing(compot_mean_dur) & missing(compot_mean)) & !(reldif(compot_mean_dur, compot_mean) <= 1e-9) ;
local e6 = r(N) ;
display as result "n_ackn `e1', cites5_ackn `e2', pat_cites `e3', pharma_cites `e4', kpss_value `e5', compot_mean `e6'" ;
assert `e1' + `e2' + `e3' + `e4' + `e5' + `e6' == 0 ;
drop n_ackn cites5_ackn pat_cites pharma_cites kpss_value compot_mean ;

/* labels and save */
local lb_dur  "during the cycle" ;
local lb_aft  "1 to 5 years after the last payment" ;
local lb_both "during and 1 to 5 years after" ;
local lb_a3   "1 to 3 years after the last payment" ;
forvalues i = 1/`nw' {;
    local w "`w`i''" ;
    label variable n_pubs_`w'       "Acknowledging papers, `lb_`w''" ;
    label variable cites5_`w'       "Five-year citations to them, `lb_`w''" ;
    label variable pat_cites_`w'    "Patent citations to them, `lb_`w''" ;
    label variable pharma_cites_`w' "Russet Book patent citations to them, `lb_`w''" ;
    label variable kpss_value_`w'   "KPSS value of the distinct citing patents, `lb_`w''" ;
    label variable compot_mean_`w'  "Mean commercial potential of the scored papers, `lb_`w''" ;
    label variable n_compot_`w'     "Scored papers, `lb_`w''" ;
} ;
label variable n_aft_next   "After-window papers attributed to the next cycle, by renewal" ;
label variable n_aft_rev    "After-window papers attributed to a revival cycle" ;
label variable n_aft_later  "After-window papers attributed to a later cycle, by renewal" ;
label variable n_aft_none   "After-window papers attributed to no cycle" ;
label variable next_revival "The grant's next cycle is a revival" ;
label variable n_grpat_dur  "Patents of the grant (RePORTER), filed during the cycle" ;
label variable n_grpat_aft  "Patents of the grant (RePORTER), filed 1 to 5 years after the last payment" ;
label variable n_grpat_both "Patents of the grant (RePORTER), filed during or 1 to 5 years after" ;
label variable n_grpat_a3   "Patents of the grant (RePORTER), filed 1 to 3 years after the last payment" ;
order setnb project_number cycle next_revival
      n_pubs_* cites5_* pat_cites_* pharma_cites_* kpss_value_* compot_mean_* n_compot_* n_grpat_* n_aft_* ;
gisid setnb project_number cycle ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_windows.dta", replace ;
describe, short ;

/* -----------------------------------------------------------------------------
   5. A first look, in the log: analysis cycles with an acknowledging
      paper, by rung and side
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/output/nih_risk_analysis.dta",
    keepusing(renewed cycle_nb eval_year n_ackn) ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
gen byte rung = cond(missing(cycle_nb), ., min(cycle_nb, 4)) ;  /* min() ignores a missing argument */
gen byte any_aft  = n_pubs_aft > 0 ;
gen byte any_none = n_aft_none > 0 ;
display as result "=== analysis cycles with an acknowledging paper, evaluated by 2020: by rung (4 = 4 or more, . = unknown) and side" ;
table (rung) (renewed) if n_ackn >= 1 & eval_year <= 2020, statistic(frequency) statistic(mean n_pubs_dur n_pubs_aft any_aft) nformat(%6.2f mean) ;
display as result "=== the same, after-window papers attributed to the next cycle, a revival, none" ;
tabstat n_aft_next n_aft_rev n_aft_later n_aft_none any_none if n_ackn >= 1 & eval_year <= 2020, by(renewed) stat(mean sum) format(%9.2f) ;
display as result "=== non-renewed cycles, evaluated by 2020, with a paper during the cycle" ;
summarize n_pubs_aft n_aft_none any_aft any_none if renewed == 0 & n_ackn >= 1 & eval_year <= 2020 ;
summarize n_ackn if renewed == 0 & n_ackn >= 1 ;
display as result "=== non-renewed cycles evaluated by 2020 without a paper during the cycle, and those of them with one after" ;
count if renewed == 0 & n_ackn == 0 & eval_year <= 2020 ;
count if renewed == 0 & n_ackn == 0 & eval_year <= 2020 & n_aft_none > 0 ;
display as result "=== the patents of the grant: last cycles (not renewed, grant not revived), evaluated by 2020, a paper during the cycle, by rung" ;
gen byte any_grpat = n_grpat_aft > 0 ;
tabstat n_grpat_aft any_grpat if renewed == 0 & !next_revival & n_ackn >= 1 & eval_year <= 2020, by(rung) stat(n mean sum) format(%9.3f) ;
display as result "=== the six outcomes by window, renewed and non-renewed (evaluated by 2020, a paper during the cycle)" ;
foreach w in dur aft both {;
    tabstat n_pubs_`w' cites5_`w' pat_cites_`w' pharma_cites_`w' kpss_value_`w' compot_mean_`w'
        if n_ackn >= 1 & eval_year <= 2020, by(renewed) stat(mean) format(%9.2f) ;
} ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
