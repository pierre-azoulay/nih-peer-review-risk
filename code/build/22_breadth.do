/* =============================================================================
   code/build/22_breadth.do

   Purpose: the breadth of the investigator's earlier research, a trait of
            Figure 5 and Appendix Table I1, one row per analysis-sample cycle.
            The breadth window of a cycle holds the investigator's Author-ity
            papers, English original research (the filters of the pivoting
            baseline, code/build/09_pivoting.do, section 3), published in
            cycle_yr - 5 to cycle_yr - 1, indexed with at least one MeSH
            descriptor, and not acknowledging the focal grant (any pmid of
            ackn_links.dta with the same project_number, whatever the cycle or
            the investigator). n_pre counts the window's papers on which she
            is first or last author (last: author_postn equal to the paper's
            number of named authors in PubMed 2025); n_pre_any counts them at
            any position.
            Sections 1 to 6: the window and the counts.
            Sections 7 to 9: breadth_pre, the mean over pairs of the window's
            first- or last-author papers of one minus the cosine similarity
            of their TF-IDF MeSH vectors, for cycles with n_pre >= 5; at most
            50 papers, drawn at random with a fixed seed. IDF on PubMed 2025,
            by publication year, the pair taking the year of its later paper.
            Two checks are saved apart: breadth on nested random subsets of
            5, 10 and 20 papers (cycles with n_pre >= 20), and the pooled
            percentiles of the pairwise dissimilarities.

   Input:
     - ${data}/build/cycles.dta               (code/build/01_cycles.do)
                                              the analysis sample, cycle_yr,
                                              author_id
     - ${data}/build/cycle_controls.dta       (code/build/04_cycle_controls.do)
                                              cycle_nb
     - ${data}/build/cycle_output.dta         (code/build/06_cycle_output.do)
                                              log_meanjif_all
     - ${data}/build/risk_tails.dta           (code/build/07_tails.do)
     - ${data}/build/risk_disruption.dta      (code/build/08_disruption.do)
     - ${data}/build/risk_pivoting.dta        (code/build/09_pivoting.do)
     - ${data}/build/risk_standout.dta        (code/build/12_standing_out.do)
     - ${data}/build/cycle_investigator.dta   (code/build/19_investigator_flags.do)
                                              new_inv, esi
     - ${data}/build/ackn_links.dta           (code/build/02_ackn_links.do)
                                              papers acknowledging each grant
     - ${pubmed_root}/authority/authority_pmids_clean.dta   author_id pmid author_postn
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_meshterms_2025.dta,
       overall_nb_of_authors_2025.dta

   Output:
     - ${data}/build/cycle_breadth.dta        one row per analysis cycle:
       breadth_pre, n_pre, npairs_pre, n_pre_any, n_excl, n_excl_any
     - ${data}/build/explore/breadth_window.dta   cycle x window paper, with flags
     - ${data}/build/explore/breadth_counts.dta   one row per cycle: the counts
     - ${data}/build/explore/breadth_subsample.dta  breadth on nested random 5,
       10 and 20 papers, cycles with n_pre >= 20
     - ${data}/build/explore/breadth_pairpctl.dta   pooled percentiles of d_pq,
       Table 2 sample cycles

   Note: DuckDB: 3 threads, 5 GB, spill in the system's temp folder
         (duckdb_spill_nihrep_breadth); the global nr_spill, if set,
         overrides it. Sums of floating-point numbers are exact decimal
         sums (DECIMAL(38,18)), so that they do not depend on the order in
         which DuckDB's threads finish: two runs give identical files.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set processors 3 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/22_breadth.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles: the analysis sample, with a numeric key
   ----------------------------------------------------------------------------- */
/* the analysis sample, with the variables this file needs, read from the
   build files that code/build/23_analysis_file.do merges: the same cycles
   (in_sample & sep != 1) and the same values as in the analysis file, which
   cannot be read here since it merges this file's output */
use setnb project_number cycle in_sample sep using "${data}/build/cycles.dta", clear ;
keep if in_sample & sep != 1 ;
drop in_sample sep ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_controls.dta", keepusing(cycle_nb) ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_investigator.dta", keepusing(new_inv esi) ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_output.dta", keepusing(log_meanjif_all) ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;
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
order setnb project_number cycle cycle_nb new_inv esi log_meanjif_all
      spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair ;
