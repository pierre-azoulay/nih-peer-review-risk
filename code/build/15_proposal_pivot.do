/* =============================================================================
   code/build/15_proposal_pivot.do

   Purpose: How far the application that starts the cycle pivots away from the
            investigator's recent work, for Appendix Table D5 (is the penalty
            on pivoting smaller when the proposal itself announced the pivot?).
            One row per analysis-sample cycle whose starting application has
            MTI tags:
              frac_app_single_new  share of the application's descriptors that
                                   appear on none of the baseline papers: the
                                   proposal measure of Appendix Table D5
              frac_app_pair_new    share of the application's MeSH descriptor
                                   pairs (unordered pairs of its distinct MTI
                                   tags) that appear on none of the
                                   investigator's baseline papers, the unit of
                                   the pivoting measure; the machine tags of an
                                   abstract rarely reproduce the pairs that
                                   indexers assign to papers, so this share
                                   bunches near 1 (an alternative, in no
                                   table)
            - the application: app_id of the competing award that starts the
              cycle; its MTI tags, own or inherited from an identical abstract
              (code/build/11_abstract_tags.do), restricted to the descriptors
              common to the MTI tags and PubMed 2025 (mti_vocab.dta), as in
              standing out;
            - baseline papers: those of the pivoting measure
              (code/build/09_pivoting.do), the investigator's English original
              research in Author-ity published from cycle_yr - 5 to
              cycle_yr - 1, PubMed 2025 MeSH.
            Both measures are defined on the same cycles: the application has
            at least two descriptors and the baseline a paper with MeSH.

   Input:
     - ${data}/build/cycles.dta          (code/build/01_cycles.do)
     - ${data}/build/abstract_tags.dta, mti_vocab.dta
                                         (code/build/11_abstract_tags.do)
     - ${data}/build/risk_pivoting.dta   (code/build/09_pivoting.do), for the
                                         first look only
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity papers
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_meshterms_2025.dta   PubMed 2025

   Output:
     - ${data}/build/proposal_pivot.dta, one row per setnb x project_number x cycle

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
log using "logs/15_proposal_pivot.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Analysis-sample cycles, with a numeric key
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr author_id app_id in_sample sep using "${data}/build/cycles.dta", clear ;
keep if in_sample & sep != 1 ;
drop in_sample sep ;
sort setnb project_number cycle ;
gen long cid = _n ;
count ;
count if missing(app_id) ;
tempfile keys ;
save `keys' ;

/* -----------------------------------------------------------------------------
   2. The application's descriptors, in the common vocabulary
   ----------------------------------------------------------------------------- */
use app_id dscrptr_ui using "${data}/build/abstract_tags.dta", clear ;
merge m:1 dscrptr_ui using "${data}/build/mti_vocab.dta" ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
gduplicates drop ;
tempfile tags ;
save `tags' ;
use cid app_id using `keys', clear ;
drop if missing(app_id) ;
joinby app_id using `tags' ;
keep cid dscrptr_ui ;
gisid cid dscrptr_ui ;
quietly gdistinct cid ;
display as result "=== cycles whose starting application has MTI tags: " r(ndistinct) ;
tempfile app ;
save `app' ;

/* -----------------------------------------------------------------------------
   3. Baseline papers (as in code/build/09_pivoting.do, section 3)
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

use pmid using `base', clear ;
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
   4. Shares, in DuckDB. Only the baseline descriptors that also tag the
   application can make one of its descriptors or pairs familiar, so the
   baseline is cut to them before pairs are formed.
   ----------------------------------------------------------------------------- */
global pp_app  "`app'" ;
global pp_base "`base'" ;
global pp_mesh "`mesh'" ;
tempfile res ;
global pp_res  "`res'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

