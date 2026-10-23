/* =============================================================================
   code/build/02_ackn_links.do

   Purpose: Acknowledgment links from the RePORTER link tables to the grants of the
            cycle file, restricted to English-language original research, with an
            author check; then the number of acknowledging papers in each cycle's
            window (span_start <= pubyear <= eval_year).

            The author check:
            - the paper's author list is complete (cmplt_list == 1, max_authr_seq ==
              nb_authrs) and has at most 20 authors; author last names longer than
              30 characters are dropped. A paper that fails these tests loses all
              its links;
            - an investigator of the grant has the same last name as an author (both
              through supermessoudar), using CGAF's first, middle and last names;
            - when several authors share that last name, initials break the tie: a
              match on first and middle initials beats a match on the first initial
              only, which beats a match on neither;
            - a link still matched by more than one author is dropped as ambiguous.
            Ambiguity is tested per investigator, grant and paper, not per grant and
            paper: a paper co-authored by two investigators of the same grant stays
            linked to each of them. The log counts the links that a test per grant
            and paper would drop.

   Input:
     - ${data}/build/cycles.dta                     (code/build/01_cycles.do)
     - ${data}/build/am_successor.dta               AM grants and their DK or AR successors
                                                    (code/build/01_cycles.do)
     - ${links}: RePORTER_PUBLNK_C_FY.csv files     RePORTER publication links, FY1980 to 2025
     - ${input}/cgaf_nih_risk.dta                   investigators' first, middle, last names
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_nb_of_authors_2025.dta
     - ${pq}/auth_names.parquet                     author names of the PubMed baseline

   Output:
     - ${data}/build/ackn_links_unchecked.dta  project_number pmid pubyear: every link, no
                                               author check
     - ${data}/build/ackn_links.dta            setnb project_number pmid pubyear author_seq
                                               nb_authrs: links passing the author check
     - ${data}/build/cycle_paper_counts.dta    setnb project_number cycle ... n_ackn
                                               n_ackn_unchecked

   Note: needs the author names of the PubMed baseline in parquet (${pq}, which
         config.do sets from bulk). The authors of the linked papers are read
         with DuckDB, through Stata's Python.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/02_ackn_links.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

capture confirm file "${pq}/auth_names.parquet" ;
if _rc {;
    display as error "this script needs the author names of the PubMed baseline in parquet: set bulk in config.do" ;
    exit 601 ;
} ;

/* -----------------------------------------------------------------------------
   1. Links to the cycle file's grants, English original research
   ----------------------------------------------------------------------------- */
use setnb project_number using "${data}/build/cycles.dta", clear ;
bysort setnb project_number: keep if _n == 1 ;
tempfile invgrant ;
save `invgrant' ;
bysort project_number: keep if _n == 1 ;
keep project_number ;
tempfile projects ;
save `projects' ;

/* one row per PMID */
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
keep if orgnl == 1 & eng == 1 ;
keep pmid pubyear ;
tempfile pm ;
save `pm' ;

/* the link tables: dir returns bare file names (no spaces), quoted, so foreach is safe here */
local files : dir "${links}" files "*.csv" ;
local first 1 ;
foreach f of local files {;
    import delimited using "${links}/`f'", clear stringcols(_all) varnames(1) ;
    keep if inlist(substr(project_number, 1, 3), "R01", "R37", "R29", "R23") ;
    gen str8 pn = substr(project_number, 4, 8) ;
    destring pmid, replace force ;
    keep pmid pn ;
    if `first' {;
        tempfile links ;
        save `links' ;
        local first 0 ;
    } ;
    else {;
        append using `links' ;
        save `links', replace ;
    } ;
} ;
use `links', clear ;
/* AM grants carry the project number of their DK or AR successor (the 1986 split of
   NIADDK, code/build/01_cycles.do), so links under the AM number go to the successor */
rename pn pn_am ;
merge m:1 pn_am using "${data}/build/am_successor.dta", keepusing(pn_succ) ;
tab _merge ;
drop if _merge == 2 ;
display as result "=== links under an AM number moved to the successor grant: " ;
count if _merge == 3 ;
replace pn_am = pn_succ if _merge == 3 ;
drop _merge pn_succ ;
rename pn_am project_number ;
drop if pmid == . ;
duplicates drop ;
merge m:1 project_number using `projects' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
merge m:1 pmid using `pm' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
sort project_number pmid ;
compress ;
save "${data}/build/ackn_links_unchecked.dta", replace ;
display as result "=== links to cycle-file grants (English original research), before the author check: " _N ;

/* -----------------------------------------------------------------------------
   2. Investigators' names, by investigator and grant (CGAF)
   ----------------------------------------------------------------------------- */
use setnb activity ic grantno first middle last using "${input}/cgaf_nih_risk.dta", clear ;
keep if inlist(activity, "R01", "R37", "R29", "R23") ;
gen str8 pn_am = ic + grantno ;
merge m:1 pn_am using "${data}/build/am_successor.dta", keepusing(pn_succ) ;
tab _merge ;
drop if _merge == 2 ;
replace pn_am = pn_succ if _merge == 3 ;
drop _merge pn_succ ;
rename pn_am project_number ;
keep setnb project_number first middle last ;
duplicates drop ;
merge m:1 setnb project_number using `invgrant' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
supermessoudar last ;
gen str1 f = substr(lower(first), 1, 1) ;
gen str1 m = substr(lower(middle), 1, 1) ;
drop if last == "" ;
keep setnb project_number last f m ;
duplicates drop ;
bysort setnb project_number: gen n_namevar = _N ;
display as result "=== name variants per investigator and grant" ;
tab n_namevar ;
drop n_namevar ;
tempfile names ;
save `names' ;

/* -----------------------------------------------------------------------------
   3. Authors of the linked papers: complete lists of at most 20 authors
   ----------------------------------------------------------------------------- */
use pmid using "${data}/build/ackn_links_unchecked.dta", clear ;
bysort pmid: keep if _n == 1 ;
merge 1:1 pmid using "${pubmed_root}/pubmed/overall_nb_of_authors_2025.dta",
      keepusing(filenb seq nb_authrs cmplt_list max_authr_seq) ;
tab _merge ;
drop if _merge == 2 ;
display as result "=== linked papers: in the author-count file, complete list, last sequence = number of authors, more than 20 authors" ;
count ;
count if _merge == 3 ;
count if cmplt_list == 1 ;
count if cmplt_list == 1 & max_authr_seq == nb_authrs ;
count if cmplt_list == 1 & max_authr_seq == nb_authrs & nb_authrs > 20 & nb_authrs < . ;
keep if _merge == 3 & cmplt_list == 1 & max_authr_seq == nb_authrs & nb_authrs <= 20 ;
keep pmid filenb seq nb_authrs ;
tempfile ver ;
save `ver' ;