sort setnb project_number cycle ;
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta",
    keepusing(cycle_yr author_id) ;
tab _merge ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;
sort setnb project_number cycle ;
gen long cid = _n ;
gen byte t2s = !missing(log_meanjif_all) & (!missing(spread_minmax_ackn) | !missing(di1nok_ackn_maxpctl)
               | !missing(frac_setnb_pair) | !missing(frac_icirg_pair)) ;
label variable t2s "In the Table 2 sample of at least one measure (with a mean impact factor)" ;
drop spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair log_meanjif_all ;
tempfile keys ;
save `keys' ;
display as result "=== cycles; without an Author-ity identifier; window past 2018 (cycle_yr > 2019)" ;
count ;
count if author_id == "" ;
count if cycle_yr > 2019 ;

/* -----------------------------------------------------------------------------
   2. English original research in PubMed 2025, with its year
      (code/build/09_pivoting.do, section 3)
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
tempfile pyr ;
save `pyr' ;
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

/* -----------------------------------------------------------------------------
   3. The window: the investigator's papers of cycle_yr - 5 to cycle_yr - 1,
      with her position in the author list
   ----------------------------------------------------------------------------- */
use author_id using `keys', clear ;
drop if author_id == "" ;
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
joinby author_id using `keys' ;
keep if pubyear >= cycle_yr - 5 & pubyear <= cycle_yr - 1 ;
keep cid project_number pmid pubyear author_postn ;
gisid cid pmid ;
display as result "=== window papers, any position, before the MeSH and focal-grant filters (cycle x paper)" ;
count ;
tempfile win ;
save `win' ;

/* papers needed below */
keep pmid ;
bysort pmid: keep if _n == 1 ;
tempfile need ;
save `need' ;

/* -----------------------------------------------------------------------------
   4. Flags: MeSH, number of authors, the focal grant
   ----------------------------------------------------------------------------- */
/* one pass over the MeSH file, in four slices of PMIDs so that no more than
   a quarter of it is in memory (code/build/10_pivoting_extras.do, section 0):
   - the descriptors of the window papers;
   - the inverse document frequency of each descriptor by publication year,
     over every PubMed 2025 paper with MeSH: idf = ln(N_y / n_dy), N_y the
     year's papers with a descriptor, n_dy those carrying d */
local cut0 = 0 ;
local cut1 = 10000000 ;
local cut2 = 20000000 ;
local cut3 = 30000000 ;
local cut4 = 1e12 ;
tempfile wmesh ndy ny ;
forvalues s = 1/4 {;
    local lo = `cut`=`s'-1'' ;
    local hi = `cut`s'' ;
    use pmid dscrptr_ui if pmid >= `lo' & pmid < `hi'
        using "${pubmed_root}/pubmed/overall_meshterms_2025.dta", clear ;
    drop if missing(dscrptr_ui) | missing(pmid) ;
    gcontract pmid dscrptr_ui ;
    drop _freq ;
    preserve ;
    merge m:1 pmid using `need' ;
    keep if _merge == 3 ;
    drop _merge ;
    if `s' > 1 append using `wmesh' ;
    save `wmesh', replace ;
    restore ;
    merge m:1 pmid using `pyr' ;
    keep if _merge == 3 ;
    drop _merge ;
    gegen byte tp = tag(pmid) ;
    preserve ;
    gcollapse (sum) N_y = tp, by(pubyear) ;
    if `s' > 1 append using `ny' ;
    save `ny', replace ;
    restore ;
    gcollapse (count) n_dy = pmid, by(dscrptr_ui pubyear) ;
    if `s' > 1 append using `ndy' ;
    save `ndy', replace ;
    display as result "slice `s' done" ;
} ;
use `ny', clear ;
gcollapse (sum) N_y, by(pubyear) ;
save `ny', replace ;
use `ndy', clear ;
gcollapse (sum) n_dy, by(dscrptr_ui pubyear) ;
merge m:1 pubyear using `ny' ;
assert _merge == 3 ;
drop _merge ;
gen double idf = ln(N_y / n_dy) ;
display as result "=== IDF by year: papers with MeSH per year, and the weights" ;
tabstat N_y if pubyear >= 1975 & pubyear <= 2018 & mod(pubyear, 5) == 0, by(pubyear) stat(mean) ;
summarize idf, detail ;
keep dscrptr_ui pubyear idf ;
rename pubyear y ;
tempfile idf ;
save `idf' ;
use `ny', clear ;
gen double idfmax = ln(N_y) ;
rename pubyear y ;
keep y idfmax ;
tempfile idfmax ;
save `idfmax' ;

use pmid using `wmesh', clear ;
gcontract pmid ;
drop _freq ;
gen byte has_mesh = 1 ;
tempfile hasm ;
save `hasm' ;

/* number of named authors; a pmid may carry several records: keep the last */
use pmid nb_authrs cnt_mismatch filenb seq using "${pubmed_root}/pubmed/overall_nb_of_authors_2025.dta", clear ;
merge m:1 pmid using `need' ;
keep if _merge == 3 ;
drop _merge ;
display as result "=== records per pmid in overall_nb_of_authors_2025 (window papers)" ;
bysort pmid: gen int nrec = _N ;
tab nrec ;
sort pmid filenb seq ;
by pmid: keep if _n == _N ;
keep pmid nb_authrs cnt_mismatch ;
tempfile nau ;
save `nau' ;

/* papers acknowledging each grant (author check passed), any cycle, any
   investigator of the grant */
use project_number pmid using "${data}/build/ackn_links.dta", clear ;
bysort project_number pmid: keep if _n == 1 ;
gen byte excl = 1 ;
tempfile foc ;
save `foc' ;

