// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Security
@testable import Nuke

let blob = "123".data(using: .utf8)
let otherBlob = "456".data(using: .utf8)

class DataCacheTests: XCTestCase {
    var cache: DataCache!

    override func setUp() {
        cache = try! DataCache(name: UUID().uuidString)
        // Make sure that file names are different from the keys so that we
        // could know for sure that keyEncoder works as expected.
        cache._keyEncoder = { String($0.reversed()) }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.path)
    }

    // MARK: Init

    func testInitWithName() {
        // Given
        let name = UUID().uuidString

        // When
        let cache = try! DataCache(name: name)

        // Then
        XCTAssertEqual(cache.path.lastPathComponent, name)
        XCTAssertNotNil(FileManager.default.fileExists(atPath: cache.path.absoluteString))
    }

    func testInitWithPath() {
        // Given
        let name = UUID().uuidString
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(name)

        // When
        let cache = try! DataCache(path: path)

        // Then
        XCTAssertEqual(cache.path, path)
        XCTAssertNotNil(FileManager.default.fileExists(atPath: path.absoluteString))
    }

    // MARK: Add

    func testAdd() {
        cache._withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache["key"], blob)
        }
    }

    func testWhenAddContentNotFlushedImmediately() {
        cache._withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache.contents.count, 0)
        }
    }

    func testAddAndFlush() {
        // Given
        cache._withSuspendedIO {
            cache["key"] = blob
        }

        // When
        cache.flush()

        // Then
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(cache["key"], blob)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
    }

    func testReplace() {
        cache._withSuspendedIO {
            // Given
            cache["key"] = blob

            // When
            cache["key"] = otherBlob

            // Then
            XCTAssertEqual(cache["key"], otherBlob)
        }
    }

    func testReplaceFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        cache._withSuspendedIO {
            cache["key"] = otherBlob
            XCTAssertEqual(cache.contents.count, 1)
            // Test that before flush we still have the old blob on disk,
            // but new blob in staging
            XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
            XCTAssertEqual(cache["key"], otherBlob)
        }

        // Flush and test that data on disk was updated.
        cache.flush()
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), otherBlob)
        XCTAssertEqual(cache["key"], otherBlob)
    }

    // MARK: Removal

    func testRemoveNonExistent() {
        cache["key"] = nil
        cache.flush()
    }

    // - Remove + write (new) staged -> remove from staging
    func testRemoveFromStaging() {
        cache._withSuspendedIO {
            cache["key"] = blob
            cache["key"] = nil
            XCTAssertNil(cache["key"])
        }
        cache.flush()
        XCTAssertNil(cache["key"])
    }

    // - Remove + write (new) staged -> remove from staging
    func testRemoveReplaced() {
        cache._withSuspendedIO {
            cache["key"] = blob
            cache["key"] = otherBlob
            cache["key"] = nil
        }
        cache.flush()
        XCTAssertNil(cache["key"])
        XCTAssertEqual(cache.contents.count, 0)
    }

    // - Remove + write (replace) staged -> schedule removal
    func testRemoveReplacedFlushed() {
        cache["key"] = blob
        cache.flush()

        cache._withSuspendedIO {
            cache["key"] = otherBlob
            cache["key"] = nil
            XCTAssertNil(cache["key"])
            XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
        }

        cache.flush() // Should still perform deletion of "blob"
        XCTAssertEqual(cache.contents.count, 0)
    }

    // - Remove + flushed -> schedule removal
    func testRemoveFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        cache._withSuspendedIO {
            cache["key"] = nil
            XCTAssertNil(cache["key"])
            // Still have data in cache
            XCTAssertEqual(cache.contents.count, 1)
            XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
        }
        cache.flush()

        XCTAssertNil(cache["key"])

        // IO performed
        XCTAssertEqual(cache.contents.count, 0)
    }

    // - Remove + removal staged -> noop
    func testRemoveWhenRemovalAlreadyScheduled() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = nil
        cache.flush()

        // Then
        XCTAssertEqual(cache.contents.count, 0)
    }

    func testRemoveAndThenReplace() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = blob
        cache.flush()

        // Then
        XCTAssertEqual(cache["key"], blob)
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
    }

    // MARK: Remove All

    func testRemoveAll() {
        cache._withSuspendedIO {
            // Given
            cache["key"] = blob

            // When
            cache.removeAll()

            // Then
            XCTAssertNil(cache["key"])
        }
    }

    func testRemoveAllFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache._withSuspendedIO {
            cache.removeAll()
            XCTAssertNil(cache["key"])
        }
    }

    func testRemoveAllFlushedAndFlush() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache.removeAll()
        cache.flush()

        // Then
        XCTAssertNil(cache["key"])
        XCTAssertEqual(cache.contents.count, 0)
    }

    func testRemoveAllAndAdd() {
        // Given
        cache._withSuspendedIO {
            cache["key"] = blob

            // When
            cache.removeAll()
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache["key"], blob)
        }
    }

    func testRemoveAllTwice() {
        // Given
        cache._withSuspendedIO {
            cache["key"] = blob

            // When
            cache.removeAll()
            cache["key"] = blob
            cache.removeAll()

            // Then
            XCTAssertNil(cache["key"])
        }
    }

    // MARK: DataCaching

    func testGetCachedDataHitFromStaging() {
        // Given
        cache.flush() // Index is loaded

        cache._withSuspendedIO {
            // Given
            cache["key"] = blob

            // When/Then
            let expectation = self.expectation(description: "Data returned")
            cache.cachedData(for: "key") { (data) in
                expectation.fulfill()
                XCTAssertEqual(data, blob)
            }

            wait()
        }
    }

    func testGetCachedData() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When/Then
        let expectation = self.expectation(description: "Data returned")
        cache.cachedData(for: "key") { (data) in
            expectation.fulfill()
            XCTAssertEqual(data, blob)
        }
        wait()
    }

    // MARK: Flush

    func testFlush() {
        // Given
        cache._withSuspendedIO {
            cache["key"] = blob
        }

        // When
        cache.flush()

        // Then
        XCTAssertEqual(cache.contents.count, 1)
    }

    // MARK: Sweep

    func testSweep() {
        // Given
        cache = try! DataCache(path: cache.path)
        cache.countLimit = 4 // we test count limit here
        cache.trimRatio = 0.5 // 1 item should remaing after trim
        cache.sizeLimit = Int.max

        let keys = (0..<4).map { "\($0)" }

        keys.forEach {
            Thread.sleep(forTimeInterval: 1)
            cache[$0] = "123".data(using: .utf8)
            cache.flush()
        }

        // When
        cache.sweep()
        cache.flush()

        // Then
        XCTAssertNil(cache[keys[0]])
        XCTAssertNil(cache[keys[1]])
        XCTAssertNotNil(cache[keys[2]])
        XCTAssertNotNil(cache[keys[3]])
    }

    // MARK: Inspection

    func testTotalCount() {
        XCTAssertEqual(cache.totalCount, 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        XCTAssertEqual(cache.totalCount, 1)
    }

    func testTotalSize() {
        XCTAssertEqual(cache.totalSize, 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        XCTAssertTrue(cache.totalSize > 0)
    }

    func testTotalAllocatedSize() {
        XCTAssertEqual(cache.totalAllocatedSize, 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        // Depends on the file system.
        XCTAssertTrue(cache.totalAllocatedSize > 0)
    }

    // MARK: Intricacies

    func testThatAccessDateIsUpdatedOnRead() {
        // Given
        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        // When

        // First access
        let _ = cache["1"]
        let date1 = cache.contents(keys: [.contentAccessDateKey])
            .first
            .flatMap { $0.meta.contentAccessDate }

        Thread.sleep(forTimeInterval: 1)

        // Second access
        let _ = cache["1"]
        let date2 = cache.contents(keys: [.contentAccessDateKey])
            .first
            .flatMap { $0.meta.contentAccessDate }

        // Then
        XCTAssertNotNil(date1)
        XCTAssertNotNil(date2)
        if let date1 = date1, let date2 = date2 {
            XCTAssertTrue(date1 < date2)
        }
    }
}

extension DataCache {
    var contents: [URL] {
        return try! FileManager.default.contentsOfDirectory(at: self.path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }

    func _withSuspendedIO(_ closure: () -> Void) {
        _wqueue.suspend()
        closure()
        _wqueue.resume()
    }
}
