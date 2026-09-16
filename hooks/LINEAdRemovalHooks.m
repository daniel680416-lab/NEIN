// Disable known advertising loaders and remove their views without touching
// chat content or ordinary LINE network requests.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include "LINEObjCRuntime.h"

typedef void (*LMVoidObjectIMP)(id, SEL, id);
typedef void (*LMVoidObjectObjectIMP)(id, SEL, id, id);
typedef void (*LMVoidNoArgIMP)(id, SEL);
typedef void (*LMVoidBoolIMP)(id, SEL, BOOL);

static BOOL LMHook(Class cls, SEL selector, const char *returnType,
                   unsigned argumentCount, const char *argument2,
                   const char *argument3, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!LMMethodHasType(method, returnType, argumentCount, argument2, argument3)) {
        return NO;
    }
    if (original) *original = method_getImplementation(method);
    method_setImplementation(method, replacement);
    return YES;
}

static BOOL LMHookClassMethodOnly(Class cls, SEL selector, const char *returnType,
                                  unsigned argumentCount, const char *argument2,
                                  const char *argument3, IMP replacement,
                                  IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!LMMethodHasType(method, returnType, argumentCount, argument2, argument3)) {
        return NO;
    }
    IMP previous = method_getImplementation(method);
    if (original) *original = previous;
    const char *encoding = method_getTypeEncoding(method);
    if (!class_addMethod(cls, selector, replacement, encoding)) {
        method_setImplementation(method, replacement);
    }
    return YES;
}

static void LMNoopObject(id self, SEL selector, id object) {
    (void)self;
    (void)selector;
    (void)object;
}

static void LMNoopObjectObject(id self, SEL selector, id object, id handler) {
    (void)self;
    (void)selector;
    (void)object;
    (void)handler;
}

static void LMNoopNoArg(id self, SEL selector) {
    (void)self;
    (void)selector;
}

static NSError *LMAdLoadBlockedError(void) {
    return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled
                           userInfo:@{NSLocalizedDescriptionKey: @"Advertising disabled"}];
}

static void LMFailAdLoad(id self, SEL selector, id unitID, id request, id completion) {
    (void)self;
    (void)selector;
    (void)unitID;
    (void)request;
    if (!completion) return;
    void (^handler)(id, NSError *) = [completion copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil, LMAdLoadBlockedError());
    });
}

static BOOL LMNameContains(NSString *name, NSArray<NSString *> *tokens) {
    for (NSString *token in tokens) {
        if ([name rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSString *> *LMAdvertisingClassTokens(void) {
    static NSArray<NSString *> *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokens = @[
            @"GAD", @"LAD", @"LineAdvertise", @"Advertise",
            @"AdView", @"AdCell", @"BannerAd", @"GoogleAd",
            @"SquareAd", @"SmartChAd", @"HomeTabAd", @"WalletAd",
            @"ChatAd", @"NewsAd", @"RCAd", @"AdHeader", @"AdSkeleton",
        ];
    });
    return tokens;
}

static BOOL LMIsAdvertisingView(UIView *view) {
    static NSMapTable *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSMapTable strongToStrongObjectsMapTable];
    });
    Class viewClass = view.class;
    NSNumber *cached = [cache objectForKey:viewClass];
    if (cached) return cached.boolValue;
    BOOL result = LMNameContains(NSStringFromClass(viewClass),
                                 LMAdvertisingClassTokens());
    [cache setObject:@(result) forKey:viewClass];
    return result;
}

static void LMHideAdvertisingView(UIView *view) {
    // Keep the hierarchy intact. LINE's ad view models may still deliver
    // callbacks after a request is cancelled.
    view.hidden = YES;
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
    view.isAccessibilityElement = NO;
}

static void LMHideAdvertisingSubviews(UIView *root) {
    for (UIView *view in [root.subviews copy]) {
        if (LMIsAdvertisingView(view)) {
            LMHideAdvertisingView(view);
        } else {
            LMHideAdvertisingSubviews(view);
        }
    }
}

static LMVoidNoArgIMP LMOriginalViewDidMoveToSuperview;