use `win', clear ;
merge m:1 pmid using `hasm' ;
drop if _merge == 2 ;
drop _merge ;
replace has_mesh = 0 if has_mesh == . ;
merge m:1 pmid using `nau' ;
display as result "=== window papers without an author count" ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge m:1 project_number pmid using `foc' ;
drop if _merge == 2 ;
drop _merge ;
replace excl = 0 if excl == . ;

gen byte first = author_postn == 1 ;
gen byte last  = author_postn == nb_authrs & nb_authrs < . ;
gen byte fl    = first | last ;
display as result "=== position against the author count (Author-ity position beyond PubMed's count)" ;
gen byte beyond = author_postn > nb_authrs & nb_authrs < . ;
tab beyond ;
tab cnt_mismatch, missing ;
display as result "=== first, last, single-author (nb_authrs == 1), among papers with MeSH" ;
tab first last if has_mesh ;
count if has_mesh & nb_authrs == 1 ;

label variable has_mesh "Paper has at least one MeSH descriptor" ;
label variable excl     "Paper acknowledges the focal grant (any cycle)" ;
label variable fl       "Investigator is first or last author" ;
keep cid pmid pubyear author_postn nb_authrs has_mesh excl first last fl ;
sort cid pmid ;
compress ;
save "${data}/build/explore/breadth_window.dta", replace ;

/* -----------------------------------------------------------------------------
   5. Counts per cycle
   ----------------------------------------------------------------------------- */
gen byte k_fl  = fl & has_mesh & !excl ;
gen byte k_any = has_mesh & !excl ;
gen byte x_fl  = fl & has_mesh & excl ;
gen byte x_any = has_mesh & excl ;
gcollapse (sum) n_pre = k_fl n_pre_any = k_any n_excl = x_fl n_excl_any = x_any, by(cid) ;
merge 1:1 cid using `keys' ;
assert _merge != 1 ;
drop _merge ;
foreach v in n_pre n_pre_any n_excl n_excl_any {;
    replace `v' = 0 if `v' == . ;
} ;
label variable n_pre      "Window papers, first or last author, MeSH, not the focal grant" ;
label variable n_pre_any  "Window papers, any position, MeSH, not the focal grant" ;
label variable n_excl     "First- or last-author papers removed as the focal grant's" ;
label variable n_excl_any "Any-position papers removed as the focal grant's" ;
sort cid ;
compress ;
save "${data}/build/explore/breadth_counts.dta", replace ;

/* -----------------------------------------------------------------------------
   6. The counts on the Table 2 sample, in the log: by group of investigators
      (all, new, early-stage, other), for all cycles, first cycles and later
      cycles
   ----------------------------------------------------------------------------- */
