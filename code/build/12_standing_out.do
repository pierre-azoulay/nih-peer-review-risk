/* =============================================================================
   code/build/12_standing_out.do

   Purpose: Standing out, the fourth of the paper's four risk measures (and the
            subject of Appendix E, Tables E1 to E4), one row per cycle: the
            share of the MeSH descriptor pairs in the cycle's acknowledging
            papers (each pair weighted by the number of papers carrying it)
            that no other funded application in the cycle's institute x study
            section x evaluation year carries in its MTI tags. The rules:
            - the pool and its tags come from code/build/11_abstract_tags.do (MTI
              tags, or those of an identical abstract);
            - the investigator's own applications are excluded from the pool by
              application ID: every application on which the investigator is a
              PI, so that the pool never holds the investigator's own
              abstracts, the renewal application's among them;
            - both sides use the descriptors common to the MTI tag vocabulary and
              PubMed 2025 (mti_vocab.dta), so that a pair cannot be unique merely
              because one of its descriptors did not exist when MTI tagged;
            - the pool holds at least 20 other tagged applications, and the
              cycle's pair weight is above 5.
            Computed for the analysis sample only (in_sample, sep != 1), whose
            pools MTI tagged; pool_complete reports the share of the pool's
            applications with text that have tags.

   Input:
     - ${data}/build/cycles.dta          (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta    (code/build/03_cycle_papers.do)
     - ${data}/build/abstract_pool.dta, abstract_tags.dta, mti_vocab.dta
                                         (code/build/11_abstract_tags.do)
     - ${pubmed_root}/pubmed/overall_meshterms_2025.dta   MeSH of PubMed 2025
     - ${input}/cgaf_nih_risk.dta   investigators of every application

   Output:
     - ${data}/build/risk_standout.dta   one row per setnb x project_number x cycle:
                                         frac_icirg_pair and the pool's size and
                                         makeup

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
log using "logs/12_standing_out.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles and their papers
   ----------------------------------------------------------------------------- */
/* analysis-sample cycles only: MTI never tagged the pools of special emphasis panels
   or of cycles outside the sample, so a value there would rest on a thin pool */
use setnb project_number cycle ic irg_code eval_year in_sample sep using "${data}/build/cycles.dta", clear ;
sort setnb project_number cycle ;
gen long cid = _n ;
gen byte so_cycle = in_sample & sep != 1 & irg_code != "" ;
tempfile keys ;
save `keys' ;
keep if so_cycle ;
rename eval_year year ;
keep cid setnb ic irg_code year ;
tempfile cyc ;
save `cyc' ;

use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
merge m:1 setnb project_number cycle using `keys', keepusing(cid so_cycle) ;
assert _merge != 1 ;
keep if _merge == 3 & so_cycle ;
keep cid pmid ;
gisid cid pmid ;
tempfile cur ;
save `cur' ;

keep pmid ;
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

