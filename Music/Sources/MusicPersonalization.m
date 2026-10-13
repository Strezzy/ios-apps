// Imported after the shared appearance, artwork and local-store helpers.
#import "MusicPersonalization.h"

static const NSUInteger GMPMaximumFontBytes = 16 * 1024 * 1024;
static const NSUInteger GMPMaximumImageBytes = 12 * 1024 * 1024;
static const NSUInteger GMPMaximumManifestBytes = 128 * 1024;
static const NSUInteger GMPMaximumFonts = 32;
static GMPersonalizationStore *GMPSharedStore;
static NSMapTable<UIFont *, UIFont *> *GMPFontBaselines;
static NSMapTable<UIView *, UIFont *> *GMPViewBaselines;

static NSError *GMPError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.billy.glassmusic.personalization" code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}

// Stream through a strict byte budget, including providers with no known size.
// No timestamp or file-size metadata APIs are needed.
static NSData *GMPReadBounded(NSURL *url, NSUInteger limit, NSError **error) {
    if (error) *error = nil;
    NSError *issue = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:&issue];
    if (!handle) { if (error) *error = issue ?: GMPError(1,@"The file couldn't be opened."); return nil; }
    NSMutableData *data = [NSMutableData new];
    while (data.length <= limit) {
        NSUInteger remaining = limit + 1 - data.length;
        NSData *chunk = [handle readDataUpToLength:remaining < 65536 ? remaining : 65536 error:&issue];
        if (!chunk) { issue = issue ?: GMPError(1,@"The file couldn't be read completely."); break; }
        if (issue) break;
        if (!chunk.length) break;
        [data appendData:chunk];
    }
    NSError *closeIssue = nil;
    [handle closeAndReturnError:&closeIssue];
    if (!issue) issue = closeIssue;
    if (!issue && (!data.length || data.length > limit))
        issue = GMPError(2,@"The file is empty or larger than the supported limit.");
    if (issue) { if (error) *error = issue; return nil; }
    return data;
}

static BOOL GMPValidName(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] > 0 && [value length] <= 255 &&
        [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound;
}
static BOOL GMPValidFilename(id value, BOOL font) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *filename = value, *extension = filename.pathExtension.lowercaseString;
    if (![filename isEqualToString:filename.lastPathComponent] || filename.length > 44) return NO;
    if (font ? !([extension isEqualToString:@"ttf"] || [extension isEqualToString:@"otf"]) : ![extension isEqualToString:@"png"]) return NO;
    return [[NSUUID alloc] initWithUUIDString:filename.stringByDeletingPathExtension] != nil;
}

static NSArray<NSString *> *GMPFontNamesAtURL(NSURL *url, NSError **error) {
    CFArrayRef descriptors = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
    if (!descriptors) { if (error) *error = GMPError(3,@"That file doesn't contain a readable OpenType or TrueType font."); return nil; }
    CFIndex count = CFArrayGetCount(descriptors);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    BOOL valid = count > 0 && count <= 64;
    for (CFIndex index = 0; valid && index < count; index++) {
        CTFontDescriptorRef descriptor = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descriptors,index);
        CFTypeRef copiedName = CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute);
        id name = (__bridge id)copiedName;
        if (!GMPValidName(name)) valid = NO;
        else if (![names containsObject:name]) [names addObject:[name copy]];
        if (copiedName) CFRelease(copiedName);
    }
    CFRelease(descriptors);
    if (!valid || !names.count) {
        if (error) *error = GMPError(4,@"That font has unsupported or invalid face information.");
        return nil;
    }
    return names;
}

@interface GMPFontDraft : NSObject
@property(nonatomic, copy) NSURL *url;
@property(nonatomic, copy) NSString *filename;
@property(nonatomic, copy) NSArray<NSString *> *fontNames;
@property(nonatomic) BOOL registered;
@property(nonatomic) BOOL committed;
@end

@implementation GMPFontDraft
- (void)dealloc {
    if (self.committed) return;
    BOOL safeToRemove = YES;
    if (self.registered) {
        CFErrorRef issue = NULL;
        safeToRemove = CTFontManagerUnregisterFontsForURL((__bridge CFURLRef)self.url,kCTFontManagerScopeProcess,&issue);
        if (issue) CFRelease(issue);
    }
    // If CoreText still has a live user of a canceled face, leave its private,
    // unreferenced file in place for this process instead of breaking that user.
    if (safeToRemove && self.url) [[NSFileManager defaultManager] removeItemAtURL:self.url error:NULL];
}
@end

@interface GMPersonalizationStore ()
@property(nonatomic, readwrite, copy) NSURL *directoryURL;
@property(nonatomic, readwrite, copy) NSString *selectedFontName;
@property(nonatomic, readwrite, strong) NSError *lastError;
@property(nonatomic, copy) NSArray<NSDictionary *> *fontRecords;
@property(nonatomic, copy) NSString *iconFilename;
@property(nonatomic) BOOL loadedSuccessfully;
- (NSURL *)manifestURL;
- (NSURL *)fontsURL;
- (NSURL *)iconsURL;
- (BOOL)fail:(NSError *)issue error:(NSError **)error;
- (BOOL)readyWithError:(NSError **)error;
- (BOOL)commitFonts:(NSArray<NSDictionary *> *)fonts selectedName:(NSString *)name iconFilename:(NSString *)iconFilename error:(NSError **)error;
- (GMPFontDraft *)prepareFontData:(NSData *)data extension:(NSString *)extension error:(NSError **)error;
- (BOOL)saveFontDraft:(GMPFontDraft *)draft error:(NSError **)error;
- (BOOL)saveCustomIcon:(UIImage *)image error:(NSError **)error;
- (UIImage *)customIcon;
@end

