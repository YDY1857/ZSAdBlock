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

static UIView *ZSOverlayRootForView(UIView *view) {
    UIWindow *window = view.window;
    if (!window) return view;
    CGFloat windowArea = window.bounds.size.width * window.bounds.size.height;
    for (UIView *candidate = view; candidate && candidate != window; candidate = candidate.superview) {
        CGRect frame = [candidate convertRect:candidate.bounds toView:window];
        CGFloat area = frame.size.width * frame.size.height;
        NSString *name = NSStringFromClass([candidate class]);
        if (windowArea > 0 && area >= windowArea * 0.6 &&
            ![name.lowercaseString containsString:@"flutter"]) {
            return candidate;
        }
    }
    return view;
}

static void ZSFinishAndHideOverlay(UIView *view) {
    for (UIResponder *responder = view; responder; responder = responder.nextResponder) {
        NSString *name = NSStringFromClass([responder class]);
        if ((responder == view || ZSLooksLikeAdClassName(name)) && ZSTryFinishAd(responder)) break;
    }
    UIView *root = ZSOverlayRootForView(view);
    ZSLog(@"hide ad overlay: %@", NSStringFromClass([root class]));
    root.userInteractionEnabled = NO;
    root.hidden = YES;
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

    // 广告 SDK 生命周期照常运行；开屏/摇一摇组件触发跳过，并连同蒙层一起隐藏。
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

#pragma mark - 安装

__attribute__((constructor))
static void ZSAdBlockInit(void) {
    ZSLog(@"==== ZSAdBlock v5 loaded (block=%d) ====", gBlock);
    ZSDisableShakeMethods();
    ZSSwizzle([UIView class], @selector(didMoveToWindow),
              (IMP)new_didMoveToWindow, &orig_didMoveToWindow);
}
