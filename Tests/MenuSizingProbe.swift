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
 @MainActor static func settle(_ host:NSView) async { for _ in 0..<35 { host.layoutSubtreeIfNeeded(); try? await Task.sleep(nanoseconds: 20_000_000) } }
 @MainActor static func scrollView(in view: NSView) -> NSScrollView? {
  if let scroll = view as? NSScrollView { return scroll }
  return view.subviews.compactMap { scrollView(in: $0) }.first
 }
 @MainActor static func save(_ host:NSView,_ name:String) {
  guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { fatalError("bitmap") }; host.cacheDisplay(in:host.bounds,to:rep)
  try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/loom-menu-\(name).png"))
 }
 @MainActor static func click(_ window:NSWindow, top:CGFloat, x:CGFloat = 170) {
  let point=NSPoint(x:x,y:window.contentLayoutRect.height-top)
  for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
   let event=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
   window.sendEvent(event)
  }
 }
 @MainActor static func selectTab(_ window:NSWindow, segment:Int) {
  let width=window.contentLayoutRect.width
  let tabWidth = width / 3.0
  let x = tabWidth * CGFloat(segment) + tabWidth / 2.0
  click(window,top:92,x:x)
 }
 @MainActor static func clickProvider(_ window:NSWindow, index:Int, total:Int) {
  let width=window.contentLayoutRect.width
  let totalSpacing=CGFloat(total - 1)*6
  let buttonWidth=(width - 24 - totalSpacing)/CGFloat(total)
  let x=12 + CGFloat(index)*(buttonWidth + 6) + buttonWidth/2
  click(window,top:130,x:x)
 }
 @MainActor static func scrollViews(in view: NSView) -> [NSScrollView] {
  if let scroll = view as? NSScrollView { return [scroll] }
  return view.subviews.flatMap { scrollViews(in: $0) }
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
  if let view = root as? NSView {
   if let tf = view as? NSTextField, !tf.stringValue.isEmpty { results.append(tf.stringValue) }
   for sub in view.subviews { results.append(contentsOf: findStrings(in: sub)) }
  }
  return results
 }
 @MainActor static func main() async {
  NSApplication.shared.setActivationPolicy(.accessory)
  NSApplication.shared.applicationIconImage=NSImage(contentsOfFile:"Resources/LoomIconMaster.png")
  let now=Date()
  let session=AgentSession(id:"s",provider:.codex,projectName:"Loom",projectPath:URL(fileURLWithPath:FileManager.default.currentDirectoryPath),state:.working,startedAt:now.addingTimeInterval(-600),lastActivityAt:now.addingTimeInterval(-60),branch:"main",summary:"Checking the aligned header and independent tabs")
  let usage=ProviderUsageSnapshot(providerID:.codex,planType:"Plus",primaryBucket:UsageBucket(identifier:"5h",label:"5-hour window",usedFraction:0.28,resetsAt:now.addingTimeInterval(8280)),secondaryBucket:UsageBucket(identifier:"week",label:"Weekly window",usedFraction:0.36,resetsAt:now.addingTimeInterval(367200)),additionalGroups:[UsageGroup(identifier:"models",label:"Other models",buckets:[UsageBucket(identifier:"other",label:"Additional model",usedFraction:nil)])])
  let provider=MockAgentProvider(id:.codex,displayName:"Codex",sessions:[session],usage:usage)
  let store=SessionStore(providers:[provider]);await store.refresh()
  let host=NSHostingView(rootView:AnyView(MenuBarRootView(store:store).frame(width:380)))
  host.appearance=NSAppearance(named:.darkAqua)
  let window=NSWindow(contentRect:NSRect(x:200,y:200,width:380,height:800),styleMask:[.borderless],backing:.buffered,defer:false)
  window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil)
  await settle(host);let agents=window.contentLayoutRect.height;print("Agents collapsed \(agents)");fflush(stdout);save(host,"tabs-agents")
  click(window,top:250);await settle(host);let expanded=window.contentLayoutRect.height;save(host,"tabs-expanded")
  print("Agents expanded \(expanded)");fflush(stdout);assert(expanded>agents,"Session disclosure must grow Agents")
  selectTab(window,segment:1);await settle(host);let usageHeight=window.contentLayoutRect.height
  print("Usage height \(usageHeight)");fflush(stdout);save(host,"tabs-usage")
  selectTab(window,segment:2);await settle(host);let storageHeight=window.contentLayoutRect.height
  print("Storage height \(storageHeight)");fflush(stdout);save(host,"tabs-storage")
  host.appearance=NSAppearance(named:.aqua);await settle(host);save(host,"tabs-storage-light")
  host.appearance=NSAppearance(named:.darkAqua);await settle(host)
  assert(storageHeight>0,"Storage tab must size correctly")
  selectTab(window,segment:1);await settle(host)
  assert(usageHeight<expanded,"Usage must size independently of expanded Agents")
  click(window,top:310,x:20);await settle(host);let modelsHeight=window.contentLayoutRect.height
  assert(modelsHeight>usageHeight,"Additional limits disclosure must grow Usage")
  selectTab(window,segment:0);await settle(host)
  assert(abs(window.contentLayoutRect.height-expanded)<2)
  selectTab(window,segment:1);await settle(host)
  assert(abs(window.contentLayoutRect.height-modelsHeight)<2,"Usage disclosure must survive tab switch")
  click(window,top:310,x:20);await settle(host);assert(abs(window.contentLayoutRect.height-usageHeight)<2)
  selectTab(window,segment:0);await settle(host)
  assert(abs(window.contentLayoutRect.height-expanded)<2,"Agents expansion must survive tab round trip")
  click(window,top:250);await settle(host);assert(abs(window.contentLayoutRect.height-agents)<2)
  for width in [CGFloat(320),CGFloat(520)] {
   host.rootView=AnyView(MenuBarRootView(store:store).frame(width:width))
   window.setContentSize(NSSize(width:width,height:800));await settle(host)
   print("Width \(width), actual \(window.contentLayoutRect.size)")
   assert(abs(window.contentLayoutRect.width-width)<2)
   save(host,"tabs-header-\(Int(width))")
  }
  host.rootView=AnyView(MenuBarRootView(store:store).frame(width:380));window.setContentSize(NSSize(width:380,height:800));await settle(host)
  let many=(1...24).map { AgentSession(id:"s\($0)",provider:.codex,projectName:"Project \($0)",state:.working) }
  provider.setSessions(many);await store.refresh();await settle(host)
  let cap=window.screen.map { $0.visibleFrame.height-16 } ?? 720
  assert(window.contentLayoutRect.height<=cap+2);assert(window.contentLayoutRect.height>expanded)
  let scrolls=scrollViews(in:host);assert(scrolls.count>=3,"All tab scroll views must remain alive")
  let agentsScroll=scrolls.max { ($0.documentView?.frame.height ?? 0)<($1.documentView?.frame.height ?? 0) }!
  let usageScroll=scrolls.first { $0 !== agentsScroll }!
  let document=agentsScroll.documentView!
  agentsScroll.contentView.scroll(to:NSPoint(x:0,y:document.frame.height-agentsScroll.contentView.bounds.height));agentsScroll.reflectScrolledClipView(agentsScroll.contentView);await settle(host)
  let agentsOffset=agentsScroll.contentView.bounds.origin.y;assert(agentsOffset>0);save(host,"tabs-overflow")
  selectTab(window,segment:1);await settle(host)
  assert(window.contentLayoutRect.height<cap-100,"Short Usage should shrink a long Agents menu")
  assert(usageScroll.contentView.bounds.origin.y==0)
  selectTab(window,segment:0);await settle(host)
  assert(abs(agentsScroll.contentView.bounds.origin.y-agentsOffset)<2,"Tab switches must preserve Agents scroll offset")
  print("Screen cap \(cap), preserved Agents offset \(agentsOffset)")
  let buckets=(1...20).map { UsageBucket(identifier:"limit\($0)",label:"Model \($0)",usedFraction:0.2) }
  provider.setUsage(ProviderUsageSnapshot(providerID:.codex,primaryBucket:usage.primaryBucket,secondaryBucket:usage.secondaryBucket,additionalGroups:[UsageGroup(identifier:"models",label:"Other models",buckets:buckets)]));await store.refresh();await settle(host)
  selectTab(window,segment:1);await settle(host);click(window,top:310,x:20);await settle(host)
  assert(window.contentLayoutRect.height<=cap+2)
  let usageDocument=usageScroll.documentView!
  usageScroll.contentView.scroll(to:NSPoint(x:0,y:usageDocument.frame.height-usageScroll.contentView.bounds.height));usageScroll.reflectScrolledClipView(usageScroll.contentView);await settle(host)
  let usageOffset=usageScroll.contentView.bounds.origin.y;assert(usageOffset>0);save(host,"tabs-usage-overflow")
  selectTab(window,segment:0);await settle(host);assert(abs(agentsScroll.contentView.bounds.origin.y-agentsOffset)<2)
  selectTab(window,segment:1);await settle(host);assert(abs(usageScroll.contentView.bounds.origin.y-usageOffset)<2,"Usage scroll offset must survive tab round trip")
  print("Usage disclosure and independent scroll offset \(usageOffset) preserved")
  provider.setUsage(usage);await store.refresh();selectTab(window,segment:0);await settle(host)
  provider.setSessions([]);await store.refresh();await settle(host);let empty=window.contentLayoutRect.height;assert(empty<agents);save(host,"tabs-empty")
  provider.setSessions([session]);async let a:Void=store.refresh();async let b:Void=store.refresh();_=await(a,b);await settle(host);assert(abs(window.contentLayoutRect.height-agents)<2)
  print("Empty \(empty); overlapping refresh restored Agents \(window.contentLayoutRect.height)")
  let agy=MockAgentProvider(id:.antigravity,displayName:"Antigravity",sessions:[AgentSession(id:"a",provider:.antigravity,projectName:"Experiment",state:.finished)])
  let referenceStore=SessionStore(providers:[provider,agy]);await referenceStore.refresh()
  host.rootView=AnyView(MenuBarRootView(store:referenceStore,expandedSessionIds:["s"]).id("reference").frame(width:420));window.setContentSize(NSSize(width:420,height:800));await settle(host)
  save(host,"tabs-reference-agents-dark")
  selectTab(window,segment:1);await settle(host);save(host,"tabs-reference-usage-dark")
  host.appearance=NSAppearance(named:.aqua);await settle(host);save(host,"tabs-reference-usage-light")
  selectTab(window,segment:0);await settle(host);save(host,"tabs-reference-agents-light")
  selectTab(window,segment:2);await settle(host);save(host,"tabs-reference-storage-light")
  host.appearance=NSAppearance(named:.darkAqua);await settle(host);save(host,"tabs-reference-storage-dark")
  provider.setUsage(usage.markedStale(error:"Local usage source unavailable; showing cached limits."));await referenceStore.refresh()
  host.appearance=NSAppearance(named:.darkAqua);selectTab(window,segment:1);await settle(host);save(host,"tabs-stale")
  provider.setAvailability(.unavailable(reason:"Provider is not installed"));await referenceStore.refresh();await settle(host);save(host,"tabs-unavailable")

  // Multi-provider fixture tests with unequal counts and separate SessionStore fixtures
  let manyCodex = (1...24).map { AgentSession(id:"codex\($0)",provider:.codex,projectName:"CodexProject\($0)",state:.working) }
  let codexProv = MockAgentProvider(id:.codex,displayName:"Codex",sessions:manyCodex)
  let claudeProv = MockAgentProvider(id:.claude,displayName:"Claude",sessions:[])
  claudeProv.setAvailability(.unavailable(reason:"Claude Code CLI not installed"))
  let manyAgy = (1...20).map { AgentSession(id:"agy\($0)",provider:.antigravity,projectName:"AgyProject\($0)",state:.working) }
  let agyProv = MockAgentProvider(id:.antigravity,displayName:"Antigravity",sessions:manyAgy)

  let multiStore = SessionStore(providers:[codexProv,claudeProv,agyProv])
  await multiStore.refresh()

  let multiHost = NSHostingView(rootView:AnyView(MenuBarRootView(store:multiStore).id("multi-root").frame(width:380)))
  multiHost.appearance = NSAppearance(named:.darkAqua)
  window.contentView = multiHost
  window.setContentSize(NSSize(width:380,height:800))
  await settle(multiHost)
  save(multiHost,"multi-codex-initial")

  // Assert store counts and snapshot labels
  assert(multiStore.providerSnapshots.count == 3)
  assert(multiStore.providerSnapshots[0].displayName == "Codex" && multiStore.providerSnapshots[0].sessions.count == 24)
  assert(multiStore.providerSnapshots[1].displayName == "Claude" && multiStore.providerSnapshots[1].sessions.count == 0)
  assert(multiStore.providerSnapshots[2].displayName == "Antigravity" && multiStore.providerSnapshots[2].sessions.count == 20)

  let axAvailable = !findStrings(in: multiHost).isEmpty
  if !axAvailable {
   print("CHECK NOT RUN: accessibility content traversal unavailable when tree empty")
   fflush(stdout)
  } else {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("Codex, 24 sessions") || $0.contains("Codex") }), "Codex button label with count 24")
   assert(axDesc.contains(where: { $0.contains("Claude, 0 sessions") || $0.contains("Claude") }), "Claude button label with count 0")
   assert(axDesc.contains(where: { $0.contains("Antigravity, 20 sessions") || $0.contains("Antigravity") }), "Antigravity button label with count 20")
   assert(axDesc.contains(where: { $0.contains("CodexProject1") }), "Codex visible sessions")
  }

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

  // Click Antigravity (another long provider with 20 sessions)
  clickProvider(window, index: 2, total: 3); await settle(multiHost)
  save(multiHost, "multi-agy-selected")

  // Switching from deeply scrolled Codex to another long provider must land at top (0)
  let agyScrolls = scrollViews(in: multiHost)
  let agyAgentsScroll = agyScrolls.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }!
  let agyOffset = agyAgentsScroll.contentView.bounds.origin.y
  assert(agyOffset == 0, "Switching from deeply scrolled Codex to long Antigravity must land at top (0), not stale Codex offset \(codexScrolledOffset)")

  if axAvailable {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("AgyProject1") }), "Antigravity session content must be visible")
   assert(!axDesc.contains(where: { $0.contains("CodexProject1") }), "Codex sessions must NOT appear when Antigravity is selected")
  }

  // Click empty/unavailable Claude
  clickProvider(window, index: 1, total: 3); await settle(multiHost)
  save(multiHost, "multi-claude-selected")
  let claudeHeight = window.contentLayoutRect.height
  assert(claudeHeight < cap - 200, "Empty/unavailable Claude must be compact")
  if axAvailable {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("Claude Code CLI not installed") || $0.contains("Unavailable") || $0.contains("Claude") }), "Claude unavailability notice visible")
   assert(!axDesc.contains(where: { $0.contains("CodexProject1") }))
   assert(!axDesc.contains(where: { $0.contains("AgyProject1") }))
  }

  // Rapid/repeated switching
  clickProvider(window, index: 0, total: 3); await settle(multiHost)
  save(multiHost, "multi-rapid-codex")
  if axAvailable {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("CodexProject1") }), "Codex content visible again")
  }

  clickProvider(window, index: 2, total: 3); await settle(multiHost)
  save(multiHost, "multi-rapid-agy")
  if axAvailable {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("AgyProject1") }), "Antigravity visible on rapid switch")
  }

  clickProvider(window, index: 1, total: 3); await settle(multiHost)
  save(multiHost, "multi-rapid-claude")
  if axAvailable {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("Claude Code CLI not installed") || $0.contains("Unavailable") || $0.contains("Claude") }))
  }

  clickProvider(window, index: 2, total: 3); await settle(multiHost)
  save(multiHost, "multi-rapid-agy-final")

  // Refresh preserving selection
  await multiStore.refresh(); await settle(multiHost)
  save(multiHost, "multi-refresh-agy")
  if axAvailable {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("AgyProject1") }), "Selection of Antigravity must persist across refresh")
   assert(!axDesc.contains(where: { $0.contains("CodexProject1") }))
  }

  // Sessions / Usage round trip preserving selection
  selectTab(window, segment: 1); await settle(multiHost)
  save(multiHost, "multi-usage-view")
  selectTab(window, segment: 0); await settle(multiHost)
  save(multiHost, "multi-roundtrip-agy")
  if axAvailable {
   let axDesc = findStrings(in: multiHost)
   assert(axDesc.contains(where: { $0.contains("AgyProject1") }), "Antigravity selection must survive tab round trip")
   assert(!axDesc.contains(where: { $0.contains("CodexProject1") }))
  }

  // Width checks (320pt and 520pt)
  for width in [CGFloat(320), CGFloat(520)] {
   multiHost.rootView = AnyView(MenuBarRootView(store: multiStore).id("multi-width-\(Int(width))").frame(width: width))
   window.setContentSize(NSSize(width: width, height: 800)); await settle(multiHost)
   assert(abs(window.contentLayoutRect.width - width) < 2)
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
  if axAvailable {
   let fallbackAX = findStrings(in: fallbackHost)
   assert(fallbackAX.contains(where: { $0.contains("CodexProject1") || $0.contains("Codex") }), "Missing selected provider must gracefully fall back to first provider (Codex)")
   assert(!fallbackAX.contains(where: { $0.contains("AgyProject") }), "Antigravity must not exist in fallback view")
  }

  print("PASS: aligned headers, real text-tab and disclosure clicks, independent sizing, persistent Agents scroll, empty/overlapping refresh, missing/stale/unavailable quota fixtures, multi-provider selector, and missing provider fallback."); fflush(stdout); window.close()
 }
}
