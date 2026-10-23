/* =============================================================================
   code/build/16_patents.do

   Purpose: patent outcomes of each cycle's acknowledging papers, for Tables 1e
            and 3. A citation is a (paper, patent) pair in Marx's Reliance on
            Science (2026 release: US granted utility patents), with match
            confidence 6 or more, front page and text, applicant and examiner
            citations alike: examiner citations are recorded only in recent
            years, so dropping them could not be done consistently over the
            period. No time window.
              pat_cites     citations from all patents (pairs)
              pharma_cites  citations from drug- and device-related patents:
                            the patents of the Russet Book (the NBER and FDA
                            Orange Books, Sampat's NDA list, Frakes and
                            Wasserman's patents on biologics, the USPTO term
                            extensions)
              kpss_value    the private value of the distinct patents citing
                            the cycle's papers (Kogan, Papanikolaou, Seru and
                            Stoffman; patents of listed firms only, granted
                            through 2023), in millions of 2023 dollars:
                            xi_nominal over the monthly CPI-U of the issue
                            month relative to its 2023 maximum, issue years
                            before 1950 dropped. A patent citing several of
                            the cycle's papers counts once.

   Input:
     - ${data}/build/cycle_papers.dta   (code/build/03_cycle_papers.do)
     - ${pubmed_root}/reliance_on_science/pmid2patent_2026.dta   paper-patent
       citation pairs, Reliance on Science
     - ${pubmed_root}/russet_book/russet_patents.dta   drug- and device-related
       patents (the Russet Book)
     - ${pubmed_root}/reliance_on_science/kpss/KPSS_2023.csv   KPSS patent values
     - ${cpi} (data/cpiaucsl_fred.csv)   CPI-U, monthly, FRED series CPIAUCSL,
       downloaded on 9 October 2026, through August 2026

   Output:
     - ${data}/build/cycle_patents.dta, one row per cycle with an
       acknowledging paper: pat_cites, pharma_cites, kpss_value, and
       pat_any, pharma_any, kpss_any
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/16_patents.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. KPSS values in 2023 dollars
   ----------------------------------------------------------------------------- */
/* CPIAUCSL, monthly: the copy of FRED's series that ships with the package
   (${cpi}), so that every run gives the same deflator. The KPSS csv is large:
   read by pandas, not import delimited. */
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
count if year < 1950 ;
display as text "KPSS patents issued before 1950 (dropped): " r(N) ;
drop if year < 1950 ;
merge m:1 year month using `cpi' ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;
gen double kpss = xi_nominal / inflation_adj ;
keep patent kpss ;
gisid patent ;
summarize kpss, detail ;
tempfile kpss ;
save `kpss' ;

/* -----------------------------------------------------------------------------
   2. Citations to the acknowledging papers
   ----------------------------------------------------------------------------- */
use patent using "${pubmed_root}/russet_book/russet_patents.dta" if !missing(patent), clear ;
gisid patent ;
gen byte pharma = 1 ;
tempfile pharma ;
save `pharma' ;

use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
drop ackn ;
gisid setnb project_number cycle pmid ;
tempfile ap ;
save `ap' ;
keep pmid ;
gduplicates drop ;
tempfile apids ;
save `apids' ;

use pmid patent cnfdnc_score using "${pubmed_root}/reliance_on_science/pmid2patent_2026.dta", clear ;
count ;
display as text "pairs, all papers: " r(N) ;
merge m:1 pmid using `apids' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
display as text "pairs on acknowledging papers, by confidence (6 or more kept):" ;
tab cnfdnc_score ;
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
quietly gdistinct patent ;
display as text "distinct citing patents: " r(ndistinct) ;
quietly gdistinct patent if !missing(kpss) ;
display as text "  with a KPSS value: " r(ndistinct) ;
quietly gdistinct patent if pharma ;
display as text "  in the Russet Book: " r(ndistinct) ;
tempfile pairs ;
save `pairs' ;

/* cycle x paper x patent */
use `ap', clear ;
joinby pmid using `pairs' ;
gen byte one = 1 ;
preserve ;
gcollapse (sum) pat_cites = one pharma_cites = pharma, by(setnb project_number cycle) ;
tempfile cites ;
save `cites' ;
restore ;
/* KPSS: each distinct citing patent once per cycle */
keep setnb project_number cycle patent kpss ;
bysort setnb project_number cycle patent: keep if _n == 1 ;
gcollapse (sum) kpss_value = kpss, by(setnb project_number cycle) ;
tempfile value ;
save `value' ;

/* every cycle with an acknowledging paper; zero where no patent cites one */
use `ap', clear ;
bysort setnb project_number cycle: keep if _n == 1 ;
keep setnb project_number cycle ;
merge 1:1 setnb project_number cycle using `cites' ;
assert _merge != 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using `value' ;
assert _merge != 2 ;
drop _merge ;
foreach v in pat_cites pharma_cites kpss_value {;
    replace `v' = 0 if missing(`v') ;
} ;
gen byte pat_any    = (pat_cites > 0) ;
gen byte pharma_any = (pharma_cites > 0) ;
gen byte kpss_any   = (kpss_value > 0) ;
label variable pat_cites    "Patent citations to the cycle's acknowledging papers" ;
label variable pharma_cites "Citations from drug- and device-related patents (Russet Book)" ;
label variable kpss_value   "KPSS value of the distinct citing patents, 2023 dollars (millions)" ;
label variable pat_any      "Some acknowledging paper is cited by a patent" ;
label variable pharma_any   "Some acknowledging paper is cited by a Russet Book patent" ;
label variable kpss_any     "Some acknowledging paper is cited by a patent with a KPSS value" ;
summarize pat_cites pharma_cites kpss_value pat_any pharma_any kpss_any, detail ;

sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_patents.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
