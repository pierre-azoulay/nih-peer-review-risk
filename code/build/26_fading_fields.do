/* =============================================================================
   code/build/26_fading_fields.do

   Purpose: The vibrancy of the field an investigator leaves, for Appendix
            Table D4 and Appendix Figure D3
            (code/analysis/27_table_D4_figure_D3.do), one row per
            analysis-sample cycle.
            - baseline papers: the investigator's Author-ity papers, English
              original research, any author position, published in s - 5 to
              s - 1 (s = cycle_yr), except papers that acknowledge the focal
              grant (acknowledgment links before the author check) and papers
              of the following types: retractions, errata, expressions of
              concern, tributes, news, newspaper articles, patient handouts,
              tutorials, legal cases, duplicate publications. Case reports
              stay. The source papers of the PMRA store follow the same rule.
            - neighbors: each baseline paper's PMRA neighbors, from all three
              parts of the store, the rank-0 row dropped, and every neighbor
              on which the investigator is an author (Author-ity, any
              position) dropped; each counted once, unweighted, by its PubMed
              2025 publication year: early window s - 10 to s - 6, late window
              s - 5 to s - 1.
            - v_p = late / (early + late), when early + late >= 5.
            - vib_pre = mean over the cycle's baseline papers of v_p net of
              its mean among baseline papers with the same cycle_yr and
              publication year, which face the same windows from the same
              date: v_p falls with the paper's distance from s, and the
              adjustment removes that; vib_pre_raw = the unadjusted mean of
              v_p.
              fading (below the median within cycle_yr) is computed on the
              regression sample by code/analysis/27_table_D4_figure_D3.do.
            The store is read once, filtered on the baseline papers, into
            parquet files in the machine's temp folder (nihrep_fading); set
            local extract to 0 to reuse that extract.

   Input:
     - ${data}/output/nih_risk_analysis.dta (cycles, cycle_yr, author_id,
       has_pivot)                           (code/build/23_analysis_file.do)
     - ${data}/build/ackn_links_unchecked.dta   (code/build/02_ackn_links.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity: the
       authors of each PubMed paper
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_pubtypes_2025.dta   PubMed 2025:
       year, type, language and NLM publication types of each paper
     - ${pubmed_root}/PMRA/pmra_links_part1.dta to part3.dta, harvested_pmids.dta
       the PMRA store: the PubMed related articles of each source paper, by
       rank, and the list of source papers

   Output:
     - ${data}/build/risk_fading.dta   one row per setnb x project_number x cycle
     - ${data}/build/explore/paper_vibrancy.dta   one row per cycle x
       baseline paper: neighbor counts by window, own papers removed, v_p

   Note: DuckDB with 3 threads and a 5 GB limit; the extract of the store
         takes about a minute, the whole file a few minutes. The means of
         floating-point numbers are taken in an explicit order, so that two
         runs give identical files.
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
log using "logs/26_fading_fields.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* the extract of the store and DuckDB's spill folder: in the machine's temp
   folder (nihrep_fading). extract 1 reads the store (about a minute),
   filtered on this run's baseline papers; 0 reuses the previous extract on
   this machine, which is right only if neither the cycles nor the store have
   changed since. */
local extract 1 ;

/* -----------------------------------------------------------------------------
   1. Cycles: the analysis sample, with a numeric key for cycle and investigator
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr author_id has_pivot using "${data}/output/nih_risk_analysis.dta", clear ;
sort setnb project_number cycle ;
gen long cid = _n ;
gegen long aid = group(author_id) ;
tempfile keys ;
save `keys' ;
display as result "=== analysis cycles; without an Author-ity id; with pivoting" ;
count ;
count if author_id == "" ;
count if has_pivot == 1 ;
drop if author_id == "" ;
keep cid aid author_id cycle_yr project_number ;
tempfile cyc ;
save `cyc' ;
keep aid author_id ;
bysort aid: keep if _n == 1 ;
tempfile auth ;
save `auth' ;

/* -----------------------------------------------------------------------------
   2. Papers eligible as baseline papers (one row per PMID): English original
      research, with the typology flags of the excluded types (rtrct_stuff,
      rcgntn), the rule stated in the header
   ----------------------------------------------------------------------------- */
