//
//  FLImageView.m
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


#import "FLImageView.h"
#import "FullyLoaded.h"


@interface FLImageView()

@property (nonatomic, readwrite, retain) NSURL *url;
@property (nonatomic, readwrite, retain) UIActivityIndicatorView *activityIndicatorView;

- (void)populateImage:(UIImage *)image;
- (UIImage*)scaledImageJustifiedLeft:(UIImage*)image;
- (void)setLoading:(BOOL)isLoading;
- (void)configureActivityIndicatorView;

@end


@implementation FLImageView

@synthesize
url                     = _url,
autoresizeEnabled       = _autoresizeEnabled,
showsLoadingActivity    = _showsLoadingActivity,
activityIndicatorView   = _activityIndicatorView;


- (void)dealloc {
    self.url = nil; // removes observer
    self.activityIndicatorView = nil;
    [super dealloc];
}


- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.autoresizeEnabled = NO;
        self.contentScaleFactor = [UIScreen mainScreen].scale;
        self.contentMode = UIViewContentModeScaleAspectFit;
    }
    return self;
}


- (id)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if (self) {
        self.contentMode = UIViewContentModeScaleAspectFit;
    }
    return self;
}


- (void)setUrl:(NSURL *)url {
    [url retain];
    [_url release];
    _url = url;
    
    NSNotificationCenter *c = [NSNotificationCenter defaultCenter];
    [c removeObserver:self];
    
    if (self.url) {
        // note: because NSNotificationCenter does pointer lookup on the sender object,
        // we cannot reliably filter by URL using notifications.
        [c addObserver:self selector:@selector(imageLoaded:) name:FLImageLoadedNotification object:nil];
    }
}

    
- (void)prepareForReuse {
    self.url = nil;
    self.image = nil;
}


- (void)loadImageAtURL:(NSURL *)url placeholderImage:(UIImage *)placeholderImage {
    
    self.url = url; // sets up observer
    self.image = nil;

    UIImage *image = [[FullyLoaded sharedFullyLoaded] imageForURL:url];
    if (image) {
        [self populateImage:image];
    }
    else {
        [self populateImage:placeholderImage];
        
        //only show image loading if we're going to the network to fetch it
        if (self.showsLoadingActivity) {
            [self setLoading:YES];
        }
    }
}


- (void)loadImageAtURLString:(NSString *)urlString placeholderImage:(UIImage *)placeholderImage {
    [self loadImageAtURL:[NSURL URLWithString:urlString] placeholderImage:placeholderImage];
}


- (void)imageLoaded:(NSNotification *)note {
    
    FLLog(@"note %10p: %@", self, note.object);
    
    if (![note.object isEqual:self.url]) return;
    
    UIImage *image = [[FullyLoaded sharedFullyLoaded] cachedImageForURL:self.url];
    if (image && image != self.image) {
        [self populateImage:image];
    }
    
    if (self.showsLoadingActivity) {
        [self setLoading:NO];
    }
}


#pragma mark - Overrides


- (void)setShowsLoadingActivity:(BOOL)showsLoadingActivity {
    
    _showsLoadingActivity = showsLoadingActivity;
    
    if (showsLoadingActivity) {
        if (!self.activityIndicatorView) {
            [self configureActivityIndicatorView];
        }
    }
    else {
        [self.activityIndicatorView removeFromSuperview];
        self.activityIndicatorView = nil;
    }
}


#pragma mark - Private


- (void)populateImage:(UIImage *)image {
    
    self.image = image;
    
    if (self.autoresizeEnabled) {
        CGRect f = self.frame;
        CGFloat scale = [UIScreen mainScreen].scale;
        f.size.width = image.size.width / scale;
        f.size.height = image.size.height / scale;
        self.frame = f;
    }
}


// create an image the size of the current bounds, with content left-justified
// in the future this could be refactored with a justification enum of (left|center|right)
// justifyImage:(UIImage*) x:(justification) y:(justification)
- (UIImage *)scaledImageJustifiedLeft:(UIImage*)image {
    
    CGSize is = image.size;         // image size
    CGSize bs = self.bounds.size;   // bounds size
    
    // don't bother with strange sizes
    if (is.width < 1 || is.height < 1 || bs.width < 1 || bs.height < 1) return nil;
    
    // aspect ratios
    CGFloat i_ar = is.width / is.height;
    CGFloat b_ar = bs.width / bs.height;
    
    CGFloat scale;
    if (i_ar < b_ar) { // image is thinner than bounds; fit height
        scale = bs.height / is.height;
    }
    else { // image is fatter than bounds; fit width
        scale = bs.width / is.width;
    }
    
    CGRect r; // draw rect, relative to bounds size; draw the entire image into this rect
    r.size = CGSizeMake(is.width * scale, is.height * scale);
    
    // justification is hard-coded to x:left y:center; to generalize add justification cases for x and y 
    r.origin = CGPointMake(0, (bs.height - r.size.height) * 0.5);
    
    UIGraphicsBeginImageContextWithOptions(bs, NO, [UIScreen mainScreen].scale);
    [image drawInRect:r];
    UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    LOG_SIZE(is);
    LOG_SIZE(bs);
    LOG_SIZE(res.size);
    
    return res;
}


// if YES, shows and animates the activity indicator at the center of the view
- (void)setLoading:(BOOL)isLoading {
    if (isLoading) {
        [self.activityIndicatorView startAnimating];
    }
    else {
        [self.activityIndicatorView stopAnimating];
    }
}


// sets up self.activityIndicatorView and adds it as a subview
- (void)configureActivityIndicatorView {
    self.activityIndicatorView = 
    [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray] autorelease];
    
    // center the indicator
    CGRect activityIndicatorFrame = self.activityIndicatorView.frame;
    activityIndicatorFrame.origin.x = (self.frame.size.width / 2.f) - (activityIndicatorFrame.size.width / 2.f);
    activityIndicatorFrame.origin.y = (self.frame.size.height / 2.f) - (activityIndicatorFrame.size.height / 2.f);
    self.activityIndicatorView.frame = activityIndicatorFrame;
    
    self.activityIndicatorView.hidesWhenStopped = YES;
    
    [self addSubview:self.activityIndicatorView];
}

@end
