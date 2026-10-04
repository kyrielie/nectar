//
//  AO3CookieCapture.swift
//  AO3Kit
//
//  Turns the cookies a WKWebView holds after a login or a Cloudflare
//  challenge into the one Cookie header value the app replays. Foundation
//  only, so it is testable without WebKit. The login screen and the
//  challenge solver both used to carry an identical copy of this.
//
import Foundation

public enum AO3CookieCapture {

	/// `name=value; name=value` for the cookies that belong to an AO3
	/// credential host (`AO3Link.isAO3CookieDomain`), in the order given.
	/// Nil when none remain, so a caller never stores an empty session.
	public static func headerValue(from cookies: [HTTPCookie]) -> String? {
		let ao3Cookies = cookies.filter { AO3Link.isAO3CookieDomain($0.domain) }
		guard !ao3Cookies.isEmpty else {
			return nil
		}
		return ao3Cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
	}
}
