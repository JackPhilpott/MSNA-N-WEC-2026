# ==============================================================================
# 2026-09-21 late evening: NRC sent a full updated accessibility report
# (partner_raw_comms/NRC/NRC_accessibility_report2109.xlsx - "2109" is 21 Sep,
# day-first). Checked before merging: 0 ward answers differ from NRC's master
# file; 14 Non-IDP clusters (NG008011/NG008013/NG008016) newly answered "N"
# where the master was blank. Street Child's two ward flips (Madagali: Gulak
# -> N, Madagali -> Y) were already placed in the returned folder by Jack -
# nothing to merge there.
#
# merge_partner() is imported, not copied, from the 2026-09-20 merge script
# so the rule is identical: MERGE, never overwrite - a non-blank raw value
# wins, a blank raw cell never clears an existing answer. Backs up the master
# file to accessibility_reports_returned/_archive/ first.
# Usage: python merge_accessibility_report_updates_2026-09-21.py
# ==============================================================================
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("m0920", os.path.join(HERE, "merge_accessibility_report_updates_2026-09-20.py"))
m0920 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m0920)
m0920.TODAY = "2026-09-21"   # backup file name only

if __name__ == "__main__":
    m0920.merge_partner("NRC", "NRC_accessibility_report2109.xlsx", reason="2109_merge")
