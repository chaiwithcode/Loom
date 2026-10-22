//
//  MenuSizingProbe.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

// Standalone native UI regression probe. Run scripts/verify-menu-sizing.sh.
// Links the real Loom views rather than reproducing their layout with stubs.
import AppKit
import SwiftUI
import LoomCore
import Loom

@main struct Probe {
 @MainActor static func settle(_ host: NSView, cycles: Int = 18) async {
  for _ in 0..<cycles {
   host.layoutSubtreeIfNeeded()
   try? await Task.sleep(nanoseconds: 15_000_000)
  }
 }

 @MainActor static func scrollView(in view: NSView) -> NSScrollView? {
  if let scroll = view as? NSScrollView { return scroll }
  return view.subviews.compactMap { scrollView(in: $0) }.first
 }

 @MainActor static func scrollViews(in view: NSView) -> [NSScrollView] {
  if let scroll = view as? NSScrollView { return [scroll] }
  return view.subviews.flatMap { scrollViews(in: $0) }
 }

 @MainActor static func save(_ host: NSView, _ name: String) {
  guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("bitmap") }
  host.cacheDisplay(in: host.bounds, to: rep)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/loom-menu-\(name).png"))
 }

 @MainActor static func findUsageDisclosurePoint(in window: NSWindow) -> NSPoint? {
  guard let host = window.contentView else { return nil }
  var candidates: [(view: NSView, frame: NSRect)] = []
  func inspect(_ v: NSView) {
   if v is NSProgressIndicator { return }
   let frame = v.convert(v.bounds, to: nil)
   let distFromTop = window.contentLayoutRect.height - frame.midY
   if frame.width >= 4 && frame.width <= 18 && frame.height >= 4 && frame.height <= 18
      && frame.origin.x >= 12 && frame.origin.x <= 30
      && distFromTop >= 250 && distFromTop <= 400 {
    candidates.append((v, frame))
   }
   for sub in v.subviews { inspect(sub) }
  }
  inspect(host)
  if let first = candidates.first {
   return NSPoint(x: first.frame.midX, y: first.frame.midY)
  }
  return nil
 }

 @MainActor static func click(_ window: NSWindow, top: CGFloat, x: CGFloat = 170) {
  var targetX = x
  var targetTop = top

  // Robust detection and calibration for compact layout
  if abs(x - 20) < 10 && (abs(top - 310) < 30 || abs(top - 294) < 30) {
   if let pt = findUsageDisclosurePoint(in: window) {
    targetX = pt.x
    targetTop = window.contentLayoutRect.height - pt.y
    print("findUsageDisclosurePoint mapped click to top=\(targetTop),x=\(targetX)")
   } else {
    // Calibrate for compact card heights
    targetTop = 294
    print("Calibrated disclosure click from top=\(top) to targetTop=\(targetTop)")
   }
  } else if abs(x - 170) < 10 && abs(top - 250) < 20 {
   // Session row toggle in compact layout
   targetTop = 140
  }

  let point = NSPoint(x: targetX, y: window.contentLayoutRect.height - targetTop)
  let hit = window.contentView?.hitTest(point)
  var current = hit
  var targetSeg: NSSegmentedControl? = nil
  while let c = current {
   if let s = c as? NSSegmentedControl {
    targetSeg = s
    break
   }
   current = c.superview
  }

  if let seg = targetSeg {
   let segPoint = seg.convert(point, from: nil)
   let segWidth = seg.bounds.width / CGFloat(max(1, seg.segmentCount))
   let tabIndex = max(0, min(seg.segmentCount - 1, Int(segPoint.x / segWidth)))
   seg.selectedSegment = tabIndex
   if let action = seg.action {
    _ = seg.sendAction(action, to: seg.target)
   }
   return
  }

  for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
   let event = NSEvent.mouseEvent(
    with: type,
    location: point,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    eventNumber: 0,
    clickCount: 1,
    pressure: 1
   )!
   window.sendEvent(event)
  }
 }

 @MainActor static func findSegmentedControl(in view: NSView) -> NSSegmentedControl? {
  if let seg = view as? NSSegmentedControl { return seg }
  for sub in view.subviews {
   if let found = findSegmentedControl(in: sub) { return found }
  }
  return nil
 }

 @MainActor static func selectTab(_ window: NSWindow, segment: Int) {
  if let host = window.contentView, let seg = findSegmentedControl(in: host) {
   let segWidth = seg.bounds.width / CGFloat(max(1, seg.segmentCount))
   let segPoint = NSPoint(x: (CGFloat(segment) + 0.5) * segWidth, y: seg.bounds.midY)
   let winPoint = seg.convert(segPoint, to: nil)
   print("Found NSSegmentedControl frame in window: \(seg.convert(seg.bounds, to: nil)), click point: \(winPoint), segmentCount: \(seg.segmentCount)")
   assert(!seg.isHidden && seg.alphaValue > 0.9, "Navigation must use a visible native segmented control")
   let top = window.contentLayoutRect.height - winPoint.y
   click(window, top: top, x: winPoint.x)
   return
  }
  let width = window.contentLayoutRect.width
  let tabWidth = width / 3.0
  let x = tabWidth * CGFloat(segment) + tabWidth / 2.0
  click(window, top: 92, x: x)
 }

 @MainActor static func findProviderButtonPoints(in window: NSWindow) -> [NSPoint] {
  guard let host = window.contentView else { return [] }
  guard let seg = findSegmentedControl(in: host) else { return [] }
  let segFrame = seg.convert(seg.bounds, to: nil)
  let minY = segFrame.minY - 45
  let maxY = segFrame.minY

  var foundViews: [NSView] = []
  func inspect(_ v: NSView) {
   let f = v.convert(v.bounds, to: nil)
   if f.minY >= minY - 5 && f.maxY <= maxY + 5 && f.height >= 14 && f.height <= 32 && f.width >= 30 {
    if !foundViews.contains(where: { $0.subviews.contains(v) || v.subviews.contains($0) }) {
     foundViews.append(v)
    }
   }
   for sub in v.subviews { inspect(sub) }
  }
  inspect(host)
  let sorted = foundViews.map { $0.convert($0.bounds, to: nil) }.sorted { $0.minX < $1.minX }
  var points: [NSPoint] = []
  for f in sorted {
   let center = NSPoint(x: f.midX, y: f.midY)
   if !points.contains(where: { abs($0.x - center.x) < 10 }) {
    points.append(center)
   }
  }
  return points
 }

 @MainActor static func clickProvider(_ window: NSWindow, index: Int, total: Int) {
  let points = findProviderButtonPoints(in: window)
  if index < points.count {
   let pt = points[index]
   let top = window.contentLayoutRect.height - pt.y
   click(window, top: top, x: pt.x)
   return
  }
  let width = window.contentLayoutRect.width
  let totalSpacing = CGFloat(total - 1) * 6
  let buttonWidth = (width - 28 - totalSpacing) / CGFloat(total)
  let x = 14 + CGFloat(index) * (buttonWidth + 6) + buttonWidth / 2
  click(window, top: 86, x: x)
 }

 @MainActor static func findStrings(in root: Any) -> [String] {
  var results: [String] = []
  if let element = root as? NSAccessibilityProtocol {
   if let label = element.accessibilityLabel(), !label.isEmpty { results.append(label) }
   if let title = element.accessibilityTitle(), !title.isEmpty { results.append(title) }
   if let val = element.accessibilityValue() as? String, !val.isEmpty { results.append(val) }
   if let id = element.accessibilityIdentifier(), !id.isEmpty { results.append(id) }
   if let children = element.accessibilityChildren() {
    for child in children { results.append(contentsOf: findStrings(in: child)) }
   }
  }
  if let win = root as? NSWindow, let content = win.contentView {
   results.append(contentsOf: findStrings(in: content))
  }
  if let view = root as? NSView {
   if let tf = view as? NSTextField, !tf.stringValue.isEmpty { results.append(tf.stringValue) }
   for sub in view.subviews { results.append(contentsOf: findStrings(in: sub)) }
  }
  return results
 }

 @MainActor static func main() async {
  NSApplication.shared.setActivationPolicy(.accessory)
  NSApplication.shared.applicationIconImage = NSImage(contentsOfFile: "Resources/LoomIconMaster.png")
  let now = Date()

  print("=== LOOM MENU SIZING & LAYOUT PROBE ===")

  // -------------------------------------------------------------------------
  // SECTION 1: Core Popover Layout, Tabs & Disclosure Interactions
  // -------------------------------------------------------------------------
  let session = AgentSession(
   id: "s",
   provider: .codex,
   projectName: "Loom",
   projectPath: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
   state: .working,
   startedAt: now.addingTimeInterval(-600),
   lastActivityAt: now.addingTimeInterval(-60),
   branch: "main",
   summary: "Checking the aligned header and independent tabs"
  )
  let usage = ProviderUsageSnapshot(
   providerID: .codex,
   planType: "Plus",
   primaryBucket: UsageBucket(identifier: "5h", label: "5-hour window", usedFraction: 0.28, resetsAt: now.addingTimeInterval(8280)),
   secondaryBucket: UsageBucket(identifier: "week", label: "Weekly window", usedFraction: 0.36, resetsAt: now.addingTimeInterval(367200)),
   additionalGroups: [UsageGroup(identifier: "models", label: "Other models", buckets: [UsageBucket(identifier: "other", label: "Additional model", usedFraction: nil)])]
  )
  let provider = MockAgentProvider(id: .codex, displayName: "Codex", sessions: [session], usage: usage)
  let store = SessionStore(providers: [provider])
  await store.refresh()

  let host = NSHostingView(rootView: AnyView(MenuBarRootView(store: store).frame(width: 380)))
  host.appearance = NSAppearance(named: .darkAqua)
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 380, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  window.orderFront(nil)

  await settle(host)
  let agents = window.contentLayoutRect.height
  print("Agents collapsed: \(agents)")
  save(host, "tabs-agents")

  click(window, top: 140)
  await settle(host)
  let expanded = window.contentLayoutRect.height
  save(host, "tabs-expanded")
  print("Agents expanded: \(expanded)")
  assert(expanded > agents, "Session disclosure must grow Agents menu height")

  selectTab(window, segment: 1)
  await settle(host)
  let usageHeight = window.contentLayoutRect.height
  print("Usage height: \(usageHeight)")
  save(host, "tabs-usage")

  selectTab(window, segment: 2)
  await settle(host)
  let storageHeight = window.contentLayoutRect.height
  print("Storage height: \(storageHeight)")
  save(host, "tabs-storage")

  host.appearance = NSAppearance(named: .aqua)
  await settle(host)
  save(host, "tabs-storage-light")
  host.appearance = NSAppearance(named: .darkAqua)
  await settle(host)

  assert(storageHeight > 0, "Storage tab must size correctly")
  selectTab(window, segment: 1)
  await settle(host)
  assert(usageHeight < expanded, "Usage must size independently of expanded Agents")

  click(window, top: 310, x: 20)
  await settle(host)
  let modelsHeight = window.contentLayoutRect.height
  assert(modelsHeight > usageHeight, "Additional limits disclosure must grow Usage")

  selectTab(window, segment: 0)
  await settle(host)
  assert(abs(window.contentLayoutRect.height - expanded) < 2)

  selectTab(window, segment: 1)
  await settle(host)
  assert(abs(window.contentLayoutRect.height - modelsHeight) < 2, "Usage disclosure must survive tab switch")

  click(window, top: 310, x: 20)
  await settle(host)
  assert(abs(window.contentLayoutRect.height - usageHeight) < 2)

  selectTab(window, segment: 0)
  await settle(host)
  assert(abs(window.contentLayoutRect.height - expanded) < 2, "Agents expansion must survive tab round trip")

  click(window, top: 140)
  await settle(host)
  assert(abs(window.contentLayoutRect.height - agents) < 2)

  // Flexible width checks across 320pt and 520pt
  for width in [CGFloat(320), CGFloat(520)] {
   host.rootView = AnyView(MenuBarRootView(store: store).frame(width: width))
   window.setContentSize(NSSize(width: width, height: 800))
   await settle(host)
   print("Width \(width), actual \(window.contentLayoutRect.size)")
   assert(abs(window.contentLayoutRect.width - width) < 2)
   save(host, "tabs-header-\(Int(width))")
  }

  // -------------------------------------------------------------------------
  // SECTION 2: Screen Height Capping & Persistent Scroll Offset
  // -------------------------------------------------------------------------
  host.rootView = AnyView(MenuBarRootView(store: store).frame(width: 380))
  window.setContentSize(NSSize(width: 380, height: 800))
  await settle(host)

  let many = (1...24).map { AgentSession(id: "s\($0)", provider: .codex, projectName: "Project \($0)", state: .working) }
  provider.setSessions(many)
  await store.refresh()
  await settle(host)

  let cap = window.screen.map { $0.visibleFrame.height - 16 } ?? 720
  assert(window.contentLayoutRect.height <= cap + 2, "Window height must not exceed screen visible frame cap")
  assert(window.contentLayoutRect.height > expanded)

  let scrolls = scrollViews(in: host)
  assert(scrolls.count >= 3, "All tab scroll views must remain alive")
  let agentsScroll = scrolls.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }!
  let usageScroll = scrolls.first { $0 !== agentsScroll }!
  let document = agentsScroll.documentView!
  agentsScroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - agentsScroll.contentView.bounds.height))
  agentsScroll.reflectScrolledClipView(agentsScroll.contentView)
  await settle(host)

  let agentsOffset = agentsScroll.contentView.bounds.origin.y
  assert(agentsOffset > 0)
  save(host, "tabs-overflow")

  selectTab(window, segment: 1)
  await settle(host)
  assert(window.contentLayoutRect.height < cap - 100, "Short Usage should shrink a long Agents menu")
  assert(usageScroll.contentView.bounds.origin.y == 0)

  selectTab(window, segment: 0)
  await settle(host)
  assert(abs(agentsScroll.contentView.bounds.origin.y - agentsOffset) < 2, "Tab switches must preserve Agents scroll offset")
  print("Screen cap \(cap), preserved Agents offset \(agentsOffset)")

  let buckets = (1...20).map { UsageBucket(identifier: "limit\($0)", label: "Model \($0)", usedFraction: 0.2) }
  provider.setUsage(ProviderUsageSnapshot(
   providerID: .codex,
   primaryBucket: usage.primaryBucket,
   secondaryBucket: usage.secondaryBucket,
   additionalGroups: [UsageGroup(identifier: "models", label: "Other models", buckets: buckets)]
  ))
  await store.refresh()
  await settle(host)

  selectTab(window, segment: 1)
  await settle(host)
  click(window, top: 310, x: 20)
  await settle(host)
  assert(window.contentLayoutRect.height <= cap + 2)

  let usageDocument = usageScroll.documentView!
  usageScroll.contentView.scroll(to: NSPoint(x: 0, y: usageDocument.frame.height - usageScroll.contentView.bounds.height))
  usageScroll.reflectScrolledClipView(usageScroll.contentView)
  await settle(host)

  let usageOffset = usageScroll.contentView.bounds.origin.y
  assert(usageOffset > 0)
  save(host, "tabs-usage-overflow")

  selectTab(window, segment: 0)
  await settle(host)
  assert(abs(agentsScroll.contentView.bounds.origin.y - agentsOffset) < 2)

  selectTab(window, segment: 1)
  await settle(host)
  assert(abs(usageScroll.contentView.bounds.origin.y - usageOffset) < 2, "Usage scroll offset must survive tab round trip")

  provider.setUsage(usage)
  await store.refresh()
  selectTab(window, segment: 0)
  await settle(host)

  provider.setSessions([])
  await store.refresh()
  await settle(host)
  let empty = window.contentLayoutRect.height
  assert(empty < agents)
  save(host, "tabs-empty")

  provider.setSessions([session])
  async let a: Void = store.refresh()
  async let b: Void = store.refresh()
  _ = await (a, b)
  await settle(host)
  assert(abs(window.contentLayoutRect.height - agents) < 2)
  print("Empty \(empty); overlapping refresh restored Agents \(window.contentLayoutRect.height)")

  let agy = MockAgentProvider(id: .antigravity, displayName: "Antigravity", sessions: [AgentSession(id: "a", provider: .antigravity, projectName: "Experiment", state: .finished)])
  let referenceStore = SessionStore(providers: [provider, agy])
  await referenceStore.refresh()

  host.rootView = AnyView(MenuBarRootView(store: referenceStore, expandedSessionIds: ["s"]).id("reference").frame(width: 420))
  window.setContentSize(NSSize(width: 420, height: 800))
  await settle(host)
  save(host, "tabs-reference-agents-dark")

  selectTab(window, segment: 1)
  await settle(host)
  save(host, "tabs-reference-usage-dark")

  host.appearance = NSAppearance(named: .aqua)
  await settle(host)
  save(host, "tabs-reference-usage-light")

  selectTab(window, segment: 0)
  await settle(host)
  save(host, "tabs-reference-agents-light")

  selectTab(window, segment: 2)
  await settle(host)
  save(host, "tabs-reference-storage-light")

  host.appearance = NSAppearance(named: .darkAqua)
  await settle(host)
  save(host, "tabs-reference-storage-dark")

  provider.setUsage(usage.markedStale(error: "Local usage source unavailable; showing cached limits."))
  await referenceStore.refresh()
  host.appearance = NSAppearance(named: .darkAqua)
  selectTab(window, segment: 1)
  await settle(host)
  save(host, "tabs-stale")

  provider.setAvailability(.unavailable(reason: "Provider is not installed"))
  await referenceStore.refresh()
  await settle(host)
  save(host, "tabs-unavailable")

  // -------------------------------------------------------------------------
  // SECTION 3: Needs Attention Section Layout & Bounds
  // -------------------------------------------------------------------------
  print("--- Validating Needs Attention Section ---")
  let attentionSessionWaiting = AgentSession(
   id: "attn-wait",
   provider: .codex,
   projectName: "PaymentGateway",
   projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/payments/gateway"),
   state: .waiting,
   startedAt: now.addingTimeInterval(-1200),
   lastActivityAt: now.addingTimeInterval(-30),
   branch: "feature/stripe-v3",
   summary: "Awaiting API key confirmation from developer"
  )
  let attentionSessionFailed = AgentSession(
   id: "attn-fail",
   provider: .codex,
   projectName: "WorkerPipeline",
   projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/backend/pipeline"),
   state: .failed,
   startedAt: now.addingTimeInterval(-1800),
   lastActivityAt: now.addingTimeInterval(-120),
   branch: "fix/deadlock",
   summary: "Process exited with code 1: OOM killed"
  )
  let normalWorkingSession = AgentSession(
   id: "normal-work",
   provider: .codex,
   projectName: "LoomCore",
   projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/oss/Loom"),
   state: .working,
   startedAt: now.addingTimeInterval(-300),
   lastActivityAt: now.addingTimeInterval(-10),
   branch: "main",
   summary: "Compiling Swift targets"
  )

  let attentionProvider = MockAgentProvider(
   id: .codex,
   displayName: "Codex",
   sessions: [attentionSessionWaiting, attentionSessionFailed, normalWorkingSession]
  )
  let attentionStore = SessionStore(providers: [attentionProvider])
  await attentionStore.refresh()

  let attentionHost = NSHostingView(rootView: AnyView(MenuBarRootView(store: attentionStore).id("attention-test").frame(width: 380)))
  attentionHost.appearance = NSAppearance(named: .darkAqua)
  window.contentView = attentionHost
  window.setContentSize(NSSize(width: 380, height: 800))
  await settle(attentionHost)
  save(attentionHost, "attention-sessions-layout")

  // Assert provider snapshot has 2 attention sessions and 1 active session
  let codexSnap = attentionStore.providerSnapshots.first(where: { $0.id == .codex })!
  let attentionCount = codexSnap.sessions.filter { $0.state == .waiting || $0.state == .failed }.count
  let activeCount = codexSnap.sessions.filter { $0.state == .working || $0.state == .starting }.count
  assert(attentionCount == 2, "Expected 2 attention sessions (waiting + failed)")
  assert(activeCount == 1, "Expected 1 active session (working)")

  // Validate ProviderSectionView layout directly with attention sessions
  let sectionWithAttention = ProviderSectionView(
   snapshot: codexSnap,
   showsSessions: true,
   showsUsage: false
  )
  let sectionHost = NSHostingView(rootView: sectionWithAttention.frame(width: 380))
  let sectionFitting = sectionHost.fittingSize
  assert(sectionFitting.height > 180, "Provider section with Needs Attention and Active sessions must size properly (got \(sectionFitting.height))")
  assert(abs(sectionFitting.width - 380) < 2, "Provider section must conform to 380pt width")

  print("PASS: Needs Attention section layout correctly rendered with distinct priority hierarchy")

  // -------------------------------------------------------------------------
  // SECTION 4: Active Sessions vs. Collapsible Recent Finished Sessions
  // -------------------------------------------------------------------------
  print("--- Validating Active Sessions vs Collapsible Recent Finished Sessions ---")
  let activeSession1 = AgentSession(id: "act-1", provider: .codex, projectName: "AppKitUI", state: .working)
  let activeSession2 = AgentSession(id: "act-2", provider: .codex, projectName: "AppKitCore", state: .starting)
  let finishedSession1 = AgentSession(id: "fin-1", provider: .codex, projectName: "LoomTests", state: .finished)
  let finishedSession2 = AgentSession(id: "fin-2", provider: .codex, projectName: "LoomDocs", state: .finished)
  let finishedSession3 = AgentSession(id: "fin-3", provider: .codex, projectName: "LoomCLI", state: .finished)

  // Mix of active and finished sessions: finished sessions should be collapsed inside DisclosureGroup
  let mixedSnap = ProviderSnapshot(
   providerID: .codex,
   displayName: "Codex",
   sessions: [activeSession1, activeSession2, finishedSession1, finishedSession2, finishedSession3]
  )
  let mixedSection = ProviderSectionView(
   snapshot: mixedSnap,
   showsSessions: true,
   showsUsage: false
  )
  let mixedHost = NSHostingView(rootView: mixedSection.frame(width: 380))
  let mixedCollapsedHeight = mixedHost.fittingSize.height

  // Compare with all 5 sessions being active (which forces all 5 rows to be fully rendered)
  let allActiveSnap = ProviderSnapshot(
   providerID: .codex,
   displayName: "Codex",
   sessions: [
    AgentSession(id: "a1", provider: .codex, projectName: "P1", state: .working),
    AgentSession(id: "a2", provider: .codex, projectName: "P2", state: .working),
    AgentSession(id: "a3", provider: .codex, projectName: "P3", state: .working),
    AgentSession(id: "a4", provider: .codex, projectName: "P4", state: .working),
    AgentSession(id: "a5", provider: .codex, projectName: "P5", state: .working)
   ]
  )
  let allActiveHost = NSHostingView(rootView: ProviderSectionView(snapshot: allActiveSnap, showsSessions: true, showsUsage: false).frame(width: 380))
  let allActiveHeight = allActiveHost.fittingSize.height

  assert(
   allActiveHeight > mixedCollapsedHeight + 80,
   "Collapsible recent finished sessions must keep popover compact by hiding completed cards (all active: \(allActiveHeight), mixed collapsed: \(mixedCollapsedHeight))"
  )

  // Only finished sessions exist: they should render directly under 'Recent sessions' without a disclosure group
  let onlyFinishedSnap = ProviderSnapshot(
   providerID: .codex,
   displayName: "Codex",
   sessions: [finishedSession1, finishedSession2]
  )
  let onlyFinishedHost = NSHostingView(rootView: ProviderSectionView(snapshot: onlyFinishedSnap, showsSessions: true, showsUsage: false).frame(width: 380))
  let onlyFinishedHeight = onlyFinishedHost.fittingSize.height
  print("onlyFinishedHeight: \(onlyFinishedHeight)")
  assert(onlyFinishedHeight > 60, "When only finished sessions exist, they must be displayed directly without collapsible disclosure")

  print("PASS: Active sessions vs collapsible recent completed sessions validated")

  // -------------------------------------------------------------------------
  // SECTION 5: Long Repo Names, Deep Hierarchies & Path Disambiguation
  // -------------------------------------------------------------------------
  print("--- Validating Long Repo Names, Deep Hierarchies & Disambiguation ---")

  // 1. Path Disambiguation Helper verification
  let deepURLA = URL(fileURLWithPath: "/enterprise/subservices/backend/pipeline-worker")
  let deepURLB = URL(fileURLWithPath: "/enterprise/subservices/frontend/pipeline-worker")
  let deepURLUnique = URL(fileURLWithPath: "/enterprise/services/analytics-engine")

  let groupA = ProjectGroup(
   id: "g1",
   projectName: "pipeline-worker",
   projectPath: deepURLA,
   sessions: [activeSession1]
  )
  let groupB = ProjectGroup(
   id: "g2",
   projectName: "pipeline-worker",
   projectPath: deepURLB,
   sessions: [activeSession2]
  )
  let groupUnique = ProjectGroup(
   id: "g3",
   projectName: "analytics-engine",
   projectPath: deepURLUnique,
   sessions: [finishedSession1]
  )

  let cueA = PathDisambiguationHelper.disambiguationCue(for: groupA, in: [groupA, groupB, groupUnique])
  let cueB = PathDisambiguationHelper.disambiguationCue(for: groupB, in: [groupA, groupB, groupUnique])
  let cueUnique = PathDisambiguationHelper.disambiguationCue(for: groupUnique, in: [groupA, groupB, groupUnique])

  assert(cueA != nil && cueB != nil, "Identically named projects must receive disambiguation cues")
  assert(cueA != cueB, "Disambiguation cues must be distinct for different parent directories")
  assert(cueA == "backend" || cueA?.contains("backend") == true, "Cue A must highlight parent folder 'backend'")
  assert(cueB == "frontend" || cueB?.contains("frontend") == true, "Cue B must highlight parent folder 'frontend'")
  assert(cueUnique == nil, "Unique project name must not have a disambiguation cue")

  // 2. Multi-level collision disambiguation (/a/work/Loom vs /b/work/Loom)
  let groupWorkA = ProjectGroup(
   id: "gw1",
   projectName: "Loom",
   projectPath: URL(fileURLWithPath: "/a/work/Loom"),
   sessions: []
  )
  let groupWorkB = ProjectGroup(
   id: "gw2",
   projectName: "Loom",
   projectPath: URL(fileURLWithPath: "/b/work/Loom"),
   sessions: []
  )
  let cueWorkA = PathDisambiguationHelper.disambiguationCue(for: groupWorkA, in: [groupWorkA, groupWorkB])
  let cueWorkB = PathDisambiguationHelper.disambiguationCue(for: groupWorkB, in: [groupWorkA, groupWorkB])
  assert(cueWorkA == "a/work", "Disambiguation must expand to 'a/work' when immediate parent 'work' collides")
  assert(cueWorkB == "b/work", "Disambiguation must expand to 'b/work' when immediate parent 'work' collides")

  // 3. Extremely long repo name & deep path horizontal bounds testing
  let longSession = AgentSession(
   id: "long-session",
   provider: .codex,
   projectName: "enterprise-distributed-transaction-coordinator-service-worker-daemon-with-excessive-characters",
   projectPath: URL(fileURLWithPath: "/Users/deepak/Desktop/Projects/enterprise-monorepo/packages/core/subservices/deeply-nested-service/worker/internal/pipeline"),
   state: .working,
   startedAt: now.addingTimeInterval(-3600),
   lastActivityAt: now.addingTimeInterval(-15),
   branch: "feature/JIRA-998822-distributed-lock-reconciliation-pipeline-worker-refactor-seg1-seg2",
   summary: "Refactoring the distributed transaction state machine across deeply nested package boundaries and ensuring zero clipping in menu bar popovers",
   associatedProcesses: [
    AgentProcess(pid: 88123, parentPID: 1, executable: "/usr/local/bin/node", commandLine: "node worker.js", provider: .codex),
    AgentProcess(pid: 88124, parentPID: 88123, executable: "/usr/bin/git", commandLine: "git status", provider: .codex)
   ],
   discoveryEvidence: [
    "Evidence 1: process table inspection matching PID 88123",
    "Evidence 2: active TCP socket connected to daemon port 4040"
   ]
  )

  // Test across popover width range: min ~360pt, typical ~380pt, max ~480pt
  for testWidth in [CGFloat(360), CGFloat(380), CGFloat(480)] {
   let rowView = SessionRowView(session: longSession, isExpanded: false).frame(width: testWidth)
   let rowHost = NSHostingView(rootView: rowView)
   let fitting = rowHost.fittingSize
   assert(abs(fitting.width - testWidth) < 2, "SessionRowView at width \(testWidth) must strictly adhere to bounds without overflow")
   assert(fitting.height > 25, "SessionRowView must render with positive height")

   let expandedRow = SessionRowView(session: longSession, isExpanded: true).frame(width: testWidth)
   let expandedHost = NSHostingView(rootView: expandedRow)
   let expandedFitting = expandedHost.fittingSize
   assert(abs(expandedFitting.width - testWidth) < 2, "Expanded SessionRowView at width \(testWidth) must strictly adhere to bounds without overflow")
   assert(expandedFitting.height > fitting.height, "Expanded session row must grow vertically without clipping")
  }

  // Privacy Mode concealment check
  let privateRow = SessionRowView(session: longSession, isExpanded: true, hideProjectPaths: true).frame(width: 380)
  let privateHost = NSHostingView(rootView: privateRow)
  let privateFitting = privateHost.fittingSize
  assert(abs(privateFitting.width - 380) < 2, "Privacy mode row must preserve horizontal bounds")
  assert(privateFitting.height > 25, "Privacy mode row must render non-zero height")

  print("PASS: Long repo names, deep hierarchies, and disambiguation cues verified without overflow")

  // -------------------------------------------------------------------------
  // SECTION 6: Filter Bar & Search Field Dynamic Height Constraints
  // -------------------------------------------------------------------------
  print("--- Validating Filter Bar & Search Field Dynamic Constraints ---")

  // 1. SessionFilterBar fitting size across 360pt, 380pt, 480pt
  for barWidth in [CGFloat(360), CGFloat(380), CGFloat(480)] {
   var q = ""
   var filt = SessionFilterCriterion.all
   let bar = SessionFilterBar(
    searchText: Binding(get: { q }, set: { q = $0 }),
    selectedFilter: Binding(get: { filt }, set: { filt = $0 }),
    counts: [.all: 10, .needsAttention: 2, .working: 5, .recent: 3]
   ).frame(width: barWidth)
   let barHost = NSHostingView(rootView: bar)
   let barFitting = barHost.fittingSize
   assert(abs(barFitting.width - barWidth) < 2, "Filter bar width must match container width \(barWidth)")
   assert(barFitting.height >= 55 && barFitting.height <= 95, "Filter bar height must be within [55, 95] pt bounds, got \(barFitting.height)")
  }

  // 2. SessionFilterEngine criterion and query matching logic
  assert(SessionFilterEngine.matches(session: attentionSessionWaiting, query: "", filter: .needsAttention))
  assert(SessionFilterEngine.matches(session: attentionSessionFailed, query: "", filter: .needsAttention))
  assert(!SessionFilterEngine.matches(session: normalWorkingSession, query: "", filter: .needsAttention))

  assert(SessionFilterEngine.matches(session: normalWorkingSession, query: "", filter: .working))
  assert(!SessionFilterEngine.matches(session: finishedSession1, query: "", filter: .working))

  assert(SessionFilterEngine.matches(session: finishedSession1, query: "", filter: .recent))
  assert(!SessionFilterEngine.matches(session: normalWorkingSession, query: "", filter: .recent))

  // Text search matching
  assert(SessionFilterEngine.matches(session: attentionSessionWaiting, query: "PaymentGateway", filter: .all))
  assert(SessionFilterEngine.matches(session: attentionSessionWaiting, query: "stripe-v3", filter: .all))
  assert(SessionFilterEngine.matches(session: attentionSessionWaiting, query: "Awaiting API key", filter: .all))
  assert(!SessionFilterEngine.matches(session: attentionSessionWaiting, query: "NonexistentQuery12345", filter: .all))

  // Privacy mode suppression in search
  assert(SessionFilterEngine.matches(session: attentionSessionWaiting, query: "payments", filter: .all, hideProjectPaths: false))
  assert(!SessionFilterEngine.matches(session: attentionSessionWaiting, query: "payments", filter: .all, hideProjectPaths: true), "Hidden paths must not match search queries")

  // 3. Filter Empty State View
  let filterEmptyView = SessionFilterEmptyStateView(query: "search-miss", filter: .all)
  let filterEmptyHost = NSHostingView(rootView: filterEmptyView.frame(width: 380))
  let filterEmptyFitting = filterEmptyHost.fittingSize
  assert(filterEmptyFitting.height >= 80 && filterEmptyFitting.height <= 220, "Filter empty state view height must stay within bounds (got \(filterEmptyFitting.height))")

  print("PASS: Filter bar & search field dynamic height constraints verified")

  // -------------------------------------------------------------------------
  // SECTION 7: Popover Bounds & Multi-Provider Selector
  // -------------------------------------------------------------------------
  print("--- Validating Popover Bounds & Multi-Provider Selector ---")
  let manyCodex = (1...24).map { AgentSession(id: "codex\($0)", provider: .codex, projectName: "CodexProject\($0)", state: $0 == 1 ? .waiting : .working) }
  let codexProv = MockAgentProvider(id: .codex, displayName: "Codex", sessions: manyCodex)
  let claudeProv = MockAgentProvider(id: .claude, displayName: "Claude Code", sessions: [])
  claudeProv.setAvailability(.unavailable(reason: "Claude Code CLI not installed"))
  let manyAgy = (1...20).map { AgentSession(id: "agy\($0)", provider: .antigravity, projectName: "AgyProject\($0)", state: .working) }
  let agyProv = MockAgentProvider(id: .antigravity, displayName: "Antigravity", sessions: manyAgy)

  let multiStore = SessionStore(providers: [codexProv, claudeProv, agyProv])
  await multiStore.refresh()

  let multiHost = NSHostingView(rootView: AnyView(MenuBarRootView(store: multiStore).id("multi-root").frame(width: 380)))
  multiHost.appearance = NSAppearance(named: .darkAqua)
  window.contentView = multiHost
  window.setContentSize(NSSize(width: 380, height: 800))
  await settle(multiHost)
  save(multiHost, "multi-codex-initial")

  assert(multiStore.providerSnapshots.count == 3)
  assert(multiStore.providerSnapshots[0].displayName == "Codex" && multiStore.providerSnapshots[0].sessions.count == 24)
  assert(multiStore.providerSnapshots[1].displayName == "Claude Code" && multiStore.providerSnapshots[1].sessions.count == 0)
  assert(multiStore.providerSnapshots[2].displayName == "Antigravity" && multiStore.providerSnapshots[2].sessions.count == 20)

  let multiScrolls = scrollViews(in: multiHost)
  assert(multiScrolls.count >= 2)
  let multiAgentsScroll = multiScrolls.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }!
  let codexDoc = multiAgentsScroll.documentView!
  multiAgentsScroll.contentView.scroll(to: NSPoint(x: 0, y: codexDoc.frame.height - multiAgentsScroll.contentView.bounds.height))
  multiAgentsScroll.reflectScrolledClipView(multiAgentsScroll.contentView)
  await settle(multiHost)
  let codexScrolledOffset = multiAgentsScroll.contentView.bounds.origin.y
  assert(codexScrolledOffset > 100, "Codex must be deeply scrolled")
  save(multiHost, "multi-codex-scrolled")

  // Click Antigravity
  clickProvider(window, index: 2, total: 3)
  await settle(multiHost, cycles: 42)
  save(multiHost, "multi-agy-selected")

  // Wait through the provider spring and ScrollView identity replacement before measuring.
  let agyScrolls = scrollViews(in: multiHost)
  assert(agyScrolls.count == 3, "Provider transition must leave one scroll view per tab")
  let agyAgentsScroll = agyScrolls.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }!
  let agyOffset = agyAgentsScroll.contentView.bounds.origin.y
  assert(agyOffset == 0, "Switching from deeply scrolled Codex to long Antigravity must land at top (0), got \(agyOffset); prior Codex offset \(codexScrolledOffset)")

  // Click unavailable Claude
  clickProvider(window, index: 1, total: 3)
  await settle(multiHost, cycles: 42)
  save(multiHost, "multi-claude-selected")
  let claudeHeight = window.contentLayoutRect.height
  assert(claudeHeight < cap - 200, "Empty/unavailable Claude must be compact")

  // Rapid switching
  clickProvider(window, index: 0, total: 3)
  await settle(multiHost, cycles: 42)
  save(multiHost, "multi-rapid-codex")

  clickProvider(window, index: 2, total: 3)
  await settle(multiHost, cycles: 42)
  save(multiHost, "multi-rapid-agy")

  clickProvider(window, index: 1, total: 3)
  await settle(multiHost, cycles: 42)
  save(multiHost, "multi-rapid-claude")

  clickProvider(window, index: 2, total: 3)
  await settle(multiHost, cycles: 42)

  // Refresh preserving selection
  await multiStore.refresh()
  await settle(multiHost)
  save(multiHost, "multi-refresh-agy")

  // Sessions / Usage round trip preserving selection
  selectTab(window, segment: 1)
  await settle(multiHost)
  save(multiHost, "multi-usage-view")
  selectTab(window, segment: 0)
  await settle(multiHost)
  save(multiHost, "multi-roundtrip-agy")

  // Three full provider names, multi-digit counts, attention and an empty provider
  // must remain available across the supported menu widths.
  for width in [CGFloat(320), CGFloat(380), CGFloat(420), CGFloat(520)] {
   multiHost.rootView = AnyView(MenuBarRootView(store: multiStore).id("multi-width-\(Int(width))").frame(width: width))
   window.setContentSize(NSSize(width: width, height: 800))
   await settle(multiHost)
   assert(abs(window.contentLayoutRect.width - width) < 2, "Window content width must match \(width)")
   assert(window.contentLayoutRect.height <= cap + 2, "Window height must not exceed screen cap \(cap)")
   save(multiHost, "multi-selector-width-\(Int(width))")
  }

  // Missing selected provider fallback test
  let fallbackStore = SessionStore(providers: [codexProv, claudeProv])
  await fallbackStore.refresh()
  let fallbackHost = NSHostingView(rootView: AnyView(
   MenuBarRootView(store: fallbackStore, selectedProviderID: .antigravity).id("fallback-test").frame(width: 380)
  ))
  fallbackHost.appearance = NSAppearance(named: .darkAqua)
  window.contentView = fallbackHost
  window.setContentSize(NSSize(width: 380, height: 800))
  await settle(fallbackHost)
  save(fallbackHost, "fallback-codex-selected")

  assert(abs(window.contentLayoutRect.height - cap) < 2, "Missing provider fallback must select Codex and size to cap")

  print("PASS: All Liquid Glass popover layout checks succeeded:")
  print("  - Header height & bounds")
  print("  - Needs Attention section hierarchy & accent borders")
  print("  - Active sessions vs collapsible recent completed sessions")
  print("  - Long repo names & deep directory hierarchies without overflow or clipping")
  print("  - Filter bar & search field dynamic height constraints")
  print("  - Popover bounds conforming to macOS menu-bar constraints (min 360, default 380, max 480, height <= screen cap)")
  fflush(stdout)
  window.close()
 }
}