@implementation GMPersonalizationStore
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL {
    self = [super init];
    if (self) { self.directoryURL = directoryURL; self.fontRecords = [NSArray array]; [self reloadWithError:NULL]; }
    return self;
}
- (NSURL *)manifestURL { return [self.directoryURL URLByAppendingPathComponent:@"Personalization.plist"]; }
- (NSURL *)fontsURL { return [self.directoryURL URLByAppendingPathComponent:@"Fonts"]; }
- (NSURL *)iconsURL { return [self.directoryURL URLByAppendingPathComponent:@"Icons"]; }
- (BOOL)fail:(NSError *)issue error:(NSError **)error {
    self.lastError = issue ?: GMPError(5,@"Your personalization changes couldn't be saved.");
    if (error) *error = self.lastError;
    return NO;
}
- (BOOL)readyWithError:(NSError **)error {
    if (error) *error = nil;
    if (!self.loadedSuccessfully) return [self fail:self.lastError ?: GMPError(6,
        @"Your saved personalization couldn't be read. The original file hasn't been changed.") error:error];
    return YES;
}
- (BOOL)reloadWithError:(NSError **)error {
    if (error) *error = nil;
    self.loadedSuccessfully = NO;
    if (!self.directoryURL.isFileURL || !self.directoryURL.path.length)
        return [self fail:GMPError(7,@"Personalization storage is unavailable.") error:error];
    NSURL *manifest = self.manifestURL;
    if (![[NSFileManager defaultManager] fileExistsAtPath:manifest.path]) {
        self.fontRecords = [NSArray array]; self.selectedFontName = nil; self.iconFilename = nil;
        self.loadedSuccessfully = YES; self.lastError = nil; return YES;
    }
    NSError *issue = nil;
    NSData *data = GMPReadBounded(manifest,GMPMaximumManifestBytes,&issue);
    if (!data) return [self fail:issue error:error];
    id document = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&issue];
    if (![document isKindOfClass:[NSDictionary class]] || [document count] < 2 || [document count] > 4)
        return [self fail:issue ?: GMPError(8,@"Saved personalization is invalid. The original file hasn't been changed.") error:error];
    for (id key in document)
        if (![key isEqual:@"formatVersion"] && ![key isEqual:@"fonts"] && ![key isEqual:@"selectedFontName"] && ![key isEqual:@"iconFilename"])
            return [self fail:GMPError(9,@"This personalization format isn't supported. The original file hasn't been changed.") error:error];
    id version = document[@"formatVersion"], fonts = document[@"fonts"], selection = document[@"selectedFontName"], icon = document[@"iconFilename"];
    if (![version isKindOfClass:[NSNumber class]] || [version doubleValue] != 1 ||
        ![fonts isKindOfClass:[NSArray class]] || [fonts count] > GMPMaximumFonts ||
        (selection && !GMPValidName(selection)) || (icon && !GMPValidFilename(icon,NO)))
        return [self fail:GMPError(10,@"Saved personalization is invalid. The original file hasn't been changed.") error:error];
    NSMutableDictionary *used = [NSMutableDictionary dictionary];
    for (id record in fonts) {
        if (![record isKindOfClass:[NSDictionary class]] || [record count] != 2 || !GMPValidFilename(record[@"filename"],YES) ||
            ![record[@"names"] isKindOfClass:[NSArray class]] || ![record[@"names"] count] || [record[@"names"] count] > 64 || used[record[@"filename"]])
            return [self fail:GMPError(11,@"A saved font entry is invalid. The original file hasn't been changed.") error:error];
        used[record[@"filename"]] = @YES;
        NSMutableDictionary *names = [NSMutableDictionary dictionary];
        for (id name in record[@"names"]) {
            if (!GMPValidName(name) || names[name])
                return [self fail:GMPError(12,@"A saved font entry is invalid. The original file hasn't been changed.") error:error];
            names[name] = @YES;
        }
    }
    // Validate the complete manifest before registering anything or allowing a
    // later save. Missing font/image files do not invalidate other settings.
    self.fontRecords = fonts; self.selectedFontName = selection; self.iconFilename = icon;
    self.loadedSuccessfully = YES; self.lastError = nil;
    for (NSDictionary *record in self.fontRecords) {
        NSURL *url = [self.fontsURL URLByAppendingPathComponent:record[@"filename"]];
        NSError *fontIssue = nil;
        NSData *fontData = GMPReadBounded(url,GMPMaximumFontBytes,&fontIssue);
        if (!fontData) { self.lastError = fontIssue; continue; }
        NSArray *actualNames = GMPFontNamesAtURL(url,&fontIssue);
        if (!actualNames || ![actualNames isEqual:record[@"names"]]) { self.lastError = fontIssue ?: GMPError(13,@"A saved font has changed. Music is using an available font instead."); continue; }
        BOOL alreadyAvailable = YES;
        for (NSString *name in actualNames) if (![UIFont fontWithName:name size:16]) alreadyAvailable = NO;
        if (alreadyAvailable) continue;
        CFErrorRef registrationError = NULL;
        BOOL registered = CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,kCTFontManagerScopeProcess,&registrationError);
        if (!registered) self.lastError = GMPError(14,@"An imported font couldn't be registered. Music will use System Default if needed.");
        if (registrationError) CFRelease(registrationError);
    }
    return YES;
}
- (BOOL)commitFonts:(NSArray<NSDictionary *> *)fonts selectedName:(NSString *)name iconFilename:(NSString *)iconFilename error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    if (fonts.count > GMPMaximumFonts || (name && !GMPValidName(name)) || (iconFilename && !GMPValidFilename(iconFilename,NO)))
        return [self fail:GMPError(15,@"The personalization collection has reached its supported limit.") error:error];
    NSMutableDictionary *document = [@{@"formatVersion":@1,@"fonts":fonts} mutableCopy];
    document[@"selectedFontName"] = name; document[@"iconFilename"] = iconFilename;
    NSError *issue = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:document format:200 options:0 error:&issue];
    if (!data || data.length > GMPMaximumManifestBytes) return [self fail:issue ?: GMPError(16,@"The personalization collection is too large.") error:error];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.directoryURL withIntermediateDirectories:YES attributes:nil error:&issue] ||
        ![data writeToURL:self.manifestURL options:1 error:&issue]) return [self fail:issue error:error];
    NSString *oldIcon = self.iconFilename;
    BOOL fontChanged = !((!name && !self.selectedFontName) || [name isEqualToString:self.selectedFontName]);
    self.fontRecords = fonts; self.selectedFontName = name; self.iconFilename = iconFilename; self.lastError = nil;
    if (oldIcon && ![oldIcon isEqualToString:iconFilename])
        [[NSFileManager defaultManager] removeItemAtURL:[self.iconsURL URLByAppendingPathComponent:oldIcon] error:NULL];
    if (fontChanged && self.fontDidChange) self.fontDidChange();
    return YES;
}
- (BOOL)selectFontName:(NSString *)name error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    if (name.length && (!GMPValidName(name) || ![UIFont fontWithName:name size:17]))
        return [self fail:GMPError(17,@"That font isn't available. Choose another installed font or import its TTF or OTF file.") error:error];
    return [self commitFonts:self.fontRecords selectedName:name.length ? name : nil iconFilename:self.iconFilename error:error];
}
- (GMPFontDraft *)prepareFontData:(NSData *)data extension:(NSString *)extension error:(NSError **)error {
    if (![self readyWithError:error]) return nil;
    extension = extension.lowercaseString;
    if (!data.length || data.length > GMPMaximumFontBytes ||
        !([extension isEqualToString:@"ttf"] || [extension isEqualToString:@"otf"])) {
        [self fail:GMPError(18,@"Choose a TTF or OTF font of 16 MB or less.") error:error]; return nil;
    }
    if (self.fontRecords.count >= GMPMaximumFonts) { [self fail:GMPError(19,@"You can keep up to 32 imported font files in Music.") error:error]; return nil; }
    GMPFontDraft *draft = [GMPFontDraft new];
    draft.filename = [[NSUUID UUID].UUIDString stringByAppendingString:[@"." stringByAppendingString:extension]];
    draft.url = [self.fontsURL URLByAppendingPathComponent:draft.filename];
    NSError *issue = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.fontsURL withIntermediateDirectories:YES attributes:nil error:&issue] ||
        ![data writeToURL:draft.url options:1 error:&issue]) { [self fail:issue error:error]; return nil; }
    draft.fontNames = GMPFontNamesAtURL(draft.url,&issue);
    if (!draft.fontNames) { [self fail:issue error:error]; return nil; }
    for (NSString *name in draft.fontNames) {
        if ([UIFont fontWithName:name size:17]) {
            [self fail:GMPError(20,@"This font is already available. Choose its face from Installed Fonts.") error:error]; return nil;
        }
    }
    CFErrorRef registrationError = NULL;
    draft.registered = CTFontManagerRegisterFontsForURL((__bridge CFURLRef)draft.url,kCTFontManagerScopeProcess,&registrationError);
    if (registrationError) CFRelease(registrationError);
    if (!draft.registered || ![UIFont fontWithName:draft.fontNames.firstObject size:17]) {
        [self fail:GMPError(21,@"iOS couldn't load that font. Try a different TTF or OTF file.") error:error]; return nil;
    }
    // This UUID path is already its final location: CoreText forbids moving a
    // registered file. Only the manifest reference is added when Save succeeds.
    return draft;
}
- (BOOL)saveFontDraft:(GMPFontDraft *)draft error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    if (!draft || draft.committed || !draft.registered || !GMPValidFilename(draft.filename,YES) ||
        ![UIFont fontWithName:draft.fontNames.firstObject size:17])
        return [self fail:GMPError(22,@"That font preview is no longer available. Import the file again.") error:error];
    NSMutableArray *updated = [self.fontRecords mutableCopy];
    [updated addObject:@{@"filename":draft.filename,@"names":draft.fontNames}];
    if (![self commitFonts:updated selectedName:draft.fontNames.firstObject iconFilename:self.iconFilename error:error]) return NO;
    draft.committed = YES;
    return YES;
}
- (BOOL)saveCustomIcon:(UIImage *)image error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    if (!image || image.size.width <= 0 || image.size.height <= 0 ||
        image.size.width * image.scale > 1200 || image.size.height * image.scale > 1200)
        return [self fail:GMPError(23,@"That icon image is unavailable or too large.") error:error];
    NSData *data = UIImagePNGRepresentation(image);
    if (!data.length || data.length > 6 * 1024 * 1024)
        return [self fail:GMPError(24,@"The prepared icon couldn't be saved. Choose a simpler image.") error:error];
    NSString *filename = [[NSUUID UUID].UUIDString stringByAppendingString:@".png"];
    NSURL *url = [self.iconsURL URLByAppendingPathComponent:filename];
    NSError *issue = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.iconsURL withIntermediateDirectories:YES attributes:nil error:&issue] ||
        ![data writeToURL:url options:1 error:&issue]) return [self fail:issue error:error];
    if (![self commitFonts:self.fontRecords selectedName:self.selectedFontName iconFilename:filename error:error]) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL]; return NO;
    }
    return YES;
}
- (UIImage *)customIcon {
    if (!GMPValidFilename(self.iconFilename,NO)) return nil;
    NSData *data = GMPReadBounded([self.iconsURL URLByAppendingPathComponent:self.iconFilename],6 * 1024 * 1024,NULL);
    return data ? GMArtworkFromData(data) : nil;
}
@end

