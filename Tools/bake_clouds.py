#!/usr/bin/env python3
# Author: MUI group 3
"""
Bakes the Blender cloud models into sprite data + textures for RealityKit.

RealityKit cannot render OpenVDB volumes, so the volumetric look is rebuilt from
soft, camera-facing sprites. This script
  1. reads the metaball meshes (the source shapes of the VDB volumes) from the USD exports,
  2. fills them with sprites, bakes self-shadowing / light scattering per sprite,
  3. pairs every start sprite with an end sprite (optimal assignment) so the app can
     morph the start cloud organically into the anvil,
  4. writes cloud_morph.json and the puff / wind / sun textures into ../MUI_Lightning_Group_3/Resources.

Re-run whenever the Blender models change:
    pip install usd-core trimesh scipy rtree pillow numpy
    python3 Tools/bake_clouds.py path/to/clouds_mui
"""
import json, math, os, sys
import numpy as np
import trimesh
from pxr import Usd, UsdGeom
from scipy.optimize import linear_sum_assignment
from PIL import Image
from PIL.PngImagePlugin import PngInfo

AUTHOR = "MUI group 3"

SRC = sys.argv[1] if len(sys.argv) > 1 else "clouds_mui"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "MUI_Lightning_Group_3", "Resources")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(4)

# ---- Look parameters (Blender-ish "Principled Volume" equivalents) -------------
SPRITES = 1100                 # sprites per cloud state
MINI_SPRITES = 150             # charged mini clouds
METERS_PER_UNIT = 0.021        # Blender unit -> metres in the scene
LIGHT_DIR = np.array([-0.45, -0.55, 1.0])   # towards the sun, Blender Z-up
DENSITY = {"start": 0.3, "end": 0.15}       # extinction per Blender unit
END_GREY = 1.0                 # keep 1.0: the app greys the cloud as the storm builds

def load_mesh(stage, path):
    m = UsdGeom.Mesh(stage.GetPrimAtPath(path))
    pts = np.array(m.GetPointsAttr().Get())
    counts = m.GetFaceVertexCountsAttr().Get()
    idx = m.GetFaceVertexIndicesAttr().Get()
    xf = np.array(UsdGeom.Xformable(m.GetPrim()).ComputeLocalToWorldTransform(0))
    pts = (np.c_[pts, np.ones(len(pts))] @ xf)[:, :3]
    faces, i = [], 0
    for c in counts:
        f = idx[i:i + c]
        faces += [[f[0], f[k], f[k + 1]] for k in range(1, c - 1)]
        i += c
    mesh = trimesh.Trimesh(pts, faces)
    bodies = mesh.split(only_watertight=False)
    return max(bodies, key=lambda b: abs(b.volume))   # drop tiny metaball fragments

stage = Usd.Stage.Open(os.path.join(SRC, "cloud_end", "cloud_end.usdc"))
meshes = {
    "start": load_mesh(stage, "/root/Mball_022/Mesh"),
    "end": load_mesh(stage, "/root/Mball_316/Mesh_001"),
}

class Occupancy:
    """Fast inside test on a filled voxel grid (much lighter than ray-based contains)."""
    def __init__(self, mesh, cells=96):
        self.pitch = float(mesh.extents.max()) / cells
        vox = mesh.voxelized(self.pitch).fill()
        self.grid = vox.matrix
        self.inv = np.linalg.inv(vox.transform)

    def contains(self, pts):
        ijk = np.round((np.c_[pts, np.ones(len(pts))] @ self.inv.T)[:, :3]).astype(int)
        ok = np.all((ijk >= 0) & (ijk < np.array(self.grid.shape)), axis=1)
        out = np.zeros(len(pts), bool)
        out[ok] = self.grid[ijk[ok, 0], ijk[ok, 1], ijk[ok, 2]]
        return out

def inside_length(occ, origins, direction, max_len, step):
    """Path length inside the cloud along `direction` (optical depth helper)."""
    n = int(max_len / step)
    ts = (np.arange(n) + 0.5) * step
    pts = origins[:, None, :] + ts[None, :, None] * direction[None, None, :]
    inside = occ.contains(pts.reshape(-1, 3)).reshape(len(origins), n)
    return inside.sum(axis=1) * step

