#include <math.h>

static BOOL LMRecordHomeTap(NSMutableArray<NSNumber *> *times, NSTimeInterval now,
                            BOOL isHome) {
    if (!isHome || !isfinite(now)) { [times removeAllObjects]; return NO; }
    if (times.count && now < times.lastObject.doubleValue) [times removeAllObjects];
    while (times.count && now - times.firstObject.doubleValue > 5.0) {
        [times removeObjectAtIndex:0];
    }
    [times addObject:@(now)];
    if (times.count < 10) return NO;
    [times removeAllObjects];
    return YES;
}

static BOOL LMIsHomeTabTitle(NSString *title) {
    NSString *normalized = [[title stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    return [@[@"HOME", @"首頁", @"主頁", @"主页", @"ホーム", @"홈"] containsObject:normalized ?: @""];
}
