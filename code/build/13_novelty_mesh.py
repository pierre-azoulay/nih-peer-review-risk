"""
code/build/13_novelty_mesh.py -- MeSH-pair age (novelty) for every cycle, on PubMed 2025.

Purpose: the novelty measure based on the age of MeSH descriptor pairs, one of
    the alternative novelty measures of Appendix F (Appendix Figures F1 and
    F2). The birth year of a MeSH descriptor, and of a pair of descriptors, is
    the earliest publication year of any PubMed paper that carries it (every
    descriptor counts, qualifiers ignored, one row per paper x descriptor). For
    each cycle, over the (paper, pair) instances of its acknowledging papers:
      agepair_cyclefrac   share of instances whose pair is at most 3 years old
                          when the paper appears (the measure that
                          Appendix F uses)
      agepair_cyclemean   mean age of the instances' pairs (raw years)
      agesingle_cyclemean mean age of the (paper, descriptor) instances
      n_pair_inst         number of (paper, pair) instances
    Both birth-year tables are computed over all of PubMed 2025, so that the
    descriptor codes are those of PubMed 2025 throughout.

Run: launched by code/build/13_novelty_mesh.do with ${python} (paths are
    arguments):
    python -I 13_novelty_mesh.py <data dir> <pubmed dir> <spill dir> <log file>
    <data dir> is the package's data root, ${data} (reads build/cycle_papers.dta);
    <pubmed dir> is ${pubmed_root}/pubmed; <spill dir> is a folder for DuckDB's
    spill files, off any synced tree; <log file> receives the progress log.

Input:
    <data dir>/build/cycle_papers.dta                  (code/build/03_cycle_papers.do)
    <pubmed dir>/overall_meshterms_2025.dta, overall_dates_2025.dta

Output:
    <data dir>/build/novelty_mesh.dta        one row per cycle with a measure
    <data dir>/build/meshpair_birthyear.parquet  every pair of PubMed 2025
    <data dir>/build/meshsingle_birthyear.parquet

Note: DuckDB runs with 24 threads and a 90 GB memory limit; the pair birth
    years come from a self-join, on pmid, of every paper x descriptor row of
    PubMed 2025.
"""
import os
import sys
import time

import duckdb
import pandas as pd

data_dir, pubmed_dir, spill, log_path = sys.argv[1:5]
build = os.path.join(data_dir, 'build')
t0 = time.time()
log = open(log_path, 'w', encoding='utf-8')


def say(msg):
    line = '[%7.1fs] %s' % (time.time() - t0, msg)
    log.write(line + '\n')
    log.flush()


def read_dta(path, cols, chunk=20_000_000):
    """Read selected columns of a large .dta in chunks, keeping codes."""
    parts = []
    with pd.read_stata(path, columns=cols, convert_categoricals=False,
                       chunksize=chunk) as rdr:
        for part in rdr:
            parts.append(part)
    return pd.concat(parts, ignore_index=True)