use pmid orgnl rtrct_stuff rcgntn using "${pubmed_root}/pubmed/overall_typology_2025.dta", clear ;
gcollapse (max) orgnl rtrct_stuff rcgntn, by(pmid) ;
tempfile typ ;
save `typ' ;
use pmid eng using "${pubmed_root}/pubmed/overall_language_2025.dta", clear ;
gcollapse (max) eng, by(pmid) ;
tempfile lng ;
save `lng' ;
use pmid year using "${pubmed_root}/pubmed/pubmed_universe_2025.dta", clear ;
bysort pmid: keep if _n == 1 ;
rename year pubyear ;
tempfile yrs ;
save `yrs' ;
merge 1:1 pmid using `typ' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using `lng' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
keep if orgnl == 1 & eng == 1 ;
keep pmid pubyear rtrct_stuff rcgntn ;
tempfile pm ;
save `pm' ;

/* -----------------------------------------------------------------------------
   3. The investigators' Author-ity papers (all, for the self-exclusion), and
      the baseline papers of each cycle
   ----------------------------------------------------------------------------- */
use author_id pmid using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `auth' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge author_id ;
bysort aid pmid: keep if _n == 1 ;
display as result "=== the investigators' Author-ity papers (investigator x paper)" ;
count ;
tempfile own ;
save `own' ;

merge m:1 pmid using `pm' ;
keep if _merge == 3 ;
drop _merge ;
joinby aid using `cyc' ;
keep if pubyear >= cycle_yr - 5 & pubyear <= cycle_yr - 1 ;
drop author_id ;
/* focal-grant papers */
preserve ;
use project_number pmid using "${data}/build/ackn_links_unchecked.dta", clear ;
bysort project_number pmid: keep if _n == 1 ;
gen byte focal = 1 ;
tempfile ack ;
save `ack' ;
restore ;
merge m:1 project_number pmid using `ack' ;
drop if _merge == 2 ;
drop _merge ;
replace focal = 0 if focal == . ;
display as result "=== cycle x paper pairs in s-5 to s-1; acknowledging the focal grant" ;
count ;
count if focal ;
drop if focal ;
/* the NLM publication types excluded from the baseline papers, as from the
   source papers of the PMRA store */
preserve ;
keep pmid ;
bysort pmid: keep if _n == 1 ;
tempfile cand ;
save `cand' ;
use pmid pubtype using "${pubmed_root}/pubmed/overall_pubtypes_2025.dta", clear ;
merge m:1 pmid using `cand' ;
keep if _merge == 3 ;
drop _merge ;
decode pubtype, gen(pt) ;
gen byte badtype = inlist(pt, "News", "Newspaper Article", "Patient Education Handout",
    "Interactive Tutorial", "Legal Case", "Duplicate Publication") ;
gen byte casereport = pt == "Case Reports" ;
gcollapse (max) badtype casereport, by(pmid) ;
tempfile ptyp ;
save `ptyp' ;
restore ;
merge m:1 pmid using `ptyp' ;
drop if _merge == 2 ;
drop _merge ;
replace badtype = 0 if badtype == . ;
replace casereport = 0 if casereport == . ;
gen byte drop_type = rtrct_stuff == 1 | rcgntn == 1 | badtype == 1 ;
display as result "=== pairs of excluded types (dropped); case reports (kept)" ;
count if drop_type ;
count if casereport & !drop_type ;
drop if drop_type ;
keep cid aid pmid cycle_yr pubyear casereport ;
gisid cid pmid ;
display as result "=== baseline pairs (cycle x paper), and distinct baseline papers" ;
count ;
tempfile base ;
save `base' ;
keep pmid ;
bysort pmid: keep if _n == 1 ;
count ;
merge 1:1 pmid using "${pubmed_root}/PMRA/harvested_pmids.dta", keepusing(pmid) ;
drop if _merge == 2 ;
gen byte in_store = _merge == 3 ;
drop _merge ;
display as result "=== distinct baseline papers in the PMRA store" ;
tab in_store ;
tempfile bpm ;
save `bpm' ;

/* -----------------------------------------------------------------------------
   4. Extract of the store (if asked) and the windows, in DuckDB
   ----------------------------------------------------------------------------- */
use pmid pubyear using `yrs', clear ;
tempfile yrs2 ;
save `yrs2' ;
tempfile res ;
global fd_extract "`extract'" ;
global fd_base    "`base'" ;
global fd_bpm     "`bpm'" ;
global fd_own     "`own'" ;
global fd_yrs     "`yrs2'" ;
global fd_res     "`res'" ;
global fd_p1 "${pubmed_root}/PMRA/pmra_links_part1.dta" ;
global fd_p2 "${pubmed_root}/PMRA/pmra_links_part2.dta" ;
global fd_p3 "${pubmed_root}/PMRA/pmra_links_part3.dta" ;

