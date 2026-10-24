import Foundation
import CryptoKit

/// Volcengine V4 signing, limited to the read-only billing action and official host.
public enum VolcBillingSigner {
    static func hex(_ data: some Sequence<UInt8>) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func hmac(_ key: Data, _ text: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key))) }
    public static func request(body: Data, accessKey: String, secret: String, date: Date) -> URLRequest {
        let host = "open.volcengineapi.com"
        let query = "Action=ListBillDetail&Version=2022-01-01"
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = f.string(from: date), day = String(stamp.prefix(8))
        let payloadHash = hex(SHA256.hash(data: body))
        let headerNames = "content-type;host;x-content-sha256;x-date"
        let headers = "content-type:application/json\nhost:\(host)\nx-content-sha256:\(payloadHash)\nx-date:\(stamp)\n"
        let canonical = ["POST", "/", query, headers, headerNames, payloadHash].joined(separator: "\n")
        let scope = "\(day)/cn-north-1/billing/request"
        let signingText = ["HMAC-SHA256", stamp, scope, hex(SHA256.hash(data: Data(canonical.utf8)))].joined(separator: "\n")
        let kDay = hmac(Data(secret.utf8), day), kRegion = hmac(kDay, "cn-north-1"), kService = hmac(kRegion, "billing")
        let signature = hex(hmac(hmac(kService, "request"), signingText))
        var request = URLRequest(url: URL(string: "https://\(host)/?\(query)")!)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(stamp, forHTTPHeaderField: "X-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Content-Sha256")
        request.setValue("HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(headerNames), Signature=\(signature)", forHTTPHeaderField: "Authorization")
        return request
    }
}
