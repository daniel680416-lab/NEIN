// Block only the audited ad host suffixes generated into LINEAdDomains.h.
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

#include "LINEAdDomains.h"
#include "LINEAdDomainMatcher.h"

typedef NSURLSessionConfiguration *(*LMConfigurationClassIMP)(id, SEL);
typedef void (*LMSetProtocolClassesIMP)(id, SEL, NSArray<Class> *);
typedef WKNavigation *(*LMWKLoadRequestIMP)(id, SEL, NSURLRequest *);

@interface LMAdBlockingURLProtocol : NSURLProtocol
@end

static BOOL LMIsBlockedAdURL(NSURL *URL) {
    return URL && LMAdHostIsBlocked(URL.host, LMAdBlockedDomains,
                                    LMAdBlockedDomainCount);
}

static NSError *LMBlockedAdRequestError(NSURL *URL) {
    return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost
        userInfo:@{
            NSURLErrorFailingURLErrorKey: URL ?: [NSNull null],
            NSLocalizedDescriptionKey: @"Advertising host blocked",
        }];
}

@implementation LMAdBlockingURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return LMIsBlockedAdURL(request.URL);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    [self.client URLProtocol:self didFailWithError:LMBlockedAdRequestError(self.request.URL)];
}

- (void)stopLoading {
}

@end

static void LMInstallAdProtocol(NSURLSessionConfiguration *configuration) {
    if (!configuration) return;
    NSMutableArray<Class> *classes = [configuration.protocolClasses mutableCopy] ?: [NSMutableArray new];
    if (![classes containsObject:LMAdBlockingURLProtocol.class]) {
        [classes insertObject:LMAdBlockingURLProtocol.class atIndex:0];
        configuration.protocolClasses = classes;
    }
}

static LMConfigurationClassIMP LMOriginalDefaultConfiguration;
static LMConfigurationClassIMP LMOriginalEphemeralConfiguration;
static LMSetProtocolClassesIMP LMOriginalSetProtocolClasses;

static NSURLSessionConfiguration *LMDefaultConfiguration(id self, SEL selector) {
    NSURLSessionConfiguration *configuration = LMOriginalDefaultConfiguration(self, selector);
    LMInstallAdProtocol(configuration);
    return configuration;
}

static NSURLSessionConfiguration *LMEphemeralConfiguration(id self, SEL selector) {
    NSURLSessionConfiguration *configuration = LMOriginalEphemeralConfiguration(self, selector);
    LMInstallAdProtocol(configuration);
    return configuration;
}

static void LMSetProtocolClasses(id self, SEL selector, NSArray<Class> *classes) {
    NSMutableArray<Class> *updated = [classes mutableCopy] ?: [NSMutableArray new];
    if (![updated containsObject:LMAdBlockingURLProtocol.class]) {
        [updated insertObject:LMAdBlockingURLProtocol.class atIndex:0];
    }
    LMOriginalSetProtocolClasses(self, selector, updated);
}

static BOOL LMHookConfigurationClassMethod(SEL selector, IMP replacement, IMP *original) {
    Method method = class_getClassMethod(NSURLSessionConfiguration.class, selector);
    if (!LMMethodHasType(method, "@", 2, NULL, NULL)) return NO;
    if (original) *original = method_getImplementation(method);
    method_setImplementation(method, replacement);
    return YES;
}

static LMWKLoadRequestIMP LMOriginalWKLoadRequest;

static WKNavigation *LMWKLoadRequest(id self, SEL selector, NSURLRequest *request) {
    if (LMIsBlockedAdURL(request.URL)) {
        WKWebView *webView = (WKWebView *)self;
        return [webView loadHTMLString:@"" baseURL:nil];
    }
    return LMOriginalWKLoadRequest(self, selector, request);
}

static void LMInstallAdNetworkBlock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSURLProtocol registerClass:LMAdBlockingURLProtocol.class];
        LMHookConfigurationClassMethod(@selector(defaultSessionConfiguration),
                                       (IMP)LMDefaultConfiguration,
                                       (IMP *)&LMOriginalDefaultConfiguration);
        LMHookConfigurationClassMethod(@selector(ephemeralSessionConfiguration),
                                       (IMP)LMEphemeralConfiguration,
                                       (IMP *)&LMOriginalEphemeralConfiguration);
        LMHook(NSURLSessionConfiguration.class, @selector(setProtocolClasses:), "v", 3,
               "@", NULL, (IMP)LMSetProtocolClasses, (IMP *)&LMOriginalSetProtocolClasses);
        LMHook(WKWebView.class, @selector(loadRequest:), "@", 3, "@", NULL,
               (IMP)LMWKLoadRequest, (IMP *)&LMOriginalWKLoadRequest);
    });
}
