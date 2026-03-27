import Foundation

private let _logStart = Date()
private let _logQueue = DispatchQueue(label: "game.logger", qos: .utility)

func glog(_ tag: String, _ message: String) {
    let elapsed = Date().timeIntervalSince(_logStart)
    let ms  = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 1000)
    let sec = Int(elapsed) % 60
    let min = Int(elapsed) / 60
    let line = String(format: "[%d:%02d.%03d] %@ %@", min, sec, ms, tag, message)
    print(line)
}
