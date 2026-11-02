# Author: MUI group 3 – builds MUI_Lightning_Group_3_Code_Guide.pdf
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table,
                                TableStyle, PageBreak, KeepTogether, Preformatted, NextPageTemplate)
from reportlab.graphics.shapes import Drawing, Rect, String, Line, Polygon, Circle, Group
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

OUT = sys.argv[1]
F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", F + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Bold", F + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Oblique", F + "DejaVuSans-Oblique.ttf"))
pdfmetrics.registerFont(TTFont("Mono", F + "DejaVuSansMono.ttf"))
from reportlab.pdfbase.pdfmetrics import registerFontFamily
registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans-Oblique", boldItalic="Sans-Bold")

INK = colors.HexColor("#1B2430")
SUB = colors.HexColor("#5B6573")
NAVY = colors.HexColor("#1F3A5F")
STORM = colors.HexColor("#3E5C83")
AMBER = colors.HexColor("#E0952B")
RED = colors.HexColor("#D9483B")
BLUE = colors.HexColor("#3A78D8")
LINE = colors.HexColor("#D5DBE3")
TINT = colors.HexColor("#F2F5F9")
TINT2 = colors.HexColor("#FBF3E6")

W, H = A4
M = 20 * mm

ss = {
    "h1": ParagraphStyle("h1", fontName="Sans-Bold", fontSize=19, leading=24, textColor=NAVY, spaceBefore=4, spaceAfter=10),
    "h2": ParagraphStyle("h2", fontName="Sans-Bold", fontSize=12.5, leading=17, textColor=INK, spaceBefore=12, spaceAfter=5),
    "body": ParagraphStyle("body", fontName="Sans", fontSize=9.4, leading=13.6, textColor=INK, spaceAfter=6),
    "small": ParagraphStyle("small", fontName="Sans", fontSize=8.2, leading=11.2, textColor=SUB),
    "cell": ParagraphStyle("cell", fontName="Sans", fontSize=8.3, leading=11.2, textColor=INK),
    "cellb": ParagraphStyle("cellb", fontName="Sans-Bold", fontSize=8.3, leading=11.2, textColor=INK),
    "code": ParagraphStyle("code", fontName="Mono", fontSize=7.6, leading=10.2, textColor=INK),
    "cap": ParagraphStyle("cap", fontName="Sans-Oblique", fontSize=8, leading=11, textColor=SUB, spaceBefore=3, spaceAfter=10),
    "callout": ParagraphStyle("callout", fontName="Sans", fontSize=9, leading=13, textColor=INK),
}

def C(t):  # inline code
    return f'<font face="Mono" size="8.2" color="#1F3A5F">{t}</font>'

def P(t, s="body"):
    return Paragraph(t, ss[s])

def h1(n, t):
    return [Paragraph(f'<font color="#E0952B">{n}</font>&nbsp;&nbsp;{t}', ss["h1"])]

def table(rows, widths, header=True, zebra=True):
    data = [[P(c, "cellb" if (header and i == 0) else "cell") if isinstance(c, str) else c for c in r]
            for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"),
          ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
          ("TOPPADDING", (0, 0), (-1, -1), 3.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
          ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE)]
    if header:
        st += [("BACKGROUND", (0, 0), (-1, 0), TINT), ("LINEBELOW", (0, 0), (-1, 0), 0.8, NAVY)]
    if zebra:
        for i in range(2 if header else 1, len(rows), 2):
            st.append(("BACKGROUND", (0, i), (-1, i), colors.HexColor("#FAFBFD")))
    t.setStyle(TableStyle(st))
    return t

def callout(text, color=TINT2, bar=AMBER):
    t = Table([[P(text, "callout")]], colWidths=[W - 2 * M])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), color), ("LINEBEFORE", (0, 0), (0, -1), 3, bar),
                           ("LEFTPADDING", (0, 0), (-1, -1), 10), ("TOPPADDING", (0, 0), (-1, -1), 7),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 7)]))
    return t

# ---------- drawing helpers ----------
def box(d, x, y, w, h, title, sub=None, fill=TINT, stroke=NAVY, tc=INK, r=5, fs=8.4):
    d.add(Rect(x, y, w, h, rx=r, ry=r, fillColor=fill, strokeColor=stroke, strokeWidth=0.8))
    if sub:
        d.add(String(x + w / 2, y + h / 2 + 2.5, title, fontName="Sans-Bold", fontSize=fs, fillColor=tc, textAnchor="middle"))
        d.add(String(x + w / 2, y + h / 2 - 8, sub, fontName="Sans", fontSize=fs - 1.6, fillColor=SUB, textAnchor="middle"))
    else:
        d.add(String(x + w / 2, y + h / 2 - 3, title, fontName="Sans-Bold", fontSize=fs, fillColor=tc, textAnchor="middle"))

def arrow(d, x1, y1, x2, y2, color=SUB, w=0.9, head=4.5, dash=None):
    import math
    ln = Line(x1, y1, x2, y2, strokeColor=color, strokeWidth=w)
    if dash: ln.strokeDashArray = dash
    d.add(ln)
    a = math.atan2(y2 - y1, x2 - x1)
    p1 = (x2 - head * math.cos(a - 0.4), y2 - head * math.sin(a - 0.4))
    p2 = (x2 - head * math.cos(a + 0.4), y2 - head * math.sin(a + 0.4))
    d.add(Polygon([x2, y2, p1[0], p1[1], p2[0], p2[1]], fillColor=color, strokeColor=color, strokeWidth=0.5))

def label(d, x, y, t, fs=7, color=SUB, anchor="middle", font="Sans"):
    d.add(String(x, y, t, fontName=font, fontSize=fs, fillColor=color, textAnchor=anchor))

DW = W - 2 * M

