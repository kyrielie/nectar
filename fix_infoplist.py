import sys, re

path = "NetNewsWire.xcodeproj/project.pbxproj"

with open(path, "r") as f:
    content = f.read()

changes = 0

# Share Extension exception set: add ShareExtension/Info.plist
old_share = "\t\t\t\t/Localized/ShareExtension/MainInterface.storyboard,\n\t\t\t\tAppDefaults.swift,\n\t\t\t\tResources/Assets.xcassets,\n\t\t\t\tShareExtension/ShareFolderPickerAccountCell.xib,"
new_share = "\t\t\t\t/Localized/ShareExtension/MainInterface.storyboard,\n\t\t\t\tAppDefaults.swift,\n\t\t\t\tResources/Assets.xcassets,\n\t\t\t\tShareExtension/Info.plist,\n\t\t\t\tShareExtension/ShareFolderPickerAccountCell.xib,"
if old_share in content:
    content = content.replace(old_share, new_share, 1)
    changes += 1
else:
    print("WARNING: Share Extension anchor not found")

# Intents Extension exception set: add IntentsExtension/Info.plist
old_intents = "\t\t\tmembershipExceptions = (\n\t\t\t\tIntentsExtension/IntentHandler.swift,\n\t\t\t);\n\t\t\ttarget = 51314636235A7BBE00387FDC /* NetNewsWire iOS Intents Extension */;"
new_intents = "\t\t\tmembershipExceptions = (\n\t\t\t\tIntentsExtension/Info.plist,\n\t\t\t\tIntentsExtension/IntentHandler.swift,\n\t\t\t);\n\t\t\ttarget = 51314636235A7BBE00387FDC /* NetNewsWire iOS Intents Extension */;"
if old_intents in content:
    content = content.replace(old_intents, new_intents, 1)
    changes += 1
else:
    print("WARNING: Intents Extension anchor not found")

if changes == 2:
    with open(path, "w") as f:
        f.write(content)
    print("Applied both fixes successfully.")
elif changes == 1:
    print("Only one fix applied — check the warning above and inspect manually.")
    sys.exit(1)
else:
    print("No fixes applied — anchors not found. File may differ from expected structure.")
    sys.exit(1)