os.makedirs(spill, exist_ok=True)
con = duckdb.connect()
try:
    con.execute("SET threads=24")
    con.execute("SET memory_limit='90GB'")
    con.execute("SET preserve_insertion_order=false")
    con.execute("SET temp_directory='{}'".format(spill.replace('\\', '/')))

    say('reading overall_meshterms_2025 (pmid, dscrptr_ui)')
    mesh = read_dta(os.path.join(pubmed_dir, 'overall_meshterms_2025.dta'),
                    ['pmid', 'dscrptr_ui'])
    say('  %d rows' % len(mesh))
    con.register('mesh_df', mesh)
    con.execute("CREATE TABLE pd AS SELECT DISTINCT CAST(pmid AS INTEGER) AS pmid, "
                "CAST(dscrptr_ui AS INTEGER) AS d FROM mesh_df WHERE dscrptr_ui IS NOT NULL")
    con.unregister('mesh_df')
    del mesh
    say('  paper x descriptor rows: %d' % con.execute("SELECT COUNT(*) FROM pd").fetchone()[0])

    say('reading overall_dates_2025 (pmid, year)')
    dates = read_dta(os.path.join(pubmed_dir, 'overall_dates_2025.dta'), ['pmid', 'year'])
    con.register('dates_df', dates)
    con.execute("CREATE TABLE yr AS SELECT CAST(pmid AS INTEGER) AS pmid, "
                "MIN(CAST(year AS INTEGER)) AS year FROM dates_df "
                "WHERE year IS NOT NULL GROUP BY 1")
    con.unregister('dates_df')
    del dates

    con.execute("CREATE TABLE pdy AS SELECT pd.pmid, pd.d, yr.year FROM pd JOIN yr USING (pmid)")
    say('  paper x descriptor rows with a year: %d'
        % con.execute("SELECT COUNT(*) FROM pdy").fetchone()[0])

    say('single-descriptor birth years')
    con.execute("CREATE TABLE single_birth AS SELECT d, MIN(year) AS birth FROM pdy GROUP BY d")
    con.execute("COPY single_birth TO '{}' (FORMAT parquet)".format(
        os.path.join(build, 'meshsingle_birthyear.parquet').replace('\\', '/')))

    say('pair birth years over all of PubMed (self-join on pmid)')
    con.execute("""CREATE TABLE pair_birth AS
                   SELECT a.d AS d1, b.d AS d2, MIN(a.year) AS birth
                   FROM pdy a JOIN pdy b ON a.pmid = b.pmid AND a.d < b.d
                   GROUP BY 1, 2""")
    say('  distinct pairs: %d' % con.execute("SELECT COUNT(*) FROM pair_birth").fetchone()[0])
    con.execute("COPY pair_birth TO '{}' (FORMAT parquet)".format(
        os.path.join(build, 'meshpair_birthyear.parquet').replace('\\', '/')))

    say('reading cycle_papers (acknowledging papers)')
    cp = pd.read_stata(os.path.join(build, 'cycle_papers.dta'),
                       columns=['setnb', 'project_number', 'cycle', 'pmid', 'ackn'],
                       convert_categoricals=False)
    cp = cp[cp['ackn'] == 1].drop(columns='ackn')
    con.register('cp_df', cp)
    con.execute("CREATE TABLE cp AS SELECT DISTINCT setnb, project_number, "
                "CAST(cycle AS INTEGER) AS cycle, CAST(pmid AS INTEGER) AS pmid FROM cp_df")
    con.unregister('cp_df')
    say('  cycle x paper rows: %d' % con.execute("SELECT COUNT(*) FROM cp").fetchone()[0])

    con.execute("""CREATE TABLE tp AS
                   SELECT pdy.* FROM pdy WHERE pmid IN (SELECT DISTINCT pmid FROM cp)""")

    say('pair ages of the cycle papers')
    con.execute("""CREATE TABLE paper_pairs AS
                   SELECT a.pmid, a.year, a.year - pb.birth AS age
                   FROM tp a JOIN tp b ON a.pmid = b.pmid AND a.d < b.d
                   JOIN pair_birth pb ON pb.d1 = a.d AND pb.d2 = b.d""")
    con.execute("""CREATE TABLE paper_pair_stats AS
                   SELECT pmid, COUNT(*) AS n_inst, SUM(CASE WHEN age <= 3 THEN 1 ELSE 0 END) AS n_young,
                          SUM(age) AS sum_age
                   FROM paper_pairs GROUP BY pmid""")
    con.execute("""CREATE TABLE paper_single_stats AS
                   SELECT tp.pmid, COUNT(*) AS n_single, SUM(tp.year - sb.birth) AS sum_single_age
                   FROM tp JOIN single_birth sb USING (d) GROUP BY tp.pmid""")

    say('cycle measures')
    out = con.execute("""
        SELECT cp.setnb, cp.project_number, cp.cycle,
               SUM(p.n_young) * 1.0 / SUM(p.n_inst)        AS agepair_cyclefrac,
               SUM(p.sum_age) * 1.0 / SUM(p.n_inst)        AS agepair_cyclemean,
               SUM(s.sum_single_age) * 1.0 / SUM(s.n_single) AS agesingle_cyclemean,
               SUM(p.n_inst)                               AS n_pair_inst
        FROM cp
        JOIN paper_pair_stats p USING (pmid)
        LEFT JOIN paper_single_stats s USING (pmid)
        GROUP BY 1, 2, 3
        ORDER BY 1, 2, 3""").df()
    say('  cycles with a measure: %d' % len(out))
    say(out[['agepair_cyclefrac', 'agepair_cyclemean', 'agesingle_cyclemean']]
        .describe().to_string())
    out['cycle'] = out['cycle'].astype('int16')
    out['n_pair_inst'] = out['n_pair_inst'].astype('int64')
    out.to_stata(os.path.join(build, 'novelty_mesh.dta'), write_index=False,
                 data_label='MeSH-pair age (novelty) by cycle, PubMed 2025',
                 variable_labels={
                     'agepair_cyclefrac': 'Share of paper x pair instances at most 3 years old',
                     'agepair_cyclemean': 'Mean age of paper x pair instances (years)',
                     'agesingle_cyclemean': 'Mean age of paper x descriptor instances (years)',
                     'n_pair_inst': 'Paper x pair instances in the cycle'})
    say('saved build/novelty_mesh.dta')
finally:
    con.close()
    say('done')
    log.close()
