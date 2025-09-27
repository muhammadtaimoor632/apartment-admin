#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Make the script aware of the rbenv environment if you use it.
export PATH="$HOME/.rbenv/shims:$PATH"

# --- Helper Functions for Colored Output ---
color_green() {
  echo -e "\033[0;32m$1\033[0m"
}
color_blue() {
  echo -e "\033[0;34m$1\033[0m"
}
color_yellow() {
  echo -e "\033[0;33m$1\033[0m"
}
color_red() {
  echo -e "\033[0;31m$1\033[0m"
}

# --- ⭐️ CONFIGURATION ⭐️ ---

# Load environment variables from .env file if it exists
if [ -f .env ]; then
  set -a # Automatically export all variables
  source .env
  set +a
fi

# Check for required environment variables from the .env file
if [ -z "$WP_USER" ] || [ -z "$WP_PASSWORD" ] || [ -z "$FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD" ]; then
  color_red "❌ Error: Required secrets are not set in your .env file."
  color_yellow "Please ensure your .env file contains WP_USER, WP_PASSWORD, and FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD."
  exit 1
fi

# Prepare Dart Defines for secure credential passing, with quotes for the password
DART_DEFINES="--dart-define=WP_USER=$WP_USER --dart-define=WP_PASSWORD='$WP_PASSWORD'"

# Your app's core configuration details
APP_NAME="WildAtlanticHub"

# --- Main Build Process ---

# --- Command-line argument parsing for skipping platforms ---
BUILD_IOS=true
BUILD_ANDROID=true

for arg in "$@"; do
  case $arg in
  --skip-ios)
    BUILD_IOS=false
    shift
    ;;
  --skip-android)
    BUILD_ANDROID=false
    shift
    ;;
  *)
    color_yellow "⚠️Warning: Unrecognized argument '$arg' will be ignored."
    shift
    ;;
  esac
done

color_green "🚀 Starting Full build process..."
echo

color_blue "Configuration:"
color_blue "Build iOS: $BUILD_IOS"
color_blue "Build Android: $BUILD_ANDROID"
echo

# 1. Fetch Latest Version and Build Info
color_blue "🔎 Fetching latest version info..."
cd "$(dirname "$0")"

# --- Fetch version directly from pubspec.yaml ---
color_yellow " - Reading version from pubspec.yaml..."
original_full_version_string=$(grep 'version:' pubspec.yaml | cut -d ' ' -f 2)
current_version=$(echo "$original_full_version_string" | cut -d '+' -f 1)

if [ -z "$current_version" ]; then
  color_red "❌ Version not found in pubspec.yaml."
  exit 1
fi

# --- Fetch build numbers from the stores ---
color_yellow " - Fetching latest build numbers from stores..."
latest_ios_build_raw=$( (cd ios && bundle exec fastlane run latest_testflight_build_number version:"$current_version") 2>/dev/null | grep "Result:" | tail -n 1 | awk '{print $NF}' )
latest_ios_build=${latest_ios_build_raw:-0}
color_green "✅ Latest iOS build for version $current_version is: $latest_ios_build"

# --- Check all Android tracks for the true latest version code ---
color_yellow " - Checking all Android tracks for the latest version code..."
get_track_version() {
  # Use a subshell and redirect stderr to /dev/null to hide "Package not found" errors on the first run
  (cd android && bundle exec fastlane run google_play_track_version_codes track:$1 2>/dev/null) | grep "Result:" | tail -n 1 | sed -E 's/.*\[(.*)\].*/\1/' | tr ',' '\n' | sort -nr | head -1
}

prod_version=$(get_track_version "production")
beta_version=$(get_track_version "beta")
alpha_version=$(get_track_version "alpha")
internal_version=$(get_track_version "internal")

# Find the maximum version code from all tracks
latest_android_build_raw=$(printf "%s\n" "${prod_version:-0}" "${beta_version:-0}" "${alpha_version:-0}" "${internal_version:-0}" | sort -nr | head -1)
latest_android_build=${latest_android_build_raw:-0}
color_green "✅ Latest Android build is: $latest_android_build"

# --- Determine the true highest build number ---
clean_ios_build=$(echo "$latest_ios_build" | tr -d -c 0-9)
clean_android_build=$(echo "$latest_android_build" | tr -d -c 0-9)
clean_ios_build=${clean_ios_build:-0}
clean_android_build=${clean_android_build:-0}

if [ "$clean_ios_build" -gt "$clean_android_build" ]; then
  highest_build=$clean_ios_build
else
  highest_build=$clean_android_build
