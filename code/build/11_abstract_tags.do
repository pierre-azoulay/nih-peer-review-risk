/* =============================================================================
   code/build/11_abstract_tags.do

   Purpose: The comparison pools of standing out (code/build/12_standing_out.do)
            and their MeSH tags. A pool is every application funded in the
            cycle's institute x study section x evaluation year (any mechanism,
            continuation years included). The tags are those that NLM's Medical
            Text Indexer (MTI) assigned to 764,867 grant abstracts in 2022 and
            2024; MTI has been discontinued, and its successor MTIX is not
            offered to outside users, so no other abstract can be tagged. Each
            application in a pool
            therefore takes:
            - its own MTI tags when it has them (tag_src 1);
            - otherwise the tags of an MTI-tagged abstract whose text is identical
              once lowered, stripped of non-ASCII characters and of repeated spaces
              (tag_src 2); among several, the closest fiscal year, then the lowest
              application ID;
            - otherwise none (tag_src 0): it stays out of the pool, as do
              abstracts without usable text.
            Continuation years repeat the abstract of the competing year, so most
            untagged applications have such a twin. The tags are recoded to the
            descriptor codes of PubMed 2025 through the descriptor IDs, since the
            two files number descriptors differently. Texts come from the raw
            RePORTER files, read as UTF-8, or as Latin-1 where UTF-8 fails
            (FY2011 to 2021).

   Input:
     - ${data}/build/cycles.dta          (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta    (code/build/03_cycle_papers.do)
     - ${cgaf}/cgaf_study_sections_000.dta   application x study section x year
     - ${cgaf}/raw/abstracts/RePORTER_PRJABS_C_FY1980.csv to FY2025.csv
     - ${legacy}/project/abstract_data/aux_files/mtimesh_single4pub.dta
       MTI tags of grant abstracts (application x descriptor)
     - ${pubmed_root}/pubmed/overall_meshterms_2025.dta (its value label only)

   Output:
     - ${data}/build/abstract_pool.dta   one row per application in a needed cell
     - ${data}/build/abstract_tags.dta   application x descriptor (PubMed 2025 codes)
     - ${data}/build/mti_vocab.dta       descriptors (PubMed 2025 codes) of the MTI
                                         tag vocabulary

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
log using "logs/11_abstract_tags.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. The cells needed: institute x study section x evaluation year of every cycle
      with an acknowledging paper
   ----------------------------------------------------------------------------- */
use setnb project_number cycle ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
bysort setnb project_number cycle: keep if _n == 1 ;
keep setnb project_number cycle ;
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta", keepusing(ic irg_code eval_year) ;
assert _merge != 1 ;
keep if _merge == 3 & irg_code != "" ;
rename eval_year year ;
keep ic irg_code year ;
bysort ic irg_code year: keep if _n == 1 ;
display as result "=== cells needed" ;
count ;
tempfile cells ;
save `cells' ;

/* -----------------------------------------------------------------------------
   2. The applications in those cells
   ----------------------------------------------------------------------------- */
use app_id year ic study_section using "${cgaf}/cgaf_study_sections_000.dta", clear ;
rename study_section irg_code ;
merge m:1 ic irg_code year using `cells' ;
display as result "=== cells needed with at least one application (2 = none, or after FY2021)" ;
preserve ;
    bysort ic irg_code year: keep if _n == 1 ;
    tab _merge ;
restore ;
keep if _merge == 3 ;
drop _merge ;
gisid app_id ;
display as result "=== applications in the cells needed" ;
count ;
tempfile pool ;
save `pool' ;

/* applications already tagged by MTI */
use app_id using "${legacy}/project/abstract_data/aux_files/mtimesh_single4pub.dta", clear ;
bysort app_id: keep if _n == 1 ;
tempfile tagged ;
save `tagged' ;

/* -----------------------------------------------------------------------------
   3. Texts, fingerprints and twins, in DuckDB
   ----------------------------------------------------------------------------- */
tempfile src ;
global at_pool   "`pool'" ;
global at_tagged "`tagged'" ;
global at_src    "`src'" ;
global at_raw    "${cgaf}/raw/abstracts" ;

#delimit cr
python:
import os, tempfile, traceback
import duckdb
import pandas as pd
from sfi import Macro, SFIToolkit