def architecture():
    d = Drawing(DW, 336)
    for y, h_, name in [(252, 80, "SwiftUI – windows & attachments"), (140, 104, "State & logic"), (0, 132, "RealityKit scene")]:
        d.add(Rect(0, y, DW, h_, rx=6, ry=6, fillColor=colors.HexColor("#F7F9FC"), strokeColor=LINE, strokeWidth=0.6))
        label(d, 8, y + h_ - 12, name, fs=7.5, color=NAVY, anchor="start", font="Sans-Bold")
    vw = (DW - 12 - 4 * 6) / 5
    vx = 6
    for t, sub in [("StartView", "start window"), ("ImmersiveView", "RealityView · gestures"), ("DashboardView", "cards · controls"),
                   ("InfoLabelView", "labels on objects"), ("ChargeBadgeView", "+ / − on clouds")]:
        box(d, vx, 260, vw, 38, t, sub, fill=colors.white, fs=7.8)
        vx += vw + 6
    # logic
    box(d, 12, 190, 108, 34, "StoryDirector", "phases · timing", fill=colors.white)
    box(d, 12, 150, 108, 26, "Script", None, fill=colors.white)
    arrow(d, 66, 190, 66, 176)
    label(d, 70, 181, "reads", fs=6.3, anchor="start")
    box(d, 180, 170, 120, 46, "AppModel", "shared state · hub", fill=TINT2, stroke=AMBER)
    arrow(d, 120, 207, 180, 203); arrow(d, 180, 185, 120, 197)
    for k, t in enumerate(["StormGame", "NarrationPlayer", "AmbienceEngine"]):
        y = 204 - k * 28
        box(d, 370, y, 104, 22, t, None, fill=colors.white, fs=7.6)
        arrow(d, 300, 193, 370, y + 11)
    # scene
    box(d, 10, 44, 118, 44, "SceneController", "builds scene · frame loop", fill=TINT2, stroke=AMBER)
    arrow(d, 240, 170, 100, 88, color=AMBER, w=1.1)
    label(d, 176, 128, "owns", fs=6.6, color=AMBER, anchor="start")
    d.add(Rect(140, 10, DW - 148, 108, rx=6, ry=6, fillColor=colors.white, strokeColor=LINE, strokeWidth=0.6))
    arrow(d, 128, 66, 140, 66)
    subs = [("StormCloud", "morph · rain"), ("ChargedClouds", "drag & drop"), ("AtmosphereEffects", "sun · air · wind"),
            ("LightningBolt", "bolt · flicker"), ("OvercastLayer", "grey sky cover"), ("SkyDimmer", "room darkness"),
            ("Landscape", "slices · terrain"), ("HeadLockedFollower", "head pose")]
    cw = (DW - 148 - 10 - 3 * 6) / 4
    for i, (t, sub) in enumerate(subs):
        col, row = i % 4, i // 4
        box(d, 145 + col * (cw + 6), 64 - row * 48, cw, 40, t, sub, fill=TINT, stroke=STORM, fs=6.7)
    arrow(d, 150, 260, 220, 216, color=STORM); label(d, 166, 238, "reads / calls", fs=6.5, color=STORM, anchor="start")
    l = Line(270, 216, 270, 260, strokeColor=STORM, strokeWidth=0.9); l.strokeDashArray = [2, 2]; d.add(l)
    arrow(d, 270, 250, 270, 260, color=STORM)
    label(d, 276, 238, "@Observable updates", fs=6.5, color=STORM, anchor="start")
    return d

def phases():
    d = Drawing(DW, 200)
    y = 120
    steps = [("idle", "start window"), ("intro", "sun opening +\n11 chapters"), ("playing", "drag + / −"),
             ("lightning", "breakdown\n+ strike"), ("afterStrike", "dark · choice"), ("ending", "dissolve ·\nsunset · fade")]
    x = 4; xs = []
    for t, s in steps:
        fill = TINT2 if t in ("playing",) else colors.white
        d.add(Rect(x, y, 70, 46, rx=6, ry=6, fillColor=fill, strokeColor=NAVY, strokeWidth=0.8))
        label(d, x + 35, y + 31, t, fs=8.2, color=INK, font="Sans-Bold")
        for k, line in enumerate(s.split("\n")):
            label(d, x + 35, y + 18 - k * 9, line, fs=6.6)
        xs.append(x); x += 82
    for i in range(len(xs) - 1):
        arrow(d, xs[i] + 70, y + 23, xs[i + 1], y + 23)
    # loop back: build another storm
    d.add(Line(xs[4] + 35, y, xs[4] + 35, y - 26, strokeColor=AMBER, strokeWidth=1))
    d.add(Line(xs[4] + 35, y - 26, xs[2] + 35, y - 26, strokeColor=AMBER, strokeWidth=1))
    arrow(d, xs[2] + 35, y - 26, xs[2] + 35, y, color=AMBER, w=1)
    label(d, (xs[2] + xs[4]) / 2 + 35, y - 36, "“Build another storm” – the old storm passes while the new round starts", fs=6.8, color=AMBER)
    # skip intro
    d.add(Line(xs[1] + 35, y + 46, xs[1] + 35, y + 62, strokeColor=STORM, strokeWidth=0.8))
    d.add(Line(xs[1] + 35, y + 62, xs[2] + 35, y + 62, strokeColor=STORM, strokeWidth=0.8))
    arrow(d, xs[2] + 35, y + 62, xs[2] + 35, y + 46, color=STORM)
    label(d, (xs[1] + xs[2]) / 2 + 35, y + 66, "Skip intro", fs=6.8, color=STORM)
    # trigger labels
    label(d, (xs[2] + xs[3]) / 2 + 35, y + 50, "energy = 100 %", fs=6.4)
    # pause box
    d.add(Rect(4, 8, DW - 8, 48, rx=6, ry=6, fillColor=colors.HexColor("#F7F9FC"), strokeColor=LINE))
    label(d, 14, 40, "Pause (any phase except idle / ending):", fs=7.6, color=INK, anchor="start", font="Sans-Bold")
    label(d, 14, 27, "scene, story timers (AppModel.wait), narration and sound freeze.  Resume · Restart (back to intro) · End (→ ending).", fs=7, anchor="start")
    label(d, 14, 15, "Next step (intro only): ends the current chapter at once; during the sun opening the sun moves to midday by itself.", fs=7, anchor="start")
    return d

