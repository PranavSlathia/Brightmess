#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 -parse-as-library \
  "$ROOT/repos/TrueTone/Sources/TrueTone/WhitePointModel.swift" \
  "$ROOT/repos/TrueTone/Sources/TrueTone/PanelProfile.swift" \
  "$ROOT/repos/TrueTone/Sources/TrueTone/BrightnessMap.swift" \
  "$ROOT/repos/LuxCurve/LuxCurve/Model/CalibrationNode.swift" \
  "$ROOT/repos/LuxCurve/LuxCurve/Engine/CurveEngine.swift" \
  "$ROOT/repos/LuxCurve/LuxCurve/Engine/MedianWindow.swift" \
  "$ROOT/ColorMathAssessment.swift" \
  -o "$ROOT/build/color-math-assessment"
"$ROOT/build/color-math-assessment"
