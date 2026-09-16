#pragma once

static inline BOOL LMIsLINEAppGroup(NSString *identifier) {
    return [identifier isEqualToString:@"group.com.linecorp.line"] ||
           [identifier isEqualToString:@"group.share.com.linecorp.line"];
}