void GMLoadPersonalization(void) {
    if (GMPSharedStore) return;
    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:9 inDomains:1] firstObject];
    GMPSharedStore = [[GMPersonalizationStore alloc] initWithDirectoryURL:[documents URLByAppendingPathComponent:@"MusicPersonalization"]];
}
GMPersonalizationStore *GMSharedPersonalization(void) { if (!GMPSharedStore) GMLoadPersonalization(); return GMPSharedStore; }

static CGFloat GMPFontWeight(UIFont *font) {
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    NSNumber *weight = [traits isKindOfClass:[NSDictionary class]] ? traits[UIFontWeightTrait] : nil;
    return [weight isKindOfClass:[NSNumber class]] ? weight.doubleValue : 0;
}
static UIFont *GMPBaselineFont(UIFont *font) { return [GMPFontBaselines objectForKey:font] ?: font; }
UIFont *GMAppFont(CGFloat size, CGFloat weight) {
    UIFont *baseline = [UIFont systemFontOfSize:size weight:weight];
    NSString *name = GMPSharedStore.selectedFontName;
    UIFont *selected = name.length ? [UIFont fontWithName:name size:size] : nil;
    if (!selected) return baseline;
    UIFontDescriptor *descriptor = [selected.fontDescriptor fontDescriptorByAddingAttributes:
        @{UIFontDescriptorTraitsAttribute:@{UIFontWeightTrait:@(weight)}}];
    selected = [UIFont fontWithDescriptor:descriptor size:size] ?: selected;
    if (!GMPFontBaselines) GMPFontBaselines = [NSMapTable weakToStrongObjectsMapTable];
    [GMPFontBaselines setObject:baseline forKey:selected];
    return selected;
}
void GMApplyAppFontToButton(UIButton *button) {
    UIButtonConfiguration *configuration = button.configuration;
    if (!configuration) return;
    // UIKit supplies a fresh native attribute set each time it resolves the
    // configuration. Preserve its intended size/weight across font changes.
    configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
        NSMutableDictionary *attributes = [incoming mutableCopy];
        UIFont *font = attributes[NSFontAttributeName];
        if ([font isKindOfClass:[UIFont class]]) {
            UIFont *baseline = GMPBaselineFont(font);
            attributes[NSFontAttributeName] = GMAppFont(baseline.pointSize,GMPFontWeight(baseline));
        }
        return attributes;
    };
    button.configuration = configuration;
}
static NSDictionary *GMPNavigationAttributes(NSDictionary *original, CGFloat size, CGFloat weight) {
    NSMutableDictionary *updated = [original mutableCopy] ?: [NSMutableDictionary dictionary];
    updated[NSFontAttributeName] = GMAppFont(size,weight);
    return updated;
}
void GMApplyAppFontToNavigation(UINavigationBar *bar) {
    if (!bar) return;
    bar.titleTextAttributes = GMPNavigationAttributes(bar.titleTextAttributes,17,.6);
    bar.largeTitleTextAttributes = GMPNavigationAttributes(bar.largeTitleTextAttributes,34,.7);
    UINavigationBarAppearance *standard = [bar.standardAppearance copy];
    standard.titleTextAttributes = GMPNavigationAttributes(standard.titleTextAttributes,17,.6);
    standard.largeTitleTextAttributes = GMPNavigationAttributes(standard.largeTitleTextAttributes,34,.7);
    bar.standardAppearance = standard;
    if (bar.scrollEdgeAppearance) {
        UINavigationBarAppearance *edge = [bar.scrollEdgeAppearance copy];
        edge.titleTextAttributes = GMPNavigationAttributes(edge.titleTextAttributes,17,.6);
        edge.largeTitleTextAttributes = GMPNavigationAttributes(edge.largeTitleTextAttributes,34,.7);
        bar.scrollEdgeAppearance = edge;
    }
    if (bar.compactAppearance) {
        UINavigationBarAppearance *compact = [bar.compactAppearance copy];
        compact.titleTextAttributes = GMPNavigationAttributes(compact.titleTextAttributes,17,.6);
        compact.largeTitleTextAttributes = GMPNavigationAttributes(compact.largeTitleTextAttributes,34,.7);
        bar.compactAppearance = compact;
    }
}
void GMApplyAppFontToViewTree(UIView *view) {
    if (!view || [view.nextResponder isKindOfClass:[UIFontPickerViewController class]] ||
        [view.nextResponder isKindOfClass:NSClassFromString(@"GMPFontPreviewController")]) return;
    if ([view isKindOfClass:[UINavigationBar class]]) { GMApplyAppFontToNavigation((UINavigationBar *)view); return; }
    if ([view isKindOfClass:[UIButton class]] && [(UIButton *)view configuration]) {
        GMApplyAppFontToButton((UIButton *)view); return;
    }
    UIFont *font = nil;
    if ([view isKindOfClass:[UILabel class]]) font = [(UILabel *)view font];
    else if ([view isKindOfClass:[UITextField class]]) font = [(UITextField *)view font];
    else if ([view isKindOfClass:[UITextView class]]) font = [(UITextView *)view font];
    if (font) {
        if (!GMPViewBaselines) GMPViewBaselines = [NSMapTable weakToStrongObjectsMapTable];
        UIFont *baseline = [GMPViewBaselines objectForKey:view];
        if (!baseline || baseline.pointSize != font.pointSize) {
            baseline = GMPBaselineFont(font); [GMPViewBaselines setObject:baseline forKey:view];
        }
        // Keep the user's elapsed/duration counters at their monospaced digit
        // baseline; app prose and labels follow the chosen face.
        if (!(baseline.fontDescriptor.symbolicTraits & (1U << 10)) &&
            [baseline.fontName.lowercaseString rangeOfString:@"mono"].location == NSNotFound) {
            UIFont *replacement = GMAppFont(baseline.pointSize,GMPFontWeight(baseline));
            if ([view isKindOfClass:[UILabel class]]) [(UILabel *)view setFont:replacement];
            else if ([view isKindOfClass:[UITextField class]]) [(UITextField *)view setFont:replacement];
            else [(UITextView *)view setFont:replacement];
        }
    }
    for (UIView *child in view.subviews) GMApplyAppFontToViewTree(child);
}

