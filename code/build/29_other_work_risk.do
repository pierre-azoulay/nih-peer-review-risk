/* =============================================================================
   code/build/29_other_work_risk.do

   Purpose: The risk of the investigator's other work, one row per cycle of the
            analysis file: three of the grant's risk measures computed on the
            investigator's other papers of the cycle's window, on all of them
            and on those acknowledging another of her grants, with the papers
            behind each. Appendix Tables G4 and G5 compare the risk of the
            grant's work with the risk of this other work
            (code/analysis/34_tables_G4_G5.do).
            - the window: the cycle's attributable span, span_start to
              eval_year, the window of the grant's measures;
            - the other work, the investigator's outside papers of
              code/build/28_team_distance.do (section 3, its count n_fout),
              rebuilt here: her Author-ity papers of the window, English
              original research, any author position, minus any paper linked
              to the focal grant in any year (ackn_links_unchecked.dta, before
              the author check) and minus the cycle's acknowledging papers.
              Papers written with her collaborators stay (28_team_distance.do
              removes them only when it compares her with each collaborator);
            - her other grants' work: the other work's papers that
              acknowledge another of her grants (ackn_links.dta, the same
              setnb, another project_number), the flag og of
              28_team_distance.do;
            - first- or last-author papers of the other work (for the log):
              first when author_postn is 1, last when it equals the paper's
              number of named authors, the rule of code/build/22_breadth.do;
            - the measures, as their builders compute them on the grant's
              acknowledging papers:
                tails       max minus min five-year citation percentile, at
                            least two papers with one (code/build/07_tails.do);
                disruption  highest disruption percentile, at least one
                            (code/build/08_disruption.do);
                pivoting    share of the papers' MeSH descriptor pairs absent
                            from the investigator's papers of cycle_yr - 5 to
                            cycle_yr - 1, the grant's own baseline, each pair
                            weighted by the number of papers carrying it;
                            defined when the baseline has a paper with MeSH
                            (code/build/09_pivoting.do);
              all on a 0-1 scale. Standing out is not computed: it measures
              the grant's work against the funded applications of the grant's
              own study section, and the investigator's other work has no
              study section of its own to be measured against.
              code/build/25_lagged_risk.do, sections 3 and 4, computes the
              same measures on the record before the cycle.
            - two checks, reported in the log: the same code run on the
              grant's acknowledging papers should return the stored measures
              (risk_tails, risk_disruption, risk_pivoting, in the analysis
              file), and the counts of the other work should equal those of
              code/build/28_team_distance.do (cycle_collabteam.dta).
            The output stays apart from the analysis file: 34_tables_G4_G5.do
            merges it in. Author-ity ends in 2018, so the other work thins for
            windows past 2018 (authority_partial).
            The last section describes the measures in the log: coverage, the
            number of other papers, the distributions of the measures on both
            sides, the raw correlations. No regression.

   Input:
     - ${data}/output/nih_risk_analysis.dta    (code/build/23_analysis_file.do)
     - ${data}/build/cycle_papers.dta          (code/build/03_cycle_papers.do)
     - ${data}/build/ackn_links_unchecked.dta, ackn_links.dta
                                               (code/build/02_ackn_links.do)
     - ${data}/build/paper_attributes.dta      (code/build/05_paper_attributes.do)
     - ${data}/build/cycle_collabteam.dta      (code/build/28_team_distance.do),
                                               for the check
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_nb_of_authors_2025.dta,
       overall_meshterms_2025.dta   PubMed 2025

   Output:
     - ${data}/build/risk_other.dta   one row per setnb x project_number x cycle

   Note: runs in batch. DuckDB: 8 threads, at most 24 GB of RAM, its spill
         folder duckdb_spill_nihrep_other in the system's temp folder.
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
log using "logs/29_other_work_risk.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles, and the grant's acknowledging papers
   ----------------------------------------------------------------------------- */
use setnb project_number cycle span_start eval_year cycle_yr author_id using "${data}/output/nih_risk_analysis.dta", clear ;
sort setnb project_number cycle ;
gen long cid = _n ;
count if span_start > eval_year ;
count if author_id == "" ;
tempfile keys ;
save `keys' ;

use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta" if ackn == 1, clear ;
merge m:1 setnb project_number cycle using `keys', keepusing(cid) ;
tab _merge ;
keep if _merge == 3 ;
keep cid pmid ;
gisid cid pmid ;
tempfile fa ;
save `fa' ;

/* -----------------------------------------------------------------------------
   2. Paper attributes: year, English original research, named authors
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
merge 1:1 pmid using "${pubmed_root}/pubmed/overall_nb_of_authors_2025.dta", keepusing(nb_authrs) ;
drop if _merge == 2 ;
drop _merge ;
keep pmid pubyear nb_authrs ;
compress ;
tempfile pm ;
save `pm' ;

