/* =============================================================================
   code/build/10_pivoting_extras.do

   Purpose: The measures of the pivoting appendix that code/build/09_pivoting.do
            does not build, one row per cycle, on the same papers, the same MeSH
            and the same weighting as pivoting. With pivoting's near and far
            split, they feed Appendix Tables D1 to D3 and Appendix Figure D1
            (code/analysis/26_tables_D1_D3_figure_D1.do):
            - frac_setnb_mesh: the share of the cycle's descriptors absent from
              the baseline, each descriptor weighted by the number of the
              cycle's papers that carry it (pivoting on single descriptors
              rather than pairs);
            - far_both_new: among the cycle's far new pairs (a descriptor absent
              from the baseline), weighted as pivoting weights them, the share
              in which both descriptors are absent; missing without a far pair;
            - cos_dissim_setnb: one minus the cosine similarity of the cycle's
              and the baseline's TF-IDF descriptor profiles (term frequency:
              papers carrying the descriptor). The inverse document
              frequency is ln(N / n_d), N the PubMed 2025 papers with a MeSH
              descriptor and n_d those carrying descriptor d, one vocabulary
              for all years.
            And the graded distance of the new pairs from the baseline:
            - piv_distance: the average distance of the cycle's new pairs from
              the baseline, each pair weighted as pivoting weights it. A
              pair's distance is the larger distance of its two descriptors.
              A descriptor's distance is 1 - s / IC(d): IC(d) is its
              information content, and s that of the most informative MeSH
              tree node lying at or above a position of the descriptor and at
              or above a position of a baseline descriptor (0 if they share
              no node, so the distance is 1). A node is a prefix of a tree
              number or a tree's category letter; its information content is
              ln(N / coverage), coverage being the PubMed 2025 papers with
              MeSH that carry a descriptor at or below it, each paper once,
              all years pooled. Near pairs score 0 by construction.
            - far_dist0: among the cycle's far new pairs (weighted), the share
              whose distance is 0, because the new descriptor lies above one
              the investigator has used; missing without a far pair.
            - piv_distance_noct, a check for the log only: piv_distance over
              the new pairs in which neither descriptor is one of NLM's 40
              check tags (Humans, Animals, sex, age groups, Pregnancy,
              common laboratory animals, United States, historical periods;
              Lister Hill Center, May 2023, listed in section 0b).
            Sections 1 to 4 repeat sections 1 to 4 of code/build/09_pivoting.do
            line for line. Section 5 rebuilds pivoting and its near and far
            split in the same DuckDB pass, and section 6 checks them against
            risk_pivoting.dta on every cycle: a mismatch stops the run.
            Kept on the cycles where pivoting is defined (piv_ok, as in
            code/build/09_pivoting.do).

   Input:
     - ${data}/build/cycles.dta          (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta    (code/build/03_cycle_papers.do)
     - ${data}/build/risk_pivoting.dta   (code/build/09_pivoting.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity papers
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_meshterms_2025.dta   PubMed 2025
     - ${pubmed_root}/mesh2025/mesh_trees_2025.dta   tree numbers of each
       descriptor (built from NLM's desc2026.xml despite its name)
     - ${pubmed_root}/mesh2025/mesh_descriptors_2025.dta   descriptor names,
       to find the check tags

   Output:
     - ${data}/build/risk_pivoting_extras.dta   one row per setnb x project_number x cycle
     - ${data}/build/explore/mesh_nodes.dta     one row per tree node: coverage, information
     - ${data}/build/explore/desc_nodes.dta     one row per descriptor x node at or above it
     - ${data}/build/explore/check_tags.dta     NLM's 40 check tags (also read by
                                                code/build/32_standout_extras.do)
     - ${data}/build/explore/desc_distance.dta  one row per cycle x descriptor absent from
                                                the baseline: its distance and the node met

   Note: DuckDB runs with 12 threads and a 32 GB memory limit. It spills to
         the folder in the global nr_spill when that global is set (best off
         any synced tree), else to a folder in the system's temporary
         directory. Sums of floating-point numbers are exact decimal sums
         (DECIMAL(38,18)), so that they do not depend on the order in which
         DuckDB's threads finish, and among equally informative nodes,
         node_met is the one with the smallest node_id: two runs give
         identical files.
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
log using "logs/10_pivoting_extras.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   0. Inverse document frequency of each descriptor over PubMed 2025, in four
      slices of PMIDs so that no more than a quarter of the file is in memory
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
    display as result "slice `s': " %12.0fc r(N) " papers with MeSH" ;
    gcollapse (count) n_d = pmid, by(dscrptr_ui) ;
    if `s' > 1 append using `idfacc' ;
    save `idfacc', replace ;
} ;
gcollapse (sum) n_d, by(dscrptr_ui) ;
gen double idf = ln(`npap' / n_d) ;
display as result "=== PubMed 2025 papers with MeSH: " %14.0fc `npap' ;
summarize n_d idf, detail ;
gisid dscrptr_ui ;
keep dscrptr_ui idf ;
tempfile idf ;
save `idf' ;

/* -----------------------------------------------------------------------------
   0b. The MeSH tree's nodes, their coverage of PubMed 2025 and their
       information content. A node is a prefix of a tree number (C18,
       C18.654, ...) or a tree's category letter (C); a descriptor reaches
       every node at or above each of its positions. Male and Female carry
       the synthetic codes X999998 and X999999 and meet at the letter X.
       Coverage counts the papers with MeSH that carry a descriptor at or
       below the node, each paper once, in ranges of PMIDs. Stata's code of
       dscrptr_ui maps to NLM's descriptor UI through its value label.
   ----------------------------------------------------------------------------- */
