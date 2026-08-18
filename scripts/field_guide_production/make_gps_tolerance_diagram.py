# GPS point offset diagram (Non-IDP only) - v2, 2026-08-12: simplified to
# the visual only (no baked-in title/caption text) and enlarged ~50%, so it
# can sit in a two-column docx layout - diagram on the left, description
# text on the right, per the user's explicit feedback that the original
# single-image-with-caption-below layout should become side-by-side.
# Matches make_cluster_diagram.py's palette/style.
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle
import os

NAVY = "#1F3864"
GREY = "#7F7F7F"
LIGHTGREY = "#D9D9D9"
CAUTION = "#C00000"
ALLOWED = "#2E7D32"
FLAGGED = "#B8860B"
ALLOWED_FILL = "#EAF4EC"
FLAGGED_FILL = "#FBF1DC"

OUT_PATH = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\output\maps\gps_tolerance_diagram.png"
os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)

fig, ax = plt.subplots(figsize=(9.6, 8.4))
ax.set_xlim(-1.55, 1.55); ax.set_ylim(-1.55, 1.55); ax.set_aspect("equal"); ax.axis("off")

R50, R150 = 0.42, 1.0

outer = Circle((0, 0), 1.42, facecolor="white", edgecolor="none", zorder=0)
ax.add_patch(outer)

# 50-150m ring (flagged) - drawn as a filled disc at R150, then the R50 disc
# painted over it, so the visible ring is the R50-R150 annulus.
ring = Circle((0, 0), R150, facecolor=FLAGGED_FILL, edgecolor=FLAGGED, linewidth=2.2, zorder=1)
ax.add_patch(ring)
core = Circle((0, 0), R50, facecolor=ALLOWED_FILL, edgecolor=ALLOWED, linewidth=2.2, zorder=2)
ax.add_patch(core)

# GPS pin at the centre
ax.scatter([0], [0], marker="P", s=320, color=CAUTION, zorder=6, edgecolor="white", linewidth=1.3)
ax.annotate("GPS pin\n(pre-loaded point)", (0, 0), textcoords="offset points", xytext=(0, -40),
            ha="center", fontsize=9.5, color=CAUTION, fontweight="bold")

# example building inside the allowed core
bx1, by1 = -0.16, 0.28
ax.scatter([bx1], [by1], s=140, marker="s", color=NAVY, zorder=5, edgecolor="white", linewidth=1.2)
ax.plot([0, bx1], [0, by1], color=ALLOWED, linewidth=1.6, zorder=3)

# example building inside the flagged ring
bx2, by2 = 0.72, 0.55
ax.scatter([bx2], [by2], s=140, marker="s", color=NAVY, zorder=5, edgecolor="white", linewidth=1.2)
ax.plot([0, bx2], [0, by2], color=FLAGGED, linewidth=1.6, linestyle=(0, (4, 2)), zorder=3)

# a building well outside 150m - greyed out, not usable - connected back to
# the pin with a red dashed line (clipped at the frame edge) so it reads as
# "way out there," not an unrelated stray mark.
bx3, by3 = -1.32, -1.18
edge_x, edge_y = -1.05, -0.94
ax.plot([edge_x, bx3 * 0.92], [edge_y, by3 * 0.92], color=CAUTION, linewidth=1.4, linestyle=(0, (3, 2)), zorder=3)
ax.scatter([bx3], [by3], s=140, marker="s", color=LIGHTGREY, zorder=4)
ax.annotate("x", (bx3, by3), ha="center", va="center", fontsize=14, color=CAUTION, fontweight="bold")

# tier labels
ax.annotate("0-50m", (0, R50), textcoords="offset points", xytext=(0, 9),
            ha="center", fontsize=12, color=ALLOWED, fontweight="bold")
ax.annotate("50-150m", (0, R150), textcoords="offset points", xytext=(0, 9),
            ha="center", fontsize=12, color=FLAGGED, fontweight="bold")
ax.annotate(">150m", (bx3, by3), textcoords="offset points", xytext=(-4, -22),
            ha="center", fontsize=12, color=CAUTION, fontweight="bold")

plt.tight_layout()
plt.savefig(OUT_PATH, dpi=220, bbox_inches="tight", facecolor="white")
print("saved:", OUT_PATH)
