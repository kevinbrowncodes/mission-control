//
//  SpaceLabels.swift
//  MissionControl
//
//  Names Spaces so the name fills that Space's thumbnail in Mission Control's Spaces bar.
//
//  While Mission Control is open, every named Space shows a full-screen card with its name,
//  so its thumbnail is the name. On the current Space the card would also cover Mission
//  Control's big view of its windows, so there it shows only while the pointer is up at the
//  Spaces bar, where the thumbnails are. Outside Mission Control nothing shows, except a
//  brief preview of the card right after naming.
//
//  macOS has no public API for naming Spaces or even identifying them, and the "Desktop 1"
//  captions in the Spaces bar can't be changed without private APIs (Guideline 2.5.1).
//  So each Space gets an invisible 1x1 marker window that doubles as its identity: a window
//  that isn't set to join all Spaces stays on the Space it was first shown on, and
//  `isOnActiveSpace` (public) tells us which marker belongs to the Space we're on. A Space
//  with no marker is one we haven't met yet. Mission Control is detected from the Dock's
//  layer-20 window in the public window list (see `missionControlIsOpen`).
//
//  Hidden cards shrink to a point as well as going transparent: Mission Control draws a
//  large window at alpha 0 as solid black in the thumbnail.
//
//  Limits: only the main display's Spaces; names can't survive a restart (no stable Space
//  ID), so after relaunch Spaces are unnamed and naming offers the names used before.
//

import AppKit
import SwiftUI
import Combine

final class SpaceLabelManager {
    private var markers: [SpaceMarkerWindow] = []
    private var observer: NSObjectProtocol?

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Preferences.spaceLabelsEnabledKey) }

    /// How long the card preview stays up after naming a Space.
    private static let previewHold: TimeInterval = 1.2

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // isOnActiveSpace settles a moment after the switch animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let self else { return }
                self.syncActiveSpace()
            }
        }
        syncActiveSpace()
        startMissionControlWatch()
    }

    // MARK: - Mission Control detection

    private var missionControlTimer: Timer?
    private var missionControlOpen = false
    /// Whether the current Space's card is up (only while the pointer is at the Spaces bar).
    private var activeCardShown = false

    /// The Spaces bar expands to thumbnails only while the pointer is near the top of the
    /// screen; it reaches about 11.5% of the height, menu bar included.
    private static let spacesBarFraction: CGFloat = 0.14

    /// macOS posts nothing when Mission Control opens, but while it's open the Dock owns a
    /// window at layer 20 covering the screen. Bounds and owner names in the public window
    /// list need no permission.
    private func startMissionControlWatch() {
        missionControlTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.enabled, self.markers.contains(where: { $0.hasName }) else { return }
            let open = Self.missionControlIsOpen()
            let active = self.markers.first { $0.isOnActiveSpace }
            if open != self.missionControlOpen {
                self.missionControlOpen = open
                // Every other named Space shows its card while Mission Control is open: it is
                // seen only in that Space's thumbnail. Cards fade gently either way.
                for marker in self.markers where marker !== active {
                    marker.setCardShown(open, animated: true)
                }
                if !open {
                    self.activeCardShown = false
                    active?.setCardShown(false, animated: true)
                }
            }
            guard open, let active else { return }
            // The current Space's card would also cover Mission Control's big view of its
            // windows, so it shows only while the pointer is up at the Spaces bar, where the
            // thumbnails are.
            let atBar = Self.pointerIsAtSpacesBar()
            if atBar != self.activeCardShown {
                self.activeCardShown = atBar
                active.setCardShown(atBar, animated: true)
            }
        }
    }

    private static func pointerIsAtSpacesBar() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let pointer = NSEvent.mouseLocation
        return screen.frame.contains(pointer)
            && pointer.y >= screen.frame.maxY - screen.frame.height * spacesBarFraction
    }

    private static func missionControlIsOpen() -> Bool {
        guard let screen = NSScreen.screens.first,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return info.contains { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "Dock",
                  (window[kCGWindowLayer as String] as? Int) == 20,
                  let b = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return b["Width"] == screen.frame.width && b["Height"] == screen.frame.height
        }
    }

    /// Called when the preference changes. Markers stay (ordering a window out would drop
    /// it from its Space); with names off, cards just never show.
    func refreshEnabled() {
        if enabled {
            syncActiveSpace()
        } else {
            markers.forEach { $0.setCardShown(false) }
        }
    }

    /// The marker on the Space the user is looking at, creating one if this Space is new.
    @discardableResult
    private func syncActiveSpace() -> SpaceMarkerWindow? {
        guard enabled else { return nil }
        let here = markers.filter { $0.isOnActiveSpace }
        if here.isEmpty {
            // A full-screen app's Space can't hold our window; don't create one there.
            guard !Self.activeSpaceIsFullScreen() else { return nil }
            let marker = SpaceMarkerWindow()
            markers.append(marker)
            return marker
        }
        // A deleted Space's windows move to a neighbour. Keep the named marker.
        let keep = here.first { $0.hasName } ?? here[0]
        for extra in here where extra !== keep {
            extra.close()
            markers.removeAll { $0 === extra }
        }
        return keep
    }

    /// The name of the Space the user is on, or nil if it has none.
    var activeSpaceName: String? {
        markers.first(where: { $0.isOnActiveSpace && $0.hasName })?.name
    }

    /// Names the Space the user is on now (from the panel or the menu).
    func renameActiveSpace() {
        guard let marker = syncActiveSpace() else { return }
        let alert = NSAlert()
        alert.messageText = "Name This Space"
        alert.informativeText = "The name fills this Space's thumbnail in Mission Control. Leave it empty to remove the name."
        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        field.addItems(withObjectValues: Self.recentNames)
        field.completes = true
        field.stringValue = marker.name ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        // From the menu bar icon's right-click menu this app may not be active; the box must
        // take the keyboard either way, so activate firmly rather than cooperatively.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        marker.name = name
        if !name.isEmpty {
            Self.remember(name)
            marker.previewCard(hold: Self.previewHold)
        }
    }

    // MARK: - Names used before (offered after a restart)

    private static var recentNames: [String] {
        UserDefaults.standard.stringArray(forKey: Preferences.recentSpaceNamesKey) ?? []
    }

    private static func remember(_ name: String) {
        var names = recentNames.filter { $0 != name }
        names.insert(name, at: 0)
        UserDefaults.standard.set(Array(names.prefix(20)), forKey: Preferences.recentSpaceNamesKey)
    }

    // MARK: - Full-screen detection

    /// True when an ordinary window covers the whole main screen, menu bar included, which
    /// only a full-screen app does. Window bounds need no permission (titles would).
    private static func activeSpaceIsFullScreen() -> Bool {
        guard let screen = NSScreen.screens.first,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let full = screen.frame.size
        return info.contains { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let b = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return b["X"] == 0 && b["Y"] == 0 && b["Width"] == full.width && b["Height"] == full.height
        }
    }
}

