#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>

// View doubles validate lifecycle/delegation, not UIKit rendering or gestures.
@interface UIView : NSObject
@property CGRect frame;
@property BOOL hidden;
@property CGFloat alpha;
@property BOOL userInteractionEnabled;
@property BOOL accessibilityElementsHidden;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic, strong) NSMutableArray *children;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
@end
@implementation UIView
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super init])) {
        _frame = frame; _alpha = 1; _userInteractionEnabled = YES;
        _children = [NSMutableArray new];
    }
    return self;
}
- (void)addSubview:(UIView *)view {
    [view removeFromSuperview];
    [self.children addObject:view]; view.superview = self;
}
- (void)removeFromSuperview {
    [self.superview.children removeObjectIdenticalTo:self]; self.superview = nil;
}
@end

@interface UITabBarItem : NSObject
@property(copy) NSString *title;
@property(strong) id image;
@property(strong) id selectedImage;
@property(copy) NSString *badgeValue;
@property(strong) id badgeColor;
@property BOOL enabled;
- (instancetype)initWithTitle:(NSString *)title image:(id)image selectedImage:(id)selectedImage;
@end
@implementation UITabBarItem
- (instancetype)initWithTitle:(NSString *)title image:(id)image selectedImage:(id)selectedImage {
    if ((self = [super init])) {
        _title = [title copy]; _image = image; _selectedImage = selectedImage; _enabled = YES;
    }
    return self;
}
@end
@class UITabBar;
@protocol UITabBarDelegate <NSObject>
- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item;
@end
enum { UITabBarItemPositioningFill = 1 };
@interface UITabBar : UIView
@property(nonatomic, weak) id<UITabBarDelegate> delegate;
@property NSInteger itemPositioning;
@property(copy) NSArray<UITabBarItem *> *items;
@property(strong) UITabBarItem *selectedItem;
@property(strong) id standardAppearance;
@property(strong) id scrollEdgeAppearance;
@property(strong) id tintColor;
@property(strong) id unselectedItemTintColor;
@property NSInteger semanticContentAttribute;
- (void)setItems:(NSArray *)items animated:(BOOL)animated;
@end
@implementation UITabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    (void)animated; self.items = items;
}
@end
@interface UIViewController : NSObject
@property(strong) UITabBarItem *tabBarItem;
@property BOOL hidesBottomBarWhenPushed;
@end
@implementation UIViewController @end
@interface UINavigationController : UIViewController
@property(copy) NSArray<UIViewController *> *viewControllers;
@end
@implementation UINavigationController @end
@class UITabBarController;
@protocol UITabBarControllerDelegate <NSObject>
@optional
- (BOOL)tabBarController:(UITabBarController *)bar shouldSelectViewController:(UIViewController *)vc;
- (void)tabBarController:(UITabBarController *)bar didSelectViewController:(UIViewController *)vc;
@end
@interface UITabBarController : UIViewController
@property(strong) UITabBar *tabBar;
@property(copy) NSArray<UIViewController *> *viewControllers;
@property(strong) UIViewController *selectedViewController;
@property(nonatomic, weak) id<UITabBarControllerDelegate> delegate;
@end
@implementation UITabBarController @end

#include "../compat/LINEVisibleTabBar.h"

@interface TestDelegate : NSObject <UITabBarControllerDelegate>
@property BOOL deny;
@property NSUInteger notifications;
@end
@implementation TestDelegate
- (BOOL)tabBarController:(UITabBarController *)bar shouldSelectViewController:(UIViewController *)vc {
    (void)bar; (void)vc; return !self.deny;
}
- (void)tabBarController:(UITabBarController *)bar didSelectViewController:(UIViewController *)vc {
    (void)bar; (void)vc; self.notifications++;
}
@end

