/* =============================================================================
   code/build/24_risk_windows.do

   Purpose: The four risk measures computed on the early and the late years of
            each cycle, and the output controls of each part of the cycle, for
            Appendix Table G1 (code/analysis/31_table_G1.do).
            - parts: early = the first two years of the attributable span
              (span_start, span_start + 1); late = the last two years
              (eval_year - 1, eval_year); middle = the years between, none
              when the span is four years;
            - cycles: the analysis sample (in_sample, sep != 1) whose span is at
              least four years, so that the windows do not overlap;
            - each measure follows its builder exactly, on the cycle's
              acknowledging papers of the part: tails (07_tails.do, at least
              two papers with a citation percentile), disruption
              (08_disruption.do), pivoting (09_pivoting.do, the same five-year
              baseline, fixed at the cycle's start), standing out
              (12_standing_out.do, the same pool of the evaluation year, at
              least 20 other tagged applications and a pair weight above 5
              within the part); the output controls follow 06_cycle_output.do;
            - the file recomputes these definitions on its own, so it computes
              the whole cycle too (suffix _f) and stops unless the whole-cycle
              version of each measure equals the stored one (section 7).
            It also keeps the highest, median and lowest citation percentile of
            each window (c5max_*, c5med_*, c5min_*), which tell whether a
            change in tails comes from the top or from the bottom of the
            window's papers.

   Input:
     - ${data}/build/cycles.dta             (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta       (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta   (code/build/05_paper_attributes.do)
     - ${data}/build/risk_tails.dta (code/build/07_tails.do),
       risk_disruption.dta (08_disruption.do), risk_pivoting.dta
       (09_pivoting.do), risk_standout.dta (12_standing_out.do): the check
     - ${data}/build/abstract_pool.dta, abstract_tags.dta, mti_vocab.dta
                                            (code/build/11_abstract_tags.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity: the
       authors of each PubMed paper
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_meshterms_2025.dta   PubMed 2025:
       year, type, language and MeSH descriptors of each paper
     - ${input}/cgaf_nih_risk.dta   investigators of every application

   Output:
     - ${data}/build/risk_windows.dta   one row per setnb x project_number x cycle

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
log using "logs/24_risk_windows.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles: the analysis sample with a span of at least four years
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr span_start eval_year author_id ic irg_code
    in_sample sep using "${data}/build/cycles.dta", clear ;
keep if in_sample & sep != 1 ;
gen int span_len = eval_year - span_start + 1 ;
display as result "=== analysis-sample cycles by span length" ;
tab span_len ;
keep if span_len >= 4 ;
sort setnb project_number cycle ;
gen long cid = _n ;
gen byte so_cycle = irg_code != "" ;
tempfile keys ;
save `keys' ;

/* -----------------------------------------------------------------------------
   2. The cycle's papers, with their part: 0 every paper, 1 early, 2 late,
      3 middle (part 0 repeats every paper of parts 1 to 3)
   ----------------------------------------------------------------------------- */
use setnb project_number cycle pmid ackn pubyear using "${data}/build/cycle_papers.dta", clear ;
merge m:1 setnb project_number cycle using `keys', keepusing(cid span_start eval_year) ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
assert pubyear >= span_start & pubyear <= eval_year ;
gen byte part = cond(pubyear <= span_start + 1, 1, cond(pubyear >= eval_year - 1, 2, 3)) ;
merge m:1 pmid using "${data}/build/paper_attributes.dta",
    keepusing(cite5_pctl di1_nok_pctl jif journal_hs) ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;
tempfile pap ;
save `pap' ;

/* -----------------------------------------------------------------------------
   3. Tails and disruption, by part (acknowledging papers)
   ----------------------------------------------------------------------------- */
