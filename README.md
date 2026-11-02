# MUI_Lightning_Group_3 – Lightning (visionOS)

Authors: MUI group 3

Apple Vision Pro experience about how lightning forms, built around a physical landscape model.

## Run

Open `MUI_Lightning_Group_3.xcodeproj` in Xcode 16+, choose an Apple Vision Pro simulator or
device, run. In the start window keep **Show virtual landscape** on in the simulator.

## Flow and controls

0. **Start window** – choose *With the physical model* (the virtual terrain is invisible but
   still hides rain and lightning behind the real mountains) or *Virtual landscape*.
1. **Opening** – the visitor drags the sun from sunrise to midday (speed-limited, ~9 s).
   Warm air rises from the ground while it moves.
2. **Intro** – the storm forms. Info labels appear one after another; the newest is in focus,
   earlier ones dim. Wind lines and moist lowland air are shown only here.
3. **Play** – drag the + / − clouds into the storm (or tap them). Each absorbed cloud gives a
   chime and a flash/swell of the storm. Near the peak, grey cloud cover closes in overhead
   and the room dims strongly.
4. **Lightning** – stays dark and raining until the visitor chooses.
5. **Choice** – *Build another storm* or *Finish*.
6. **Ending** – the cloud dissolves, rain stops, the sky clears and the sun sets during the
   outro; a thank-you card, then everything fades out.

All UI sits on the **dashboard** (`Layout.dashboard`): the card for the moment plus the
control row (*Next step*, *Skip intro*, *Pause* → *Resume / Restart / End*).

See `MUI_Lightning_Group_3_Code_Guide.pdf` for the full architecture.

## Narration

All 23 lines are generated with a neural voice (Kokoro, voice `af_heart`) by
`Tools/make_narration.py`, which reads the texts straight from `Story/Script.swift`.
After editing a line, run it again (first run downloads the voice model, ~350 MB):

```
pip install kokoro-onnx soundfile numpy        # + ffmpeg
python3 Tools/make_narration.py                 # or: --voice bm_george --speed 0.92
python3 Tools/make_narration.py --samples       # compare voices → Tools/voice_samples/
```

A recording with the same file name in `MUI_Lightning_Group_3/Narration/` replaces any line.
The ambience is lowered automatically while the narrator speaks.

## The physical model

The landscape is 60 vertical, laser-cut profile slices. `Tools/bake_terrain.py` reads the
cutting SVGs (`Tools/laser_svg/`), recognises the slice numbers, and writes the heights to
`Resources/terrain_slices.json`. The app builds the occlusion mesh (physical model) and the
virtual landscape from it.

Not in the SVGs – set in `App/Layout.swift`:
- `slicePitch` – 7.0 mm centre to centre (board + 5 mm gap; measured from the scan),
- `firstSliceAtFront` – false: slice 01 is at the back (from the scan),
- `numberSideOnLeft` – the numbered end of the slices on the visitor's left (confirmed from a photo).

### Finding the model in the room

**Calibration (current setup):** the first time (in a new room, or after the plinth moved), a
calibration model appears: a see-through blue copy of the landscape inside a wire box with the
real model's outer dimensions (41 × 42 × 18 cm, orange = front, yellow dots = bottom corners).
Pinch and move it over the real model, turn it with both hands, line up the yellow corners with
the corners of the slices, then fine-tune with the arrows (3 mm / 0.5° steps: move, height, turn)
and **Save position**. visionOS stores this as a room anchor; every later start finds the
model by itself ("Finding the model …"). If it can't (other room, lights off), calibration opens
again. Start window → *Model moved? Place it again* forces a new calibration.

**No mask:** `Layout.useOcclusionMask = false`. Hand alignment is never millimetre-exact, and an
invisible mask that is a little off shows hard edges. Instead the room darkening (`SkyDimmer`)
is a dome with a vertical gradient: full storm darkness when looking ahead or up, fading to
about a fifth of it when looking down at the model (`fullAbove`, `clearBelow`, `floorLevel`).

**Object tracking (optional, off):** `Layout.useObjectTracking = false`. With a trained
`LandscapeModel.referenceobject` (Create ML, Object Tracking, from `LandscapeScan.usdz`, ~8 h of
training) the Vision Pro could recognise the model by itself. `LandscapeScan.usdz` is the
Scaniverse scan, registered to the slice data, scaled to the measured size and moved into model
space, so `Layout.scanAlignment` is identity.

The virtual landscape simply appears in front of the viewer.

## Sound

`Audio/AmbienceEngine.swift` synthesises wind (irregular gusts), rain (hiss + drops), rumble and
thunder – no audio assets, no regular swells.

## Clouds

`Tools/bake_clouds.py` bakes the Blender clouds into `MUI_Lightning_Group_3/Resources`:

```
pip install usd-core trimesh scipy rtree pillow numpy
python3 Tools/bake_clouds.py path/to/clouds_mui
```

## Where to change things

| What | Where |
|---|---|
| Narration ids/texts, chapter durations, which labels a chapter shows | `Story/Script.swift` |
| Label texts and icons | `Views/InfoLabels.swift` |
| Label positions on the objects | `SceneController.anchor(for:)` / `offset(for:)` |
| Storm progress panel | `Views/StormProgressView.swift`, position in `SceneController.attachProgress` |
| Pause / skip / restart buttons | `Views/HUDViews.swift` (`ControlBar`) |
| Sun path, light & shadows, 3D sun + aura | `Scene/AtmosphereEffects.swift`, surface texture from `Tools/bake_clouds.py` |
| Area where it rains | `StormCloud.rainArea` |
| Sun drag goal / start position | `Script.sunrise`, `Script.sunDragGoal` |
| Sun instruction card | `Views/SunInstructionView.swift` |
| Game rules (pairs needed, penalty) | `Game/StormGame.swift` |
| Model position in the room | `SceneController.modelPosition` |
| Terrain shape | `Tools/bake_terrain.py` → `Resources/terrain_slices.json`; spacing/orientation in `Layout` |
| Cloud / rain / wind / lightning | `Scene/StormCloud.swift`, `RainStreaks.swift`, `WindRibbons.swift`, `LightningBolt.swift` |
| Room darkening | `Scene/SkyDimmer.swift` |
| Grey cloud cover overhead (height, radius, when it appears) | `Scene/OvercastLayer.swift`, `SceneController.update` |
| + / − badges on the charged clouds | `Views/ChargeBadgeView.swift` |
| Hot/cold bubbles inside the cloud (glass look) | `Materials.bubble` in `Scene/SceneHelpers.swift`, `StormCloud` |

## Notes

- Debug builds are compiled with optimisation (`-O`): the scene updates thousands of cloud
  puffs and rain drops per frame, and unoptimised Swift made the drag and drop stutter.
  For step-by-step debugging set *Optimization Level* back to *None* temporarily.

- visionOS 2 APIs used: `LowLevelMesh`, `BillboardComponent`, directional light with shadows,
  `writesDepth` on materials. If a build fails on one of them, tell us the error.
