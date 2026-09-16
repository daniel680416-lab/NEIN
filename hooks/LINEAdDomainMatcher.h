#import <Foundation/Foundation.h>

static BOOL LMAdHostMatchesDomain(NSString *host, NSString *domain) {
    if (!host.length || !domain.length) return NO;
    NSString *normalizedHost = host.lowercaseString;
    NSString *normalizedDomain = domain.lowercaseString;
    return [normalizedHost isEqualToString:normalizedDomain] ||
           [normalizedHost hasSuffix:[@"." stringByAppendingString:normalizedDomain]];
}

static BOOL LMAdHostIsBlocked(NSString *host, NSString * const domains[], NSUInteger count) {
    for (NSUInteger index = 0; index < count; index++) {
        if (LMAdHostMatchesDomain(host, domains[index])) return YES;
    }
    return NO;
}
