#!/usr/bin/env bash
# Generates the standard Flutter platform files (Gradle wrapper, iOS project, launcher icons)
# around the files committed in this repository. Existing files are never overwritten, so the
# customised android/app/build.gradle.kts and AndroidManifest.xml are kept.
# Run once after cloning, from the app/ directory.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --platforms=android,ios --org com.hobbylens --project-name hobbylens --no-pub .
# flutter create adds a sample widget_test.dart (for a counter app that does not exist here).
rm -f test/widget_test.dart
python3 tool/patch_ios_plist.py
# Google ML Kit needs iOS 15.5 or later.
if [ -f ios/Podfile ]; then
  sed -i.bak -E "s/^#? *platform :ios, '[0-9.]+'/platform :ios, '15.5'/" ios/Podfile && rm -f ios/Podfile.bak
fi
if [ -f ios/Runner.xcodeproj/project.pbxproj ]; then
  sed -i.bak -E 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.5;/' ios/Runner.xcodeproj/project.pbxproj
  rm -f ios/Runner.xcodeproj/project.pbxproj.bak
fi
