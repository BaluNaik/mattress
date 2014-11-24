//
//  URLCache.swift
//  Mattress
//
//  Created by David Mauro on 11/12/14.
//  Copyright (c) 2014 BuzzFeed. All rights reserved.
//

import Foundation

public let MattressOfflineCacheRequestPropertyKey = "MattressOfflineCacheRequest"
let URLCacheStoredRequestPropertyKey = "URLCacheStoredRequest"

private let ArbitrarilyLargeSize = 1024 * 1024 * 5 * 20
private let kB = 1024
private let MB = kB * 1024

/*!
    @class URLCache
    URLCache creates an offline diskCache that will
    be stored to when appropriate, and will always be
    checked when retrieving stored responses.
*/
public class URLCache: NSURLCache {
    var offlineCache = DiskCache(path: "offline", searchPathDirectory: .DocumentDirectory, cacheSize: 100 * MB)
    var cachers: [WebViewCacher] = []
    var reachabilityHandler: (() -> Bool)?

    /*
    We need to override these because when deciding
    whether or not to cache, the connection will
    make sure our cache is sufficiently large enough.
    
    TODO: Can we remove this and catch requests that
    didn't get cached in the URLProtocol somehow?
    */
    override public var memoryCapacity: Int {
        get {
            return ArbitrarilyLargeSize
        }
        set (value) {}
    }
    override public var diskCapacity: Int {
        get {
            return ArbitrarilyLargeSize
        }
        set (value) {}
    }

    // Mark: - Class Methods

    class func requestShouldBeStoredOffline(request: NSURLRequest) -> Bool {
        if let value = NSURLProtocol.propertyForKey(MattressOfflineCacheRequestPropertyKey, inRequest: request) as? Bool {
            return value
        }
        return false
    }

    // Mark: - Methods

    override init(memoryCapacity: Int, diskCapacity: Int, diskPath path: String?) {
        super.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: path)
        addToProtocol(true)
    }

    deinit {
        addToProtocol(false)
    }

    func addToProtocol(shouldAdd: Bool) {
        if shouldAdd {
            URLProtocol.addCache(self)
        } else {
            URLProtocol.removeCache(self)
        }
    }

    func webViewCacherOriginatingRequest(request: NSURLRequest) -> WebViewCacher? {
        for cacher in cachers {
            if cacher.didOriginateRequest(request) {
                return cacher
            }
        }
        return nil
    }

    // MARK: - Public

    override public func storeCachedResponse(cachedResponse: NSCachedURLResponse, forRequest request: NSURLRequest) {
        if URLCache.requestShouldBeStoredOffline(request) {
            let success = offlineCache.storeCachedResponse(cachedResponse, forRequest: request)
        } else {
            return super.storeCachedResponse(cachedResponse, forRequest: request)
        }
    }

    public override func cachedResponseForRequest(request: NSURLRequest) -> NSCachedURLResponse? {
        var cachedResponse = offlineCache.cachedResponseForRequest(request)
        if let response = cachedResponse {
            var isOffline = false
            if let handler = reachabilityHandler {
                isOffline = !handler()
            }
            if isOffline {
                let maxAgeResponse = maxAgeModifiedResponseForCachedResponse(response)
                return maxAgeResponse
            }
            return cachedResponse
        }
        return super.cachedResponseForRequest(request)
    }

    public func offlineCacheURL(url: NSURL, loadedHandler: WebViewLoadedHandler) {
        let webViewCacher = WebViewCacher()
        cachers.append(webViewCacher)
        webViewCacher.offlineCacheURL(url, loadedHandler: loadedHandler) { buzzCacher in
            if let index = find(self.cachers, webViewCacher) {
                self.cachers.removeAtIndex(index)
            }
        }
    }

    func maxAgeModifiedResponseForCachedResponse(cachedResponse: NSCachedURLResponse) -> NSCachedURLResponse {
        if let httpResponse = cachedResponse.response as? NSHTTPURLResponse {
            if let url = httpResponse.URL {
                var headers = httpResponse.allHeaderFields
                headers.updateValue("max-age=\(60*60*24*365*10)", forKey: "Cache-Control")
                let newResponse = NSHTTPURLResponse(URL: url, statusCode: httpResponse.statusCode, HTTPVersion: "HTTP/1.1", headerFields: headers)
                if let newResponse = newResponse {
                    let newCachedResponse = NSCachedURLResponse(response: newResponse, data: cachedResponse.data, userInfo: cachedResponse.userInfo, storagePolicy: cachedResponse.storagePolicy)
                    return newCachedResponse
                }
            }
        }
        return cachedResponse // TODO: Can we check on whether we should store this
    }
}
