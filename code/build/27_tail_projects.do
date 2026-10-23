/* =============================================================================
   code/build/27_tail_projects.do

   Purpose: The tail measure taken apart, for Appendix Tables B1
            (code/analysis/23_table_B1.do) and B2 (code/analysis/24_table_B2.do):
            the median citation percentile of the cycle's acknowledging papers
            and the two half-spreads (max minus median, median minus min); and
            the grouping of each cycle's papers into projects, which splits the
            lower half-spread into a part between projects and a part within
            the project of the weakest paper.
            - papers: the cycle's acknowledging papers with a citation
              percentile, those of the tail measure (code/build/07_tails.do),
              in the analysis-sample cycles with at least three of them;
            - projects, definition A: two papers are linked when the TF-IDF
              cosine similarity of their MeSH descriptors is at least tau
              (0.3, 0.5 or 0.7); projects are the connected groups; a paper
              without MeSH, or linked to none, is a project of its own. IDF
              over all PubMed 2025 papers with MeSH, as
              code/build/10_pivoting_extras.do; every descriptor of a paper
              counts once;
            - projects, definition B: papers with the same first author
              (author_postn == 1 in Author-ity); a paper whose first author
              is not in Author-ity is a project of its own;
            - the split: the weakest paper's project (ties at the minimum go
              to the project with the highest lead, the conservative choice);
              its lead is its best paper; median - min = (median - lead) +
              (lead - min), the between and the within parts.
            The file stops unless the count of papers and their lowest and
            highest percentiles equal those of risk_tails.dta (section 4).

   Input:
     - ${data}/build/cycles.dta             (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta       (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta   (code/build/05_paper_attributes.do)
     - ${data}/build/risk_tails.dta         (code/build/07_tails.do), the cycles
                                            and the check
     - ${pubmed_root}/pubmed/overall_meshterms_2025.dta   MeSH descriptors of
       PubMed 2025
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity: the
       authors of each PubMed paper and their position

   Output:
     - ${data}/build/risk_tail_projects.dta   one row per setnb x project_number x cycle

   Note: DuckDB with 3 threads and a 5 GB limit; a few minutes.
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
log using "logs/27_tail_projects.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   0. Inverse document frequency of each descriptor over PubMed 2025, as
      code/build/10_pivoting_extras.do, section 0 (four slices of PMIDs)
   ----------------------------------------------------------------------------- */
local cut0 = 0 ;
local cut1 = 10000000 ;
local cut2 = 20000000 ;
local cut3 = 30000000 ;
local cut4 = 1e12 ;
tempfile idfacc ;
local npap = 0 ;
forvalues s = 1/4 {;
    local lo = `cut`=`s'-1'' ;
    local hi = `cut`s'' ;
    use pmid dscrptr_ui if pmid >= `lo' & pmid < `hi'
        using "${pubmed_root}/pubmed/overall_meshterms_2025.dta", clear ;
    drop if missing(dscrptr_ui) | missing(pmid) ;
    gcontract pmid dscrptr_ui ;
    gegen byte tp = tag(pmid) ;
    quietly count if tp ;
    local npap = `npap' + r(N) ;
    gcollapse (count) n_d = pmid, by(dscrptr_ui) ;
    if `s' > 1 append using `idfacc' ;
    save `idfacc', replace ;
} ;
gcollapse (sum) n_d, by(dscrptr_ui) ;
gen double idf = ln(`npap' / n_d) ;
display as result "=== PubMed 2025 papers with MeSH: " %14.0fc `npap' ;
keep dscrptr_ui idf ;
tempfile idf ;
save `idf' ;

/* -----------------------------------------------------------------------------
   1. Cycles: the analysis sample with at least three papers with a percentile
   ----------------------------------------------------------------------------- */
use setnb project_number cycle in_sample sep using "${data}/build/cycles.dta", clear ;
keep if in_sample & sep != 1 ;
merge 1:1 setnb project_number cycle using "${data}/build/risk_tails.dta",
    keepusing(n_tails max_pctl_ackn min_pctl_ackn p50_pctl_ackn) ;
drop if _merge == 2 ;
drop _merge ;
keep if n_tails >= 3 & n_tails < . ;
sort setnb project_number cycle ;
gen long cid = _n ;
keep cid setnb project_number cycle n_tails max_pctl_ackn min_pctl_ackn p50_pctl_ackn ;
tempfile keys ;
save `keys' ;
display as result "=== cycles with at least three papers with a citation percentile" ;
count ;

/* -----------------------------------------------------------------------------
   2. Their papers, with percentile, MeSH (and IDF) and first author
   ----------------------------------------------------------------------------- */
use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta" if ackn == 1, clear ;
merge m:1 setnb project_number cycle using `keys', keepusing(cid) ;
keep if _merge == 3 ;
drop _merge ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5_pctl) ;
drop if _merge == 2 ;
drop _merge ;
keep if cite5_pctl < . ;
keep cid pmid cite5_pctl ;
gisid cid pmid ;
tempfile pap ;
save `pap' ;

keep pmid ;
bysort pmid: keep if _n == 1 ;
tempfile need ;
save `need' ;
use pmid dscrptr_ui using "${pubmed_root}/pubmed/overall_meshterms_2025.dta", clear ;
merge m:1 pmid using `need' ;
keep if _merge == 3 ;
drop _merge ;
bysort pmid dscrptr_ui: keep if _n == 1 ;
merge m:1 dscrptr_ui using `idf' ;
keep if _merge == 3 ;
drop _merge ;
tempfile mesh ;
save `mesh' ;

use author_id pmid author_postn if author_postn == 1
    using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 pmid using `need' ;
