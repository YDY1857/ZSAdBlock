// ZSAdBlock.dylib —— 「妆时手账」(com.dtz.zhuangshi) 去广告注入库
// 方案：非越狱 dylib 注入 + 重签名重打包
// 技术：纯 Objective-C runtime method swizzling（不依赖 Substrate/越狱）
//
// 核心原则：不拦截广告 SDK 的加载和展示方法，只隐藏明确属于广告 SDK 的 UIView。
// 这样 SDK 仍会正常触发展示完成/关闭回调，避免 App 卡在开屏白屏。
//
// 覆盖的广告技术栈（静态分析确认）：
//   聚合层  : Sigmob WindMill (WindMillSDK / WindSDK)
//   广告网络: 腾讯优量汇/广点通 GDTMobSDK、Sigmob 自有、BeiZi 比孜
//   广告形态: 开屏 Splash / 插屏 Interstitial / 激励 RewardVideo / Banner / 信息流 NativeAd
//
// 仅用于自有或已获授权应用的兼容性 / 去广告研究。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 开关

static BOOL gBlock = YES;

#pragma mark - 日志（写沙盒 tmp，便于真机复现后精修拦截规则）

static void ZSLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ZSAdBlock.log"]; });
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    FILE *fp = fopen(path.UTF8String, "a");
    if (fp) { fputs(line.UTF8String, fp); fclose(fp); }
}

#pragma mark - Swizzle 工具

// 经典交换：保留原实现指针，替换为自定义 C 函数
static void ZSSwizzle(Class cls, SEL sel, IMP newImp, IMP *origStore) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (origStore) *origStore = method_getImplementation(m);
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))) {
        method_setImplementation(m, newImp);
    }
}

static BOOL ZSLooksLikeAdClassName(NSString *name) {
    NSString *low = name.lowercaseString;
    return [low containsString:@"windmill"] || [low containsString:@"sigmob"] ||
           [low containsString:@"beizi"] || [low containsString:@"gdt"] ||
           [low containsString:@"adscope"] || [low containsString:@"amps"] ||
           [low hasPrefix:@"agl"] || [low containsString:@".agl"] ||
           [low hasPrefix:@"bzi"] || [low containsString:@".bzi"] ||
           [low hasPrefix:@"smmotion"] || [low hasPrefix:@"windmotion"];
}

static BOOL ZSLooksLikeOverlayComponent(NSString *name) {
    NSString *low = name.lowercaseString;
    return [low containsString:@"splash"] || [low containsString:@"interstit"] ||
           [low containsString:@"shake"] || [low containsString:@"skip"] ||
           [low containsString:@"zoomout"] || [low containsString:@"customwindow"];
}

static void ZSNoop(id self, SEL _cmd) { (void)self; (void)_cmd; }
static BOOL ZSReturnNo(id self, SEL _cmd) { (void)self; (void)_cmd; return NO; }

static void ZSDisableShakeMethods(void) {
    NSArray<NSString *> *voidSelectors = @[
        @"startMotionServices", @"startShake", @"startShakeServices",
        @"startDeviceMotionServe"
    ];
    NSArray<NSString *> *boolSelectors = @[@"canUseMotionManager", @"isCanUseMotionManager"];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return;
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!ZSLooksLikeAdClassName(NSStringFromClass(cls))) continue;
        for (NSString *name in voidSelectors) {
            ZSSwizzle(cls, NSSelectorFromString(name), (IMP)ZSNoop, NULL);
        }
        for (NSString *name in boolSelectors) {
            ZSSwizzle(cls, NSSelectorFromString(name), (IMP)ZSReturnNo, NULL);
        }
    }
    free(classes);
}