/* -----------------------------------------------------------------------------
   3. The investigator's papers in the cycle's window (the other work) and in
      the five years before the cycle (the pivoting baseline)
   ----------------------------------------------------------------------------- */
use author_id using `keys', clear ;
bysort author_id: keep if _n == 1 ;
tempfile invid ;
save `invid' ;
use author_id pmid author_postn using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `invid' ;
keep if _merge == 3 ;
drop _merge ;
gcollapse (min) author_postn, by(author_id pmid) ;
merge m:1 pmid using `pm' ;
keep if _merge == 3 ;
drop _merge ;
preserve ;
use cid setnb project_number span_start eval_year cycle_yr author_id using `keys', clear ;
tempfile jk ;
save `jk' ;
restore ;
joinby author_id using `jk' ;
gen byte in_ow   = pubyear >= span_start & pubyear <= eval_year ;
gen byte in_base = pubyear >= cycle_yr - 5 & pubyear <= cycle_yr - 1 ;
keep if in_ow | in_base ;
display as result "=== papers in both windows (span_start before cycle_yr), cycle x paper" ;
count if in_ow & in_base ;
gisid cid pmid ;
preserve ;
keep if in_base ;
keep cid pmid ;
tempfile base ;
save `base' ;
restore ;
keep if in_ow ;
keep cid setnb project_number pmid author_postn nb_authrs ;

