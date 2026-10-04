//
//  AO3RateLimit.swift
//  AO3Kit
//
//  One cooldown state for every AO3 transport. The state itself lives in
//  RSWeb's Downloader (per lowercased host); this file is the small
//  main-actor bridge that AO3 transports with their own URLSession use to
//  read and write it. Downloader is main-actor isolated, so callers hop
//  with `await`.
//
import Foundation
import RSWeb

public enum AO3RateLimit {

	/// When requests to `url`'s host may resume, or nil when no cooldown is
	/// active.
	@MainActor static func resumeDate(for url: URL) -> Date? {
		guard let host = url.host()?.lowercased() else {
			return nil
		}
		return Downloader.shared.cooldownResumeDate(forHost: host)
	}

	/// Records a 429 seen by a transport that does not go through
	/// Downloader, then returns the resume date it produced.
	@MainActor static func record(url: URL, response: HTTPURLResponse?) -> Date? {
		Downloader.shared.recordRateLimit(url: url, response: response)
		return resumeDate(for: url)
	}

	/// The latest resume date among active cooldowns for any recognized AO3
	/// host, or nil when none is active. Cooldowns are per host, and AO3 has
	/// several recognized hosts, so this is what a person should be told.
	/// Downloader purges expired cooldowns as a side effect of asking.
	@MainActor public static func activeResumeDate() -> Date? {
		AO3Link.recognizedHosts
			.compactMap { Downloader.shared.cooldownResumeDate(forHost: $0) }
			.max()
	}
}