pool   = pd.read_stata(Macro.getGlobal("at_pool"))[["app_id", "year"]]
tagged = pd.read_stata(Macro.getGlobal("at_tagged"))
raw    = Macro.getGlobal("at_raw").replace("\\", "/")
spill  = os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_tags")
os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=16")
    con.execute("SET temp_directory='{}'".format(spill.replace("\\", "/")))
    con.execute("SET preserve_insertion_order=false")
    con.register("pool_df", pool)
    con.register("tagged_df", tagged)
    con.execute("CREATE TEMP TABLE pool AS SELECT CAST(app_id AS BIGINT) app_id, CAST(year AS INTEGER) fy FROM pool_df")
    con.execute("CREATE TEMP TABLE tagged AS SELECT DISTINCT CAST(app_id AS BIGINT) app_id FROM tagged_df")
    con.execute("CREATE TEMP TABLE want AS SELECT app_id FROM pool UNION SELECT app_id FROM tagged")
    con.execute("CREATE TEMP TABLE txt (app_id BIGINT, fy INTEGER, h VARCHAR)")
    # the files are UTF-8, except FY2011 to 2021, which are read as Latin-1; pandas
    # parses them (DuckDB's decoders reject some); non-ASCII characters are dropped
    # before hashing either way
    enc_used = []
    for y in range(1980, 2026):
        f = "{}/RePORTER_PRJABS_C_FY{}.csv".format(raw, y)
        for enc in ("utf-8", "latin-1"):
            try:
                df = pd.read_csv(f, dtype=str, encoding=enc, keep_default_na=False)
                break
            except UnicodeDecodeError:
                continue
        if enc != "utf-8":
            enc_used.append(str(y))
        df.columns = [c.lower() for c in df.columns]
        con.register("raw_df", df)
        con.execute("""
            INSERT INTO txt
            SELECT app_id, {y} AS fy,
                   CASE WHEN length(t) > 150 THEN md5(t) END AS h
            FROM (
                SELECT TRY_CAST(application_id AS BIGINT) AS app_id,
                       trim(regexp_replace(regexp_replace(lower(abstract_text),
                            '[^\\x00-\\x7F]', '', 'g'), '\\s+', ' ', 'g')) AS t
                FROM raw_df
            ) SEMI JOIN want USING (app_id)""".replace("{y}", str(y)))
        con.unregister("raw_df")
        del df
    n_dup = con.execute("SELECT count(*) - count(DISTINCT app_id) FROM txt").fetchone()[0]
    # one text per application: the earliest fiscal year that has it
    con.execute("""CREATE TEMP TABLE txt1 AS
        SELECT app_id, arg_min(h, fy) AS h FROM txt GROUP BY app_id""")
    # tagged texts and their fiscal years (from the file that holds them)
    con.execute("""CREATE TEMP TABLE ttag AS
        SELECT t.app_id, min(t.fy) AS fy, any_value(x.h) AS h
        FROM txt t JOIN txt1 x USING (app_id) SEMI JOIN tagged USING (app_id)
        WHERE x.h IS NOT NULL GROUP BY t.app_id""")
    res = con.execute("""
        WITH p AS (
            SELECT p.app_id, p.fy, x.h, (t.app_id IS NOT NULL) AS own
            FROM pool p LEFT JOIN txt1 x ON x.app_id = p.app_id LEFT JOIN tagged t ON t.app_id = p.app_id),
        tw AS (
            SELECT p.app_id, tt.app_id AS src_app_id,
                   row_number() OVER (PARTITION BY p.app_id ORDER BY abs(tt.fy - p.fy), tt.app_id) AS r
            FROM p JOIN ttag tt ON tt.h = p.h
            WHERE NOT p.own AND p.h IS NOT NULL)
        SELECT p.app_id,
               CAST(p.h IS NOT NULL AS INTEGER) AS has_text,
               CAST(CASE WHEN p.own THEN 1 WHEN tw.src_app_id IS NOT NULL THEN 2 ELSE 0 END AS INTEGER) AS tag_src,
               CASE WHEN p.own THEN p.app_id ELSE tw.src_app_id END AS src_app_id
        FROM p LEFT JOIN tw ON tw.app_id = p.app_id AND tw.r = 1
        ORDER BY p.app_id""").df()
    n_txt = con.execute("SELECT count(*) FROM txt1").fetchone()[0]
except Exception:
    SFIToolkit.display(traceback.format_exc())
    raise
finally:
    con.close()
