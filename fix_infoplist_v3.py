import sys, re

path = "NetNewsWire.xcodeproj/project.pbxproj"

with open(path, "r") as f:
    content = f.read()

marker = "ShareExtension/Info.plist,"
target_marker = "target = 513C5CE5232571C2003D4054 /* NetNewsWire iOS Share Extension */;"

# Find the specific occurrence of "ShareExtension/Info.plist," that is followed
# (within the next ~15 lines) by the Share Extension target line, to make sure
# we're editing the right block if the marker string appears more than once.
idx = content.find(marker)
found_idx = None
while idx != -1:
    window = content[idx: idx + 800]
    if target_marker in window:
        found_idx = idx
        break
    idx = content.find(marker, idx + 1)

if found_idx is None:
    print("ERROR: could not locate the ShareExtension/Info.plist line followed by the Share Extension target marker.")
    sys.exit(1)

# Insert the two missing lines right before "ShareExtension/Info.plist,"
# preserving whatever indentation precedes it.
line_start = content.rfind("\n", 0, found_idx) + 1
indent = content[line_start:found_idx]
insertion = f"{indent}IntentsExtension/Info.plist,\n{indent}Resources/Info.plist,\n"

already_has = "IntentsExtension/Info.plist," in content[line_start-500:line_start] 
if "IntentsExtension/Info.plist,\n" + indent in content[max(0,line_start-200):line_start+len(marker)+5]:
    print("Looks like it's already applied nearby — please check manually.")
    sys.exit(1)

new_content = content[:line_start] + insertion + content[line_start:]

with open(path, "w") as f:
    f.write(new_content)

print("Inserted IntentsExtension/Info.plist and Resources/Info.plist before ShareExtension/Info.plist in the Share Extension's exception set.")