app  = pd.read_stata(Macro.getGlobal("pp_app"), convert_categoricals=False)
base = pd.read_stata(Macro.getGlobal("pp_base"))
mesh = pd.read_stata(Macro.getGlobal("pp_mesh"), convert_categoricals=False)
spill = os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_proposal")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=16")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    con.register("app_df", app)
    con.register("base_df", base)
    con.register("mesh_df", mesh)
    con.execute("CREATE TEMP TABLE apd  AS SELECT DISTINCT CAST(cid AS INTEGER) cid, CAST(dscrptr_ui AS INTEGER) d FROM app_df")
    con.execute("CREATE TEMP TABLE base AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM base_df")
    con.execute("CREATE TEMP TABLE mesh AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.unregister("app_df"); con.unregister("base_df"); con.unregister("mesh_df")
    # the application's pairs
    con.execute("""CREATE TEMP TABLE ap AS
        SELECT a.cid, a.d AS d1, b.d AS d2 FROM apd a JOIN apd b ON a.cid = b.cid AND a.d < b.d""")
    # baseline papers with MeSH, per cycle
    con.execute("""CREATE TEMP TABLE nb AS
        SELECT b.cid, count(DISTINCT b.pmid) AS n_base FROM base b SEMI JOIN mesh m ON m.pmid = b.pmid GROUP BY b.cid""")
    # baseline paper x descriptor, cut to the application's descriptors
    con.execute("""CREATE TEMP TABLE bm AS
        SELECT DISTINCT b.cid, b.pmid, m.d FROM base b JOIN mesh m ON m.pmid = b.pmid
        SEMI JOIN apd ON apd.cid = b.cid AND apd.d = m.d""")
    con.execute("CREATE TEMP TABLE bd AS SELECT DISTINCT cid, d FROM bm")
    con.execute("""CREATE TEMP TABLE bp AS
        SELECT DISTINCT x.cid, x.d AS d1, y.d AS d2 FROM bm x JOIN bm y
        ON x.cid = y.cid AND x.pmid = y.pmid AND x.d < y.d""")
    res = con.execute("""
        WITH s AS (SELECT a.cid, count(*) AS n_desc, count(bd.d) AS n_desc_old
                   FROM apd a LEFT JOIN bd ON bd.cid = a.cid AND bd.d = a.d GROUP BY a.cid),
             p AS (SELECT a.cid, count(*) AS n_pair, count(bp.d1) AS n_pair_old
                   FROM ap a LEFT JOIN bp ON bp.cid = a.cid AND bp.d1 = a.d1 AND bp.d2 = a.d2 GROUP BY a.cid)
        SELECT CAST(s.cid AS INTEGER) cid, CAST(s.n_desc AS INTEGER) n_app_desc, CAST(s.n_desc_old AS INTEGER) n_desc_old,
               CAST(coalesce(p.n_pair, 0) AS INTEGER) n_pair, CAST(coalesce(p.n_pair_old, 0) AS INTEGER) n_pair_old,
               CAST(coalesce(nb.n_base, 0) AS INTEGER) n_app_base
        FROM s LEFT JOIN p ON p.cid = s.cid LEFT JOIN nb ON nb.cid = s.cid ORDER BY cid""").df()
    n_ap = con.execute("SELECT count(*) FROM ap").fetchone()[0]
    n_bp = con.execute("SELECT count(*) FROM bp").fetchone()[0]
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("application pairs: {:,}; familiar pairs in the baselines: {:,}; cycles: {:,}".format(n_ap, n_bp, len(res)))
res.to_stata(Macro.getGlobal("pp_res"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   5. The measures, saved
   ----------------------------------------------------------------------------- */
use `res', clear ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
tab _merge ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
gen byte pp_ok = n_app_desc >= 2 & n_app_base > 0 ;
tab pp_ok ;
keep if pp_ok ;
gen double frac_app_pair_new   = 1 - n_pair_old / n_pair ;
gen double frac_app_single_new = 1 - n_desc_old / n_app_desc ;
label var frac_app_pair_new   "Share of the starting application's MeSH pairs absent from the 5-yr baseline" ;
label var frac_app_single_new "Share of the starting application's MeSH descriptors absent from the 5-yr baseline" ;
label var n_app_desc          "MTI descriptors of the starting application (common vocabulary)" ;
label var n_app_base          "Baseline papers with MeSH" ;
keep setnb project_number cycle frac_app_pair_new frac_app_single_new n_app_desc n_app_base ;
order setnb project_number cycle frac_app_pair_new frac_app_single_new n_app_desc n_app_base ;
summarize frac_app_pair_new frac_app_single_new n_app_desc n_app_base, detail ;
label data "Pivoting in the proposal, nih_risk" ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/proposal_pivot.dta", replace ;

/* first look: by renewal, and against pivoting in the cycle's papers */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta", keepusing(renewed) ;
keep if _merge == 3 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_pivoting.dta", keepusing(frac_setnb_pair) ;
drop if _merge == 2 ;
drop _merge ;
tabstat frac_app_pair_new frac_app_single_new n_app_desc, by(renewed) stat(mean p50 n) ;
correlate frac_app_pair_new frac_app_single_new frac_setnb_pair ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
