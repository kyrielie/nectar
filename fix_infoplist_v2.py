import sys

path = "NetNewsWire.xcodeproj/project.pbxproj"

with open(path, "r") as f:
    content = f.read()

changes = 0

# Share Extension: also exclude IntentsExtension/Info.plist and Resources/Info.plist
old_share = "\t\t\t\tShareExtension/Info.plist,\n\t\t\t\tShareExtension/ShareFolderPickerAccountCell.xib,"
new_share = "\t\t\t\tIntentsExtension/Info.plist,\n\t\t\t\tResources/Info.plist,\n\t\t\t\tShareExtension/Info.plist,\n\t\t\t\tShareExtension/ShareFolderPickerAccountCell.xib,"
if old_share in content:
    content = content.replace(old_share, new_share, 1)
    changes += 1
else:
    print("WARNING: Share Extension anchor not found (already patched, or v1 fix not applied yet)")

# Intents Extension: also exclude ShareExtension/Info.plist and Resources/Info.plist
old_intents = "\t\t\t\tIntentsExtension/Info.plist,\n\t\t\t\tIntentsExtension/IntentHandler.swift,\n\t\t\t);\n\t\t\ttarget = 51314636235A7BBE00387FDC /* NetNewsWire iOS Intents Extension */;"
new_intents = "\t\t\t\tIntentsExtension/Info.plist,\n\t\t\t\tIntentsExtension/IntentHandler.swift,\n\t\t\t\tResources/Info.plist,\n\t\t\t\tShareExtension/Info.plist,\n\t\t\t);\n\t\t\ttarget = 51314636235A7BBE00387FDC /* NetNewsWire iOS Intents Extension */;"
if old_intents in content:
    content = content.replace(old_intents, new_intents, 1)
    changes += 1
else:
    print("WARNING: Intents Extension anchor not found (already patched, or v1 fix not applied yet)")

if changes == 2:
    with open(path, "w") as f:
        f.write(content)
    print("Applied both v2 fixes successfully.")
else:
    print(f"Only {changes}/2 fixes applied. Inspect the warnings above.")
    sys.exit(1)