static UIVisualEffectView *GMPNewGlass(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = glass && [glass respondsToSelector:@selector(effectWithStyle:)] ? [glass effectWithStyle:0] : nil;
    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect ?: [UIBlurEffect effectWithStyle:6]];
    view.layer.cornerRadius = 24; view.clipsToBounds = YES;
    view.userInteractionEnabled = NO; view.accessibilityElementsHidden = YES;
    return view;
}
static void GMPShowError(UIViewController *presenter, NSString *title, NSError *issue) {
    if (!presenter.view.window || presenter.isBeingDismissed || presenter.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:issue.localizedDescription ?: @"Please try again." preferredStyle:1];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
static void GMPPresentSheet(UIViewController *presenter, UIViewController *content) {
    if (!presenter.view.window || presenter.presentedViewController || presenter.isBeingDismissed) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:content];
    navigation.overrideUserInterfaceStyle = presenter.overrideUserInterfaceStyle;
    navigation.modalPresentationStyle = 1;
    navigation.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent largeDetent]];
    navigation.sheetPresentationController.prefersGrabberVisible = YES;
    navigation.sheetPresentationController.preferredCornerRadius = 28;
    navigation.navigationBar.tintColor = GMCurrentAccent();
    GMApplyAppFontToNavigation(navigation.navigationBar);
    [presenter presentViewController:navigation animated:YES completion:nil];
}
static void GMPAfterFilePicker(UIViewController *presenter, UIDocumentPickerViewController *picker, void (^completion)(void)) {
    // A tiny local file can finish loading before Files' automatic dismissal.
    // UIKit's completion provides the transition boundary without a timer.
    if (presenter.presentedViewController == picker || picker.isBeingDismissed)
        [picker dismissViewControllerAnimated:YES completion:completion];
    else completion();
}
static UIButton *GMPButton(NSString *title, NSString *symbol, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:1];
    [button setTitle:title forState:0];
    if (symbol) [button setImage:[UIImage systemImageNamed:symbol] forState:0];
    [button addTarget:target action:action forControlEvents:(1UL << 6)];
    GMStyleGlassButton(button,NO); GMApplyAppFontToButton(button);
    return button;
}

@interface GMPFontPreviewController : UIViewController
@property(nonatomic, copy) NSString *fontName;
@property(nonatomic, strong) GMPFontDraft *fontDraft;
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *largeSample;
@property(nonatomic, strong) UILabel *bodySample;
@property(nonatomic, strong) UILabel *note;
@property(nonatomic, copy) void (^didSave)(void);
@property(nonatomic) BOOL canceled;
- (void)applyTheme;
@end
@implementation GMPFontPreviewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = self.fontDraft ? @"Import Font" : @"Font Preview";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:0 target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:2 target:self action:@selector(save)];
    self.backdrop = GMNewPageBackdrop(self.view.bounds,NO); [self.view addSubview:self.backdrop];
    self.glass = GMPNewGlass(); [self.view addSubview:self.glass];
    self.nameLabel = GMLabel(self.fontName ?: @"System Default",15,.55,GMSecondaryTextColor()); self.nameLabel.numberOfLines = 2;
    self.largeSample = GMLabel(@"A little music.\nA different feeling.",34,.55,GMPrimaryTextColor()); self.largeSample.numberOfLines = 3;
    self.bodySample = GMLabel(@"Songs, albums, and the moments between.\n\nABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789",18,0,GMPrimaryTextColor()); self.bodySample.numberOfLines = 0;
    self.note = GMLabel(self.fontDraft ? @"This font stays inside Music. Save to keep it and apply it to app text." : @"Save to apply this face to Music. Your system font stays unchanged.",14,0,GMSecondaryTextColor()); self.note.numberOfLines = 3;
    for (UIView *view in @[self.nameLabel,self.largeSample,self.bodySample,self.note]) [self.view addSubview:view];
    [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, top = self.view.safeAreaInsets.top+20;
    self.backdrop.frame = self.view.bounds;
    CGFloat available = self.view.bounds.size.height - top - self.view.safeAreaInsets.bottom;
    CGFloat cardHeight = GMMin(410,GMMax(260,available-104));
    self.glass.frame = CGRectMake(16,top,GMMax(0,width-32),cardHeight);
    self.nameLabel.frame = CGRectMake(36,top+20,GMMax(0,width-72),40);
    self.largeSample.frame = CGRectMake(36,top+72,GMMax(0,width-72),116);
    self.bodySample.frame = CGRectMake(36,top+200,GMMax(0,width-72),GMMax(50,cardHeight-218));
    self.note.frame = CGRectMake(24,top+cardHeight+18,GMMax(0,width-48),70);
}
- (void)applyTheme {
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    self.nameLabel.textColor = GMSecondaryTextColor(); self.note.textColor = GMSecondaryTextColor();
    self.largeSample.textColor = GMPrimaryTextColor(); self.bodySample.textColor = GMPrimaryTextColor();
    self.largeSample.font = self.fontName.length ? [UIFont fontWithName:self.fontName size:34] : [UIFont systemFontOfSize:34 weight:.55];
    self.bodySample.font = self.fontName.length ? [UIFont fontWithName:self.fontName size:18] : [UIFont systemFontOfSize:18 weight:0];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.glass) [self applyTheme]; }