static void LMViewDidMoveToSuperview(id self, SEL selector) {
    if (LMOriginalViewDidMoveToSuperview) {
        LMOriginalViewDidMoveToSuperview(self, selector);
    }
    UIView *view = (UIView *)self;
    if (LMIsAdvertisingView(view)) LMHideAdvertisingView(view);
}

static LMVoidBoolIMP LMOriginalViewDidAppear;

static void LMViewControllerDidAppear(id self, SEL selector, BOOL animated) {
    if (LMOriginalViewDidAppear) LMOriginalViewDidAppear(self, selector, animated);
    UIView *view = [(UIViewController *)self viewIfLoaded];
    if (view) LMHideAdvertisingSubviews(view);
}

static void LMOpenLineSettings(UITabBarController *controller) {
    // Route inside this app. UIApplication.openURL could launch the original LINE.
    if (!controller.viewIfLoaded.window || controller.presentedViewController) return;
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    SEL selector = @selector(application:openURL:options:);
    NSURL *url = [NSURL URLWithString:@"line://nv/settings"];
    if ([delegate respondsToSelector:selector] &&
        [delegate application:UIApplication.sharedApplication openURL:url options:@{}]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NEIN"
        message:@"此版本無法透過內部路由開啟設定，請使用首頁齒輪。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

#include "LINEVisibleTabBar.h"
#ifdef LINE_MULTI_TAB_DIAGNOSTICS
#include "LINETabDiagnostics.h"
#endif

static LMVoidNoArgIMP LMOriginalTabBarLayout;
static LMVoidNoArgIMP LMOriginalSourceTabBarLayout;
static void (*LMOriginalSelectedIndex)(id, SEL, NSUInteger);
static void (*LMOriginalSelectedController)(id, SEL, UIViewController *);
static void (*LMOriginalTabHidden)(id, SEL, BOOL);
static void (*LMOriginalTabAlpha)(id, SEL, CGFloat);
static void (*LMOriginalTabFrame)(id, SEL, CGRect);
static void (*LMOriginalTabCenter)(id, SEL, CGPoint);
static void (*LMOriginalTabBounds)(id, SEL, CGRect);
static void (*LMOriginalTabTransform)(id, SEL, CGAffineTransform);
static LMVoidNoArgIMP LMOriginalNavigationWillLayout;

static void LMSourceTabSetHidden(id self, SEL selector, BOOL hidden) {
    LMOriginalTabHidden(self, selector, hidden);
    LMSyncSourceTabVisibility(self);
}

static void LMSourceTabSetAlpha(id self, SEL selector, CGFloat alpha) {
    LMOriginalTabAlpha(self, selector, LMVisibleSourceAlpha(self, alpha));
    LMSyncSourceTabVisibility(self);
}

static void LMSourceTabSetFrame(id self, SEL selector, CGRect frame) {
    LMOriginalTabFrame(self, selector, frame);
    LMSyncSourceTabVisibility(self);
}

static void LMSourceTabSetCenter(id self, SEL selector, CGPoint center) {
    LMOriginalTabCenter(self, selector, center);
    LMSyncSourceTabVisibility(self);
}

static void LMSourceTabSetBounds(id self, SEL selector, CGRect bounds) {
    LMOriginalTabBounds(self, selector, bounds);
    LMSyncSourceTabVisibility(self);
}

static void LMSourceTabSetTransform(id self, SEL selector, CGAffineTransform transform) {
    LMOriginalTabTransform(self, selector, transform);
    LMSyncSourceTabVisibility(self);
}

static void LMNavigationWillLayout(id self, SEL selector) {
    if (LMOriginalNavigationWillLayout) LMOriginalNavigationWillLayout(self, selector);
    UITabBarController *controller = [(UINavigationController *)self tabBarController];
    LMVisibleTabBar *presentation = objc_getAssociatedObject(controller, &LMVisibleTabBarKey);
    [presentation syncVisibility];
}

static void LMTabBarControllerDidLayoutSubviews(id self, SEL selector) {
    if (LMOriginalTabBarLayout) LMOriginalTabBarLayout(self, selector);
    if (![self isKindOfClass:UITabBarController.class]) return;
    LMUpdateVisibleTabBar(self);
#ifdef LINE_MULTI_TAB_DIAGNOSTICS
    LMInstallTabDiagnosticButton(self);
#endif
}

static void LMSourceTabBarLayout(id self, SEL selector) {
    if (LMOriginalSourceTabBarLayout) LMOriginalSourceTabBarLayout(self, selector);
    for (UIResponder *responder = [(UITabBar *)self nextResponder]; responder;
         responder = responder.nextResponder) {
        if ([responder isKindOfClass:UITabBarController.class] &&
            ((UITabBarController *)responder).tabBar == self) {
            LMUpdateVisibleTabBar((UITabBarController *)responder);
            return;
        }
    }
}

static void LMSetVisibleSelectedIndex(id self, SEL selector, NSUInteger requested) {
    NSUInteger destination = LMGuardVisibleTabSelection(self, requested);
    if (destination == NSNotFound && requested != NSNotFound) return;
    LMOriginalSelectedIndex(self, selector, destination);
}

static void LMSetVisibleSelectedController(id self, SEL selector, UIViewController *requested) {
    UITabBarController *controller = self;
    NSArray<UIViewController *> *controllers = controller.viewControllers;
    NSUInteger index = requested ? [controllers indexOfObjectIdenticalTo:requested] : NSNotFound;
    if (index != NSNotFound) {
        NSUInteger destination = LMGuardVisibleTabSelection(controller, index);
        if (destination == NSNotFound) return;
        if (destination < controllers.count) requested = controllers[destination];
    }
    LMOriginalSelectedController(self, selector, requested);
}

static void LMInstallAdvertisingLoaderHooks(void) {
#ifndef LINE_MULTI_REMOVE_ADS
    Class gadLoader = NSClassFromString(@"GADAdLoader");
    if (gadLoader) {
        LMHook(gadLoader, @selector(loadRequest:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
        LMHook(gadLoader, @selector(loadRequestWithTarget:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
        LMHook(gadLoader, @selector(loadWithAdResponseString:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
    }

    Class banner = NSClassFromString(@"GADBannerView");
    if (banner) {
        LMHook(banner, @selector(loadRequest:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
        LMHook(banner, @selector(loadWithAdResponseString:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
        LMHook(banner, @selector(loadWithTargeting:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
    }
#endif

    Class interstitial = NSClassFromString(@"GADInterstitialAd");
    if (interstitial) {
        LMHook(interstitial, @selector(presentFromRootViewController:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
        LMHookClassMethod(interstitial,
               @selector(loadWithAdUnitID:request:completionHandler:), "v", 5, "@", "@",
               (IMP)LMFailAdLoad, NULL);
    }
    Class rewarded = NSClassFromString(@"GADRewardedAd");
    if (rewarded) {
        LMHook(rewarded, @selector(presentFromRootViewController:userDidEarnRewardHandler:),
               "v", 4, "@", "@?", (IMP)LMNoopObjectObject, NULL);
        LMHookClassMethod(rewarded,
               @selector(loadWithAdUnitID:request:completionHandler:), "v", 5, "@", "@",
               (IMP)LMFailAdLoad, NULL);
    }
    Class appOpen = NSClassFromString(@"GADAppOpenAd");
    if (appOpen) {
        LMHook(appOpen, @selector(presentFromRootViewController:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
        LMHookClassMethod(appOpen,
               @selector(loadWithAdUnitID:request:completionHandler:), "v", 5, "@", "@",
               (IMP)LMFailAdLoad, NULL);
    }
    Class rewardedInterstitial = NSClassFromString(@"GADRewardedInterstitialAd");
    if (rewardedInterstitial) {
        LMHookClassMethod(rewardedInterstitial,
               @selector(loadWithAdUnitID:request:completionHandler:), "v", 5, "@", "@",
               (IMP)LMFailAdLoad, NULL);
    }
    Class gamInterstitial = NSClassFromString(@"GAMInterstitialAd");
    if (gamInterstitial) {
        LMHookClassMethod(gamInterstitial,
               @selector(loadWithAdManagerAdUnitID:request:completionHandler:), "v", 5,
               "@", "@", (IMP)LMFailAdLoad, NULL);
    }

#ifndef LINE_MULTI_REMOVE_ADS
    Class imaLoader = NSClassFromString(@"IMAAdsLoader");
    if (imaLoader) {
        LMHook(imaLoader, @selector(requestAdsWithRequest:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
    }
#endif
    Class imaManager = NSClassFromString(@"IMAAdsManager");
    if (imaManager) {
        LMHook(imaManager, @selector(start), "v", 2, NULL, NULL,
               (IMP)LMNoopNoArg, NULL);
    }
}

static void LMInstallAdvertisingCleanupHook(void) {
    Class view = UIView.class;
    LMHook(view, @selector(didMoveToSuperview), "v", 2, NULL, NULL,
           (IMP)LMViewDidMoveToSuperview,
           (IMP *)&LMOriginalViewDidMoveToSuperview);
    Class controller = UIViewController.class;
    LMHook(controller, @selector(viewDidAppear:), "v", 3, "B", NULL,
           (IMP)LMViewControllerDidAppear, (IMP *)&LMOriginalViewDidAppear);
}

static void LMInstallPromotionalTabHooks(void) {
    LMHookClassMethodOnly(UITabBar.class, @selector(setAlpha:), "v", 3, @encode(CGFloat), NULL,
                          (IMP)LMSourceTabSetAlpha, (IMP *)&LMOriginalTabAlpha);
    LMHookClassMethodOnly(UITabBar.class, @selector(setHidden:), "v", 3, @encode(BOOL), NULL,
                          (IMP)LMSourceTabSetHidden, (IMP *)&LMOriginalTabHidden);
    LMHookClassMethodOnly(UITabBar.class, @selector(setFrame:), "v", 3, @encode(CGRect), NULL,
                          (IMP)LMSourceTabSetFrame, (IMP *)&LMOriginalTabFrame);
    LMHookClassMethodOnly(UITabBar.class, @selector(setCenter:), "v", 3, @encode(CGPoint), NULL,
                          (IMP)LMSourceTabSetCenter, (IMP *)&LMOriginalTabCenter);
    LMHookClassMethodOnly(UITabBar.class, @selector(setBounds:), "v", 3, @encode(CGRect), NULL,
                          (IMP)LMSourceTabSetBounds, (IMP *)&LMOriginalTabBounds);
    LMHookClassMethodOnly(UITabBar.class, @selector(setTransform:), "v", 3, @encode(CGAffineTransform), NULL,
                          (IMP)LMSourceTabSetTransform, (IMP *)&LMOriginalTabTransform);
    LMHookClassMethodOnly(UINavigationController.class, @selector(viewWillLayoutSubviews),
                          "v", 2, NULL, NULL, (IMP)LMNavigationWillLayout,
                          (IMP *)&LMOriginalNavigationWillLayout);
    Class controller = UITabBarController.class;
    LMHookClassMethodOnly(controller, @selector(setSelectedIndex:),
                          "v", 3, @encode(NSUInteger), NULL,
                          (IMP)LMSetVisibleSelectedIndex, (IMP *)&LMOriginalSelectedIndex);
    LMHookClassMethodOnly(controller, @selector(setSelectedViewController:),
                          "v", 3, "@", NULL,
                          (IMP)LMSetVisibleSelectedController, (IMP *)&LMOriginalSelectedController);
    LMHookClassMethodOnly(controller, @selector(viewDidLayoutSubviews),
                          "v", 2, NULL, NULL, (IMP)LMTabBarControllerDidLayoutSubviews,
                          (IMP *)&LMOriginalTabBarLayout);
    LMHookClassMethodOnly(UITabBar.class, @selector(layoutSubviews),
                          "v", 2, NULL, NULL, (IMP)LMSourceTabBarLayout,
                          (IMP *)&LMOriginalSourceTabBarLayout);
}

void LMInstallAdRemovalCompat(BOOL removeAds, BOOL hidePromotionalTabs) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (removeAds) {
            LMInstallAdvertisingLoaderHooks();
            LMInstallAdvertisingCleanupHook();
        }
        if (hidePromotionalTabs) LMInstallPromotionalTabHooks();
    });
}
