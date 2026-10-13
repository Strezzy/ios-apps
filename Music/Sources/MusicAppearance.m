// System=0, Light=1, Dark=2, Dynamic=3. Dynamic follows the system's text
// contrast while the shared local artwork palette supplies every page's color.
// The old Gray preference naturally becomes Dynamic at the same saved value.
static NSInteger GMThemeMode = 0;
static CGFloat GMAccentComponents[3] = {.98,.18,.32};
UIColor *GMCurrentAccent(void) { return GMColor(GMAccentComponents[0],GMAccentComponents[1],GMAccentComponents[2],1); }
UIColor *GMPageColor(void) { return [UIColor systemBackgroundColor]; }
UIColor *GMGroupedColor(void) { return [UIColor systemGroupedBackgroundColor]; }
UIColor *GMCardColor(void) {
    UIColor *color = [UIColor secondarySystemGroupedBackgroundColor];
    return GMThemeMode == 3 ? [color colorWithAlphaComponent:.70] : color;
}
UIColor *GMPrimaryTextColor(void) { return [UIColor labelColor]; }
UIColor *GMSecondaryTextColor(void) { return [UIColor secondaryLabelColor]; }
UIColor *GMSeparatorColor(void) { return [UIColor separatorColor]; }
static void GMReadRGB(UIColor *color, UITraitCollection *traits, CGFloat *r, CGFloat *g, CGFloat *b) {
    UIColor *resolved = traits ? [color resolvedColorWithTraitCollection:traits] : color;
    CGFloat alpha = 1, white = 0;
    if (![resolved getRed:r green:g blue:b alpha:&alpha]) {
        if ([resolved getWhite:&white alpha:&alpha]) *r = *g = *b = white;
        else { *r = .98; *g = .18; *b = .32; }
    }
}
static UIColor *GMBlend(UIColor *base, UIColor *accent, CGFloat amount, UITraitCollection *traits) {
    CGFloat r=0,g=0,b=0,ar=0,ag=0,ab=0;
    GMReadRGB(base,traits,&r,&g,&b); GMReadRGB(accent,traits,&ar,&ag,&ab);
    return GMColor(r*(1-amount)+ar*amount,g*(1-amount)+ag*amount,b*(1-amount)+ab*amount,1);
}
static void GMSetThemeValues(NSInteger mode, UIColor *color) {
    GMThemeMode = mode >= 0 && mode <= 3 ? mode : 0;
    CGFloat r=0,g=0,b=0; GMReadRGB(color,nil,&r,&g,&b);
    GMAccentComponents[0] = (r>=0 && r<=1) ? r : .98;
    GMAccentComponents[1] = (g>=0 && g<=1) ? g : .18;
    GMAccentComponents[2] = (b>=0 && b<=1) ? b : .32;
}
static UIColor *GMAccentForeground(void) {
    CGFloat brightness = .2126*GMAccentComponents[0]+.7152*GMAccentComponents[1]+.0722*GMAccentComponents[2];
    return brightness > .58 ? GMColor(.07,.08,.10,1) : [UIColor whiteColor];
}
static void GMSetButtonImage(UIButton *button, UIImage *image) {
    if (!button) return;
    if (button.configuration) {
        // UIKit refreshes a glass configuration after highlighted/disabled
        // state changes. Reapply the latest glyph after every such refresh,
        // so lifting a finger cannot restore an earlier play/pause image.
        // Capture only the image, never the button or its owning controller.
        button.configurationUpdateHandler = ^(UIButton *updatedButton) {
            UIButtonConfiguration *current = updatedButton.configuration;
            if (!current) return;
            UIButtonConfiguration *configuration = [current copy];
            configuration.image = image;
            updatedButton.configuration = configuration;
        };
        UIButtonConfiguration *configuration = [button.configuration copy];
        configuration.image = image;
        button.configuration = configuration;
        [button setNeedsUpdateConfiguration];
    } else [button setImage:image forState:0];
}
void GMStyleGlassButton(UIButton *button, BOOL prominent) {
    if (!button) return;
    UIButtonConfiguration *existing = button.configuration;
    UIImage *image = existing ? existing.image : [button imageForState:0];
    NSString *title = existing ? existing.title : [button titleForState:0];
    if (!existing) {
        // Move the initial content into the configuration once. Legacy state
        // values must not compete with configuration updates during taps.
        [button setImage:nil forState:0];
        [button setTitle:nil forState:0];
    }
    Class configurationClass = NSClassFromString(@"UIButtonConfiguration");
    UIButtonConfiguration *configuration = nil;
    if ([configurationClass respondsToSelector:@selector(glassButtonConfiguration)]) {
        configuration = prominent ? [configurationClass prominentGlassButtonConfiguration] : [configurationClass glassButtonConfiguration];
    } else {
        configuration = prominent ? [configurationClass filledButtonConfiguration] : [configurationClass tintedButtonConfiguration];
    }
    configuration.image = image; configuration.title = title;
    configuration.baseForegroundColor = prominent ? GMAccentForeground() : GMCurrentAccent();
    configuration.baseBackgroundColor = prominent ? GMCurrentAccent() : [UIColor clearColor];
    configuration.cornerStyle = 4; // UIButtonConfigurationCornerStyleCapsule
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(6,10,6,10);
    button.configuration = configuration;
    button.tintColor = GMCurrentAccent();
    GMApplyAppFontToButton(button);
}