keep if _merge == 3 ;
drop _merge author_postn ;
bysort pmid (author_id): keep if _n == 1 ;
rename author_id first_author ;
tempfile fa ;
save `fa' ;
use `pap', clear ;
merge m:1 pmid using `fa' ;
drop if _merge == 2 ;
drop _merge ;
display as result "=== papers, and those without a first author in Author-ity" ;
count ;
count if first_author == "" ;
save `pap', replace ;

/* -----------------------------------------------------------------------------
   3. Similarities, projects and the split, in DuckDB and pandas
   ----------------------------------------------------------------------------- */
tempfile res ;
global t_pap   "`pap'" ;
global t_mesh  "`mesh'" ;
global t_res   "`res'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import numpy as np
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
pap  = pd.read_stata(g("t_pap"))
mesh = pd.read_stata(g("t_mesh"), convert_categoricals=False)
spill = g("nr_spill") or os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_tailproj")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=3")
    con.execute("SET memory_limit='5GB'")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    con.register("pap_df", pap)
    con.register("mesh_df", mesh)
    con.execute("CREATE TEMP TABLE pap AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM pap_df")
    con.execute("CREATE TEMP TABLE w AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d, CAST(idf AS DOUBLE) w FROM mesh_df")
    con.unregister("pap_df"); con.unregister("mesh_df")
    con.execute("CREATE TEMP TABLE nrm AS SELECT pmid, sqrt(sum(w*w)) AS nr FROM w GROUP BY pmid")
    con.execute("CREATE TEMP TABLE cw AS SELECT p.cid, p.pmid, w.d, w.w FROM pap p JOIN w USING (pmid)")
    # cosine of every pair of a cycle's papers sharing a descriptor; keep pairs at 0.3 or more
    edges = con.execute("""
        WITH dot AS (
            SELECT a.cid, a.pmid AS p1, b.pmid AS p2, sum(a.w * b.w) AS dp
            FROM cw a JOIN cw b ON a.cid = b.cid AND a.d = b.d AND a.pmid < b.pmid
            GROUP BY ALL)
        SELECT dot.cid, dot.p1, dot.p2, dot.dp / (n1.nr * n2.nr) AS cs
        FROM dot JOIN nrm n1 ON n1.pmid = dot.p1 JOIN nrm n2 ON n2.pmid = dot.p2
        WHERE dot.dp / (n1.nr * n2.nr) >= 0.3""").df()
    nomesh = con.execute("SELECT count(*) FROM pap WHERE pmid NOT IN (SELECT pmid FROM nrm)").fetchone()[0]
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("paper pairs with cosine >= 0.3: {:,}; papers without MeSH: {:,}".format(len(edges), nomesh))

# connected components by union-find, for each threshold
def components(nodes, e):
    parent = {n: n for n in nodes}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a, b in e:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    return {n: find(n) for n in nodes}

pap["key"] = list(zip(pap["cid"].astype(int), pap["pmid"].astype(int)))
nodes = pap["key"].tolist()
for tau, tag in [(0.3, "m3"), (0.5, "m5"), (0.7, "m7")]:
    sub = edges[edges["cs"] >= tau]
    e = zip(zip(sub["cid"].astype(int), sub["p1"].astype(int)), zip(sub["cid"].astype(int), sub["p2"].astype(int)))
    lab = components(nodes, e)
    pap["lab_" + tag] = [str(lab[k][1]) for k in nodes]
