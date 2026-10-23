/* =============================================================================
   code/build/32_standout_extras.do

   Purpose: The pieces that dissect standing out, one row per analysis cycle
            with the measure, for Appendix Tables E1 to E4
            (code/analysis/29_tables_E1_E4.do). Standing out is the share of
            the pair instances of the cycle's acknowledging papers (a pair of
            descriptors counted once for each paper on which it appears)
            whose pair appears on no other tagged application of the pool
            (code/build/12_standing_out.do). Here:
            - test 1, where the unique pairs are found: on the investigator's
              publications of the five years before the cycle (the baseline of
              code/build/09_pivoting.do), so_own; new to her and first used in
              PubMed more than three years before the paper appeared, so_est;
              new to her and first used at most three years before, so_new
              (the rule of code/build/13_novelty_mesh.py). The three add up to
              standing out. For the log, the part new to PubMed at one year
              (so_new1) and at ten (so_new10). Defined when the baseline has a
              paper with a descriptor, as pivoting is.
            - test 2, a placebo: the share of the cycle's pair instances
              absent from the pool of another study section of the same
              evaluation year, for five study sections drawn at random among
              the institute x study section cells with at least 20 tagged
              applications, the cycle's own study section excluded under
              every institute and the investigator's own applications removed
              from each; so_plac is the mean of the five, so_plac1 the first
              draw.
            - test 3, near and far unique pairs: near when each descriptor of
              the pair appears on some application of the pool (her own
              excluded), far otherwise; so_near + so_far = standing out. Also
              standing out without NLM's 40 check tags (so_noct), on the pairs
              with no check tag, defined when they number more than five.
            - the split of pivoting (Appendix Table E3): on the same pairs of
              the common vocabulary, the pairs new to the investigator that
              some application of the pool has (piv_sh) and those that none
              has (piv_un, equal to so_est + so_new). With so_own, the three
              are the cells of a two-way split of the cycle's pairs, new or
              not to the investigator, shared or not with the pool.
            The do-file copies the pools and pairs of 12_standing_out.do and
            the baseline of 09_pivoting.do, and stops unless it reproduces
            frac_icirg_pair and frac_setnb_pair exactly. Test 4 (the pool's
            size) uses nb_abs, already in risk_standout.dta. The output stays
            apart from the analysis file: 29_tables_E1_E4.do merges it in.
            The placebo draws (Stata, set seed) and the draw of the example's
            five cycles (numpy) use fixed seeds.

   Input:
     - ${data}/build/cycles.dta          (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta    (code/build/03_cycle_papers.do)
     - ${data}/build/abstract_pool.dta, abstract_tags.dta, mti_vocab.dta
                                         (code/build/11_abstract_tags.do)
     - ${data}/build/risk_standout.dta   (code/build/12_standing_out.do) and
       ${data}/build/risk_pivoting.dta   (code/build/09_pivoting.do), for the
                                         checks
     - ${data}/build/meshpair_birthyear.parquet   (code/build/13_novelty_mesh.py)
     - ${data}/build/explore/check_tags.dta       (code/build/10_pivoting_extras.do)
     - ${input}/cgaf_nih_risk.dta   investigators of every application
     - ${pubmed_root}/pubmed/overall_meshterms_2025.dta, overall_dates_2025.dta,
       pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta
     - ${pubmed_root}/authority/authority_pmids_clean.dta
     - ${pubmed_root}/mesh2025/mesh_descriptors_2025.dta (names, for the
       examples)

   Output:
     - ${data}/build/risk_standout_extras.dta   one row per cycle with
       standing out
     - ${data}/build/explore/standout_examples.dta   the pairs of five cycles
       with a single acknowledging paper, for the example in the text of
       Appendix E

   Note: DuckDB with 16 threads, its spill folder ${nr_spill} if set,
         otherwise duckdb_spill_nihrep_standout_extras in the system's temp
         folder.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/32_standout_extras.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles: the cycles of code/build/12_standing_out.do, with what the
      baseline needs
   ----------------------------------------------------------------------------- */
use setnb project_number cycle ic irg_code eval_year cycle_yr author_id in_sample sep
    using "${data}/build/cycles.dta", clear ;
sort setnb project_number cycle ;
gen long cid = _n ;
gen byte so_cycle = in_sample & sep != 1 & irg_code != "" ;
tempfile keys ;
save `keys' ;
keep if so_cycle ;
rename eval_year year ;
keep cid setnb ic irg_code year cycle_yr author_id ;
tempfile cyc ;
save `cyc' ;

/* -----------------------------------------------------------------------------
   2. Current papers (code/build/12_standing_out.do, section 1), with their
      year
   ----------------------------------------------------------------------------- */
use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
merge m:1 setnb project_number cycle using `keys', keepusing(cid so_cycle) ;
tab _merge ;
assert _merge != 1 ;
keep if _merge == 3 & so_cycle ;
keep cid pmid ;
gisid cid pmid ;
tempfile cur ;
save `cur' ;

/* the publication year of code/build/13_novelty_mesh.py: the earliest year
   of the paper in overall_dates_2025 */
