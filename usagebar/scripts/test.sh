#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc -swift-version 5 -warnings-as-errors \
  Sources/UsageBar/Usage.swift Sources/UsageBar/UsageTime.swift Sources/UsageBar/CodexProvider.swift \
  Sources/UsageBar/ClaudeProvider.swift Sources/UsageBar/AppModel.swift \
  Tests/UsageBarTests/UsageTests.swift Tests/UsageBarTests/ProviderTests.swift \
  Tests/UsageBarTests/ModelTests.swift Tests/UsageBarTests/PublicationTests.swift Tests/UsageBarTests/TimeTests.swift \
  scripts/BundlePublication.swift -o .build/checks/UsageChecks
.build/checks/UsageChecks