use cid pmid part ackn cite5_pctl di1_nok_pctl using `pap' if ackn == 1, clear ;
expand 2, generate(dup) ;
replace part = 0 if dup ;
drop dup ;
keep if part <= 2 ;
gen double c5 = cite5_pctl ;
gen double di = di1_nok_pctl ;
gcollapse (count) n_tails = c5 n_disr = di (max) c5max = c5 dimax = di (min) c5min = c5
          (median) c5med = c5, by(cid part) ;
gen double tails = (c5max - c5min) / 100 if n_tails >= 2 ;
gen double disr  = dimax / 100 if n_disr >= 1 ;
/* the two ends and the median of the citation percentiles, on the domain of
   tails, which tell whether a change in tails comes from the top or from the
   bottom of the window's papers */
foreach v in c5max c5med c5min {;
    replace `v' = cond(n_tails >= 2, `v' / 100, .) ;
} ;
keep cid part n_tails tails c5max c5med c5min n_disr disr ;
tempfile td ;
save `td' ;

/* -----------------------------------------------------------------------------
   4. Output controls by part (every paper of the window, as
      code/build/06_cycle_output.do)
   ----------------------------------------------------------------------------- */
use cid part ackn jif journal_hs using `pap', clear ;
keep if part >= 1 ;
gen byte one_ackn  = ackn == 1 ;
gen byte one_noack = ackn == 0 ;
gen byte hs_ackn   = journal_hs * (ackn == 1) ;
gen byte hs_noackn = journal_hs * (ackn == 0) ;
gcollapse (sum) n_ackn = one_ackn n_noackn = one_noack (mean) meanjif = jif
          (max) hs_ackn hs_noackn, by(cid part) ;
tempfile oc ;
save `oc' ;

/* -----------------------------------------------------------------------------
   5. Pivoting and standing out, by part, in DuckDB
   ----------------------------------------------------------------------------- */
/* current papers: acknowledging, parts 0 to 2 */
use cid pmid part ackn using `pap' if ackn == 1, clear ;
expand 2, generate(dup) ;
replace part = 0 if dup ;
drop dup ackn ;
keep if part <= 2 ;
gisid cid part pmid ;
tempfile cur ;
save `cur' ;

/* baseline papers, exactly as code/build/09_pivoting.do, section 3: the
   investigator's Author-ity papers, English original research, published in
   the five years before the cycle's first year (cycle_yr - 5 to cycle_yr - 1) */
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

use author_id using `keys', clear ;
drop if author_id == "" ;
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
joinby author_id using `keys' ;
keep if pubyear >= cycle_yr - 5 & pubyear <= cycle_yr - 1 ;
keep cid pmid ;
gisid cid pmid ;
tempfile base ;
save `base' ;

/* MeSH of every current or baseline paper */
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

/* standing out: the cells and the investigators' own pool applications, as
   code/build/12_standing_out.do, sections 1 and 2 */