// An accent wash UNDER the native bar gives its unchanged system glass useful
// color to transmit. No private tab-bar subviews or replacement blur materials.
@interface GMContentBackdrop : UIView
@property(strong) CAGradientLayer *wash;
@property(strong) GMArtworkBackdrop *artworkColors;
@property BOOL grouped;
- (void)refreshColors;
@end
@implementation GMContentBackdrop
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.wash = [CAGradientLayer layer];
    self.wash.startPoint = CGPointMake(.25,0); self.wash.endPoint = CGPointMake(.85,1);
    self.wash.locations = @[@0,@.55,@1];
    [self.layer addSublayer:self.wash];
    self.artworkColors = [[GMArtworkBackdrop alloc] initWithFrame:self.bounds];
    self.artworkColors.autoresizingMask = (1UL<<1)|(1UL<<4);
    [self addSubview:self.artworkColors];
    [self refreshColors];
    return self;
}
- (void)refreshColors {
    self.artworkColors.hidden = GMThemeMode != 3;
    self.artworkColors.groupedBackground = self.grouped;
    if (!self.artworkColors.hidden) [self.artworkColors applyTheme];
    UIColor *base = self.grouped ? GMGroupedColor() : GMPageColor();
    CGFloat strength = self.traitCollection.userInterfaceStyle == 2 ? .18 : .10;
    self.wash.colors = @[(__bridge id)[base resolvedColorWithTraitCollection:self.traitCollection].CGColor,
                         (__bridge id)GMBlend(base,GMCurrentAccent(),.018,self.traitCollection).CGColor,
                         (__bridge id)GMBlend(base,GMCurrentAccent(),strength,self.traitCollection).CGColor];
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.wash.frame = self.bounds;
    self.artworkColors.frame = self.bounds;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection]; [self refreshColors];
}
@end
UIView *GMNewPageBackdrop(CGRect frame, BOOL grouped) {
    GMContentBackdrop *backdrop = [[GMContentBackdrop alloc] initWithFrame:frame];
    backdrop.grouped = grouped; [backdrop refreshColors];
    backdrop.autoresizingMask = (1UL<<1)|(1UL<<4);
    return backdrop;
}
void GMApplyPageBackground(UIView *page, UITableView *table, BOOL grouped) {
    page.backgroundColor = grouped ? GMGroupedColor() : GMPageColor();
    table.backgroundColor = [UIColor clearColor];
    GMContentBackdrop *backdrop = [table.backgroundView isKindOfClass:[GMContentBackdrop class]] ? (GMContentBackdrop *)table.backgroundView : nil;
    if (!backdrop) { backdrop = [[GMContentBackdrop alloc] initWithFrame:table.bounds]; table.backgroundView = backdrop; }
    backdrop.grouped = grouped; [backdrop refreshColors];
    table.separatorColor = GMSeparatorColor();
}