global piv_npap   "`npap'" ;
global piv_nodes  "${data}/build/explore/mesh_nodes.dta" ;
global piv_dnodes "${data}/build/explore/desc_nodes.dta" ;
global piv_ctags  "${data}/build/explore/check_tags.dta" ;

#delimit cr
python:
import os, tempfile, traceback
import numpy as np
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

mt_path = Macro.getGlobal("pubmed_root") + "/pubmed/overall_meshterms_2025.dta"
tr_path = Macro.getGlobal("pubmed_root") + "/mesh2025/mesh_trees_2025.dta"
npap = int(float(Macro.getGlobal("piv_npap")))

# Stata's descriptor code -> NLM UI, from the value label of dscrptr_ui
with pd.read_stata(mt_path, iterator=True) as rdr:
    lab = rdr.value_labels()["dscrptr_ui_lbl"]
code_ui = pd.DataFrame({"d": [int(k) for k in lab.keys()], "ui": list(lab.values())})

# NLM's 40 check tags (Le and Mork, "Check Tags MeSH Terms Indexing Research
# Project", Lister Hill National Center for Biomedical Communications, May
# 2023), for a log-only check: the distance without them. MeSH 2026 itself
# flags only Female and Male (DescriptorClass 3).
CHECK_TAGS = ["Adolescent", "Adult", "Aged", "Aged, 80 and over", "Animals", "Bees", "Cats", "Cattle",
              "Chick Embryo", "Child", "Child, Preschool", "Chlorocebus aethiops", "Cricetinae", "Dogs",
              "Female", "Guinea Pigs", "History of Medicine", "History, 15th Century", "History, 16th Century",
              "History, 17th Century", "History, 18th Century", "History, 19th Century", "History, 20th Century",
              "History, 21st Century", "History, Ancient", "History, Medieval", "Horses", "Humans", "Infant",
              "Infant, Newborn", "Male", "Mice", "Middle Aged", "Pregnancy", "Rabbits", "Rats", "Sheep", "Swine",
              "United States", "Young Adult"]
dnames = pd.read_stata(Macro.getGlobal("pubmed_root") + "/mesh2025/mesh_descriptors_2025.dta", columns=["ui", "dscrptr"])
ct = dnames[dnames["dscrptr"].isin(CHECK_TAGS)].merge(code_ui, on="ui")
SFIToolkit.display("check tags: {} listed, {} found in PubMed 2025".format(len(CHECK_TAGS), ct["dscrptr"].nunique()))
assert len(CHECK_TAGS) == 40 and len(ct) == 40 and ct["dscrptr"].nunique() == 40
ct[["d", "ui", "dscrptr"]].to_stata(Macro.getGlobal("piv_ctags"), write_index=False, version=118)

