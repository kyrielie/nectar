//
//  CSSImportExtractorTests.swift
//  NetNewsWire-iOSTests
//
//  Created by OpenAI on 8/6/26.
//

import Testing
@testable import Nectar

@Suite struct CSSImportExtractorTests {

	@Test func noImports() {
		let css = """
		body {
			color: red;
		}
		"""

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == "")
		#expect(result.remainingCSS == css)
	}

	@Test func singleImport() {
		let css = """
		@import url(A);

		body {
		}
		"""

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == "@import url(A);\n\n")
		#expect(result.remainingCSS == "body {\n}")
	}

	@Test func multipleImportsPreserveOrder() {
		let css = """
		@import url(A);

		@import url(B);

		body {
		}
		"""

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == "@import url(A);\n\n@import url(B);\n\n")
		#expect(result.remainingCSS == "body {\n}")
	}

	@Test func commentsRemainAttachedToLeadingImportBlock() {
		let css = """
		/* Theme */

		@import url(A);

		/* Fonts */
		body {
		}
		"""

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == "/* Theme */\n\n@import url(A);\n\n/* Fonts */\n")
		#expect(result.remainingCSS == "body {\n}")
	}

	@Test func whitespaceIsPreserved() {
		let css = "\n\n\t@import url(A);\n\n  \nbody {\n}\n"

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == "\n\n\t@import url(A);\n\n  \n")
		#expect(result.remainingCSS == "body {\n}\n")
	}

	@Test func lateImportIsNotMoved() {
		let css = """
		body {
		}

		@import url(A);
		"""

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == "")
		#expect(result.remainingCSS == css)
	}

	@Test func emptyStylesheet() {
		let result = CSSImportExtractor.extract(from: "")

		#expect(result.importCSS == "")
		#expect(result.remainingCSS == "")
	}

	@Test func whitespaceOnlyStylesheet() {
		let css = "\n\t  \n"

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == "")
		#expect(result.remainingCSS == css)
	}

	@Test func onlyImports() {
		let css = """
		@import url(A);

		@import url(B);
		"""

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS == css)
		#expect(result.remainingCSS == "")
	}

	@Test func multilineImport() {
		let css = """
		@import
			url("https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap");

		body {
			font-family: "Inter", sans-serif;
		}
		"""

		let result = CSSImportExtractor.extract(from: css)

		#expect(result.importCSS.contains("fonts.googleapis.com"))
		#expect(!result.remainingCSS.contains("@import"))
	}
}
