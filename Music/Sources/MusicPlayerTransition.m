// One retained WebView moves with the artwork. Its render target stays at the
// destination size while UIKit scales the layer, avoiding resize/shader churn.
@interface GMPlayerCaseTransition : NSObject <UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning>
@property(nonatomic, weak) GMMusicShell *shell;
@property(nonatomic) CGRect sourceRect;
@property(nonatomic,weak) UIView *sourceArtwork;
@property(nonatomic) BOOL presenting;
@end
@implementation GMPlayerCaseTransition
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    self.presenting = YES; return self;
}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    self.presenting = NO; return self;
}
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    return GMCDReducedMotion() ? .2 : (self.presenting ? .5 : .4);
}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    PlayerController *player = self.shell.player;
    UIView *container = context.containerView;
    UIView *page = player.view;
    BOOL presenting = self.presenting, reduced = GMCDReducedMotion();
    player.caseTransitionInProgress = YES;
    if (presenting) {
        player.showingLyrics = NO; player.lyricsView.hidden = YES; player.artView.hidden = NO;
        player.lyricsButton.accessibilityLabel = @"Show lyrics";
        GMStyleGlassButton(player.lyricsButton,NO);
        [container addSubview:page];
        page.frame = [context finalFrameForViewController:player];
        player.artView.transform = CGAffineTransformIdentity;
        [page setNeedsLayout]; [page layoutIfNeeded];
        CGRect destination = [player.artView convertRect:player.artView.bounds toView:container];
        GMCDCaseView *hero = player.cdCaseView;
        [hero setEntranceSpeed:reduced ? 1 : 2.4];
        [hero setCaseOpen:NO animated:NO];
        [hero moveToHost:container frame:destination prewarming:NO];
        CGRect source = [container convertRect:self.sourceRect fromView:container.window];
        if (source.size.width < 2 || source.size.height < 2) source = destination;
        if (!reduced) {
            hero.transform = CGAffineTransformMakeScale(source.size.width/GMMax(1,destination.size.width), source.size.height/GMMax(1,destination.size.height));
            hero.center = CGPointMake(source.origin.x+source.size.width/2,source.origin.y+source.size.height/2);
            page.transform = CGAffineTransformMakeTranslation(0,container.bounds.size.height);
        } else page.alpha = 0;
        hero.alpha=0;
        [UIView animateWithDuration:reduced ? 0 : .12 animations:^{hero.alpha=1;self.sourceArtwork.alpha=0;}];
        player.artworkOwnerVisible = YES;
        [hero setPlaying:player.player.isPlaying];
        [hero setCaseOpen:player.player.isPlaying animated:!reduced];
        [UIView animateWithDuration:[self transitionDuration:context] delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            page.transform = CGAffineTransformIdentity; page.alpha = 1;
            hero.transform = CGAffineTransformIdentity;
            hero.center = CGPointMake(destination.origin.x+destination.size.width/2,destination.origin.y+destination.size.height/2);
        } completion:^(BOOL finished) {
            BOOL cancelled = context.transitionWasCancelled;
            self.sourceArtwork.alpha=1;hero.alpha=1;
            player.caseTransitionInProgress = NO;
            player.playerCaseOpen = player.player.isPlaying;
            if (cancelled) { [hero setEntranceSpeed:1]; [page removeFromSuperview]; [self.shell warmPlayerCase]; }
            else {
                [hero moveToHost:player.artView frame:player.artView.bounds prewarming:NO];
                [player updateArtworkPlaybackStateAnimated:NO];
            }
            [context completeTransition:!cancelled];
        }];
    } else {
        UIView *underlying = [context viewForKey:UITransitionContextToViewKey];
        if (underlying) [container insertSubview:underlying belowSubview:page];
        [UIView animateWithDuration:[self transitionDuration:context] animations:^{
            if (reduced) page.alpha = 0;
            else page.transform = CGAffineTransformMakeTranslation(0,container.bounds.size.height);
        } completion:^(BOOL finished) {
            BOOL cancelled = context.transitionWasCancelled;
            page.transform = CGAffineTransformIdentity; page.alpha = 1;
            player.caseTransitionInProgress = NO;
            if (!cancelled) [page removeFromSuperview];
            [context completeTransition:!cancelled];
            if (!cancelled) [self.shell warmPlayerCase];
            else { player.artworkOwnerVisible = YES; [player updateCDCaseActivity]; }
        }];
    }
}
@end