# every node at or above each position of each descriptor; own = the position itself
tr = pd.read_stata(tr_path, columns=["ui", "mesh_tree"])
tr["tn"] = tr["mesh_tree"].astype(str)
tr = tr.merge(code_ui, on="ui", how="inner")
n_lab, n_tr = len(code_ui), tr["d"].nunique()
SFIToolkit.display("descriptors in PubMed 2025: {:,}; with a tree position: {:,}".format(n_lab, n_tr))
assert n_lab == n_tr
rows = []
for d, tn in zip(tr["d"].tolist(), tr["tn"].tolist()):
    parts = tn.split(".")
    rows.append((d, tn[0], 0))
    for k in range(1, len(parts) + 1):
        rows.append((d, ".".join(parts[:k]), int(k == len(parts))))
dn = pd.DataFrame(rows, columns=["d", "node", "own"])
dn = dn.groupby(["d", "node"], as_index=False)["own"].max()
nodes = pd.DataFrame({"node": sorted(dn["node"].unique())})
nodes["node_id"] = np.arange(1, len(nodes) + 1, dtype=np.int32)
dn = dn.merge(nodes, on="node")[["d", "node_id", "own"]]
SFIToolkit.display("tree nodes: {:,}; descriptor x node rows: {:,}".format(len(nodes), len(dn)))

# the paper x descriptor rows of PubMed 2025
parts = []
with pd.read_stata(mt_path, columns=["pmid", "dscrptr_ui"], convert_categoricals=False, chunksize=50_000_000) as rdr:
    for ch in rdr:
        ch = ch.dropna()
        parts.append(pd.DataFrame({"pmid": ch["pmid"].astype("int32").to_numpy(), "d": ch["dscrptr_ui"].astype("int32").to_numpy()}))
pm = pd.concat(parts, ignore_index=True)
del parts

spill = Macro.getGlobal("nr_spill") or os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_pivot_extras")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=12")
    con.execute("SET memory_limit='32GB'")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    con.register("pm_df", pm)
    con.register("dn_df", dn)
    con.execute("CREATE TEMP TABLE pm AS SELECT DISTINCT pmid, d FROM pm_df ORDER BY pmid")
    con.execute("CREATE TEMP TABLE dn AS SELECT CAST(d AS INTEGER) d, node_id FROM dn_df")
    con.unregister("pm_df"); con.unregister("dn_df")
    del pm
    n_pm, n_pap, maxp = con.execute("SELECT count(*), count(DISTINCT pmid), max(pmid) FROM pm").fetchone()
    SFIToolkit.display("paper x descriptor rows: {:,}; papers: {:,} (the IDF pass: {:,})".format(n_pm, n_pap, npap))
    assert n_pap == npap
    con.execute("CREATE TEMP TABLE cov (node_id INTEGER, n BIGINT)")
    step = 2_000_000
    for lo in range(0, maxp + 1, step):
        con.execute("""INSERT INTO cov
            SELECT node_id, count(*) FROM (
                SELECT DISTINCT p.pmid, dn.node_id FROM pm p JOIN dn USING (d)
                WHERE p.pmid >= ? AND p.pmid < ?)
            GROUP BY node_id""", [lo, lo + step])
    cov = con.execute("SELECT node_id, CAST(sum(n) AS BIGINT) AS cover FROM cov GROUP BY node_id").df()
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()

