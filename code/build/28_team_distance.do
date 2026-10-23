/* =============================================================================
   code/build/28_team_distance.do

   Purpose: The distance of the team, for Appendix Figures J1 and J2 and
            Appendix Table J1 (code/analysis/37_figures_J1_J2_table_J1.do), one
            row per analysis-sample cycle: the mean distance between the
            investigator and her collaborators, each side measured on work
            outside the grant, in the cycle's window.
            - the window is the cycle's attributable span, span_start to
              eval_year;
            - the team: the Author-ity coauthors on the cycle's acknowledging
              papers who last-authored, in the window, an original paper with
              at least two named authors that the investigator did not write;
            - two kinds of paper never enter a profile: any paper that
              acknowledges the focal grant (ackn_links_unchecked.dta) and any
              paper the investigator and that collaborator wrote together;
            - the collaborator's profile: her English original papers of the
              window, minus those two kinds; the first kind removes the
              grant's papers she wrote without the investigator, too;
            - the investigator's profile, for each collaborator: her English
              original papers of the window in Author-ity, any position, minus
              those two kinds; papers acknowledging her other grants count. It
              is computed as her full outside profile minus the descriptors of
              the papers she shares with that collaborator, so no pair-level
              profile is stored; a sample of pairs is recomputed directly as a
              check (section 5);
            - the distance of a pair: one minus the cosine of the two
              descriptor profiles, each descriptor weighted by the number of
              the profile's papers that carry it times its IDF over PubMed
              2025 (the log of the number of PubMed 2025 papers with MeSH over
              the number that carry the descriptor, section 4); a pair whose
              investigator side is empty once shared papers are removed has no
              distance;
            - team_dist, the cycle's measure: the mean over its collaborators,
              defined when the investigator has at least three outside papers
              with MeSH in the window (before removing shared papers).
            Kept apart from the analysis file:
            code/analysis/37_figures_J1_J2_table_J1.do merges it.
            Author-ity ends in 2018, so neither side finds papers after 2018.

   Input:
     - ${data}/output/nih_risk_analysis.dta   (code/build/23_analysis_file.do)
     - ${data}/build/cycle_papers.dta         (code/build/03_cycle_papers.do)
     - ${data}/build/ackn_links_unchecked.dta, ackn_links.dta
                                              (code/build/02_ackn_links.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity: the
       authors of each PubMed paper and their position
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_nb_of_authors_2025.dta,
       overall_meshterms_2025.dta   PubMed 2025: year, type, language,
       number of authors and MeSH descriptors of each paper

   Output:
     - ${data}/build/cycle_collabteam.dta   one row per setnb x project_number x cycle

   Note: The DuckDB database team.duckdb, in the machine's temp folder
         (nihrep_team), keeps the Author-ity table (auth) between runs: it is
         loaded from authority_pmids_clean.dta when the database lacks it (or
         when local reuse is not 1), and reused otherwise. This file's own
         tables there carry the prefix tm_. DuckDB with 4 threads and a 6 GB
         limit; about six minutes. Sums of floating-point numbers are exact
         decimal sums (DECIMAL(38,18)), so that they do not depend on the
         order in which DuckDB's threads finish: two runs give identical
         files, and so does Figure J2.
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
log using "logs/28_team_distance.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* reuse switch: 1 keeps the Author-ity table already loaded in the DuckDB file */
local reuse 1 ;
/* the floor: outside papers with MeSH needed for team_dist */
local floor 3 ;

/* -----------------------------------------------------------------------------
   1. Cycles, the cycles' papers, the grants' acknowledgment links
   ----------------------------------------------------------------------------- */
use setnb project_number cycle span_start eval_year author_id using "${data}/output/nih_risk_analysis.dta", clear ;
sort setnb project_number cycle ;
gen long cid = _n ;
count if span_start > eval_year ;
count if missing(author_id) | author_id == "" ;
tempfile keys ;
save `keys' ;

use setnb project_number cycle pmid ackn author_seq using "${data}/build/cycle_papers.dta", clear ;
merge m:1 setnb project_number cycle using `keys', keepusing(cid) ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
preserve ;
keep if ackn == 1 ;
keep cid pmid author_seq ;
gisid cid pmid ;
tempfile fa ;
save `fa' ;
restore ;
keep cid pmid ;
tempfile fown ;
save `fown' ;