keep pmid ;
bysort pmid: keep if _n == 1 ;
tempfile curp ;
save `curp' ;
use pmid year using "${pubmed_root}/pubmed/overall_dates_2025.dta", clear ;
merge m:1 pmid using `curp' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
drop if missing(year) ;
gcollapse (min) pyear = year, by(pmid) ;
tempfile pyr ;
save `pyr' ;

/* -----------------------------------------------------------------------------
   3. Baseline papers (code/build/09_pivoting.do, section 3): the
      investigator's papers in the five years before the cycle
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

use author_id using `cyc', clear ;
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
joinby author_id using `cyc' ;
keep if pubyear >= cycle_yr - 5 & pubyear <= cycle_yr - 1 ;
keep cid pmid ;
gisid cid pmid ;
display as result "=== baseline papers of the standing-out cycles (cycle x paper)" ;
count ;
tempfile base ;
save `base' ;

/* -----------------------------------------------------------------------------
   4. MeSH descriptors of every current or baseline paper (all descriptors)
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
   5. The pools and the investigators of each (code/build/12_standing_out.do,
      section 2)
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
   6. The placebo draws. Eligible cells: institute x study section x year cells
      with at least 20 tagged applications. For each cycle, five distinct
      cells of its evaluation year whose study section is not its own, drawn
      with replacement from a fixed seed after a unique sort, duplicates and
      the cycle's own study section dropped, the first five kept.
   ----------------------------------------------------------------------------- */
use ic irg_code year tag_src using `pool', clear ;
gen byte tagged = tag_src > 0 ;
gcollapse (sum) ntag = tagged, by(ic irg_code year) ;
keep if ntag >= 20 ;
sort year ic irg_code ;
by year: gen int pno = _n ;
by year: gen int npy = _N ;
gen long cell = _n ;
display as result "=== eligible placebo cells (at least 20 tagged applications), by decade" ;
gen int decade = 10 * floor(year / 10) ;
tab decade ;
drop decade ;
tempfile pcells ;
save `pcells' ;
keep year npy ;
bysort year: keep if _n == 1 ;
tempfile npy ;
save `npy' ;

use cid year irg_code using `cyc', clear ;
rename irg_code irg_own ;
merge m:1 year using `npy' ;
tab _merge ;
drop if _merge == 2 ;
display as result "=== standing-out cycles whose evaluation year has no eligible cell (no placebo)" ;
count if _merge == 1 ;
keep if _merge == 3 ;
drop _merge ;
expand 60 ;
sort cid ;
by cid: gen int draw = _n ;
sort cid draw ;
set seed 20261013 ;
gen double u = runiform() ;
gen int pno = 1 + floor(u * npy) ;
merge m:1 year pno using `pcells', keepusing(irg_code cell) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
drop if irg_code == irg_own ;
bysort cid cell (draw): keep if _n == 1 ;
bysort cid (draw): keep if _n <= 5 ;
by cid: gen byte pdraw = _n ;
by cid: gen byte ndraw = _N ;
display as result "=== placebo draws per cycle (5 expected)" ;
tab ndraw ;
keep cid pdraw cell ;
sort cid pdraw ;
tempfile plc ;
save `plc' ;

/* -----------------------------------------------------------------------------
   7. The pieces, in DuckDB
   ----------------------------------------------------------------------------- */
tempfile res piv plres exm ;
global sx_cyc    "`cyc'" ;
global sx_cur    "`cur'" ;
global sx_pyr    "`pyr'" ;
global sx_base   "`base'" ;
global sx_mesh   "`mesh'" ;
global sx_pool   "`pool'" ;
global sx_own    "`own'" ;
global sx_plc    "`plc'" ;
global sx_pcells "`pcells'" ;
global sx_tags   "${data}/build/abstract_tags.dta" ;
global sx_vocab  "${data}/build/mti_vocab.dta" ;
global sx_ctag   "${data}/build/explore/check_tags.dta" ;
global sx_birth  "${data}/build/meshpair_birthyear.parquet" ;
global sx_res    "`res'" ;
global sx_piv    "`piv'" ;
global sx_plres  "`plres'" ;
global sx_exm    "`exm'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import numpy as np
import pandas as pd
from sfi import Macro, Scalar, SFIToolkit