/* the authors of the record version the PubMed 2025 files keep (pmid, filenb, seq) */
local authpq = subinstr("`c(tmpdir)'", "\", "/", .) + "/nihrep_ackn_authors.parquet" ;
#delimit cr
python:
import duckdb, pandas as pd
from sfi import Macro, SFIToolkit
src = Macro.getGlobal("pq").replace("\\", "/") + "/auth_names.parquet"
out = Macro.getLocal("authpq")
ver = pd.read_stata(Macro.getLocal("ver"))[["pmid", "filenb", "seq"]].astype("int64")
con = duckdb.connect()
try:
    con.execute("SET threads=8")
    con.register("ver", ver)
    # a plain string, not an f-string: run in Stata's batch mode, Python 3.12
    # and later cannot read a triple-quoted f-string that spans lines
    sql = """COPY (SELECT CAST(a.pmid AS INTEGER) AS pmid,
                          CAST(a.position AS INTEGER) AS author_seq,
                          a.lastname, a.initials
                   FROM read_parquet('{src}') a
                   JOIN ver v ON a.pmid = v.pmid AND a.filenb = v.filenb AND a.seq = v.seq)
             TO '{out}' (FORMAT PARQUET)"""
    con.execute(sql.replace("{src}", src).replace("{out}", out))
    n = con.execute(f"SELECT count(*), count(DISTINCT pmid) FROM read_parquet('{out}')").fetchone()
    SFIToolkit.displayln(f"author rows: {n[0]:,} on {n[1]:,} papers")
finally:
    con.close()
end
#delimit ;

import parquet using "`authpq'", clear ;
erase "`authpq'" ;
/* check: author rows per paper against the author count */
preserve ;
    bysort pmid: gen n_rows = _N ;
    bysort pmid: keep if _n == 1 ;
    merge 1:1 pmid using `ver' ;
    tab _merge ;
    keep if _merge == 3 ;
    drop _merge ;
    gen d = n_rows - nb_authrs ;
    display as result "=== author rows minus nb_authrs, by paper" ;
    tab d if inrange(d, -3, 3), missing ;
    count if !inrange(d, -3, 3) ;
restore ;
replace lastname = "" if inlist(lastname, "NA", ".") ;
drop if lastname == "" | strlen(lastname) > 30 ;
preserve ;
    keep lastname ;
    bysort lastname: keep if _n == 1 ;
    gen ln = lastname ;
    supermessoudar ln ;
    tempfile lnmap ;
    save `lnmap' ;
restore ;
merge m:1 lastname using `lnmap' ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
replace initials = "" if initials == "NA" ;
gen ini = lower(initials) ;
keep pmid author_seq ln ini ;
tempfile au ;
save `au' ;

/* -----------------------------------------------------------------------------
   4. The check
   ----------------------------------------------------------------------------- */
use "${data}/build/ackn_links_unchecked.dta", clear ;
joinby project_number using `names' ;
joinby pmid using `au' ;
keep if ln == last ;
gen byte match1 = substr(ini, 1, 1) == f ;
gen byte match2 = ini == strtrim(f + m) ;
/* one row per author, whatever the number of name variants */
gcollapse (max) match1 match2, by(setnb project_number pmid pubyear author_seq) ;
gegen byte max1 = max(match1), by(setnb project_number pmid) ;
gegen byte max2 = max(match2), by(setnb project_number pmid) ;
drop if match1 == 1 & match2 == 0 & max2 == 1 ;
drop if match1 == 0 & match2 == 0 & (max1 == 1 | max2 == 1) ;
bysort pmid project_number setnb: gen n_inv_rule = _N ;
bysort pmid project_number: gen n_old_rule = _N ;
display as result "=== investigator-grant-paper links: matched once, ambiguous, matched once but ambiguous under a per-grant test" ;
count if n_inv_rule == 1 ;
count if n_inv_rule > 1 ;
count if n_inv_rule == 1 & n_old_rule > 1 ;
keep if n_inv_rule == 1 ;
keep setnb project_number pmid pubyear author_seq ;
merge m:1 pmid using `ver', keepusing(nb_authrs) ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;
label var author_seq "Investigator's position in the author list" ;
label var nb_authrs  "Number of authors" ;
label data "Acknowledgment links passing the author check, nih_risk" ;
notes: Built `c(current_date)' by code/build/02_ackn_links.do. ;
sort setnb project_number pmid ;
compress ;
save "${data}/build/ackn_links.dta", replace ;
display as result "=== links passing the author check (investigator, grant, paper): " _N ;

/* share of grant-paper links that pass for at least one investigator, by decade */
preserve ;
    keep project_number pmid ;
    bysort project_number pmid: keep if _n == 1 ;
    gen byte pass = 1 ;
    tempfile passed ;
    save `passed' ;
restore ;
preserve ;
    use "${data}/build/ackn_links_unchecked.dta", clear ;
    merge 1:1 project_number pmid using `passed' ;
    tab _merge ;
    drop if _merge == 2 ;
    drop _merge ;
    replace pass = 0 if pass == . ;
    gen decade = 10 * floor(pubyear / 10) ;
    display as result "=== grant-paper links passing the author check, by decade of publication" ;
    tabstat pass, by(decade) stat(n mean) ;
restore ;

/* -----------------------------------------------------------------------------
   5. Papers per cycle in the cycle's window (span_start to eval_year), with and
      without the check
   ----------------------------------------------------------------------------- */
use setnb project_number cycle span_start eval_year using "${data}/build/cycles.dta", clear ;
joinby setnb project_number using "${data}/build/ackn_links.dta" ;
keep if pubyear >= span_start & pubyear <= eval_year ;
gcollapse (count) n_ackn = pmid, by(setnb project_number cycle) ;
tempfile cnt ;
save `cnt' ;
use setnb project_number cycle span_start eval_year using "${data}/build/cycles.dta", clear ;
joinby project_number using "${data}/build/ackn_links_unchecked.dta" ;
keep if pubyear >= span_start & pubyear <= eval_year ;
gcollapse (count) n_ackn_unchecked = pmid, by(setnb project_number cycle) ;
tempfile cntu ;
save `cntu' ;
use setnb project_number cycle in_sample sep renewed start_act cycle_yr
    using "${data}/build/cycles.dta", clear ;
merge 1:1 setnb project_number cycle using `cnt' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using `cntu' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
replace n_ackn = 0 if n_ackn == . ;
replace n_ackn_unchecked = 0 if n_ackn_unchecked == . ;
label var n_ackn           "Acknowledging papers in the cycle's window, author check passed" ;
label var n_ackn_unchecked "Acknowledging papers in the cycle's window, no author check" ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_paper_counts.dta", replace ;

keep if in_sample & sep != 1 ;
foreach v in n_ackn n_ackn_unchecked {;
    gen nbin_`v' = cond(`v' == 0, 0, cond(`v' == 1, 1, cond(`v' == 2, 2, cond(`v' <= 4, 3, 5)))) ;
} ;
capture label drop nbin ;
label define nbin 0 "0" 1 "1" 2 "2" 3 "3-4" 5 "5+" ;
label values nbin_* nbin ;
display as result "=== acknowledging papers per sample cycle: with the check, and without" ;
tab nbin_n_ackn ;
tab nbin_n_ackn_unchecked ;
display as result "=== with the check, by renewal" ;
tab nbin_n_ackn renewed, col ;
tabstat n_ackn n_ackn_unchecked, by(renewed) stat(mean) ;
display as result "=== with the check, by the award that starts the cycle" ;
tab nbin_n_ackn start_act, col ;
display as result "=== with the check, by decade of the cycle's start" ;
gen decade = 10 * floor(cycle_yr / 10) ;
tab nbin_n_ackn decade, col ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/02_ackn_links.do */
