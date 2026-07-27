#import <UIKit/UIKit.h>
#import <stdint.h>

static NSString * const ZSBaselineKey = @"ZS_DIAG_DEFAULTS_HASHES_20260727_V1";
static BOOL ZSScheduled = NO;

static BOOL ZSIsSensitiveKey(NSString *key) {
    NSString *s = key.lowercaseString;
    for (NSString *word in @[@"token", @"password", @"passwd", @"secret", @"cookie",
                             @"auth", @"session", @"credential", @"phone", @"email",
                             @"idfa", @"idfv", @"openid", @"unionid", @"deviceid"]) {
        if ([s containsString:word]) return YES;
    }
    return NO;
}

static NSString *ZSStableHash(id value) {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (!data) data = [[value description] dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    uint64_t hash = 14695981039346656037ULL;
    for (NSUInteger i = 0; i < data.length; i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", hash];
}

static NSDictionary<NSString *, NSString *> *ZSSnapshot(void) {
    NSDictionary *all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    [all enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([key hasPrefix:@"ZS_DIAG_"] || ZSIsSensitiveKey(key)) return;
        snapshot[key] = ZSStableHash(value);
    }];
    return snapshot;
}

static NSString *ZSValueSummary(id value) {
    if (!value) return @"<不存在>";
    if ([value isKindOfClass:NSData.class])
        return [NSString stringWithFormat:@"<数据 %lu 字节>", (unsigned long)[value length]];
    if ([value isKindOfClass:NSArray.class])
        return [NSString stringWithFormat:@"<数组 %lu 项>", (unsigned long)[value count]];
    if ([value isKindOfClass:NSDictionary.class])
        return [NSString stringWithFormat:@"<字典 %lu 项>", (unsigned long)[value count]];
    NSString *text = [[value description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"…"] : text;
}

static NSString *ZSDiff(NSDictionary<NSString *, NSString *> *before,
                        NSDictionary<NSString *, NSString *> *after) {
    NSMutableSet *keys = [NSMutableSet setWithArray:before.allKeys];
    [keys addObjectsFromArray:after.allKeys];
    NSArray *sorted = [keys.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSDictionary *current = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
    NSMutableArray<NSString *> *changes = [NSMutableArray array];
    for (NSString *key in sorted) {
        NSString *oldHash = before[key], *newHash = after[key];
        if ((oldHash == newHash) || [oldHash isEqualToString:newHash]) continue;
        NSString *oldText = oldHash ? @"<值已变化>" : @"<不存在>";
        NSString *newText = newHash ? ZSValueSummary(current[key]) : @"<已删除>";
        [changes addObject:[NSString stringWithFormat:@"%@\n  %@ → %@", key, oldText, newText]];
    }
    if (!changes.count) return @"未发现 NSUserDefaults 变化。";
    return [NSString stringWithFormat:@"共发现 %lu 项变化：\n\n%@",
            (unsigned long)changes.count, [changes componentsJoinedByString:@"\n\n"]];
}

static UIViewController *ZSTopViewController(void) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) { window = candidate; break; }
            }
            if (window) break;
        }
    }
    if (!window) {
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
    }
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = window.rootViewController;
    while (top) {
        if (top.presentedViewController) top = top.presentedViewController;
        else if ([top isKindOfClass:UINavigationController.class])
            top = ((UINavigationController *)top).visibleViewController;
        else if ([top isKindOfClass:UITabBarController.class])
            top = ((UITabBarController *)top).selectedViewController;
        else break;
    }
    return top;
}

static void ZSShowAlert(NSString *title, NSString *message, NSString *copyText) {
    UIViewController *top = ZSTopViewController();
    if (!top || !top.view.window) return;
    NSString *preview = message.length > 3500
        ? [[message substringToIndex:3500] stringByAppendingString:@"\n\n……完整内容请点击复制"]
        : message;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:preview
                                                             preferredStyle:UIAlertControllerStyleAlert];
    if (copyText) {
        [alert addAction:[UIAlertAction actionWithTitle:@"复制完整结果"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = copyText;
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void ZSRunDiagnostic(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *before = [defaults dictionaryForKey:ZSBaselineKey];
    NSDictionary *after = ZSSnapshot();
    if (!before) {
        [defaults setObject:after forKey:ZSBaselineKey];
        [defaults synchronize];
        ZSShowAlert(@"新版诊断：基准已保存",
                    @"现在输入变身口令，杀掉 App 后台，再重新打开并等待约 7 秒。不要卸载或覆盖安装。",
                    nil);
        return;
    }
    NSString *result = ZSDiff(before, after);
    ZSShowAlert(@"新版变身状态诊断结果", result, result);
}

static void ZSApplicationDidBecomeActive(__unused NSNotification *note) {
    if (ZSScheduled) return;
    ZSScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZSRunDiagnostic(); });
}

__attribute__((constructor))
static void ZSTransformDiagnosticInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            ZSApplicationDidBecomeActive(note);
        }];
    });
}
