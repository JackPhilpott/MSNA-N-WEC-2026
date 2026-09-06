# ==============================================================================
# One-time, git-committed migration of resampling_requests_log.csv: adds the
# new "reported_by" column (Partner / IMPACT-default) alongside the existing
# "source_channel" field, matching the schema 02_ingest_accessibility_reports.py
# now writes for every future row (see that script's ingest() function).
#
# Also standardises every existing row's "source_channel" value from the old
# hardcoded "partner_excel_return" string to "Partner's own template" - the
# new fixed vocabulary's equivalent term (see 01_generate_accessibility_
# reports.py's SOURCE_CHANNEL_OPTIONS). Safe to do for all 2,052 rows
# unconditionally, independent of the reported_by classification below: the
# CHANNEL a row arrived through (the standard returned Excel template) is a
# fact about the file format, true for every row regardless of whether the
# specific cell VALUE inside that file was the partner's own answer or a
# coordinator pre-fill - that second, harder question is exactly what
# reported_by's "" (needs review) below is for.
#
# Why this can't just be "add the column and default everything to Partner":
# "reported_by" answers who actually typed a given cell's value, which the
# ingest process itself can never know - it only knows a file came back from a
# partner, not whether every value in it was genuinely the partner's own
# answer or a coordinator's pre-filled assumption (Save the Children's case
# below is the clearest confirmed example). That distinction only exists in
# this session's own review history, verified against real data, not in
# anything 02_ingest.py could derive on rerun. So this migration only marks a
# row "Partner" where that's been directly confirmed; everything else is left
# blank ("" = not yet classified) rather than guessed, so a blank value in
# this column is a known-unknown, not a silent wrong answer.
#
# Rerun safety: idempotent - if resampling_requests_log.csv already has a
# reported_by column, running this again just recomputes the same values
# (does not touch anything a subsequent manual review may have written in,
# UNLESS that column is dropped and this is rerun - so don't rerun after any
# manual edit to reported_by without first checking this script's own
# CONFIRMED_PARTNER_ROWS / NEEDS_REVIEW logic still matches what you intended).
# ==============================================================================
import csv

PROJECT_DIR = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling"
LOG_CSV = PROJECT_DIR + r"\resampling\output\resampling_requests_log.csv"

# Partners who never passed through the coordinator-prep drafts/ stage before
# being ingested - every value in their returned file is mechanically the
# partner's own entry (see 2026-08-27 provenance-proposal review). FACT is
# handled separately below (see FACT_NEEDS_REVIEW) since 11 of its rows were
# coordinator-corrected from the partner's own evidence text, not left as the
# partner's literal original entry.
SAFE_PARTNERS = {"COOPI", "FACT", "INTERSOS", "IRC", "ZOA"}

# FACT's 5 Yes+insecurity-notes contradiction flips and 6 blank-Accessible-but-
# reasoned rows set to No (patch_fact_report_2026-08-26.py) - coordinator-
# corrected FROM the partner's own evidence, a genuinely different case from
# "coordinator assumed an answer with no partner evidence at all". Recommended
# as "Partner" provenance in the 2026-08-27 review but explicitly flagged as
# not yet user-confirmed - left for manual review here rather than assumed.
FACT_NEEDS_REVIEW = {
    ("Kebbi", "Augie", "Tiggi"), ("Sokoto", "Gada", "Gilbadi"), ("Sokoto", "Gudu", "Bachaka"),
    ("Sokoto", "Silame", "Jekanadu"), ("Sokoto", "Silame", "Kwaido"),
    ("Sokoto", "Gudu", "Chilas"), ("Sokoto", "Gudu", "Marake"), ("Sokoto", "Gudu", "Tullun Doya"),
    ("Kebbi", "Kebbe", "Bardoki"), ("Sokoto", "Silame", "Bakale"), ("Sokoto", "Tureta", "Kwarare"),
}

# Save the Children: the 6 "No"/Insecurity rows were confirmed directly
# against the partner's returned file (2026-08-27 provenance review) as the
# partner's own genuine answers. The other 42 rows in the log are all
# "Yes" with no reason given - consistent with a coordinator-assumed default
# rather than a partner-typed answer, but not directly confirmed either way,
# so left for review rather than asserted as IMPACT-default outright.
STC_CONFIRMED_PARTNER = {
    ("Benue", "Kwande", "Kumakwagh"), ("Benue", "Kwande", "Moon"),
    ("Zamfara", "Bungudu", "Gada Karakai"), ("Zamfara", "Bungudu", "Samawa"),
    ("Zamfara", "Bungudu", "Bingi South"), ("Zamfara", "Bungudu", "Tofa"),
}

