import Cocoa

enum LaunchOptions {
    /// Debug/test uniquement : mot de passe fourni via stdin (jamais loggé, jamais écrit).
    static var stdinPassword: String?
    /// Debug/test : ne pas quitter quand la fenêtre perd le focus.
    static var keepAlive = false
}

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(SelfTest.run())
}

if arguments.contains("--password-stdin") {
    if let line = readLine(strippingNewline: true) {
        LaunchOptions.stdinPassword = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
    }
}

if arguments.contains("--keep-alive") {
    LaunchOptions.keepAlive = true
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