# definition B: first author, or the paper itself
fa = pap["first_author"].fillna("").astype(str)
pap["lab_fa"] = np.where(fa != "", "A" + fa, "P" + pap["pmid"].astype(int).astype(str))

# per cycle and definition: projects and the split of median - min
pap["pctl"] = pap["cite5_pctl"].astype(float) / 100.0
out = pap.groupby("cid").agg(n=("pctl", "size"), pmin=("pctl", "min"), pmax=("pctl", "max"), pmed=("pctl", "median")).reset_index()
for tag in ["m3", "m5", "m7", "fa"]:
    lab = "lab_" + tag
    proj = pap.groupby(["cid", lab]).agg(lead=("pctl", "max"), size=("pctl", "size")).reset_index()
    pp = pap[["cid", lab, "pctl"]].merge(proj, on=["cid", lab])
    pp = pp.merge(out[["cid", "pmin"]], on="cid")
    weak = pp[pp["pctl"] == pp["pmin"]].merge(pap[["cid", lab, "pctl", "pmid"]], on=["cid", lab, "pctl"])
    weak = weak.sort_values(["cid", "lead", "pmid"], ascending=[True, False, True]).drop_duplicates("cid")
    weak = weak[["cid", "lead", "size", "pmid"]].rename(columns={"lead": "lead_" + tag, "size": "wsize_" + tag, "pmid": "wpmid_" + tag})
    ps = proj.groupby("cid").agg(**{"nproj_" + tag: ("size", "size"), "ppp_" + tag: ("size", "mean"),
                                   "single_" + tag: ("size", lambda s: (s == 1).mean())}).reset_index()
    out = out.merge(weak, on="cid").merge(ps, on="cid")
out.to_stata(g("t_res"), write_index=False)
SFIToolkit.display("cycles: {:,}".format(len(out)))
end
#delimit ;

/* -----------------------------------------------------------------------------
   4. The variables, the checks, save
   ----------------------------------------------------------------------------- */
use `res', clear ;
merge 1:1 cid using `keys' ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
display as result "=== check: papers and order statistics equal those of risk_tails.dta" ;
assert n == n_tails ;
assert abs(pmin - min_pctl_ackn) < 1e-6 & abs(pmax - max_pctl_ackn) < 1e-6 ;
count if abs(pmed - p50_pctl_ackn) > 1e-6 ;
gen double tl_med = pmed ;
gen double tl_up  = pmax - pmed ;
gen double tl_lo  = pmed - pmin ;
foreach t in m3 m5 m7 fa {;
    gen double tl_lo_btw_`t' = pmed - lead_`t' ;
    gen double tl_lo_wth_`t' = lead_`t' - pmin ;
    assert abs(tl_lo_btw_`t' + tl_lo_wth_`t' - tl_lo) < 1e-9 ;
    gen byte multi_`t' = wsize_`t' > 1 ;
    label var tl_lo_btw_`t' "Lower half-spread between projects (`t'): median minus lead of the weakest paper's project" ;
    label var tl_lo_wth_`t' "Lower half-spread within projects (`t'): that lead minus the minimum" ;
    label var nproj_`t'     "Projects in the cycle (`t')" ;
    label var ppp_`t'       "Mean papers per project (`t')" ;
    label var single_`t'    "Share of single-paper projects (`t')" ;
    label var multi_`t'     "Weakest paper in a multi-paper project (`t')" ;
} ;
label var tl_med "Median citation percentile (0-1)" ;
label var tl_up  "Max minus median (0-1)" ;
label var tl_lo  "Median minus min (0-1)" ;
keep setnb project_number cycle tl_med tl_up tl_lo tl_lo_btw_* tl_lo_wth_* nproj_* ppp_* single_* multi_* wpmid_* ;
order setnb project_number cycle tl_med tl_up tl_lo ;
label data "Tail measure split by projects, nih_risk" ;
notes: Built `c(current_date)' by code/build/27_tail_projects.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_tail_projects.dta", replace ;

display as result "=== projects by definition" ;
tabstat nproj_* ppp_* single_* multi_*, stat(mean p50) col(stat) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/27_tail_projects.do */