def frameloop():
    d = Drawing(DW, 250)
    box(d, 0, 205, 150, 34, "SceneEvents.Update", "RealityKit, every frame", fill=colors.white)
    box(d, 190, 205, 160, 34, "SceneController.update(dt)", None, fill=TINT2, stroke=AMBER)
    arrow(d, 150, 222, 190, 222)
    rows = [("1  head.update", "camera position from ARKit world tracking"),
            ("2  paused?", "→ only the room dimmer is refreshed, then return"),
            ("3  sun opening", "heat → thermals; sun speed limited to 0.045 / s"),
            ("4  current.approach(target)", "every value eases towards its target"),
            ("5  effects.update", "sun, air bubbles, wind lines"),
            ("6  cloud.update", "morph puffs, tint, charges, rain"),
            ("7  charged.update", "+ / − clouds float, mini-cloud puffs"),
            ("8  updateLabels", "fade in focus / dimmed / hidden, leader lines"),
            ("9  dimmer + overcast", "room darkness, grey sky cover"),
            ("10 audio.set", "rain, wind, rumble levels → AmbienceEngine")]
    y = 180
    for a, b in rows:
        d.add(Rect(190, y - 3, 160, 15, fillColor=colors.white, strokeColor=LINE, strokeWidth=0.5))
        label(d, 196, y + 1.5, a, fs=7.2, color=INK, anchor="start", font="Sans-Bold")
        label(d, 360, y + 1.5, b, fs=7, anchor="start")
        y -= 17.5
    arrow(d, 270, 205, 270, 195, head=3)
    return d

def marker(d, x, y, n, color):
    d.add(Circle(x, y, 6.5, fillColor=color, strokeColor=colors.white, strokeWidth=1))
    d.add(String(x, y - 2.6, str(n), fontName="Sans-Bold", fontSize=7, fillColor=colors.white, textAnchor="middle"))

def spaces():
    import math
    d = Drawing(DW, 250)
    S = 72; ox, oy = DW - 70, 26
    def X(z): return ox + z * S
    def Y(y): return oy + y * S
    d.add(Line(10, oy, DW - 10, oy, strokeColor=INK, strokeWidth=1))
    label(d, 14, oy - 11, "floor  (y = 0)", fs=7, anchor="start")
    # overcast band
    l = Line(10, Y(2.6), DW - 10, Y(2.6), strokeColor=colors.HexColor("#8A96A6"), strokeWidth=5); l.strokeDashArray = [12, 7]; d.add(l)
    # visitor
    d.add(Line(X(0), Y(0), X(0), Y(1.45), strokeColor=STORM, strokeWidth=2))
    d.add(Circle(X(0), Y(1.55), 7, fillColor=colors.white, strokeColor=STORM, strokeWidth=1.5))
    # table + model
    d.add(Rect(X(-1.2) - 0.45 * S, Y(0), 0.9 * S, 0.88 * S, fillColor=colors.HexColor("#EFE6DA"), strokeColor=SUB, strokeWidth=0.5))
    label(d, X(-1.2), Y(0.4), "table", fs=7)
    pts = []
    for i in range(41):
        z = -0.35 + 0.7 * i / 40
        h = 0.03 + 0.2 * math.exp(-((z + 0.2) ** 2) / 0.02) + 0.12 * math.exp(-((z - 0.12) ** 2) / 0.01)
        pts += [X(-1.2 + z), Y(0.9 + h)]
    pts += [X(-1.2 + 0.35), Y(0.9), X(-1.2 - 0.35), Y(0.9)]
    d.add(Polygon(pts, fillColor=colors.HexColor("#7E9A6B"), strokeColor=colors.HexColor("#5B7650"), strokeWidth=0.6))
    # cloud
    cz, cy = -1.26, 1.35
    for dx, dy, r in [(0, 0.1, 0.12), (-0.09, 0.05, 0.08), (0.09, 0.05, 0.08), (0, 0.28, 0.1), (-0.16, 0.44, 0.09), (0.13, 0.44, 0.08), (0, 0.46, 0.1)]:
        d.add(Circle(X(cz + dx), Y(cy + dy), r * S, fillColor=colors.HexColor("#DDE3EA"), strokeColor=colors.HexColor("#B7C1CC"), strokeWidth=0.5))
    # sun + path arc
    for i in range(30):
        a0 = math.pi * i / 30; a1 = math.pi * (i + 1) / 30
        if i % 2 == 0:
            d.add(Line(X(-1.75) + 0.0, Y(1.1 + 0.65 * math.sin(a0)), X(-1.75), Y(1.1 + 0.65 * math.sin(a1)), strokeColor=colors.white))
    d.add(Circle(X(-1.75), Y(1.55), 8, fillColor=AMBER, strokeColor=AMBER))
    # dashboard
    d.add(Rect(X(-0.78) - 3, Y(1.1) - 14, 6, 28, fillColor=TINT2, strokeColor=AMBER, strokeWidth=1))
    # markers
    marker(d, X(0), Y(0), 1, AMBER)
    marker(d, X(0) + 16, Y(1.55), 2, STORM)
    marker(d, X(-1.2), Y(0.9), 3, RED)
    marker(d, X(cz), Y(cy), 4, NAVY)
    marker(d, X(-0.78) + 12, Y(1.1), 5, AMBER)
    marker(d, X(-1.75) - 16, Y(1.55), 6, AMBER)
    marker(d, 40, Y(2.6), 7, SUB)
    arrow(d, 40, 200 - 120, 40, 200 - 90, color=INK); label(d, 46, 108, "+y", fs=7, anchor="start", color=INK)
    arrow(d, 40, 80, 8, 80, color=INK); label(d, 20, 68, "−z (forward)", fs=7, anchor="start", color=INK)
    return d

SPACE_LEGEND = [["#", "What", "Position"],
    ["1", "Immersive-space origin (floor below the visitor's start position)", "(0, 0, 0)"],
    ["2", "Visitor's head (tracked by ARKit, not fixed)", "≈ (0, 1.55, 0)"],
    ["3", "Model origin = centre of the model footprint – placed via the saved room anchor", "found automatically"],
    ["4", "Cloud base · Layout.cloudBase", "(0.05, 0.45, −0.06) model"],
    ["5", "Dashboard · Layout.dashboard", "(0, 0.2, 0.42) model"],
    ["6", "Sun on its path: arc 0.55 m behind the model, up to 0.85 m above it", "model space"],
    ["7", "Overcast cover near the storm's peak: 2.5–3 m high, 1.9–4.6 m around", "world"]]