#delimit cr
python:
import os, tempfile, time, traceback
import numpy as np
import pandas as pd
import pyarrow as pa, pyarrow.parquet as pq
import duckdb
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
scr = os.path.join(tempfile.gettempdir(), "nihrep_fading")
os.makedirs(scr, exist_ok=True)
def say(s):
    SFIToolkit.display(time.strftime("%H:%M:%S ") + s)

# ---- the extract: neighbors of the baseline papers, one parquet per part
if g("fd_extract") == "1":
    want = np.sort(pd.read_stata(g("fd_bpm"), columns=["pmid"])["pmid"].to_numpy().astype(np.int64))
    say("baseline papers to look up: {:,}".format(len(want)))
    for k in (1, 2, 3):
        out = os.path.join(scr, "nb_part{}.parquet".format(k))
        tmp = out + ".tmp"
        n_in = n_kept = 0
        sch = pa.schema([("pmid", pa.int32()), ("rltd_pmid", pa.int32()), ("rltd_rnk", pa.int16())])
        w = pq.ParquetWriter(tmp, sch)
        try:
            with pd.read_stata(g("fd_p" + str(k)), columns=["pmid", "rltd_pmid", "rltd_rnk"],
                               chunksize=20_000_000, convert_categoricals=False) as rdr:
                for ch in rdr:
                    n_in += len(ch)
                    p = ch["pmid"].to_numpy().astype(np.int64)
                    i = np.searchsorted(want, p)
                    i[i == len(want)] = 0
                    keep = want[i] == p
                    sub = ch.loc[keep]
                    n_kept += len(sub)
                    w.write_table(pa.Table.from_pandas(pd.DataFrame({
                        "pmid": sub["pmid"].astype("int32"),
                        "rltd_pmid": sub["rltd_pmid"].astype("int32"),
                        "rltd_rnk": sub["rltd_rnk"].astype("int16")}), schema=sch, preserve_index=False))
        finally:
            w.close()
        os.replace(tmp, out)
        say("part {}: {:,} rows read, {:,} kept".format(k, n_in, n_kept))
else:
    say("extract skipped: reusing the parquet files in " + scr)