/* -----------------------------------------------------------------------------
   2. The pools: tagged applications, and the investigators of each
   ----------------------------------------------------------------------------- */
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
display as result "=== pool applications held by an investigator of the cycle file (application x investigator)" ;
count ;
tempfile own ;
save `own' ;

/* -----------------------------------------------------------------------------
   3. Unique pairs, in DuckDB
   ----------------------------------------------------------------------------- */
tempfile res ;
global so_cyc   "`cyc'" ;
global so_cur   "`cur'" ;
global so_mesh  "`mesh'" ;
global so_pool  "`pool'" ;
global so_own   "`own'" ;
global so_tags  "${data}/build/abstract_tags.dta" ;
global so_vocab "${data}/build/mti_vocab.dta" ;
global so_res   "`res'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
frames = {
    "cyc":   pd.read_stata(g("so_cyc")),
    "cur":   pd.read_stata(g("so_cur")),
    "mesh":  pd.read_stata(g("so_mesh"), convert_categoricals=False),
    "pool":  pd.read_stata(g("so_pool"), convert_categoricals=False),
    "own":   pd.read_stata(g("so_own")),
    "tags":  pd.read_stata(g("so_tags"), convert_categoricals=False),
    "vocab": pd.read_stata(g("so_vocab"), convert_categoricals=False),
}
spill = os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_standout")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=16")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    for k, df in frames.items():
        con.register(k + "_df", df)
    con.execute("CREATE TEMP TABLE cyc AS SELECT CAST(cid AS INTEGER) cid, setnb, ic, irg_code, CAST(year AS INTEGER) yr FROM cyc_df")
    con.execute("CREATE TEMP TABLE cur AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM cur_df")
    con.execute("CREATE TEMP TABLE vocab AS SELECT CAST(dscrptr_ui AS INTEGER) d FROM vocab_df")
    con.execute("CREATE TEMP TABLE mesh AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.execute("""CREATE TEMP TABLE pool AS SELECT CAST(app_id AS BIGINT) app_id, ic, irg_code, CAST(year AS INTEGER) yr,
                   CAST(has_text AS INTEGER) has_text, CAST(tag_src AS INTEGER) tag_src FROM pool_df""")
    con.execute("CREATE TEMP TABLE own AS SELECT DISTINCT CAST(app_id AS BIGINT) app_id, setnb FROM own_df")
    con.execute("CREATE TEMP TABLE tags AS SELECT CAST(app_id AS BIGINT) app_id, CAST(dscrptr_ui AS INTEGER) d FROM tags_df SEMI JOIN vocab ON vocab.d = CAST(tags_df.dscrptr_ui AS INTEGER)")
    for k in frames:
        con.unregister(k + "_df")
    # how much of the cycles' pair weight the common vocabulary removes
    vshare = con.execute("""
        WITH k AS (SELECT c.cid, m.pmid, count(*) AS n_all, count(v.d) AS n_voc
                   FROM cur c JOIN mesh m USING (pmid) LEFT JOIN vocab v ON v.d = m.d GROUP BY ALL)
        SELECT sum(n_voc * (n_voc - 1) / 2) / sum(n_all * (n_all - 1) / 2) FROM k""").fetchone()[0]
    # the cycle's pairs, within the common vocabulary, weighted by papers
    con.execute("CREATE TEMP TABLE meshv AS SELECT m.pmid, m.d FROM mesh m SEMI JOIN vocab ON vocab.d = m.d")
    con.execute("""CREATE TEMP TABLE cp AS
        SELECT c.cid, a.d AS d1, b.d AS d2, count(*) AS freq
        FROM cur c JOIN meshv a ON a.pmid = c.pmid JOIN meshv b ON b.pmid = c.pmid AND a.d < b.d
        GROUP BY ALL""")
    # the pairs each cell's cycles need, and the pool applications' pairs among them
    con.execute("""CREATE TEMP TABLE need AS
        SELECT DISTINCT y.ic, y.irg_code, y.yr, cp.d1, cp.d2 FROM cp JOIN cyc y USING (cid)""")
    con.execute("""CREATE TEMP TABLE ap AS
        SELECT p.app_id, p.ic, p.irg_code, p.yr, a.d AS d1, b.d AS d2
        FROM pool p JOIN tags a ON a.app_id = p.app_id JOIN tags b ON b.app_id = p.app_id AND a.d < b.d
        SEMI JOIN need n ON n.ic = p.ic AND n.irg_code = p.irg_code AND n.yr = p.yr AND n.d1 = a.d AND n.d2 = b.d""")
    con.execute("""CREATE TEMP TABLE cnt AS
        SELECT ic, irg_code, yr, d1, d2, count(*) AS n FROM ap GROUP BY ALL""")
    con.execute("""CREATE TEMP TABLE owncnt AS
        SELECT y.cid, ap.d1, ap.d2, count(*) AS n_own
        FROM cyc y JOIN own o ON o.setnb = y.setnb
        JOIN ap ON ap.app_id = o.app_id AND ap.ic = y.ic AND ap.irg_code = y.irg_code AND ap.yr = y.yr
        GROUP BY ALL""")
    # the pools' size and makeup, the investigator's own applications excluded
    con.execute("""CREATE TEMP TABLE psize AS
        SELECT y.cid,
               count(*) FILTER (WHERE p.tag_src > 0) AS nb_abs,
               count(*) FILTER (WHERE p.tag_src = 2) AS nb_twin,
               count(*) FILTER (WHERE p.tag_src = 0 AND p.has_text = 1) AS nb_untagged
        FROM cyc y JOIN pool p ON p.ic = y.ic AND p.irg_code = y.irg_code AND p.yr = y.yr
        WHERE NOT EXISTS (SELECT 1 FROM own o WHERE o.app_id = p.app_id AND o.setnb = y.setnb)
        GROUP BY y.cid""")
    res = con.execute("""
        WITH w AS (
            SELECT cp.cid, CAST(sum(cp.freq) AS DOUBLE) AS w_all,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE coalesce(c.n, 0) - coalesce(o.n_own, 0) = 0), 0) AS DOUBLE) AS w_uniq
            FROM cp JOIN cyc y ON y.cid = cp.cid
            LEFT JOIN cnt c ON c.ic = y.ic AND c.irg_code = y.irg_code AND c.yr = y.yr AND c.d1 = cp.d1 AND c.d2 = cp.d2
            LEFT JOIN owncnt o ON o.cid = cp.cid AND o.d1 = cp.d1 AND o.d2 = cp.d2
            GROUP BY cp.cid)
        SELECT CAST(w.cid AS INTEGER) AS cid, w.w_all, w.w_uniq,
               CAST(coalesce(s.nb_abs, 0) AS INTEGER) AS nb_abs,
               CAST(coalesce(s.nb_twin, 0) AS INTEGER) AS nb_twin,
               CAST(coalesce(s.nb_untagged, 0) AS INTEGER) AS nb_untagged
        FROM w LEFT JOIN psize s ON s.cid = w.cid ORDER BY w.cid""").df()
    n_cp  = con.execute("SELECT count(*) FROM cp").fetchone()[0]
    n_ap  = con.execute("SELECT count(*) FROM ap").fetchone()[0]
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("share of the cycles' pair weight kept by the common vocabulary: {:.4f}".format(vshare))
SFIToolkit.display("cycle x pair rows: {:,}; pool application x needed pair rows: {:,}; cycles: {:,}".format(n_cp, n_ap, len(res)))
res.to_stata(g("so_res"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   4. The measure, saved
   ----------------------------------------------------------------------------- */
use `res', clear ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
display as result "=== cycles with a pair: pool of at least 20 others, pair weight above 5" ;
gen byte ok_pool = nb_abs >= 20 ;
gen byte ok_w    = w_all > 5 ;
tab ok_pool ok_w ;
keep if ok_pool & ok_w ;
gen double frac_icirg_pair = w_uniq / w_all ;
gen double pool_twin_share = nb_twin / nb_abs ;
gen double pool_complete   = nb_abs / (nb_abs + nb_untagged) ;
label var frac_icirg_pair  "Standing out: share of the cycle's MeSH pairs absent from its pool" ;
label var nb_abs           "Other tagged applications in the pool" ;
label var nb_twin          "... of which tagged through an identical abstract" ;
label var nb_untagged      "Other applications in the pool with text but no tags" ;
label var pool_twin_share  "nb_twin / nb_abs" ;
label var pool_complete    "nb_abs / (nb_abs + nb_untagged)" ;
keep setnb project_number cycle frac_icirg_pair nb_abs nb_twin nb_untagged pool_twin_share pool_complete ;
order setnb project_number cycle frac_icirg_pair nb_abs nb_twin nb_untagged pool_twin_share pool_complete ;
label data "Standing out, nih_risk" ;
notes: Built `c(current_date)' by code/build/12_standing_out.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_standout.dta", replace ;

/* -----------------------------------------------------------------------------
   5. First look: sample cycles
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta",
    keepusing(in_sample sep renewed cycle_yr) ;
assert _merge != 1 ;
keep if _merge == 3 & in_sample & sep != 1 ;
drop _merge ;
display as result "=== sample cycles with standing out defined" ;
count ;
display as result "=== standing out and its pool, by renewal" ;
tabstat frac_icirg_pair nb_abs pool_twin_share pool_complete, by(renewed) stat(mean p50 n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/12_standing_out.do */