def pipeline():
    d = Drawing(DW, 92)
    steps = [("Blender", "cloud_start / cloud_end\nUSD + VDB"), ("Tools/bake_clouds.py", "fill meshes with puffs,\nbake light, pair puffs"),
             ("Resources/", "cloud_morph.json\n+ PNG textures"), ("CloudAssets", "load data,\nmake materials"), ("SpriteBatch", "one mesh,\nsorted puffs")]
    x = 2
    for i, (t, s) in enumerate(steps):
        fill = TINT2 if i == 1 else colors.white
        d.add(Rect(x, 20, 86, 58, rx=6, ry=6, fillColor=fill, strokeColor=NAVY, strokeWidth=0.8))
        label(d, x + 43, 63, t, fs=7.4, color=INK, font="Sans-Bold")
        for k, line in enumerate(s.split("\n")):
            label(d, x + 43, 47 - k * 10, line, fs=6.6)
        if i < len(steps) - 1:
            arrow(d, x + 86, 49, x + 96, 49)
        x += 96
    label(d, 2 + 96 * 1.5 + 43 - 48, 6, "run once on a computer (Python)", fs=6.6, color=AMBER)
    label(d, 2 + 96 * 3.5 + 43 - 48, 6, "runs in the app (Swift)", fs=6.6, color=STORM)
    return d

# ---------- content ----------
story = []
# cover
story += [Spacer(1, 70),
          Paragraph('<font color="#E0952B">MUI group 3</font>', ParagraphStyle("k", fontName="Sans-Bold", fontSize=10, textColor=AMBER)),
          Spacer(1, 6),
          Paragraph("Lightning – Code Guide", ParagraphStyle("t", fontName="Sans-Bold", fontSize=30, leading=36, textColor=NAVY)),
          Spacer(1, 8),
          Paragraph("How the Apple Vision Pro project MUI_Lightning_Group_3 is built: architecture, files, "
                    "coordinate spaces, the frame loop, and where every parameter lives.",
                    ParagraphStyle("st", fontName="Sans", fontSize=12, leading=17, textColor=SUB)),
          Spacer(1, 30)]
toc = [["", "Contents"],
       ["1", "The experience in one page"], ["2", "Project structure"], ["3", "Architecture – how the parts talk"],
       ["4", "Story flow and phases"], ["5", "Spaces, volumes and coordinates"], ["6", "The frame loop"],
       ["7", "How things are drawn"], ["8", "Interaction"], ["9", "Sound and narration"],
       ["10", "Cloud asset pipeline"], ["11", "Parameter reference"], ["12", "Common changes, step by step"],
       ["13", "Troubleshooting"]]
t = Table([[P(a, "cellb" if i == 0 else "cell"), P(b, "cellb" if i == 0 else "cell")] for i, (a, b) in enumerate(toc)],
          colWidths=[14 * mm, 110 * mm])
t.setStyle(TableStyle([("LINEBELOW", (0, 0), (-1, 0), 0.8, NAVY), ("LINEBELOW", (0, 1), (-1, -1), 0.3, LINE),
                       ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]))
story += [t, Spacer(1, 24),
          callout("<b>Reading tip.</b> Sections 1–6 explain the big picture; read them once. Sections 11–12 are the "
                  "everyday reference: “I want to change X – which file and which value?”"),
          PageBreak()]

# 1
story += h1("1", "The experience in one page")
story += [P("A visitor wearing an Apple Vision Pro stands in front of a laser-cut landscape model (60 vertical profile slices: mountains, valleys, open land). "
            "The app adds the weather above it in mixed reality: the sun, rising warm air, wind, a growing cloud, rain and lightning."),
          table([["Step", "What the visitor sees and does", "Code"],
                 ["0  Start window", "Chooses <b>With the physical model</b> or <b>Virtual landscape</b>.", C("StartView")],
                 ["1  Sun opening", "Drags the sun along a white path from sunrise to midday (speed-limited, ≈ 9 s). Warm air starts rising.", C("StoryDirector.waitForSunDrag")],
                 ["2  Intro", "11 narrated chapters: heating, rising air, wind, condensation, tower, anvil, inside the cloud, charge separation, rain. Labels appear one by one on the objects.", C("Script.intro")],
                 ["3  Play", "Drags + / − clouds into the storm. Balanced charge raises the storm energy; the room darkens, rain, grey sky cover closes in.", C("StoryDirector.handleAbsorb")],
                 ["4  Lightning", "At 100 % energy: flicker, branching bolt to the highest peak, room flash, thunder.", C("SceneController.strike")],
                 ["5  Choice", "Stays dark and raining. Build another storm or Finish.", C("AfterStrikeView")],
                 ["6  Ending", "Cloud dissolves, rain stops, sky clears, sun sets, thank-you card, fade-out.", C("StoryDirector.playEnding")]],
                [28 * mm, 100 * mm, 42 * mm]),
          Spacer(1, 8),
          P("All buttons and status cards share one place in the room, the <b>dashboard</b>: the storm-energy bar, the sun instruction, "
            "the after-strike choice and the thank-you card, with the control row (Next step, Skip intro, Pause) underneath."),
          PageBreak()]

