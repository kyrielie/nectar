//
//  ArticleThemeSmokeTests.swift
//  NetNewsWire-iOSTests
//
//  The all-themes sanity check, split out of `ArticleThemeColorProbeTests` so CI can skip it
//  when nothing theme-related changed (docs/theme-testing.md, "CI scope"). It probes every
//  `Themes/` and `gallery-themes/` bundle, stores nothing, and fails if any measurement is
//  rejected. Results go through `ThemeProbeMeasurementCache`, so a bundle already measured by
//  another suite in the same test process is not loaded again.
//
//  Written without being run in Xcode.
//

import Testing
import Foundation
@testable import Nectar
@testable import ArticleTheming

@MainActor @Suite(.serialized) struct ArticleThemeSmokeTests {

	private static func seconds(_ d: Duration) -> Double {
		Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
	}

	private static func median(_ values: [Double]) -> Double {
		let sorted = values.sorted()
		guard !sorted.isEmpty else {
			return 0
		}
		return sorted[sorted.count / 2]
	}

	@Test(.timeLimit(.minutes(10))) func everyShippedThemePassesTheSanityCheck() async throws {
		let bundled = try ThemeCheckPaths.bundles(in: "Themes")
		let gallery = try ThemeCheckPaths.bundles(in: "gallery-themes")
		#expect(!bundled.isEmpty && !gallery.isEmpty)
		var failures = [String]()
		var times = [Double]()
		var breaker = ConsecutiveNilBreaker()
		var aborted = false
		let clock = ContinuousClock()
		for url in bundled + gallery {
			let theme = try ArticleTheme(url: url, isAppTheme: false)
			let start = clock.now
			let measurement = await ThemeProbeMeasurementCache.measure(theme)
			times.append(Self.seconds(clock.now - start))
			breaker.record(isNil: measurement == nil)
			if measurement == nil {
				failures.append(theme.name)
				if breaker.isTripped {
					aborted = true
					break
				}
			}
		}
		// Acceptance test 5 is a recording, not an assertion. Times include cache hits (near zero).
		print("ThemeColorProbe timing: median \(Self.median(times)) s over \(times.count) themes (plan threshold 0.75 s)\(aborted ? " (aborted by circuit breaker)" : "")")
		#expect(!aborted, "\(breaker.limit) consecutive themes returned no measurement; the run was aborted. This points at the probe or the harness, not at one theme.")
		#expect(failures.isEmpty, "Failed the probe sanity check (investigate the theme or probe, do not lower the floor): \(failures.joined(separator: ", "))")
	}
}
