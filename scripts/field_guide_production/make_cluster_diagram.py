# ==============================================================================
# Static 3-panel comparison diagram (Non-IDP / IDP in-camp / IDP in-host) for
# the general field guide page prepended to every cluster factsheet. Ported
# from the reference make_diagram_v2.py (Claude web attachment, 2026-08-07) -
# same figure, only the output path changed. Generated once, embedded by
# reference (not regenerated) in every cluster's factsheet.
# ==============================================================================
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import RegularPolygon, Polygon
import numpy as np
import os

NAVY = "#1F3864"
CAMP = "#B45309"
HOSTCOMM = "#6B2FA3"
GREY = "#7F7F7F"
LIGHTGREY = "#D9D9D9"

OUT_PATH = r"c:\Users\JackPHILPOTT\ACTED\IMPACT NGA - 02. MSNA\4. Data\MSNA N-WEC 2026\1_sampling\output\maps\cluster_diagram_v2.png"
os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)

fig, axes = plt.subplots(1, 3, figsize=(13.8, 4.7))

# ---------------- PANEL 1: NON-IDP ----------------
ax = axes[0]
ax.set_xlim(-1.3, 1.3); ax.set_ylim(-1.3, 1.4); ax.set_aspect("equal"); ax.axis("off")

hexagon = RegularPolygon((0, 0), numVertices=6, radius=1.15, orientation=np.pi/6,
                          facecolor="none", edgecolor=GREY, linewidth=2, linestyle=(0, (5, 3)))
ax.add_patch(hexagon)

rng = np.random.default_rng(7)
bg_pts = []
while len(bg_pts) < 22:
    x, y = rng.uniform(-1.0, 1.0, 2)
    if abs(x) < 1.0 and abs(y) < 0.95:
        bg_pts.append((x, y))
bg_pts = np.array(bg_pts)
ax.scatter(bg_pts[:, 0], bg_pts[:, 1], s=14, color=LIGHTGREY, zorder=2)

primary = np.array([(-0.55, 0.5), (0.15, 0.7), (0.65, 0.25), (-0.3, -0.15), (0.4, -0.55), (-0.75, -0.5)])
for i, (x, y) in enumerate(primary, 1):
    ax.scatter(x, y, s=90, color=NAVY, zorder=4, edgecolor="white", linewidth=1)
    ax.annotate(f"H{i}", (x, y), textcoords="offset points", xytext=(0, 9), ha="center", fontsize=7.5, color=NAVY, fontweight="bold")

reserve = np.array([(0.85, -0.1), (-0.95, 0.15)])
for i, (x, y) in enumerate(reserve, 1):
    ax.scatter(x, y, s=70, facecolor="white", edgecolor=NAVY, linewidth=1.6, zorder=4)
    ax.annotate(f"R{i}", (x, y), textcoords="offset points", xytext=(0, 8), ha="center", fontsize=7, color=NAVY, fontweight="bold")

ax.set_title("NON-IDP cluster\n(hexagon PSU)", fontsize=12, fontweight="bold", color=NAVY, pad=10)
ax.text(0, -1.32, "Buildings already listed & selected\nNavigate to pins H1-H6 in your app,\nuse reserves only if unreachable",
        ha="center", va="top", fontsize=8.2, color="#333333")

# ---------------- PANEL 2: IDP - IN-CAMP ----------------
ax = axes[1]
ax.set_xlim(-1.3, 1.3); ax.set_ylim(-1.3, 1.4); ax.set_aspect("equal"); ax.axis("off")

rng2 = np.random.default_rng(11)
angles = np.linspace(0, 2*np.pi, 14, endpoint=False)
radii = 0.75 + rng2.uniform(-0.22, 0.28, len(angles))
blob_pts = np.column_stack([radii*np.cos(angles), radii*np.sin(angles)])
blob = Polygon(blob_pts, closed=True, facecolor="#FBF0E4", edgecolor=CAMP, linewidth=2, linestyle=(0, (5, 3)), zorder=1)
ax.add_patch(blob)

ax.scatter([0], [0], marker="*", s=220, color="#C00000", zorder=5, edgecolor="white", linewidth=0.8)
ax.annotate("Head of area\n(camp lead/warden)", (0, 0), textcoords="offset points", xytext=(0, -20), ha="center", fontsize=7.2, color="#C00000", fontweight="bold")

hh_pts = []
while len(hh_pts) < 15:
    x, y = rng2.uniform(-0.9, 0.9, 2)
    if x**2 + y**2 < 0.75**2 and x**2 + y**2 > 0.02:
        hh_pts.append((x, y))
hh_pts = np.array(hh_pts)
ax.scatter(hh_pts[:, 0], hh_pts[:, 1], s=40, marker="s", color=CAMP, zorder=3, alpha=0.85)
for x, y in hh_pts[:6]:
    ax.plot([0, x], [0, y], color=CAMP, linewidth=0.6, linestyle=(0, (2, 2)), alpha=0.6, zorder=1)

ax.scatter([0.55], [-0.5], marker="P", s=90, color="#333333", zorder=5, edgecolor="white", linewidth=0.8)
ax.annotate("Backup pt\n(Tier 2 start only)", (0.55, -0.5), textcoords="offset points", xytext=(10, -4), ha="left", fontsize=6.6, color="#333333", fontweight="bold")

ax.set_title("IDP cluster - IN-CAMP\n(head of area, listing)", fontsize=12, fontweight="bold", color=NAVY, pad=10)
ax.text(0, -1.32, "Ask head of area for a full list of\nHHs at this site. Not possible?\nFallback: random-walk from backup pt",
        ha="center", va="top", fontsize=8.2, color="#333333")

# ---------------- PANEL 3: IDP - HOST-COMMUNITY ----------------
ax = axes[2]
ax.set_xlim(-1.3, 1.3); ax.set_ylim(-1.3, 1.4); ax.set_aspect("equal"); ax.axis("off")

rng3 = np.random.default_rng(19)
all_pts = rng3.uniform(-1.05, 1.05, (26, 2))
idx_idp = rng3.choice(len(all_pts), size=9, replace=False)
for i, (x, y) in enumerate(all_pts):
    if i in idx_idp:
        ax.scatter(x, y, s=42, marker="s", color=HOSTCOMM, zorder=4)
    else:
        ax.scatter(x, y, s=16, marker="s", color=LIGHTGREY, zorder=2)

ax.scatter([0], [0.05], marker="*", s=260, color="#C00000", zorder=5, edgecolor="white", linewidth=0.8)
ax.annotate("Head of area\n(chief/head of settlement)", (0, 0.05), textcoords="offset points", xytext=(0, -20), ha="center", fontsize=7.2, color="#C00000", fontweight="bold")

for i in list(idx_idp)[:6]:
    x, y = all_pts[i]
    ax.plot([0, x], [0.05, y], color=HOSTCOMM, linewidth=0.6, linestyle=(0, (2, 2)), alpha=0.6, zorder=1)

ax.set_title("IDP cluster - HOST-COMMUNITY\n(head of area, listing)", fontsize=12, fontweight="bold", color=NAVY, pad=10)
ax.text(0, -1.32, "No fixed radius. Head of area\nidentifies which households (purple)\nare displaced - list & pool, then select",
        ha="center", va="top", fontsize=8.2, color="#333333")

plt.tight_layout()
plt.savefig(OUT_PATH, dpi=220, bbox_inches="tight", facecolor="white")
print("saved:", OUT_PATH)
