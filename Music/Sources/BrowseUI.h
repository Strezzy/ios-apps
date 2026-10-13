// Native offline Songs, Albums, Playlists, and Search navigation controllers.
#ifndef GLASS_MUSIC_BROWSE_UI
#define GLASS_MUSIC_BROWSE_UI
#import "MusicScrollAnimations.h"
@class GMMusicShell;
@interface GMBrowseTableController : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic, weak) GMMusicShell *shell;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic) NSInteger tableStyle;
- (void)reloadLibrary;
- (void)applyTheme;
- (void)refreshPlaybackIndicators;
- (void)resetScrollEntryAnimations;
// A tap closes an exposed action tray before selecting another row.
- (BOOL)closeRevealedActionsIfNeeded;
@end
@interface GMSongsController : GMBrowseTableController @end
@interface GMAlbumsController : GMBrowseTableController
- (void)inspectAlbumWithIdentifier:(NSString *)identifier;
@end
@interface GMPlaylistsController : GMBrowseTableController @end
@interface GMSearchController : GMBrowseTableController <UISearchResultsUpdating,UISearchControllerDelegate>
- (void)performAfterDismissingSearch:(void (^)(void))action;
@end
#endif
