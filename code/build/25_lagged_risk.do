/* =============================================================================
   code/build/25_lagged_risk.do

   Purpose: The lagged risk, for Appendix Tables A2 (code/analysis/21_table_A2.do)
            and G2 (code/analysis/32_table_G2.do), one row per analysis-sample
            cycle whose cycle number is known: for each measure, lag_<m>, the
            risk measured before the cycle began, and n_lag_<m>, the papers it
            rests on.
            - first cycles (cycle_nb == 1): a "cycle 0" measure on the
              investigator's Author-ity papers, English original research, any
              author position, published in s - 5 to s - 1, s the grant's first
              year (cycle_yr of cycle 1); most have nothing to do with the grant:
                tails       max minus min citation percentile, at least two;
                disruption  highest disruption percentile, at least one;
                pivoting    share of the papers' MeSH pairs (weighted by papers)
                            absent from the investigator's papers of s - 10 to
                            s - 6, defined when both windows have MeSH;
                standing out share of the papers' MeSH pairs carried by no
                            other funded application in the grant's institute
                            x study section in year s, the investigator's own
                            applications excluded, within the MTI vocabulary;
                            at least 20 other tagged applications and a pair
                            weight above 5, as the main measure. The pools are
                            those of code/build/11_abstract_tags.do, built for
                            evaluation years: a start year whose cell is not
                            among them has no value (32% of first cycles).
              Each follows its builder (code/build/07_tails.do,
              08_disruption.do, 09_pivoting.do, 12_standing_out.do).
            - later cycles (cycle_nb >= 2): the stored measure of the grant's
              previous cycle (cycle - 1 of the same investigator and grant),
              and its paper count (standing out: the previous cycle's papers
              with MeSH, n_cur_mesh, its builder storing no count).
            - grants first observed at a renewal (cycle_nb missing) get no lag.

   Input:
     - ${data}/build/cycles.dta             (code/build/01_cycles.do)
     - ${data}/build/paper_attributes.dta   (code/build/05_paper_attributes.do)
     - ${data}/build/risk_tails.dta (code/build/07_tails.do),
       risk_disruption.dta (08_disruption.do), risk_pivoting.dta
       (09_pivoting.do), risk_standout.dta (12_standing_out.do)
     - ${data}/build/abstract_pool.dta, abstract_tags.dta, mti_vocab.dta
                                            (code/build/11_abstract_tags.do)
     - ${data}/output/nih_risk_analysis.dta (cycle_nb)
                                            (code/build/23_analysis_file.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity: the
       authors of each PubMed paper
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_meshterms_2025.dta   PubMed 2025:
       year, type, language and MeSH descriptors of each paper
     - ${input}/cgaf_nih_risk.dta   investigators of every application

   Output:
     - ${data}/build/risk_lagged.dta   one row per setnb x project_number x cycle

   Note: DuckDB with 6 threads and a 10 GB limit; a few minutes.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set processors 4 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/25_lagged_risk.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles: the analysis sample with a known cycle number
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_nb using "${data}/output/nih_risk_analysis.dta", clear ;
drop if cycle_nb == . ;
assert cycle_nb == cycle ;
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta",
    keepusing(cycle_yr author_id ic irg_code am_link) ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
/* ic serves only the pool of the grant's start year (section 4): the institute in
   force that year, AM before the 1986 split for a grant linked across it (the
   cycle file's ic is the one of the evaluation year) */