keep if t2s ;
gen byte g_all = 1 ;
gen byte g_new = new_inv == 1 ;
gen byte g_esi = esi == 1 ;
gen byte g_oth = new_inv == 0 & esi == 0 ;
foreach a in fl any {;
    local v = cond("`a'" == "fl", "n_pre", "n_pre_any") ;
    gen byte ge5_`a'  = `v' >= 5 ;
    gen byte ge10_`a' = `v' >= 10 ;
} ;
display as result "=== overlap of new and early-stage investigators (Table 2 sample)" ;
tab new_inv esi, missing ;
forvalues c = 0/2 {;
    if `c' == 0 local cond "1" ;
    if `c' == 1 local cond "cycle_nb == 1" ;
    if `c' == 2 local cond "cycle_nb >= 2 & cycle_nb < ." ;
    if `c' == 0 local cl "All cycles" ;
    if `c' == 1 local cl "First cycles" ;
    if `c' == 2 local cl "Later cycles" ;
    display _newline as result "==================== Window counts: `cl' ====================" ;
    display as text "group | cycles | mean n_pre (f/l) | mean n_pre (any) | >=5 f/l | >=5 any | >=10 f/l | >=10 any | papers removed f/l | removed any" ;
    foreach g in all new esi oth {;
        quietly count if g_`g' & `cond' ;
        local N = r(N) ;
        local nn = strtrim(string(`N', "%9.0fc")) ;
        local out "`g' | `nn'" ;
        foreach v in n_pre n_pre_any ge5_fl ge5_any ge10_fl ge10_any n_excl n_excl_any {;
            quietly summarize `v' if g_`g' & `cond' ;
            local mm = strtrim(string(r(mean), "%6.3f")) ;
            local out "`out' | `mm'" ;
        } ;
        display as result "`out'" ;
    } ;
} ;
display _newline as result "=== distribution of n_pre (first or last) and n_pre_any, Table 2 sample" ;
summarize n_pre n_pre_any, detail ;

/* -----------------------------------------------------------------------------
   7. The papers of the index: first or last author, MeSH, not the focal
      grant, cycles with n_pre >= 5. A random order within the cycle (fixed
      seed) caps the index at 50 papers and gives the nested subsets of 5, 10
      and 20 papers on which breadth is recomputed in section 8.
   ----------------------------------------------------------------------------- */
use cid pmid pubyear fl has_mesh excl using "${data}/build/explore/breadth_window.dta", clear ;
keep if fl & has_mesh & !excl ;
merge m:1 cid using "${data}/build/explore/breadth_counts.dta", keepusing(n_pre t2s) ;
assert _merge != 1 ;
keep if _merge == 3 & n_pre >= 5 ;
drop _merge ;
sort cid pmid ;
set seed 20261010 ;
gen double u = runiform() ;
sort cid u ;
by cid: gen int rk = _n ;
keep if rk <= 50 ;
keep cid pmid pubyear rk t2s ;
display as result "=== papers in the index (cycle x paper), cycles" ;
count ;
gegen byte tc = tag(cid) ;
count if tc ;
drop tc ;
tempfile wp ;
save `wp' ;
keep pmid ;
bysort pmid: keep if _n == 1 ;
merge 1:m pmid using `wmesh' ;
keep if _merge == 3 ;
drop _merge ;
tempfile mesh ;
save `mesh' ;

/* -----------------------------------------------------------------------------
   8. Pairwise dissimilarities, in DuckDB. For a pair (p, q) of the same
      cycle, y is the later paper's year; w_p holds the year-y IDF of p's
      descriptors (a descriptor absent from year y takes ln(N_y), as if one
      paper carried it); d_pq = 1 - sum over shared descriptors of idf^2 /
      (||w_p|| ||w_q||). A pair shared by several cycles of an investigator
      is computed once.
   ----------------------------------------------------------------------------- */
tempfile cres pres ;
global l_wp     "`wp'" ;
global l_mesh   "`mesh'" ;
global l_idf    "`idf'" ;
global l_idfmax "`idfmax'" ;
global l_cres   "`cres'" ;
global l_pres   "`pres'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
frames = {
    "wp":     pd.read_stata(g("l_wp")),
    "mesh":   pd.read_stata(g("l_mesh"), convert_categoricals=False),
    "idf":    pd.read_stata(g("l_idf"), convert_categoricals=False),
    "idfmax": pd.read_stata(g("l_idfmax")),
}
spill = g("nr_spill") or os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_breadth")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=3")
    con.execute("SET memory_limit='5GB'")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    for k, df in frames.items():
        con.register(k + "_df", df)
    con.execute("CREATE TEMP TABLE wp AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid, CAST(pubyear AS INTEGER) y, CAST(rk AS INTEGER) rk, CAST(t2s AS INTEGER) t2s FROM wp_df")
    con.execute("CREATE TEMP TABLE mesh AS SELECT DISTINCT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.execute("CREATE TEMP TABLE idf AS SELECT CAST(dscrptr_ui AS INTEGER) d, CAST(y AS INTEGER) y, CAST(idf AS DOUBLE) idf FROM idf_df")
    con.execute("CREATE TEMP TABLE idfmax AS SELECT CAST(y AS INTEGER) y, CAST(idfmax AS DOUBLE) idfmax FROM idfmax_df")
    for k in frames:
        con.unregister(k + "_df")
    del frames

    con.execute("""CREATE TEMP TABLE pr AS
        SELECT a.cid, a.pmid AS p, b.pmid AS q, a.rk AS ra, b.rk AS rb, greatest(a.y, b.y) AS y, a.t2s
        FROM wp a JOIN wp b ON a.cid = b.cid AND a.pmid < b.pmid""")
    con.execute("CREATE TEMP TABLE u AS SELECT DISTINCT p, q, y FROM pr")
    con.execute("CREATE TEMP TABLE nd AS SELECT DISTINCT pmid, y FROM (SELECT p AS pmid, y FROM u UNION ALL SELECT q AS pmid, y FROM u)")
    con.execute("""CREATE TEMP TABLE nrm AS
        SELECT nd.pmid, nd.y, CAST(sum(CAST(power(coalesce(i.idf, x.idfmax), 2) AS DECIMAL(38,18))) AS DOUBLE) AS n2
        FROM nd JOIN mesh m ON m.pmid = nd.pmid
        JOIN idfmax x ON x.y = nd.y
        LEFT JOIN idf i ON i.d = m.d AND i.y = nd.y
        GROUP BY nd.pmid, nd.y""")
    con.execute("""CREATE TEMP TABLE sh AS
        SELECT u.p, u.q, u.y, CAST(sum(CAST(power(coalesce(i.idf, x.idfmax), 2) AS DECIMAL(38,18))) AS DOUBLE) AS s
        FROM u JOIN mesh a ON a.pmid = u.p
        JOIN mesh b ON b.pmid = u.q AND b.d = a.d
        JOIN idfmax x ON x.y = u.y
        LEFT JOIN idf i ON i.d = a.d AND i.y = u.y
        GROUP BY u.p, u.q, u.y""")
    con.execute("""CREATE TEMP TABLE dd AS
        SELECT u.p, u.q, u.y,
               CASE WHEN np.n2 > 0 AND nq.n2 > 0
                    THEN 1 - coalesce(sh.s, 0) / sqrt(np.n2 * nq.n2) END AS d
        FROM u LEFT JOIN sh ON sh.p = u.p AND sh.q = u.q AND sh.y = u.y
        JOIN nrm np ON np.pmid = u.p AND np.y = u.y
        JOIN nrm nq ON nq.pmid = u.q AND nq.y = u.y""")
    chk = con.execute("SELECT count(*), count(d), min(d), max(d) FROM dd").fetchone()
    SFIToolkit.display("distinct pairs: {:,}; with d: {:,}; min d {:.6f}; max d {:.6f}".format(*chk))
    npr = con.execute("SELECT count(*) FROM pr").fetchone()[0]
    SFIToolkit.display("cycle x pair rows: {:,}".format(npr))
    # means as exact decimal sums over counts (sum / count is avg)
    cres = con.execute("""
        SELECT pr.cid,
               CAST(sum(CAST(dd.d AS DECIMAL(38,18))) AS DOUBLE) / count(dd.d) AS b_all, count(dd.d) AS np_all,
               CAST(sum(CAST(dd.d AS DECIMAL(38,18))) FILTER (WHERE pr.ra <= 5 AND pr.rb <= 5) AS DOUBLE)
                   / count(dd.d) FILTER (WHERE pr.ra <= 5 AND pr.rb <= 5) AS s5,
               CAST(sum(CAST(dd.d AS DECIMAL(38,18))) FILTER (WHERE pr.ra <= 10 AND pr.rb <= 10) AS DOUBLE)
                   / count(dd.d) FILTER (WHERE pr.ra <= 10 AND pr.rb <= 10) AS s10,
               CAST(sum(CAST(dd.d AS DECIMAL(38,18))) FILTER (WHERE pr.ra <= 20 AND pr.rb <= 20) AS DOUBLE)
                   / count(dd.d) FILTER (WHERE pr.ra <= 20 AND pr.rb <= 20) AS s20
        FROM pr JOIN dd ON dd.p = pr.p AND dd.q = pr.q AND dd.y = pr.y
        GROUP BY pr.cid ORDER BY pr.cid""").df()
    pres = con.execute("""
        SELECT count(dd.d) AS npairs,
               quantile_cont(dd.d, 0.10) AS p10, quantile_cont(dd.d, 0.25) AS p25,
               quantile_cont(dd.d, 0.50) AS p50, quantile_cont(dd.d, 0.75) AS p75,
               quantile_cont(dd.d, 0.90) AS p90,
               CAST(sum(CAST(dd.d AS DECIMAL(38,18))) AS DOUBLE) / count(dd.d) AS mean,
               CAST(sum(CASE WHEN dd.d >= 0.9 THEN 1 ELSE 0 END) AS DOUBLE) / count(*) AS share_ge90,
               CAST(sum(CASE WHEN dd.d >= 0.999999 THEN 1 ELSE 0 END) AS DOUBLE) / count(*) AS share_1
        FROM pr JOIN dd ON dd.p = pr.p AND dd.q = pr.q AND dd.y = pr.y
        WHERE pr.t2s = 1""").df()
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("cycles with an index: {:,}".format(len(cres)))
cres.to_stata(g("l_cres"), write_index=False)
pres.to_stata(g("l_pres"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   9. Save: the cycle file, the subsamples, the pooled percentiles of d_pq
   ----------------------------------------------------------------------------- */
use `pres', clear ;
display as result "=== pooled pairwise dissimilarities, Table 2 sample cycles" ;
list, noobs abbreviate(12) ;
compress ;
save "${data}/build/explore/breadth_pairpctl.dta", replace ;

use "${data}/build/explore/breadth_counts.dta", clear ;
merge 1:1 cid using `cres' ;
assert _merge != 2 ;
drop _merge ;
gen double breadth_pre = b_all if n_pre >= 5 ;
gen int npairs_pre = np_all if n_pre >= 5 ;
assert !missing(breadth_pre) if n_pre >= 5 ;
assert npairs_pre == comb(min(n_pre, 50), 2) if n_pre >= 5 ;
foreach k in 5 10 20 {;
    gen double breadth_s`k' = s`k' if n_pre >= 20 ;
} ;
label variable breadth_pre "Breadth: mean TF-IDF cosine dissimilarity over pairs of window papers (n_pre >= 5)" ;
label variable npairs_pre  "Pairs behind breadth_pre (at most 50 papers, 1,225 pairs)" ;
label variable breadth_s5  "Breadth on a random 5 of the window papers (n_pre >= 20)" ;
label variable breadth_s10 "Breadth on a random 10 (nested, n_pre >= 20)" ;
label variable breadth_s20 "Breadth on a random 20 (nested, n_pre >= 20)" ;

preserve ;
keep if n_pre >= 20 ;
keep setnb project_number cycle breadth_pre breadth_s5 breadth_s10 breadth_s20 ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/explore/breadth_subsample.dta", replace ;
restore ;

keep setnb project_number cycle n_pre n_pre_any n_excl n_excl_any breadth_pre npairs_pre ;
order setnb project_number cycle breadth_pre n_pre npairs_pre ;
label data "Investigator breadth, one row per analysis-sample cycle" ;
notes: Built `c(current_date)' by code/build/22_breadth.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_breadth.dta", replace ;

display as result "=== first look: breadth_pre, and its rank correlation with n_pre" ;
summarize breadth_pre, detail ;
spearman breadth_pre n_pre ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/22_breadth.do */