# 2
story += h1("2", "Project structure")
story += [P("The Xcode project uses <i>folder-synchronised groups</i>: every file inside the "
            f"{C('MUI_Lightning_Group_3/')} folder is part of the app automatically – add or delete files in Finder and Xcode follows."),
          table([["Folder", "File", "Responsibility"],
                 ["App/", "MUI_Lightning_Group_3App", "Entry point. Declares the start window (WindowGroup) and the ImmersiveSpace."],
                 ["", "AppModel", "Central shared state: phase, pause, labels, storm level, slot charges. Owns director, game, narration, audio, scene."],
                 ["", "Layout", "All placements in the room (model, cloud base, dashboard). Change positions here."],
                 ["Story/", "Script", "Narration line ids + texts, chapter order, fallback durations, what each chapter shows."],
                 ["", "StoryDirector", "Runs the phases: intro → play → lightning → choice → ending. Reacts to absorbed clouds."],
                 ["", "NarrationPlayer", "Plays recorded narration files; waits for them to finish; pause/resume."],
                 ["Game/", "StormGame", "The rules: counts + and −, computes storm intensity 0…1."],
                 ["Audio/", "AmbienceEngine", "Real-time synthesised wind, rain, rumble, thunder, chime; master fade."],
                 ["Scene/", "SceneController", "Builds the 3D scene, runs the per-frame update, story hooks (strike, discharge, ending)."],
                 ["", "StormCloud", "Main cloud: morph start → anvil, storm tint, charge bubbles inside, rain + mist."],
                 ["", "ChargedClouds", "The six + / − mini clouds: spawning, floating, drag & drop, absorb."],
                 ["", "AtmosphereEffects", "Sun (3D body, aura, light, path), rising-air bubbles (AirParticles), wind lines."],
                 ["", "WindRibbons", "Wind as fading streamlines following the terrain (intro only)."],
                 ["", "RainStreaks", "Up to 2600 thin rain streaks, slanted by the wind."],
                 ["", "LightningBolt", "Procedural branching bolt + flicker pattern."],
                 ["", "OvercastLayer", "Grey cloud cover overhead near the storm's peak."],
                 ["", "SkyDimmer", "Darkens / flashes the real room (planes ≈ 5 m around the head)."],
                 ["", "Landscape", "Terrain from the baked slices, virtual terrain + texture, occlusion mesh."],
                 ["", "SpriteBatch", "Draws many soft camera-facing puffs as one mesh (clouds, overcast)."],
                 ["", "CloudAssets", "Loads baked cloud data and textures; creates cloud / sun / wind / rain materials."],
                 ["", "HeadLockedFollower", "Head position from ARKit (used for sorting, billboards, dimmer)."],
                 ["", "SceneHelpers", "Materials (incl. glass bubbles), ramp/lerp helpers, opacity helper."],
                 ["Views/", "StartView", "Start window with the two landscape choices."],
                 ["", "ImmersiveView", "RealityView: builds the scene, registers attachments and gestures."],
                 ["", "DashboardView", "The card for the moment + control row; EndingView."],
                 ["", "HUDViews", "ControlBar (pause, next, skip …) and AfterStrikeView."],
                 ["", "StormProgressView", "Storm-energy bar, + / − counts, status text."],
                 ["", "SunInstructionView", "“Move the sun across the sky” card with progress."],
                 ["", "InfoLabels", "Texts, icons and colours of the info labels."],
                 ["", "ChargeBadgeView", "+ / − symbol on each charged cloud."],
                 ["Resources/", "cloud_morph.json, *.png", "Baked clouds and textures (generated by the bake script)."],
                 ["Narration/", "*.m4a …", "Narration, one file per line id – generated with a neural voice (Tools/make_narration.py) or recorded."],
                 ["", "terrain_slices.json", "Heights of the 60 laser-cut slices (generated by Tools/bake_terrain.py)."],
                 ["Tools/ (outside app)", "bake_clouds.py", "Turns the Blender clouds into Resources/."]],
                [27 * mm, 40 * mm, 103 * mm]),
          PageBreak()]

# 3
story += h1("3", "Architecture – how the parts talk")
story += [P("The app follows a simple hub pattern. <b>AppModel</b> is the single source of truth that SwiftUI observes. "
            "<b>StoryDirector</b> decides <i>when</i> things happen; <b>SceneController</b> decides <i>how they look</i>. "
            "Views never touch 3D entities directly – they call methods on AppModel or its director."),
          architecture(),
          Paragraph("Figure 1 – Layers. Orange boxes are the two hubs; arrows show who calls whom.", ss["cap"]),
          P("<b>Target / current state.</b> Almost every visual quantity (sun position, cloud growth, storm darkness, wind …) is a field of "
            f"{C('AtmosphereState')}. The story only sets {C('scene.target.x = …')}; every frame {C('current.approach(target)')} "
            "moves the current value a little towards it (exponential easing). That is why every change in the experience is smooth "
            "without any animation code in the story."),
          table([["Field", "Meaning", "Set by"],
                 [C("sunVisible / sunProgress"), "sun fade-in; position on its path 0 (sunrise) … 1 (sunset)", "Script, sun drag, ending"],
                 [C("thermals"), "amount of warm air rising from the ground", "sun opening, Script"],
                 [C("wind / windVisible"), "wind strength (rain slant, sound) / visible wind lines + moist lowland air", "Script, storm intensity"],
                 [C("cloudGrowth / anvil"), "0 = no cloud … 1 = full tower; anvil spread", "Script, storm intensity, ending"],
                 [C("interior / separation / xray"), "show particles inside; + up / − middle; see-through shell", "Script"],
                 [C("storm"), "0 … 1 – darkness, rain, overcast, sound", "storm intensity, discharge, clearSky"],
                 [C("rainPulse"), "extra rain for explanations and after the strike", "Script, discharge"]],
                [48 * mm, 80 * mm, 42 * mm]),
          PageBreak()]

# 4
story += h1("4", "Story flow and phases")
story += [P(f"{C('AppModel.phase')} tells every part where we are. The dashboard, the control row and the label logic all switch on it."),
          phases(),
          Paragraph("Figure 2 – Phases. Pause, Next step and Skip intro work on top of these.", ss["cap"]),
          P("<b>Chapter timing.</b> Each intro chapter lasts as long as its narration file in Narration/ (or its fallback seconds in "
            f"Script.swift), plus 0.6 s. All waiting goes through {C('AppModel.wait')}, which stops counting while paused and ends early on Next step."),
          P(f"<b>Labels in sequence.</b> A chapter calls {C('app.showLabels([...])')}. The labels appear one after another, spread over ~75 % of the chapter; "
            "the newest is in focus (100 %), earlier ones of the chapter dim to 35 %, labels of previous chapters fade out."),
          P("<b>Storm energy.</b> StormGame counts absorbed charges. Energy = (balanced pairs − 0.75 × excess) / 4, clamped 0…1. "
            "4 balanced pairs → 100 % → lightning. An unbalanced cloud lowers the energy and the sky clears a bit."),
          P("<b>Ending.</b> Finish (or End while paused) runs StoryDirector.playEnding: storm → 0, cloud evaporates puff by puff, sun sets, sound "
            "fades to 35 %, outro plays, then the whole scene fades out (2.5 s) and the start window returns."),
          PageBreak()]