SFIToolkit.display("files read as Latin-1: FY" + ", ".join(enc_used))
SFIToolkit.display("texts read for {:,} applications ({:,} in two fiscal-year files)".format(n_txt, n_dup))
res["src_app_id"] = res["src_app_id"].astype("float64")
res.to_stata(Macro.getGlobal("at_src"), write_index=False)
end
#delimit ;

/* -----------------------------------------------------------------------------
   4. The pool file
   ----------------------------------------------------------------------------- */
use `pool', clear ;
merge 1:1 app_id using `src' ;
assert _merge == 3 ;
drop _merge ;
capture label drop tagsrc ;
label define tagsrc 0 "none" 1 "own MTI tags" 2 "tags of an identical abstract" ;
label values tag_src tagsrc ;
label var has_text   "Abstract text longer than 150 characters" ;
label var tag_src    "Source of the application's MeSH tags" ;
label var src_app_id "Application whose MTI tags it takes" ;
label data "Applications in the standing-out comparison cells, nih_risk" ;
notes: Built `c(current_date)' by code/build/11_abstract_tags.do. ;
order app_id ic irg_code year has_text tag_src src_app_id ;
sort app_id ;
compress ;
save "${data}/build/abstract_pool.dta", replace ;
display as result "=== applications in the cells needed: source of tags, by text" ;
tab has_text tag_src ;
gen int decade = 10 * floor(year / 10) ;
display as result "=== source of tags by decade" ;
tab decade tag_src, row nofreq ;

/* -----------------------------------------------------------------------------
   5. Descriptor codes: MTI file to PubMed 2025, through the descriptor IDs
   ----------------------------------------------------------------------------- */
use in 1 using "${legacy}/project/abstract_data/aux_files/mtimesh_single4pub.dta", clear ;
uselabel dscrptr_ui, clear ;
keep value label ;
rename (value label) (code_mti ui) ;
tempfile lab_mti ;
save `lab_mti' ;
use in 1 using "${pubmed_root}/pubmed/overall_meshterms_2025.dta", clear ;
uselabel dscrptr_ui_lbl, clear ;
keep value label ;
rename (value label) (code_25 ui) ;
gisid ui ;
merge 1:1 ui using `lab_mti' ;
display as result "=== descriptor IDs: PubMed 2025 only (1), MTI file only (2), both (3)" ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
tempfile map ;
save `map' ;
keep code_25 ;
rename code_25 dscrptr_ui ;
label var dscrptr_ui "Descriptor (PubMed 2025 code) in the MTI tag vocabulary" ;
label data "Descriptors common to the MTI tags and PubMed 2025, nih_risk" ;
notes: Built `c(current_date)' by code/build/11_abstract_tags.do. ;
sort dscrptr_ui ;
compress ;
save "${data}/build/mti_vocab.dta", replace ;

/* -----------------------------------------------------------------------------
   6. The tags of every pool application, in PubMed 2025 codes
   ----------------------------------------------------------------------------- */
use app_id src_app_id tag_src using "${data}/build/abstract_pool.dta", clear ;
keep if tag_src > 0 ;
keep app_id src_app_id ;
tempfile srcmap ;
save `srcmap' ;
keep src_app_id ;
bysort src_app_id: keep if _n == 1 ;
rename src_app_id app_id ;
merge 1:m app_id using "${legacy}/project/abstract_data/aux_files/mtimesh_single4pub.dta" ;
keep if _merge == 3 ;
drop _merge ;
rename (app_id dscrptr_ui) (src_app_id code_mti) ;
merge m:1 code_mti using `map', keepusing(code_25) ;
display as result "=== MTI tags whose descriptor is absent from PubMed 2025 (1, dropped)" ;
tab _merge ;
keep if _merge == 3 ;
keep src_app_id code_25 ;
joinby src_app_id using `srcmap' ;
rename code_25 dscrptr_ui ;
keep app_id dscrptr_ui ;
gisid app_id dscrptr_ui ;
label var dscrptr_ui "MeSH descriptor (PubMed 2025 code), from MTI" ;
label data "MeSH tags of the standing-out pool applications, nih_risk" ;
notes: Built `c(current_date)' by code/build/11_abstract_tags.do. ;
sort app_id dscrptr_ui ;
compress ;
save "${data}/build/abstract_tags.dta", replace ;
display as result "=== tags per tagged pool application" ;
bysort app_id: gen int ntags = _N ;
bysort app_id: keep if _n == 1 ;
summarize ntags, detail ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/11_abstract_tags.do */