/* -----------------------------------------------------------------------------
   2. Paper attributes: year, original research, English, author counts
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
merge 1:1 pmid using `typ' ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using `lng' ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using "${pubmed_root}/pubmed/overall_nb_of_authors_2025.dta", keepusing(nb_authrs max_authr_seq) ;
drop if _merge == 2 ;
drop _merge ;
replace orgnl = 0 if orgnl == . ;
replace eng   = 0 if eng == . ;
compress ;
tempfile info ;
save `info' ;

/* -----------------------------------------------------------------------------
   3. The team, the profiles' papers, the shared papers, in DuckDB (block 1)
   ----------------------------------------------------------------------------- */
tempfile need ;
global l_keys  "`keys'" ;
global l_fa    "`fa'" ;
global l_fown  "`fown'" ;
global l_info  "`info'" ;
global l_gack  "${data}/build/ackn_links_unchecked.dta" ;
global l_alnk  "${data}/build/ackn_links.dta" ;
global l_auth  "${pubmed_root}/authority/authority_pmids_clean.dta" ;
global l_need  "`need'" ;
global l_reuse "`reuse'" ;

#delimit cr
python:
import os, tempfile, traceback, time
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
tmp = os.path.join(tempfile.gettempdir(), "nihrep_team")
spill = os.path.join(tmp, "spill")
os.makedirs(spill, exist_ok=True)
def say(s):
    SFIToolkit.display(time.strftime("%H:%M:%S") + "  " + s)