static BOOL ZSTryFinishAd(id object) {
    if (!object) return NO;
    if ([object isKindOfClass:[UIControl class]] && [(UIControl *)object allTargets].count > 0) {
        [(UIControl *)object sendActionsForControlEvents:UIControlEventTouchUpInside];
        ZSLog(@"trigger ad control: %@", NSStringFromClass([object class]));
        return YES;
    }
    NSArray<NSString *> *selectors = @[
        @"tapSkipEvent", @"skipAd", @"skip", @"closeAd", @"closeSelf", @"close",
        @"removeSplashAd", @"removeSplashView", @"removeUnifiedSplash",
        @"BeiZi_removeSplashAd", @"BeiZi_removeUnifiedSplash",
        @"beizi_skipViewCloseDidClicked", @"BeiZi_didClickClose", @"clickCloseAd"
    ];
    for (NSString *name in selectors) {
        SEL sel = NSSelectorFromString(name);
        if (![object respondsToSelector:sel]) continue;
        ((void(*)(id, SEL))objc_msgSend)(object, sel);
        ZSLog(@"invoke ad finish: -[%@ %@]", NSStringFromClass([object class]), name);
        return YES;
    }
    return NO;
}

static void ZSFinishAndHideOverlay(UIView *view) {
    for (UIResponder *responder = view; responder; responder = responder.nextResponder) {
        NSString *name = NSStringFromClass([responder class]);
        if ((responder == view || ZSLooksLikeAdClassName(name)) && ZSTryFinishAd(responder)) break;
    }
    ZSLog(@"hide ad component: %@", NSStringFromClass([view class]));
    view.userInteractionEnabled = NO;
    view.hidden = YES;
}

#pragma mark - UIView 广告视图隐藏

static IMP orig_didMoveToWindow = NULL;

// 精确已知的广告视图类（不限启动期，覆盖信息流/Banner）
static NSSet<NSString *> *ZSKnownAdViewClasses(void) {
    static NSSet *s = nil; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"WindSplashAdView", @"WindPortSplashAd", @"WindNativeAdView",
            @"TBNativeAdView", @"WindMillBannerAd",
            @"GDTSplashAdView", @"GDTUnifiedBannerView", @"GDTUnifiedNativeAdView",
            @"GDTMediationSplashWindow",
            @"BeiZiSplashView", @"BeiZiBannerView", @"BeiZiNativeAdView",
        ]];
    });
    return s;
}

static void new_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void(*)(id, SEL))orig_didMoveToWindow)(self, _cmd);
    if (!gBlock || !self.window) return;
    NSString *name = NSStringFromClass([self class]);

    // 广告 SDK 生命周期照常运行；开屏/摇一摇组件触发跳过，只隐藏 SDK 自身视图。
    if ([ZSKnownAdViewClasses() containsObject:name] || ZSLooksLikeAdClassName(name)) {
        if (ZSLooksLikeOverlayComponent(name)) {
            dispatch_async(dispatch_get_main_queue(), ^{ ZSFinishAndHideOverlay(self); });
        } else {
            ZSLog(@"hide ad view: %@", name);
            self.userInteractionEnabled = NO;
            self.hidden = YES;
        }
    }
}

#pragma mark - 变身状态诊断

static NSString * const ZSDiagnosticBaselineKey = @"ZS_DIAG_DEFAULTS_BASELINE_V1";

static NSDictionary *ZSCleanDefaultsSnapshot(void) {
    NSDictionary *all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    [all enumerateKeysAndObjectsUsingBlock:^(id rawKey, id value, BOOL *stop) {
        (void)stop;
        NSString *key = [rawKey isKindOfClass:[NSString class]] ? rawKey : [rawKey description];
        if (![key hasPrefix:@"ZS_DIAG_"] && value) clean[key] = value;
    }];
    return clean;
}

static BOOL ZSIsSensitiveKey(NSString *key) {
    NSString *low = key.lowercaseString;
    for (NSString *word in @[@"token", @"password", @"passwd", @"secret", @"auth",
                             @"cookie", @"session", @"credential", @"deviceid", @"userid"]) {
        if ([low containsString:word]) return YES;
    }
    return NO;
}

