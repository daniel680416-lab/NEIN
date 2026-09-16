#import <Foundation/Foundation.h>
#include <assert.h>

#include "../hooks/LINEAdDomainMatcher.h"

int main(void) {
    @autoreleasepool {
        NSString * const domains[] = {@"doubleclick.net", @"taboola.com"};
        assert(LMAdHostIsBlocked(@"googleads.g.doubleclick.net", domains, 2));
        assert(LMAdHostIsBlocked(@"TRC.TABOOLA.COM", domains, 2));
        assert(!LMAdHostIsBlocked(@"notdoubleclick.net", domains, 2));
        assert(!LMAdHostIsBlocked(@"google.com", domains, 2));
    }
    return 0;
}
