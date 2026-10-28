import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.applicationRegistrar
    DictationCoordinator.shared.attach(registrar.messenger())
    registrar.register(GlassNavigationFactory(messenger: registrar.messenger()), withId: "network.utterleaf/glass-navigation")
  }
}

private final class GlassNavigationFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    GlassNavigationView(frame: frame, id: viewId, arguments: args, messenger: messenger)
  }
}
private final class GlassNavigationView: NSObject, FlutterPlatformView {
  private let surface: NavigationSurface
  private let channel: FlutterMethodChannel
  private let lens: UIVisualEffectView
  private let stack = UIStackView()
  private var buttons: [UIButton] = []
  private var selected = 0
  private var dragging = false
  private var dragOrigin = 0
  private let feedback = UISelectionFeedbackGenerator()
  private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(track(_:)))

  init(frame: CGRect, id: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    let backdrop: UIVisualEffect, selector: UIVisualEffect
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: .regular); glass.isInteractive = true
      let highlight = UIGlassEffect(style: .clear); highlight.isInteractive = true
      backdrop = glass; selector = highlight
    } else {
      backdrop = UIBlurEffect(style: .systemMaterial)
      selector = UIBlurEffect(style: .systemThinMaterial)
    }
    let opaque = UIAccessibility.isReduceTransparencyEnabled
    surface = NavigationSurface(effect: opaque ? nil : backdrop)
    lens = UIVisualEffectView(effect: opaque ? nil : selector)
    channel = FlutterMethodChannel(name: "network.utterleaf/navigation/\(id)", binaryMessenger: messenger)
    super.init()
    surface.frame = frame; surface.overrideUserInterfaceStyle = .dark
    surface.layer.cornerRadius = 34; surface.clipsToBounds = true
    if opaque { surface.backgroundColor = .secondarySystemBackground }
    lens.backgroundColor = UIColor.white.withAlphaComponent(opaque ? 0.16 : 0.1)
    lens.clipsToBounds = true; lens.isUserInteractionEnabled = false
    surface.addSubview(lens)
    stack.axis = .horizontal; stack.distribution = .fillEqually; stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -6)])
    for (index,item) in [("主页","waveform"),("历史","clock.arrow.circlepath"),("用量","chart.bar.xaxis"),("设置","slider.horizontal.3")].enumerated() {
      let button = UIButton(type: .system)
      var config = UIButton.Configuration.plain(); config.title = item.0; config.image = UIImage(systemName: item.1)
      config.imagePlacement = .top; config.imagePadding = 3; config.cornerStyle = .capsule
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19)
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var result = attributes; result.font = UIFont.preferredFont(forTextStyle: .caption1); return result
      }
      button.configuration = config; button.accessibilityLabel = item.0
      button.addAction(UIAction { [weak self] _ in self?.select(index, notify: true) }, for: .touchUpInside)
      buttons.append(button); stack.addArrangedSubview(button)
    }
    pan.maximumNumberOfTouches = 1
    surface.addGestureRecognizer(pan)
    surface.didLayout = { [weak self] in
      guard let self, !dragging else { return }
      position(Double(selected))
    }
    selected = min(buttons.count - 1, max(0, (arguments as? [String: Any])?["selected"] as? Int ?? 0))
    paint(selected)
    surface.layoutIfNeeded(); position(Double(selected))
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "select", let index = call.arguments as? Int else {
        result(FlutterMethodNotImplemented); return
      }
      self?.select(index, notify: false); result(nil)
    }
  }
  func view() -> UIView { surface }
  private var step: CGFloat { max(1, (surface.bounds.width - 16) / CGFloat(buttons.count)) }
  private func fraction(at x: CGFloat) -> Double { min(Double(buttons.count - 1), max(0, Double((x - 8 - step / 2) / step))) }
  private func position(_ fraction: Double, stretch: CGFloat = 1) {
    lens.transform = .identity
    lens.bounds = CGRect(x: 0, y: 0, width: max(1, step - 4), height: max(1, surface.bounds.height - 12))
    lens.center = CGPoint(x: 8 + step * (CGFloat(fraction) + 0.5), y: surface.bounds.midY)
    lens.layer.cornerRadius = lens.bounds.height / 2
    lens.transform = CGAffineTransform(scaleX: stretch, y: stretch > 1 ? 0.98 : 1)
  }
  private func paint(_ preview: Int) {
    for (index, button) in buttons.enumerated() {
      button.isSelected = index == selected
      button.accessibilityTraits = index == selected ? [.button,.selected] : .button
      button.configuration?.baseForegroundColor = index == preview ? UIColor(red: 0.62, green: 0.84, blue: 0.71, alpha: 1) : .secondaryLabel
      button.configuration?.background.backgroundColor = .clear
    }
  }
  private func stopMotion() {
    let center = lens.layer.presentation()?.position ?? lens.center
    lens.layer.removeAllAnimations(); lens.transform = .identity; lens.center = center
  }
  private func select(_ index: Int, notify: Bool) {
    guard buttons.indices.contains(index) else { return }
    let changed = selected != index
    selected = index; dragging = false; paint(index)
    let move = { self.position(Double(index)) }
    if UIAccessibility.isReduceMotionEnabled { UIView.performWithoutAnimation(move) }
    else {
      UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0,
        options: [.beginFromCurrentState, .allowUserInteraction], animations: move)
    }
    if notify && changed { feedback.selectionChanged(); channel.invokeMethod("select", arguments: index) }
  }
  @objc private func track(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      dragging = true; dragOrigin = selected; stopMotion(); feedback.prepare()
      fallthrough
    case .changed:
      let value = fraction(at: gesture.location(in: surface).x)
      let stretch: CGFloat = UIAccessibility.isReduceMotionEnabled ? 1 : 1 + min(0.08, abs(gesture.velocity(in: surface).x) / 15000)
      position(value, stretch: stretch); paint(Int(value.rounded()))
    case .ended:
      select(Int(fraction(at: gesture.location(in: surface).x).rounded()), notify: true)
    case .cancelled, .failed:
      select(dragOrigin, notify: false)
    default: break
    }
  }
}

private final class NavigationSurface: UIView {
  var didLayout: (() -> Void)?
  private let backdrop: UIVisualEffectView
  init(effect: UIVisualEffect?) {
    backdrop = UIVisualEffectView(effect: effect)
    super.init(frame: .zero)
    backdrop.isUserInteractionEnabled = false
    backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(backdrop)
  }
  required init?(coder: NSCoder) { nil }
  override func layoutSubviews() {
    super.layoutSubviews()
    backdrop.frame = bounds
    didLayout?()
  }
}