// MARK: - Shared window setup

/// A borderless, click-through panel above ordinary windows that never takes focus and
/// stays out of ⌘Tab and App Exposé.
class OverlayPanel: NSPanel {
    init(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = level
        collectionBehavior = behavior.union([.ignoresCycle, .stationary])
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The frame while showing.
    var shownFrame: NSRect = .zero

    /// Shows or hides the window. Mission Control draws a large window at alpha 0 as solid
    /// black in that Space's thumbnail, hiding everything on it, so a hidden window also
    /// shrinks to a single point. Resizing never moves a window to another Space, which
    /// ordering it out and back in would.
    func setPresence(_ alpha: CGFloat, animated: Bool, fadeIn: TimeInterval = 0.4,
                     fadeOut: TimeInterval = 0.8) {
        if alpha > 0 {
            if frame != shownFrame { setFrame(shownFrame, display: true) }
            if animated {
                NSAnimationContext.runAnimationGroup {
                    $0.duration = fadeIn
                    $0.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    animator().alphaValue = alpha
                }
            } else {
                alphaValue = alpha
            }
        } else if animated {
            NSAnimationContext.runAnimationGroup({
                $0.duration = fadeOut
                $0.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().alphaValue = 0
            }) { [weak self] in
                // Unless it was shown again during the fade.
                if let self, self.alphaValue == 0 { self.collapse() }
            }
        } else {
            alphaValue = 0
            collapse()
        }
    }

    /// Parks the window as a point at the centre of its shown frame, so showing it again
    /// opens out from the middle of the screen rather than a corner.
    private func collapse() {
        setFrame(NSRect(x: shownFrame.midX, y: shownFrame.midY, width: 1, height: 1), display: false)
    }

    /// Puts the window on the active Space at its shown frame if visible, else collapsed.
    func place(at frame: NSRect) {
        shownFrame = frame
        if alphaValue > 0 { setFrame(frame, display: true) } else { collapse() }
        orderFrontRegardless()
    }
}

// MARK: - The marker (one per Space)

/// An invisible 1x1 window whose only job is to stay on its Space and so identify it.
/// It owns that Space's name card.
final class SpaceMarkerWindow: OverlayPanel {
    /// nil: never named. "": name cleared.
    var name: String? { didSet { syncCard() } }
    var hasName: Bool { !(name ?? "").isEmpty }

    /// The full-screen name card, created on naming. Naming happens on the active Space, so
    /// the card lands on the same Space as this marker.
    private var card: SpaceCardWindow?
    private var cardShown = false
    private var previewWork: DispatchWorkItem?

    init() {
        // No .canJoinAllSpaces: staying on one Space is the whole point.
        super.init(level: .floating, behavior: [])
        contentView = NSView()
        if let visible = NSScreen.screens.first?.visibleFrame {
            setFrame(NSRect(x: visible.minX, y: visible.maxY - 1, width: 1, height: 1), display: false)
        }
        orderFrontRegardless()
    }

