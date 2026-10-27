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
  let surface: UIVisualEffectView
  let channel: FlutterMethodChannel
  var buttons: [UIButton] = []
  init(frame: CGRect, id: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: .regular); glass.isInteractive = true; effect = glass
    } else { effect = UIBlurEffect(style: .systemMaterial) }
    surface = UIVisualEffectView(effect: UIAccessibility.isReduceTransparencyEnabled ? nil : effect)
    channel = FlutterMethodChannel(name: "network.utterleaf/navigation/\(id)", binaryMessenger: messenger)
    super.init()
    surface.frame = frame; surface.overrideUserInterfaceStyle = .dark
    surface.layer.cornerRadius = 34; surface.clipsToBounds = true
    if UIAccessibility.isReduceTransparencyEnabled { surface.backgroundColor = .secondarySystemBackground }
    let stack = UIStackView(); stack.axis = .horizontal; stack.distribution = .fillEqually; stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false; surface.contentView.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor, constant: -6)])
    for (index,item) in [("主页","waveform"),("用量","chart.bar.xaxis"),("设置","slider.horizontal.3")].enumerated() {
      let button = UIButton(type: .system)
      var config = UIButton.Configuration.plain(); config.title = item.0; config.image = UIImage(systemName: item.1)
      config.imagePlacement = .top; config.imagePadding = 3; config.cornerStyle = .capsule
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19)
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var result = attributes; result.font = UIFont.preferredFont(forTextStyle: .caption1); return result
      }
      button.configuration = config; button.accessibilityLabel = item.0
      button.addAction(UIAction { [weak self] _ in self?.select(index); self?.channel.invokeMethod("select", arguments: index) }, for: .touchUpInside)
      buttons.append(button); stack.addArrangedSubview(button)
    }
    select((arguments as? [String: Any])?["selected"] as? Int ?? 0)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "select", let index = call.arguments as? Int { self?.select(index); result(nil) }
      else { result(FlutterMethodNotImplemented) }
    }
  }
  func select(_ index: Int) {
    guard buttons.indices.contains(index) else { return }
    for (i,button) in buttons.enumerated() {
      button.isSelected = i == index
      button.accessibilityTraits = i == index ? [.button,.selected] : .button
      button.configuration?.baseForegroundColor = i == index ? UIColor(red: 0.62, green: 0.84, blue: 0.71, alpha: 1) : .secondaryLabel
      button.configuration?.background.backgroundColor = i == index ? UIColor.white.withAlphaComponent(0.1) : .clear
    }
  }
  func view() -> UIView { surface }
}
