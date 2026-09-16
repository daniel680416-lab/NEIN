#include "LINEPromotionalTabIdentity.h"

static char LMTabOriginalEnabledKey;

static void LMUpdatePromotionalItems(NSArray<UITabBarItem *> *items) {
    for (UITabBarItem *item in items) {
        BOOL promotional = LMIsPromotionalTabItem(item);
        NSNumber *original = objc_getAssociatedObject(item, &LMTabOriginalEnabledKey);
        if (promotional) {
            if (!original) {
                objc_setAssociatedObject(item, &LMTabOriginalEnabledKey,
                    @(item.enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            item.enabled = NO;
        } else if (original) {
            item.enabled = original.boolValue;
            objc_setAssociatedObject(item, &LMTabOriginalEnabledKey,
                nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static BOOL LMContainsControl(UIView *root) {
    for (UIView *child in root.subviews) {
        if ([child isKindOfClass:UIControl.class] || LMContainsControl(child)) return YES;
    }
    return NO;
}

static BOOL LMHasPromotionalText(UIView *root) {
    if (LMExactPromotionalTitle(root.accessibilityLabel)) return YES;
    if ([root isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)root;
        if (LMExactPromotionalTitle(label.text) ||
            LMExactPromotionalTitle(label.attributedText.string)) return YES;
    }
    if ([root isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)root;
        if (LMExactPromotionalTitle(button.currentTitle) ||
            LMExactPromotionalTitle(button.currentAttributedTitle.string)) return YES;
    }
    for (UIView *child in root.subviews) {
        if (LMHasPromotionalText(child)) return YES;
    }
    return NO;
}

static BOOL LMIsOtherTitle(NSString *text) {
    return [text stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0 &&
           !LMExactPromotionalTitle(text);
}

static BOOL LMHasOtherText(UIView *root) {
    if (LMIsOtherTitle(root.accessibilityLabel)) return YES;
    if ([root isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)root;
        if (LMIsOtherTitle(label.text) ||
            LMIsOtherTitle(label.attributedText.string)) return YES;
    }
    if ([root isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)root;
        if (LMIsOtherTitle(button.currentTitle) ||
            LMIsOtherTitle(button.currentAttributedTitle.string)) return YES;
    }
    for (UIView *child in root.subviews) {
        if (LMHasOtherText(child)) return YES;
    }
    return NO;
}

static char LMTabOriginalHiddenKey;

static void LMUpdatePromotionalButtons(UIView *root) {
    for (UIView *child in root.subviews) {
        // A shared control wrapping multiple buttons is not a single tab.
        if ([child isKindOfClass:UIControl.class] && !LMContainsControl(child)) {
            NSNumber *original = objc_getAssociatedObject(child, &LMTabOriginalHiddenKey);
            if (LMHasPromotionalText(child) && !LMHasOtherText(child)) {
                if (!original) {
                    objc_setAssociatedObject(child, &LMTabOriginalHiddenKey,
                        @(child.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                child.hidden = YES;
            } else if (original) {
                child.hidden = original.boolValue;
                objc_setAssociatedObject(child, &LMTabOriginalHiddenKey,
                    nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else {
            LMUpdatePromotionalButtons(child);
        }
    }
}
