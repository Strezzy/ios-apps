// Cache raw file metadata before user edits are applied. Restoring it before
// the first library reload keeps album grouping and rendered-cover keys stable
// while launching. Audio replacements invalidate entries by size and mtime.
static NSURL *GMMetadataCacheDirectory(void) {
    NSURL *support=[[[NSFileManager defaultManager] URLsForDirectory:14 inDomains:1] firstObject];
    return [support URLByAppendingPathComponent:@"MusicMetadata-v1"];
}
static NSDictionary *GMMetadataSignature(NSURL *url) {
    NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL];
    id size=attributes[@"NSFileSize"], date=attributes[@"NSFileModificationDate"];
    return size && date ? @{@"size":size,@"modified":date} : nil;
}
static NSURL *GMMetadataEntryURL(GMTrack *track) {
    NSString *identifier=GMTrackIdentifier(track);
    return identifier.length ? [GMMetadataCacheDirectory() URLByAppendingPathComponent:GMMediaDigest([identifier dataUsingEncoding:NSUTF8StringEncoding])] : nil;
}
static BOOL GMRestoreCachedMetadata(GMTrack *track) {
    NSDictionary *signature=GMMetadataSignature(track.url);if(!signature)return NO;
    NSData *data=[NSData dataWithContentsOfURL:GMMetadataEntryURL(track)];
    if(!data.length || data.length>128*1024)return NO;
    id value=[NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if(![value isKindOfClass:[NSDictionary class]])return NO;
    NSDictionary *entry=value;
    if(![entry[@"signature"] isEqual:signature])return NO;
    for(NSString *field in @[@"title",@"artist",@"album",@"albumArtist"])
        if(![entry[field] isKindOfClass:[NSString class]])return NO;
    for(NSString *field in @[@"trackNumber",@"discNumber"])
        if(![entry[field] isKindOfClass:[NSNumber class]])return NO;
    UIImage *artwork=nil;NSString *cover=entry[@"cover"];
    if(cover){
        if(![cover isKindOfClass:[NSString class]] || cover.length!=64 || ![cover isEqual:cover.lastPathComponent])return NO;
        // Shared covers are decoded once during launch, not once per song.
        static NSMapTable *images;
        if(!images)images=[NSMapTable strongToWeakObjectsMapTable];
        artwork=[images objectForKey:cover];
        if(!artwork){
            NSData *png=[NSData dataWithContentsOfURL:[GMMetadataCacheDirectory() URLByAppendingPathComponent:cover]];
            if(!png.length || png.length>12*1024*1024)return NO;
            artwork=[UIImage imageWithData:png];if(!GMStoreValidArtworkImage(artwork))return NO;
            [images setObject:artwork forKey:cover];
        }
    }
    track.title=entry[@"title"];track.artist=entry[@"artist"];track.album=entry[@"album"];track.albumArtist=entry[@"albumArtist"];
    track.trackNumber=[entry[@"trackNumber"] integerValue];track.discNumber=[entry[@"discNumber"] integerValue];
    track.artwork=artwork;track.metadataLoaded=YES;track.metadataSignature=signature;
    return YES;
}
static void GMCacheRawMetadata(GMTrack *track) {
    if(!track.metadataSignature || ![track.metadataSignature isEqual:GMMetadataSignature(track.url)])return;
    NSURL *directory=GMMetadataCacheDirectory();
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableDictionary *entry=[NSMutableDictionary dictionary];
    entry[@"signature"]=track.metadataSignature;
    entry[@"title"]=track.title ?: @"";entry[@"artist"]=track.artist ?: @"";
    entry[@"album"]=track.album ?: @"";entry[@"albumArtist"]=track.albumArtist ?: @"";
    entry[@"trackNumber"]=@(track.trackNumber);entry[@"discNumber"]=@(track.discNumber);
    if(track.artwork){
        // Lossless storage preserves the exact rendered-thumbnail fingerprint.
        NSData *png=UIImagePNGRepresentation(track.artwork);if(!png.length || png.length>12*1024*1024)return;
        NSString *cover=GMMediaDigest(png);NSURL *file=[directory URLByAppendingPathComponent:cover];
        if(![[NSFileManager defaultManager] fileExistsAtPath:file.path] && ![png writeToURL:file options:1 error:NULL])return;
        entry[@"cover"]=cover;
    }
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:entry format:200 options:0 error:NULL];
    [data writeToURL:GMMetadataEntryURL(track) options:1 error:NULL];
}
