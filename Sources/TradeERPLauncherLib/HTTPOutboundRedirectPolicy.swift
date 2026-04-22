import Foundation

/// Entscheidet, ob `URLSession` einem **HTTP-Redirect** folgen soll: nur **http(s)** mit Host; kein `fsclientlauncher:` (wie bei der Definitions-URL).
enum HTTPOutboundRedirectPolicy {
    static func respondToRedirect(
        context: String,
        response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let next = request.url else {
            LaunchLoadTrace.log("\(context): Redirect ohne Ziel-URL (HTTP \(response.statusCode))")
            completionHandler(nil)
            return
        }
        let sch = next.scheme?.lowercased() ?? ""
        if sch == "fsclientlauncher" {
            LaunchLoadTrace.log(
                "\(context): HTTP \(response.statusCode) Weiterleitung auf fsclientlauncher (kein HTTP-Follow; Ziel steht in der Location): \(LaunchLoadTrace.preview(next.absoluteString))"
            )
            completionHandler(nil)
            return
        }
        guard sch == "http" || sch == "https" else {
            LaunchLoadTrace.log(
                "\(context): HTTP \(response.statusCode) Weiterleitung abgelehnt — Schema „\(sch)“: \(LaunchLoadTrace.preview(next.absoluteString))"
            )
            completionHandler(nil)
            return
        }
        guard let host = next.host, !host.isEmpty else {
            LaunchLoadTrace.log("\(context): Redirect abgelehnt (ohne Host) HTTP \(response.statusCode)")
            completionHandler(nil)
            return
        }
        LaunchLoadTrace.log(
            "\(context): folge HTTP-Redirect \(response.statusCode) → \(LaunchLoadTrace.preview(next.absoluteString))"
        )
        completionHandler(request)
    }
}