- (void)cancel { self.canceled = YES; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)save {
    if (self.canceled || !self.view.window || self.navigationController.isBeingDismissed) return;
    NSError *issue = nil;
    BOOL saved = self.fontDraft ? [GMSharedPersonalization() saveFontDraft:self.fontDraft error:&issue] :
                                 [GMSharedPersonalization() selectFontName:self.fontName error:&issue];
    if (!saved) { GMPShowError(self,@"Couldn't Save Font",issue); return; }
    if (self.didSave) self.didSave();
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

@interface GMFontSettingsController () <UIFontPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, strong) UILabel *selectionLabel;
@property(nonatomic, strong) UILabel *sample;
@property(nonatomic, strong) UILabel *note;
@property(nonatomic, strong) UIButton *installedButton;
@property(nonatomic, strong) UIButton *importButton;
@property(nonatomic, strong) UIButton *resetButton;
@property(nonatomic, strong) UIDocumentPickerViewController *filePicker;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSUInteger loadGeneration;
- (void)refresh;
- (void)showPreviewName:(NSString *)name draft:(GMPFontDraft *)draft;
@end
@implementation GMFontSettingsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Font";
    self.backdrop = GMNewPageBackdrop(self.view.bounds,NO); [self.view addSubview:self.backdrop];
    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds]; self.scroll.alwaysBounceVertical = YES;
    self.scroll.contentInsetAdjustmentBehavior = 2; [self.view addSubview:self.scroll];
    self.glass = GMPNewGlass(); [self.scroll addSubview:self.glass];
    self.selectionLabel = GMLabel(@"",13,.6,GMSecondaryTextColor()); self.selectionLabel.numberOfLines = 2;
    self.sample = GMLabel(@"Your music.\nYour own type.",32,.55,GMPrimaryTextColor()); self.sample.numberOfLines = 3;
    self.note = GMLabel(@"Choose an installed face, or import a TTF or OTF file up to 16 MB. Imported fonts stay inside Music.",14,0,GMSecondaryTextColor()); self.note.numberOfLines = 0;
    self.installedButton = GMPButton(@"Installed Fonts",@"textformat",self,@selector(installedFonts));
    self.importButton = GMPButton(@"Import Font",@"folder",self,@selector(importFont));
    self.resetButton = GMPButton(@"System Default",@"arrow.counterclockwise",self,@selector(resetFont));
    for (UIView *view in @[self.selectionLabel,self.sample,self.note,self.installedButton,self.importButton,self.resetButton]) [self.scroll addSubview:view];
    [self refresh]; [self applyTheme];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (self.scroll) { [self refresh]; [self applyTheme]; } }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, top = self.view.safeAreaInsets.top+18;
    self.backdrop.frame = self.view.bounds; self.scroll.frame = self.view.bounds;
    self.glass.frame = CGRectMake(16,top,GMMax(0,width-32),190);
    self.selectionLabel.frame = CGRectMake(36,top+18,GMMax(0,width-72),36);
    self.sample.frame = CGRectMake(36,top+60,GMMax(0,width-72),108);
    self.installedButton.frame = CGRectMake(20,top+212,GMMax(0,width-40),52);
    self.importButton.frame = CGRectMake(20,top+276,GMMax(0,width-40),52);
    self.resetButton.frame = CGRectMake(20,top+340,GMMax(0,width-40),52);
    self.note.frame = CGRectMake(26,top+410,GMMax(0,width-52),104);
    self.scroll.contentSize = CGSizeMake(width,top+536+self.view.safeAreaInsets.bottom);
}
- (void)refresh {
    NSString *name = GMSharedPersonalization().selectedFontName;
    BOOL available = !name.length || [UIFont fontWithName:name size:17] != nil;
    self.selectionLabel.text = self.loading ? @"Opening Font…" : name.length ? name : @"System Default";
    self.sample.font = GMAppFont(32,.55);
    self.note.text = !GMSharedPersonalization().loadedSuccessfully ? GMSharedPersonalization().lastError.localizedDescription :
        !available ? @"Your selected font is unavailable, so Music is using System Default. Choose another face or reimport it." :
        @"Choose an installed face, or import a TTF or OTF file up to 16 MB. Imported fonts stay inside Music.";
    self.installedButton.enabled = !self.loading; self.importButton.enabled = !self.loading; self.resetButton.enabled = !self.loading;
}
- (void)applyTheme {
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    self.scroll.backgroundColor = [UIColor clearColor];
    self.selectionLabel.textColor = GMSecondaryTextColor(); self.sample.textColor = GMPrimaryTextColor(); self.note.textColor = GMSecondaryTextColor();
    for (UIButton *button in @[self.installedButton,self.importButton,self.resetButton]) { GMStyleGlassButton(button,NO); GMApplyAppFontToButton(button); }
    GMApplyAppFontToViewTree(self.scroll); GMApplyAppFontToNavigation(self.navigationController.navigationBar);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.scroll) [self applyTheme]; }
- (void)showPreviewName:(NSString *)name draft:(GMPFontDraft *)draft {
    GMPFontPreviewController *preview = [GMPFontPreviewController new];
    preview.fontName = name; preview.fontDraft = draft;
    __weak GMFontSettingsController *weakSelf = self;
    preview.didSave = ^{ [weakSelf refresh]; [weakSelf applyTheme]; };
    GMPPresentSheet(self,preview);
}
- (void)installedFonts {
    if (self.loading || self.presentedViewController) return;
    UIFontPickerViewControllerConfiguration *configuration = [UIFontPickerViewControllerConfiguration new];
    configuration.includeFaces = YES;
    UIFontPickerViewController *picker = [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)fontPickerViewControllerDidCancel:(UIFontPickerViewController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController *)picker {
    NSString *name = [picker.selectedFontDescriptor.postscriptName copy];
    __weak GMFontSettingsController *weakSelf = self;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!GMPValidName(name) || ![UIFont fontWithName:name size:17]) { GMPShowError(weakSelf,@"Font Unavailable",GMPError(25,@"Choose a font that is available on this iPhone.")); return; }
        [weakSelf showPreviewName:name draft:nil];
    }];
}
- (void)resetFont { [self showPreviewName:nil draft:nil]; }
- (void)importFont {
    if (self.loading || self.filePicker || self.presentedViewController) return;
    UTType *ttf = [UTType typeWithFilenameExtension:@"ttf"], *otf = [UTType typeWithFilenameExtension:@"otf"];
    NSMutableArray *types = [NSMutableArray array]; if (ttf) [types addObject:ttf]; if (otf) [types addObject:otf];
    if (!types.count) { GMPShowError(self,@"Fonts Unavailable",GMPError(26,@"iOS couldn't open the font file picker.")); return; }
    self.filePicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    self.filePicker.allowsMultipleSelection = NO; self.filePicker.delegate = self;
    [self presentViewController:self.filePicker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker { if (picker == self.filePicker) self.filePicker = nil; }
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (picker != self.filePicker) return;
    self.filePicker = nil; NSURL *url = urls.firstObject;
    if (!url) return;
    self.loading = YES; NSUInteger generation = ++self.loadGeneration; [self refresh];
    BOOL scoped = [url startAccessingSecurityScopedResource];
    __weak GMFontSettingsController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSError *issue = nil; NSData *data = GMPReadBounded(url,GMPMaximumFontBytes,&issue);
        NSString *extension = [url.pathExtension copy];
        if (scoped) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{
            GMFontSettingsController *owner = weakSelf;
            if (!owner || owner.loadGeneration != generation) return;
            owner.loading = NO; [owner refresh];
            if (!owner.view.window || owner.isBeingDismissed || owner.navigationController.isBeingDismissed) return;
            GMPAfterFilePicker(owner,picker,^{
                if (!owner.view.window || owner.isBeingDismissed || owner.navigationController.isBeingDismissed) return;
                NSError *prepareIssue = issue;
                GMPFontDraft *draft = data ? [GMSharedPersonalization() prepareFontData:data extension:extension error:&prepareIssue] : nil;
                if (!draft) { GMPShowError(owner,@"Couldn't Import Font",prepareIssue); return; }
                [owner showPreviewName:draft.fontNames.firstObject draft:draft];
            });
        });
    });
}
@end