/* minus any paper linked to the focal grant, any year, before the author check */
preserve ;
use pmid project_number using "${data}/build/ackn_links_unchecked.dta", clear ;
gduplicates drop ;
gen byte gx = 1 ;
tempfile gack ;
save `gack' ;
restore ;
merge m:1 project_number pmid using `gack' ;
drop if _merge == 2 ;
drop _merge ;
display as result "=== window papers linked to the focal grant (dropped)" ;
count if gx == 1 ;
drop if gx == 1 ;
drop gx ;
/* minus the cycle's acknowledging papers */
merge 1:1 cid pmid using `fa' ;
display as result "=== window papers among the cycle's acknowledging papers (_merge 3, dropped)" ;
tab _merge ;
drop if _merge != 1 ;
drop _merge ;

/* og: the paper acknowledges another of her grants (author check passed) */
preserve ;
use setnb project_number pmid using "${data}/build/ackn_links.dta", clear ;
gduplicates drop ;
rename project_number opn ;
tempfile alnk ;
save `alnk' ;
restore ;
preserve ;
keep cid setnb project_number pmid ;
joinby setnb pmid using `alnk' ;
keep if opn != project_number ;
keep cid pmid ;
gduplicates drop ;
gen byte og = 1 ;
tempfile ogf ;
save `ogf' ;
restore ;
merge 1:1 cid pmid using `ogf' ;
assert _merge != 2 ;
drop _merge ;
replace og = 0 if og == . ;

/* first- or last-author papers (the rule of code/build/22_breadth.do) */
gen byte fl = author_postn == 1 | (author_postn == nb_authrs & nb_authrs < .) ;
display as result "=== the other work (cycle x paper): other grants' papers, first- or last-author papers" ;
tab og fl ;

/* the sets, one row per cycle x paper: s1 all the other work, s2 her other
   grants' work, s3 first- or last-author other work, s4 the grant's
   acknowledging papers (the check) */
gen byte s1 = 1 ;
gen byte s2 = og ;
gen byte s3 = fl ;
gen byte s4 = 0 ;
keep cid pmid s1 s2 s3 s4 ;
append using `fa' ;
replace s1 = 0 if s1 == . ;
replace s2 = 0 if s2 == . ;
replace s3 = 0 if s3 == . ;
replace s4 = 1 if s4 == . ;
gisid cid pmid ;
sort cid pmid ;
compress ;
tempfile cur ;
save `cur' ;

/* -----------------------------------------------------------------------------
   4. Tails and disruption on each set
   ----------------------------------------------------------------------------- */
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5_pctl di1_nok_pctl) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
tempfile curpa td ;
save `curpa' ;
forvalues k = 1/4 {;
    use if s`k' == 1 using `curpa', clear ;
    gcollapse (count) n_p = pmid n_t = cite5_pctl n_d = di1_nok_pctl
              (max) c5max = cite5_pctl dimax = di1_nok_pctl (min) c5min = cite5_pctl, by(cid) ;
    gen double tails = (c5max - c5min) / 100 if n_t >= 2 ;
    gen double disr  = dimax / 100 if n_d >= 1 ;
    keep cid n_p n_t n_d tails disr ;
    foreach v in n_p n_t n_d tails disr {;
        rename `v' `v'`k' ;
    } ;
    if `k' > 1 merge 1:1 cid using `td', nogen ;
    save `td', replace ;
} ;

/* -----------------------------------------------------------------------------
   5. Pivoting on each set, in DuckDB: the MeSH of every paper of a set or of
      the baseline, then the pairs, in eight slices of cycles
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
display as result "=== paper x descriptor rows for the sets' and the baselines' papers" ;
count ;
tempfile mesh ;
save `mesh' ;

tempfile pres ;
global l_cur  "`cur'" ;
global l_base "`base'" ;
global l_mesh "`mesh'" ;
global l_pres "`pres'" ;

#delimit cr
python:
import os, tempfile, traceback, time
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
def say(s):
    SFIToolkit.display(time.strftime("%H:%M:%S") + "  " + s)
spill = os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_other")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    _ = con.execute("SET threads=8")
    _ = con.execute("SET memory_limit='24GB'")
    _ = con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    _ = con.execute("SET preserve_insertion_order=false")
    cur = pd.read_stata(g("l_cur"), convert_categoricals=False)
    con.register("cur_df", cur)
    _ = con.execute("""CREATE TEMP TABLE cur AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid,
                       CAST(s1 AS INTEGER) s1, CAST(s2 AS INTEGER) s2, CAST(s3 AS INTEGER) s3, CAST(s4 AS INTEGER) s4 FROM cur_df""")
    con.unregister("cur_df")
    del cur
    base = pd.read_stata(g("l_base"), convert_categoricals=False)
    con.register("base_df", base)
    _ = con.execute("CREATE TEMP TABLE base AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM base_df")
    con.unregister("base_df")
    del base
    mesh = pd.read_stata(g("l_mesh"), convert_categoricals=False)
    con.register("mesh_df", mesh)
    _ = con.execute("CREATE TEMP TABLE mesh AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.unregister("mesh_df")
    del mesh
    _ = con.execute("CREATE TEMP TABLE mp AS SELECT DISTINCT pmid FROM mesh")
    say("set rows: {:,}; baseline rows: {:,}; MeSH rows: {:,}".format(
        con.execute("SELECT count(*) FROM cur").fetchone()[0],
        con.execute("SELECT count(*) FROM base").fetchone()[0],
        con.execute("SELECT count(*) FROM mesh").fetchone()[0]))
    _ = con.execute("""CREATE TEMP TABLE wres (cid INTEGER, w_all1 DOUBLE, w_new1 DOUBLE, w_all2 DOUBLE, w_new2 DOUBLE,
                       w_all3 DOUBLE, w_new3 DOUBLE, w_all4 DOUBLE, w_new4 DOUBLE)""")
    K = 8
    for k in range(K):
        _ = con.execute("CREATE OR REPLACE TEMP TABLE cs AS SELECT * FROM cur WHERE cid % {} = {}".format(K, k))
        _ = con.execute("CREATE OR REPLACE TEMP TABLE bs AS SELECT * FROM base WHERE cid % {} = {}".format(K, k))
        # the sets' pairs, each weighted by the number of the set's papers carrying it
        _ = con.execute("""CREATE OR REPLACE TEMP TABLE cp AS
            SELECT c.cid, a.d AS d1, b.d AS d2, sum(c.s1) f1, sum(c.s2) f2, sum(c.s3) f3, sum(c.s4) f4
            FROM cs c JOIN mesh a ON a.pmid = c.pmid JOIN mesh b ON b.pmid = c.pmid AND a.d < b.d
            GROUP BY c.cid, a.d, b.d""")
        # the baseline's pairs that some set of the cycle also has
        _ = con.execute("""CREATE OR REPLACE TEMP TABLE bp AS
            SELECT DISTINCT b.cid, x.d AS d1, y.d AS d2
            FROM bs b JOIN mesh x ON x.pmid = b.pmid JOIN mesh y ON y.pmid = b.pmid AND x.d < y.d
            SEMI JOIN cp ON cp.cid = b.cid AND cp.d1 = x.d AND cp.d2 = y.d""")
        _ = con.execute("""INSERT INTO wres
            SELECT cp.cid,
                   CAST(sum(f1) AS DOUBLE), CAST(coalesce(sum(f1) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE),
                   CAST(sum(f2) AS DOUBLE), CAST(coalesce(sum(f2) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE),
                   CAST(sum(f3) AS DOUBLE), CAST(coalesce(sum(f3) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE),
                   CAST(sum(f4) AS DOUBLE), CAST(coalesce(sum(f4) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE)
            FROM cp LEFT JOIN bp ON bp.cid = cp.cid AND bp.d1 = cp.d1 AND bp.d2 = cp.d2
            GROUP BY cp.cid""")
        say("slice {} of {}: cycles with a pair so far {:,}".format(k + 1, K, con.execute("SELECT count(*) FROM wres").fetchone()[0]))
    pres = con.execute("""
        WITH nm AS (SELECT cid, sum(s1) nm1, sum(s2) nm2, sum(s3) nm3, sum(s4) nm4 FROM cur SEMI JOIN mp USING (pmid) GROUP BY cid),
             nb AS (SELECT cid, count(*) n_base_mesh FROM base SEMI JOIN mp USING (pmid) GROUP BY cid),
             ids AS (SELECT cid FROM nm UNION SELECT cid FROM nb UNION SELECT cid FROM wres)
        SELECT CAST(cid AS INTEGER) cid, w.w_all1, w.w_new1, w.w_all2, w.w_new2, w.w_all3, w.w_new3, w.w_all4, w.w_new4,
               CAST(coalesce(nm.nm1, 0) AS INTEGER) nm1, CAST(coalesce(nm.nm2, 0) AS INTEGER) nm2,
               CAST(coalesce(nm.nm3, 0) AS INTEGER) nm3, CAST(coalesce(nm.nm4, 0) AS INTEGER) nm4,
               CAST(coalesce(nb.n_base_mesh, 0) AS INTEGER) n_base_mesh
        FROM ids LEFT JOIN wres w USING (cid) LEFT JOIN nm USING (cid) LEFT JOIN nb USING (cid)
        ORDER BY cid""").df()
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
say("cycles with a set paper with MeSH, a baseline paper with MeSH or a pair: {:,}".format(len(pres)))
pres.to_stata(g("l_pres"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   6. Assemble, check against the grant's stored measures and against the
      counts of code/build/28_team_distance.do, save
   ----------------------------------------------------------------------------- */
use `pres', clear ;
forvalues k = 1/4 {;
    gen double pivot`k' = w_new`k' / w_all`k' if n_base_mesh > 0 & w_all`k' > 0 & w_all`k' < . ;
} ;
keep cid pivot1 pivot2 pivot3 pivot4 nm1 nm2 nm3 nm4 n_base_mesh ;
merge 1:1 cid using `td' ;
drop _merge ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
assert _merge != 1 ;
drop _merge ;
foreach v in n_p n_t n_d nm {;
    forvalues k = 1/4 {;
        replace `v'`k' = 0 if `v'`k' == . ;
    } ;
} ;
replace n_base_mesh = 0 if n_base_mesh == . ;

display as result _newline "=== CHECK 1: the code run on the grant's acknowledging papers against the stored measures" ;
rename n_base_mesh nbm ;
merge 1:1 setnb project_number cycle using "${data}/output/nih_risk_analysis.dta",
    keepusing(spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair n_tails n_disr n_cur_mesh n_base_mesh n_ackn)
    gen(m_an) ;
assert m_an == 3 ;
drop m_an ;
rename n_base_mesh n_base_mesh_g ;
rename nbm n_base_mesh ;
gen byte d_tails = (missing(tails4) != missing(spread_minmax_ackn)) | (abs(tails4 - spread_minmax_ackn) > 1e-9 & !missing(tails4)) ;
gen byte d_disr  = (missing(disr4) != missing(di1nok_ackn_maxpctl)) | (abs(disr4 - di1nok_ackn_maxpctl) > 1e-9 & !missing(disr4)) ;
gen byte d_pivot = (missing(pivot4) != missing(frac_setnb_pair)) | (abs(pivot4 - frac_setnb_pair) > 1e-9 & !missing(pivot4)) ;
gen byte d_n     = n_p4 != n_ackn | (n_t4 != n_tails & n_tails < .) | (n_d4 != n_disr & n_disr < .) | (nm4 != n_cur_mesh & n_cur_mesh < .) ;
display as text "cycles where the recomputed measure differs from the stored one (tails, disruption, pivoting, paper counts):" ;
tabstat d_tails d_disr d_pivot d_n, stat(sum n) ;
display as text "pivoting baseline: papers with MeSH, recomputed against stored, where the stored is defined" ;
count if n_base_mesh_g < . & n_base_mesh != n_base_mesh_g ;
summarize tails4 spread_minmax_ackn disr4 di1nok_ackn_maxpctl pivot4 frac_setnb_pair ;
drop d_* tails4 disr4 pivot4 n_p4 n_t4 n_d4 nm4 spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair n_tails n_disr n_cur_mesh n_base_mesh_g n_ackn ;

display as result _newline "=== CHECK 2: the other work against the counts of 28_team_distance.do (cycle_collabteam.dta: n_fout, n_fout_og)" ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_collabteam.dta", keepusing(n_fout n_fout_og) ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
count if n_p1 != n_fout ;
count if n_p2 != n_fout_og ;
summarize n_p1 n_fout n_p2 n_fout_og ;
drop n_fout n_fout_og ;

/* names: ow all the other work, og her other grants' work, fl first- or
   last-author other work */
local s1 "ow" ;
local s2 "og" ;
local s3 "fl" ;
local w1 "the other work" ;
local w2 "other grants' work" ;
local w3 "first- or last-author other work" ;
forvalues k = 1/3 {;
    local s "`s`k''" ;
    rename tails`k' `s'_tails ;
    rename disr`k'  `s'_disr ;
    rename pivot`k' `s'_pivot ;
    rename n_p`k'   n_`s' ;
    rename n_t`k'   n_`s'_tails ;
    rename n_d`k'   n_`s'_disr ;
    rename nm`k'    n_`s'_mesh ;
    label var `s'_tails   "Tails (0-1) on `w`k''" ;
    label var `s'_disr    "Disruption (0-1) on `w`k''" ;
    label var `s'_pivot   "Pivoting on `w`k'', against the grant's baseline" ;
    label var n_`s'       "Papers of `w`k''" ;
    label var n_`s'_tails "Papers of `w`k'' with a citation percentile" ;
    label var n_`s'_disr  "Papers of `w`k'' with a disruption percentile" ;
    label var n_`s'_mesh  "Papers of `w`k'' with MeSH" ;
} ;
label var n_base_mesh "Pivoting baseline: papers of cycle_yr - 5 to cycle_yr - 1 with MeSH" ;
keep setnb project_number cycle ow_* og_* fl_* n_ow* n_og* n_fl* n_base_mesh ;
order setnb project_number cycle ow_tails ow_disr ow_pivot og_tails og_disr og_pivot fl_tails fl_disr fl_pivot
      n_ow n_ow_tails n_ow_disr n_ow_mesh n_og n_og_tails n_og_disr n_og_mesh n_fl n_fl_tails n_fl_disr n_fl_mesh n_base_mesh ;
label data "Risk of the investigator's other work, nih_risk" ;
notes: Built `c(current_date)' by code/build/29_other_work_risk.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_other.dta", replace ;

/* -----------------------------------------------------------------------------
   7. A first look, in the log: coverage, the number of other papers, the
      distributions and the correlations of the measures. No regression
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/output/nih_risk_analysis.dta",
    keepusing(eval_year log_meanjif_all authority_partial n_ackn n_noackn
              spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair) ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
rename spread_minmax_ackn g_tails ;
rename di1nok_ackn_maxpctl g_disr ;
rename frac_setnb_pair g_pivot ;
gen byte blk = cond(eval_year <= 1995, 1, cond(eval_year <= 2008, 2, 3)) ;
capture label drop blk ;
label define blk 1 "1981-1995" 2 "1996-2008" 3 "2009 on" ;
label values blk blk ;
local ml1 "tails" ;
local ml2 "disr" ;
local ml3 "pivot" ;
local mn1 "Extreme tail outcomes" ;
local mn2 "Disruption" ;
local mn3 "Pivoting" ;
forvalues j = 1/3 {;
    local m "`ml`j''" ;
    /* Table 2's cycles for the measure: the measure and the output controls defined */
    gen byte t2_`m' = !missing(g_`m') & !missing(log_meanjif_all) ;
    foreach s in ow og fl {;
        gen byte h`s'_`m' = !missing(`s'_`m') ;
    } ;
} ;

display as result _newline "=== 7a. coverage: share of Table 2's cycles with the measure on the other work (all, other grants, first- or last-author)" ;
forvalues j = 1/3 {;
    local m "`ml`j''" ;
    display as result "--- `mn`j''" ;
    tabstat how_`m' hog_`m' hfl_`m' if t2_`m', stat(mean sum n) ;
    tabstat how_`m' hog_`m' hfl_`m' if t2_`m', by(blk) stat(mean n) ;
} ;
display as result "--- coverage by the flag for windows past 2018 (tails)" ;
tabstat how_tails hog_tails if t2_tails, by(authority_partial) stat(mean n) ;

display as result _newline "=== 7b. the number of other papers per cycle: all analysis cycles, then Table 2's tails cycles" ;
summarize n_ow n_og n_fl n_noackn, detail ;
summarize n_ow n_og n_fl if t2_tails, detail ;
tabstat n_ow n_og n_fl, stat(mean p10 p25 p50 p75 p90 n) ;
tabstat n_ow n_og n_fl, by(blk) stat(mean p50 n) ;
quietly summarize n_og ;
local s_og = r(sum) ;
quietly summarize n_fl ;
local s_fl = r(sum) ;
quietly summarize n_ow ;
display as result "share of the other work acknowledging another of her grants: " %5.3f `s_og' / r(sum)
    ", first- or last-author: " %5.3f `s_fl' / r(sum) ;
foreach k in 1 2 3 5 10 {;
    quietly count if n_ow >= `k' ;
    local a = r(N) / _N ;
    quietly count if n_og >= `k' ;
    local b = r(N) / _N ;
    display as text "cycles with at least `k' other papers: all " %5.3f `a' ", other grants " %5.3f `b' ;
} ;
display as text "correlation of the count of other papers with Table 2's count of other papers (n_noackn)" ;
correlate n_ow n_noackn ;

display as result _newline "=== 7c. the measures on the grant's work and on the other work, on the cycles where each is defined (0-1 scale)" ;
forvalues j = 1/3 {;
    local m "`ml`j''" ;
    display as result "--- `mn`j'': Table 2's cycles, then the grant's measure where the other work's is defined" ;
    tabstat g_`m' ow_`m' og_`m' fl_`m' if t2_`m', stat(mean sd p10 p25 p50 p75 p90 n) ;
    tabstat g_`m' if t2_`m' & how_`m', stat(mean sd p50 n) ;
    tabstat g_`m' if t2_`m' & hog_`m', stat(mean sd p50 n) ;
} ;
display as result "--- papers behind each measure on the other work, Table 2's cycles where it is defined" ;
tabstat n_ow_tails if t2_tails & how_tails, stat(mean p50 n) ;
tabstat n_ow_disr if t2_disr & how_disr, stat(mean p50 n) ;
tabstat n_ow_mesh if t2_pivot & how_pivot, stat(mean p50 n) ;
tabstat n_og_tails if t2_tails & hog_tails, stat(mean p50 n) ;
tabstat n_og_disr if t2_disr & hog_disr, stat(mean p50 n) ;
tabstat n_og_mesh if t2_pivot & hog_pivot, stat(mean p50 n) ;

display as result _newline "=== 7d. raw correlations of the grant's measure with the same measure on the other work, Table 2's cycles" ;
forvalues j = 1/3 {;
    local m "`ml`j''" ;
    display as result "--- `mn`j''" ;
    pwcorr g_`m' ow_`m' og_`m' fl_`m' if t2_`m', obs ;
    spearman g_`m' ow_`m' if t2_`m' ;
    spearman g_`m' og_`m' if t2_`m' ;
} ;
display as result "--- the three measures on the other work, among themselves (all the other work)" ;
pwcorr ow_tails ow_disr ow_pivot g_tails g_disr g_pivot, obs ;
display as result "--- the count of papers against each measure (all the other work)" ;
gen double l_ow = ln(n_ow) if n_ow > 0 ;
pwcorr l_ow ow_tails ow_disr ow_pivot, obs ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/29_other_work_risk.do */
