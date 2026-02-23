// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Stable identifiers for critical UX flows.
public enum UXFlowID: String, CaseIterable {
    case launchEmptyState = "ux.launch.empty_state"
    case demoToggle = "ux.demo.toggle"
    case deviceListVisible = "ux.device.list.visible"
    case deviceSelect = "ux.device.select"
    case storageRender = "ux.storage.render"
    case filesRefresh = "ux.files.refresh"
    case errorDiscovery = "ux.error.discovery"
    case detachSelectionReset = "ux.detach.selection_reset"
    case discoveryStateMarker = "ux.discovery.state.marker"
    case selectionPlaceholderVisible = "ux.selection.placeholder.visible"
    case deviceLoadingPhase = "ux.device.loading.phase"
    case detailContainerVisible = "ux.detail.container.visible"
    case filesLoadingPhase = "ux.files.loading.phase"
    case filesEmptyPhase = "ux.files.empty.phase"
    case filesErrorPhase = "ux.files.error.phase"
    case filesOutcomeMarker = "ux.files.outcome.marker"
    case deviceRowRender = "ux.device.row.render"
    case storageRowRender = "ux.storage.row.render"
    case fileRowRender = "ux.file.row.render"
}
