#include <math.h>

// Translation keeps UIKit's original centers/sizes and control identity intact.
// Only the floating hierarchy observed on the test device is supported.
static char LMCompactMovedKey;
static char LMCompactDeltaKey;
static char LMCompactHiddenLensKey;
static char LMCompactLensHiddenStateKey;
static char LMCompactLensTargetKey;

@interface LMCompactLensTarget : NSObject
@property(nonatomic, weak) UITabBar *bar;
@property(nonatomic, weak) UIControl *button;
@property(nonatomic, weak) UITabBarItem *item;
@property(nonatomic) BOOL updating;
@end
@implementation LMCompactLensTarget @end

static BOOL LMCompactClass(UIView *view, NSString *name) {
    return [NSStringFromClass(view.class) isEqualToString:name];
}

static BOOL LMCompactNear(CGFloat a, CGFloat b) {
    return isfinite(a) && isfinite(b) && fabs(a - b) <= 0.5;
}

static BOOL LMCompactRectNear(CGRect a, CGRect b) {
    return LMCompactNear(a.origin.x, b.origin.x) &&
           LMCompactNear(a.origin.y, b.origin.y) &&
           LMCompactNear(a.size.width, b.size.width) &&
           LMCompactNear(a.size.height, b.size.height);
}

static void LMCompactAlignLens(UIView *lens, UITabBarItem *selection) {
    LMCompactLensTarget *target = objc_getAssociatedObject(lens, &LMCompactLensTargetKey);
    UIControl *button = target.button;
    NSNumber *previous = objc_getAssociatedObject(lens, &LMCompactDeltaKey);
    if (!target || target.updating || !target.bar || !button ||
        !selection || selection != target.item || !selection.enabled ||
        ![target.bar.items containsObject:selection] || lens.hidden || button.hidden ||
        button.transform.a != 1 || button.transform.b != 0 ||
        button.transform.c != 0 || button.transform.d != 1 ||
        !previous || !CGAffineTransformEqualToTransform(lens.transform,
            CGAffineTransformMakeTranslation(previous.doubleValue, 0)) ||
        !LMCompactNear(lens.bounds.size.width, button.bounds.size.width) ||
        !LMCompactNear(lens.bounds.size.height, button.bounds.size.height)) return;
    CGFloat dx = button.center.x + button.transform.tx - lens.center.x;
    if (!isfinite(dx)) return;
    CGAffineTransform translation = CGAffineTransformMakeTranslation(dx, 0);
    if (CGAffineTransformEqualToTransform(lens.transform, translation)) return;
    target.updating = YES;
    lens.transform = translation;
    objc_setAssociatedObject(lens, &LMCompactDeltaKey, @(dx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    target.updating = NO;
}

static void LMCompactRestore(UIView *bar) {
    UIView *lens = objc_getAssociatedObject(bar, &LMCompactHiddenLensKey);
    if (lens) {
        NSNumber *hidden = objc_getAssociatedObject(lens, &LMCompactLensHiddenStateKey);
        if (hidden) lens.hidden = hidden.boolValue;
        objc_setAssociatedObject(lens, &LMCompactLensHiddenStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &LMCompactHiddenLensKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *view in objc_getAssociatedObject(bar, &LMCompactMovedKey)) {
        objc_setAssociatedObject(view, &LMCompactLensTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSNumber *delta = objc_getAssociatedObject(view, &LMCompactDeltaKey);
        if (delta && CGAffineTransformEqualToTransform(view.transform,
                CGAffineTransformMakeTranslation(delta.doubleValue, 0))) {
            view.transform = CGAffineTransformIdentity;
        }
        objc_setAssociatedObject(view, &LMCompactDeltaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(bar, &LMCompactMovedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSArray<UIControl *> *LMCompactButtons(UIView *row) {
    if (row.subviews.count < 2 || row.subviews.count > 6) return nil;
    for (UIView *view in row.subviews) {
        if (!LMCompactClass(view, @"_UITabButton") ||
            ![view isKindOfClass:UIControl.class] ||
            !CGAffineTransformIsIdentity(view.transform)) return nil;
    }
    return [row.subviews sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.center.x < b.center.x ? NSOrderedAscending :
               a.center.x > b.center.x ? NSOrderedDescending : NSOrderedSame;
    }];
}

static void LMCompactTabsForSelection(UITabBar *bar, UITabBarItem *selection) {
    LMCompactRestore(bar);
    // The captured hierarchy is LTR; do not infer item order for other layouts.
    if (bar.effectiveUserInterfaceLayoutDirection != UIUserInterfaceLayoutDirectionLeftToRight) return;
    NSArray<UITabBarItem *> *items = bar.items;
    NSUInteger selectedIndex = selection
        ? [items indexOfObjectIdenticalTo:selection] : NSNotFound;
    if (selectedIndex == NSNotFound || selectedIndex >= items.count) return;
    UIView *platter = nil;
    for (UIView *view in bar.subviews) {
        if (LMCompactClass(view, @"UIKit._UITabBarItemPlatterView")) {
            if (platter) return;
            platter = view;
        } else if (!LMCompactClass(view, @"_UIPortalView") ||
                   view.frame.size.width != 0 || view.frame.size.height != 0 ||
                   view.bounds.size.width != 0 || view.bounds.size.height != 0) {
            return;
        }
    }
    if (!platter || platter.subviews.count != 5) return;
    UIView *normal = nil, *selected = nil, *lens = nil, *badges = nil;
    for (UIView *view in platter.subviews) {
        NSString *name = NSStringFromClass(view.class);
        if ([name isEqualToString:@"_TtCC5UIKit20_UITabBarPlatterViewP33_022AA364308030F4627162921FD6D31A11ContentView"]) normal = view;
        else if ([name isEqualToString:@"_TtCC5UIKit32_UITabBarVisualProvider_FloatingP33_3C6E5A7AE2316B749C88F887559DAAB619SelectedContentView"]) selected = view;
        else if ([name isEqualToString:@"_UILiquidLensView"]) lens = view;
        else if ([name isEqualToString:@"_TtCC5UIKit20_UITabBarPlatterViewP33_022AA364308030F4627162921FD6D31A18BadgeContainerView"]) badges = view;
        else if (![name isEqualToString:@"_TtCE5UIKitCSo17_UILiquidLensViewP33_4C400BD973F5E4E0B779D1A21A7AEB2711DestOutView"]) return;
    }
    if (!normal || !selected || !lens || !badges ||
        !CGAffineTransformIsIdentity(lens.transform) ||
        !LMCompactRectNear(normal.frame, selected.frame) ||
        !LMCompactRectNear(normal.frame, badges.frame) ||
        !LMCompactNear(normal.frame.origin.x, 0) || !LMCompactNear(normal.frame.origin.y, 0) ||
        !LMCompactNear(normal.bounds.origin.x, 0) || !LMCompactNear(normal.bounds.origin.y, 0)) return;
    NSArray<UIControl *> *buttons = LMCompactButtons(normal);
    NSArray<UIControl *> *copies = LMCompactButtons(selected);
    if (!buttons || buttons.count != copies.count || buttons.count != items.count) return;
    NSMutableArray<UIView *> *targets = [NSMutableArray new];
    NSMutableArray<NSNumber *> *deltas = [NSMutableArray new];
    NSMutableArray<NSNumber *> *visible = [NSMutableArray new];
    CGFloat previous = -INFINITY;
    CGFloat spacing = INFINITY;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIControl *button = buttons[i], *copy = copies[i];
        if (!LMCompactRectNear(button.frame, copy.frame) ||
            button.hidden != copy.hidden || button.enabled != copy.enabled ||
            button.enabled != items[i].enabled ||
            !isfinite(button.center.x) || button.center.x <= previous ||
            button.bounds.size.width <= 0) return;
        spacing = fmin(spacing, button.center.x - previous);
        previous = button.center.x;
        if (button.hidden) {
            if (button.enabled ||
                !objc_getAssociatedObject(button, &LMTabOriginalHiddenKey) ||
                !objc_getAssociatedObject(copy, &LMTabOriginalHiddenKey)) return;
        } else {
            [visible addObject:@(i)];
        }
    }
    if (visible.count < 2 || visible.count == buttons.count) return;
    CGFloat left = buttons.firstObject.center.x;
    CGFloat right = buttons.lastObject.center.x;
    CGFloat step = (right - left) / (visible.count - 1);
    if (!isfinite(step) || step <= 0 || left < 0 || right > normal.bounds.size.width) return;
    NSUInteger selectedRank = [visible indexOfObject:@(selectedIndex)];
    UIControl *selectedButton = buttons[selectedIndex];
    if (!isfinite(lens.center.x) ||
        !LMCompactNear(lens.frame.origin.y, selectedButton.frame.origin.y) ||
        !LMCompactNear(lens.bounds.size.width, selectedButton.bounds.size.width) ||
        !LMCompactNear(lens.bounds.size.height, selectedButton.bounds.size.height)) return;
    for (NSUInteger rank = 0; rank < visible.count; rank++) {
        NSUInteger i = visible[rank].unsignedIntegerValue;
        UIControl *button = buttons[i];
        if (button.bounds.size.width > step) return;
        CGFloat dx = left + rank * step - button.center.x;
        [targets addObject:button]; [deltas addObject:@(dx)];
        [targets addObject:copies[i]];
        [deltas addObject:@(left + rank * step - copies[i].center.x)];
    }
    // UIKit can leave the lens over a hidden slot. Use actual item selection,
    // not that stale position, without changing UIKit's selection or arrays.
    if (selectedRank != NSNotFound) {
        [targets addObject:lens];
        [deltas addObject:@(left + selectedRank * step - lens.center.x)];
    }
    for (UIView *badge in badges.subviews) {
        if (!LMCompactClass(badge, @"_UIBarBadgeView") ||
            !CGAffineTransformIsIdentity(badge.transform)) return;
        NSInteger nearest = -1;
        CGFloat distance = INFINITY;
        for (NSUInteger i = 0; i < buttons.count; i++) {
            CGFloat d = fabs(badge.center.x - buttons[i].center.x);
            if (d < distance) { distance = d; nearest = (NSInteger)i; }
        }
        if (nearest < 0 || distance >= spacing / 2) return;
        NSUInteger rank = [visible indexOfObject:@(nearest)];
        if (rank == NSNotFound) return;
        [targets addObject:badge]; [deltas addObject:deltas[rank * 2]];
    }
    if (selectedRank == NSNotFound) {
        // Keep the actual page selected, but do not highlight a hidden tab.
        objc_setAssociatedObject(lens, &LMCompactLensHiddenStateKey, @(lens.hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &LMCompactHiddenLensKey, lens,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lens.hidden = YES;
    }
    for (NSUInteger i = 0; i < targets.count; i++) {
        targets[i].transform = CGAffineTransformMakeTranslation(deltas[i].doubleValue, 0);
        objc_setAssociatedObject(targets[i], &LMCompactDeltaKey, deltas[i],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(bar, &LMCompactMovedKey, targets, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (selectedRank != NSNotFound) {
        LMCompactLensTarget *target = [LMCompactLensTarget new];
        target.bar = bar;
        target.button = selectedButton;
        target.item = selection;
        objc_setAssociatedObject(lens, &LMCompactLensTargetKey, target,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static inline void LMCompactTabs(UITabBar *bar) {
    LMCompactTabsForSelection(bar, bar.selectedItem);
}
