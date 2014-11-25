//
//  DiskCacheTests.swift
//  Mattress
//
//  Created by David Mauro on 11/14/14.
//  Copyright (c) 2014 BuzzFeed. All rights reserved.
//

import XCTest

class DiskCacheTests: XCTestCase {

    override func setUp() {
        // Ensure plist on disk is reset
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 0)
        if let path = diskCache.diskPathForPropertyList()?.path {
            NSFileManager.defaultManager().removeItemAtPath(path, error: nil)
        }
    }

    func testDiskPathForRequestIsDeterministic() {
        let url = NSURL(string: "foo://bar")!
        let request1 = NSURLRequest(URL: url)
        let request2 = NSURLRequest(URL: url)
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        let path = diskCache.diskPathForRequest(request1)
        XCTAssertNotNil(path, "Path for request was nil")
        XCTAssert(path == diskCache.diskPathForRequest(request2), "Requests for the same url did not match")
    }

    func testDiskPathsForDifferentRequestsAreNotEqual() {
        let url1 = NSURL(string: "foo://bar")!
        let url2 = NSURL(string: "foo://baz")!
        let request1 = NSURLRequest(URL: url1)
        let request2 = NSURLRequest(URL: url2)
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        let path1 = diskCache.diskPathForRequest(request1)
        let path2 = diskCache.diskPathForRequest(request2)
        XCTAssert(path1 != path2, "Paths should not be matching")
    }

    func testStoreCachedResponseReturnsTrue() {
        let url = NSURL(string: "foo://bar")!
        let request = NSURLRequest(URL: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: ["foo" : "bar"])
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        let success = diskCache.storeCachedResponse(cachedResponse, forRequest: request)
        XCTAssert(success, "Did not save the cached response to disk")
    }

    func testCachedResponseCanBeArchivedAndUnarchivedWithoutDataLoss() {
        // Saw some old reports of keyedArchiver not working well with NSCachedURLResponse
        // so this is just here to make sure things are working on Apple's end
        let url = NSURL(string: "foo://bar")!
        let request = NSURLRequest(URL: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: ["foo" : "bar"])
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        diskCache.storeCachedResponse(cachedResponse, forRequest: request)

        let restored = diskCache.cachedResponseForRequest(request)
        if let restored = restored {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
    }

    func testCacheReturnsCorrectResponseForRequest() {
        let url1 = NSURL(string: "foo://bar")!
        let request1 = NSURLRequest(URL: url1)
        let cachedResponse1 = cachedResponseWithDataString("hello, world", request: request1, userInfo: ["foo" : "bar"])

        let url2 = NSURL(string: "foo://baz")!
        let request2 = NSURLRequest(URL: url2)
        let cachedResponse2 = cachedResponseWithDataString("goodbye, cruel world", request: request2, userInfo: ["baz" : "qux"])

        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        let success1 = diskCache.storeCachedResponse(cachedResponse1, forRequest: request1)
        let success2 = diskCache.storeCachedResponse(cachedResponse2, forRequest: request2)
        XCTAssert(success1 && success2, "The responses did not save properly")

        let restored1 = diskCache.cachedResponseForRequest(request1)
        if let restored = restored1 {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse1)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
        let restored2 = diskCache.cachedResponseForRequest(request2)
        if let restored = restored2 {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse2)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
    }

    func testStoredRequestIncrementsDiskCacheSizeByFilesize() {
        let url = NSURL(string: "foo://bar")!
        let request = NSURLRequest(URL: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: ["foo" : "bar"])
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024 * 1024)
        XCTAssert(diskCache.currentSize == 0, "Current size should start zeroed out")
        diskCache.storeCachedResponse(cachedResponse, forRequest: request)
        if let path = diskCache.diskPathForRequest(request)?.path {
            if let attributes = NSFileManager.defaultManager().attributesOfItemAtPath(path, error: nil) as? [String: AnyObject] {
                if let fileSize = attributes[NSFileSize] as? NSNumber {
                    let size = fileSize.integerValue
                    XCTAssert(diskCache.currentSize == size, "Disk cache size was not incremented by the correct amount")
                } else {
                    XCTFail("Could not get fileSize from attribute")
                }
            } else {
                XCTFail("Could not get attributes for file")
            }
        } else {
            XCTFail("Did not get a valid path for request")
        }
    }

    func testStoringARequestIncreasesTheRequestCachesSize() {
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        let url = NSURL(string: "foo://bar")!
        let request = NSURLRequest(URL: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: nil)
        XCTAssert(diskCache.requestCaches.count == 0, "Should not start with any request caches")
        diskCache.storeCachedResponse(cachedResponse, forRequest: request)
        XCTAssert(diskCache.requestCaches.count == 1, "requestCaches should be 1")
    }

    func testFilesAreRemovedInChronOrderWhenCacheExceedsMaxSize() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: cacheSize)
        let dataSize = cacheSize/3 + 1

        let url1 = NSURL(string: "foo://bar")!
        let request1 = NSURLRequest(URL: url1)
        let cachedResponse1 = cachedResponseWithDataOfSize(dataSize, request: request1, userInfo: nil)

        let url2 = NSURL(string: "bar://baz")!
        let request2 = NSURLRequest(URL: url2)
        let cachedResponse2 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        let url3 = NSURL(string: "baz://qux")!
        let request3 = NSURLRequest(URL: url3)
        let cachedResponse3 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        diskCache.storeCachedResponse(cachedResponse1, forRequest: request1)
        diskCache.storeCachedResponse(cachedResponse2, forRequest: request2)
        diskCache.storeCachedResponse(cachedResponse3, forRequest: request3) // This should cause response1 to be removed

        let requestCaches = [diskCache.hashForURLString(url2.absoluteString!)!, diskCache.hashForURLString(url3.absoluteString!)!]
        XCTAssert(diskCache.requestCaches == requestCaches, "Request caches did not match expectations")
    }

    func testPlistIsUpdatedAfterStoringARequest() {
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        let url = NSURL(string: "foo://bar")!
        let request = NSURLRequest(URL: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: nil)
        diskCache.storeCachedResponse(cachedResponse, forRequest: request)

        let data = NSKeyedArchiver.archivedDataWithRootObject(cachedResponse)
        let expectedSize = data.length
        let expectedRequestCaches = diskCache.requestCaches
        if let plistPath = diskCache.diskPathForPropertyList()?.path {
            if NSFileManager.defaultManager().fileExistsAtPath(plistPath) {
                if let dict = NSDictionary(contentsOfFile: plistPath) {
                    if let currentSize = dict.valueForKey(DiskCache.DictionaryKeys.cacheSize.rawValue) as? Int {
                        XCTAssert(currentSize == expectedSize, "Current size did not match expected value")
                    } else {
                        XCTFail("Plist did not have currentSize property")
                    }
                    if let requestCaches = dict.valueForKey(DiskCache.DictionaryKeys.requestsFilenameArray.rawValue) as? [String] {
                        XCTAssert(requestCaches == expectedRequestCaches, "Request caches did not match expected value")
                    } else {
                        XCTFail("Plist did not have requestCaches property")
                    }
                }
            } else {
                XCTFail("Could not find plist")
            }
        } else {
            XCTFail("Could not get plist path")
        }
    }

    func testDiskCacheRestoresPropertiesFromPlist() {
        var expectedRequestCaches: [String] = []
        var expectedSize = 0
        autoreleasepool { [unowned self] in
            let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
            let url = NSURL(string: "foo://bar")!
            let request = NSURLRequest(URL: url)
            let cachedResponse = self.cachedResponseWithDataString("hello, world", request: request, userInfo: nil)
            diskCache.storeCachedResponse(cachedResponse, forRequest: request)
            expectedRequestCaches = diskCache.requestCaches
            expectedSize = diskCache.currentSize
        }
        let newDiskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: 1024)
        XCTAssert(newDiskCache.currentSize == expectedSize, "Size property did not match expectations")
        XCTAssert(newDiskCache.requestCaches == expectedRequestCaches, "RequestCaches did not match expectations")
    }

    func testRequestCacheIsRemovedFromDiskAfterTrim() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let diskCache = DiskCache(path: "test", searchPathDirectory: .DocumentDirectory, cacheSize: cacheSize)
        let dataSize = cacheSize/3 + 1

        let url1 = NSURL(string: "foo://bar")!
        let request1 = NSURLRequest(URL: url1)
        let cachedResponse1 = cachedResponseWithDataOfSize(dataSize, request: request1, userInfo: nil)
        let pathForResponse = (diskCache.diskPathForRequest(request1)?.path)!

        let url2 = NSURL(string: "bar://baz")!
        let request2 = NSURLRequest(URL: url2)
        let cachedResponse2 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        let url3 = NSURL(string: "baz://qux")!
        let request3 = NSURLRequest(URL: url3)
        let cachedResponse3 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        diskCache.storeCachedResponse(cachedResponse1, forRequest: request1)
        diskCache.storeCachedResponse(cachedResponse2, forRequest: request2)
        var isFileOnDisk = NSFileManager.defaultManager().fileExistsAtPath(pathForResponse)
        XCTAssert(isFileOnDisk, "File should be on disk")
        diskCache.storeCachedResponse(cachedResponse3, forRequest: request3) // This should cause response1 to be removed
        isFileOnDisk = NSFileManager.defaultManager().fileExistsAtPath(pathForResponse)
        XCTAssertFalse(isFileOnDisk, "File should no longer be on disk")

    }

    // Mark: - Test Helpers

    func assertCachedResponsesAreEqual(#response1 : NSCachedURLResponse, response2: NSCachedURLResponse) {
        XCTAssert(response1.data == response2.data, "Data did not match")
        XCTAssert(response1.response.URL == response2.response.URL, "Response did not match")
        XCTAssert(response1.userInfo!.description == response2.userInfo!.description, "userInfo didn't match")
    }

    func cachedResponseWithDataString(dataString: String, request: NSURLRequest, userInfo: [NSObject : AnyObject]?) -> NSCachedURLResponse {
        let data = dataString.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
        let response = NSURLResponse(URL: request.URL, MIMEType: "text/html", expectedContentLength: data.length, textEncodingName: nil)
        let cachedResponse = NSCachedURLResponse(response: response, data: data, userInfo: userInfo, storagePolicy: .Allowed)
        return cachedResponse
    }

    func cachedResponseWithDataOfSize(dataSize: Int, request: NSURLRequest, userInfo: [NSObject : AnyObject]?) -> NSCachedURLResponse {
        var bytes: [UInt32] = Array(count: dataSize, repeatedValue: 0)
        let data = NSData(bytes: &bytes, length: dataSize)
        let response = NSURLResponse(URL: request.URL, MIMEType: "text/html", expectedContentLength: data.length, textEncodingName: nil)
        let cachedResponse = NSCachedURLResponse(response: response, data: data, userInfo: userInfo, storagePolicy: .Allowed)
        return cachedResponse
    }
}