# FHI 360 (resolved 2026-08-27): cross-checked their raw
# `partner_raw_comms/FHI 360/FHI 360_sampling_points_summary_FHI360.xlsx`
# (the point-level file their 2026-08-17 email describes as "Green (Column
# F): Accessible... Red (Column F): Inaccessible" - a genuine cell-fill
# colour on the "Ward (OCHA/COD)" column, not a text value, which is why it
# wasn't visible on a plain value read) against all 22 of their returned
# Ward Accessibility rows: 21 match the point-file colour exactly
# (source_channel = "Point-level file annotation"). The 22nd, Gazabure, has
# no coloured points at all (zero primary target HHs there - reserve-only)
# but is traceable to the partner's own blanket email statement ("For
# Mobbar LGA, all currently assigned households are inaccessible") - already
# documented in that row's own Reason notes - so it's still Partner
# provenance, just via "Email" rather than the point file.
FHI360_POINT_FILE_WARDS = {
    ("Borno", "Mafa", "Mafa"), ("Borno", "Mafa", "Masu"), ("Borno", "Mafa", "Miye"),
    ("Borno", "Mafa", "Mujigine"), ("Borno", "Mafa", "Ajiri"), ("Borno", "Mafa", "Limanti"),
    ("Borno", "Mafa", "Koshebe"), ("Borno", "Mafa", "Gawa"), ("Borno", "Mafa", "Khaddamari"),
    ("Borno", "Mafa", "Dalori"), ("Borno", "Mafa", "Tamsum Gamdua"), ("Borno", "Mafa", "Laje"),
    ("Borno", "Mobbar", "Ngetra"), ("Borno", "Mobbar", "Layi"), ("Borno", "Mobbar", "Futchimiram"),
    ("Borno", "Mobbar", "Kareto"), ("Borno", "Mobbar", "Chamba"), ("Borno", "Mobbar", "Zari"),
    ("Borno", "Mobbar", "Fukurti"), ("Borno", "Mobbar", "Gashigar"), ("Borno", "Mobbar", "Banowa"),
}
FHI360_EMAIL_WARDS = {("Borno", "Mobbar", "Gazabure")}

# Not yet individually verified against their own returned files (see
# 2026-08-27 review's pending-tasks list) - left blank rather than guessed.
UNVERIFIED_PARTNERS = {"IMC"}


def classify(row):
    """Returns (reported_by, source_channel). Empty string in either means
    "not yet classified" (needs review), never a guess."""
    partner = row["partner"]
    key = (row["state"], row["lga"], row["ward_name"])

    if partner == "FACT":
        return ("", "") if key in FACT_NEEDS_REVIEW else ("Partner", "Partner's own template")
    if partner == "Save the Children":
        return ("Partner", "Partner's own template") if key in STC_CONFIRMED_PARTNER else ("", "")
    if partner == "FHI 360":
        if key in FHI360_POINT_FILE_WARDS:
            return ("Partner", "Point-level file annotation")
        if key in FHI360_EMAIL_WARDS:
            return ("Partner", "Email")
        return ("", "")  # any ward not in either known set - don't guess
    if partner in UNVERIFIED_PARTNERS:
        return ("", "")
    # Matched by prefix, not exact string: the "Solidarites" partner name in
    # the source WORKING frame/log is stored missing its trailing "s" - not
    # mojibake as first assumed while writing this script, just a genuine
    # (separate, pre-existing, unfixed here) truncation upstream - matching
    # the literal accented character in this file's own source risked a
    # further encoding round-trip issue, so prefix match sidesteps it.
    if partner in SAFE_PARTNERS or partner.startswith("Solidarit"):
        return ("Partner", "Partner's own template")
    raise ValueError(f"Unrecognised partner '{partner}' - classify explicitly before rerunning.")


def migrate():
    with open(LOG_CSV, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)

    if "reported_by" not in fieldnames:
        # Insert right after source_channel, matching 02_ingest's LOG_FIELDS order.
        idx = fieldnames.index("source_channel") + 1
        fieldnames = fieldnames[:idx] + ["reported_by"] + fieldnames[idx:]

    counts = {"Partner": 0, "": 0}
    for row in rows:
        reported_by, source_channel = classify(row)
        row["reported_by"] = reported_by
        counts[reported_by] += 1
        if source_channel:
            row["source_channel"] = source_channel
        elif row["source_channel"] == "partner_excel_return":
            # Old hardcoded value, channel unclassified either way - still
            # standardise the string even though reported_by stays blank.
            row["source_channel"] = "Partner's own template"

    with open(LOG_CSV, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Migrated {len(rows)} rows.")
    print(f"  reported_by = 'Partner': {counts['Partner']}")
    print(f"  reported_by = '' (needs review): {counts['']}")


if __name__ == "__main__":
    migrate()
