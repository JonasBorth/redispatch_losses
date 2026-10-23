"""Vertical wind profiles for different surface roughness lengths (Hellmann power law)."""

import matplotlib.pyplot as plt
import numpy as np

V_REF = 6.0   # reference wind speed [m/s]
H_REF = 10.0  # reference measurement height [m]

surfaces = {
    "Water": (0.0002, "#1f77b4"),
    "Farmland": (0.1, "#2ca02c"),
    "Forest": (1.0, "#8c564b"),
    "City": (1.5, "#7f7f7f"),
}

heights = np.linspace(H_REF, 200, 400)

fig, ax = plt.subplots(figsize=(6.3, 3.4), dpi=300)

for label, (z0, color) in surfaces.items():
    alpha = 1.0 / np.log(np.sqrt(heights * H_REF) / z0)
    v = V_REF * (heights / H_REF) ** alpha
    ax.plot(heights, v, color=color, linewidth=1.4, label=f"{label} ($z_0$ = {z0} m)")

ax.set_xlabel("Height above ground (m)", fontsize=8)
ax.set_ylabel("Wind speed (m/s)", fontsize=8)
ax.tick_params(axis="both", labelsize=7)
ax.legend(fontsize=7, frameon=False, loc="upper left")
ax.grid(True, linewidth=0.4, alpha=0.4)
ax.margins(x=0)
plt.tight_layout()

fig.savefig("wind_profile_roughness.png", dpi=300, bbox_inches="tight")
plt.show()
