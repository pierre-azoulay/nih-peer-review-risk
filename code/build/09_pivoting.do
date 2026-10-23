/* =============================================================================
   code/build/09_pivoting.do

   Purpose: Pivoting, the third of the paper's four risk measures, one row per
            cycle: the share of the MeSH descriptor pairs in the cycle's
            acknowledging papers that appear in none of the investigator's
            papers from the five years before the cycle starts, each pair
            weighted by the number of the cycle's papers that carry it. Also
            its split into near and far new pairs (Appendix Tables D1 to D3,
            Appendix Figure D1): a new pair is near when both of its
            descriptors appear in the baseline papers, far otherwise; the two
            add up to the main measure.
            - current papers: the cycle's acknowledging papers
              (code/build/03_cycle_papers.do; English original research,
              author check passed);
            - baseline papers: the investigator's Author-ity papers, English original
              research, published from cycle_yr - 5 to cycle_yr - 1;
            - pairs: unordered pairs of distinct descriptors on a paper, every
              descriptor counted (check tags included, qualifiers ignored), from
              PubMed 2025, so both windows share one vocabulary.
            Defined when the cycle has a paper with a pair and the baseline a paper
            with a descriptor. The pair computation runs in DuckDB.

   Input:
     - ${data}/build/cycles.dta         (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta   (code/build/03_cycle_papers.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity papers
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_meshterms_2025.dta   PubMed 2025

   Output:
     - ${data}/build/risk_pivoting.dta   one row per setnb x project_number x cycle:
                                         frac_setnb_pair, its near and far parts,
                                         n_base_mesh, n_cur_mesh

   Note: DuckDB runs with 16 threads and spills to a folder in the system's
         temporary directory.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/09_pivoting.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles, with a numeric key
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr author_id using "${data}/build/cycles.dta", clear ;
sort setnb project_number cycle ;
gen long cid = _n ;
tempfile keys ;
save `keys' ;

/* -----------------------------------------------------------------------------
   2. Current papers: the cycle's acknowledging papers
   ----------------------------------------------------------------------------- */
use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
merge m:1 setnb project_number cycle using `keys', keepusing(cid) ;
tab _merge ;
assert _merge != 1 ;
keep if _merge == 3 ;
keep cid pmid ;
gisid cid pmid ;
tempfile cur ;
save `cur' ;

/* -----------------------------------------------------------------------------
   3. Baseline papers: the investigator's papers in the five years before the cycle
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

use author_id using `keys', clear ;
drop if author_id == "" ;
bysort author_id: keep if _n == 1 ;
tempfile invid ;
save `invid' ;
use author_id pmid using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `invid' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
bysort author_id pmid: keep if _n == 1 ;
merge m:1 pmid using `pm' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
joinby author_id using `keys' ;
keep if pubyear >= cycle_yr - 5 & pubyear <= cycle_yr - 1 ;
keep cid pmid ;
gisid cid pmid ;
display as result "=== baseline papers (cycle x paper)" ;
count ;
tempfile base ;
save `base' ;

/* -----------------------------------------------------------------------------
   4. MeSH descriptors of every current or baseline paper, one row per descriptor
   ----------------------------------------------------------------------------- */
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
display as result "=== paper x descriptor rows for the current and baseline papers" ;
count ;
tempfile mesh ;
save `mesh' ;

/* -----------------------------------------------------------------------------
   5. Pairs and shares, in DuckDB
   ----------------------------------------------------------------------------- */
global piv_cur  "`cur'" ;
global piv_base "`base'" ;
global piv_mesh "`mesh'" ;
tempfile res ;
global piv_res  "`res'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

