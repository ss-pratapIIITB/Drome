import Foundation

let dromeBridgeJS: String = {
    guard let url = Bundle.main.url(forResource: "drome-bridge", withExtension: "js"),
          let src = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    return src
}()