nodes = nodes.merge(cov, on="node_id", how="left")
# a node covers no paper only if every descriptor at or below it is in the
# value label but on no paper of PubMed 2025; no cycle carries such a
# descriptor (section 5 stops the run if one lacks an information content)
zero = nodes.loc[nodes["cover"].isna(), "node"].tolist()
SFIToolkit.display("nodes without a paper, dropped: {:,}: {}".format(len(zero), ", ".join(zero[:60])))
d_zero = set(dn.loc[dn["node_id"].isin(nodes.loc[nodes["cover"].isna(), "node_id"]), "d"])
nodes = nodes[nodes["cover"].notna()].copy()
dn = dn[dn["node_id"].isin(nodes["node_id"])].copy()
SFIToolkit.display("descriptors with a node dropped: {:,}".format(len(d_zero)))
nodes["cover"] = nodes["cover"].astype("int64")
nodes["ic"] = np.log(npap / nodes["cover"])
nodes["depth"] = np.where(nodes["node"].str.len() == 1, 0, nodes["node"].str.count(r"\.") + 1).astype("int8")
# coverage never falls from a node to its parent
par = nodes["node"].str.rsplit(".", n=1).str[0]
par = par.where(nodes["node"].str.contains(".", regex=False), nodes["node"].str[0])
chk = nodes.assign(parent=par).merge(nodes[["node", "cover"]].rename(columns={"node": "parent", "cover": "cover_parent"}), on="parent", how="left")
chk = chk[chk["node"].str.len() > 1]
n_orph = int(chk["cover_parent"].isna().sum())
n_viol = int((chk["cover_parent"] < chk["cover"]).sum())
SFIToolkit.display("nodes whose parent is missing: {:,}; whose parent covers fewer papers: {:,}".format(n_orph, n_viol))
assert n_viol == 0
for c in sorted(nodes.loc[nodes["node"].str.len() == 1, "node"]):
    r = nodes.loc[nodes["node"] == c].iloc[0]
    SFIToolkit.display("  letter {}: {:>12,} papers, share {:.3f}, IC {:.3f}".format(c, int(r["cover"]), r["cover"] / npap, r["ic"]))
nodes[["node_id", "node", "depth", "cover", "ic"]].to_stata(Macro.getGlobal("piv_nodes"), write_index=False, version=118)
dn = dn.merge(tr[["d", "ui"]].drop_duplicates(), on="d")
dn[["d", "ui", "node_id", "own"]].to_stata(Macro.getGlobal("piv_dnodes"), write_index=False, version=118)
end
#delimit ;

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

/* every descriptor of these papers has a weight */
merge m:1 dscrptr_ui using `idf' ;
tab _merge ;
assert _merge != 1 ;
clear ;

/* -----------------------------------------------------------------------------
   5. Pairs, descriptors and profiles, in DuckDB. The tables cur, base, mesh,
      pp, cp, bd and bp and the shares w_all, w_new and w_near are those of
      code/build/09_pivoting.do; the others serve the measures of this file.
   ----------------------------------------------------------------------------- */
global piv_cur  "`cur'" ;
global piv_base "`base'" ;
global piv_mesh "`mesh'" ;
global piv_idf  "`idf'" ;
tempfile res ;
global piv_res  "`res'" ;
tempfile ddist ;
global piv_ddist "`ddist'" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

