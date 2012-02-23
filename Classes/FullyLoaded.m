//
//  FullyLoaded.m
//  FullyLoaded
//
//  Created by Anoop Ranganath on 1/1/11.
//  Copyright 2011 Anoop Ranganath. All rights reserved.
//
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


#import "FullyLoaded.h"
#import "SynthesizeSingleton.h"

#if FullyLoadedErrorLog
#define FLError(...) NSLog(@"FullyLoaded error: " __VA_ARGS__)
#else
#define FLError(...) ((void)0)
#endif

#if FullyLoadedVerboseLog
#define FLLog(...) NSLog(@"FullyLoaded: " __VA_ARGS__)
#else
#define FLLog(...) ((void)0)
#endif


// users can define their own concurrency rules
#ifndef kFullyLoadedMaxConnections
#define kFullyLoadedMaxConnections 2
#endif


#define ASSERT_MAIN_THREAD \
NSAssert1([NSThread isMainThread], @"%@: must be called from the main thread", __FUNCTION__);


static NSString * const FLIdleRunloopNotification = @"FLIdleRunloopNotification";


// encapsulates the result created in the urlQueue thread to pass to main thread. 
@interface FLResponse : NSObject

@property (nonatomic, retain) NSURL *url;
@property (nonatomic, retain) UIImage *image;
@property (nonatomic, retain) NSError *error;

@end


@implementation FLResponse

@synthesize
url     = _url,
image   = _image,
error   = _error;

@end



@interface FullyLoaded()

@property (nonatomic, retain) NSString *imageCachePath;
@property (nonatomic, retain) NSMutableDictionary *imageCache;  // maps urls to images; access must be synchronized
@property (nonatomic, retain) NSMutableArray *urlQueue;         // urls that have not yet been connected
@property (nonatomic, retain) NSMutableSet *pendingURLSet;      // urls in the queue, plus connected urls
@property (nonatomic, retain) NSOperationQueue *responseQueue;  // operation queue for NSURLConnection

@property (nonatomic) int connectionCount; // number of connected urls
@property (nonatomic) BOOL suspended;

- (void)dequeueNextURL;

@end


@implementation FullyLoaded

SYNTHESIZE_SINGLETON_FOR_CLASS(FullyLoaded);

@synthesize
imageCachePath  = _imageCachePath,
imageCache      = _imageCache,
urlQueue        = _urlQueue,
pendingURLSet   = _pendingURLSet,
responseQueue   = _responseQueue,
connectionCount = _connectionCount,
suspended       = _suspended;


- (void)dealloc {
    self.imageCachePath = nil;
    self.imageCache = nil;
    self.urlQueue = nil;
    self.pendingURLSet = nil;
    self.responseQueue = nil;
    [super dealloc];
}


- (id)init {
    self = [super init];
    if (self) {
        self.imageCachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"images"];
        self.imageCache     = [NSMutableDictionary dictionary];
        self.urlQueue       = [NSMutableArray array];
        self.pendingURLSet  = [NSMutableSet set];
        self.responseQueue  = [[NSOperationQueue new] autorelease];
        
        NSNotificationCenter *c = [NSNotificationCenter defaultCenter];
        
        // listen for the idle notification to resume downloads
        [c addObserver:self selector:@selector(resume) name:FLIdleRunloopNotification object:nil];
        
        // note (itsbonczek): iOS sometimes removes old files from /tmp while the app is suspended. When a UIImage loses
        // it's file data, it will try to attempt to restore it from disk. However, if the image happens to have been
        // deleted, UIImage can't restore itself and UIImageView will end up showing a black image. To combat this
        // we delete the in-memory cache whenever the app is backgrounded.
        [c addObserver:self selector:@selector(emptyCache) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}


#pragma mark - FullyLoaded


- (BOOL)connectionsAvailable {
    return self.connectionCount < kFullyLoadedMaxConnections;
}


- (NSString *)pathForURL:(NSURL*)url {
    NSString *hostPath = [self.imageCachePath stringByAppendingPathComponent:url.host];
    return [hostPath stringByAppendingPathComponent:url.path];	
}


- (void)cacheImage:(UIImage *)image forURL:(NSURL *)url {
    
    NSAssert(image, @"nil image");
    NSAssert(url, @"nil url");
    
    @synchronized(self.imageCache) {
        [self.imageCache setObject:image forKey:url];
    }
    
    NSString *path = [self pathForURL:url];
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSError *error = nil;
    
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    
    if (error) {
        FLError(@"creating directory: %@\n%@", dir, error);
        return;
    }

    NSData *jpegData = UIImageJPEGRepresentation(image, 0.8f);
    if (!jpegData) {
        FLError(@"creating jpeg data: %@", url);
        return;
    }
    
    [jpegData writeToFile:path options:NSDataWritingAtomic error:&error];
    
    if (error) {
        FLError(@"writing to file: %@\n%@", path, error);
    }
    else {
        FLLog(@"cached: %@", url);
        // FLLog(@"at path: %@", path);
    }
}


- (void)cacheImage:(UIImage *)image forURLString:(NSString *)urlString {
    
    [self cacheImage:image forURL:[NSURL URLWithString:urlString]];
}


- (UIImage *)retrieveImageForURL:(NSURL *)url {
    
    UIImage *image = [UIImage imageWithContentsOfFile:[self pathForURL:url]];
    
    if (image) {
        @synchronized(self.imageCache) {
            [self.imageCache setObject:image forKey:url];
        }
    }
    
    FLLog(@"retrieved: %@", url);
    return image;
}



- (void)fetchURL:(NSURL *)url {
    
    NSURLRequest *request = [[[NSURLRequest alloc] initWithURL:url] autorelease];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.responseQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               
                               FLResponse *r = [[FLResponse new] autorelease];
                               
                               r.url = response.URL;
                               r.error = error;
                               
                               if (!r.error) {
                                   r.image = [UIImage imageWithData:data];
                                   
                                   if (r.image) {
                                       [self cacheImage:r.image forURL:r.url];
                                   }
                               }
                               
                               [self performSelectorOnMainThread:@selector(handleResponse:)
                                                      withObject:r
                                                   waitUntilDone:NO];
                           }];    
}



