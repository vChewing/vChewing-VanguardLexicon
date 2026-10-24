// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Foundation

// MARK: - WikipediaFetcher

/// 由 MediaWiki API 抓取條目純文字。
///
/// - Note: 取樣一律走 `variant=zh-cn`（簡體）或 `variant=zh-tw`（繁體），
///   以免原始碼內的字形與語料內的陳述互相矛盾。
struct WikipediaFetcher {
  let endpoint: URL
  let variant: String

  func fetch(titles: [String], batchSize: Int = 10) throws -> [(title: String, text: String)] {
    var results = [(title: String, text: String)]()
    let batches = stride(from: 0, to: titles.count, by: batchSize).map {
      Array(titles[$0 ..< min($0 + batchSize, titles.count)])
    }
    for (offset, batch) in batches.enumerated() {
      if offset > 0 { Thread.sleep(forTimeInterval: 2) }
      let pages = try fetchBatch(batch)
      for page in pages where !page.text.isEmpty {
        results.append(page)
      }
    }
    return results
  }

  // MARK: Private

  private struct PageResponse: Decodable {
    struct Query: Decodable {
      struct Page: Decodable {
        let title: String
        let extract: String?
      }

      let pages: [String: Page]
    }

    let query: Query?
  }

  private func fetchBatch(_ titles: [String]) throws -> [(title: String, text: String)] {
    guard !titles.isEmpty else { return [] }
    var attempt = 0
    while true {
      attempt += 1
      do {
        let data = try request(titles)
        let decoded = try JSONDecoder().decode(PageResponse.self, from: data)
        let pages = decoded.query?.pages.values.compactMap { page -> (title: String, text: String)? in
          guard let extract = page.extract else { return nil }
          return (title: page.title, text: extract)
        } ?? []
        return pages
      } catch {
        guard attempt < 5 else { throw error }
        Thread.sleep(forTimeInterval: pow(2, Double(attempt)))
      }
    }
  }

  private func request(_ titles: [String]) throws -> Data {
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "action", value: "query"),
      URLQueryItem(name: "format", value: "json"),
      URLQueryItem(name: "prop", value: "extracts"),
      URLQueryItem(name: "explaintext", value: "1"),
      URLQueryItem(name: "exsectionformat", value: "plain"),
      URLQueryItem(name: "redirects", value: "1"),
      URLQueryItem(name: "variant", value: variant),
      URLQueryItem(name: "titles", value: titles.joined(separator: "|")),
    ]
    var request = URLRequest(url: components.url!)
    request.setValue("VanguardLexiconCorpusMiner/2.0 (vChewing dev tooling)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 30

    let semaphore = DispatchSemaphore(value: 0)
    let box = ResponseBox()
    URLSession.shared.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      box.error = error
      box.data = data
      box.statusCode = (response as? HTTPURLResponse)?.statusCode
    }.resume()
    semaphore.wait()
    if let error = box.error { throw FetchError.network(error) }
    guard let status = box.statusCode else { throw FetchError.badResponse }
    guard (200 ..< 300).contains(status) else { throw FetchError.httpStatus(status) }
    guard let data = box.data else { throw FetchError.emptyBody }
    return data
  }
}

// MARK: - WikipediaFetcher.FetchError

extension WikipediaFetcher {
  enum FetchError: Error, CustomStringConvertible {
    case network(Error)
    case badResponse
    case httpStatus(Int)
    case emptyBody

    var description: String {
      switch self {
      case let .network(error): "網路錯誤：\(error.localizedDescription)"
      case .badResponse: "回應不是 HTTP 回應。"
      case let .httpStatus(status): "HTTP 狀態 \(status)。"
      case .emptyBody: "回應沒有內容。"
      }
    }
  }
}

// MARK: - ResponseBox

private final class ResponseBox: @unchecked Sendable {
  var data: Data?
  var error: Error?
  var statusCode: Int?
}