def make_sprites(mesh, count, density, grey):
    occ = Occupancy(mesh)
    ext = mesh.extents
    size = float(np.cbrt(np.prod(ext)))
    radius = size * 0.105
    # Mostly a shell just under the surface (that's what you see), some interior fill.
    n_shell = int(count * 0.82)
    surf, face_idx = trimesh.sample.sample_surface_even(mesh, n_shell * 2, seed=3)
    surf = surf[:n_shell]
    normals = mesh.face_normals[face_idx[:n_shell]]
    depth = rng.uniform(0.25, 0.9, n_shell)[:, None] * radius
    shell = surf - normals * depth
    lo, hi = mesh.bounds
    fill = []
    while len(fill) < count - n_shell:
        c = rng.uniform(lo, hi, (4000, 3))
        fill += list(c[occ.contains(c)])
    fill = np.array(fill[: count - n_shell])
    pos = np.vstack([shell, fill])
    nrm = np.vstack([normals, np.zeros_like(fill)])

    L = LIGHT_DIR / np.linalg.norm(LIGHT_DIR)
    step = radius * 0.35
    sun_len = inside_length(occ, pos, L, size * 2.5, step)
    up_len = inside_length(occ, pos, np.array([0, 0, 1.0]), size * 2.5, step)
    direct = np.exp(-density * sun_len)
    multi = np.exp(-density * 0.22 * sun_len)       # cheap multiple-scattering term
    ambient = np.exp(-density * 0.35 * up_len)       # sky light from above
    wrap = np.clip(nrm @ L * 0.5 + 0.5, 0, 1)
    wrap[len(shell):] = 0.5
    shade = 0.2 + 0.6 * (0.5 * direct + 0.5 * multi) * (0.5 + 0.5 * wrap) + 0.3 * ambient
    shade = np.clip(shade * grey, 0.05, 1.0)
    radii = 1.12 * radius * rng.uniform(0.85, 1.25, count)   # 1.12 compensates the tile margin * np.where(np.arange(count) < n_shell, 1.0, 1.25)
    return pos, radii, shade

data = {k: make_sprites(m, SPRITES, DENSITY[k], 1.0 if k == "start" else END_GREY) for k, m in meshes.items()}

# ---- Pair start <-> end sprites in normalised space (cloud grows, doesn't teleport)
def normalised(p, m):
    lo, hi = m.bounds
    return (p - lo) / (hi - lo)
ns, ne = normalised(data["start"][0], meshes["start"]), normalised(data["end"][0], meshes["end"])
cost = ((ns[:, None, :] - ne[None, :, :]) ** 2 * np.array([1.0, 1.0, 1.6])).sum(-1)
_, match = linear_sum_assignment(cost)

# ---- Blender Z-up units -> RealityKit Y-up metres, cloud base at y = 0
s_lo, s_hi = meshes["start"].bounds
cx, cy, z0 = (s_lo[0] + s_hi[0]) / 2, (s_lo[1] + s_hi[1]) / 2, s_lo[2]
def to_rk(p):
    return np.stack([(p[:, 0] - cx), (p[:, 2] - z0), -(p[:, 1] - cy)], -1) * METERS_PER_UNIT

sp, sr, ss = data["start"]
ep, er, es = data["end"][0][match], data["end"][1][match], data["end"][2][match]
sp_m, ep_m = to_rk(sp), to_rk(ep)
end_h = (ep_m[:, 1] - ep_m[:, 1].min()) / np.ptp(ep_m[:, 1])
delay = np.clip(0.45 * end_h ** 1.2 + rng.uniform(-0.06, 0.06, SPRITES), 0, 0.5)   # tower first, anvil last
seeds = rng.random(SPRITES)
rows = np.column_stack([sp_m, sr * METERS_PER_UNIT, ss, ep_m, er * METERS_PER_UNIT, es, delay, seeds])

def bounds(p, r):
    return [(p - r[:, None]).min(0).round(4).tolist(), (p + r[:, None]).max(0).round(4).tolist()]

# ---- Mini cloud (charged clouds): farthest-point subsample of the start cloud
chosen = [int(np.argmax(sp_m[:, 1]))]
d = np.linalg.norm(sp_m - sp_m[chosen[0]], axis=1)
for _ in range(MINI_SPRITES - 1):
    i = int(np.argmax(d)); chosen.append(i)
    d = np.minimum(d, np.linalg.norm(sp_m - sp_m[i], axis=1))