int main(void) {
    @autoreleasepool {
        UIView *root = [UIView new];
        UITabBarController *controller = [UITabBarController new];
        controller.tabBar = [[UITabBar alloc] initWithFrame:CGRectMake(0, 790, 402, 83)];
        [root addSubview:controller.tabBar];
        NSMutableArray *items = [NSMutableArray new], *controllers = [NSMutableArray new];
        for (NSString *title in @[@"首頁", @"聊天", @"VOOM", @"通話"]) {
            UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:[NSObject new] selectedImage:nil];
            UIViewController *vc = [title isEqualToString:@"聊天"]
                ? [UINavigationController new] : [UIViewController new];
            vc.tabBarItem = item;
            [items addObject:item]; [controllers addObject:vc];
        }
        controller.viewControllers = controllers; controller.tabBar.items = items;
        controller.selectedViewController = controllers[1];
        TestDelegate *delegate = [TestDelegate new]; controller.delegate = delegate;
        LMUpdateVisibleTabBar(controller);
        LMVisibleTabBar *presentation = objc_getAssociatedObject(controller, &LMVisibleTabBarKey);
        assert(presentation.active && presentation.bar.items.count == 3);
        assert(presentation.bar.items[1] != items[1]);
        assert(presentation.bar.selectedItem == presentation.bar.items[1]);
        assert(controller.tabBar.alpha == 0 && !controller.tabBar.userInteractionEnabled);
        assert(controller.tabBar.accessibilityElementsHidden);
        assert(controller.tabBar.items.count == 4 && controller.viewControllers.count == 4);
        assert(((UITabBarItem *)items[2]).enabled);
        assert(LMVisibleSourceAlpha(controller.tabBar, 0) == 0);
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(presentation.bar.hidden);
        assert(LMVisibleSourceAlpha(controller.tabBar, 0.5) == 0);
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(!presentation.bar.hidden && presentation.bar.alpha == 0.5);
        assert(controller.tabBar.alpha == 0);
        assert(LMVisibleSourceAlpha(controller.tabBar, 1) == 0);
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(presentation.bar.alpha == 1);
        presentation.suppressingSourceAppearance = YES;
        assert(LMVisibleSourceAlpha(controller.tabBar, 0) == 0);
        presentation.suppressingSourceAppearance = NO;
        assert(presentation.originalAlpha == 1);
        assert(LMVisibleSourceAlpha(presentation.bar, 0.5) == 0.5);
        UINavigationController *navigation = controllers[1];
        UIViewController *list = [UIViewController new], *chat = [UIViewController new];
        UIViewController *detail = [UIViewController new];
        chat.hidesBottomBarWhenPushed = YES;
        navigation.viewControllers = @[list, chat];
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(presentation.bar.hidden); // No tap or full presentation update.
        navigation.viewControllers = @[list, chat, detail];
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(presentation.bar.hidden);
        navigation.viewControllers = @[list];
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(!presentation.bar.hidden);
        navigation.viewControllers = @[list, chat]; // Cancelled interactive pop.
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(presentation.bar.hidden);
        navigation.viewControllers = @[list, detail];
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(!presentation.bar.hidden); // Do not hide every pushed page.
        controller.tabBar.hidden = YES;
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(presentation.bar.hidden);
        controller.tabBar.hidden = NO;
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(!presentation.bar.hidden);
        CGRect oldFrame = controller.tabBar.frame;
        controller.tabBar.frame = CGRectOffset(oldFrame, 0, 90);
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(CGRectEqualToRect(presentation.bar.frame, controller.tabBar.frame));
        controller.tabBar.frame = oldFrame;
        LMSyncSourceTabVisibility(controller.tabBar);
        navigation.viewControllers = @[list];
        NSArray *copies = presentation.bar.items;
        ((UITabBarItem *)items[1]).badgeValue = @"7";
        LMUpdateVisibleTabBar(controller);
        assert(presentation.bar.items == copies);
        assert([presentation.bar.items[1].badgeValue isEqualToString:@"7"]);
        assert(LMGuardVisibleTabSelection(controller, 2) == 3);
        [presentation tabBar:presentation.bar didSelectItem:presentation.bar.items[2]];
        assert(controller.selectedViewController == controllers[3] && delegate.notifications == 1);
        assert(LMGuardVisibleTabSelection(controller, 2) == 1);
        delegate.deny = YES;
        [presentation tabBar:presentation.bar didSelectItem:presentation.bar.items[0]];
        assert(controller.selectedViewController == controllers[3] && delegate.notifications == 1);
        controller.selectedViewController = controllers[2]; // Simulate bypassing setter hooks.
        LMUpdateVisibleTabBar(controller);
        assert(controller.selectedViewController == controllers[1]);
        controller.tabBar.frame = CGRectMake(0, 400, 700, 83);
        LMUpdateVisibleTabBar(controller);
        assert(CGRectEqualToRect(controller.tabBar.frame, presentation.bar.frame));
        controller.tabBar.hidden = YES;
        LMUpdateVisibleTabBar(controller);
        assert(presentation.bar.hidden);
        controller.tabBar.hidden = NO;
        ((UITabBarItem *)items[2]).title = @"設定";
        LMUpdateVisibleTabBar(controller);
        assert(!presentation.active && !presentation.bar.superview);
        assert(controller.tabBar.alpha == 1 && controller.tabBar.userInteractionEnabled);
        assert(!controller.tabBar.accessibilityElementsHidden);
        assert(LMVisibleSourceAlpha(controller.tabBar, 0.5) == 0.5);
        LMSyncSourceTabVisibility(controller.tabBar);
        assert(!presentation.bar.superview); // No source observer survives deactivation.
        ((UITabBarItem *)items[2]).title = @"VOOM";
        LMUpdateVisibleTabBar(controller);
        assert(presentation.active);
        controller.viewControllers = @[controllers[0]]; // Invalid model restores original UI.
        LMUpdateVisibleTabBar(controller);
        assert(!presentation.active && controller.tabBar.alpha == 1);
        puts("Native tab presentation lifecycle and selection tests passed (view doubles).");
    }
    return 0;
}