- (void)fetchOrEnqueueURL:(NSURL *)url {
    ASSERT_MAIN_THREAD; // pendingURLSet is not synchronized
    
    NSAssert(![self.pendingURLSet containsObject:url], @"pendingURLSet already contains url: %@", url);
    
    [self.pendingURLSet addObject:url];
    
    if (self.connectionsAvailable) {
        [self fetchURL:url];
    }
    else {
        [self.urlQueue addObject:url];
    }
}


- (void)dequeueNextURL {
    NSAssert(self.connectionsAvailable, @"exceeded max connection count: %d", self.connectionCount);
    
    if (!self.urlQueue.count) return;
    
    NSURL *url = [self.urlQueue objectAtIndex:0];
    [url retain];
    [self.urlQueue removeObjectAtIndex:0];
    [self fetchURL:url];
    [url release];
}


- (void)handleResponse:(FLResponse *)response {
    ASSERT_MAIN_THREAD; // pendingURLSet is not synchronized
    
    if (response.error) {
        FLError(@"connection: %@", response.error);
    }
    else {
        // TODO: could always post (or post separate failuer note), include url and error in userInfo
        [[NSNotificationCenter defaultCenter] postNotificationName:FLImageLoadedNotification object:self];
    }
    
    [self.pendingURLSet removeObject:response.url];
    [self dequeueNextURL];
}


- (void)emptyCache {
    FLLog(@"emptying Cache");
    @synchronized(self.imageCache) {
        [self.imageCache removeAllObjects];
    }
}


- (void)suspend {
    FLLog(@"suspend");
    
    self.suspended = YES;
    self.responseQueue.suspended = YES;
    
    // whenever the run loop becomes idle, this notification will get posted, and the queue will resume downloading
    NSNotification *n = [NSNotification notificationWithName:FLIdleRunloopNotification object:self];
    [[NSNotificationQueue defaultQueue] enqueueNotification:n postingStyle:NSPostWhenIdle];	
}


// called manually or in response to the idle run loop notification
- (void)resume {
    FLLog(@"resume");
    
    self.suspended = NO;
    self.responseQueue.suspended = NO;
    
    if (self.connectionsAvailable) {
        [self dequeueNextURL];
    }
}


- (UIImage *)imageForURL:(NSURL *)url {
    
    if (!url) {
        FLLog(@"nil url");
        return nil;
    }
    
    UIImage *image;
    
    @synchronized(self.imageCache) {
        image = [self.imageCache objectForKey:url];
    }
    
    if (image) return image;
    
    if ((image = [self retrieveImageForURL:url])) {
        return image;
    }
    
    if (![self.pendingURLSet containsObject:url]) {
        [self fetchOrEnqueueURL:url];
    }
    return nil;
}


- (UIImage *)imageForURLString:(NSString *)urlString {
    return [self imageForURL:[NSURL URLWithString:urlString]];
}


@end