# 5
story += h1("5", "Spaces, volumes and coordinates")
story += [P("<b>Windows and spaces.</b> The app has two SwiftUI scenes:"),
          table([["Scene", "Type", "What it is"],
                 ["StartWindow", "WindowGroup", "A normal floating window with the two start choices. Closed when the experience starts, reopened at the end."],
                 ["LightningSpace", "ImmersiveSpace, style .mixed", "The experience. Mixed: the real room stays visible (passthrough); virtual content is added. No other apps' windows are hidden."]],
                [32 * mm, 42 * mm, 96 * mm]),
          Spacer(1, 6),
          P("<b>Units and axes.</b> RealityKit uses metres. +y is up, −z is forward (away from the visitor at start), +x is to the right."),
          spaces(),
          Paragraph("Figure 3 – Side view (roughly to scale). The model, cloud, sun and dashboard live in model space, so moving the model moves everything.", ss["cap"]),
          table(SPACE_LEGEND, [8 * mm, 112 * mm, 50 * mm]),
          PageBreak(),
          P("<b>The coordinate spaces in the code:</b>"),
          table([["Space", "Origin", "Used for"],
                 ["Immersive space (world)", "Floor below where the visitor stood when the space opened", "head position, room dimmer, overcast"],
                 ["Model space (modelRoot)", "Centre of the model footprint on its supports – placed from the saved room anchor (WorldAnchor)", "terrain, sun, air, wind, labels, dashboard, charged clouds, bolt"],
                 ["Cloud space", "Layout.cloudBase inside model space", "main cloud puffs, rain sources"],
                 ["Cloud body", "same, but scaled with the storm (0.95 … 1.07) and pulses", "puffs, charge bubbles"],
                 ["Attachment views", "SwiftUI points, placed as entities", "labels, badges, dashboard (BillboardComponent: always face the viewer)"]],
                [38 * mm, 66 * mm, 66 * mm]),
          Spacer(1, 10)]
story += [P("<b>Entity tree.</b> What SceneController.build creates:"),
          Preformatted("""root
├─ modelRoot                       placed from the room anchor (placement ghost while placing)
│  ├─ LandscapeEntity               terrain from the slices (texture or occlusion)
│  ├─ AtmosphereEffects             sun aura + 3D sun body + DirectionalLight (shadows), path line
│  │   ├─ AirParticles              rising air bubbles (temperature colours)
│  │   └─ WindRibbons               wind streamlines
│  ├─ StormCloud                    position = Layout.cloudBase
│  │   ├─ body → SpriteBatch puffs, charge bubbles, inner glow
│  │   ├─ mist emitter, RainStreaks
│  ├─ ChargedCloudField             6 slots → MiniCloud + ChargeBadge attachment
│  ├─ LightningBolt
│  ├─ dashboard attachment          position = Layout.dashboard
│  └─ info label attachments + leader lines + dots
├─ head follower entity            (ARKit head pose)
├─ SkyDimmer                       6 planes, 5 m around the head
└─ OvercastLayer                   8 sectors of grey puffs overhead""", ss["code"]),
          Spacer(1, 8),
          callout("<b>Physical vs. virtual landscape.</b> With the physical model, the terrain mesh uses an <b>OcclusionMaterial</b>: invisible, "
                  "but it hides rain, wind and the bolt behind the real mountains. That only works if "
                  f"{C('Terrain')} in Landscape.swift matches the real model's shape and the saved placement lines up with it (re-place after moving the plinth)."),
          PageBreak()]

# 6
story += h1("6", "The frame loop")
story += [P("Everything that moves is driven from one place. ImmersiveView subscribes to RealityKit's per-frame update event and calls "
            f"{C('SceneController.update(dt:)')} about 90 times per second."),
          frameloop(),
          Paragraph("Figure 4 – One frame. dt is clamped to 50 ms so a hiccup never makes things jump.", ss["cap"]),
          callout("<b>Performance.</b> Each frame recalculates ~1100 main-cloud puffs, 6 × 150 mini-cloud puffs, 480 overcast puffs, up to 2600 rain "
                  "streaks and the wind lines in Swift. That's why Debug builds are compiled with optimisation (-O). Puff sorting only re-runs "
                  "when the camera has moved ≥ 2 cm or every 6 frames (SpriteBatch)."),
          PageBreak()]

# 7
story += h1("7", "How things are drawn")
story += [table([["Element", "Technique", "File"],
                 ["Clouds", "Soft, camera-facing puffs (octagons with a baked puff texture), sorted far → near, all in one LowLevelMesh. "
                            "Light and shadow are baked per puff; a material tint darkens the cloud with the storm.", "SpriteBatch, StormCloud, CloudAssets"],
                 ["Cloud growth", "Every start puff is paired with an end (anvil) puff. A puff rises first, then spreads sideways; higher puffs start later. "
                                  "Growing below 0.35 = condensation (puffs fade in one by one).", "StormCloud.updateSprites"],
                 ["Charge bubbles", "Translucent glass spheres (clear-coat) with glowing cores; red + / blue −; white/grey before separation.", "StormCloud, Materials.bubble"],
                 ["Rain", "Thin streak quads aligned to each drop's velocity; spawn over an organic area covering the landscape, from an uneven ceiling; grow in over 0.1 s.", "RainStreaks, StormCloud.rainArea"],
                 ["Rising air", "Small glass bubbles. Warm ground: red (hot) cooling to light blue as they rise. Lowlands: blue moist air, carried by the wind, then up.", "AirParticles"],
                 ["Wind", "28 streamlines through a flow field that follows the terrain and is sucked up under the cloud. Intro only.", "WindRibbons"],
                 ["Sun", "Emissive 3D sphere with a slowly turning granulated surface, inside a large soft aura (no rays); real directional light + shadows.", "AtmosphereEffects"],
                 ["Lightning", "Midpoint-displacement main channel, 7 branches, 3 in-cloud channels; white core + blue glow cylinders; flicker pattern ≈ 1.6 s.", "LightningBolt"],
                 ["Room darkening", "Semi-transparent planes 5 m around the head – up to 85 % dark, blue-grey; flash bright during lightning.", "SkyDimmer"],
                 ["Overcast", "480 dark-grey puffs in 8 sectors, 2.5–3 m high, gathering from 25 % storm energy.", "OvercastLayer"],
                 ["Virtual terrain", "Height mesh from the 60 slices (2 mm along, smoothed between slices); texture generated at start from the relief (meadow, forest, alpine meadow, rock, snow).", "Landscape"],
                 ["UI", "SwiftUI views placed in 3D as RealityView attachments, turned to the viewer (BillboardComponent). Leader lines are opaque so cards cover them.", "Views/, SceneController"]],
                [26 * mm, 104 * mm, 40 * mm]),
          Spacer(1, 6),
          callout("<b>Transparency rules that matter.</b> Soft sprites set <i>writesDepth = false</i> (otherwise their transparent corners cut square holes). "
                  "Opaque objects are always drawn before transparent ones – used on purpose for the label leader lines.",
                  color=TINT, bar=STORM),
          PageBreak()]

