// The default browser. A link to a saved site opens straight in its profile;
// any other link (or any link while Option is held) shows a popup to pick one.
import AppKit

struct Browser {
    let name: String       // app name, as `open -a` knows it
    let bundleId: String
    let support: String    // folder holding "Local State"
}

let browsers = [
    Browser(name: "Comet", bundleId: "ai.perplexity.comet", support: "Comet"),
    Browser(name: "Google Chrome", bundleId: "com.google.Chrome", support: "Google/Chrome"),
]

let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
let finickyConfig = home + "/.finicky.js"
let storeDir = home + "/Library/Application Support/Profiley"
let sitesFile = storeDir + "/sites.json"

// `defaults write com.kamalkhatwani.profiley browser "Google Chrome"`, else the one an old
// ~/.finicky.js named (`const pickerBrowser = "...";`), else the first one installed.
let browser: Browser = {
    if let name = UserDefaults.standard.string(forKey: "browser"),
       let b = browsers.first(where: { $0.name == name }) { return b }
    if let src = try? String(contentsOfFile: finickyConfig, encoding: .utf8),
       let m = src.range(of: #"const pickerBrowser = "([^"]+)""#, options: .regularExpression) {
        let name = src[m].split(separator: "\"")[1]
        if let b = browsers.first(where: { $0.name == name }) { return b }
    }
    return browsers.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil } ?? browsers[0]
}()

let browserSupport = home + "/Library/Application Support/" + browser.support
let cometResources = "/Applications/Comet.app/Contents/Frameworks/Comet Framework.framework/Resources/"
// Resource ids of Comet's avatar art, found by dumping its packs (Comet 154).
// Picked avatars: IDR_PROFILE_AVATAR_N is id avatarBaseId + N in chrome_200_percent.pak.
// The default avatar is a separate image in chrome_100_percent.pak.
let avatarBaseId = 14386
let defaultAvatarId = 338

// Saved sites: domain -> profile name. A domain also covers its subdomains.
func loadSites() -> [String: String] {
    guard let d = FileManager.default.contents(atPath: sitesFile),
          let json = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
    return json
}

func saveSites(_ sites: [String: String]) {
    try? FileManager.default.createDirectory(atPath: storeDir, withIntermediateDirectories: true)
    if let d = try? JSONSerialization.data(withJSONObject: sites, options: [.prettyPrinted, .sortedKeys]) {
        try? d.write(to: URL(fileURLWithPath: sitesFile), options: .atomic)
    }
}

// First run: bring over the sites an older Finicky-based setup saved in ~/.finicky.js.
func migrateFromFinicky() {
    guard !FileManager.default.fileExists(atPath: sitesFile) else { return }
    var sites: [String: String] = [:]
    if let src = try? String(contentsOfFile: finickyConfig, encoding: .utf8),
       let a = src.range(of: "const learned = "), let b = src.range(of: ";\n// learned:end"),
       let json = try? JSONSerialization.jsonObject(with: Data(src[a.upperBound..<b.lowerBound].utf8)) as? [String: String] {
        sites = json
    }
    saveSites(sites)
}

// "https://www.App.Example.com/x" or "*.example.com" -> "app.example.com" / "example.com".
func siteName(_ s: String) -> String {
    var h = s.trimmingCharacters(in: .whitespaces).lowercased()
    if let u = URL(string: h), let host = u.host { h = host }
    else if let u = URL(string: "https://" + h), let host = u.host { h = host }
    for prefix in ["*.", "www."] where h.hasPrefix(prefix) { h.removeFirst(prefix.count) }
    return h
}

// The saved site covering this host: itself or its closest parent domain.
func savedMatch(_ host: String, in sites: [String: String]) -> (site: String, profile: String)? {
    var h = host
    while !h.isEmpty {
        if let p = sites[h] { return (h, p) }
        guard let dot = h.firstIndex(of: ".") else { break }
        h = String(h[h.index(after: dot)...])
    }
    return nil
}

func isDefaultBrowser() -> Bool {
    NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?.standardizedFileURL
        == Bundle.main.bundleURL.standardizedFileURL
}

struct Profile {
    let dir: String
    let name: String
    let color: NSColor
    let avatar: NSImage?
}

func argb(_ v: Any?) -> NSColor? {
    guard let n = (v as? NSNumber)?.int64Value else { return nil }
    let u = UInt32(truncatingIfNeeded: n)
    return NSColor(srgbRed: CGFloat((u >> 16) & 0xff) / 255, green: CGFloat((u >> 8) & 0xff) / 255,
                   blue: CGFloat(u & 0xff) / 255, alpha: 1)
}