con = duckdb.connect(os.path.join(tmp, "team.duckdb"))
try:
    _ = con.execute("SET threads=4")
    _ = con.execute("SET memory_limit='6GB'")
    _ = con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    _ = con.execute("SET preserve_insertion_order=false")
    have = con.execute("SELECT count(*) FROM information_schema.tables WHERE table_name = 'auth'").fetchone()[0]
    if have == 0 or g("l_reuse") != "1":
        _ = con.execute("DROP TABLE IF EXISTS auth")
        _ = con.execute("CREATE TABLE auth (author_id VARCHAR, pmid INTEGER, pos SMALLINT)")
        n = 0
        for ch in pd.read_stata(g("l_auth"), columns=["author_id", "pmid", "author_postn"], chunksize=10_000_000):
            con.register("ch_df", ch)
            _ = con.execute("INSERT INTO auth SELECT author_id, CAST(pmid AS INTEGER), CAST(author_postn AS SMALLINT) FROM ch_df")
            con.unregister("ch_df")
            n += len(ch)
            say("Author-ity rows loaded: {:,}".format(n))
    say("Author-ity rows in table: {:,}".format(con.execute("SELECT count(*) FROM auth").fetchone()[0]))

    def load(name, path, sql, cols=None):
        df = pd.read_stata(path, columns=cols, convert_categoricals=False)
        con.register(name + "_df", df)
        _ = con.execute("CREATE OR REPLACE TEMP TABLE {} AS {}".format(name, sql.replace("{df}", name + "_df")))
        con.unregister(name + "_df")
    load("keys", g("l_keys"), "SELECT CAST(cid AS INTEGER) cid, CAST(span_start AS INTEGER) y0, CAST(eval_year AS INTEGER) y1, author_id AS fid, setnb, project_number AS pnum FROM {df}")
    load("fa",   g("l_fa"),   "SELECT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid, CAST(author_seq AS INTEGER) seq FROM {df}")
    load("fown", g("l_fown"), "SELECT DISTINCT CAST(cid AS INTEGER) cid, CAST(pmid AS INTEGER) pmid FROM {df}")
    load("gack", g("l_gack"), "SELECT DISTINCT CAST(pmid AS INTEGER) pmid, project_number AS pnum FROM {df}", ["pmid", "project_number"])
    load("alnk", g("l_alnk"), "SELECT DISTINCT setnb, project_number AS pnum, CAST(pmid AS INTEGER) pmid FROM {df}", ["setnb", "project_number", "pmid"])
    _ = con.execute("CREATE OR REPLACE TEMP TABLE info (pmid INTEGER, yr SMALLINT, orgnl TINYINT, eng TINYINT, nauth INTEGER, maxseq INTEGER)")
    for ch in pd.read_stata(g("l_info"), columns=["pmid", "year", "orgnl", "eng", "nb_authrs", "max_authr_seq"], chunksize=10_000_000):
        con.register("ch_df", ch)
        _ = con.execute("INSERT INTO info SELECT CAST(pmid AS INTEGER), CAST(year AS SMALLINT), CAST(orgnl AS TINYINT), CAST(eng AS TINYINT), CAST(nb_authrs AS INTEGER), CAST(max_authr_seq AS INTEGER) FROM ch_df")
        con.unregister("ch_df")
    say("paper attributes: {:,}".format(con.execute("SELECT count(*) FROM info").fetchone()[0]))

    # every paper acknowledging the focal grant, any year
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE gx AS
        SELECT DISTINCT k.cid, g.pmid FROM keys k JOIN gack g ON g.pnum = k.pnum""")
    # the team: the Author-ity coauthors on the cycle's acknowledging papers,
    # the investigator aside (cand), who last-authored, in the window, an
    # original paper with at least two named authors that the investigator
    # did not write (qual)
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE cand AS
        SELECT DISTINCT f.cid, a.author_id
        FROM fa f JOIN keys k USING (cid) JOIN auth a ON a.pmid = f.pmid
        WHERE a.pos <> f.seq AND a.author_id <> coalesce(k.fid, '')""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE excl AS
        SELECT cid, pmid FROM fown
        UNION
        SELECT k.cid, a.pmid FROM keys k JOIN auth a ON a.author_id = k.fid
        JOIN info i ON i.pmid = a.pmid WHERE i.yr BETWEEN k.y0 AND k.y1""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE cpap AS
        SELECT a.author_id, a.pmid, a.pos, i.yr, i.eng, i.nauth, i.maxseq
        FROM auth a JOIN info i ON i.pmid = a.pmid
        WHERE i.orgnl = 1 AND a.author_id IN (SELECT DISTINCT author_id FROM cand)""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE cpub AS
        SELECT c.cid, c.author_id, p.pmid, p.pos, p.eng, p.nauth, p.maxseq
        FROM cand c JOIN keys k USING (cid) JOIN cpap p ON p.author_id = c.author_id
        WHERE p.yr BETWEEN k.y0 AND k.y1
        AND NOT EXISTS (SELECT 1 FROM excl e WHERE e.cid = c.cid AND e.pmid = p.pmid)""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE qual AS
        SELECT cid, author_id FROM cpub GROUP BY cid, author_id
        HAVING bool_or(pos = maxseq AND nauth >= 2)""")
    # the collaborator's profile: English, not shared, not acknowledging the grant
    _ = con.execute("CREATE TABLE IF NOT EXISTS tm_prof (cid INTEGER, author_id VARCHAR, pmid INTEGER)")
    _ = con.execute("DELETE FROM tm_prof")
    _ = con.execute("""INSERT INTO tm_prof
        SELECT DISTINCT p.cid, p.author_id, p.pmid FROM cpub p
        SEMI JOIN qual q ON q.cid = p.cid AND q.author_id = p.author_id
        WHERE p.eng = 1
        AND NOT EXISTS (SELECT 1 FROM gx WHERE gx.cid = p.cid AND gx.pmid = p.pmid)""")
    # the investigator's outside papers: English original research of the
    # window, not acknowledging the focal grant; og marks those acknowledging
    # another of her grants
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE fout0 AS
        SELECT DISTINCT k.cid, a.pmid FROM keys k JOIN auth a ON a.author_id = k.fid
        JOIN info i ON i.pmid = a.pmid
        WHERE i.yr BETWEEN k.y0 AND k.y1 AND i.orgnl = 1 AND i.eng = 1""")
    _ = con.execute("CREATE TABLE IF NOT EXISTS tm_fout (cid INTEGER, pmid INTEGER, og TINYINT)")
    _ = con.execute("DELETE FROM tm_fout")
    _ = con.execute("""INSERT INTO tm_fout
        SELECT f.cid, f.pmid, max(CASE WHEN l.pmid IS NULL THEN 0 ELSE 1 END)
        FROM fout0 f JOIN keys k USING (cid)
        LEFT JOIN alnk l ON l.pmid = f.pmid AND l.setnb = k.setnb AND l.pnum <> k.pnum
        WHERE NOT EXISTS (SELECT 1 FROM gx WHERE gx.cid = f.cid AND gx.pmid = f.pmid)
        AND NOT EXISTS (SELECT 1 FROM fa WHERE fa.cid = f.cid AND fa.pmid = f.pmid)
        GROUP BY f.cid, f.pmid""")
    # her outside papers written with each collaborator
    _ = con.execute("CREATE TABLE IF NOT EXISTS tm_fsh (cid INTEGER, author_id VARCHAR, pmid INTEGER)")
    _ = con.execute("DELETE FROM tm_fsh")
    _ = con.execute("""INSERT INTO tm_fsh
        SELECT DISTINCT q.cid, q.author_id, f.pmid
        FROM qual q JOIN tm_fout f ON f.cid = q.cid
        JOIN auth a ON a.pmid = f.pmid AND a.author_id = q.author_id""")
    # counts by cycle
    _ = con.execute("CREATE TABLE IF NOT EXISTS tm_cnt (cid INTEGER, n_cand INTEGER, n_qual INTEGER, n_fout INTEGER, n_fout_og INTEGER)")
    _ = con.execute("DELETE FROM tm_cnt")
    _ = con.execute("""INSERT INTO tm_cnt
        SELECT k.cid, coalesce(c.n, 0), coalesce(q.n, 0), coalesce(o.n, 0), coalesce(o.nog, 0) FROM keys k
        LEFT JOIN (SELECT cid, count(*) n FROM cand GROUP BY cid) c USING (cid)
        LEFT JOIN (SELECT cid, count(*) n FROM qual GROUP BY cid) q USING (cid)
        LEFT JOIN (SELECT cid, count(*) n, sum(og) nog FROM tm_fout GROUP BY cid) o USING (cid)""")
    d = con.execute("""SELECT (SELECT count(*) FROM cand) n_cand, (SELECT count(*) FROM qual) n_qual,
                              (SELECT count(*) FROM tm_prof) n_prof_rows, (SELECT count(*) FROM tm_fout) n_fout_rows,
                              (SELECT sum(og) FROM tm_fout) n_fout_og, (SELECT count(*) FROM tm_fsh) n_shared_rows,
                              (SELECT count(*) FROM gx) n_grant_papers""").df()
    say("candidates, collaborators, collaborator profile rows, outside papers (cycle x paper), of which other grants, shared pair rows, focal-grant papers: " + d.to_string(index=False, header=False))
    need = con.execute("SELECT pmid FROM tm_prof UNION SELECT pmid FROM tm_fout ORDER BY pmid").df()
    for t in ["cpub", "cpap", "excl", "cand", "qual", "info", "fout0", "gx", "gack", "alnk"]:
        _ = con.execute("DROP TABLE IF EXISTS " + t)
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
say("papers whose MeSH is needed: {:,}".format(len(need)))
need.to_stata(g("l_need"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   4. IDF over PubMed 2025 by descriptor, ln(papers with MeSH / papers that
      carry the descriptor), and the MeSH of the needed papers, in four slices
      of PMIDs
   ----------------------------------------------------------------------------- */
local cut0 = 0 ;
local cut1 = 10000000 ;
local cut2 = 20000000 ;
local cut3 = 30000000 ;
local cut4 = 1e12 ;
tempfile idfacc meshacc ;
local npap = 0 ;
forvalues s = 1/4 {;
    local lo = `cut`=`s'-1'' ;
    local hi = `cut`s'' ;
    use pmid dscrptr_ui if pmid >= `lo' & pmid < `hi'
        using "${pubmed_root}/pubmed/overall_meshterms_2025.dta", clear ;
    drop if missing(dscrptr_ui) | missing(pmid) ;
    gcontract pmid dscrptr_ui ;
    drop _freq ;
    gegen byte tp = tag(pmid) ;
    quietly count if tp ;
    local npap = `npap' + r(N) ;
    drop tp ;
    preserve ;
    merge m:1 pmid using `need' ;
    keep if _merge == 3 ;
    drop _merge ;
    if `s' > 1 append using `meshacc' ;
    save `meshacc', replace ;
    restore ;
    gcollapse (count) n_d = pmid, by(dscrptr_ui) ;
    if `s' > 1 append using `idfacc' ;
    save `idfacc', replace ;
} ;
gcollapse (sum) n_d, by(dscrptr_ui) ;
gen double idf = ln(`npap' / n_d) ;
display as result "=== PubMed 2025 papers with MeSH: " %14.0fc `npap' ;
gisid dscrptr_ui ;
keep dscrptr_ui idf ;
tempfile idf ;
save `idf' ;

/* -----------------------------------------------------------------------------
   5. The distances, in DuckDB (block 2), in eight slices of cycles; then a
      direct recomputation on a sample of pairs
   ----------------------------------------------------------------------------- */
tempfile res ;
global l_mesh "`meshacc'" ;
global l_idf  "`idf'" ;
global l_res  "`res'" ;

#delimit cr
python:
import os, tempfile, traceback, time
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

g = Macro.getGlobal
tmp = os.path.join(tempfile.gettempdir(), "nihrep_team")
def say(s):
    SFIToolkit.display(time.strftime("%H:%M:%S") + "  " + s)
con = duckdb.connect(os.path.join(tmp, "team.duckdb"))
try:
    _ = con.execute("SET threads=4")
    _ = con.execute("SET memory_limit='6GB'")
    _ = con.execute("SET temp_directory='{}'".format(os.path.join(tmp, "spill").replace("\\", "/")))
    _ = con.execute("SET preserve_insertion_order=false")
    mesh = pd.read_stata(g("l_mesh"), convert_categoricals=False)
    con.register("mesh_df", mesh)
    _ = con.execute("CREATE OR REPLACE TEMP TABLE mesh AS SELECT DISTINCT CAST(pmid AS INTEGER) pmid, CAST(dscrptr_ui AS INTEGER) d FROM mesh_df")
    con.unregister("mesh_df")
    del mesh
    idf = pd.read_stata(g("l_idf"), convert_categoricals=False)
    con.register("idf_df", idf)
    _ = con.execute("CREATE OR REPLACE TEMP TABLE idf AS SELECT CAST(dscrptr_ui AS INTEGER) d, CAST(idf AS DOUBLE) w FROM idf_df")
    con.unregister("idf_df")
    say("MeSH rows of needed papers: {:,}".format(con.execute("SELECT count(*) FROM mesh").fetchone()[0]))
    _ = con.execute("CREATE OR REPLACE TEMP TABLE mp AS SELECT DISTINCT pmid FROM mesh")
    # the investigator's full outside profile, and her outside papers with MeSH
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE nfm AS
        SELECT f.cid, count(*) n_fm FROM tm_fout f SEMI JOIN mp ON mp.pmid = f.pmid GROUP BY f.cid""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE fd AS
        SELECT f.cid, m.d, count(*) fr FROM tm_fout f JOIN mesh m ON m.pmid = f.pmid GROUP BY ALL""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE fn AS
        SELECT fd.cid, CAST(sum(CAST(power(fd.fr * i.w, 2) AS DECIMAL(38,18))) AS DOUBLE) ff FROM fd JOIN idf i USING (d) GROUP BY fd.cid""")
    # the papers she shares with each collaborator: their descriptors, their
    # number, and the correction to her profile's squared norm
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE sdv AS
        SELECT s.cid, s.author_id, m.d, count(*) fr FROM tm_fsh s JOIN mesh m ON m.pmid = s.pmid GROUP BY ALL""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE nsm AS
        SELECT s.cid, s.author_id, count(*) n_sm FROM tm_fsh s SEMI JOIN mp ON mp.pmid = s.pmid GROUP BY ALL""")
    _ = con.execute("""CREATE OR REPLACE TEMP TABLE cff AS
        SELECT s.cid, s.author_id, CAST(sum(CAST(i.w * i.w * (f.fr * f.fr - (f.fr - s.fr) * (f.fr - s.fr)) AS DECIMAL(38,18))) AS DOUBLE) corr
        FROM sdv s JOIN fd f ON f.cid = s.cid AND f.d = s.d JOIN idf i ON i.d = s.d GROUP BY ALL""")
    say("cycles with an outside paper with MeSH: {:,}; pairs with a shared outside paper with MeSH: {:,}".format(
        con.execute("SELECT count(*) FROM nfm").fetchone()[0],
        con.execute("SELECT count(*) FROM nsm").fetchone()[0]))
    _ = con.execute("CREATE OR REPLACE TEMP TABLE resc (cid INTEGER, author_id VARCHAR, cosdis DOUBLE, sh DOUBLE)")
    K = 8
    for k in range(K):
        _ = con.execute("CREATE OR REPLACE TEMP TABLE pc AS SELECT * FROM tm_prof WHERE cid % {} = {}".format(K, k))
        _ = con.execute("""CREATE OR REPLACE TEMP TABLE cdv AS
            SELECT pc.cid, pc.author_id, m.d, count(*) fr
            FROM pc JOIN mesh m ON m.pmid = pc.pmid SEMI JOIN fn ON fn.cid = pc.cid
            GROUP BY ALL""")
        _ = con.execute("""INSERT INTO resc
            WITH cn AS (SELECT c.cid, c.author_id, CAST(sum(CAST(power(c.fr * i.w, 2) AS DECIMAL(38,18))) AS DOUBLE) cc FROM cdv c JOIN idf i USING (d) GROUP BY ALL),
                 dtf AS (SELECT c.cid, c.author_id, CAST(sum(CAST(c.fr * f.fr * i.w * i.w AS DECIMAL(38,18))) AS DOUBLE) dot
                         FROM cdv c JOIN fd f ON f.cid = c.cid AND f.d = c.d JOIN idf i ON i.d = c.d GROUP BY ALL),
                 dtc AS (SELECT c.cid, c.author_id, CAST(sum(CAST(c.fr * s.fr * i.w * i.w AS DECIMAL(38,18))) AS DOUBLE) dot
                         FROM cdv c JOIN sdv s ON s.cid = c.cid AND s.author_id = c.author_id AND s.d = c.d
                         JOIN idf i ON i.d = c.d GROUP BY ALL),
                 pr AS (SELECT cn.cid, cn.author_id, cn.cc, n.n_fm, coalesce(ns.n_sm, 0) n_sm,
                               fn.ff - coalesce(cf.corr, 0) ffp, coalesce(dtf.dot, 0) - coalesce(dtc.dot, 0) dotp
                        FROM cn JOIN fn ON fn.cid = cn.cid JOIN nfm n ON n.cid = cn.cid
                        LEFT JOIN nsm ns ON ns.cid = cn.cid AND ns.author_id = cn.author_id
                        LEFT JOIN cff cf ON cf.cid = cn.cid AND cf.author_id = cn.author_id
                        LEFT JOIN dtf ON dtf.cid = cn.cid AND dtf.author_id = cn.author_id
                        LEFT JOIN dtc ON dtc.cid = cn.cid AND dtc.author_id = cn.author_id)
            SELECT cid, author_id,
                   CASE WHEN n_fm - n_sm >= 1 AND cc > 0 AND ffp > 0
                        THEN greatest(0.0, least(1.0, 1 - dotp / sqrt(cc * ffp))) END,
                   CAST(n_sm AS DOUBLE) / n_fm
            FROM pr""")
        say("slice {} of {}: pairs so far {:,}".format(k + 1, K, con.execute("SELECT count(*) FROM resc").fetchone()[0]))
    # check: recompute a sample of pairs with each pair's profile built directly
    chk = con.execute("""
        WITH pr AS (SELECT cid, author_id, cosdis FROM resc WHERE cid % 97 = 0 AND cosdis IS NOT NULL),
             fp AS (SELECT pr.cid, pr.author_id, f.pmid FROM pr JOIN tm_fout f ON f.cid = pr.cid
                    WHERE NOT EXISTS (SELECT 1 FROM tm_fsh s WHERE s.cid = pr.cid AND s.author_id = pr.author_id AND s.pmid = f.pmid)),
             fv AS (SELECT fp.cid, fp.author_id, m.d, count(*) fr FROM fp JOIN mesh m ON m.pmid = fp.pmid GROUP BY ALL),
             cv AS (SELECT p.cid, p.author_id, m.d, count(*) fr FROM tm_prof p
                    JOIN pr ON pr.cid = p.cid AND pr.author_id = p.author_id JOIN mesh m ON m.pmid = p.pmid GROUP BY ALL),
             nf AS (SELECT fv.cid, fv.author_id, sum(power(fv.fr * i.w, 2)) ff FROM fv JOIN idf i USING (d) GROUP BY ALL),
             nc AS (SELECT cv.cid, cv.author_id, sum(power(cv.fr * i.w, 2)) cc FROM cv JOIN idf i USING (d) GROUP BY ALL),
             dt AS (SELECT c.cid, c.author_id, sum(c.fr * f.fr * i.w * i.w) dot FROM cv c
                    JOIN fv f ON f.cid = c.cid AND f.author_id = c.author_id AND f.d = c.d JOIN idf i ON i.d = c.d GROUP BY ALL)
        SELECT count(*) n_pairs,
               max(abs(pr.cosdis - (1 - coalesce(dt.dot, 0) / sqrt(nc.cc * nf.ff)))) max_abs_diff
        FROM pr JOIN nf ON nf.cid = pr.cid AND nf.author_id = pr.author_id
        JOIN nc ON nc.cid = pr.cid AND nc.author_id = pr.author_id
        LEFT JOIN dt ON dt.cid = pr.cid AND dt.author_id = pr.author_id""").df()
    say("CHECK, direct recomputation of a sample of pairs (pairs, largest absolute difference): " + chk.to_string(index=False, header=False))
    res = con.execute("""
        SELECT c.cid, c.n_cand, c.n_qual, c.n_fout, c.n_fout_og, coalesce(n.n_fm, 0) n_fout_mesh,
               CAST(sum(CAST(r.cosdis AS DECIMAL(38,18))) AS DOUBLE) / count(r.cosdis) team_dist_nofloor,
               count(r.cosdis) n_collab_team,
               CAST(sum(CAST(r.sh AS DECIMAL(38,18))) FILTER (WHERE r.cosdis IS NOT NULL) AS DOUBLE)
                   / count(r.sh) FILTER (WHERE r.cosdis IS NOT NULL) sh_shared
        FROM tm_cnt c LEFT JOIN nfm n USING (cid) LEFT JOIN resc r USING (cid)
        GROUP BY c.cid, c.n_cand, c.n_qual, c.n_fout, c.n_fout_og, n.n_fm ORDER BY c.cid""").df()
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
say("cycles: {:,}".format(len(res)))
res.to_stata(g("l_res"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   6. Assemble and save
   ----------------------------------------------------------------------------- */
use `res', clear ;
merge 1:1 cid using `keys', keepusing(setnb project_number cycle) ;
tab _merge ;
assert _merge == 3 ;
drop _merge cid ;
foreach v in n_cand n_qual n_fout n_fout_og n_fout_mesh n_collab_team {;
    replace `v' = 0 if `v' == . ;
} ;
gen double team_dist = team_dist_nofloor if n_fout_mesh >= `floor' ;
label var team_dist         "Team distance: mean over collaborators of 1 - TF-IDF cosine, outside the grant" ;
label var team_dist_nofloor "Team distance before the floor of `floor' outside papers with MeSH (not the measure)" ;
label var n_cand            "Coauthors on the cycle's acknowledging papers (Author-ity)" ;
label var n_qual            "Coauthors qualifying as collaborators (last-authored multi-author paper in span)" ;
label var n_collab_team     "Collaborators behind team_dist_nofloor" ;
label var n_fout            "Investigator's outside papers: English original, in span, not acknowledging the grant" ;
label var n_fout_og         "Outside papers acknowledging another of the investigator's grants" ;
label var n_fout_mesh       "Outside papers with MeSH" ;
label var sh_shared         "Mean share of outside papers with MeSH written with the collaborator" ;
order setnb project_number cycle team_dist team_dist_nofloor n_fout_mesh n_fout n_fout_og n_collab_team n_qual n_cand sh_shared ;
label data "Team distance, nih_risk" ;
notes: Built `c(current_date)' by code/build/28_team_distance.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_collabteam.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/28_team_distance.do */