static UIImage *GMPSquareIcon(UIImage *image) {
    if (!image || image.size.width <= 0 || image.size.height <= 0 ||
        image.size.width * image.scale > 1200 || image.size.height * image.scale > 1200) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1024,1024) format:format];
    CGFloat scale = GMMax(1024/image.size.width,1024/image.size.height);
    CGRect crop = CGRectMake((1024-image.size.width*scale)/2,(1024-image.size.height*scale)/2,image.size.width*scale,image.size.height*scale);
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor whiteColor] setFill]; [context fillRect:CGRectMake(0,0,1024,1024)];
        [image drawInRect:crop];
    }];
}

static void GMPExportIcon(UIViewController *presenter, UIImage *image, UIView *source) {
    if (!image || !presenter.view.window || presenter.presentedViewController) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
    share.popoverPresentationController.sourceView = source ?: presenter.view;
    share.popoverPresentationController.sourceRect = source ? source.bounds : CGRectMake(presenter.view.bounds.size.width/2,80,1,1);
    [presenter presentViewController:share animated:YES completion:nil];
}

static void GMPShortcutHelp(UIViewController *presenter) {
    if (!presenter.view.window || presenter.presentedViewController) return;
    NSString *instructions = @"1. Export an icon image and save it to Files.\n\n2. In LiveContainer, open Music's menu and choose Copy Launch URL.\n\n3. In Shortcuts, make a shortcut with that URL and an Open URLs action.\n\n4. Choose Add to Home Screen, tap its icon, and choose your exported image.\n\nFor a separately installed copy of Music, use Shortcuts' Open App action instead. This creates a custom launcher; it doesn't replace Music's bundled icon.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Home Screen Icon" message:instructions preferredStyle:1];
    [alert addAction:[UIAlertAction actionWithTitle:@"Got It" style:0 handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface GMPIconChoiceTile : UIControl
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, strong) UIImageView *preview;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UIImageView *selectionMark;
@property(nonatomic) BOOL chosen;
@property(nonatomic) BOOL importAction;
- (instancetype)initWithName:(NSString *)name image:(UIImage *)image;
- (void)applyTheme;
@end
@implementation GMPIconChoiceTile
- (instancetype)initWithName:(NSString *)name image:(UIImage *)image {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.glass = GMPNewGlass(); [self addSubview:self.glass];
    self.preview = [[UIImageView alloc] initWithImage:image]; self.preview.contentMode = 2;
    self.preview.clipsToBounds = YES; self.preview.userInteractionEnabled = NO; [self addSubview:self.preview];
    self.nameLabel = GMLabel(name,14,.55,GMPrimaryTextColor()); self.nameLabel.textAlignment = 1;
    self.nameLabel.adjustsFontSizeToFitWidth = YES; self.nameLabel.minimumScaleFactor = .8;
    self.nameLabel.userInteractionEnabled = NO; [self addSubview:self.nameLabel];
    self.selectionMark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    self.selectionMark.contentMode = 1; [self addSubview:self.selectionMark];
    self.isAccessibilityElement = YES; self.accessibilityLabel = name; [self applyTheme];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.glass.frame = self.bounds;
    CGFloat side = GMMin(92,GMMin(self.bounds.size.width-28,self.bounds.size.height-52));
    self.preview.frame = CGRectMake((self.bounds.size.width-side)/2,12,side,side);
    self.preview.layer.cornerRadius = side*.22;
    self.nameLabel.frame = CGRectMake(8,self.bounds.size.height-34,GMMax(0,self.bounds.size.width-16),22);
    self.selectionMark.frame = CGRectMake(self.bounds.size.width-29,7,22,22);
}
- (void)applyTheme {
    self.backgroundColor = [UIColor clearColor]; self.tintColor = GMCurrentAccent();
    self.nameLabel.textColor = GMPrimaryTextColor();
    self.selectionMark.tintColor = GMCurrentAccent(); self.selectionMark.hidden = !self.chosen;
    self.glass.layer.borderWidth = self.chosen ? 1.5 : 0;
    self.glass.layer.borderColor = GMCurrentAccent().CGColor;
    self.preview.backgroundColor = self.importAction ? [UIColor clearColor] : [UIColor whiteColor];
    self.preview.tintColor = GMCurrentAccent(); self.preview.contentMode = self.importAction ? 1 : 2;
    self.accessibilityValue = self.chosen ? @"Current app icon" : nil;
    GMApplyAppFontToViewTree(self.nameLabel);
}
@end

@interface GMPIconPreviewController : UIViewController
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, copy) NSString *iconName;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic) BOOL imported;
@property(nonatomic) BOOL savedImage;
@property(nonatomic) BOOL saving;
@property(nonatomic) BOOL canceled;
@property(nonatomic, copy) void (^didSave)(void);
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, strong) UIImageView *preview;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *note;
@property(nonatomic, strong) UIButton *exportButton;
@property(nonatomic, strong) UIButton *helpButton;
- (void)applyTheme;
@end
@implementation GMPIconPreviewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = self.imported ? @"Custom Icon" : @"Icon Preview";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.savedImage ? @"Done" : @"Cancel" style:0 target:self action:@selector(cancel)];
    if (!self.savedImage) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:2 target:self action:@selector(save)];
    self.backdrop = GMNewPageBackdrop(self.view.bounds,NO); [self.view addSubview:self.backdrop];
    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds]; self.scroll.contentInsetAdjustmentBehavior = 2;
    self.scroll.alwaysBounceVertical = YES; [self.view addSubview:self.scroll];
    self.glass = GMPNewGlass(); [self.scroll addSubview:self.glass];
    self.preview = [[UIImageView alloc] initWithImage:self.image]; self.preview.contentMode = 2;
    self.preview.clipsToBounds = YES; self.preview.backgroundColor = [UIColor whiteColor]; [self.scroll addSubview:self.preview];
    self.nameLabel = GMLabel(self.displayName ?: @"Custom Image",23,.65,GMPrimaryTextColor()); self.nameLabel.textAlignment = 1;
    self.note = GMLabel(self.imported ? @"Save this square image in Music, then export it for a custom Home Screen shortcut. iOS doesn't let an imported picture replace the app's bundled icon." :
        @"Save to ask iOS to use this included app icon. Some launch environments, including LiveContainer, may not allow the change.",14,0,GMSecondaryTextColor());
    self.note.numberOfLines = 0; self.note.textAlignment = 1;
    if (self.savedImage) self.note.text = @"This custom image is saved in Music. Export it to use with a Home Screen shortcut.";
    self.exportButton = GMPButton(@"Export Image",@"square.and.arrow.up",self,@selector(exportImage));
    self.helpButton = GMPButton(@"Home Screen Shortcut",@"arrow.up.forward.app",self,@selector(shortcutHelp));
    for (UIView *view in @[self.nameLabel,self.note,self.exportButton,self.helpButton]) [self.scroll addSubview:view];
    [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, top = self.view.safeAreaInsets.top+18;
    self.backdrop.frame = self.view.bounds; self.scroll.frame = self.view.bounds;
    CGFloat side = GMMin(200,GMMax(80,width-104));
    self.glass.frame = CGRectMake(20,top,GMMax(0,width-40),side+98);
    self.preview.frame = CGRectMake((width-side)/2,top+20,side,side); self.preview.layer.cornerRadius = side*.22;
    self.nameLabel.frame = CGRectMake(28,top+side+40,GMMax(0,width-56),30);
    self.note.frame = CGRectMake(28,top+side+114,GMMax(0,width-56),116);
    self.exportButton.frame = CGRectMake(24,top+side+244,GMMax(0,width-48),50);
    self.helpButton.frame = CGRectMake(24,top+side+306,GMMax(0,width-48),50);
    self.scroll.contentSize = CGSizeMake(width,top+side+378+self.view.safeAreaInsets.bottom);
}
- (void)applyTheme {
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent(); self.scroll.backgroundColor = [UIColor clearColor];
    self.nameLabel.textColor = GMPrimaryTextColor(); self.note.textColor = GMSecondaryTextColor();
    GMStyleGlassButton(self.exportButton,NO); GMStyleGlassButton(self.helpButton,NO);
    GMApplyAppFontToViewTree(self.scroll); GMApplyAppFontToNavigation(self.navigationController.navigationBar);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.scroll) [self applyTheme]; }