func pakImage(_ pak: String, _ id: Int) -> NSImage? {
    guard browser.name == "Comet", let d = FileManager.default.contents(atPath: cometResources + pak), d.count > 12 else { return nil }
    func u16(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
    func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
    guard u32(0) == 5 else { return nil }
    let count = u16(8)
    for i in 0..<count where u16(12 + i * 6) == id {
        let start = u32(14 + i * 6), end = u32(20 + i * 6)
        return NSImage(data: d.subdata(in: start..<end))
    }
    return nil
}

func loadProfiles() -> [Profile] {
    guard let data = FileManager.default.contents(atPath: browserSupport + "/Local State"),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]]
    else { return [] }
    return cache.sorted { ($0.value["name"] as? String ?? $0.key).localizedStandardCompare($1.value["name"] as? String ?? $1.key) == .orderedAscending }.map { dir, info in
        var avatar: NSImage?
        if let pic = info["gaia_picture_file_name"] as? String, !pic.isEmpty, (info["use_gaia_picture"] as? Bool) == true {
            avatar = NSImage(contentsOfFile: "\(browserSupport)/\(dir)/\(pic)")
        } else if (info["is_using_default_avatar"] as? Bool) == true {
            avatar = pakImage("chrome_100_percent.pak", defaultAvatarId)
        } else if let icon = info["avatar_icon"] as? String,
                  let n = Int(icon.replacingOccurrences(of: "chrome://theme/IDR_PROFILE_AVATAR_", with: "")) {
            avatar = pakImage("chrome_200_percent.pak", avatarBaseId + n)
        }
        return Profile(dir: dir, name: info["name"] as? String ?? dir,
                       color: argb(info["profile_color_seed"]) ?? .systemGray, avatar: avatar)
    }
}

final class AvatarView: NSView {
    let profile: Profile
    init(_ p: Profile) { profile = p; super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 72)) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 3
        let inner = bounds.insetBy(dx: 6, dy: 6)
        if let img = profile.avatar {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: inner).addClip()
            img.draw(in: inner)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            profile.color.setFill()
            NSBezierPath(ovalIn: inner).fill()
        }
        let letter = NSAttributedString(string: String(profile.name.prefix(1)).uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white,
            .shadow: { let s = NSShadow(); s.shadowBlurRadius = 3; s.shadowColor = .black.withAlphaComponent(0.5); return s }(),
        ])
        let size = letter.size()
        letter.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        NSColor.white.withAlphaComponent(0.25).setStroke()
        ring.stroke()
    }
}

final class ProfileButton: NSButton {
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

final class Picker: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NSPanel?
    var url = ""
    var host = ""
    var remember: NSButton!
    var savedLabel: NSTextField!
    var profiles: [Profile] = []
    var savedSite: String?
    var gotURL = false
    var pending: [String] = []
    var manager: NSWindow?
    var addField: NSTextField?
    var addPop: NSPopUpButton?

    func applicationDidFinishLaunching(_ n: Notification) {
        migrateFromFinicky()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
            show(url: "https://example.com/some/page", preview: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--manage-preview"), i + 1 < args.count {
            showManager(preview: args[i + 1])
            return
        }
        if args.contains("--make-default") {
            makeDefault { NSApp.terminate(nil) }
            return
        }
        // Opened by hand rather than by a link: show the saved sites.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !self.gotURL && self.panel == nil { self.showManager(preview: nil) } }
    }

    // Links (and .html files) sent to us as the default browser.
    func application(_ app: NSApplication, open urls: [URL]) {
        gotURL = true
        let forcePicker = NSEvent.modifierFlags.contains(.option)
        let sites = loadSites()
        let all = loadProfiles()
        for u in urls {
            if !forcePicker, let host = u.host.map(siteName), let m = savedMatch(host, in: sites),
               let p = all.first(where: { $0.name == m.profile }) {
                openInBrowser(u.absoluteString, p)
            } else {
                pending.append(u.absoluteString)
            }
        }
        if panel == nil { next() }
    }

    // Shows the popup for the next waiting link, or quits once nothing is left on screen.
    func next() {
        panel?.orderOut(nil)
        panel = nil
        if !pending.isEmpty { show(url: pending.removeFirst(), preview: nil) }
        else if manager == nil { NSApp.terminate(nil) }
    }

    @objc func cancel() { next() }

