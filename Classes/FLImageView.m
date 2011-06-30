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

@property (nonatomic, readwrite, retain) NSString *imageURLString;

- (void)populateImage:(UIImage *)anImage;

@end

@implementation FLImageView

@synthesize autoresizeEnabled = _autoresizeEnabled,
            imageURLString = _imageURLString;


- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.autoresizeEnabled = NO;
        self.contentMode = UIViewContentModeScaleAspectFit;
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(imageLoaded:)
                                                     name:FLImageLoadedNotification 
                                                   object:nil];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.contentMode = UIViewContentModeScaleAspectFit;
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(imageLoaded:)
                                                     name:FLImageLoadedNotification 
                                                   object:nil];
    }
    return self;
}

- (void)loadImageAtURLString:(NSString *)aString placeholderImage:(UIImage *)placeholderImage {
    
    self.imageURLString = aString;
    self.image = nil;
    
    UIImage *anImage = [[FullyLoaded sharedFullyLoaded] imageForURL:self.imageURLString];
    if (anImage != nil) {
        [self populateImage:anImage];
    } else {
        [self populateImage:placeholderImage];
    }
}

- (void)imageLoaded:(NSNotification *)aNote {
    UIImage *anImage = [[FullyLoaded sharedFullyLoaded] imageForURL:self.imageURLString];
    if (anImage) {
        [self populateImage:anImage];
    }
}

- (void)populateImage:(UIImage *)anImage {
    self.image = anImage;
    if (self.autoresizeEnabled) {
        UIScreen *screen = [UIScreen mainScreen];
        if ([screen respondsToSelector:@selector(scale)] && self.image.scale != screen.scale) {
            self.image = [UIImage imageWithCGImage:self.image.CGImage scale:screen.scale orientation:UIImageOrientationUp];
        }
        CGRect imageFrame = self.frame;
        imageFrame.size = self.image.size;
        self.frame = imageFrame;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:FLImageLoadedNotification
                                                  object:nil];
    self.imageURLString = nil;
    [super dealloc];
}


@end
