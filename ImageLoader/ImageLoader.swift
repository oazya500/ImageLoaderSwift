//
//  ImageLoader.swift
//  ImageLoader
//
//  Created by Hirohisa Kawasaki on 2014/10/16.
//  Copyright (c) 2014年 Hirohisa Kawasaki. All rights reserved.
//

import Foundation
import UIKit

public let ImageLoaderDomain = "swift.imageloader"
internal typealias CompletionHandler = (NSURL, UIImage?, NSError?) -> (Void)

internal class Block: NSObject {

    let completionHandler: CompletionHandler
    init(completionHandler: CompletionHandler) {
        self.completionHandler = completionHandler
    }

}

public class Manager {

    let session: NSURLSession
    let cache: ImageLoaderCacheProtocol

    // MARK: singleton instance
    public class var sharedInstance: Manager {
        struct Singleton {

            static let instance = Manager()
        }

        return Singleton.instance
    }

    init(configuration: NSURLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration(),
        cache: ImageLoaderCacheProtocol = ImageLoaderCache()
        ) {
            self.session = NSURLSession(configuration: configuration)
            self.cache = cache
    }

    // MARK: temporary class
    class LoaderStore: NSObject {

        private let _queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
        private var loaders: Dictionary<NSURL, Loader>  = [NSURL: Loader]()

        private subscript (URL: NSURL) -> Loader? {

            get {
                var loader : Loader?
                dispatch_sync(_queue) {
                    loader = self.loaders[URL]
                }

                return loader
            }

            set {
                dispatch_barrier_async(_queue) {
                    self.loaders[URL] = newValue!
                }
            }
        }

    }
    let store: LoaderStore = LoaderStore()

    // MARK: loading

    internal func load(URL: NSURL) -> Loader {

        if let loader: Loader = self.store[URL] {

            switch loader.status {

            case .Suspended:
                loader.resume()
                return loader

            default:
                return loader
            }

        }

        let request: NSURLRequest = NSURLRequest(URL: URL)
        let task: NSURLSessionDataTask = self.session.dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
            self.taskCompletion(URL, data: data, error: error)
        })

        let loader: Loader = Loader(task: task, delegate: self)
        self.store[URL] = loader
        return loader
    }

    internal func cancel(URL: NSURL, block: Block?) -> Loader? {

        if let loader: Loader = self.store[URL] {

            if block != nil {
                loader.remove(block!)
            }

            return loader
        }

        return nil
    }

    private func taskCompletion(URL: NSURL, data: NSData?, error: NSError?) {

        var image: UIImage?
        if data != nil {
            image = UIImage(data: data!)
            if image != nil {
                self.cache[URL] = data
            }
        }

        if let loader: Loader = self.store[URL] {
            loader.complete(URL, image: image, error: error)
        }

    }

}

public class Loader {

    let delegate: Manager
    let task: NSURLSessionDataTask
    internal var blocks: [Block] = []

    private class var _resuming_queue: dispatch_queue_t {
        struct Static {
            static let queue = dispatch_queue_create("swift.imageloader.queues.resuming", DISPATCH_QUEUE_SERIAL);
        }

        return Static.queue
    }

    init (task: NSURLSessionDataTask, delegate: Manager) {
        self.task = task
        self.delegate = delegate
        self.resume()
    }

    var status: NSURLSessionTaskState {
        get {
            return self.task.state
        }
    }

    internal func completionHandler(completionHandler: (NSURL, UIImage?, NSError?) -> Void) -> Self {

        let block: Block = Block(completionHandler: completionHandler)
        self.blocks += [block]

        return self
    }

    // MARK: task

    internal func suspend() {
        dispatch_async(Loader._resuming_queue) {
            self.task.suspend()
        }
    }

    internal func resume() {
        dispatch_async(Loader._resuming_queue) {
            self.task.resume()
        }
    }

    private func remove(block: Block) {
        // needs to queue with sync
        var blocks: [Block] = []
        for b: Block in self.blocks {
            if !b.isEqual(block) {
                blocks.append(b)
            }
        }

        self.blocks = blocks
    }

    private func complete(URL: NSURL, image: UIImage?, error: NSError?) {

        for block: Block in self.blocks {
            block.completionHandler(URL, image, error)
        }

        self.blocks = []
    }
}

public func load (URL: NSURL?) -> Loader? {
    if (URL != nil) {
        return Manager.sharedInstance.load(URL!)
    }
    return nil
}
