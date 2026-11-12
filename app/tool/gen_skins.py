"""Theta.Hatch.Series の design/skins/skins.json（スキンの正本）から lib/ui/hud/skins.g.dart を作る。

    python tool/gen_skins.py <Theta.Hatch.Series>/design/skins/skins.json

skins.g.dart は手で直さない。スキンが増えたり色が変わったりしたら、これをもう一度実行する。
"""
import json
import sys

src = sys.argv[1]
d = json.load(open(src, encoding="utf-8"))


def color(v):
    v = v.lstrip("#")
    if len(v) == 6:
        v = "FF" + v
    return f"Color(0x{v.upper()})"


out = [
    "// 生成ファイル：手で直さない。python tool/gen_skins.py <Theta.Hatch.Series>/design/skins/skins.json",
    "// 正本は Theta.Hatch.Series の design/skins/skins.json（シリーズ共通のスキン ui.skin）",
    "import 'package:flutter/painting.dart';",
    "",
    "import 'hud_theme.dart';",
    "",
    "/// ui.skin の値（system は端末の明暗で dark・light）",
    "const skinNames = <String>[" + ", ".join(f"'{n}'" for n in d["setting"]["values"]) + "];",
    "",
    "const skinLabels = <String, String>{",
]
for k, v in d["skins"].items():
    out.append(f"  '{k}': '{v['label']}',")
out += ["};", "", "const skinPalettes = <String, Palette>{"]
for k, v in d["skins"].items():
    c = v["color"]
    out.append(f"  '{k}': Palette(")
    for role in ["bg", "panel", "raised", "fg", "muted", "faint", "line", "accent", "onAccent", "widget", "launch",
                 "zebra", "accent2", "accent3"]:
        out.append(f"    {role}: {color(c[role])},")
    out.append(f"    pop: {'true' if v['pop'] else 'false'},")
    out.append(f"    backdrop: '{v['backdrop']}',")
    out.append(f"    hazard: {float(v['hazard'])},")
    out.append(f"    style: '{v['style']}',")
    out.append(f"    radius: {float(v['radius'])},")
    out.append(f"    font: '{v['font']}',")
    out.append(f"    shadow: '{v['shadow']}',")
    out.append("  ),")
out += ["};", ""]
open("lib/ui/hud/skins.g.dart", "w", encoding="utf-8").write("\n".join(out))
print("lib/ui/hud/skins.g.dart:", len(d["skins"]), "skins")
