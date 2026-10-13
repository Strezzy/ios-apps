// Bound decoded artwork before it enters the UI, metadata cache, or persistence.
// ImageIO handles HEIC/JPEG/PNG and applies the source's orientation transform.
static UIImage *GMArtworkFromSource(CGImageSourceRef source) {
    if (!source) return nil;
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                              (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
                              (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@1200,
                              (__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES};
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnail) return nil;
    UIImage *image = [UIImage imageWithCGImage:thumbnail scale:1 orientation:0];
    CGImageRelease(thumbnail);
    return image;
}
UIImage *GMArtworkFromURL(NSURL *url) {
    if (!url) return nil;
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceShouldCache:@NO};
    return GMArtworkFromSource(CGImageSourceCreateWithURL((__bridge CFURLRef)url,(__bridge CFDictionaryRef)options));
}
UIImage *GMArtworkFromData(NSData *data) {
    if (!data.length) return nil;
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceShouldCache:@NO};
    return GMArtworkFromSource(CGImageSourceCreateWithData((__bridge CFDataRef)data,(__bridge CFDictionaryRef)options));
}
