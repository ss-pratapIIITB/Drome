import Foundation

let dromeBridgeJS: String = {
    guard let url = Bundle.main.url(forResource: "drome-bridge", withExtension: "js"),
          let src = try? String(contentsOf: url) else { return "" }
    return src
}()

let dromeReadabilityJS: String = {
    guard let url = Bundle.main.url(forResource: "drome-readability", withExtension: "js"),
          let src = try? String(contentsOf: url) else { return "" }
    return src
}()