mp = sp_m[chosen]; mc = (mp.max(0) + mp.min(0)) / 2; extent = np.ptp(mp, axis=0).max()
mini = np.column_stack([(mp - mc) / extent, sr[chosen] * METERS_PER_UNIT / extent * 1.7, ss[chosen]])

out = {
    "author": AUTHOR,
    "sprites": np.round(rows, 5).tolist(),
    "startBounds": bounds(sp_m, sr * METERS_PER_UNIT),
    "endBounds": bounds(ep_m, er * METERS_PER_UNIT),
    "mini": np.round(mini, 5).tolist(),
}
with open(os.path.join(OUT, "cloud_morph.json"), "w") as f:
    json.dump(out, f, separators=(",", ":"))
print("bounds start", out["startBounds"], "end", out["endBounds"])

# ---- Textures ------------------------------------------------------------------
def fbm(n, octaves, seed):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n)); amp = 1.0; tot = 0
    for o in range(octaves):
        g = 2 ** (o + 2)
        grid = r.random((g + 1, g + 1))
        img = np.array(Image.fromarray((grid * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
        acc += img * amp; tot += amp; amp *= 0.5
    return acc / tot

TILE, SHADES, VARIANTS = 64, 16, 4
yy, xx = np.mgrid[0:TILE, 0:TILE]
# Puff fills 86% of its tile: the empty margin keeps mipmaps of neighbouring tiles from
# bleeding in (which shows as square blocks when a puff is small on screen).
rad = np.hypot(xx - TILE / 2 + 0.5, yy - TILE / 2 + 0.5) / (TILE / 2 * 0.86)
atlas_rgb = np.zeros((TILE * VARIANTS, TILE * SHADES, 3))
atlas_a = np.zeros((TILE * VARIANTS, TILE * SHADES))
for v in range(VARIANTS):
    noise = fbm(TILE, 4, 10 + v)
    falloff = np.clip(1 - rad, 0, 1) ** 1.6
    alpha = np.clip(falloff * (0.55 + 0.9 * noise) - 0.05, 0, 1) * 0.92
    alpha[rad > 0.97] = 0
    for s in range(SHADES):
        shade = s / (SHADES - 1)
        # subtle internal variation so overlapping puffs read as billows
        tone = np.clip(shade * (0.9 + 0.2 * noise), 0, 1)
        atlas_rgb[v*TILE:(v+1)*TILE, s*TILE:(s+1)*TILE] = tone[..., None]
        atlas_a[v*TILE:(v+1)*TILE, s*TILE:(s+1)*TILE] = alpha

def save_pair(name, rgb, a):
    meta = PngInfo()
    meta.add_text("Author", AUTHOR)
    rgba = np.dstack([rgb, a])
    Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"), pnginfo=meta)
    g = (a * 255).round().astype(np.uint8)
    Image.fromarray(np.dstack([g, g, g, np.full_like(g, 255)]), "RGBA").save(os.path.join(OUT, name + "_alpha.png"), pnginfo=meta)

save_pair("cloud_puff_atlas", atlas_rgb, atlas_a)

# Wind streak: long soft wisp, fades towards the tail (u=0) and the head (u=1)
W, H = 256, 32
u = np.linspace(0, 1, W)[None, :]; v = np.linspace(-1, 1, H)[:, None]
noise = np.array(Image.fromarray((fbm(64, 3, 77) * 255).astype(np.uint8)).resize((W, H))) / 255.0
along = np.clip(u, 0, 1) ** 1.4 * np.clip((1 - u) * 6, 0, 1)
across = np.exp(-(v ** 2) * 5.5)
wind_a = np.clip(along * across * (0.6 + 0.6 * noise), 0, 1)
save_pair("wind_streak", np.ones((H, W, 3)), wind_a)

# Sun: bright core, soft glare and faint corona
S = 256
yy, xx = np.mgrid[0:S, 0:S]
r = np.hypot(xx - S / 2 + 0.5, yy - S / 2 + 0.5) / (S / 2)
core = np.clip(1 - r / 0.16, 0, 1) ** 0.5
glare = np.exp(-(r / 0.32) ** 2) * 0.8
corona = np.exp(-(r / 0.75) ** 2) * 0.28
sun_a = np.clip(core + glare + corona, 0, 1) * (r < 1)
warm = np.dstack([np.ones_like(r), 0.93 + 0.07 * core, 0.78 + 0.22 * core])
save_pair("sun_glow", warm, sun_a)
print("written to", os.path.abspath(OUT))