- (void)cancel { if (self.saving) return; self.canceled = YES; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)exportImage { GMPExportIcon(self,self.image,self.exportButton); }
- (void)shortcutHelp { GMPShortcutHelp(self); }
- (void)save {
    if (self.canceled || self.saving || !self.view.window || self.navigationController.isBeingDismissed) return;
    if (self.imported) {
        NSError *issue = nil;
        if (![GMSharedPersonalization() saveCustomIcon:self.image error:&issue]) { GMPShowError(self,@"Couldn't Save Image",issue); return; }
        if (self.didSave) self.didSave();
        self.savedImage = YES; self.navigationItem.rightBarButtonItem = nil;
        self.navigationItem.leftBarButtonItem.title = @"Done";
        self.note.text = @"Your custom image is saved in Music. Export it below to use with a Home Screen shortcut.";
        return;
    }
    UIApplication *application = [UIApplication sharedApplication];
    NSString *current = application.alternateIconName;
    if ((!current && !self.iconName) || [current isEqualToString:self.iconName]) {
        if (self.didSave) self.didSave(); [self dismissViewControllerAnimated:YES completion:nil]; return;
    }
    if (!application.supportsAlternateIcons) {
        GMPShowError(self,@"Icon Change Unavailable",GMPError(27,@"iOS isn't allowing Music to change its app icon in this launch environment. You can still export the image for a Home Screen shortcut.")); return;
    }
    self.saving = YES; self.navigationItem.rightBarButtonItem.enabled = NO; self.navigationItem.leftBarButtonItem.enabled = NO;
    self.navigationController.modalInPresentation = YES; self.exportButton.enabled = NO; self.helpButton.enabled = NO;
    NSString *requested = [self.iconName copy];
    __weak GMPIconPreviewController *weakSelf = self;
    [application setAlternateIconName:requested completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            GMPIconPreviewController *owner = weakSelf;
            if (!owner) return;
            owner.saving = NO; owner.navigationItem.rightBarButtonItem.enabled = YES; owner.navigationItem.leftBarButtonItem.enabled = YES;
            owner.navigationController.modalInPresentation = NO; owner.exportButton.enabled = YES; owner.helpButton.enabled = YES;
            if (!owner.view.window || owner.canceled || owner.navigationController.isBeingDismissed) return;
            NSString *actual = [[UIApplication sharedApplication] alternateIconName];
            BOOL matches = (!actual && !requested) || [actual isEqualToString:requested];
            if (error || !matches) {
                GMPShowError(owner,@"Couldn't Change Icon",error ?: GMPError(28,@"This launch environment didn't apply the icon. You can export it for a custom shortcut instead.")); return;
            }
            if (owner.didSave) owner.didSave();
            [owner dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}
@end

@interface GMIconPickerController () <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, strong) UILabel *note;
@property(nonatomic, copy) NSArray<GMPIconChoiceTile *> *tiles;
@property(nonatomic, strong) GMPIconChoiceTile *importTile;
@property(nonatomic, strong) GMPIconChoiceTile *customTile;
@property(nonatomic, strong) UIButton *helpButton;
@property(nonatomic, strong) UIImage *savedCustomImage;
@property(nonatomic, strong) UIDocumentPickerViewController *filePicker;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSUInteger loadGeneration;
- (void)refresh;
- (void)showImage:(UIImage *)image iconName:(NSString *)name displayName:(NSString *)displayName imported:(BOOL)imported saved:(BOOL)saved;
@end
@implementation GMIconPickerController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"App Icon";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:2 target:self action:@selector(done)];
    self.backdrop = GMNewPageBackdrop(self.view.bounds,NO); [self.view addSubview:self.backdrop];
    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds]; self.scroll.contentInsetAdjustmentBehavior = 2;
    self.scroll.alwaysBounceVertical = YES; [self.view addSubview:self.scroll];
    self.heading = GMLabel(@"Make it yours",27,.7,GMPrimaryTextColor()); [self.scroll addSubview:self.heading];
    self.note = GMLabel(@"Choose an included icon, or import an image to save and export for a custom shortcut.",14,0,GMSecondaryTextColor());
    self.note.numberOfLines = 3; [self.scroll addSubview:self.note];
    NSArray *names = @[@"Original",@"Noir",@"Ivory",@"Aurora",@"Signal",@"Chrome"];
    NSMutableArray *tiles = [NSMutableArray array];
    for (NSUInteger index = 0; index < names.count; index++) {
        NSString *asset = index ? [NSString stringWithFormat:@"Icon%@Preview.png",names[index]] : @"AppIcon1024.png";
        GMPIconChoiceTile *tile = [[GMPIconChoiceTile alloc] initWithName:names[index] image:[UIImage imageNamed:asset]];
        tile.tag = (NSInteger)index; [tile addTarget:self action:@selector(chooseTile:) forControlEvents:(1UL<<6)];
        [tiles addObject:tile]; [self.scroll addSubview:tile];
    }
    self.tiles = tiles;
    self.importTile = [[GMPIconChoiceTile alloc] initWithName:@"Import Icon" image:[UIImage systemImageNamed:@"plus"]];
    self.importTile.importAction = YES; self.importTile.accessibilityHint = @"Choose an image from Files to preview and save for export.";
    [self.importTile addTarget:self action:@selector(importIcon) forControlEvents:(1UL<<6)]; [self.scroll addSubview:self.importTile];
    self.customTile = [[GMPIconChoiceTile alloc] initWithName:@"Saved Image" image:nil];
    self.customTile.accessibilityHint = @"Preview or export your saved custom image.";
    [self.customTile addTarget:self action:@selector(openSavedImage) forControlEvents:(1UL<<6)]; [self.scroll addSubview:self.customTile];
    self.helpButton = GMPButton(@"Home Screen Shortcut",@"arrow.up.forward.app",self,@selector(shortcutHelp)); [self.scroll addSubview:self.helpButton];
    [self refresh]; [self applyTheme];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (self.scroll) { [self refresh]; [self applyTheme]; } }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, top = self.view.safeAreaInsets.top+12;
    self.backdrop.frame = self.view.bounds; self.scroll.frame = self.view.bounds;
    CGFloat contentWidth = GMMin(650,GMMax(0,width-32)), left = (width-contentWidth)/2;
    self.heading.frame = CGRectMake(left+6,top,GMMax(0,contentWidth-12),36);
    self.note.frame = CGRectMake(left+6,top+44,GMMax(0,contentWidth-12),64);
    NSUInteger columns = contentWidth >= 398 ? 3 : 2;
    CGFloat gap = 12, tileWidth = (contentWidth-gap*(columns-1))/columns;
    CGFloat tileHeight = GMMin(146,GMMax(118,tileWidth+4));
    CGFloat gridTop = top+126;
    for (NSUInteger index = 0; index < self.tiles.count; index++)
        self.tiles[index].frame = CGRectMake(left+(index%columns)*(tileWidth+gap),gridTop+(index/columns)*(tileHeight+gap),tileWidth,tileHeight);
    NSUInteger rows = (self.tiles.count+columns-1)/columns;
    CGFloat importsTop = gridTop+rows*(tileHeight+gap)+10;
    self.importTile.frame = CGRectMake(left,importsTop,tileWidth,tileWidth);
    self.customTile.frame = CGRectMake(left+tileWidth+gap,importsTop,tileWidth,tileWidth);
    self.helpButton.frame = CGRectMake(left+4,importsTop+tileWidth+22,GMMax(0,contentWidth-8),48);
    self.scroll.contentSize = CGSizeMake(width,importsTop+tileWidth+94+self.view.safeAreaInsets.bottom);
}
- (void)refresh {
    NSString *actual = [[UIApplication sharedApplication] alternateIconName];
    NSArray *names = @[@"",@"Noir",@"Ivory",@"Aurora",@"Signal",@"Chrome"];
    for (NSUInteger index = 0; index < self.tiles.count; index++) {
        GMPIconChoiceTile *tile = self.tiles[index];
        tile.chosen = index ? [actual isEqualToString:names[index]] : !actual.length;
        [tile applyTheme]; tile.enabled = !self.loading;
    }
    self.savedCustomImage = [GMSharedPersonalization() customIcon];
    self.customTile.preview.image = self.savedCustomImage; self.customTile.hidden = !self.savedCustomImage;
    self.importTile.nameLabel.text = self.loading ? @"Opening…" : @"Import Icon";
    self.importTile.enabled = !self.loading; self.customTile.enabled = !self.loading;
    [self.view setNeedsLayout];
}
- (void)applyTheme {
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent(); self.scroll.backgroundColor = [UIColor clearColor];
    self.heading.textColor = GMPrimaryTextColor(); self.note.textColor = GMSecondaryTextColor();
    for (GMPIconChoiceTile *tile in self.tiles) [tile applyTheme];
    [self.importTile applyTheme]; [self.customTile applyTheme]; GMStyleGlassButton(self.helpButton,NO);
    GMApplyAppFontToViewTree(self.scroll); GMApplyAppFontToNavigation(self.navigationController.navigationBar);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.scroll) [self applyTheme]; }