use cid setnb ic irg_code eval_year so_cycle using `keys' if so_cycle, clear ;
rename eval_year year ;
keep cid setnb ic irg_code year ;
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

tempfile pres bres sres ;
global w_cur   "`cur'" ;
global w_base  "`base'" ;
global w_mesh  "`mesh'" ;
global w_cyc   "`cyc'" ;
global w_pool  "`pool'" ;
global w_own   "`own'" ;
global w_tags  "${data}/build/abstract_tags.dta" ;
global w_vocab "${data}/build/mti_vocab.dta" ;
global w_pres  "`pres'" ;
global w_bres  "`bres'" ;
global w_sres  "`sres'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
frames = {
    "cur":   pd.read_stata(g("w_cur")),
    "base":  pd.read_stata(g("w_base")),
    "mesh":  pd.read_stata(g("w_mesh"), convert_categoricals=False),
    "cyc":   pd.read_stata(g("w_cyc")),
    "pool":  pd.read_stata(g("w_pool"), convert_categoricals=False),
    "own":   pd.read_stata(g("w_own")),
    "tags":  pd.read_stata(g("w_tags"), convert_categoricals=False),
    "vocab": pd.read_stata(g("w_vocab"), convert_categoricals=False),
}
spill = g("nr_spill") or os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_windows")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=6")
    con.execute("SET memory_limit='10GB'")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    for k, df in frames.items():
        con.register(k + "_df", df)
    con.execute("CREATE TEMP TABLE cur  AS SELECT CAST(cid AS INTEGER) cid, CAST(part AS INTEGER) part, CAST(pmid AS INTEGER) pmid FROM cur_df")
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

    # ---- pivoting (09_pivoting.do), by cycle and part
    con.execute("CREATE TEMP TABLE pp AS SELECT a.pmid, a.d AS d1, b.d AS d2 FROM mesh a JOIN mesh b ON a.pmid = b.pmid AND a.d < b.d")
    con.execute("""CREATE TEMP TABLE cp AS
        SELECT c.cid, c.part, p.d1, p.d2, count(*) AS freq FROM cur c JOIN pp p USING (pmid) GROUP BY ALL""")
    con.execute("""CREATE TEMP TABLE bp AS
        SELECT DISTINCT b.cid, p.d1, p.d2 FROM base b JOIN pp p USING (pmid)
        SEMI JOIN cp ON cp.cid = b.cid AND cp.d1 = p.d1 AND cp.d2 = p.d2""")
    pres = con.execute("""
        WITH sh AS (
            SELECT cp.cid, cp.part, CAST(sum(cp.freq) AS DOUBLE) AS w_all,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE) AS w_new
            FROM cp LEFT JOIN bp ON bp.cid = cp.cid AND bp.d1 = cp.d1 AND bp.d2 = cp.d2
            GROUP BY cp.cid, cp.part),
        np AS (SELECT c.cid, c.part, count(DISTINCT c.pmid) AS n_piv FROM cur c SEMI JOIN pp USING (pmid) GROUP BY ALL)
        SELECT CAST(sh.cid AS INTEGER) cid, CAST(sh.part AS INTEGER) part, sh.w_all, sh.w_new, CAST(np.n_piv AS INTEGER) n_piv
        FROM sh JOIN np ON np.cid = sh.cid AND np.part = sh.part ORDER BY cid, part""").df()
    bres = con.execute("""SELECT CAST(cid AS INTEGER) cid, CAST(count(DISTINCT pmid) AS INTEGER) AS n_base_mesh
        FROM base SEMI JOIN mesh USING (pmid) GROUP BY cid ORDER BY cid""").df()
    con.execute("DROP TABLE pp"); con.execute("DROP TABLE cp"); con.execute("DROP TABLE bp")

    # ---- standing out (12_standing_out.do), by cycle and part
    con.execute("CREATE TEMP TABLE scur AS SELECT c.* FROM cur c SEMI JOIN cyc USING (cid)")
    con.execute("CREATE TEMP TABLE meshv AS SELECT m.pmid, m.d FROM mesh m SEMI JOIN vocab ON vocab.d = m.d")
    con.execute("""CREATE TEMP TABLE sp AS
        SELECT c.cid, c.part, c.pmid, a.d AS d1, b.d AS d2
        FROM scur c JOIN meshv a ON a.pmid = c.pmid JOIN meshv b ON b.pmid = c.pmid AND a.d < b.d""")
    con.execute("CREATE TEMP TABLE scp AS SELECT cid, part, d1, d2, count(*) AS freq FROM sp GROUP BY ALL")
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
            SELECT s.cid, s.part, CAST(sum(s.freq) AS DOUBLE) AS w_all,
                   CAST(coalesce(sum(s.freq) FILTER (WHERE coalesce(c.n, 0) - coalesce(o.n_own, 0) = 0), 0) AS DOUBLE) AS w_uniq
            FROM scp s JOIN cyc y ON y.cid = s.cid
            LEFT JOIN cnt c ON c.ic = y.ic AND c.irg_code = y.irg_code AND c.yr = y.yr AND c.d1 = s.d1 AND c.d2 = s.d2
            LEFT JOIN owncnt o ON o.cid = s.cid AND o.d1 = s.d1 AND o.d2 = s.d2
            GROUP BY s.cid, s.part),
        np AS (SELECT cid, part, count(DISTINCT pmid) AS n_so FROM sp GROUP BY ALL)
        SELECT CAST(w.cid AS INTEGER) cid, CAST(w.part AS INTEGER) part, w.w_all, w.w_uniq,
               CAST(np.n_so AS INTEGER) n_so, CAST(coalesce(s.nb_abs, 0) AS INTEGER) nb_abs
        FROM w JOIN np ON np.cid = w.cid AND np.part = w.part
        LEFT JOIN psize s ON s.cid = w.cid ORDER BY cid, part""").df()
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("pivoting rows: {:,}; baseline cycles: {:,}; standing-out rows: {:,}".format(len(pres), len(bres), len(sres)))
pres.to_stata(g("w_pres"), write_index=False)
bres.to_stata(g("w_bres"), write_index=False)
sres.to_stata(g("w_sres"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   6. Assemble: one row per cycle, measures by part (_f whole cycle, _e early,
      _l late) and output controls by part (_e, _l, _m)
   ----------------------------------------------------------------------------- */
use `pres', clear ;
merge m:1 cid using `bres' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
replace n_base_mesh = 0 if n_base_mesh == . ;
gen double pivot = w_new / w_all if n_base_mesh > 0 & w_all > 0 & w_all < . ;
keep cid part pivot n_piv ;
tempfile piv ;
save `piv' ;

use `sres', clear ;
gen double so = w_uniq / w_all if nb_abs >= 20 & w_all > 5 ;
keep cid part so n_so ;
tempfile so ;
save `so' ;

use `td', clear ;
merge 1:1 cid part using `piv' ;
drop _merge ;
merge 1:1 cid part using `so' ;
drop _merge ;
gen str1 sfx = cond(part == 0, "f", cond(part == 1, "e", "l")) ;
drop part ;
reshape wide n_tails tails c5max c5med c5min n_disr disr pivot n_piv so n_so, i(cid) j(sfx) string ;
foreach v in n_tails tails c5max c5med c5min n_disr disr pivot n_piv so n_so {;
    foreach s in f e l {;
        capture confirm variable `v'`s' ;
        if _rc == 0 rename `v'`s' `v'_`s' ;
        else        gen double `v'_`s' = . ;
    } ;
} ;
tempfile meas ;
save `meas' ;

/* output controls by part: zeros where the part has no paper; the log mean
   impact factor set to 0 with an indicator where no paper of the part has one,
   so that a part without papers keeps its cycle in the regression; counts in
   the bins of code/build/06_cycle_output.do */
use `oc', clear ;
gen str1 sfx = cond(part == 1, "e", cond(part == 2, "l", "m")) ;
drop part ;
reshape wide n_ackn n_noackn meanjif hs_ackn hs_noackn, i(cid) j(sfx) string ;
tempfile ocw ;
save `ocw' ;

use cid setnb project_number cycle span_len using `keys', clear ;
merge 1:1 cid using `meas' ;
tab _merge ;
assert _merge != 2 ;
drop _merge ;
merge 1:1 cid using `ocw' ;
tab _merge ;
assert _merge != 2 ;
drop _merge ;
capture label drop npapers ;
label define npapers 0 "0" 1 "1" 2 "2" 3 "3" 4 "4" 5 "5" 6 "6-7" 8 "8-10" 11 "11-15" 16 "16-20" 21 "21+" ;
foreach s in e l m {;
    foreach v in n_ackn n_noackn hs_ackn hs_noackn meanjif {;
        capture confirm variable `v'`s' ;
        if _rc gen double `v'`s' = . ;
        rename `v'`s' `v'_`s' ;
    } ;
    foreach v in n_ackn n_noackn hs_ackn hs_noackn {;
        replace `v'_`s' = 0 if `v'_`s' == . ;
    } ;
    gen byte nojif_`s' = meanjif_`s' == . ;
    gen double ljif_`s' = cond(nojif_`s', 0, ln(meanjif_`s')) ;
    foreach k in ackn noackn {;
        gen byte bin_`k'_`s' = cond(n_`k'_`s' <= 5, n_`k'_`s', cond(n_`k'_`s' <= 7, 6,
            cond(n_`k'_`s' <= 10, 8, cond(n_`k'_`s' <= 15, 11, cond(n_`k'_`s' <= 20, 16, 21))))) ;
        label values bin_`k'_`s' npapers ;
    } ;
    drop meanjif_`s' ;
} ;
foreach v in n_tails n_disr n_piv n_so {;
    foreach s in f e l {;
        replace `v'_`s' = 0 if `v'_`s' == . ;
    } ;
} ;

/* -----------------------------------------------------------------------------
   7. The check: the whole-cycle versions equal the stored measures
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/risk_tails.dta", keepusing(spread_minmax_ackn) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_disruption.dta", keepusing(di1nok_ackn_maxpctl) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_pivoting.dta", keepusing(frac_setnb_pair) ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_standout.dta", keepusing(frac_icirg_pair) ;
drop if _merge == 2 ;
drop _merge ;
display as result "=== check: whole-cycle versions against the stored measures (both missing, or equal within 1e-9)" ;
local j = 0 ;
foreach p in "tails_f spread_minmax_ackn" "disr_f di1nok_ackn_maxpctl" "pivot_f frac_setnb_pair" "so_f frac_icirg_pair" {;
    local a : word 1 of `p' ;
    local b : word 2 of `p' ;
    count if missing(`a') != missing(`b') | (abs(`a' - `b') > 1e-9 & !missing(`a')) ;
    display as result "`a' vs `b': " r(N) " discrepancies" ;
    assert r(N) == 0 ;
} ;
drop spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair ;

/* -----------------------------------------------------------------------------
   8. Save, and a first look
   ----------------------------------------------------------------------------- */
foreach s in f e l {;
    local w = cond("`s'" == "f", "whole cycle", cond("`s'" == "e", "early window", "late window")) ;
    label var tails_`s'   "Tails, `w' (0-1)" ;
    label var c5max_`s'   "Highest citation percentile, `w' (0-1, where tails is defined)" ;
    label var c5med_`s'   "Median citation percentile, `w' (0-1, where tails is defined)" ;
    label var c5min_`s'   "Lowest citation percentile, `w' (0-1, where tails is defined)" ;
    label var disr_`s'    "Disruption, `w' (0-1)" ;
    label var pivot_`s'   "Pivoting, `w'" ;
    label var so_`s'      "Standing out, `w'" ;
    label var n_tails_`s' "Acknowledging papers with a citation percentile, `w'" ;
    label var n_disr_`s'  "Acknowledging papers with a disruption index, `w'" ;
    label var n_piv_`s'   "Acknowledging papers with a MeSH pair, `w'" ;
    label var n_so_`s'    "Acknowledging papers with a MeSH pair in the MTI vocabulary, `w'" ;
} ;
foreach s in e l m {;
    local w = cond("`s'" == "e", "early window", cond("`s'" == "l", "late window", "middle years")) ;
    label var n_ackn_`s'     "Acknowledging papers, `w'" ;
    label var n_noackn_`s'   "Other papers, `w'" ;
    label var bin_ackn_`s'   "Acknowledging papers in the bins of the output controls, `w'" ;
    label var bin_noackn_`s' "Other papers in the bins of the output controls, `w'" ;
    label var ljif_`s'       "ln(mean impact factor + 1), `w', 0 if none" ;
    label var nojif_`s'      "No paper with an impact factor, `w'" ;
    label var hs_ackn_`s'    "An acknowledging paper in NEJM, Science, Cell or Nature, `w'" ;
    label var hs_noackn_`s'  "Another paper in NEJM, Science, Cell or Nature, `w'" ;
} ;
label var span_len "Years in the attributable span, span_start to eval_year" ;
drop cid ;
order setnb project_number cycle span_len ;
label data "Risk measures by window and output controls by part of the cycle, nih_risk" ;
notes: Built `c(current_date)' by code/build/24_risk_windows.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_windows.dta", replace ;

display as result "=== cycles, and the measures defined in each version" ;
count ;
summarize tails_* disr_* pivot_* so_* ;
display as result "=== papers by part (means)" ;
tabstat n_ackn_e n_ackn_l n_ackn_m n_noackn_e n_noackn_l n_noackn_m, stat(mean p50) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/24_risk_windows.do */
