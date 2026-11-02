//
//  TLSInspectorService.swift
//  NetScan
//
//  Reads a TLS service's leaf certificate: subject, expiry, self-signing and iOS trust.
//  The handshake is cancelled after the certificate arrives, so no request is sent.
//

import Foundation
import Security

public struct TLSCertificateReport: Equatable {
    public var subject: String
    public var notAfter: Date?
    public var selfSigned: Bool
    public var trusted: Bool
    public var trustError: String?

    public init(subject: String, notAfter: Date?, selfSigned: Bool, trusted: Bool, trustError: String? = nil) {
        self.subject = subject
        self.notAfter = notAfter
        self.selfSigned = selfSigned
        self.trusted = trusted
        self.trustError = trustError
    }

    public func daysRemaining(now: Date = Date()) -> Int? {
        notAfter.map { Int(floor($0.timeIntervalSince(now) / 86_400)) }
    }

    /// Plain-language observations, most important first.
    public func findings(now: Date = Date()) -> [String] {
        var findings: [String] = []
        if let days = daysRemaining(now: now) {
            if days < 0 { findings.append("Certificate expired \(-days) days ago.") }
            else if days < 30 { findings.append("Certificate expires in \(days) days.") }
        } else {
            findings.append("Expiry date could not be read.")
        }
        if selfSigned { findings.append("Self-signed: common for routers and appliances, but iOS cannot verify who issued it.") }
        else if !trusted { findings.append("Not trusted by iOS for this address\(trustError.map { ": \($0)" } ?? ".")") }
        if findings.isEmpty { findings.append("Trusted by iOS and not close to expiry.") }
        return findings
    }
}

public enum TLSInspector {
    public static func inspect(host: String, port: Int, timeout: TimeInterval = 4) async -> TLSCertificateReport? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65535).contains(port), timeout.isFinite, timeout > 0,
              let url = URL(string: "https://\(host):\(port)/") else { return nil }
        return await withCheckedContinuation { continuation in
            let delegate = CertificateCapture(host: host, continuation: continuation)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            session.dataTask(with: request).resume()
            session.finishTasksAndInvalidate()
        }
    }

    public static func report(trust: SecTrust, host: String) -> TLSCertificateReport? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return nil }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var error: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &error)
        let issuer = SecCertificateCopyNormalizedIssuerSequence(leaf) as Data?
        let subjectSequence = SecCertificateCopyNormalizedSubjectSequence(leaf) as Data?
        let der = SecCertificateCopyData(leaf) as Data
        return TLSCertificateReport(
            subject: (SecCertificateCopySubjectSummary(leaf) as String?) ?? "Unnamed certificate",
            notAfter: notAfter(der: der),
            selfSigned: issuer != nil && issuer == subjectSequence,
            trusted: trusted,
            trustError: trusted ? nil : error.map { CFErrorCopyDescription($0) as String })
    }

    // MARK: - Minimal DER reading for Certificate.tbsCertificate.validity.notAfter

    private struct DERElement {
        let tag: UInt8
        let content: Range<Int>
        let end: Int
    }

    private static func element(_ bytes: [UInt8], at index: Int) -> DERElement? {
        guard index + 2 <= bytes.count else { return nil }
        let tag = bytes[index]
        var cursor = index + 1
        let first = Int(bytes[cursor])
        cursor += 1
        var length = 0
        if first < 0x80 {
            length = first
        } else {
            let count = first & 0x7F
            guard (1...4).contains(count), cursor + count <= bytes.count else { return nil }
            for byte in bytes[cursor..<(cursor + count)] { length = (length << 8) | Int(byte) }
            cursor += count
        }
        guard length >= 0, cursor + length <= bytes.count else { return nil }
        return DERElement(tag: tag, content: cursor..<(cursor + length), end: cursor + length)
    }

    /// Expiry date from a DER X.509 certificate, or nil when the structure is unexpected.
    public static func notAfter(der data: Data) -> Date? {
        let bytes = [UInt8](data)
        guard let certificate = element(bytes, at: 0), certificate.tag == 0x30,
              let tbs = element(bytes, at: certificate.content.lowerBound), tbs.tag == 0x30 else { return nil }
        guard var field = element(bytes, at: tbs.content.lowerBound) else { return nil }
        if field.tag == 0xA0 { // explicit version
            guard let next = element(bytes, at: field.end) else { return nil }
            field = next
        }
        // serialNumber, signature, issuer, then validity.
        for expected: UInt8 in [0x02, 0x30, 0x30] {
            guard field.tag == expected, let next = element(bytes, at: field.end) else { return nil }
            field = next
        }
        guard field.tag == 0x30, let notBefore = element(bytes, at: field.content.lowerBound),
              let notAfter = element(bytes, at: notBefore.end), notAfter.end <= field.end else { return nil }
        return time(tag: notAfter.tag, text: String(decoding: bytes[notAfter.content], as: UTF8.self))
    }

    /// UTCTime (YYMMDDHHMMSSZ) or GeneralizedTime (YYYYMMDDHHMMSSZ), UTC only.
    static func time(tag: UInt8, text: String) -> Date? {
        guard text.hasSuffix("Z") else { return nil }
        let digits = Array(text.dropLast())
        guard digits.allSatisfy(\.isNumber) else { return nil }
        let yearLength: Int
        switch (tag, digits.count) {
        case (0x17, 12): yearLength = 2
        case (0x18, 14): yearLength = 4
        default: return nil
        }
        func number(_ start: Int, _ length: Int) -> Int { Int(String(digits[start..<(start + length)])) ?? -1 }
        var year = number(0, yearLength)
        if yearLength == 2 { year += year < 50 ? 2000 : 1900 }
        var components = DateComponents()
        components.year = year
        components.month = number(yearLength, 2)
        components.day = number(yearLength + 2, 2)
        components.hour = number(yearLength + 4, 2)
        components.minute = number(yearLength + 6, 2)
        components.second = number(yearLength + 8, 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Out-of-range fields would otherwise roll over into a different date.
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == components.month,
              calendar.component(.day, from: date) == components.day,
              (0...23).contains(components.hour ?? -1), (0...59).contains(components.minute ?? -1),
              (0...59).contains(components.second ?? -1) else { return nil }
        return date
    }
}

private final class CertificateCapture: NSObject, URLSessionTaskDelegate {
    private let host: String
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TLSCertificateReport?, Never>?

    init(host: String, continuation: CheckedContinuation<TLSCertificateReport?, Never>) {
        self.host = host
        self.continuation = continuation
    }

    private func finish(_ report: TLSCertificateReport?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: report)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        finish(TLSInspector.report(trust: trust, host: host))
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(nil)
    }
}