    func show(url: String, preview: String?) {
        self.url = url
        host = URL(string: url)?.host.map(siteName) ?? ""
        profiles = loadProfiles()

        let content = NSView()
        let title = NSTextField(labelWithString: "Open \(host.isEmpty ? "link" : host) in")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let sub = NSTextField(labelWithString: url)
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingMiddle

        let row = NSStackView()
        row.spacing = 12
        for (i, p) in profiles.enumerated() {
            row.addArrangedSubview(card(p, index: i))
        }

        remember = NSButton(checkboxWithTitle: "Always open \(host) this way", target: nil, action: nil)
        remember.state = .off
        remember.font = .systemFont(ofSize: 12)
        var views: [NSView] = [title, sub, row, remember]
        savedSite = nil
        if let m = savedMatch(host, in: loadSites()) {
            savedSite = m.site
            savedLabel = NSTextField(labelWithString: "Saved: \(m.site) always opens in \(m.profile)")
            savedLabel.font = .systemFont(ofSize: 12)
            savedLabel.textColor = .secondaryLabelColor
            let forget = NSButton(title: "Forget", target: self, action: #selector(forgetSaved(_:)))
            forget.bezelStyle = .inline
            forget.controlSize = .small
            let savedRow = NSStackView(views: [savedLabel, forget])
            savedRow.spacing = 8
            views.append(savedRow)
        }
        let hint = NSTextField(labelWithString: "Press 1–\(profiles.count) · hold ⌥ while clicking a link to change a saved site")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let manage = NSButton(title: "Saved sites…", target: self, action: #selector(openManager))
        manage.bezelStyle = .inline
        manage.controlSize = .small
        let buttons = NSStackView(views: [cancel, manage])
        buttons.spacing = 10
        views.append(buttons)
        views.append(hint)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(16, after: sub)
        stack.setCustomSpacing(16, after: row)
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 18, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sub.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.addSubview(stack)
        content.addSubview(blur)
        blur.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor), stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor), stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor), blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blur.topAnchor.constraint(equalTo: content.topAnchor), blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.picker = self
        p.contentView = content
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.setContentSize(content.fittingSize)
        p.center()
        panel = p