g = Macro.getGlobal
frames = {
    "cyc":   pd.read_stata(g("sx_cyc")),
    "cur":   pd.read_stata(g("sx_cur")),
    "pyr":   pd.read_stata(g("sx_pyr")),
    "base":  pd.read_stata(g("sx_base")),
    "mesh":  pd.read_stata(g("sx_mesh"), convert_categoricals=False),
    "pool":  pd.read_stata(g("sx_pool"), convert_categoricals=False),
    "own":   pd.read_stata(g("sx_own")),
    "plc":   pd.read_stata(g("sx_plc")),
    "pcell": pd.read_stata(g("sx_pcells")),
    "tags":  pd.read_stata(g("sx_tags"), convert_categoricals=False),
    "vocab": pd.read_stata(g("sx_vocab"), convert_categoricals=False),
    "ctag":  pd.read_stata(g("sx_ctag"), columns=["d"], convert_categoricals=False),
}
birth_path = g("sx_birth").replace("\\", "/")
spill = g("nr_spill") or os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_standout_extras")
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
    con.execute("CREATE TEMP TABLE pyr AS SELECT CAST(pmid AS INTEGER) pmid, CAST(pyear AS INTEGER) pyear FROM pyr_df")
    con.execute("CREATE TEMP TABLE base AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM base_df")
    con.execute("CREATE TEMP TABLE mesh AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.execute("CREATE TEMP TABLE vocab AS SELECT CAST(dscrptr_ui AS INTEGER) d FROM vocab_df")
    con.execute("CREATE TEMP TABLE ctag AS SELECT DISTINCT CAST(d AS INTEGER) d FROM ctag_df")
    con.execute("""CREATE TEMP TABLE pool AS SELECT CAST(app_id AS BIGINT) app_id, ic, irg_code, CAST(year AS INTEGER) yr,
                   CAST(has_text AS INTEGER) has_text, CAST(tag_src AS INTEGER) tag_src FROM pool_df""")
    con.execute("CREATE TEMP TABLE own AS SELECT DISTINCT CAST(app_id AS BIGINT) app_id, setnb FROM own_df")
    con.execute("CREATE TEMP TABLE tags AS SELECT CAST(app_id AS BIGINT) app_id, CAST(dscrptr_ui AS INTEGER) d FROM tags_df SEMI JOIN vocab ON vocab.d = CAST(tags_df.dscrptr_ui AS INTEGER)")
    con.execute("CREATE TEMP TABLE plc AS SELECT CAST(cid AS INTEGER) cid, CAST(pdraw AS INTEGER) pdraw, CAST(cell AS INTEGER) cell FROM plc_df")
    con.execute("CREATE TEMP TABLE pcell AS SELECT CAST(cell AS INTEGER) cell, ic, irg_code, CAST(year AS INTEGER) yr FROM pcell_df")
    for k in frames:
        con.unregister(k + "_df")
    del frames

    # pairs of distinct descriptors on a paper, every descriptor (as in
    # code/build/09_pivoting.do)
    con.execute("""CREATE TEMP TABLE pp AS
        SELECT a.pmid, a.d AS d1, b.d AS d2 FROM mesh a JOIN mesh b ON a.pmid = b.pmid AND a.d < b.d""")
    # pivoting, for the check: the cycle's pairs and those of its baseline
    con.execute("""CREATE TEMP TABLE cpf AS
        SELECT c.cid, p.d1, p.d2, count(*) AS freq FROM cur c JOIN pp p USING (pmid) GROUP BY ALL""")
    con.execute("""CREATE TEMP TABLE bpf AS
        SELECT DISTINCT b.cid, p.d1, p.d2 FROM base b JOIN pp p USING (pmid)
        SEMI JOIN cpf ON cpf.cid = b.cid AND cpf.d1 = p.d1 AND cpf.d2 = p.d2""")
    piv = con.execute("""
        WITH sh AS (
            SELECT cpf.cid, CAST(sum(cpf.freq) AS DOUBLE) AS w_all_f,
                   CAST(coalesce(sum(cpf.freq) FILTER (WHERE bpf.cid IS NULL), 0) AS DOUBLE) AS w_new_f
            FROM cpf LEFT JOIN bpf ON bpf.cid = cpf.cid AND bpf.d1 = cpf.d1 AND bpf.d2 = cpf.d2
            GROUP BY cpf.cid),
        nb AS (SELECT cid, count(DISTINCT pmid) AS n_base_mesh FROM base SEMI JOIN mesh USING (pmid) GROUP BY cid)
        SELECT CAST(sh.cid AS INTEGER) AS cid, sh.w_all_f, sh.w_new_f,
               CAST(coalesce(nb.n_base_mesh, 0) AS INTEGER) AS n_base_mesh
        FROM sh LEFT JOIN nb USING (cid) ORDER BY cid""").df()

    # standing out (code/build/12_standing_out.do): the cycle's pairs within
    # the common vocabulary, paper by paper, then weighted by papers
    con.execute("""CREATE TEMP TABLE pinst AS
        SELECT c.cid, c.pmid, p.d1, p.d2 FROM cur c JOIN pp p USING (pmid)
        SEMI JOIN vocab v1 ON v1.d = p.d1 SEMI JOIN vocab v2 ON v2.d = p.d2""")
    con.execute("CREATE TEMP TABLE cp AS SELECT cid, d1, d2, count(*) AS freq FROM pinst GROUP BY ALL")
    con.execute("""CREATE TEMP TABLE need AS
        SELECT DISTINCT y.ic, y.irg_code, y.yr, cp.d1, cp.d2 FROM cp JOIN cyc y USING (cid)""")
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
        SELECT y.cid,
               count(*) FILTER (WHERE p.tag_src > 0) AS nb_abs
        FROM cyc y JOIN pool p ON p.ic = y.ic AND p.irg_code = y.irg_code AND p.yr = y.yr
        WHERE NOT EXISTS (SELECT 1 FROM own o WHERE o.app_id = p.app_id AND o.setnb = y.setnb)
        GROUP BY y.cid""")

    # test 3: each descriptor of the pool's applications, the investigator's
    # own applications excluded
    con.execute("""CREATE TEMP TABLE celld AS
        SELECT p.ic, p.irg_code, p.yr, t.d, count(*) AS n
        FROM pool p JOIN tags t USING (app_id)
        SEMI JOIN (SELECT DISTINCT ic, irg_code, yr FROM cyc) z ON z.ic = p.ic AND z.irg_code = p.irg_code AND z.yr = p.yr
        GROUP BY ALL""")
    con.execute("""CREATE TEMP TABLE ownd AS
        SELECT y.cid, t.d, count(*) AS n_own
        FROM cyc y JOIN own o ON o.setnb = y.setnb
        JOIN pool p ON p.app_id = o.app_id AND p.ic = y.ic AND p.irg_code = y.irg_code AND p.yr = y.yr
        JOIN tags t ON t.app_id = p.app_id
        GROUP BY ALL""")

    # every pair of the cycle: shared with the pool, on the baseline, near,
    # with a check tag
    con.execute("""CREATE TEMP TABLE cpx AS
        SELECT cp.cid, cp.d1, cp.d2, cp.freq,
               (coalesce(c.n, 0) - coalesce(o.n_own, 0) > 0) AS shared,
               (bpf.cid IS NOT NULL) AS isown,
               (coalesce(e1.n, 0) - coalesce(f1.n_own, 0) > 0) AND (coalesce(e2.n, 0) - coalesce(f2.n_own, 0) > 0) AS near,
               (k1.d IS NOT NULL OR k2.d IS NOT NULL) AS hasct
        FROM cp JOIN cyc y USING (cid)
        LEFT JOIN cnt c ON c.ic = y.ic AND c.irg_code = y.irg_code AND c.yr = y.yr AND c.d1 = cp.d1 AND c.d2 = cp.d2
        LEFT JOIN owncnt o ON o.cid = cp.cid AND o.d1 = cp.d1 AND o.d2 = cp.d2
        LEFT JOIN bpf ON bpf.cid = cp.cid AND bpf.d1 = cp.d1 AND bpf.d2 = cp.d2
        LEFT JOIN celld e1 ON e1.ic = y.ic AND e1.irg_code = y.irg_code AND e1.yr = y.yr AND e1.d = cp.d1
        LEFT JOIN ownd f1 ON f1.cid = cp.cid AND f1.d = cp.d1
        LEFT JOIN celld e2 ON e2.ic = y.ic AND e2.irg_code = y.irg_code AND e2.yr = y.yr AND e2.d = cp.d2
        LEFT JOIN ownd f2 ON f2.cid = cp.cid AND f2.d = cp.d2
        LEFT JOIN ctag k1 ON k1.d = cp.d1
        LEFT JOIN ctag k2 ON k2.d = cp.d2""")

    # test 1: the age of each pair instance, the paper's year minus the
    # pair's first year in PubMed
    con.execute("CREATE TEMP TABLE upairs AS SELECT DISTINCT d1, d2 FROM cp")
    con.execute("""CREATE TEMP TABLE birth AS
        SELECT CAST(b.d1 AS INTEGER) d1, CAST(b.d2 AS INTEGER) d2, CAST(b.birth AS INTEGER) birth
        FROM read_parquet('{}') b
        SEMI JOIN upairs u ON u.d1 = CAST(b.d1 AS INTEGER) AND u.d2 = CAST(b.d2 AS INTEGER)""".format(birth_path))
    n_nobirth = con.execute("SELECT count(*) FROM upairs ANTI JOIN birth USING (d1, d2)").fetchone()[0]
    n_noyear = con.execute("SELECT count(DISTINCT pmid) FROM pinst ANTI JOIN pyr USING (pmid)").fetchone()[0]
    con.execute("""CREATE TEMP TABLE agec AS
        SELECT i.cid, i.d1, i.d2,
               count(*) FILTER (WHERE r.pyear - b.birth <= 1)  AS n1,
               count(*) FILTER (WHERE r.pyear - b.birth <= 3)  AS n3,
               count(*) FILTER (WHERE r.pyear - b.birth <= 10) AS n10,
               count(*) FILTER (WHERE r.pyear IS NULL OR b.birth IS NULL) AS nna,
               count(*) FILTER (WHERE r.pyear - b.birth < 0) AS nneg
        FROM pinst i LEFT JOIN pyr r USING (pmid) LEFT JOIN birth b ON b.d1 = i.d1 AND b.d2 = i.d2
        GROUP BY ALL""")
    res = con.execute("""
        SELECT CAST(x.cid AS INTEGER) AS cid,
               CAST(sum(x.freq) AS DOUBLE) AS w_all,
               CAST(coalesce(sum(x.freq) FILTER (WHERE NOT x.shared), 0) AS DOUBLE) AS w_uniq,
               CAST(coalesce(sum(x.freq) FILTER (WHERE NOT x.shared AND x.isown), 0) AS DOUBLE) AS w_own,
               CAST(coalesce(sum(a.n3)   FILTER (WHERE NOT x.shared AND NOT x.isown), 0) AS DOUBLE) AS w_new3,
               CAST(coalesce(sum(a.n1)   FILTER (WHERE NOT x.shared AND NOT x.isown), 0) AS DOUBLE) AS w_new1,
               CAST(coalesce(sum(a.n10)  FILTER (WHERE NOT x.shared AND NOT x.isown), 0) AS DOUBLE) AS w_new10,
               CAST(coalesce(sum(a.nna)  FILTER (WHERE NOT x.shared AND NOT x.isown), 0) AS DOUBLE) AS w_na,
               CAST(coalesce(sum(a.n3)   FILTER (WHERE NOT x.shared AND x.isown), 0) AS DOUBLE) AS w_own_new3,
               CAST(coalesce(sum(a.nneg), 0) AS DOUBLE) AS w_neg,
               CAST(coalesce(sum(x.freq) FILTER (WHERE x.shared AND NOT x.isown), 0) AS DOUBLE) AS w_newsh,
               CAST(coalesce(sum(x.freq) FILTER (WHERE NOT x.shared AND x.near), 0) AS DOUBLE) AS w_near,
               CAST(coalesce(sum(x.freq) FILTER (WHERE NOT x.hasct), 0) AS DOUBLE) AS w_all_noct,
               CAST(coalesce(sum(x.freq) FILTER (WHERE NOT x.hasct AND NOT x.shared), 0) AS DOUBLE) AS w_uniq_noct,
               CAST(coalesce(sum(x.freq) FILTER (WHERE x.hasct), 0) AS DOUBLE) AS w_ct,
               CAST(coalesce(sum(x.freq) FILTER (WHERE x.hasct AND x.shared), 0) AS DOUBLE) AS w_ct_sh,
               CAST(coalesce(s.nb_abs, 0) AS INTEGER) AS nb_abs
        FROM cpx x LEFT JOIN agec a ON a.cid = x.cid AND a.d1 = x.d1 AND a.d2 = x.d2
        LEFT JOIN psize s ON s.cid = x.cid
        GROUP BY x.cid, s.nb_abs ORDER BY x.cid""").df()
    # share of the pools' tags that are check tags (the pools of these cycles)
    ct_pool = con.execute("""
        SELECT avg(CASE WHEN k.d IS NOT NULL THEN 1.0 ELSE 0.0 END)
        FROM pool p JOIN tags t USING (app_id) LEFT JOIN ctag k ON k.d = t.d
        SEMI JOIN (SELECT DISTINCT ic, irg_code, yr FROM cyc) z ON z.ic = p.ic AND z.irg_code = p.irg_code AND z.yr = p.yr""").fetchone()[0]

    # test 2: the placebo pools, their pairs among the pairs the cycles need,
    # and the investigator's own applications in them
    con.execute("""CREATE TEMP TABLE needp AS
        SELECT DISTINCT q.cell, cp.d1, cp.d2 FROM cp JOIN plc q USING (cid)""")
    con.execute("""CREATE TEMP TABLE appc AS
        SELECT p.app_id, c.cell, p.tag_src FROM pool p
        JOIN pcell c ON c.ic = p.ic AND c.irg_code = p.irg_code AND c.yr = p.yr
        SEMI JOIN (SELECT DISTINCT cell FROM plc) z ON z.cell = c.cell""")
    con.execute("""CREATE TEMP TABLE apP AS
        SELECT a.cell, a.app_id, x.d AS d1, y.d AS d2
        FROM appc a JOIN tags x ON x.app_id = a.app_id JOIN tags y ON y.app_id = a.app_id AND x.d < y.d
        SEMI JOIN needp n ON n.cell = a.cell AND n.d1 = x.d AND n.d2 = y.d""")
    con.execute("CREATE TEMP TABLE cntP AS SELECT cell, d1, d2, count(*) AS n FROM apP GROUP BY ALL")
    con.execute("""CREATE TEMP TABLE ownP AS
        SELECT q.cid, q.pdraw, ap.d1, ap.d2, count(*) AS n_own
        FROM plc q JOIN cyc y USING (cid) JOIN own o ON o.setnb = y.setnb
        JOIN apP ap ON ap.app_id = o.app_id AND ap.cell = q.cell
        GROUP BY ALL""")
    plres = con.execute("""
        WITH w AS (
            SELECT q.cid, q.pdraw,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE coalesce(c.n, 0) - coalesce(o.n_own, 0) = 0), 0) AS DOUBLE) AS w_uniq_p
            FROM cp JOIN plc q USING (cid)
            LEFT JOIN cntP c ON c.cell = q.cell AND c.d1 = cp.d1 AND c.d2 = cp.d2
            LEFT JOIN ownP o ON o.cid = q.cid AND o.pdraw = q.pdraw AND o.d1 = cp.d1 AND o.d2 = cp.d2
            GROUP BY ALL),
        tot AS (SELECT cell, count(*) FILTER (WHERE tag_src > 0) AS ntag FROM appc GROUP BY cell),
        ownn AS (
            SELECT q.cid, q.pdraw, count(DISTINCT a.app_id) AS n_own
            FROM plc q JOIN cyc y USING (cid) JOIN own o ON o.setnb = y.setnb
            JOIN appc a ON a.app_id = o.app_id AND a.cell = q.cell
            WHERE a.tag_src > 0
            GROUP BY ALL)
        SELECT CAST(w.cid AS INTEGER) cid, CAST(w.pdraw AS INTEGER) pdraw, w.w_uniq_p,
               CAST(t.ntag - coalesce(n.n_own, 0) AS INTEGER) AS nb_p
        FROM w JOIN plc q ON q.cid = w.cid AND q.pdraw = w.pdraw
        JOIN tot t ON t.cell = q.cell
        LEFT JOIN ownn n ON n.cid = w.cid AND n.pdraw = w.pdraw
        ORDER BY cid, pdraw""").df()

    # the example in the text of Appendix E: five cycles with a single
    # acknowledging paper of six to eight descriptors in the common
    # vocabulary, a pool of at least 20 and a baseline, drawn with a fixed
    # seed from the sorted list
    cand = con.execute("""
        WITH one AS (SELECT cid FROM pinst GROUP BY cid HAVING count(DISTINCT pmid) = 1),
        nd AS (SELECT i.cid, count(DISTINCT d) AS nd FROM
                 (SELECT cid, d1 AS d FROM pinst UNION ALL SELECT cid, d2 AS d FROM pinst) i GROUP BY i.cid)
        SELECT one.cid FROM one JOIN nd USING (cid) JOIN psize s USING (cid)
        WHERE nd.nd BETWEEN 6 AND 8 AND s.nb_abs >= 20
          AND EXISTS (SELECT 1 FROM base b SEMI JOIN mesh USING (pmid) WHERE b.cid = one.cid)
        ORDER BY one.cid""").df()["cid"].to_numpy()
    rng = np.random.default_rng(20261013)
    pick = np.sort(rng.choice(cand, size=min(5, len(cand)), replace=False))
    con.register("pick_df", pd.DataFrame({"cid": pick.astype("int64")}))
    exm = con.execute("""
        SELECT CAST(x.cid AS INTEGER) cid, CAST(i.pmid AS INTEGER) pmid, x.d1, x.d2,
               CAST(x.shared AS INTEGER) shared, CAST(x.isown AS INTEGER) isown,
               CAST(x.near AS INTEGER) near, CAST(x.hasct AS INTEGER) hasct,
               r.pyear, b.birth
        FROM cpx x JOIN pinst i ON i.cid = x.cid AND i.d1 = x.d1 AND i.d2 = x.d2
        LEFT JOIN pyr r ON r.pmid = i.pmid LEFT JOIN birth b ON b.d1 = x.d1 AND b.d2 = x.d2
        SEMI JOIN pick_df k ON k.cid = x.cid
        ORDER BY cid, d1, d2""").df()
    con.unregister("pick_df")
    n_cp = con.execute("SELECT count(*) FROM cp").fetchone()[0]
    n_needp = con.execute("SELECT count(*) FROM needp").fetchone()[0]
    n_apP = con.execute("SELECT count(*) FROM apP").fetchone()[0]
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("cycle x pair rows: {:,}; placebo cell x needed pair rows: {:,}; placebo application x pair rows: {:,}".format(n_cp, n_needp, n_apP))
SFIToolkit.display("pairs without a birth year: {:,}; current papers without a year: {:,}".format(n_nobirth, n_noyear))
SFIToolkit.display("share of the pools' tags that are check tags: {:.4f}".format(ct_pool))
SFIToolkit.display("candidates for the example: {:,}; drawn: {}".format(len(cand), ", ".join(str(c) for c in pick)))
Scalar.setValue("n_nobirth", n_nobirth)
Scalar.setValue("n_noyear", n_noyear)
Scalar.setValue("ct_pool", ct_pool)
res.to_stata(g("sx_res"), write_index=False)
piv.to_stata(g("sx_piv"), write_index=False)
plres.to_stata(g("sx_plres"), write_index=False)
for c in ["d1", "d2"]:
    exm[c] = exm[c].astype("int32")
exm.to_stata(g("sx_exm"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   8. Checks: pivoting and standing out reproduced exactly
   ----------------------------------------------------------------------------- */
display as result "=== CHECK: every pair has a first year in PubMed, every paper a year" ;
assert scalar(n_nobirth) == 0 ;
assert scalar(n_noyear) == 0 ;

use `piv', clear ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
gen byte piv_ok = n_base_mesh > 0 & w_all_f > 0 & w_all_f < . ;
gen double chk_piv = w_new_f / w_all_f if piv_ok ;
keep if piv_ok ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_pivoting.dta",
    keepusing(frac_setnb_pair n_base_mesh) update ;
display as result "=== CHECK: pivoting reproduced (3: same cycle and baseline count, 2: other cycles of risk_pivoting.dta)" ;
tab _merge ;
assert _merge == 2 | _merge == 3 ;
keep if _merge == 3 ;
drop _merge ;
gen double dd = abs(chk_piv - frac_setnb_pair) ;
summarize dd ;
assert dd < 1e-9 ;
display as result "=== CHECK passed: pivoting on " %9.0fc _N " standing-out cycles" ;
keep setnb project_number cycle n_base_mesh ;
tempfile pivok ;
save `pivok' ;

use `res', clear ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
gen byte ok_pool = nb_abs >= 20 ;
gen byte ok_w    = w_all > 5 ;
keep if ok_pool & ok_w ;
gen double chk_so = w_uniq / w_all ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_standout.dta",
    keepusing(frac_icirg_pair nb_abs) update ;
display as result "=== CHECK: the same cycles, with the same pool size (3), as risk_standout.dta" ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
gen double dd = abs(chk_so - frac_icirg_pair) ;
summarize dd ;
assert dd < 1e-12 ;
display as result "=== CHECK passed: standing out on " %9.0fc _N " cycles" ;
drop dd chk_so ok_pool ok_w ;

/* -----------------------------------------------------------------------------
   9. The pieces
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using `pivok' ;
/* 2: a cycle with pivoting but without standing out (a thin pool) */
drop if _merge == 2 ;
gen byte has_base = _merge == 3 ;
drop _merge ;
replace n_base_mesh = 0 if !has_base ;
display as result "=== cycles with standing out, with a baseline paper with MeSH (test 1 defined)" ;
tab has_base ;
/* on her earlier publications only when a baseline exists */
assert w_own == 0 & w_own_new3 == 0 if !has_base ;
assert w_na == 0 ;
assert w_neg == 0 ;

gen double so_own   = w_own / w_all if has_base ;
gen double so_new   = w_new3 / w_all if has_base ;
gen double so_est   = (w_uniq - w_own - w_new3) / w_all if has_base ;
gen double so_new1  = w_new1 / w_all if has_base ;
gen double so_new10 = w_new10 / w_all if has_base ;
/* pivoting on the same pairs (the common vocabulary), split by the study
   section's portfolio: pairs new to the investigator that the pool has
   (piv_sh) or does not have (piv_un, the last two parts of standing out).
   Appendix Table E3 */
gen double piv_sh   = w_newsh / w_all if has_base ;
gen double piv_un   = (w_uniq - w_own) / w_all if has_base ;
gen double so_near  = w_near / w_all ;
gen double so_far   = (w_uniq - w_near) / w_all ;
gen double so_noct  = w_uniq_noct / w_all_noct if w_all_noct > 5 ;
gen double ct_share    = w_ct / w_all ;
gen double ct_share_sh = w_ct_sh / (w_all - w_uniq) if w_all > w_uniq ;
assert abs(so_own + so_est + so_new - frac_icirg_pair) < 1e-9 if has_base ;
assert abs(so_near + so_far - frac_icirg_pair) < 1e-9 ;
assert abs(piv_un - so_est - so_new) < 1e-9 if has_base ;
assert piv_sh + piv_un <= 1 - so_own + 1e-9 if has_base ;
assert so_est >= -1e-12 if has_base ;
assert w_new1 <= w_new3 & w_new3 <= w_new10 ;

/* the placebo: five draws per cycle */
preserve ;
use `plres', clear ;
reshape wide w_uniq_p nb_p, i(cid) j(pdraw) ;
tempfile plw ;
save `plw' ;
restore ;
merge 1:1 cid using `plw' ;
display as result "=== CHECK: every cycle with standing out has its five placebo draws" ;
tab _merge ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
forvalues r = 1/5 {;
    assert !missing(w_uniq_p`r', nb_p`r') ;
    gen double so_plac_`r' = w_uniq_p`r' / w_all ;
} ;
egen double so_plac = rowmean(so_plac_1 so_plac_2 so_plac_3 so_plac_4 so_plac_5) ;
gen double so_plac1 = so_plac_1 ;
egen int plac_small = anycount(nb_p1 nb_p2 nb_p3 nb_p4 nb_p5), values(0/19) ;
display as result "=== placebo pools under 20 tagged applications once the investigator's are removed (per cycle, of 5)" ;
tab plac_small ;

label var so_own      "Standing out: unique pairs on the investigator's publications of the 5 years before" ;
label var so_est      "Standing out: unique pairs new to her, first used in PubMed over 3 years before" ;
label var so_new      "Standing out: unique pairs new to her, first used in PubMed at most 3 years before" ;
label var so_new1     "As so_new, at most 1 year (log)" ;
label var so_new10    "As so_new, at most 10 years (log)" ;
label var piv_sh      "Pivoting, common vocabulary: new pairs that the pool has" ;
label var piv_un      "Pivoting, common vocabulary: new pairs that the pool does not have" ;
label var so_near     "Standing out: unique pairs whose descriptors both appear in the pool" ;
label var so_far      "Standing out: unique pairs with a descriptor absent from the pool" ;
label var so_noct     "Standing out without NLM's 40 check tags (more than 5 pair instances)" ;
label var so_plac     "Placebo: share of pair instances absent from 5 other sections' pools, mean" ;
label var so_plac1    "Placebo, first draw" ;
label var has_base    "A baseline paper with MeSH (test 1 defined)" ;
label var n_base_mesh "Baseline papers with MeSH (code/build/09_pivoting.do)" ;
label var ct_share    "Share of the cycle's pair instances with a check tag" ;
label var ct_share_sh "... among the shared ones" ;
label var plac_small  "Placebo pools under 20 tagged applications, of 5" ;
label var w_all       "Pair instances of the cycle, common vocabulary" ;
tempfile all ;
save `all' ;
keep setnb project_number cycle so_own so_est so_new so_near so_far so_plac so_plac1 so_noct
     so_new1 so_new10 piv_sh piv_un has_base n_base_mesh ct_share ct_share_sh plac_small w_all ;
order setnb project_number cycle so_own so_est so_new so_near so_far so_plac so_plac1 so_noct
      so_new1 so_new10 piv_sh piv_un has_base n_base_mesh ct_share ct_share_sh plac_small w_all ;
label data "Standing out, its pieces, nih_risk" ;
notes: Built `c(current_date)' by code/build/32_standout_extras.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_standout_extras.dta", replace ;

/* -----------------------------------------------------------------------------
   10. The example in the text of Appendix E, with descriptor names
   ----------------------------------------------------------------------------- */
use in 1 using "${pubmed_root}/pubmed/overall_meshterms_2025.dta", clear ;
uselabel dscrptr_ui_lbl, clear ;
keep value label ;
rename (value label) (d ui) ;
merge 1:1 ui using "${pubmed_root}/mesh2025/mesh_descriptors_2025.dta", keepusing(dscrptr) ;
keep if _merge == 3 ;
drop _merge ;
keep d dscrptr ;
tempfile dn ;
save `dn' ;

use `exm', clear ;
merge m:1 cid using `keys', keepusing(setnb project_number cycle) ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;
forvalues k = 1/2 {;
    rename d`k' d ;
    merge m:1 d using `dn' ;
    assert _merge != 1 ;
    keep if _merge == 3 ;
    drop _merge ;
    rename (d dscrptr) (d`k' name`k') ;
} ;
gen int age = pyear - birth ;
gen str12 part = cond(shared, "shared", cond(isown, "own", cond(age <= 3, "new", "established"))) ;
gen str4 nf = cond(shared, "", cond(near, "near", "far")) ;
merge m:1 setnb project_number cycle using "${data}/build/risk_standout.dta", keepusing(frac_icirg_pair nb_abs) ;
keep if _merge == 3 ;
drop _merge ;
sort cid d1 d2 ;
compress ;
save "${data}/build/explore/standout_examples.dta", replace ;
display as result "=== the five example cycles: each pair of the single paper, and its status" ;
by cid: gen byte first = _n == 1 ;
levelsof cid, local(ex) ;
foreach c of local ex {;
    display _newline as result "--- cycle " `c' ;
    list setnb project_number cycle pmid pyear frac_icirg_pair nb_abs if cid == `c' & first, noobs clean ;
    list name1 name2 part nf age if cid == `c', noobs clean ;
} ;

/* -----------------------------------------------------------------------------
   11. A first look at the pieces, in the log
   ----------------------------------------------------------------------------- */
use `all', clear ;
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta",
    keepusing(in_sample sep renewed eval_year) ;
assert _merge != 1 ;
keep if _merge == 3 & in_sample & sep != 1 ;
drop _merge ;
display as result "=== analysis cycles with standing out" ;
count ;
display as result "=== with a baseline paper with MeSH (test 1)" ;
tab has_base ;
display as result "=== the parts, by renewal (cycles with a baseline)" ;
tabstat frac_icirg_pair so_own so_est so_new so_near so_far if has_base, by(renewed) stat(mean sd n) ;
display as result "=== the parts, all cycles with standing out" ;
tabstat frac_icirg_pair so_near so_far so_plac so_plac1 so_noct, by(renewed) stat(mean sd n) ;
display as result "=== the two-way split: new to her or not, shared with the pool or not (cycles with a baseline)" ;
gen double old_sh = 1 - so_own - piv_sh - piv_un if has_base ;
tabstat old_sh so_own piv_sh piv_un if has_base, by(renewed) stat(mean sd n) ;
display as result "=== the part new to PubMed at 1, 3 and 10 years" ;
tabstat so_new1 so_new so_new10 if has_base, stat(mean sd p50 n) ;
display as result "=== unique pairs on her earlier publications that are also at most 3 years old, share of her own part" ;
gen double w_own_young = w_own_new3 / w_own if w_own > 0 ;
summarize w_own_young ;
quietly summarize w_own_new3 if has_base ;
local a = r(sum) ;
quietly summarize w_own if has_base ;
display as result "pooled: " %6.4f `a' / r(sum) ;
display as result "=== check tags: share of pair instances with one, all and shared" ;
summarize ct_share ct_share_sh ;
display as result "share of the pools' tags that are check tags: " %6.4f scalar(ct_pool) ;
display as result "=== correlations" ;
correlate frac_icirg_pair so_own so_est so_new so_near so_far so_plac so_noct nb_abs if has_base ;
display as result "=== the pool's size, by decade of evaluation" ;
gen int decade = 10 * floor(eval_year / 10) ;
tabstat nb_abs, by(decade) stat(p10 p25 p50 p75 p90 mean n) ;
gen byte pool_bin = 1 if inrange(nb_abs, 20, 49) ;
replace pool_bin = 2 if inrange(nb_abs, 50, 99) ;
replace pool_bin = 3 if inrange(nb_abs, 100, 149) ;
replace pool_bin = 4 if inrange(nb_abs, 150, 199) ;
replace pool_bin = 5 if inrange(nb_abs, 200, 299) ;
replace pool_bin = 6 if nb_abs >= 300 & !missing(nb_abs) ;
display as result "=== the bins of the pool's size (20-49, 50-99, 100-149, 150-199, 200-299, 300+)" ;
tab pool_bin ;
display as result "=== pools of at least 50 and of at least 100" ;
count if nb_abs >= 50 ;
count if nb_abs >= 100 ;
display as result "=== standing out without check tags: defined for" ;
count if !missing(so_noct) ;

/* coverage by evaluation year, on analysis cycles with an acknowledging paper */
use setnb project_number cycle in_sample sep eval_year using "${data}/build/cycles.dta", clear ;
keep if in_sample & sep != 1 ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_standout.dta", keepusing(frac_icirg_pair) ;
assert _merge != 2 ;
gen byte has_so = _merge == 3 ;
drop _merge ;
tempfile cov ;
save `cov' ;
use setnb project_number cycle ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
bysort setnb project_number cycle: keep if _n == 1 ;
keep setnb project_number cycle ;
merge 1:1 setnb project_number cycle using `cov' ;
keep if _merge == 3 ;
drop _merge ;
display as result "=== share of analysis cycles with an acknowledging paper that have standing out, by evaluation year" ;
tabstat has_so, by(eval_year) stat(mean n) ;

/* facts for the definition: tags per application and twins, in the pools of
   the cycles with the measure */
use app_id ic irg_code year tag_src using "${data}/build/abstract_pool.dta", clear ;
keep if tag_src > 0 ;
tempfile tagged ;
save `tagged' ;
use ic irg_code eval_year setnb project_number cycle using "${data}/build/cycles.dta", clear ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_standout.dta", keepusing(frac_icirg_pair) ;
keep if _merge == 3 ;
keep ic irg_code eval_year ;
rename eval_year year ;
bysort ic irg_code year: keep if _n == 1 ;
merge 1:m ic irg_code year using `tagged' ;
keep if _merge == 3 ;
drop _merge ;
display as result "=== tagged applications in the pools of the cycles with the measure: own tags (1) or a twin's (2)" ;
tab tag_src ;
keep app_id ;
bysort app_id: keep if _n == 1 ;
merge 1:m app_id using "${data}/build/abstract_tags.dta" ;
keep if _merge == 3 ;
drop _merge ;
bysort app_id: gen int ntags = _N ;
bysort app_id: keep if _n == 1 ;
display as result "=== tags per tagged application in those pools" ;
summarize ntags, detail ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/32_standout_extras.do */