cur  = pd.read_stata(Macro.getGlobal("piv_cur"))
base = pd.read_stata(Macro.getGlobal("piv_base"))
mesh = pd.read_stata(Macro.getGlobal("piv_mesh"), convert_categoricals=False)
spill = os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_pivoting")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=16")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    con.register("cur_df", cur)
    con.register("base_df", base)
    con.register("mesh_df", mesh)
    con.execute("CREATE TEMP TABLE cur  AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM cur_df")
    con.execute("CREATE TEMP TABLE base AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM base_df")
    con.execute("CREATE TEMP TABLE mesh AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.unregister("cur_df"); con.unregister("base_df"); con.unregister("mesh_df")
    # pairs of distinct descriptors on a paper, each once
    con.execute("""CREATE TEMP TABLE pp AS
        SELECT a.pmid, a.d AS d1, b.d AS d2 FROM mesh a JOIN mesh b ON a.pmid = b.pmid AND a.d < b.d""")
    # the cycle's pairs, weighted by the number of its papers carrying each
    con.execute("""CREATE TEMP TABLE cp AS
        SELECT c.cid, p.d1, p.d2, count(*) AS freq FROM cur c JOIN pp p USING (pmid) GROUP BY ALL""")
    # the baseline's descriptors, and those of its pairs that the cycle also has
    con.execute("""CREATE TEMP TABLE bd AS
        SELECT DISTINCT b.cid, m.d FROM base b JOIN mesh m USING (pmid)""")
    con.execute("""CREATE TEMP TABLE bp AS
        SELECT DISTINCT b.cid, p.d1, p.d2 FROM base b JOIN pp p USING (pmid)
        SEMI JOIN cp ON cp.cid = b.cid AND cp.d1 = p.d1 AND cp.d2 = p.d2""")
    res = con.execute("""
        WITH sh AS (
            SELECT cp.cid, CAST(sum(cp.freq) AS DOUBLE) AS w_all,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE) AS w_new,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE bp.cid IS NULL AND b1.d IS NOT NULL AND b2.d IS NOT NULL), 0) AS DOUBLE) AS w_near
            FROM cp
            LEFT JOIN bp ON bp.cid = cp.cid AND bp.d1 = cp.d1 AND bp.d2 = cp.d2
            LEFT JOIN bd b1 ON b1.cid = cp.cid AND b1.d = cp.d1
            LEFT JOIN bd b2 ON b2.cid = cp.cid AND b2.d = cp.d2
            GROUP BY cp.cid),
        nb AS (SELECT cid, count(DISTINCT pmid) AS n_base_mesh FROM base SEMI JOIN mesh USING (pmid) GROUP BY cid),
        nc AS (SELECT cid, count(DISTINCT pmid) AS n_cur_mesh  FROM cur  SEMI JOIN mesh USING (pmid) GROUP BY cid)
        SELECT CAST(coalesce(sh.cid, nb.cid, nc.cid) AS INTEGER) AS cid, sh.w_all, sh.w_new, sh.w_near,
               CAST(coalesce(nb.n_base_mesh, 0) AS INTEGER) AS n_base_mesh,
               CAST(coalesce(nc.n_cur_mesh, 0) AS INTEGER) AS n_cur_mesh
        FROM sh FULL JOIN nb ON nb.cid = sh.cid FULL JOIN nc ON nc.cid = coalesce(sh.cid, nb.cid)
        ORDER BY cid""").df()
    n_pp = con.execute("SELECT count(*) FROM pp").fetchone()[0]
    n_cp = con.execute("SELECT count(*) FROM cp").fetchone()[0]
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("pairs on the papers: {:,}; cycle x pair rows: {:,}; cycles with a value: {:,}".format(n_pp, n_cp, len(res)))
res.to_stata(Macro.getGlobal("piv_res"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   6. The measures, saved
   ----------------------------------------------------------------------------- */
use `res', clear ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
tab _merge ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
gen byte piv_ok = n_base_mesh > 0 & w_all > 0 & w_all < . ;
gen double frac_setnb_pair      = w_new / w_all  if piv_ok ;
gen double frac_setnb_pair_near = w_near / w_all if piv_ok ;
gen double frac_setnb_pair_far  = (w_new - w_near) / w_all if piv_ok ;
assert abs(frac_setnb_pair_near + frac_setnb_pair_far - frac_setnb_pair) < 1e-9 if piv_ok ;
drop if !piv_ok ;
label var frac_setnb_pair      "Pivoting: share of the cycle's MeSH pairs new to the investigator (5-yr baseline)" ;
label var frac_setnb_pair_near "New pairs whose two descriptors both appear in the baseline" ;
label var frac_setnb_pair_far  "New pairs with a descriptor absent from the baseline" ;
label var n_base_mesh          "Baseline papers with MeSH" ;
label var n_cur_mesh           "Cycle's acknowledging papers with MeSH" ;
keep setnb project_number cycle frac_setnb_pair frac_setnb_pair_near frac_setnb_pair_far
     n_base_mesh n_cur_mesh ;
order setnb project_number cycle frac_setnb_pair frac_setnb_pair_near frac_setnb_pair_far
      n_base_mesh n_cur_mesh ;
label data "Pivoting, nih_risk" ;
notes: Built `c(current_date)' by code/build/09_pivoting.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_pivoting.dta", replace ;

/* -----------------------------------------------------------------------------
   7. First look: sample cycles
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta",
    keepusing(in_sample sep renewed cycle_yr) ;
assert _merge != 1 ;
keep if _merge == 3 & in_sample & sep != 1 ;
drop _merge ;
display as result "=== sample cycles with pivoting defined" ;
count ;
display as result "=== pivoting and its split, by renewal" ;
tabstat frac_setnb_pair frac_setnb_pair_near frac_setnb_pair_far n_base_mesh n_cur_mesh,
    by(renewed) stat(mean p50 n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/09_pivoting.do */