        if let out = preview {
            p.appearance = NSAppearance(named: .darkAqua)
            p.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let v = p.contentView!
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
            return
        }
        p.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKey()
        // Nothing picked in 2 minutes: drop the link rather than leave a stray popup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { if self.panel === p { self.next() } }
    }

    func card(_ p: Profile, index: Int) -> NSView {
        let avatar = AvatarView(p)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: p.name)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let key = NSTextField(labelWithString: "\(index + 1)")
        key.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        key.textColor = .tertiaryLabelColor
        let v = NSStackView(views: [avatar, name, key])
        v.orientation = .vertical
        v.spacing = 6
        v.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 8, right: 14)
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([avatar.widthAnchor.constraint(equalToConstant: 72), avatar.heightAnchor.constraint(equalToConstant: 72)])

        let b = ProfileButton(title: "", target: self, action: #selector(picked(_:)))
        b.tag = index
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 12
        b.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: b.leadingAnchor), v.trailingAnchor.constraint(equalTo: b.trailingAnchor),
            v.topAnchor.constraint(equalTo: b.topAnchor), v.bottomAnchor.constraint(equalTo: b.bottomAnchor),
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 104),
        ])
        b.onHover = { [weak b] on in b?.layer?.backgroundColor = on ? NSColor.white.withAlphaComponent(0.12).cgColor : nil }
        return b
    }

    @objc func forgetSaved(_ sender: NSButton) {
        guard let site = savedSite else { return }
        var sites = loadSites()
        sites[site] = nil
        saveSites(sites)
        savedLabel.stringValue = "Forgotten: \(site) will ask again"
        sender.isHidden = true
        reloadManager()
    }

    @objc func picked(_ sender: NSButton) { choose(sender.tag) }

    @objc func openManager() {
        panel?.orderOut(nil)
        panel = nil
        showManager(preview: nil)
    }

    // A window listing saved sites: change the profile each one opens in, or remove it.
    func showManager(preview: String?) {
        if profiles.isEmpty { profiles = loadProfiles() }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Profiley — Saved sites"
        w.isReleasedWhenClosed = false
        w.delegate = self
        manager = w
        reloadManager()
        w.center()

        if let out = preview {
            w.appearance = NSAppearance(named: .aqua)
            w.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let v = w.contentView!
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func reloadManager() {
        guard let w = manager else { return }
        let saved = loadSites().sorted { $0.key < $1.key }
        let names = profiles.map(\.name)

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        rows.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        let note = NSTextField(wrappingLabelWithString: saved.isEmpty
            ? "No saved sites yet. Tick \"Always open this site this way\" in the popup, or add one below."
            : "These sites, and their subdomains, open straight in the profile shown.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 440
        rows.addArrangedSubview(note)
        rows.setCustomSpacing(14, after: note)

        for (site, profile) in saved {
            let id = NSUserInterfaceItemIdentifier(site)
            let label = NSTextField(labelWithString: site)
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            label.widthAnchor.constraint(equalToConstant: 200).isActive = true
            let pop = NSPopUpButton(frame: .zero, pullsDown: false)
            pop.addItems(withTitles: names)
            if !names.contains(profile) { pop.addItem(withTitle: profile) }  // a profile that no longer exists
            pop.selectItem(withTitle: profile)
            pop.identifier = id
            pop.target = self
            pop.action = #selector(changeSaved(_:))
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeSaved(_:)))
            remove.bezelStyle = .rounded
            remove.identifier = id
            let row = NSStackView(views: [label, pop, remove])
            row.spacing = 10
            rows.addArrangedSubview(row)
        }

        let field = NSTextField(string: addField?.stringValue ?? "")
        field.placeholderString = "Add a site, e.g. example.com"
        field.font = .systemFont(ofSize: 13)
        field.widthAnchor.constraint(equalToConstant: 200).isActive = true
        field.target = self
        field.action = #selector(addSite)
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: names)
        let add = NSButton(title: "Add", target: self, action: #selector(addSite))
        add.bezelStyle = .rounded
        addField = field
        addPop = pop
        let addRow = NSStackView(views: [field, pop, add])
        addRow.spacing = 10
        if let last = rows.arrangedSubviews.last { rows.setCustomSpacing(16, after: last) }
        rows.addArrangedSubview(addRow)

        if !isDefaultBrowser() {
            let note = NSTextField(wrappingLabelWithString: "Profiley isn't your default browser yet, so links from other apps won't come here.")
            note.font = .systemFont(ofSize: 12)
            note.textColor = .secondaryLabelColor
            note.preferredMaxLayoutWidth = 440
            let make = NSButton(title: "Make default browser", target: self, action: #selector(makeDefaultPressed))
            make.bezelStyle = .rounded
            rows.setCustomSpacing(20, after: addRow)
            rows.addArrangedSubview(note)
            rows.addArrangedSubview(make)
        }

        let content = NSView()
        rows.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rows.topAnchor.constraint(equalTo: content.topAnchor),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        w.contentView = content
        w.setContentSize(NSSize(width: 480, height: max(160, rows.fittingSize.height)))
    }

    @objc func changeSaved(_ sender: NSPopUpButton) {
        guard let site = sender.identifier?.rawValue, let profile = sender.titleOfSelectedItem else { return }
        var sites = loadSites()
        sites[site] = profile
        saveSites(sites)
    }

    @objc func removeSaved(_ sender: NSButton) {
        guard let site = sender.identifier?.rawValue else { return }
        var sites = loadSites()
        sites[site] = nil
        saveSites(sites)
        reloadManager()
    }

    @objc func addSite() {
        guard let field = addField, let profile = addPop?.titleOfSelectedItem else { return }
        let site = siteName(field.stringValue)
        guard site.contains("."), !site.contains(" ") else { NSSound.beep(); return }
        var sites = loadSites()
        sites[site] = profile
        saveSites(sites)
        field.stringValue = ""
        reloadManager()
    }

    @objc func makeDefaultPressed() { makeDefault { self.reloadManager() } }

    // macOS asks the user to confirm before the change takes effect.
    func makeDefault(then done: @escaping () -> Void) {
        guard #available(macOS 12.0, *) else { return done() }
        let ws = NSWorkspace.shared, me = Bundle.main.bundleURL
        ws.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { e in
            if let e { NSLog("Couldn't become the default browser: %@", e.localizedDescription) }
            ws.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { _ in
                DispatchQueue.main.async(execute: done)
            }
        }
    }

    func windowWillClose(_ n: Notification) {
        manager = nil
        if panel == nil { NSApp.terminate(nil) }
    }

    func choose(_ i: Int) {
        guard profiles.indices.contains(i) else { return }
        let p = profiles[i]
        openInBrowser(url, p)
        if remember.state == .on && !host.isEmpty {
            var sites = loadSites()
            sites[host] = p.name
            saveSites(sites)
            reloadManager()
        }
        next()
    }

    func openInBrowser(_ url: String, _ p: Profile) {
        NSLog("Opening %@ in %@ profile %@", url, browser.name, p.name)
        run("/usr/bin/open", ["-na", browser.name, "--args", "--profile-directory=\(p.dir)", url])
        bringBrowserForward()
    }

    // The browser sometimes opens the tab without coming forward, so hand focus to it explicitly.
    func bringBrowserForward() {
        let id = browser.bundleId
        if #available(macOS 14.0, *) { NSApp.yieldActivation(toApplicationWithBundleIdentifier: id) }
        for delay in [0.0, 0.3] {
            Thread.sleep(forTimeInterval: delay)
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate(options: [.activateAllWindows])
        }
    }

    func run(_ path: String, _ args: [String]) {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: path)
        t.arguments = args
        try? t.run()
        t.waitUntilExit()
    }
}

final class KeyPanel: NSPanel {
    weak var picker: Picker?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { picker?.next(); return }
        if let c = event.characters, let n = Int(c) { picker?.choose(n - 1); return }
        super.keyDown(with: event)
    }
}

let app = NSApplication.shared
let delegate = Picker()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