replace ic = "AM" if am_link == 1 & cycle_yr <= 1985 ;
drop am_link ;
sort setnb project_number cycle ;
gen long cid = _n ;
tempfile keys ;
save `keys' ;
display as result "=== cycles: first and later" ;
tab cycle_nb if cycle_nb <= 2, missing ;

/* -----------------------------------------------------------------------------
   2. Later cycles: the previous cycle's stored measures
   ----------------------------------------------------------------------------- */
use cid setnb project_number cycle using `keys' if cycle >= 2, clear ;
replace cycle = cycle - 1 ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_tails.dta", keepusing(spread_minmax_ackn n_tails) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_disruption.dta", keepusing(di1nok_ackn_maxpctl n_disr) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_pivoting.dta", keepusing(frac_setnb_pair n_cur_mesh) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_standout.dta", keepusing(frac_icirg_pair) ;
drop if _merge == 2 ;
drop _merge ;
gen double lag_tails = spread_minmax_ackn ;
gen double lag_disr  = di1nok_ackn_maxpctl ;
gen double lag_pivot = frac_setnb_pair ;
gen double lag_so    = frac_icirg_pair ;
gen int n_lag_tails = n_tails ;
gen int n_lag_disr  = n_disr ;
gen int n_lag_pivot = n_cur_mesh ;
gen int n_lag_so    = n_cur_mesh ;
keep cid lag_* n_lag_* ;
tempfile later ;
save `later' ;

/* -----------------------------------------------------------------------------
   3. First cycles: the cycle-0 papers (s - 5 to s - 1) and the pivoting
      baseline of cycle 0 (s - 10 to s - 6), as code/build/09_pivoting.do,
      section 3
   ----------------------------------------------------------------------------- */
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
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using `lng' ;
drop if _merge == 2 ;
drop _merge ;
keep if orgnl == 1 & eng == 1 ;
keep pmid pubyear ;
tempfile pm ;
save `pm' ;

use cid cycle author_id cycle_yr using `keys' if cycle == 1, clear ;
drop if author_id == "" ;
tempfile first ;
save `first' ;
keep author_id ;
bysort author_id: keep if _n == 1 ;
tempfile invid ;
save `invid' ;
use author_id pmid using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `invid' ;
keep if _merge == 3 ;
drop _merge ;
bysort author_id pmid: keep if _n == 1 ;
merge m:1 pmid using `pm' ;
keep if _merge == 3 ;
drop _merge ;
joinby author_id using `first' ;
gen byte win = cond(pubyear >= cycle_yr - 5 & pubyear <= cycle_yr - 1, 1,
               cond(pubyear >= cycle_yr - 10 & pubyear <= cycle_yr - 6, 2, 0)) ;
keep if win > 0 ;
keep cid pmid win ;
gisid cid pmid ;
preserve ;
keep if win == 1 ;
drop win ;
tempfile cur ;
save `cur' ;
restore ;
keep if win == 2 ;
drop win ;
tempfile base ;
save `base' ;

/* tails and disruption of cycle 0 */
use `cur', clear ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5_pctl di1_nok_pctl) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
gcollapse (count) n_lag_tails = cite5_pctl n_lag_disr = di1_nok_pctl
          (max) c5max = cite5_pctl dimax = di1_nok_pctl (min) c5min = cite5_pctl, by(cid) ;
gen double lag_tails = (c5max - c5min) / 100 if n_lag_tails >= 2 ;
gen double lag_disr  = dimax / 100 if n_lag_disr >= 1 ;
keep cid lag_tails lag_disr n_lag_tails n_lag_disr ;
tempfile td ;
save `td' ;

/* MeSH of the cycle-0 and baseline papers */
use pmid using `cur', clear ;
append using `base', keep(pmid) ;
bysort pmid: keep if _n == 1 ;
tempfile need ;
save `need' ;
use pmid dscrptr_ui using "${pubmed_root}/pubmed/overall_meshterms_2025.dta", clear ;
merge m:1 pmid using `need' ;
keep if _merge == 3 ;
drop _merge ;
bysort pmid dscrptr_ui: keep if _n == 1 ;
tempfile mesh ;
save `mesh' ;

/* standing out: the cell of the grant's start year, and the investigators'
   own pool applications, as code/build/12_standing_out.do, sections 1 and 2 */