# ---- the windows
base = pd.read_stata(g("fd_base"), columns=["cid", "aid", "pmid", "cycle_yr"])
own  = pd.read_stata(g("fd_own"), columns=["aid", "pmid"])
yrs  = pd.read_stata(g("fd_yrs"))
spill = os.path.join(scr, "spill")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=3")
    con.execute("SET memory_limit='5GB'")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    for nm, df in (("base", base), ("own", own), ("yrs", yrs)):
        con.register(nm + "_df", df)
    con.execute("CREATE TEMP TABLE base AS SELECT CAST(cid AS INTEGER) cid, CAST(aid AS INTEGER) aid, CAST(pmid AS INTEGER) pmid, CAST(cycle_yr AS INTEGER) s FROM base_df")
    con.execute("CREATE TEMP TABLE own  AS SELECT DISTINCT CAST(aid AS INTEGER) aid, CAST(pmid AS INTEGER) opmid FROM own_df")
    con.execute("CREATE TEMP TABLE yrs  AS SELECT CAST(pmid AS INTEGER) pmid, CAST(pubyear AS INTEGER) ny FROM yrs_df WHERE pubyear IS NOT NULL")
    for nm in ("base", "own", "yrs"):
        con.unregister(nm + "_df")
    del base, own, yrs

    pat = os.path.join(scr, "nb_part*.parquet").replace("\\", "/")
    chk = con.execute("""SELECT count(*) n_rows, count(*) FILTER (WHERE rltd_rnk = 0) n_rank0,
               count(*) FILTER (WHERE rltd_rnk > 0 AND rltd_pmid = pmid) n_selfrank,
               count(DISTINCT pmid) n_src FROM read_parquet('{}')""".format(pat)).fetchone()
    say("extract: {:,} rows, {:,} rank-0 rows, {:,} self rows at rank > 0, {:,} source papers".format(*chk))
    twice = con.execute("""SELECT count(*) FROM (SELECT pmid FROM read_parquet('{}', filename = true)
               GROUP BY pmid HAVING count(DISTINCT filename) > 1)""".format(pat)).fetchone()[0]
    say("source papers in more than one part: {:,}".format(twice))
    if twice > 0:
        raise RuntimeError("a source paper sits in two parts of the store")
    con.execute("""CREATE TEMP TABLE nb AS SELECT DISTINCT pmid, rltd_pmid FROM read_parquet('{}')
                   WHERE rltd_rnk > 0 AND rltd_pmid <> pmid""".format(pat))
    say("neighbor pairs: {:,}".format(con.execute("SELECT count(*) FROM nb").fetchone()[0]))
    # neighbors with a publication year, by source paper and year
    con.execute("""CREATE TEMP TABLE agg AS SELECT nb.pmid, y.ny, count(*) n
                   FROM nb JOIN yrs y ON y.pmid = nb.rltd_pmid GROUP BY ALL""")
    con.execute("CREATE TEMP TABLE src AS SELECT pmid, count(*) n_nb FROM nb GROUP BY pmid")
    con.execute("CREATE TEMP TABLE srcy AS SELECT pmid, sum(n) n_nb_yr FROM agg GROUP BY pmid")
    con.execute("""CREATE TEMP TABLE tot AS
        SELECT b.cid, b.pmid,
               coalesce(sum(a.n) FILTER (WHERE a.ny BETWEEN b.s - 10 AND b.s - 6), 0) n_early,
               coalesce(sum(a.n) FILTER (WHERE a.ny BETWEEN b.s - 5  AND b.s - 1), 0) n_late,
               coalesce(sum(a.n) FILTER (WHERE a.ny BETWEEN b.s AND b.s + 4), 0) n_post
        FROM base b JOIN agg a USING (pmid) GROUP BY ALL""")
    # neighbors on which the investigator is an author
    con.execute("""CREATE TEMP TABLE onb AS
        SELECT b.cid, b.pmid,
               count(*) FILTER (WHERE y.ny BETWEEN b.s - 10 AND b.s - 6) o_early,
               count(*) FILTER (WHERE y.ny BETWEEN b.s - 5  AND b.s - 1) o_late,
               count(*) FILTER (WHERE y.ny BETWEEN b.s AND b.s + 4) o_post,
               count(*) o_all
        FROM nb JOIN own o ON o.opmid = nb.rltd_pmid
        JOIN base b ON b.pmid = nb.pmid AND b.aid = o.aid
        JOIN yrs y ON y.pmid = nb.rltd_pmid
        GROUP BY ALL""")
    res = con.execute("""
        SELECT b.cid, b.pmid,
               CAST(coalesce(s.n_nb, 0) AS INTEGER) n_nb,
               CAST(coalesce(sy.n_nb_yr, 0) AS INTEGER) n_nb_yr,
               CAST(coalesce(t.n_early, 0) AS INTEGER) n_early_all,
               CAST(coalesce(t.n_late, 0) AS INTEGER) n_late_all,
               CAST(coalesce(o.o_early, 0) AS INTEGER) n_own_early,
               CAST(coalesce(o.o_late, 0) AS INTEGER) n_own_late,
               CAST(coalesce(t.n_post, 0) AS INTEGER) n_post_all,
               CAST(coalesce(o.o_post, 0) AS INTEGER) n_own_post,
               CAST(coalesce(o.o_all, 0) AS INTEGER) n_own_all
        FROM base b
        LEFT JOIN src s ON s.pmid = b.pmid
        LEFT JOIN srcy sy ON sy.pmid = b.pmid
        LEFT JOIN tot t ON t.cid = b.cid AND t.pmid = b.pmid
        LEFT JOIN onb o ON o.cid = b.cid AND o.pmid = b.pmid
        ORDER BY b.cid, b.pmid""").df()
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
say("cycle x paper rows: {:,}".format(len(res)))
res.to_stata(g("fd_res"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   5. v_p by paper, vib_pre by cycle
   ----------------------------------------------------------------------------- */
use `res', clear ;
merge 1:1 cid pmid using `base', keepusing(aid cycle_yr pubyear casereport) ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;
merge m:1 pmid using `bpm', keepusing(in_store) ;
tab _merge ;
assert _merge != 1 ;
keep if _merge == 3 ;
drop _merge ;
gen int n_early = n_early_all - n_own_early ;
gen int n_late  = n_late_all - n_own_late ;
/* a check only, never part of the measure (the measure uses no window past
   s): neighbors in s to s + 4, whether the field kept its course */
gen int n_post  = n_post_all - n_own_post ;
assert n_early >= 0 & n_late >= 0 & n_post >= 0 ;
gen double post_share = n_post / (n_late + n_post) if n_late + n_post >= 5 ;
gen double v_p = n_late / (n_early + n_late) if n_early + n_late >= 5 ;
/* PMRA neighbors cluster near a paper's own date and the late window holds
   the paper, so v_p falls with s - pubyear (0.72 in s - 1, 0.62 in s - 5).
   Each paper is compared with the baseline papers that face the same windows
   from the same date: v_p minus its mean in the cycle_yr x pubyear cell. */
/* a mean of floating-point numbers depends on the order it adds them: the order is
   set explicitly, so that two runs give identical files */
sort cycle_yr pubyear cid pmid ;
gegen double v_cell = mean(v_p), by(cycle_yr pubyear) ;
gen double v_adj = v_p - v_cell ;
gen byte has_nb = n_nb > 0 ;
label var n_nb        "PMRA neighbors of the paper (rank 0 excluded)" ;
label var n_nb_yr     "... with a PubMed 2025 publication year" ;
label var n_early_all "Neighbors published s-10 to s-6, own papers included" ;
label var n_late_all  "Neighbors published s-5 to s-1, own papers included" ;
label var n_own_early "Neighbors in s-10 to s-6 authored by the investigator" ;
label var n_own_late  "Neighbors in s-5 to s-1 authored by the investigator" ;
label var n_own_all   "Neighbors authored by the investigator, any year" ;
label var n_early     "Neighbors published s-10 to s-6, own papers removed" ;
label var n_late      "Neighbors published s-5 to s-1, own papers removed" ;
label var v_p         "Paper vibrancy: late share, at least 5 neighbors in the two windows" ;
label var n_post_all  "Neighbors published s to s+4, own papers included (check only)" ;
label var n_own_post  "Neighbors in s to s+4 authored by the investigator (check only)" ;
label var n_post      "Neighbors published s to s+4, own papers removed (check only)" ;
label var post_share  "n_post / (n_late + n_post), at least 5 (check only, not the measure)" ;
label var v_cell      "Mean v_p of baseline papers with the same cycle_yr and pubyear" ;
label var v_adj       "v_p minus v_cell" ;
label var in_store    "Paper is a source paper of the PMRA store" ;
label var has_nb      "Paper has at least one neighbor" ;

display as result "=== baseline pairs: in the store, with neighbors, with v_p defined" ;
summarize in_store has_nb ;
count if v_p < . ;
display as result "=== pairs with neighbors but fewer than 5 in the two windows (v_p dropped)" ;
count if has_nb & v_p == . ;
display as result "=== neighbor counts per paper, and own-paper neighbors" ;
summarize n_nb n_nb_yr n_early_all n_late_all n_own_all n_early n_late, detail ;
display as result "=== v_p across pairs; with and without own papers removed" ;
gen double v_p_all = n_late_all / (n_early_all + n_late_all) if n_early_all + n_late_all >= 5 ;
summarize v_p v_p_all ;
correlate v_p v_p_all ;
drop v_p_all ;

preserve ;
merge m:1 cid using `keys', keepusing(setnb project_number cycle) ;
keep if _merge == 3 ;
drop _merge cid aid ;
order setnb project_number cycle pmid ;
label data "Baseline papers, PMRA neighbors by window, v_p" ;
notes: Built `c(current_date)' by code/build/26_fading_fields.do. ;
sort setnb project_number cycle pmid ;
compress ;
save "${data}/build/explore/paper_vibrancy.dta", replace ;
restore ;

gen byte one = 1 ;
sort cid pmid ;
gcollapse (sum) n_base = one n_base_store = in_store n_base_nb = has_nb
          (count) n_vp = v_p (mean) vib_pre = v_adj vib_pre_raw = v_p, by(cid) ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
tab _merge ;
assert _merge != 1 ;
drop if _merge == 2 ;
drop _merge cid ;
replace vib_pre = . if n_vp == 0 ;
replace vib_pre_raw = . if n_vp == 0 ;
label var vib_pre_raw  "Mean v_p, unadjusted" ;
label var n_base       "Baseline papers" ;
label var n_base_store "Baseline papers in the PMRA store" ;
label var n_base_nb    "Baseline papers with at least one neighbor" ;
label var n_vp         "Baseline papers with v_p defined" ;
label var vib_pre      "Vibrancy of the field before the cycle: mean of v_p net of its cell mean" ;
order setnb project_number cycle vib_pre vib_pre_raw n_vp n_base n_base_store n_base_nb ;
label data "Vibrancy of the field before the cycle, nih_risk" ;
notes: Built `c(current_date)' by code/build/26_fading_fields.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_fading.dta", replace ;

/* -----------------------------------------------------------------------------
   6. First look
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/output/nih_risk_analysis.dta", keepusing(has_pivot cycle_yr) ;
tab _merge ;
drop _merge ;
gen byte has_vib = vib_pre < . ;
display as result "=== cycles with vib_pre: all analysis cycles, and with pivoting" ;
tab has_vib ;
tab has_vib if has_pivot == 1 ;
display as result "=== vib_pre and its papers, cycles with pivoting" ;
summarize vib_pre n_vp n_base n_base_store if has_pivot == 1, detail ;
summarize vib_pre_raw if has_pivot == 1 ;
correlate vib_pre vib_pre_raw if has_pivot == 1 ;
gen int period = floor(cycle_yr / 5) * 5 ;
display as result "=== vib_pre by start period (cycles with pivoting)" ;
tabstat vib_pre has_vib if has_pivot == 1, by(period) stat(mean sd n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/26_fading_fields.do */