- (void)done { self.loadGeneration++; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)shortcutHelp { GMPShortcutHelp(self); }
- (void)showImage:(UIImage *)image iconName:(NSString *)name displayName:(NSString *)displayName imported:(BOOL)imported saved:(BOOL)saved {
    if (!image) { GMPShowError(self,@"Image Unavailable",GMPError(29,@"The icon image couldn't be opened. Choose another image.")); return; }
    GMPIconPreviewController *preview = [GMPIconPreviewController new];
    preview.image = image; preview.iconName = name; preview.displayName = displayName; preview.imported = imported; preview.savedImage = saved;
    __weak GMIconPickerController *weakSelf = self;
    preview.didSave = ^{ [weakSelf refresh]; };
    GMPPresentSheet(self,preview);
}
- (void)chooseTile:(GMPIconChoiceTile *)tile {
    if (self.loading || self.presentedViewController) return;
    NSString *name = tile.tag ? tile.nameLabel.text : nil;
    [self showImage:tile.preview.image iconName:name displayName:tile.nameLabel.text imported:NO saved:NO];
}
- (void)openSavedImage { [self showImage:self.savedCustomImage iconName:nil displayName:@"Custom Image" imported:YES saved:YES]; }
- (void)importIcon {
    if (self.loading || self.filePicker || self.presentedViewController) return;
    self.filePicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    self.filePicker.allowsMultipleSelection = NO; self.filePicker.delegate = self;
    [self presentViewController:self.filePicker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker { if (picker == self.filePicker) self.filePicker = nil; }
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (picker != self.filePicker) return;
    self.filePicker = nil; NSURL *url = urls.firstObject; if (!url) return;
    self.loading = YES; NSUInteger generation = ++self.loadGeneration; [self refresh];
    BOOL scoped = [url startAccessingSecurityScopedResource];
    __weak GMIconPickerController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSError *issue = nil; NSData *data = GMPReadBounded(url,GMPMaximumImageBytes,&issue);
        UIImage *decoded = data ? GMArtworkFromData(data) : nil;
        if (scoped) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{
            GMIconPickerController *owner = weakSelf;
            if (!owner || owner.loadGeneration != generation) return;
            owner.loading = NO; [owner refresh];
            if (!owner.view.window || owner.isBeingDismissed || owner.navigationController.isBeingDismissed) return;
            GMPAfterFilePicker(owner,picker,^{
                if (!owner.view.window || owner.isBeingDismissed || owner.navigationController.isBeingDismissed) return;
                UIImage *square = GMPSquareIcon(decoded);
                if (!square) { GMPShowError(owner,@"Couldn't Import Icon",issue ?: GMPError(30,@"Choose a readable image of 12 MB or less.")); return; }
                [owner showImage:square iconName:nil displayName:@"Custom Image" imported:YES saved:NO];
            });
        });
    });
}
@end
