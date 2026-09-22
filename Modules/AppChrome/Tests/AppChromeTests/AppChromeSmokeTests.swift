import Testing
@testable import AppChrome

@Test func appChromeExposesPaletteCases() {
	#expect(!AccentColor.allCases.isEmpty)
	#expect(!SurfacePalette.allCases.isEmpty)
}
