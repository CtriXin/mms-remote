// FILE: SidebarView.swift
// Purpose: Orchestrates the sidebar experience with modular presentation components.
// Layer: View
// Exports: SidebarView
// Depends on: CodexService, Sidebar* components/helpers

import SwiftUI

struct SidebarView: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedThread: CodexThread?
    @Binding var showSettings: Bool
    @Binding var isSearchActive: Bool
    var showsInlineCloseButton: Bool = false
    var isVisible: Bool = true
    var usesSheetChrome: Bool = false

    let onClose: () -> Void
    let onNewChatCreationStateChange: (Bool) -> Void
    let onOpenThread: (CodexThread) -> Void

    @State private var searchText = ""
    @State private var isCreatingThread = false
    @State private var isThreadSelectionMode = false
    @State private var selectedThreadIDs: Set<String> = []
    @State private var bulkArchivePendingThreadIDs: Set<String>? = nil
    @State private var bulkDeletePendingThreadIDs: Set<String>? = nil
    @State private var groupedThreads: [SidebarThreadGroup] = []
    @State private var activeSidebarSheet: SidebarPresentedSheet?
    @State private var projectGroupPendingArchive: SidebarThreadGroup? = nil
    @State private var projectGroupPendingDeletion: SidebarThreadGroup? = nil
    @State private var archivedGroupPendingDeletion: SidebarThreadGroup? = nil
    @State private var threadPendingDeletion: CodexThread? = nil
    @State private var createThreadErrorMessage: String? = nil
    @State private var cachedDiffTotals: [String: TurnSessionDiffTotals] = [:]
    @State private var cachedDiffRevisionByThreadID: [String: Int] = [:]
    @State private var cachedRunBadges: [String: CodexThreadRunBadgeState] = [:]
    @State private var lastGroupedThreadsFingerprint: Int = 0
    @State private var lastDiffFingerprint: Int = 0
    @State private var lastBadgeFingerprint: Int = 0

    var body: some View {
        sidebarChrome
            .sidebarLifecycle(
                isVisible: isVisible,
                threads: codex.threads,
                searchText: searchText,
                pinnedThreadIDs: codex.pinnedThreadIDs,
                diffFingerprint: diffFingerprint,
                badgeFingerprint: badgeFingerprint,
                onTask: handleSidebarTask,
                onThreadsChanged: handleThreadsChanged,
                onSearchTextChanged: handleSearchTextChanged,
                onPinnedThreadIDsChanged: handlePinnedThreadIDsChanged,
                onDiffFingerprintChanged: handleDiffFingerprintChanged,
                onBadgeFingerprintChanged: handleBadgeFingerprintChanged,
                onVisibilityChanged: handleVisibilityChanged
            )
            .sidebarArchiveDialogs(
                projectGroupPendingArchive: $projectGroupPendingArchive,
                bulkArchivePendingThreadIDs: $bulkArchivePendingThreadIDs,
                onArchiveProjectGroup: archivePendingProjectGroup,
                onArchiveSelectedThreads: archivePendingSelectedThreads
            )
            .sidebarDeletionDialogs(
                projectGroupPendingDeletion: $projectGroupPendingDeletion,
                bulkDeletePendingThreadIDs: $bulkDeletePendingThreadIDs,
                archivedGroupPendingDeletion: $archivedGroupPendingDeletion,
                threadPendingDeletion: $threadPendingDeletion,
                onDeleteProjectGroup: deletePendingProjectGroupLocally,
                onDeleteSelectedThreads: deletePendingSelectedThreadsLocally,
                onDeleteArchivedChats: deletePendingArchivedChatsLocally,
                onDeleteThread: deletePendingThreadLocally
            )
            .sidebarErrorAlert(createThreadErrorMessage: $createThreadErrorMessage)
    }

    private var sidebarChrome: some View {
        sidebarContent
            .frame(maxHeight: .infinity)
            .background {
                if usesSheetChrome {
                    ZStack {
                        Rectangle().fill(Color(.secondarySystemGroupedBackground))
                        LinearGradient(
                            colors: [
                                codexSheetAccent.opacity(colorScheme == .dark ? 0.14 : 0.10),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                } else {
                    Color(.systemBackground)
                }
            }
            .overlay {
                sidebarLoadingOverlay
            }
            .sheet(item: $activeSidebarSheet) { sheet in
                sidebarSheetContent(sheet)
            }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if usesSheetChrome {
            sheetSidebarContent
        } else {
            standardSidebarContent
        }
    }

    private var standardSidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            sidebarSearchField
            sidebarNewChatButton
            sidebarInlineLoadingStatus
            sidebarThreadList
            sidebarSelectionActions
            sidebarFooter
        }
    }

    private var sheetSidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarSheetHeader
            Divider().overlay(Color.primary.opacity(0.10))
            sidebarSearchField
            sidebarSheetActionRow
            sidebarInlineLoadingStatus
            sidebarThreadList
            sidebarSelectionActions
            sidebarFooter
        }
    }

    private var codexSheetAccent: Color {
        Color(red: 0.31, green: 0.58, blue: 1.00)
    }

    private var sidebarHeader: some View {
        SidebarHeaderView(
            showsCloseButton: showsInlineCloseButton,
            showsSelectionButton: hasVisibleSelectableThreads || isThreadSelectionMode,
            isSelectionMode: isThreadSelectionMode,
            closeButtonSystemImage: usesSheetChrome ? "xmark" : nil,
            onClose: onClose,
            onSelectionModeToggle: toggleThreadSelectionMode
        )
    }

    private var sidebarSheetHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(codexSheetAccent.opacity(0.22), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(localized: "sidebar.title")
                    .font(AppFont.title3(weight: .semibold))
                    .lineLimit(1)
                Text(String(format: LocalizationManager.shared.localized("sidebar.count"), codex.threads.count))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if showsInlineCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizationManager.shared.localized("sidebar.close_menu"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, usesSheetChrome ? 30 : 18)
        .padding(.bottom, 14)
    }

    private var sidebarSearchField: some View {
        SidebarSearchField(
            text: $searchText,
            isActive: $isSearchActive,
            style: usesSheetChrome ? .sheet : .standard
        )
        .padding(.horizontal, usesSheetChrome ? 18 : 16)
        .padding(.top, usesSheetChrome ? 12 : 8)
        .padding(.bottom, usesSheetChrome ? 8 : 6)
    }

    private var sidebarNewChatButton: some View {
        SidebarNewChatButton(
            isCreatingThread: isCreatingThread,
            isEnabled: canCreateThread,
            statusMessage: nil,
            action: handleNewChatButtonTap
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var sidebarSheetActionRow: some View {
        HStack(spacing: 10) {
            Button(action: handleNewChatButtonTap) {
                HStack(spacing: 8) {
                    if isCreatingThread {
                        ProgressView()
                            .tint(.primary)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(localized: "sidebar.new_chat")
                }
                .font(AppFont.caption(weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .disabled(!canCreateThread || isCreatingThread)

            if hasVisibleSelectableThreads || isThreadSelectionMode {
                Button(action: toggleThreadSelectionMode) {
                    Label(
                        LocalizationManager.shared.localized(isThreadSelectionMode ? "sidebar.done" : "sidebar.select"),
                        systemImage: isThreadSelectionMode ? "checkmark" : "checkmark.circle"
                    )
                    .font(AppFont.caption(weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                }
            }
        }
        .buttonStyle(.bordered)
        .tint(codexSheetAccent)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var sidebarInlineLoadingStatus: some View {
        if SidebarThreadsLoadingPresentation.shouldShowInlineStatus(
            isLoadingThreads: codex.isLoadingThreads,
            threadCount: codex.threads.count
        ) {
            SidebarThreadsInlineLoadingView()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.opacity)
        }
    }

    private var sidebarThreadList: some View {
        SidebarThreadListView(
            isFiltering: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isConnected: codex.isConnected,
            isCreatingThread: isCreatingThread,
            threads: codex.threads,
            groups: groupedThreads,
            selectedThread: selectedThread,
            bottomContentInset: 0,
            timingLabelProvider: { SidebarRelativeTimeFormatter.compactLabel(for: $0) },
            diffTotalsByThreadID: cachedDiffTotals,
            runBadgeStateByThreadID: cachedRunBadges,
            isSelectionMode: isThreadSelectionMode,
            selectedThreadIDs: selectedThreadIDs,
            onSelectThread: selectThread,
            onToggleThreadSelection: toggleThreadSelection,
            onCreateThreadInProjectGroup: { group in
                handleNewChatTap(preferredProjectPath: group.projectPath)
            },
            onArchiveProjectGroup: { group in
                projectGroupPendingArchive = group
            },
            onDeleteProjectGroup: { group in
                projectGroupPendingDeletion = group
            },
            onDeleteArchivedGroup: { group in
                archivedGroupPendingDeletion = group
            },
            onRenameThread: { thread, newName in
                codex.renameThread(thread.id, name: newName)
            },
            onPinToggleThread: { thread in
                if codex.isThreadPinned(thread.id) {
                    codex.unpinThread(thread.id)
                } else {
                    codex.pinThread(thread.id)
                }
                rebuildGroupedThreads()
            },
            onArchiveToggleThread: { thread in
                if thread.syncState == .archivedLocal {
                    codex.unarchiveThread(thread.id)
                } else {
                    codex.archiveThread(thread.id)
                    if selectedThread?.id == thread.id {
                        selectedThread = nil
                    }
                }
            },
            onDeleteThread: { thread in
                threadPendingDeletion = thread
            }
        )
        .refreshable {
            await refreshThreads()
        }
    }

    @ViewBuilder
    private var sidebarSelectionActions: some View {
        if isThreadSelectionMode {
            sidebarBulkActionBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            SidebarFloatingSettingsButton(colorScheme: colorScheme, action: openSettings)
            Spacer(minLength: 0)
            if let trustedPairPresentation = codex.trustedPairPresentation {
                SidebarComputerConnectionStatusView(
                    name: trustedPairPresentation.name,
                    systemName: trustedPairPresentation.systemName,
                    isConnected: codex.isConnected
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, usesSheetChrome ? 18 : 14)
    }

    @ViewBuilder
    private var sidebarLoadingOverlay: some View {
        if SidebarThreadsLoadingPresentation.shouldShowOverlay(
            isLoadingThreads: codex.isLoadingThreads,
            threadCount: codex.threads.count
        ) {
            ProgressView()
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var hasVisibleSelectableThreads: Bool {
        groupedThreads.contains { !$0.threads.isEmpty }
    }

    private var selectedLiveThreadIDs: [String] {
        codex.threads
            .filter { selectedThreadIDs.contains($0.id) && $0.syncState != .archivedLocal }
            .map(\.id)
    }

    private var sidebarBulkActionBar: some View {
        HStack(spacing: 8) {
            Text(
                String(
                    format: LocalizationManager.shared.localized("sidebar.selected_count"),
                    selectedThreadIDs.count
                )
            )
            .font(AppFont.footnote(weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                let liveThreadIDs = Set(selectedLiveThreadIDs)
                guard !liveThreadIDs.isEmpty else { return }
                bulkArchivePendingThreadIDs = liveThreadIDs
            } label: {
                Label(LocalizationManager.shared.localized("sidebar.archive_selected"), systemImage: "archivebox")
            }
            .buttonStyle(.bordered)
            .disabled(selectedLiveThreadIDs.isEmpty)

            Button(role: .destructive) {
                guard !selectedThreadIDs.isEmpty else { return }
                bulkDeletePendingThreadIDs = selectedThreadIDs
            } label: {
                Label(LocalizationManager.shared.localized("sidebar.delete_selected"), systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(selectedThreadIDs.isEmpty)
        }
        .font(AppFont.caption(weight: .semibold))
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Actions

    private func handleSidebarTask() async {
        debugSidebarLog("task start visible=\(isVisible) threadCount=\(codex.threads.count)")
        rebuildGroupedThreads()
        rebuildCachedSidebarState()
        if codex.isConnected, codex.threads.isEmpty {
            await refreshThreads()
        }
    }

    private func handleThreadsChanged() {
        debugSidebarLog(
            "threads changed while \(isVisible ? "visible" : "hidden-prewarmed") "
                + "threadCount=\(codex.threads.count)"
        )
        rebuildGroupedThreads()
        rebuildCachedSidebarState()
        pruneSelectedThreads()
    }

    private func handleSearchTextChanged() {
        debugSidebarLog("search changed queryLength=\(searchText.count)")
        rebuildGroupedThreads()
    }

    private func handlePinnedThreadIDsChanged() {
        debugSidebarLog("pinned threads changed count=\(codex.pinnedThreadIDs.count)")
        rebuildGroupedThreads()
    }

    private func handleDiffFingerprintChanged() {
        debugSidebarLog("diff fingerprint changed visible=\(isVisible)")
        rebuildCachedDiffTotals()
    }

    private func handleBadgeFingerprintChanged() {
        debugSidebarLog("badge fingerprint changed visible=\(isVisible)")
        rebuildCachedRunBadges()
    }

    private func handleVisibilityChanged(_ visible: Bool) {
        debugSidebarLog("visibility changed visible=\(visible)")
    }

    private func refreshThreads() async {
        guard codex.isConnected else { return }
        let startedAt = Date()
        debugSidebarLog("refreshThreads start threadCount=\(codex.threads.count)")
        do {
            try await codex.listThreads()
            debugSidebarLog(
                "refreshThreads success durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) "
                    + "threadCount=\(codex.threads.count)"
            )
        } catch {
            debugSidebarLog(
                "refreshThreads failed durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) "
                    + "error=\(error.localizedDescription)"
            )
            // Error stored in CodexService.
        }
    }

    // Shows a native sheet so folder names and full paths stay readable on small screens.
    private func handleNewChatButtonTap() {
        activeSidebarSheet = .newChatProjectPicker
    }

    private func presentLocalFolderBrowser() {
        activeSidebarSheet = .localFolderBrowser
    }

    private func handleNewChatTap(preferredProjectPath: String?) {
        createThreadErrorMessage = nil
        isCreatingThread = true
        onNewChatCreationStateChange(true)
        prepareSidebarForChatNavigation()
        Task { @MainActor in
            defer {
                isCreatingThread = false
                onNewChatCreationStateChange(false)
            }

            do {
                let thread = try await WorktreeFlowCoordinator.startNewLocalChat(
                    preferredProjectPath: preferredProjectPath,
                    codex: codex
                )
                onOpenThread(thread)
            } catch {
                guard let message = codex.userFacingTurnErrorMessageForFooter(from: error) else { return }
                codex.lastErrorMessage = message
                createThreadErrorMessage = message.isEmpty ? "Unable to create a chat right now." : message
            }
        }
    }

    private func handleNewWorktreeChatTap(preferredProjectPath: String) {
        createThreadErrorMessage = nil
        isCreatingThread = true
        onNewChatCreationStateChange(true)
        prepareSidebarForChatNavigation()
        Task { @MainActor in
            defer {
                isCreatingThread = false
                onNewChatCreationStateChange(false)
            }

            do {
                let thread = try await WorktreeFlowCoordinator.startNewWorktreeChat(
                    preferredProjectPath: preferredProjectPath,
                    codex: codex
                )
                onOpenThread(thread)
            } catch {
                guard let message = codex.userFacingTurnErrorMessageForFooter(from: error) else { return }
                codex.lastErrorMessage = message
                createThreadErrorMessage = message.isEmpty ? "Unable to create a worktree chat right now." : message
            }
        }
    }

    private func selectThread(_ thread: CodexThread) {
        debugSidebarLog("selectThread id=\(thread.id) title=\(thread.displayTitle)")
        prepareSidebarForChatNavigation()
        onOpenThread(thread)
    }

    private func openSettings() {
        searchText = ""
        isSearchActive = false
        endThreadSelection()
        showSettings = true
        onClose()
    }

    // Clears sidebar-only input state before navigation so full-width search mode cannot hold the drawer open.
    private func prepareSidebarForChatNavigation() {
        searchText = ""
        isSearchActive = false
        endThreadSelection()
        onClose()
    }

    private func toggleThreadSelectionMode() {
        if isThreadSelectionMode {
            endThreadSelection()
        } else {
            isThreadSelectionMode = true
        }
    }

    private func toggleThreadSelection(_ thread: CodexThread) {
        if !isThreadSelectionMode {
            isThreadSelectionMode = true
        }

        if selectedThreadIDs.contains(thread.id) {
            selectedThreadIDs.remove(thread.id)
        } else {
            selectedThreadIDs.insert(thread.id)
        }
    }

    private func endThreadSelection() {
        isThreadSelectionMode = false
        selectedThreadIDs.removeAll()
        bulkArchivePendingThreadIDs = nil
        bulkDeletePendingThreadIDs = nil
    }

    private func pruneSelectedThreads() {
        guard !selectedThreadIDs.isEmpty else { return }
        let existingThreadIDs = Set(codex.threads.map(\.id))
        selectedThreadIDs = selectedThreadIDs.intersection(existingThreadIDs)
        if isThreadSelectionMode, selectedThreadIDs.isEmpty, !hasVisibleSelectableThreads {
            endThreadSelection()
        }
    }

    private func archivePendingSelectedThreads() {
        guard let pendingThreadIDs = bulkArchivePendingThreadIDs, !pendingThreadIDs.isEmpty else {
            bulkArchivePendingThreadIDs = nil
            return
        }

        let affectedThreadIDs = affectedThreadIDsForSubtreeOperation(Array(pendingThreadIDs))
        _ = codex.archiveThreadGroup(threadIDs: Array(pendingThreadIDs))

        if let selectedThread, affectedThreadIDs.contains(selectedThread.id) {
            self.selectedThread = codex.threads.first { thread in
                thread.syncState == .live && !affectedThreadIDs.contains(thread.id)
            }
        }

        endThreadSelection()
    }

    private func deletePendingSelectedThreadsLocally() {
        guard let pendingThreadIDs = bulkDeletePendingThreadIDs, !pendingThreadIDs.isEmpty else {
            bulkDeletePendingThreadIDs = nil
            return
        }

        let affectedThreadIDs = affectedThreadIDsForSubtreeOperation(Array(pendingThreadIDs))
        _ = codex.deleteLocalThreadGroup(threadIDs: Array(pendingThreadIDs))

        if let selectedThread, affectedThreadIDs.contains(selectedThread.id) {
            self.selectedThread = codex.threads.first { thread in
                thread.syncState == .live && !affectedThreadIDs.contains(thread.id)
            }
        }

        endThreadSelection()
    }

    private func affectedThreadIDsForSubtreeOperation(_ rootIDs: [String]) -> Set<String> {
        let rootIDSet = Set(rootIDs)
        let childrenByParentID = codex.threads.reduce(into: [String: [String]]()) { partialResult, thread in
            guard let parentThreadID = thread.parentThreadId else { return }
            partialResult[parentThreadID, default: []].append(thread.id)
        }

        var affectedThreadIDs: Set<String> = []
        var queue = Array(rootIDSet)
        while let currentID = queue.popLast() {
            guard affectedThreadIDs.insert(currentID).inserted else { continue }
            queue.append(contentsOf: childrenByParentID[currentID] ?? [])
        }
        return affectedThreadIDs
    }

    // Archives every live chat in the selected project group and clears the current selection if needed.
    private func archivePendingProjectGroup() {
        guard let group = projectGroupPendingArchive else { return }

        let threadIDs = SidebarThreadGrouping.liveThreadIDsForProjectGroup(group, in: codex.threads)
        let selectedThreadWasArchived = selectedThread.map { selected in
            threadIDs.contains(selected.id)
        } ?? false

        _ = codex.archiveThreadGroup(threadIDs: threadIDs)

        if selectedThreadWasArchived {
            selectedThread = codex.threads.first(where: { thread in
                thread.syncState == .live && !threadIDs.contains(thread.id)
            })
        }

        projectGroupPendingArchive = nil
    }

    // Removes every local chat for the selected project while leaving the desktop runtime untouched.
    private func deletePendingProjectGroupLocally() {
        guard let group = projectGroupPendingDeletion else { return }

        let threadIDs = SidebarThreadGrouping.allThreadIDsForProjectGroup(group, in: codex.threads)
        let selectedThreadWasDeleted = selectedThread.map { selected in
            threadIDs.contains(selected.id)
        } ?? false

        _ = codex.deleteLocalThreadGroup(threadIDs: threadIDs)

        if selectedThreadWasDeleted {
            selectedThread = codex.threads.first { thread in
                thread.syncState == .live && !threadIDs.contains(thread.id)
            }
        }

        projectGroupPendingDeletion = nil
    }

    // Removes the selected archived local chats from this phone while leaving Codex on the Mac untouched.
    private func deletePendingArchivedChatsLocally() {
        let pendingThreadIDs = Set(archivedGroupPendingDeletion?.threads.map(\.id) ?? [])
        let removedThreadIDs = Set(codex.deleteArchivedThreadsLocally(threadIDs: Array(pendingThreadIDs)))
        let affectedThreadIDs = removedThreadIDs.isEmpty ? pendingThreadIDs : removedThreadIDs

        if let selectedThread, affectedThreadIDs.contains(selectedThread.id) {
            self.selectedThread = codex.threads.first { thread in
                thread.syncState == .live && !affectedThreadIDs.contains(thread.id)
            }
        }

        archivedGroupPendingDeletion = nil
    }

    private func deletePendingThreadLocally() {
        if let thread = threadPendingDeletion {
            if selectedThread?.id == thread.id {
                selectedThread = nil
            }
            codex.deleteThreadLocally(thread.id)
        }
        threadPendingDeletion = nil
    }

    // Rebuilds sidebar sections only when the source thread array changes.
    private func rebuildGroupedThreads() {
        let startedAt = Date()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: [CodexThread]
        if query.isEmpty {
            source = codex.threads
        } else {
            source = codex.threads.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
                || ($0.preview?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.projectDisplayName.localizedCaseInsensitiveContains(query)
                || ($0.normalizedProjectPath?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        let fingerprint = groupingFingerprint(query: query, source: source)
        guard fingerprint != lastGroupedThreadsFingerprint else { return }
        lastGroupedThreadsFingerprint = fingerprint
        groupedThreads = SidebarThreadGrouping.makeGroups(from: source, pinnedThreadIDs: codex.pinnedThreadIDs)
        debugSidebarLog(
            "rebuildGroupedThreads durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) "
                + "queryLength=\(query.count) sourceCount=\(source.count) groupCount=\(groupedThreads.count)"
        )
    }

    private func groupingFingerprint(query: String, source: [CodexThread]) -> Int {
        var hasher = Hasher()
        hasher.combine(query)
        hasher.combine(codex.pinnedThreadIDs)
        for thread in source {
            hasher.combine(thread)
        }
        return hasher.finalize()
    }

    // Cheap fingerprint: hashes thread IDs + message revisions (O(n) integer work, no message access).
    private var diffFingerprint: Int {
        var hasher = Hasher()
        let hasRunningTurn = codex.hasAnyRunningTurn
        hasher.combine(hasRunningTurn)
        guard !hasRunningTurn else {
            return hasher.finalize()
        }
        for thread in codex.threads {
            hasher.combine(thread.id)
            hasher.combine(codex.messageRevision(for: thread.id))
        }
        return hasher.finalize()
    }

    // Cheap fingerprint for run badge state — changes when running/ready/failed sets change.
    private var badgeFingerprint: Int {
        var hasher = Hasher()
        for thread in codex.threads {
            hasher.combine(thread.id)
            if let badge = codex.threadRunBadgeState(for: thread.id) {
                hasher.combine(badge)
            }
        }
        return hasher.finalize()
    }

    private func rebuildCachedSidebarState() {
        let startedAt = Date()
        rebuildCachedDiffTotals()
        rebuildCachedRunBadges()
        debugSidebarLog(
            "rebuildCachedSidebarState durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) "
                + "diffTotals=\(cachedDiffTotals.count) runBadges=\(cachedRunBadges.count)"
        )
    }

    private func rebuildCachedDiffTotals() {
        let fp = diffFingerprint
        guard fp != lastDiffFingerprint else { return }
        // Keep streaming smooth: diff totals are sidebar-only and can wait until active runs settle.
        guard !codex.hasAnyRunningTurn else {
            debugSidebarLog("rebuildCachedDiffTotals skipped runningTurn=true")
            return
        }
        let startedAt = Date()
        lastDiffFingerprint = fp

        let currentThreadIDs = Set(codex.threads.map(\.id))
        cachedDiffTotals = cachedDiffTotals.filter { currentThreadIDs.contains($0.key) }
        cachedDiffRevisionByThreadID = cachedDiffRevisionByThreadID.filter { currentThreadIDs.contains($0.key) }

        for thread in codex.threads {
            let revision = codex.messageRevision(for: thread.id)
            guard cachedDiffRevisionByThreadID[thread.id] != revision else { continue }

            let messages = codex.messages(for: thread.id)
            cachedDiffTotals[thread.id] = TurnSessionDiffSummaryCalculator.totals(
                from: messages,
                scope: .unpushedSession
            )
            cachedDiffRevisionByThreadID[thread.id] = revision
        }
        debugSidebarLog(
            "rebuildCachedDiffTotals durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) "
                + "threadCount=\(codex.threads.count) cached=\(cachedDiffTotals.count)"
        )
    }

    private func rebuildCachedRunBadges() {
        let fp = badgeFingerprint
        guard fp != lastBadgeFingerprint else { return }
        let startedAt = Date()
        lastBadgeFingerprint = fp

        var byThreadID: [String: CodexThreadRunBadgeState] = [:]
        for thread in codex.threads {
            if let state = codex.threadRunBadgeState(for: thread.id) {
                byThreadID[thread.id] = state
            }
        }
        cachedRunBadges = byThreadID
        debugSidebarLog(
            "rebuildCachedRunBadges durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) "
                + "threadCount=\(codex.threads.count) cached=\(cachedRunBadges.count)"
        )
    }

    // Keeps the chooser in sync with the same project buckets shown in the sidebar.
    private var newChatProjectChoices: [SidebarProjectChoice] {
        SidebarThreadGrouping.makeProjectChoices(from: codex.threads)
    }

    private var canCreateThread: Bool {
        codex.isConnected && codex.isInitialized
    }

    // Sidebar refresh and search events can fire during gestures; logs must not mutate view state.
    private func debugSidebarLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard Self.isSidebarDebugLoggingEnabled else { return }
        print("[SidebarData] \(message())")
        #endif
    }
}

private extension SidebarView {
    static var isSidebarDebugLoggingEnabled: Bool { false }
}

private struct SidebarLifecycleModifier: ViewModifier {
    let isVisible: Bool
    let threads: [CodexThread]
    let searchText: String
    let pinnedThreadIDs: [String]
    let diffFingerprint: Int
    let badgeFingerprint: Int

    let onTask: @Sendable () async -> Void
    let onThreadsChanged: () -> Void
    let onSearchTextChanged: () -> Void
    let onPinnedThreadIDsChanged: () -> Void
    let onDiffFingerprintChanged: () -> Void
    let onBadgeFingerprintChanged: () -> Void
    let onVisibilityChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .task {
                await onTask()
            }
            .onChange(of: threads) { _, _ in
                onThreadsChanged()
            }
            .onChange(of: searchText) { _, _ in
                onSearchTextChanged()
            }
            .onChange(of: pinnedThreadIDs) { _, _ in
                onPinnedThreadIDsChanged()
            }
            .onChange(of: diffFingerprint) { _, _ in
                onDiffFingerprintChanged()
            }
            .onChange(of: badgeFingerprint) { _, _ in
                onBadgeFingerprintChanged()
            }
            .onChange(of: isVisible) { _, visible in
                onVisibilityChanged(visible)
            }
    }
}

private struct SidebarArchiveDialogsModifier: ViewModifier {
    @Binding var projectGroupPendingArchive: SidebarThreadGroup?
    @Binding var bulkArchivePendingThreadIDs: Set<String>?

    let onArchiveProjectGroup: () -> Void
    let onArchiveSelectedThreads: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                String(
                    format: LocalizationManager.shared.localized("sidebar.alert.archive_project_title"),
                    projectGroupPendingArchive?.label ?? "project"
                ),
                isPresented: projectArchiveIsPresented,
                titleVisibility: .visible
            ) {
                Button(LocalizationManager.shared.localized("sidebar.alert.archive_project_button")) {
                    onArchiveProjectGroup()
                }
                Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {
                    projectGroupPendingArchive = nil
                }
            } message: {
                Text(localized: "sidebar.alert.archive_project_message")
            }
            .confirmationDialog(
                String(
                    format: LocalizationManager.shared.localized("sidebar.alert.archive_selected_title"),
                    bulkArchivePendingThreadIDs?.count ?? 0
                ),
                isPresented: selectedArchiveIsPresented,
                titleVisibility: .visible
            ) {
                Button(
                    String(
                        format: LocalizationManager.shared.localized("sidebar.alert.archive_selected_button"),
                        bulkArchivePendingThreadIDs?.count ?? 0
                    )
                ) {
                    onArchiveSelectedThreads()
                }
                Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {
                    bulkArchivePendingThreadIDs = nil
                }
            } message: {
                Text(localized: "sidebar.alert.archive_selected_message")
            }
    }

    private var projectArchiveIsPresented: Binding<Bool> {
        Binding(
            get: { projectGroupPendingArchive != nil },
            set: { isPresented in
                if !isPresented {
                    projectGroupPendingArchive = nil
                }
            }
        )
    }

    private var selectedArchiveIsPresented: Binding<Bool> {
        Binding(
            get: { bulkArchivePendingThreadIDs != nil },
            set: { isPresented in
                if !isPresented {
                    bulkArchivePendingThreadIDs = nil
                }
            }
        )
    }
}

private struct SidebarDeletionDialogsModifier: ViewModifier {
    @Binding var projectGroupPendingDeletion: SidebarThreadGroup?
    @Binding var bulkDeletePendingThreadIDs: Set<String>?
    @Binding var archivedGroupPendingDeletion: SidebarThreadGroup?
    @Binding var threadPendingDeletion: CodexThread?

    let onDeleteProjectGroup: () -> Void
    let onDeleteSelectedThreads: () -> Void
    let onDeleteArchivedChats: () -> Void
    let onDeleteThread: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                String(
                    format: LocalizationManager.shared.localized("sidebar.alert.remove_project_title"),
                    projectGroupPendingDeletion?.label ?? "project"
                ),
                isPresented: projectDeletionIsPresented
            ) {
                Button(LocalizationManager.shared.localized("sidebar.remove_from_phone"), role: .destructive) {
                    onDeleteProjectGroup()
                }
                Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {
                    projectGroupPendingDeletion = nil
                }
            } message: {
                Text(localized: "sidebar.alert.remove_project_message")
            }
            .confirmationDialog(
                String(
                    format: LocalizationManager.shared.localized("sidebar.alert.remove_selected_title"),
                    bulkDeletePendingThreadIDs?.count ?? 0
                ),
                isPresented: selectedDeletionIsPresented,
                titleVisibility: .visible
            ) {
                Button(
                    String(
                        format: LocalizationManager.shared.localized("sidebar.alert.remove_selected_button"),
                        bulkDeletePendingThreadIDs?.count ?? 0
                    ),
                    role: .destructive
                ) {
                    onDeleteSelectedThreads()
                }
                Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {
                    bulkDeletePendingThreadIDs = nil
                }
            } message: {
                Text(localized: "sidebar.alert.remove_selected_message")
            }
            .confirmationDialog(
                String(
                    format: LocalizationManager.shared.localized("sidebar.alert.remove_archived_title"),
                    archivedGroupPendingDeletion?.threads.count ?? 0
                ),
                isPresented: archivedDeletionIsPresented,
                titleVisibility: .visible
            ) {
                Button(
                    String(
                        format: LocalizationManager.shared.localized("sidebar.alert.remove_archived_button"),
                        archivedGroupPendingDeletion?.threads.count ?? 0
                    ),
                    role: .destructive
                ) {
                    onDeleteArchivedChats()
                }
                Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {
                    archivedGroupPendingDeletion = nil
                }
            } message: {
                Text(
                    String(
                        format: LocalizationManager.shared.localized("sidebar.alert.remove_archived_message"),
                        archivedGroupPendingDeletion?.threads.count ?? 0
                    )
                )
            }
            .alert(
                String(
                    format: LocalizationManager.shared.localized("sidebar.alert.remove_chat_title"),
                    threadPendingDeletion?.displayTitle ?? "conversation"
                ),
                isPresented: threadDeletionIsPresented
            ) {
                Button(LocalizationManager.shared.localized("sidebar.remove_from_phone"), role: .destructive) {
                    onDeleteThread()
                }
                Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {
                    threadPendingDeletion = nil
                }
            } message: {
                Text(localized: "sidebar.remove_confirm")
            }
    }

    private var projectDeletionIsPresented: Binding<Bool> {
        Binding(
            get: { projectGroupPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    projectGroupPendingDeletion = nil
                }
            }
        )
    }

    private var selectedDeletionIsPresented: Binding<Bool> {
        Binding(
            get: { bulkDeletePendingThreadIDs != nil },
            set: { isPresented in
                if !isPresented {
                    bulkDeletePendingThreadIDs = nil
                }
            }
        )
    }

    private var archivedDeletionIsPresented: Binding<Bool> {
        Binding(
            get: { archivedGroupPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    archivedGroupPendingDeletion = nil
                }
            }
        )
    }

    private var threadDeletionIsPresented: Binding<Bool> {
        Binding(
            get: { threadPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    threadPendingDeletion = nil
                }
            }
        )
    }
}

private struct SidebarErrorAlertModifier: ViewModifier {
    @Binding var createThreadErrorMessage: String?

    func body(content: Content) -> some View {
        content.alert(
            LocalizationManager.shared.localized("sidebar.alert.action_failed"),
            isPresented: errorIsPresented,
            actions: {
                Button(LocalizationManager.shared.localized("common.ok"), role: .cancel) {
                    createThreadErrorMessage = nil
                }
            },
            message: {
                Text(createThreadErrorMessage ?? LocalizationManager.shared.localized("sidebar.alert.try_again"))
            }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { createThreadErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    createThreadErrorMessage = nil
                }
            }
        )
    }
}

private extension View {
    func sidebarLifecycle(
        isVisible: Bool,
        threads: [CodexThread],
        searchText: String,
        pinnedThreadIDs: [String],
        diffFingerprint: Int,
        badgeFingerprint: Int,
        onTask: @escaping @Sendable () async -> Void,
        onThreadsChanged: @escaping () -> Void,
        onSearchTextChanged: @escaping () -> Void,
        onPinnedThreadIDsChanged: @escaping () -> Void,
        onDiffFingerprintChanged: @escaping () -> Void,
        onBadgeFingerprintChanged: @escaping () -> Void,
        onVisibilityChanged: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            SidebarLifecycleModifier(
                isVisible: isVisible,
                threads: threads,
                searchText: searchText,
                pinnedThreadIDs: pinnedThreadIDs,
                diffFingerprint: diffFingerprint,
                badgeFingerprint: badgeFingerprint,
                onTask: onTask,
                onThreadsChanged: onThreadsChanged,
                onSearchTextChanged: onSearchTextChanged,
                onPinnedThreadIDsChanged: onPinnedThreadIDsChanged,
                onDiffFingerprintChanged: onDiffFingerprintChanged,
                onBadgeFingerprintChanged: onBadgeFingerprintChanged,
                onVisibilityChanged: onVisibilityChanged
            )
        )
    }

    func sidebarArchiveDialogs(
        projectGroupPendingArchive: Binding<SidebarThreadGroup?>,
        bulkArchivePendingThreadIDs: Binding<Set<String>?>,
        onArchiveProjectGroup: @escaping () -> Void,
        onArchiveSelectedThreads: @escaping () -> Void
    ) -> some View {
        modifier(
            SidebarArchiveDialogsModifier(
                projectGroupPendingArchive: projectGroupPendingArchive,
                bulkArchivePendingThreadIDs: bulkArchivePendingThreadIDs,
                onArchiveProjectGroup: onArchiveProjectGroup,
                onArchiveSelectedThreads: onArchiveSelectedThreads
            )
        )
    }

    func sidebarDeletionDialogs(
        projectGroupPendingDeletion: Binding<SidebarThreadGroup?>,
        bulkDeletePendingThreadIDs: Binding<Set<String>?>,
        archivedGroupPendingDeletion: Binding<SidebarThreadGroup?>,
        threadPendingDeletion: Binding<CodexThread?>,
        onDeleteProjectGroup: @escaping () -> Void,
        onDeleteSelectedThreads: @escaping () -> Void,
        onDeleteArchivedChats: @escaping () -> Void,
        onDeleteThread: @escaping () -> Void
    ) -> some View {
        modifier(
            SidebarDeletionDialogsModifier(
                projectGroupPendingDeletion: projectGroupPendingDeletion,
                bulkDeletePendingThreadIDs: bulkDeletePendingThreadIDs,
                archivedGroupPendingDeletion: archivedGroupPendingDeletion,
                threadPendingDeletion: threadPendingDeletion,
                onDeleteProjectGroup: onDeleteProjectGroup,
                onDeleteSelectedThreads: onDeleteSelectedThreads,
                onDeleteArchivedChats: onDeleteArchivedChats,
                onDeleteThread: onDeleteThread
            )
        )
    }

    func sidebarErrorAlert(createThreadErrorMessage: Binding<String?>) -> some View {
        modifier(SidebarErrorAlertModifier(createThreadErrorMessage: createThreadErrorMessage))
    }
}

private enum SidebarPresentedSheet: String, Identifiable {
    case newChatProjectPicker
    case localFolderBrowser

    var id: String { rawValue }
}

private extension SidebarView {
    @ViewBuilder
    func sidebarSheetContent(_ sheet: SidebarPresentedSheet) -> some View {
        switch sheet {
        case .newChatProjectPicker:
            SidebarNewChatProjectPickerSheet(
                choices: newChatProjectChoices,
                onSelectProject: { projectPath in
                    activeSidebarSheet = nil
                    handleNewChatTap(preferredProjectPath: projectPath)
                },
                onSelectWorktreeProject: { projectPath in
                    activeSidebarSheet = nil
                    handleNewWorktreeChatTap(preferredProjectPath: projectPath)
                },
                onSelectWithoutProject: {
                    activeSidebarSheet = nil
                    handleNewChatTap(preferredProjectPath: nil)
                },
                onBrowseLocalFolder: {
                    presentLocalFolderBrowser()
                }
            )
        case .localFolderBrowser:
            SidebarLocalFolderBrowserSheet { projectPath in
                activeSidebarSheet = nil
                handleNewChatTap(preferredProjectPath: projectPath)
            }
        }
    }
}

enum SidebarThreadsLoadingPresentation {
    // Keeps pull-to-refresh from stacking a second spinner over an already populated sidebar.
    static func shouldShowOverlay(isLoadingThreads: Bool, threadCount: Int) -> Bool {
        isLoadingThreads && threadCount == 0
    }

    // Populated sidebars still need feedback while the complete metadata pass is running.
    static func shouldShowInlineStatus(isLoadingThreads: Bool, threadCount: Int) -> Bool {
        isLoadingThreads && threadCount > 0
    }
}

private struct SidebarThreadsInlineLoadingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(localized: "sidebar.syncing")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// SidebarNewChatProjectPickerSheet has moved to
// Views/Sidebar/SidebarNewChatProjectPickerSheet.swift so it can carry its own
// SwiftUI #Preview without dragging in the rest of the sidebar.