static NSString *ZSValueSummary(NSString *key, id value) {
    if (!value) return @"<不存在>";
    if (ZSIsSensitiveKey(key)) return @"<已打码>";
    if ([value isKindOfClass:[NSString class]]) {
        NSString *text = value;
        return text.length > 80 ? [[text substringToIndex:80] stringByAppendingString:@"…"] : text;
    }
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]]) {
        return [value description];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"<数组 %lu 项>", (unsigned long)[value count]];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"<字典 %lu 项>", (unsigned long)[value count]];
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"<数据 %lu 字节>", (unsigned long)[value length]];
    }
    return NSStringFromClass([value class]);
}

static UIViewController *ZSTopViewController(void) {
    UIWindow *window = nil;
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) { window = candidate; break; }
    }
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = window.rootViewController;
    while (top) {
        if (top.presentedViewController) {
            top = top.presentedViewController;
        } else if ([top isKindOfClass:[UINavigationController class]]) {
            top = ((UINavigationController *)top).visibleViewController;
        } else if ([top isKindOfClass:[UITabBarController class]]) {
            top = ((UITabBarController *)top).selectedViewController;
        } else {
            break;
        }
    }
    return top;
}

static void ZSShowDiagnosticAlert(NSString *title, NSString *message, NSString *copyText) {
    UIViewController *top = ZSTopViewController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (copyText.length) {
        [alert addAction:[UIAlertAction actionWithTitle:@"复制结果"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = copyText;
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void ZSRunSwitchDiagnostic(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *current = ZSCleanDefaultsSnapshot();
    NSDictionary *baseline = [defaults dictionaryForKey:ZSDiagnosticBaselineKey];
    if (!baseline) {
        [defaults setObject:current forKey:ZSDiagnosticBaselineKey];
        [defaults synchronize];
        ZSShowDiagnosticAlert(@"诊断基准已保存",
                              @"现在输入变身口令，杀掉 App 后台（不要卸载），然后重新打开。",
                              nil);
        ZSLog(@"diagnostic baseline saved: %lu keys", (unsigned long)current.count);
        return;
    }

    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:baseline.allKeys];
    [keys addObjectsFromArray:current.allKeys];
    NSMutableArray<NSString *> *changes = [NSMutableArray array];
    for (NSString *key in [keys.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        id before = baseline[key];
        id after = current[key];
        if ((before == after) || [before isEqual:after]) continue;
        [changes addObject:[NSString stringWithFormat:@"%@\n  %@ → %@", key,
                            ZSValueSummary(key, before), ZSValueSummary(key, after)]];
    }

    NSString *report = changes.count ? [changes componentsJoinedByString:@"\n"] : @"未发现 NSUserDefaults 变化";
    NSUInteger visibleCount = MIN((NSUInteger)12, changes.count);
    NSString *visible = changes.count ? [[changes subarrayWithRange:NSMakeRange(0, visibleCount)] componentsJoinedByString:@"\n"] : report;
    if (changes.count > visibleCount) {
        visible = [visible stringByAppendingFormat:@"\n……另有 %lu 项，请点“复制结果”", (unsigned long)(changes.count - visibleCount)];
    }
    ZSShowDiagnosticAlert(@"变身状态诊断结果", visible, report);
    ZSLog(@"diagnostic changes (%lu): %@", (unsigned long)changes.count, report);
}

#pragma mark - 安装

__attribute__((constructor))
static void ZSAdBlockInit(void) {
    ZSLog(@"==== ZSAdBlock v7 diagnostic loaded (block=%d) ====", gBlock);
    ZSDisableShakeMethods();
    ZSSwizzle([UIView class], @selector(didMoveToWindow),
              (IMP)new_didMoveToWindow, &orig_didMoveToWindow);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZSRunSwitchDiagnostic(); });
}
