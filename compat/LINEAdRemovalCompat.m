// Disable known advertising loaders and remove their views without touching
// chat content or ordinary LINE network requests.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

typedef void (*LMVoidObjectIMP)(id, SEL, id);
typedef void (*LMVoidObjectObjectIMP)(id, SEL, id, id);
typedef void (*LMVoidNoArgIMP)(id, SEL);
typedef void (*LMVoidBoolIMP)(id, SEL, BOOL);

static BOOL LMMethodHasType(Method method, const char *returnType,
                            unsigned argumentCount, const char *argument2,
                            const char *argument3) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, returnType) != 0) return NO;
    if (argument2) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (strcmp(type, argument2) != 0) return NO;
    }
    if (argument3) {
        method_getArgumentType(method, 3, type, sizeof(type));
        if (strcmp(type, argument3) != 0) return NO;
    }
    return YES;
}

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

static BOOL LMControllerNameMatches(UIViewController *controller) {
    if (!controller) return NO;
    NSArray *tokens = @[
        @"Voom", @"LineVoom", @"NewsRowTab", @"LineNews",
        @"NewsPortal", @"CommerceTab", @"ShoppingTab",
        @"TWCommerce", @"YahooShopping",
    ];
    for (UIViewController *current = controller; current;
         current = current.parentViewController) {
        if (LMNameContains(NSStringFromClass(current.class), tokens)) return YES;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        for (UIViewController *child in ((UINavigationController *)controller).viewControllers) {
            if (LMControllerNameMatches(child)) return YES;
        }
    }
    NSString *title = controller.tabBarItem.title.uppercaseString;
    return [@[@"VOOM", @"LINE NEWS", @"NEWS", @"SHOPPING", @"LINE SHOPPING"]
            containsObject:title];
}

typedef void (*LMVoidArrayBoolIMP)(id, SEL, NSArray *, BOOL);
static LMVoidArrayBoolIMP LMOriginalSetViewControllers;

static void LMSetViewControllers(id self, SEL selector, NSArray *controllers, BOOL animated) {
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:controllers.count];
    for (UIViewController *controller in controllers) {
        if (!LMControllerNameMatches(controller)) [filtered addObject:controller];
    }
    // Never hand UIKit an empty tab list. A server/configuration variation
    // must not turn this compatibility hook into a startup crash.
    if (controllers.count && !filtered.count) {
        filtered = [controllers mutableCopy];
    }
    if (LMOriginalSetViewControllers) {
        LMOriginalSetViewControllers(self, selector, filtered, animated);
    }
}

static void LMInstallAdvertisingLoaderHooks(void) {
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

    Class interstitial = NSClassFromString(@"GADInterstitialAd");
    if (interstitial) {
        LMHook(interstitial, @selector(presentFromRootViewController:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
    }
    Class rewarded = NSClassFromString(@"GADRewardedAd");
    if (rewarded) {
        LMHook(rewarded, @selector(presentFromRootViewController:userDidEarnRewardHandler:),
               "v", 4, "@", "@?", (IMP)LMNoopObjectObject, NULL);
    }
    Class appOpen = NSClassFromString(@"GADAppOpenAd");
    if (appOpen) {
        LMHook(appOpen, @selector(presentFromRootViewController:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
    }

    Class imaLoader = NSClassFromString(@"IMAAdsLoader");
    if (imaLoader) {
        LMHook(imaLoader, @selector(requestAdsWithRequest:), "v", 3, "@", NULL,
               (IMP)LMNoopObject, NULL);
    }
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
    Class controller = UITabBarController.class;
    LMHook(controller, @selector(setViewControllers:animated:), "v", 4, "@", "B",
           (IMP)LMSetViewControllers, (IMP *)&LMOriginalSetViewControllers);
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
