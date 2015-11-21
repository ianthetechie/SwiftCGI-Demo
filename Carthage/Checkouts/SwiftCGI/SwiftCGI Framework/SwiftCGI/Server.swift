//
//  Server.swift
//  SwiftCGI
//
//  Copyright (c) 2014, Ian Wagner
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that thefollowing conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//


// MARK: Main server class

// NOTE: This class muse inherit from NSObject; otherwise the Obj-C code for
// GCDAsyncSocket will somehow not be able to store a reference to the delegate
// (it will remain nil and no error will be logged).
public class FCGIServer: NSObject {
    // MARK: Properties
    
    public let port: UInt16
    public var requestRouter: Router
//    public var requestHandler: FCGIRequestHandler
    
    public var http404Handler: RequestHandler = { (request) -> HTTPResponse? in
        return HTTPResponse(status: .NotFound, contentType: .TextPlain(.UTF8), body: "HTTP 404 - This isn't the page you're looking for...")
    }
    
    private let delegateQueue: dispatch_queue_t
    private lazy var listener: GCDAsyncSocket = {
        GCDAsyncSocket(delegate: self, delegateQueue: self.delegateQueue)
    }()
    
    
    private var activeSockets: Set<GCDAsyncSocket> = []
    
    private var registeredPreware: [RequestPrewareHandler] = []
    private var registeredMiddleware: [RequestMiddlewareHandler] = []
    private var registeredPostware: [RequestPostwareHandler] = []
    private let backend: Backend
    private let useEmbeddedHTTPServer: Bool
    
    // MARK: Init
    
    public init(port: UInt16, requestRouter: Router, useEmbeddedHTTPServer: Bool = true) {
        self.useEmbeddedHTTPServer = useEmbeddedHTTPServer
        
        if useEmbeddedHTTPServer {
            backend = EmbeddedHTTPBackend()
        } else {
            backend = FCGIBackend()
        }
        
        self.port = port
        self.requestRouter = requestRouter
        
        delegateQueue = dispatch_queue_create("SocketAcceptQueue", DISPATCH_QUEUE_SERIAL)
        super.init()
        
        backend.delegate = self
    }
    
    
    // MARK: Instance methods
    
    public func start() throws {
        try listener.acceptOnPort(port)
    }
    
    // MARK: Pre/middle/postware registration
    
    public func registerPrewareHandler(handler: RequestPrewareHandler) -> Void {
        registeredPreware.append(handler)
    }
    
    public func registerMiddlewareHandler(handler: RequestMiddlewareHandler) -> Void {
        registeredMiddleware.append(handler)
    }
    
    public func registerPostwareHandler(handler: RequestPostwareHandler) -> Void {
        registeredPostware.append(handler)
    }
}

extension FCGIServer: GCDAsyncSocketDelegate {
    public func socket(sock: GCDAsyncSocket!, didAcceptNewSocket newSocket: GCDAsyncSocket!) {
        activeSockets.insert(newSocket)
        
        // Looks like a leak, but isn't.
        let acceptedSocketQueue = dispatch_queue_create("SocketAcceptQueue-\(newSocket.connectedPort)", DISPATCH_QUEUE_SERIAL)
        newSocket.delegateQueue = acceptedSocketQueue
        
        // Tell the backend we have started reading from a new socket
        backend.startReadingFromSocket(newSocket)
    }
    
    public func socketDidDisconnect(sock: GCDAsyncSocket?, withError err: NSError!) {
        if let sock = sock {
            backend.cleanUp(sock)
            activeSockets.remove(sock)
        } else {
            NSLog("WARNING: nil sock disconnect")
        }
    }
    
    public func socket(sock: GCDAsyncSocket!, didReadData data: NSData!, withTag tag: Int) {
        // Tell the backend the socket has send us some data, please process it
        backend.processData(sock, data: data, tag: tag)
    }
}

extension FCGIServer: BackendDelegate {
    // When our backend has parsed a full request, it sends it here for processing
    func finishedParsingRequest(request: Request) {
        var req = request
        
        // TODO: Future - when Swift gets exception handling, wrap this
        for handler in registeredPreware {
            req = handler(request)  // Because we can't correctly force compiler type checking without generic typealiases
        }
        
        if let requestHandler = requestRouter.route(req.path) {
            if var response = requestHandler(req) {
                for handler in registeredMiddleware {
                    response = handler(req, response)
                }
                
                backend.sendResponse(req, response: response)
                
                for handler in registeredPostware {
                    handler(req, response)
                }
                
                req.finish(.Complete)
            } else {
                // TODO: Figure out how this should be handled
                
//                backend.sendResponse(req, response: response)
                
                for handler in registeredPostware {
                    handler(req, nil)
                }
                
                req.finish(.Complete)
            }
        } else {
            // Invoke the overrideable HTTP 404 handler
            if let response = http404Handler(req) {
                backend.sendResponse(req, response: response)
                
                for handler in registeredPostware {
                    handler(req, response)
                }
            } else {
                // Invoke postware anyways, but with a nil argument
                for handler in registeredPostware {
                    handler(req, nil)
                }
            }
            
            req.finish(.Complete)
        }
        
        if let sock = request.socket {
            backend.cleanUp(sock)
        }
    }
}
