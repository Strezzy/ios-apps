#ifndef MUSIC_CD_CASE_H
#define MUSIC_CD_CASE_H

// This view owns only the local CD-case presentation. Playback, navigation,
// selection, and inspection gestures remain in the native Music controllers.
typedef NSInteger GMCDCasePresentation;
enum {
    GMCDCasePresentationGrid = 0,
    GMCDCasePresentationPlayer = 1,
    GMCDCasePresentationInspector = 2,
    GMCDCasePresentationStatic = 3,
    GMCDCasePresentationSnapshot = 4
};

static NSInteger GMLiveMedium = 0; // 0 CD, 1 cassette; persisted with appearance.
static NSString * const GMLiveMediumChanged = @"Music.LiveMediumChanged";

@interface GMCDCaseView : UIView
- (instancetype)initWithFrame:(CGRect)frame presentation:(GMCDCasePresentation)presentation;
@property(nonatomic, readonly, copy) NSString *representedIdentifier;
- (void)configureWithIdentifier:(NSString *)identifier title:(NSString *)title
                        artist:(NSString *)artist artwork:(UIImage *)artwork;
// Owner visibility is combined with actual window/scene visibility. Setting
// active to NO pauses rendering and may cache a bounded idle renderer for reuse.
- (void)setActive:(BOOL)active;
// Move the same renderer between its warm host, transition, and player.
- (void)moveToHost:(UIView *)host frame:(CGRect)frame prewarming:(BOOL)prewarming;
@property(nonatomic, readonly) BOOL readyForDisplay;
- (void)setPlaying:(BOOL)playing;
- (void)setEntranceSpeed:(CGFloat)speed;
- (void)setCaseOpen:(BOOL)open animated:(BOOL)animated;
- (void)setInspectionTiltX:(CGFloat)x y:(CGFloat)y;
- (void)resetInspectionTiltAnimated:(BOOL)animated;
- (void)prepareForReuse;
- (void)applyTheme;
@end

#endif
