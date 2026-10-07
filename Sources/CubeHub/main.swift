import AppKit

MainActor.assumeIsolated {
    let options = LaunchOptions(arguments: CommandLine.arguments)
    let app = NSApplication.shared

    if let iconURL = options.iconURL {
        exit(Snapshots.writeIcon(to: iconURL) ? 0 : 1)
    }

    let delegate = AppDelegate(options: options)
    app.delegate = delegate
    app.run()
}
