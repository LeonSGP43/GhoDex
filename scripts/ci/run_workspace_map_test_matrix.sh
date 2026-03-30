#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/macos/GhoDex.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/macos/build/DerivedData}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Debug}"
SCHEME="${SCHEME:-GhoDex}"
DESTINATION="${DESTINATION:-platform=macOS}"

TEST_BUNDLE_PATH="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/GhoDex.app/Contents/PlugIns/GhosttyTests.xctest"
FRAMEWORKS_PATH="$TEST_BUNDLE_PATH/Contents/Frameworks"

build_for_testing() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$BUILD_CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build-for-testing
}

wire_test_bundle_rpaths() {
  mkdir -p "$FRAMEWORKS_PATH"
  ln -sf ../../../../MacOS/GhoDex.debug.dylib "$FRAMEWORKS_PATH/GhoDex.debug.dylib"

  local item
  for item in \
    Sparkle.framework \
    Testing.framework \
    XCTest.framework \
    XCTestCore.framework \
    XCTestSupport.framework \
    XCTAutomationSupport.framework \
    XCUIAutomation.framework \
    XCUnit.framework \
    libXCTestSwiftSupport.dylib \
    libXCTestBundleInject.dylib; do
    ln -sf "../../../../Frameworks/$item" "$FRAMEWORKS_PATH/$item"
  done
}

run_matrix() {
  local -a classes=(
    NewTabPickerWorkspaceMapTests
    WorkspaceMapContractsTests
    WorkspaceMapProjectionFixtureTests
    WorkspaceMapProjectionBoundaryTests
    WorkspaceMapCommandGatewayTests
    WorkspaceMapViewModelDeterminismTests
    WorkspaceMapPerformanceRegressionTests
    WorkspaceMapPerformancePolicyTests
    WorkspaceMapCanvasInputPolicyTests
    WorkspaceMapLiveCanvasViewVisibilityTests
    WorkspaceMapLiveCanvasContentProviderTests
  )

  local class_name
  for class_name in "${classes[@]}"; do
    xcrun xctest -XCTest "$class_name" "$TEST_BUNDLE_PATH"
  done
}

build_for_testing

if [[ ! -d "$TEST_BUNDLE_PATH" ]]; then
  echo "Workspace Map test bundle not found at: $TEST_BUNDLE_PATH"
  exit 1
fi

wire_test_bundle_rpaths
run_matrix
