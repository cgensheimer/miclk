import AppKit
import QuartzCore

final class MuteOverlayPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isFloatingPanel = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        isMovableByWindowBackground = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MuteOverlayContentView: NSView {

    private let gradientLayer = CAGradientLayer()
    private let dotView = NSView()
    private let label = NSTextField(labelWithString: "")
    private let stack: NSStackView

    override init(frame: NSRect) {
        stack = NSStackView()
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        gradientLayer.frame = CGRect(origin: .zero, size: newSize)
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(white: 0, alpha: 0.35).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        gradientLayer.cornerRadius = 8
        gradientLayer.cornerCurve = .continuous
        layer?.insertSublayer(gradientLayer, at: 0)

        let haze = NSShadow()
        haze.shadowColor = NSColor.black.withAlphaComponent(0.6)
        haze.shadowBlurRadius = 10
        haze.shadowOffset = .zero

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.shadow = haze

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(white: 1.0, alpha: 0.9)
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.shadow = haze

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(dotView)
        addSubview(stack)

        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(text: String, dotColor: NSColor, pulsing: Bool) {
        label.stringValue = text
        dotView.layer?.backgroundColor = dotColor.cgColor

        gradientLayer.colors = [
            NSColor.clear.cgColor,
            dotColor.withAlphaComponent(0.35).cgColor,
        ]

        dotView.layer?.removeAnimation(forKey: "pulse")
        if pulsing {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.2
            pulse.duration = 1.4
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dotView.layer?.add(pulse, forKey: "pulse")
        }
    }
}

final class OverlayController {

    private let panel: MuteOverlayPanel
    private let contentView: MuteOverlayContentView
    private var animationGeneration = 0
    private var autoDismissWork: DispatchWorkItem?

    private let topMargin: CGFloat = 4
    private let gradientFade: CGFloat = 40

    init() {
        let frame = NSRect(origin: .zero, size: NSSize(width: 180, height: 32))
        panel = MuteOverlayPanel(contentRect: frame)
        contentView = MuteOverlayContentView(frame: frame)
        panel.contentView = contentView
    }

    func show(text: String, dotColor: NSColor, pulsing: Bool) {
        autoDismissWork?.cancel()
        autoDismissWork = nil

        animationGeneration += 1
        contentView.layer?.removeAllAnimations()

        contentView.configure(text: text, dotColor: dotColor, pulsing: pulsing)
        let size = sizeForContent(text: text)
        panel.setFrame(overlayFrame(size: size), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
    }

    func flash(text: String, dotColor: NSColor = NSColor(white: 1, alpha: 0.45),
               pulsing: Bool = false, duration: TimeInterval, completion: (() -> Void)? = nil) {
        show(text: text, dotColor: dotColor, pulsing: pulsing)

        let work = DispatchWorkItem { [weak self] in
            self?.dismiss(completion: completion)
        }
        autoDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismiss(completion: (() -> Void)? = nil) {
        autoDismissWork?.cancel()
        autoDismissWork = nil

        animationGeneration += 1
        let gen = animationGeneration

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            guard self?.animationGeneration == gen else { return }
            panel?.orderOut(nil)
            panel?.alphaValue = 1.0
            completion?()
        })
    }

    private func sizeForContent(text: String) -> NSSize {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let contentWidth: CGFloat = 14 + textWidth + 14
        let width = gradientFade + contentWidth
        return NSSize(width: width, height: 32)
    }

    private func overlayFrame(size: NSSize) -> NSRect {
        guard let screen = activeScreen() else {
            return NSRect(origin: .zero, size: size)
        }
        let sf = screen.frame
        let vf = screen.visibleFrame
        return NSRect(
            x: sf.maxX - size.width,
            y: vf.maxY - size.height - topMargin,
            width: size.width,
            height: size.height
        )
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }
}