    override func close() {
        card?.close()
        super.close()
    }

    func setCardShown(_ shown: Bool, animated: Bool = false) {
        previewWork?.cancel()
        cardShown = shown
        card?.setPresence(shown && hasName ? 1 : 0, animated: animated, fadeIn: 0.6)
    }

    /// After naming: the card fades in, holds, and fades out, showing what Mission Control
    /// will show.
    func previewCard(hold: TimeInterval) {
        guard hasName, !cardShown else { return }
        card?.setPresence(1, animated: true)
        previewWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.cardShown else { return }
            self.card?.setPresence(0, animated: true)
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    private func syncCard() {
        if let name, hasName {
            if card == nil { card = SpaceCardWindow() }
            card?.show(name)
        }
        card?.setPresence(cardShown && hasName ? 1 : 0, animated: false)
    }
}

// MARK: - The name card

/// The Space's name filling the screen, so it fills that Space's Mission Control thumbnail.
final class SpaceCardWindow: OverlayPanel {
    private let model = SpaceNameModel()

    init() {
        super.init(level: .floating, behavior: [])
        contentView = NSHostingView(rootView: SpaceCardView(model: model))
        alphaValue = 0
    }

    func show(_ name: String) {
        guard let screen = NSScreen.screens.first else { return }
        let fit = SpaceCardLayout.fit(name.uppercased(), in: screen.frame.size)
        model.text = name.uppercased()
        model.fontSize = fit.size
        model.width = fit.width
        place(at: screen.frame)
    }
}

final class SpaceNameModel: ObservableObject {
    @Published var text = ""
    @Published var fontSize: CGFloat = 100
    @Published var width: Font.Width = .standard
}

/// Picks the SF Pro width and size for a name card: the widest width (Standard, then
/// Condensed, then Compressed) whose size gets within 5% of the largest size any width
/// reaches. Short names hit the size cap in every width, so they get Standard's clearer,
/// wider letters; long names get Compressed, the only width that keeps them large.
/// Compared on real thumbnails before choosing this rule.
enum SpaceCardLayout {
    static let maxSizeFraction: CGFloat = 0.36   // of screen height
    static let paddingFraction: CGFloat = 0.05   // of screen width, each side
    static let maxLines = 2

    static func fit(_ text: String, in screen: CGSize) -> (width: Font.Width, size: CGFloat) {
        let candidates: [(Font.Width, NSFont.Width)] = [(.standard, .standard), (.condensed, .condensed),
                                                         (.compressed, .compressed)]
        let sizes = candidates.map { largestSize(text, $0.1, screen) }
        let best = sizes.max() ?? 100
        let index = sizes.firstIndex { $0 >= best * 0.95 } ?? candidates.count - 1
        return (candidates[index].0, sizes[index])
    }

    /// The largest size at which the text wraps to at most `maxLines` lines that fit.
    private static func largestSize(_ text: String, _ width: NSFont.Width, _ screen: CGSize) -> CGFloat {
        let maxSize = screen.height * maxSizeFraction
        if fits(text, maxSize, width, screen) { return maxSize }
        var low: CGFloat = 8, high = maxSize
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if fits(text, mid, width, screen) { low = mid } else { high = mid }
        }
        return low
    }

    private static func fits(_ text: String, _ size: CGFloat, _ width: NSFont.Width, _ screen: CGSize) -> Bool {
        let font = NSFont.systemFont(ofSize: size, weight: .heavy, width: width)
        let available = screen.width * (1 - 2 * paddingFraction)
        func measure(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        var lines = 0, current = ""
        for word in text.split(separator: " ").map(String.init) {
            let trial = current.isEmpty ? word : current + " " + word
            if current.isEmpty || measure(trial) <= available {
                current = trial
            } else {
                guard measure(current) <= available else { return false }
                lines += 1
                current = word
            }
        }
        lines += 1
        guard lines <= maxLines, measure(current) <= available else { return false }
        let height = screen.height * (1 - 2 * paddingFraction)
        return CGFloat(lines) * font.ascender * 1.25 <= height
    }
}

struct SpaceCardView: View {
    @ObservedObject var model: SpaceNameModel

    var body: some View {
        GeometryReader { geo in
            Text(model.text)
                .font(.system(size: model.fontSize, weight: .heavy).width(model.width))
                .multilineTextAlignment(.center)
                .lineLimit(SpaceCardLayout.maxLines)
                // Safety net only; SpaceCardLayout already sized it to fit.
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .padding(geo.size.width * SpaceCardLayout.paddingFraction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.95))
        }
        // Drawn for the Mission Control thumbnails only; the panel's THIS SPACE row is where
        // the name is read. Without this, VoiceOver would find the name in a hidden window.
        .accessibilityHidden(true)
    }
}
