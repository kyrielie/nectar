import Foundation
import AO3Kit
import RSParser
import XCTest

private let ao3FeedExtensionForTests = AO3FeedExtension()

func parserData(_ filename: String, _ fileExtension: String, _ url: String) -> ParserData {
	AO3FeedExtensionPoint.provider = ao3FeedExtensionForTests
	guard let resourceURL = Bundle.module.url(forResource: filename, withExtension: fileExtension, subdirectory: "Resources") else {
		XCTFail("Missing AO3Kit test fixture Resources/\(filename).\(fileExtension) in \(Bundle.module.bundleURL.path)")
		return ParserData(url: url, data: Data())
	}
	guard let data = try? Data(contentsOf: resourceURL) else {
		XCTFail("Could not read AO3Kit test fixture at \(resourceURL.path)")
		return ParserData(url: url, data: Data())
	}
	return ParserData(url: url, data: data)
}

func htmlFixtureString(_ filename: String) -> String {
	guard let resourceURL = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Resources") else {
		XCTFail("Missing AO3Kit test fixture Resources/\(filename) in \(Bundle.module.bundleURL.path)")
		return ""
	}
	guard let contents = try? String(contentsOf: resourceURL, encoding: .utf8) else {
		XCTFail("Could not read AO3Kit test fixture at \(resourceURL.path)")
		return ""
	}
	return contents
}
