/* =============================================================================
   config.do

   Purpose: The one file a replicator edits. It declares where the raw sources
            are, where the package writes its data, and which Python the
            build calls. Every do-file of the package includes it first, and
            every path in the code comes from here.

   Use:     Stata's working directory must be the package's root folder (the
            folder that holds master.do). Run master.do from there, or run a
            single do-file from there with  do code/analysis/<file>.do

   Edit:    sections 1 to 3. Nothing else in the package names a folder.
   ============================================================================= */

#delimit ;

capture confirm file "master.do" ;
if _rc {;
    display as error "config.do: Stata's working directory must be the package's root folder (the one that holds master.do)." ;
    exit 601 ;
} ;

/* -----------------------------------------------------------------------------
   1. The raw sources (read only)

      src   the folder under which the raw sources sit, with a trailing slash.
            On the authors' machines Stata's profile.do sets ${F7} to it.
      bulk  the folder of the PubMed baseline in parquet (author names), off
            the main tree. On the authors' machines profile.do sets ${bulk}.
      Only the build reads the raw sources, which are available from the
      authors on request. To replicate the paper's tables and figures from
      the public analysis file included in the package, leave src empty.
   ----------------------------------------------------------------------------- */
if "${F7}" != "" global src "${F7}" ;
else             global src "" ;          /* <- EDIT: e.g. "/data/nih_sources/" */
if "${src}" == "" {;
    display as text "config.do: src is not set (section 1). The build cannot run; the analysis reads only the public analysis file (data/nih_risk_public.zip)." ;
} ;
if "${bulk}" == "" global bulk "" ;        /* <- EDIT: the folder that holds PubMed2026/parquet_merged */

/* the grant-year records with the investigator's gender (cgaf_nih_risk.dta),
   and the frequency of the investigators' last names in Author-ity
   (namefreq_authority.dta) */
global input      "${src}CGAF/2019/r01_project/nih_risk/data/input" ;
/* the NIH grant records' lookups */
global cgaf       "${src}CGAF/2019" ;                       /* crosswalks, study sections, funding, abstracts, patents */
global links      "${src}CGAF/2019/raw/link_tables" ;       /* RePORTER publication links, FY1980 to 2025              */
global cgaf2008   "${src}CGAF/2008/aux_files" ;             /* institution lookup                                      */
/* investigators: honors (stars_all_new.dta) */
global stars      "${src}Bambino/star_files_polished" ;     /* honors of investigators                                 */
/* PubMed 2025 and the resources built on it: Author-ity, OpenAlex citations,
   the disruption index, PMRA neighbors, MeSH trees, textual novelty, patents */
global pubmed_root "${src}PubMed2025" ;
/* a file of an earlier build of the grant data: MTI tags of grant abstracts */
global legacy     "${src}CGAF/2019/r01_project" ;
/* author names of the PubMed baseline, in parquet */
global pq         "${bulk}/PubMed2026/parquet_merged" ;

/* -----------------------------------------------------------------------------
   2. The build's data root (written by the build only; about 2 GB)
   ----------------------------------------------------------------------------- */
global data "D:/nih_risk_replication_data" ;                /* <- EDIT, for the build only */

/* -----------------------------------------------------------------------------
   3. Python: the interpreter that carries duckdb, pandas and pyarrow. On the
      authors' machines profile.do sets ${python} and pins Stata's embedded
      Python to it (python set exec).
   ----------------------------------------------------------------------------- */
if "${python}" == "" global python "python" ;              /* <- EDIT: full path of the interpreter */
/* Inkscape converts the figures from SVG to PDF: found on the PATH, or here */
global inkscape "" ;                                        /* <- EDIT if Inkscape is not on the PATH */

/* -----------------------------------------------------------------------------
   4. Fixed: the package's own folders and settings (do not edit)
   ----------------------------------------------------------------------------- */
global tools "code/programs" ;                              /* format_table.py, svg2pdf.py */
global cpi   "data/cpiaucsl_fred.csv" ;                     /* CPI-U, monthly, FRED CPIAUCSL */
/* the public analysis file, which every do-file of code/analysis reads:
   data/nih_risk_public.zip in the package, unzipped by master.do into
   data/nih_risk_public.dta (written by code/build/34_public_file.do) */
global public "data" ;
adopath ++ "code/programs" ;                                /* supermessoudar.ado */
set varabbrev off ;
set more off ;

capture mkdir "logs" ;
capture mkdir "estimates" ;
capture mkdir "estimates/tex" ;
capture mkdir "graphs" ;
capture mkdir "graphs/gph" ;
capture mkdir "graphs/svg" ;
capture mkdir "graphs/data" ;
capture mkdir "output" ;
capture mkdir "output/tables" ;
capture mkdir "output/figures" ;
/* the build's folders, only where the raw sources are set (section 1) */
if "${src}" != "" {;
    capture mkdir "${data}" ;
    capture mkdir "${data}/build" ;
    capture mkdir "${data}/build/explore" ;
    capture mkdir "${data}/output" ;
} ;
