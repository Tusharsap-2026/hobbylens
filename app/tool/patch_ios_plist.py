"""Adds the iOS permission explanations (camera, photos, location) to ios/Runner/Info.plist."""
import os, plistlib, sys

path = os.path.join(os.path.dirname(__file__), "..", "ios", "Runner", "Info.plist")
if not os.path.exists(path):
    sys.exit(0)
with open(path, "rb") as f:
    plist = plistlib.load(f)
plist.update({
    "NSCameraUsageDescription": "HobbyLens uses the camera to photograph a plant or pet you want to identify.",
    "NSPhotoLibraryUsageDescription": "HobbyLens lets you choose a photo of a plant or pet to identify.",
    "NSLocationWhenInUseUsageDescription": "HobbyLens uses your location only while you search for nearby shops. It is not stored.",
    "CFBundleLocalizations": ["bn", "en"],
})
with open(path, "wb") as f:
    plistlib.dump(plist, f)
print("Info.plist updated")