# 8
story += h1("8", "Interaction")
story += [table([["Gesture", "On", "What happens", "Code"],
                 ["Pinch + drag", "+ / − cloud", "Cloud follows the hand (grows 12 %). Counts as dropped when it covers the storm from the visitor's view "
                                                  "(angle check, works although a drag keeps its depth). The storm pulses while hovering.", "ChargedCloudField.drag / endDrag"],
                 ["Tap", "+ / − cloud", "Sends it straight into the storm.", "sendToStorm"],
                 ["Pinch + drag", "sun (opening only)", "Sets the target on the path; the sun follows at max 0.045 progress / s, so the morning can't be rushed.", "SceneController.dragSun"],
                 ["Buttons", "dashboard", "Next step, Skip intro, Pause → Resume / Restart / End, Build another storm, Finish.", "ControlBar, AfterStrikeView"]],
                [22 * mm, 26 * mm, 84 * mm, 38 * mm]),
          Spacer(1, 6),
          P("<b>Feedback when a cloud is absorbed:</b> chime (rising two notes = good, falling = wrong charge) + soft whoosh, the storm swells "
            "briefly and lights up inside, energy bar and counts update, optional recorded feedback line."),
          P("Gestures are registered once in ImmersiveView: one DragGesture targeted to any entity (checks for SunComponent or ChargeComponent) and a "
            "SpatialTapGesture for ChargeComponent. Entities are only hit-testable if they have an InputTargetComponent and a CollisionComponent."),
          Spacer(1, 4)]
story += h1("9", "Sound and narration")
story += [table([["Part", "How", "Where"],
                 ["Ambience", "AVAudioEngine source node, synthesised live: wind (band-passed noise, random gusts), rain (hiss + drops), rumble.", "AmbienceEngine"],
                 ["Thunder", "Crack + long rolling rumble (≈ 6 s audible, 10 s tail), mid band so small speakers can play it, echo boom after 1.4 s; starts 0.65 s after the flash.", "AmbienceDSP, SceneController.strike"],
                 ["Chime", "Sine notes + octave, 0.55 s decay; whoosh = filtered noise swell.", "AmbienceEngine.chime"],
                 ["Levels", "rain / wind / rumble follow the storm every frame; master fades for the ending.", "SceneController.update, fade(to:)"],
                 ["Narration", "Neural voice (Kokoro af_heart) generated from Script.swift by Tools/make_narration.py; any file can be swapped for a recording. Ambience ducks while it speaks. Missing files → fallback duration.", "NarrationPlayer, Script"]],
                [24 * mm, 104 * mm, 42 * mm]),
          PageBreak()]

# 10
story += h1("10", "Cloud asset pipeline")
story += [P("RealityKit can't render Blender's OpenVDB volumes, so the volumetric look is rebuilt from soft puffs. This happens once, offline:"),
          pipeline(),
          Paragraph("Figure 5 – From Blender to the screen.", ss["cap"]),
          Preformatted("pip install usd-core trimesh scipy rtree pillow numpy\npython3 Tools/bake_clouds.py path/to/clouds_mui", ss["code"]),
          Spacer(1, 6),
          table([["Output", "Content"],
                 [C("cloud_morph.json"), "1100 puffs: start position, size, brightness; end position, size, brightness; delay; seed. Plus 150 puffs for the mini clouds."],
                 [C("cloud_puff_atlas(.png/_alpha)"), "16 brightness columns × 4 puff shapes."],
                 [C("sun_glow, sun_surface"), "Soft sun aura; granulated sun surface (equirectangular)."],
                 [C("wind_streak"), "Soft streak used for wind lines and rain."]],
                [52 * mm, 118 * mm]),
          Spacer(1, 6),
          P("Look parameters at the top of the script: " + C("SPRITES") + ", " + C("DENSITY") + ", " + C("LIGHT_DIR") + ", " + C("END_GREY") + ", " +
            C("METERS_PER_UNIT") + " (cloud size in the room). The virtual terrain texture is <i>not</i> baked – it is generated in Swift at start."),
          PageBreak()]