fi
color_blue "➡️Current version is $current_version with highest build number $highest_build."
echo

# --- Pre-calculate next values ---
major=$(echo "$current_version" | cut -d '.' -f 1 | tr -d -c 0-9)
minor=$(echo "$current_version" | cut -d '.' -f 2 | tr -d -c 0-9)
patch=$(echo "$current_version" | cut -d '.' -f 3 | tr -d -c 0-9)
next_patch=$((patch + 1))
next_version_prefix="$major.$minor.$next_patch"
next_build_code=$((highest_build + 1))

# --- Automatically Increment Version and Build ---
color_yellow "➡️Automatically incrementing VERSION and BUILD number..."
new_version_name="$next_version_prefix"
ios_build_number=$((clean_ios_build + 1))
android_build_number=$next_build_code
pubspec_build_number=1
color_blue "⬆️Setting new version to ${new_version_name} (iOS Build: ${ios_build_number}, Android Build: ${android_build_number})"

new_full_version="${new_version_name}+${pubspec_build_number}"

sed -i '' "s/version: $original_full_version_string/version: $new_full_version/" pubspec.yaml
color_green "✅ pubspec.yaml updated to version $new_full_version"
echo

# 2. Clean and get dependencies
color_blue "🧹 Cleaning and fetching dependencies..."
flutter clean
flutter pub get
echo

# --- Load Release Notes from File ---
RELEASE_NOTES_PATH="release_notes/whats_new.txt"
WHATS_NEW_CONTENT=""
if [ -f "$RELEASE_NOTES_PATH" ]; then
  WHATS_NEW_CONTENT=$(cat "$RELEASE_NOTES_PATH")
  color_green "✅ Loaded release notes from $RELEASE_NOTES_PATH"
else
  if [ "$BUILD_IOS" = true ] || [ "$BUILD_ANDROID" = true ]; then
    color_red "❌ Release notes file not found at '$RELEASE_NOTES_PATH'. This is required."
    exit 1
  fi
fi
echo

# --- iOS DEPLOYMENT ---
if [ "$BUILD_IOS" = true ]; then
  color_blue "🚀 Preparing and building iOS App (.ipa)..."
  (cd ios && bundle exec fastlane set_version_and_build version_number:$new_version_name build_number:$ios_build_number)

  # Create an export options plist for the build
  EXPORT_PLIST_PATH="build/ios/exportOptions.plist"
  /usr/libexec/PlistBuddy -c "Add :destination string export" -c "Add :method string app-store" -c "Add :signingStyle string automatic" -c "Add :uploadBitcode bool true" -c "Add :uploadSymbols bool true" "$EXPORT_PLIST_PATH" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :destination export" -c "Set :method app-store" -c "Set :signingStyle automatic" -c "Set :uploadBitcode true" -c "Set :uploadSymbols true" "$EXPORT_PLIST_PATH"

  # Build the ipa with Dart Defines, quoting the variable to handle spaces
  flutter build ipa --release "$DART_DEFINES" --export-options-plist="$EXPORT_PLIST_PATH"

  color_green "✅ iOS build completed."
  echo

  color_blue "⬆️Uploading iOS App to App Store Connect..."
  IPA_PATH="build/ios/ipa/$APP_NAME.ipa"
  # Pass the changelog content to the fastlane command
  (cd ios && bundle exec fastlane app_store_release ipa_path:"../$IPA_PATH" changelog:"$WHATS_NEW_CONTENT")
  color_green "✅ iOS deployment completed."
  echo
fi

# --- ANDROID DEPLOYMENT ---
if [ "$BUILD_ANDROID" = true ]; then
  color_blue "🤖 Building for Android (Release App Bundle)..."

  # NEW: Create the changelog file where fastlane expects it
  CHANGELOG_DIR="android/fastlane/metadata/android/en-US/changelogs"
  mkdir -p "$CHANGELOG_DIR"
  echo "$WHATS_NEW_CONTENT" > "$CHANGELOG_DIR/$android_build_number.txt"
  color_green "✅ Android changelog created for build $android_build_number."

  # Build the appbundle with Dart Defines, quoting the variable
  flutter build appbundle --release "$DART_DEFINES" --build-name=$new_version_name --build-number=$android_build_number
  color_green "✅ Android build completed."
  echo

  color_blue "⬆️Uploading Android App to Google Play..."
  AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
  # Call fastlane without the changelog parameter, as it's now read from the file
  (cd android && bundle exec fastlane release aab_path:"../$AAB_PATH")
  color_green "✅ Android deployment completed."
  echo
fi

color_green "🎉 All requested platforms built and deployed successfully!"

