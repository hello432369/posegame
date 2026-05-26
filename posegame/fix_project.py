#!/usr/bin/env python3
"""修改 project.pbxproj，添加 PoseBridge 源文件。仅添加缺失条目，不删除已有内容。"""

import re, os

PBX = os.path.expanduser("~/Documents/xcodeapp/posegame/posegame.xcodeproj/project.pbxproj")

with open(PBX, "r") as f:
    text = f.read()

swift_files = [
    "CameraManager.swift", "CameraPreview.swift",
        "Models.swift", "PoseBridgeApp.swift",
    "PoseDetector.swift", "PoseMatcher.swift",
    "SettingsView.swift", "SkeletonOverlay.swift",
    "UDPSender.swift",
]

base = "5D0A6B"
build_uuids = {}
ref_uuids = {}
for i, sf in enumerate(swift_files):
    build_uuids[sf] = f"{base}{i+1:02X}2FC4406300F86BF0"
    ref_uuids[sf] = f"{base}{i+20:02X}2FC4406300F86BF0"


def insert_after_marker(section_text, marker, new_lines_str):
    """在 marker 之后插入 new_lines_str，marker 保留在原文中"""
    idx = section_text.find(marker)
    if idx == -1:
        return section_text
    end_of_marker = idx + len(marker)
    # 检查是否已经插入过
    if new_lines_str.strip().split('\n')[0] in section_text:
        return section_text
    return section_text[:end_of_marker] + "\n" + new_lines_str + section_text[end_of_marker:]


# ── 1. PBXBuildFile: 仅在 Begin 标记后插入不存在的条目 ──
bf_begin = "/* Begin PBXBuildFile section */"
bf_end = "/* End PBXBuildFile section */"
bf_section_start = text.index(bf_begin)
bf_section_end = text.index(bf_end, bf_section_start)
bf_section = text[bf_section_start:bf_section_end + len(bf_end)]

for sf in swift_files:
    bu = build_uuids[sf]
    entry = f'\t\t{bu} /* {sf} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_uuids[sf]} /* {sf} */; }};'
    if bu not in bf_section:
        bf_section = insert_after_marker(bf_section, bf_begin + "\n", entry + "\n")

text = text[:bf_section_start] + bf_section + text[bf_section_end + len(bf_end):]


# ── 2. PBXFileReference: 仅在 Begin 标记后插入不存在的条目 ──
fr_begin = "/* Begin PBXFileReference section */"
fr_end = "/* End PBXFileReference section */"
fr_section_start = text.index(fr_begin)
fr_section_end = text.index(fr_end, fr_section_start)
fr_section = text[fr_section_start:fr_section_end + len(fr_end)]

for sf in swift_files:
    ru = ref_uuids[sf]
    entry = f'\t\t{ru} /* {sf} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {sf}; sourceTree = "<group>"; }};'
    if ru not in fr_section:
        fr_section = insert_after_marker(fr_section, fr_begin + "\n", entry + "\n")

text = text[:fr_section_start] + fr_section + text[fr_section_end + len(fr_end):]


# ── 3. PBXGroup: 完全替换 posegame group 的 children ──
new_children = []
for sf in swift_files:
    ru = ref_uuids[sf]
    new_children.append(f'\t\t\t\t{ru} /* {sf} */,')
new_children.append('\t\t\t\t5D0A69ED2FC4406300F86BAF /* ContentView.swift */,')
new_children.append('\t\t\t\t5D0A69EF2FC4406600F86BAF /* Assets.xcassets */,')
new_children.append('\t\t\t\t5D0A69F12FC4406600F86BAF /* Preview Content */,')

group_pat = (
    re.escape('\t\t5D0A69EA2FC4406300F86BAF /* posegame */ = {\n'
              '\t\t\tisa = PBXGroup;\n'
              '\t\t\tchildren = (\n')
    + r'.*?'
    + re.escape('\t\t\t);\n'
                '\t\t\tpath = posegame;\n'
                '\t\t\tsourceTree = "<group>";\n'
                '\t\t};')
)
new_group = (
    '\t\t5D0A69EA2FC4406300F86BAF /* posegame */ = {\n'
    '\t\t\tisa = PBXGroup;\n'
    '\t\t\tchildren = (\n'
    + '\n'.join(new_children) + '\n'
    '\t\t\t);\n'
    '\t\t\tpath = posegame;\n'
    '\t\t\tsourceTree = "<group>";\n'
    '\t\t};'
)
text = re.sub(group_pat, new_group, text, flags=re.DOTALL)


# ── 4. PBXSourcesBuildPhase: 完全替换 posegame 的 files ──
source_files = []
for sf in swift_files:
    bu = build_uuids[sf]
    source_files.append(f'\t\t\t\t{bu} /* {sf} in Sources */,')
source_files.append('\t\t\t\t5D0A69EE2FC4406300F86BAF /* ContentView.swift in Sources */,')

sources_pat = (
    re.escape('\t\t5D0A69E42FC4406300F86BAF /* Sources */ = {\n'
              '\t\t\tisa = PBXSourcesBuildPhase;\n'
              '\t\t\tbuildActionMask = 2147483647;\n'
              '\t\t\tfiles = (\n')
    + r'.*?'
    + re.escape('\t\t\t);\n'
                '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
                '\t\t};')
)
new_sources = (
    '\t\t5D0A69E42FC4406300F86BAF /* Sources */ = {\n'
    '\t\t\tisa = PBXSourcesBuildPhase;\n'
    '\t\t\tbuildActionMask = 2147483647;\n'
    '\t\t\tfiles = (\n'
    + '\n'.join(source_files) + '\n'
    '\t\t\t);\n'
    '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
    '\t\t};'
)
text = re.sub(sources_pat, new_sources, text, flags=re.DOTALL)


# ── 5. Info.plist permissions (只添加缺失的) ──
if "NSCameraUsageDescription" not in text:
    old_perms = (
        '\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
        '\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;'
    )
    new_perms = (
        '\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
        '\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "PoseBridge uses camera for body pose recognition to control games";\n'
        '\t\t\t\tINFOPLIST_KEY_NSLocalNetworkUsageDescription = "PoseBridge needs local network to send pose data to your computer";\n'
        '\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;'
    )
    text = text.replace(old_perms, new_perms)


with open(PBX, "w") as f:
    f.write(text)

print("Done! Project file updated successfully.")