# 11
story += h1("11", "Parameter reference")
P11 = [["What you want to change", "File · symbol", "Current value"],
       ["Where the model is in the room", "Placed once on site (Save position) → WorldAnchor; fallback Layout.modelPosition (simulator)", "found automatically"],
       ["Virtual landscape distance / height", "Layout.viewerDistance · baseBelowEyes", "0.9 m · 0.6 m"],
       ["Height / position of the storm cloud", "Layout.cloudBase", "(0.05, 0.45, −0.06) m"],
       ["Where all UI sits (bar, cards, buttons)", "Layout.dashboard", "(0, 0.2, 0.42) m"],
       ["Terrain shape", "Tools/bake_terrain.py → terrain_slices.json", "60 slices, 409 mm wide"],
       ["Slice spacing / orientation", "Layout.slicePitch · firstSliceAtFront · numberSideOnLeft", "7.0 mm · no · yes"],
       ["Where lightning hits", "Terrain.strikePoint", "highest peak"],
       ["Narration texts, ids, chapter order", "Script.swift · intro", "11 chapters + 1 drag line"],
       ["Chapter length without recording", "IntroStep.fallback", "5–11 s"],
       ["Sun start / goal of the drag", "Script.sunrise / sunDragGoal", "0.06 / 0.45"],
       ["Sun drag speed limit", "SceneController.maxSunSpeed", "0.045 / s (≈ 9 s)"],
       ["Ending length / fade-out", "Script.endingDuration / fadeOutDuration", "8 s / 2.5 s"],
       ["Pairs needed for lightning", "StormGame.pairsNeeded", "4"],
       ["Penalty for unbalanced charge", "StormGame.imbalancePenalty", "0.75"],
       ["Number of charged clouds / size", "ChargedCloudField.slotCount / cloudSize", "6 / 0.13 m"],
       ["Charged cloud positions (arc)", "ChargedCloudField.init · angles, heights", "6 slots, radius ≈ 0.5 m"],
       ["How fast values ease", "AtmosphereState.approach", "rates 0.35 … 1.5 per s"],
       ["Storm → cloud size / wind", "SceneController.setStormIntensity", "growth 0.6→1, wind 0.35→1"],
       ["Room darkness at peak", "SkyDimmer.update", "85 %"],
       ["When overcast appears", "SceneController.update · overcast", "from 25 % → full at 85 %"],
       ["Overcast height / radius", "OvercastLayer static lets", "2.5 m · 1.9–4.6 m"],
       ["Rain amount / area", "RainStreaks.capacity · StormCloud.rainArea", "2600 drops · landscape"],
       ["Label texts / icons / colours", "InfoLabels.swift", "14 labels"],
       ["Label positions on objects", "SceneController.anchor / offset", "per label"],
       ["Label timing / dim level", "AppModel.showLabels · updateLabels", "1.4–3.2 s apart · 35 %"],
       ["Sun aura size", "AtmosphereEffects.auraSize", "0.62 m"],
       ["Air bubble colours", "AirParticles.scale", "blue → red, 7 steps"],
       ["Thunder length / loudness", "AmbienceDSP · thunderDecay, gains", "10 s tail"],
       ["Chime notes", "AmbienceDSP · notes", "A5→E6 good, G4→D4 wrong"],
       ["Cloud look (bake)", "Tools/bake_clouds.py top", "DENSITY, LIGHT_DIR …"]]
story += [table(P11, [70 * mm, 62 * mm, 38 * mm]), PageBreak()]

# 12
story += h1("12", "Common changes, step by step")
howto = [
    ("Move the dashboard (bar, cards, buttons)", f"Change {C('Layout.dashboard')}. Model space: y up from the base plate, +z towards the visitor."),
    ("Place the model in a new room", "Start with the physical model. If no saved position is found, the blue see-through landscape appears: move it onto the real model (pinch and drag, turn with both hands, fine buttons), orange edge = front, then Save position. Later starts find it by themselves; the start window has Model moved? Place it again."),
    ("Update the terrain after re-cutting the model", f"Export the cutting SVGs into {C('Tools/laser_svg/')} and run {C('python3 Tools/bake_terrain.py Tools/laser_svg')}. Slice numbers are read automatically. Then set {C('Layout.slicePitch')} to the measured spacing."),
    ("Change narration text or voice", f"Edit the line in Script.swift, then run {C('python3 Tools/make_narration.py')} (add {C('--voice bm_george')} for another voice). A recording with the same file name in {C('Narration/')} replaces a line."),
    ("Change what a chapter shows", f"Edit its {C('apply')} closure in Script.intro: set {C('scene.target.…')} values and {C('app.showLabels([...])')}."),
    ("Add an info label", f"Add a case to {C('InfoLabel')} (title, detail, symbol, tint), an anchor + offset in SceneController, and use it in a chapter."),
    ("Make lightning easier / harder", f"Change {C('StormGame.pairsNeeded')} or {C('imbalancePenalty')}."),
    ("Re-bake the clouds after changing them in Blender", "Export again as before, run the bake script (section 10), rebuild."),
    ("Make the storm darker / lighter", f"SkyDimmer (room), {C('StormCloud.updateMaterial')} (cloud tint), OvercastLayer.update (cover tint)."),
]
story += [table([["Task", "How"]] + [[a, b] for a, b in howto], [52 * mm, 118 * mm]), Spacer(1, 6)]
story += h1("13", "Troubleshooting")
story += [table([["Symptom", "Likely cause / fix"],
                 ["Build error on a visionOS API", "Uses visionOS 2 APIs (LowLevelMesh, writesDepth, DynamicLightShadowComponent, shadows, emissive textures). Check the deployment target is 2.0+; otherwise send the exact error."],
                 ["Laggy drag, low frame rate", "Debug optimisation set back to None. Set Build Settings → Swift Optimization Level → -O."],
                 ["Rain / bolt visible in front of real mountains", "Placement is off – start window → Model moved? Place it again. Or slicePitch / orientation flags don't match."],
                 ["Clouds look blocky / square", "A material writes depth or has a hover effect. Keep writesDepth = false, no HoverEffectComponent on puffs."],
                 ["No narration", "File names must match the ids exactly; files must be inside the app folder (check Target Membership)."],
                 ["Missing cloud", "Resources/cloud_morph.json missing – run the bake script."]],
                [52 * mm, 118 * mm])]

def on_page(c, doc):
    c.saveState()
    if doc.page > 1:
        c.setFont("Sans", 7.5); c.setFillColor(SUB)
        c.drawString(M, 12 * mm, "MUI_Lightning_Group_3 · Code Guide")
        c.drawRightString(W - M, 12 * mm, f"MUI group 3  ·  {doc.page}")
        c.setStrokeColor(LINE); c.setLineWidth(0.5); c.line(M, 15 * mm, W - M, 15 * mm)
    else:
        c.setFillColor(NAVY); c.rect(0, H - 14 * mm, W, 14 * mm, stroke=0, fill=1)
        c.setFillColor(AMBER); c.rect(0, H - 15.5 * mm, W, 1.5 * mm, stroke=0, fill=1)
    c.restoreState()

doc = BaseDocTemplate(OUT, pagesize=A4, leftMargin=M, rightMargin=M, topMargin=18 * mm, bottomMargin=20 * mm,
                      title="Lightning – Code Guide", author="MUI group 3", subject="MUI_Lightning_Group_3 architecture")
frame = Frame(M, 20 * mm, W - 2 * M, H - 38 * mm, id="f")
doc.addPageTemplates([PageTemplate(id="p", frames=[frame], onPage=on_page)])
doc.build(story)
print("ok", OUT)
