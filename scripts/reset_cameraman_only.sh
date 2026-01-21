#!/bin/bash

# reset_cameraman_only.sh - Reset ONLY Cameraman permissions (safe version)

set -e

echo "🧹 Reseteando SOLO permisos de Cameraman..."

BUNDLE_IDS=(
    "com.cameraman.app"
    "com.apple.dt.Xcode"
    "org.swift.cameraman"
)

for bundle_id in "${BUNDLE_IDS[@]}"; do
    echo "  ↪️  Reseteando: $bundle_id"
    tccutil reset ScreenCapture "$bundle_id" 2>/dev/null || echo "     (no encontrado)"
done

echo ""
echo "✅ Solo Cameraman/Xcode reseteado."
echo "ℹ️  Otras apps no afectadas."