use cid cycle setnb ic irg_code cycle_yr using `keys' if cycle == 1 & irg_code != "", clear ;
rename cycle_yr year ;
tempfile cyc ;
save `cyc' ;
use app_id ic irg_code year has_text tag_src using "${data}/build/abstract_pool.dta", clear ;
tempfile pool ;
save `pool' ;
keep app_id ;
tempfile poolid ;
save `poolid' ;
use setnb using `cyc', clear ;
bysort setnb: keep if _n == 1 ;
tempfile setnbs ;
save `setnbs' ;
use app_id setnb using "${input}/cgaf_nih_risk.dta", clear ;
drop if app_id == . | setnb == "" ;
bysort app_id setnb: keep if _n == 1 ;
merge m:1 app_id using `poolid' ;
keep if _merge == 3 ;
drop _merge ;
merge m:1 setnb using `setnbs' ;
keep if _merge == 3 ;
drop _merge ;
tempfile own ;
save `own' ;

/* -----------------------------------------------------------------------------
   4. Pivoting and standing out of cycle 0, in DuckDB
   ----------------------------------------------------------------------------- */
tempfile pres sres ;
global l_cur   "`cur'" ;
global l_base  "`base'" ;
global l_mesh  "`mesh'" ;
global l_cyc   "`cyc'" ;
global l_pool  "`pool'" ;
global l_own   "`own'" ;
global l_tags  "${data}/build/abstract_tags.dta" ;
global l_vocab "${data}/build/mti_vocab.dta" ;
global l_pres  "`pres'" ;
global l_sres  "`sres'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
frames = {
    "cur":   pd.read_stata(g("l_cur")),
    "base":  pd.read_stata(g("l_base")),
    "mesh":  pd.read_stata(g("l_mesh"), convert_categoricals=False),
    "cyc":   pd.read_stata(g("l_cyc")),
    "pool":  pd.read_stata(g("l_pool"), convert_categoricals=False),
    "own":   pd.read_stata(g("l_own")),
    "tags":  pd.read_stata(g("l_tags"), convert_categoricals=False),
    "vocab": pd.read_stata(g("l_vocab"), convert_categoricals=False),
}
spill = g("nr_spill") or os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_lagged")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=6")
    con.execute("SET memory_limit='10GB'")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    for k, df in frames.items():
        con.register(k + "_df", df)
    con.execute("CREATE TEMP TABLE cur  AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM cur_df")
    con.execute("CREATE TEMP TABLE base AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM base_df")
    con.execute("CREATE TEMP TABLE mesh AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.execute("CREATE TEMP TABLE cyc  AS SELECT CAST(cid AS INTEGER) cid, setnb, ic, irg_code, CAST(year AS INTEGER) yr FROM cyc_df")
    con.execute("""CREATE TEMP TABLE pool AS SELECT CAST(app_id AS BIGINT) app_id, ic, irg_code, CAST(year AS INTEGER) yr,
                   CAST(has_text AS INTEGER) has_text, CAST(tag_src AS INTEGER) tag_src FROM pool_df""")
    con.execute("CREATE TEMP TABLE own  AS SELECT DISTINCT CAST(app_id AS BIGINT) app_id, setnb FROM own_df")
    con.execute("CREATE TEMP TABLE vocab AS SELECT CAST(dscrptr_ui AS INTEGER) d FROM vocab_df")
    con.execute("CREATE TEMP TABLE tags AS SELECT CAST(app_id AS BIGINT) app_id, CAST(dscrptr_ui AS INTEGER) d FROM tags_df SEMI JOIN vocab ON vocab.d = CAST(tags_df.dscrptr_ui AS INTEGER)")
    for k in frames:
        con.unregister(k + "_df")
    del frames

    # ---- pivoting of cycle 0 (09_pivoting.do), against s - 10 to s - 6
    con.execute("CREATE TEMP TABLE pp AS SELECT a.pmid, a.d AS d1, b.d AS d2 FROM mesh a JOIN mesh b ON a.pmid = b.pmid AND a.d < b.d")
    con.execute("CREATE TEMP TABLE cp AS SELECT c.cid, p.d1, p.d2, count(*) AS freq FROM cur c JOIN pp p USING (pmid) GROUP BY ALL")
    con.execute("""CREATE TEMP TABLE bp AS
        SELECT DISTINCT b.cid, p.d1, p.d2 FROM base b JOIN pp p USING (pmid)
        SEMI JOIN cp ON cp.cid = b.cid AND cp.d1 = p.d1 AND cp.d2 = p.d2""")
    pres = con.execute("""
        WITH sh AS (
            SELECT cp.cid, CAST(sum(cp.freq) AS DOUBLE) AS w_all,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE) AS w_new
            FROM cp LEFT JOIN bp ON bp.cid = cp.cid AND bp.d1 = cp.d1 AND bp.d2 = cp.d2
            GROUP BY cp.cid),
        np AS (SELECT cid, count(DISTINCT pmid) AS n_piv FROM cur SEMI JOIN pp USING (pmid) GROUP BY cid),
        nb AS (SELECT cid, count(DISTINCT pmid) AS n_base FROM base SEMI JOIN mesh USING (pmid) GROUP BY cid)
        SELECT CAST(sh.cid AS INTEGER) cid, sh.w_all, sh.w_new, CAST(np.n_piv AS INTEGER) n_piv,
               CAST(coalesce(nb.n_base, 0) AS INTEGER) n_base
        FROM sh JOIN np ON np.cid = sh.cid LEFT JOIN nb ON nb.cid = sh.cid ORDER BY cid""").df()
    con.execute("DROP TABLE pp"); con.execute("DROP TABLE cp"); con.execute("DROP TABLE bp")

    # ---- standing out of cycle 0 (12_standing_out.do), pool of the start year
    con.execute("CREATE TEMP TABLE scur AS SELECT c.* FROM cur c SEMI JOIN cyc USING (cid)")
    con.execute("CREATE TEMP TABLE meshv AS SELECT m.pmid, m.d FROM mesh m SEMI JOIN vocab ON vocab.d = m.d")
    con.execute("""CREATE TEMP TABLE sp AS
        SELECT c.cid, c.pmid, a.d AS d1, b.d AS d2
        FROM scur c JOIN meshv a ON a.pmid = c.pmid JOIN meshv b ON b.pmid = c.pmid AND a.d < b.d""")
    con.execute("CREATE TEMP TABLE scp AS SELECT cid, d1, d2, count(*) AS freq FROM sp GROUP BY ALL")
    con.execute("""CREATE TEMP TABLE need AS
        SELECT DISTINCT y.ic, y.irg_code, y.yr, s.d1, s.d2 FROM scp s JOIN cyc y USING (cid)""")
    con.execute("""CREATE TEMP TABLE ap AS
        SELECT p.app_id, p.ic, p.irg_code, p.yr, a.d AS d1, b.d AS d2
        FROM pool p JOIN tags a ON a.app_id = p.app_id JOIN tags b ON b.app_id = p.app_id AND a.d < b.d
        SEMI JOIN need n ON n.ic = p.ic AND n.irg_code = p.irg_code AND n.yr = p.yr AND n.d1 = a.d AND n.d2 = b.d""")
    con.execute("CREATE TEMP TABLE cnt AS SELECT ic, irg_code, yr, d1, d2, count(*) AS n FROM ap GROUP BY ALL")
    con.execute("""CREATE TEMP TABLE owncnt AS
        SELECT y.cid, ap.d1, ap.d2, count(*) AS n_own
        FROM cyc y JOIN own o ON o.setnb = y.setnb
        JOIN ap ON ap.app_id = o.app_id AND ap.ic = y.ic AND ap.irg_code = y.irg_code AND ap.yr = y.yr
        GROUP BY ALL""")
    con.execute("""CREATE TEMP TABLE psize AS
        SELECT y.cid, count(*) FILTER (WHERE p.tag_src > 0) AS nb_abs
        FROM cyc y JOIN pool p ON p.ic = y.ic AND p.irg_code = y.irg_code AND p.yr = y.yr
        WHERE NOT EXISTS (SELECT 1 FROM own o WHERE o.app_id = p.app_id AND o.setnb = y.setnb)
        GROUP BY y.cid""")
    sres = con.execute("""
        WITH w AS (
            SELECT s.cid, CAST(sum(s.freq) AS DOUBLE) AS w_all,
                   CAST(coalesce(sum(s.freq) FILTER (WHERE coalesce(c.n, 0) - coalesce(o.n_own, 0) = 0), 0) AS DOUBLE) AS w_uniq
            FROM scp s JOIN cyc y ON y.cid = s.cid
            LEFT JOIN cnt c ON c.ic = y.ic AND c.irg_code = y.irg_code AND c.yr = y.yr AND c.d1 = s.d1 AND c.d2 = s.d2
            LEFT JOIN owncnt o ON o.cid = s.cid AND o.d1 = s.d1 AND o.d2 = s.d2
            GROUP BY s.cid),
        np AS (SELECT cid, count(DISTINCT pmid) AS n_so FROM sp GROUP BY cid)
        SELECT CAST(w.cid AS INTEGER) cid, w.w_all, w.w_uniq, CAST(np.n_so AS INTEGER) n_so,
               CAST(coalesce(s.nb_abs, 0) AS INTEGER) nb_abs
        FROM w JOIN np ON np.cid = w.cid LEFT JOIN psize s ON s.cid = w.cid ORDER BY cid""").df()
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("cycle-0 pivoting rows: {:,}; standing-out rows: {:,}".format(len(pres), len(sres)))
pres.to_stata(g("l_pres"), write_index=False)
sres.to_stata(g("l_sres"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   5. Assemble the first cycles, append the later ones, save
   ----------------------------------------------------------------------------- */
use `pres', clear ;
gen double lag_pivot = w_new / w_all if n_base > 0 & w_all > 0 & w_all < . ;
gen int n_lag_pivot = n_piv ;
keep cid lag_pivot n_lag_pivot ;
tempfile p0 ;
save `p0' ;
use `sres', clear ;
gen double lag_so = w_uniq / w_all if nb_abs >= 20 & w_all > 5 ;
gen int n_lag_so = n_so ;
keep cid lag_so n_lag_so ;
tempfile s0 ;
save `s0' ;

use cid cycle using `keys' if cycle == 1, clear ;
drop cycle ;
foreach f in td p0 s0 {;
    merge 1:1 cid using ``f'' ;
    assert _merge != 2 ;
    drop _merge ;
} ;
append using `later' ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle cycle_yr) ;
assert _merge != 1 ;
drop _merge ;
foreach m in tails disr pivot so {;
    replace n_lag_`m' = 0 if n_lag_`m' == . ;
} ;
gen byte lag_type = cond(cycle == 1, 0, 1) ;
label define lagtype 0 "cycle 0 (pre-grant record)" 1 "previous cycle", replace ;
label values lag_type lagtype ;
label var lag_tails   "Lagged tails (0-1): cycle 0 for first cycles, previous cycle otherwise" ;
label var lag_disr    "Lagged disruption (0-1)" ;
label var lag_pivot   "Lagged pivoting" ;
label var lag_so      "Lagged standing out" ;
label var n_lag_tails "Papers behind lag_tails" ;
label var n_lag_disr  "Papers behind lag_disr" ;
label var n_lag_pivot "Papers behind lag_pivot" ;
label var n_lag_so    "Papers behind lag_so" ;
label var lag_type    "Source of the lagged measures" ;
keep setnb project_number cycle lag_type lag_tails lag_disr lag_pivot lag_so n_lag_tails n_lag_disr n_lag_pivot n_lag_so ;
order setnb project_number cycle lag_type ;
label data "Lagged risk, nih_risk" ;
notes: Built `c(current_date)' by code/build/25_lagged_risk.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_lagged.dta", replace ;

/* -----------------------------------------------------------------------------
   6. First look: coverage by source and by start period of the grant
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using `keys', keepusing(cycle_yr) ;
drop _merge ;
display as result "=== lag defined, by source" ;
foreach m in tails disr pivot so {;
    gen byte has_`m' = !missing(lag_`m') ;
} ;
tabstat has_tails has_disr has_pivot has_so, by(lag_type) stat(mean n) ;
gen int period = floor(cycle_yr / 5) * 5 ;
display as result "=== cycle 0: lag defined by start period of the grant" ;
tabstat has_tails has_disr has_pivot has_so if lag_type == 0, by(period) stat(mean) ;
display as result "=== papers behind the lag, by source (means)" ;
tabstat n_lag_tails n_lag_disr n_lag_pivot n_lag_so, by(lag_type) stat(mean p50) ;
display as result "=== the lags (0-1 scale), by source" ;
tabstat lag_tails lag_disr lag_pivot lag_so, by(lag_type) stat(mean sd n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/25_lagged_risk.do */