cur  = pd.read_stata(Macro.getGlobal("piv_cur"))
base = pd.read_stata(Macro.getGlobal("piv_base"))
mesh = pd.read_stata(Macro.getGlobal("piv_mesh"), convert_categoricals=False)
idf  = pd.read_stata(Macro.getGlobal("piv_idf"), convert_categoricals=False)
dnod = pd.read_stata(Macro.getGlobal("piv_dnodes"), columns=["d", "node_id", "own"], convert_categoricals=False)
nic  = pd.read_stata(Macro.getGlobal("piv_nodes"), columns=["node_id", "depth", "ic"])
ctag = pd.read_stata(Macro.getGlobal("piv_ctags"), columns=["d"], convert_categoricals=False)
spill = Macro.getGlobal("nr_spill") or os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_pivot_extras")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=12")
    con.execute("SET memory_limit='32GB'")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    con.register("cur_df", cur)
    con.register("base_df", base)
    con.register("mesh_df", mesh)
    con.register("idf_df", idf)
    con.execute("CREATE TEMP TABLE cur  AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM cur_df")
    con.execute("CREATE TEMP TABLE base AS SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM base_df")
    con.execute("CREATE TEMP TABLE mesh AS SELECT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.execute("CREATE TEMP TABLE idf  AS SELECT CAST(dscrptr_ui AS INTEGER) d, CAST(idf AS DOUBLE) idf FROM idf_df")
    con.unregister("cur_df"); con.unregister("base_df"); con.unregister("mesh_df"); con.unregister("idf_df")
    del cur, base, mesh, idf
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
    con.execute("DROP TABLE pp")
    # the descriptor profiles of the cycle and of the baseline, each
    # descriptor weighted by the number of papers carrying it
    con.execute("""CREATE TEMP TABLE cd AS
        SELECT c.cid, m.d, count(*) AS freq FROM cur c JOIN mesh m USING (pmid) GROUP BY ALL""")
    con.execute("""CREATE TEMP TABLE bdf AS
        SELECT b.cid, m.d, count(*) AS freq FROM base b JOIN mesh m USING (pmid) GROUP BY ALL""")
    # the distance of each of the cycle's descriptors absent from the
    # baseline, then of each new pair (the larger of its two descriptors'),
    # then of the cycle's new pairs on average
    con.register("dnod_df", dnod)
    con.register("nic_df", nic)
    con.register("ctag_df", ctag)
    con.execute("CREATE TEMP TABLE dn  AS SELECT CAST(d AS INTEGER) d, CAST(node_id AS INTEGER) node_id, CAST(own AS INTEGER) own FROM dnod_df")
    con.execute("CREATE TEMP TABLE nic AS SELECT CAST(node_id AS INTEGER) node_id, CAST(depth AS INTEGER) depth, CAST(ic AS DOUBLE) ic FROM nic_df")
    con.execute("CREATE TEMP TABLE ct  AS SELECT CAST(d AS INTEGER) d FROM ctag_df")
    con.unregister("dnod_df"); con.unregister("nic_df"); con.unregister("ctag_df")
    del dnod, nic, ctag
    con.execute("""CREATE TEMP TABLE dic AS
        SELECT dn.d, max(nic.ic) AS ic_d FROM dn JOIN nic USING (node_id) WHERE dn.own = 1 GROUP BY dn.d""")
    con.execute("""CREATE TEMP TABLE bn AS
        SELECT DISTINCT bd.cid, dn.node_id FROM bd JOIN dn USING (d)""")
    con.execute("""CREATE TEMP TABLE nd AS
        SELECT cd.cid, cd.d, cd.freq FROM cd ANTI JOIN bd ON bd.cid = cd.cid AND bd.d = cd.d""")
    con.execute("""CREATE TEMP TABLE ndist AS
        WITH m AS (
            SELECT nd.cid, nd.d, any_value(nd.freq) AS freq, any_value(dic.ic_d) AS ic_d,
                   coalesce(max(nic.ic) FILTER (WHERE bn.cid IS NOT NULL), 0) AS s,
                   arg_max(dn.node_id, [nic.ic + nic.depth * 1e-9, -dn.node_id]) FILTER (WHERE bn.cid IS NOT NULL) AS node_met
            FROM nd
            JOIN dic ON dic.d = nd.d
            JOIN dn  ON dn.d = nd.d
            JOIN nic ON nic.node_id = dn.node_id
            LEFT JOIN bn ON bn.cid = nd.cid AND bn.node_id = dn.node_id
            GROUP BY nd.cid, nd.d)
        SELECT cid, d, freq, ic_d, s, node_met, greatest(0.0, least(1.0, 1 - s / ic_d)) AS delta FROM m""")
    n_nd   = con.execute("SELECT count(*) FROM nd").fetchone()[0]
    n_dist = con.execute("SELECT count(*), sum(CASE WHEN s > ic_d + 1e-9 THEN 1 ELSE 0 END), min(ic_d) FROM ndist").fetchone()
    SFIToolkit.display("new descriptors: {:,}; with a distance: {:,}; s above IC(d): {:,}; smallest IC(d): {:.3f}".format(n_nd, n_dist[0], n_dist[1], n_dist[2]))
    assert n_dist[0] == n_nd and n_dist[1] == 0 and n_dist[2] > 0
    con.execute("DROP TABLE bn")
    con.execute("""CREATE TEMP TABLE dist AS
        WITH pdist AS (
            SELECT cp.cid, cp.freq,
                   (x1.d IS NOT NULL OR x2.d IS NOT NULL) AS far,
                   greatest(coalesce(x1.delta, 0), coalesce(x2.delta, 0)) AS pd
            FROM cp ANTI JOIN bp ON bp.cid = cp.cid AND bp.d1 = cp.d1 AND bp.d2 = cp.d2
            LEFT JOIN ndist x1 ON x1.cid = cp.cid AND x1.d = cp.d1
            LEFT JOIN ndist x2 ON x2.cid = cp.cid AND x2.d = cp.d2)
        SELECT cid, CAST(sum(CAST(freq * pd AS DECIMAL(38,18))) AS DOUBLE) / sum(freq) AS piv_distance,
               CAST(sum(freq) AS DOUBLE) AS w_new_chk,
               CAST(coalesce(sum(freq) FILTER (WHERE far), 0) AS DOUBLE) AS w_far_chk,
               CAST(coalesce(sum(freq) FILTER (WHERE far AND pd = 0), 0) AS DOUBLE) AS w_far0
        FROM pdist GROUP BY cid""")
    # log-only check: the same average over the new pairs in which neither
    # descriptor is one of NLM's check tags
    con.execute("""CREATE TEMP TABLE dist2 AS
        WITH pdist AS (
            SELECT cp.cid, cp.freq,
                   greatest(coalesce(x1.delta, 0), coalesce(x2.delta, 0)) AS pd
            FROM cp ANTI JOIN bp ON bp.cid = cp.cid AND bp.d1 = cp.d1 AND bp.d2 = cp.d2
            ANTI JOIN ct c1 ON c1.d = cp.d1
            ANTI JOIN ct c2 ON c2.d = cp.d2
            LEFT JOIN ndist x1 ON x1.cid = cp.cid AND x1.d = cp.d1
            LEFT JOIN ndist x2 ON x2.cid = cp.cid AND x2.d = cp.d2)
        SELECT cid, CAST(sum(CAST(freq * pd AS DECIMAL(38,18))) AS DOUBLE) / sum(freq) AS piv_distance_noct,
               CAST(sum(freq) AS DOUBLE) AS w_new_noct
        FROM pdist GROUP BY cid""")
    ddist = con.execute("SELECT cid, d, freq, ic_d, s, delta, node_met FROM ndist ORDER BY cid, d").df()
    res = con.execute("""
        WITH sh AS (
            SELECT cp.cid, CAST(sum(cp.freq) AS DOUBLE) AS w_all,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE bp.cid IS NULL), 0) AS DOUBLE) AS w_new,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE bp.cid IS NULL AND b1.d IS NOT NULL AND b2.d IS NOT NULL), 0) AS DOUBLE) AS w_near,
                   CAST(coalesce(sum(cp.freq) FILTER (WHERE bp.cid IS NULL AND b1.d IS NULL AND b2.d IS NULL), 0) AS DOUBLE) AS w_far2
            FROM cp
            LEFT JOIN bp ON bp.cid = cp.cid AND bp.d1 = cp.d1 AND bp.d2 = cp.d2
            LEFT JOIN bd b1 ON b1.cid = cp.cid AND b1.d = cp.d1
            LEFT JOIN bd b2 ON b2.cid = cp.cid AND b2.d = cp.d2
            GROUP BY cp.cid),
        nb AS (SELECT cid, count(DISTINCT pmid) AS n_base_mesh FROM base SEMI JOIN mesh USING (pmid) GROUP BY cid),
        nc AS (SELECT cid, count(DISTINCT pmid) AS n_cur_mesh  FROM cur  SEMI JOIN mesh USING (pmid) GROUP BY cid),
        sd AS (
            SELECT cd.cid, CAST(sum(cd.freq) AS DOUBLE) AS wd_all,
                   CAST(coalesce(sum(cd.freq) FILTER (WHERE bd.cid IS NULL), 0) AS DOUBLE) AS wd_new
            FROM cd LEFT JOIN bd ON bd.cid = cd.cid AND bd.d = cd.d
            GROUP BY cd.cid),
        nx AS (SELECT cd.cid, CAST(sum(CAST(power(cd.freq * i.idf, 2) AS DECIMAL(38,18))) AS DOUBLE) AS xx FROM cd JOIN idf i USING (d) GROUP BY cd.cid),
        ny AS (SELECT bdf.cid, CAST(sum(CAST(power(bdf.freq * i.idf, 2) AS DECIMAL(38,18))) AS DOUBLE) AS yy FROM bdf JOIN idf i USING (d) GROUP BY bdf.cid),
        xy AS (SELECT cd.cid, CAST(sum(CAST(cd.freq * bdf.freq * i.idf * i.idf AS DECIMAL(38,18))) AS DOUBLE) AS xy
               FROM cd JOIN bdf ON bdf.cid = cd.cid AND bdf.d = cd.d JOIN idf i ON i.d = cd.d GROUP BY cd.cid),
        allc AS (SELECT cid FROM sh UNION SELECT cid FROM nb UNION SELECT cid FROM nc)
        SELECT CAST(a.cid AS INTEGER) AS cid, sh.w_all, sh.w_new, sh.w_near, sh.w_far2,
               CAST(coalesce(nb.n_base_mesh, 0) AS INTEGER) AS n_base_mesh,
               CAST(coalesce(nc.n_cur_mesh, 0) AS INTEGER) AS n_cur_mesh,
               sd.wd_all, sd.wd_new,
               CASE WHEN nx.xx > 0 AND ny.yy > 0 THEN coalesce(xy.xy, 0) / sqrt(nx.xx * ny.yy) END AS cos_tfidf,
               dist.piv_distance, dist.w_new_chk, dist.w_far_chk, dist.w_far0,
               dist2.piv_distance_noct, dist2.w_new_noct
        FROM allc a
        LEFT JOIN sh ON sh.cid = a.cid
        LEFT JOIN nb ON nb.cid = a.cid
        LEFT JOIN nc ON nc.cid = a.cid
        LEFT JOIN sd ON sd.cid = a.cid
        LEFT JOIN nx ON nx.cid = a.cid
        LEFT JOIN ny ON ny.cid = a.cid
        LEFT JOIN xy ON xy.cid = a.cid
        LEFT JOIN dist ON dist.cid = a.cid
        LEFT JOIN dist2 ON dist2.cid = a.cid
        ORDER BY a.cid""").df()
    n_cp = con.execute("SELECT count(*) FROM cp").fetchone()[0]
    n_cd = con.execute("SELECT count(*) FROM cd").fetchone()[0]
    n_bdf = con.execute("SELECT count(*) FROM bdf").fetchone()[0]
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("cycle x pair rows: {:,}; cycle x descriptor rows: {:,}; baseline x descriptor rows: {:,}; cycles with a value: {:,}".format(n_cp, n_cd, n_bdf, len(res)))
res.to_stata(Macro.getGlobal("piv_res"), write_index=False)
ddist["node_met"] = ddist["node_met"].astype("float64")
ddist.to_stata(Macro.getGlobal("piv_ddist"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   6. The measures; near and far checked against risk_pivoting.dta
   ----------------------------------------------------------------------------- */
use `res', clear ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
tab _merge ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge ;
gen byte piv_ok = n_base_mesh > 0 & w_all > 0 & w_all < . ;
gen double chk_pair = w_new / w_all  if piv_ok ;
gen double chk_near = w_near / w_all if piv_ok ;
gen double chk_far  = (w_new - w_near) / w_all if piv_ok ;
drop if !piv_ok ;

merge 1:1 setnb project_number cycle using "${data}/build/risk_pivoting.dta",
    keepusing(frac_setnb_pair frac_setnb_pair_near frac_setnb_pair_far n_base_mesh n_cur_mesh)
    update ;
/* 1: here only; 2: in risk_pivoting.dta only; 3: in both, with the same
   paper counts; 5: in both, paper counts differ */
display as result "=== CHECK: the same cycles, with the same baseline and current paper counts" ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
gen double dd = max(abs(chk_pair - frac_setnb_pair), abs(chk_near - frac_setnb_pair_near),
                    abs(chk_far - frac_setnb_pair_far)) ;
display as result "=== CHECK: largest absolute difference with risk_pivoting.dta, pair, near or far" ;
summarize dd ;
assert dd < 1e-9 ;
display as result "=== CHECK passed: " %9.0fc _N " cycles, the same set, same pair, near and far shares" ;
drop dd chk_* ;

/* the distance's own pass counts the same new and far pairs */
display as result "=== CHECK: the distance pass sees the same new and far pairs" ;
assert abs(w_new_chk - w_new) < 1e-9 if w_new > 0 ;
assert abs(w_far_chk - (w_new - w_near)) < 1e-9 if w_new > 0 ;
assert missing(piv_distance) if w_new == 0 ;
assert inrange(piv_distance, 0, 1) if w_new > 0 ;
gen double far_dist0 = w_far0 / (w_new - w_near) if w_new - w_near > 0 ;
count if w_new == 0 ;
display as result "=== cycles without a new pair (no distance): " r(N) ;
drop w_new_chk w_far_chk ;

/* the measures of this file */
gen double frac_setnb_mesh  = wd_new / wd_all if wd_all > 0 & wd_all < . ;
gen double far_both_new     = w_far2 / (w_new - w_near) if w_new - w_near > 0 ;
gen double cos_dissim_setnb = 1 - cos_tfidf ;
assert !missing(frac_setnb_mesh, cos_dissim_setnb) ;
assert inrange(far_both_new, 0, 1) if !missing(far_both_new) ;
assert cos_dissim_setnb > -1e-9 & cos_dissim_setnb < 1 + 1e-9 ;
replace cos_dissim_setnb = min(max(cos_dissim_setnb, 0), 1) ;
label var frac_setnb_mesh  "Share of the cycle's MeSH descriptors new to the investigator (5-yr baseline, paper-weighted)" ;
label var far_both_new     "Among far new pairs (paper-weighted), share with both descriptors new" ;
label var cos_dissim_setnb "1 - TF-IDF cosine similarity, cycle vs 5-yr baseline MeSH profile" ;
label var piv_distance     "Average distance of the cycle's new MeSH pairs from the 5-yr baseline, 0-1" ;
label var far_dist0        "Among far new pairs (paper-weighted), share at distance 0" ;
label var piv_distance_noct "piv_distance on new pairs without a check tag (check, log only)" ;
assert inrange(piv_distance_noct, 0, 1) if !missing(piv_distance_noct) ;
count if missing(piv_distance_noct) & !missing(piv_distance) ;
display as result "=== cycles whose new pairs all involve a check tag: " r(N) ;
drop w_new_noct ;
display as result "=== the measures of this file, every cycle with pivoting" ;
summarize frac_setnb_mesh far_both_new cos_dissim_setnb piv_distance far_dist0 frac_setnb_pair frac_setnb_pair_near frac_setnb_pair_far, detail ;
correlate frac_setnb_mesh far_both_new cos_dissim_setnb piv_distance frac_setnb_pair frac_setnb_pair_near frac_setnb_pair_far ;

keep setnb project_number cycle frac_setnb_mesh far_both_new cos_dissim_setnb piv_distance far_dist0 piv_distance_noct ;
order setnb project_number cycle frac_setnb_mesh far_both_new cos_dissim_setnb piv_distance far_dist0 piv_distance_noct ;
label data "Pivoting extras, nih_risk" ;
notes: Built `c(current_date)' by code/build/10_pivoting_extras.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_pivoting_extras.dta", replace ;
tempfile extras ;
save `extras' ;

/* the distance of each new descriptor, on the cycles where pivoting is
   defined, kept for the inspection of the distance */
use `ddist', clear ;
merge m:1 cid using `keys', keepusing(setnb project_number cycle) ;
tab _merge ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge cid ;
merge m:1 setnb project_number cycle using `extras', keepusing(piv_distance) ;
tab _merge ;
keep if _merge == 3 ;
drop _merge piv_distance ;
rename d dscrptr_ui ;
label var dscrptr_ui "Descriptor, Stata's code of overall_meshterms_2025.dta (desc_nodes.dta: d)" ;
label var freq     "Cycle's acknowledging papers carrying the descriptor" ;
label var ic_d     "Information content of the descriptor" ;
label var s        "Information content of the most informative node shared with the baseline" ;
label var delta    "Distance from the baseline, 1 - s / ic_d" ;
label var node_met "That node (mesh_nodes.dta: node_id), missing if none" ;
order setnb project_number cycle dscrptr_ui ;
sort setnb project_number cycle dscrptr_ui ;
display as result "=== new descriptors on the cycles with pivoting" ;
count ;
summarize delta, detail ;
compress ;
save "${data}/build/explore/desc_distance.dta", replace ;

use `extras', clear ;

/* -----------------------------------------------------------------------------
   7. First look: sample cycles
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta",
    keepusing(in_sample sep renewed cycle_yr) ;
assert _merge != 1 ;
keep if _merge == 3 & in_sample & sep != 1 ;
drop _merge ;
display as result "=== sample cycles with the extras" ;
count ;
tabstat frac_setnb_mesh far_both_new cos_dissim_setnb piv_distance far_dist0, by(renewed) stat(mean p50 n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/10_pivoting_extras.do */
