// Keep model indices intact. Only the separate presentation bar is filtered.
static BOOL LMVisibleTabIsPromotional(UITabBarItem *item) {
    NSString *title = [[item.title stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    return [@[@"VOOM", @"LINE VOOM", @"NEWS", @"LINE NEWS",
              @"SHOPPING", @"LINE SHOPPING"] containsObject:title ?: @""] ||
           [NSStringFromClass(item.class) hasSuffix:@"VOOMSkinnedTabBarItem"];
}

static NSArray<NSNumber *> *LMVisibleTabIndices(NSArray<UITabBarItem *> *items) {
    NSMutableArray *indices = [NSMutableArray new];
    for (NSUInteger i = 0; i < items.count; i++) {
        if (!LMVisibleTabIsPromotional(items[i])) [indices addObject:@(i)];
    }
    return indices;
}

static NSUInteger LMVisibleTabDestination(NSArray<UITabBarItem *> *items,
                                          NSUInteger current, NSUInteger requested) {
    if (requested >= items.count) return NSNotFound;
    if (!LMVisibleTabIsPromotional(items[requested]) && items[requested].enabled) return requested;
    NSInteger direction = current < items.count && requested < current ? -1 : 1;
    for (NSInteger i = (NSInteger)requested + direction;
         i >= 0 && (NSUInteger)i < items.count; i += direction) {
        if (!LMVisibleTabIsPromotional(items[i]) && items[i].enabled) return (NSUInteger)i;
    }
    if (current < items.count && !LMVisibleTabIsPromotional(items[current]) &&
        items[current].enabled) return current;
    for (NSUInteger i = 0; i < items.count; i++) {
        if (!LMVisibleTabIsPromotional(items[i]) && items[i].enabled) return i;
    }
    return NSNotFound;
}
