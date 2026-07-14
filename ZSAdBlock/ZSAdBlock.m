// ZSAdBlock.dylib —— 「妆时手账」(com.dtz.zhuangshi) 去广告注入库
// 方案：非越狱 dylib 注入 + 重签名重打包
// 技术：纯 Objective-C runtime method swizzling（不依赖 Substrate/越狱）
//
// 核心原则（来自实战经验）：
//   【放行加载，只拦展示】—— 绝不 hook 广告的 load/request 方法。
//   App 的开屏页要等广告 SDK 的“加载完成/失败”回调才消失；掐断加载会导致
//   “无广告也卡开屏”。我们只拦截 show/present/display 类展示方法，并对开屏用
//   UIWindow / UIView 两层兜底，保证广告不出现、App 正常继续。
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
#import <mach/mach_time.h>

#pragma mark - 开关 & 启动计时

static BOOL       gBlock    = YES;   // 总开关
static uint64_t   gStartAbs = 0;
static double     gTimebase = 0.0;   // mach ticks -> 纳秒 的换算系数

// 是否处于“启动期”（开屏兜底只在这段时间内生效，避免误伤后续正常界面）
static BOOL ZSInLaunchWindow(double seconds) {
    if (gStartAbs == 0) return NO;
    uint64_t now = mach_absolute_time();
    double elapsedNs = (double)(now - gStartAbs) * gTimebase;
    return (elapsedNs / 1e9) < seconds;
}

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

// 把某类某方法替换成“什么都不做”（no-op）。适用于展示类 void 方法。
static void ZSNukeMethod(Class cls, SEL sel) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;   // 该类没有此方法，跳过（不会崩）
    IMP noop = imp_implementationWithBlock(^(__unused id _self){ /* 拦截：不展示 */ });
    // 若方法来自父类，先在广告子类上添加覆盖，避免误改 UIViewController 等全局实现。
    if (!class_addMethod(cls, sel, noop, method_getTypeEncoding(m))) {
        method_setImplementation(m, noop);
    }
    ZSLog(@"nuked %@ -[%@ %@]", @"", NSStringFromClass(cls), NSStringFromSelector(sel));
}

// 经典交换：保留原实现指针，替换为自定义 C 函数
static void ZSSwizzle(Class cls, SEL sel, IMP newImp, IMP *origStore) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (origStore) *origStore = method_getImplementation(m);
    // UIWindow 的部分方法可能继承自 UIView；添加子类覆盖可避免污染所有 UIView。
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))) {
        method_setImplementation(m, newImp);
    }
}

#pragma mark - 广告展示方法拦截表

// 所有“展示 / 呈现”类 selector —— 拦截这些即可让广告不出现。
// ⚠️ 故意不包含任何 load / request / fetch，遵守“放行加载”原则。
static NSArray<NSString *> *ZSDisplaySelectors(void) {
    return @[
        @"show", @"showAd", @"showAdView", @"showSplashAd", @"showSplashView",
        @"presentSplashAd", @"displaySplashAd", @"present", @"presentAd",
        @"showInWindow:", @"showInKeyWindow", @"showInKeyWindow:",
        @"showSplashViewInRootViewController:",
        @"showAdInWindow:withRootController:",
        @"showAdInWindow:",
        @"showSplashViewInRootViewController:withCustomView:",
        @"presentFromRootViewController:",
        @"showFromRootViewController:",
        @"showAdFromRootViewController:",
        @"presentAdFromRootViewController:",
        @"showRewardVideoAdFromRootViewController:",
        @"showFullScreenVideoAdFromRootViewController:",
        @"showInViewController:", @"showInView:", @"showInView:animated:",
        @"presentInViewController:", @"presentViewController:animated:completion:",
    ];
}

// 已知广告类（WindMill / Sigmob / GDT）—— 逐个把上面的展示方法置空。
static NSArray<NSString *> *ZSAdClassNames(void) {
    return @[
        // ---- Sigmob WindMill 聚合层 ----
        @"WindSplashAdManager", @"WindSplashAdView", @"WindPortSplashAd",
        @"WindMillSplashAd", @"WindMillSplashAdManager",
        @"WindNewInterstitialViewController", @"WindInterstitialAd",
        @"WindMillInterstitialAdManager", @"WindNewInterstitialAd",
        @"SigmobFullscreenAdViewController", @"SigmobInterstitialAdViewController",
        @"WindRewardVideoAd", @"WindMillRewardedVideoAdManager", @"RewardVideoAd",
        @"WindMillBannerAdManager", @"WindMillBannerAd",
        @"WindNativeAdView", @"WindMillNativeAdsManager", @"TBNativeAdView",
        // ---- 腾讯优量汇 / 广点通 GDT ----
        @"GDTSplashAd", @"GDTUnifiedInterstitialAd", @"GDTRewardVideoAd",
        @"GDTUnifiedBannerView", @"GDTUnifiedNativeAd", @"GDTUnifiedNativeAdView",
        @"GDTMediationSplashAd",
        // ---- BeiZi 比孜 ----
        @"BeiZiSplash", @"BeiZiSplashAd", @"BeiZiInterstitialAd",
        @"BeiZiRewardedVideoAd", @"BeiZiBannerAd", @"BeiZiNativeAd",
    ];
}

static void ZSNukeAllDisplayMethods(void) {
    NSArray *sels = ZSDisplaySelectors();
    for (NSString *cn in ZSAdClassNames()) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        for (NSString *sn in sels) {
            SEL sel = NSSelectorFromString(sn);
            if (class_getInstanceMethod(cls, sel)) ZSNukeMethod(cls, sel);
        }
    }
}

#pragma mark - 第二层兜底：UIWindow（拦截以独立窗口弹出的开屏广告）

static IMP orig_makeKeyAndVisible = NULL;
static IMP orig_setHidden = NULL;

static BOOL ZSIsAdWindow(UIWindow *w) {
    if (w.windowLevel <= UIWindowLevelNormal) return NO;   // 只管高于普通层的浮层
    NSString *cls = NSStringFromClass([w class]);
    return ([cls containsString:@"Splash"] || [cls containsString:@"Ad"]);
}

static void new_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    if (gBlock && ZSInLaunchWindow(15.0) && ZSIsAdWindow(self)) {
        ZSLog(@"block window makeKeyAndVisible: %@", NSStringFromClass([self class]));
        return; // 不让广告窗口显示/成为 key
    }
    ((void(*)(id, SEL))orig_makeKeyAndVisible)(self, _cmd);
}

static void new_setHidden(UIWindow *self, SEL _cmd, BOOL hidden) {
    if (gBlock && !hidden && ZSInLaunchWindow(15.0) && ZSIsAdWindow(self)) {
        ZSLog(@"force-hide ad window: %@", NSStringFromClass([self class]));
        ((void(*)(id, SEL, BOOL))orig_setHidden)(self, _cmd, YES);
        return;
    }
    ((void(*)(id, SEL, BOOL))orig_setHidden)(self, _cmd, hidden);
}

#pragma mark - 第三层兜底：UIView（移除嵌入式 / 全屏广告视图）

static IMP orig_didMoveToWindow = NULL;

// 精确已知的广告视图类：只要出现就移除（不限启动期，覆盖信息流/Banner）
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

    // 1) 精确命中：已知广告视图，直接移除
    if ([ZSKnownAdViewClasses() containsObject:name]) {
        ZSLog(@"remove known ad view: %@", name);
        [self removeFromSuperview];
        return;
    }
    // 2) 启动期通用兜底：全屏 + 类名像开屏广告
    if (ZSInLaunchWindow(15.0)) {
        CGRect scr = UIScreen.mainScreen.bounds;
        BOOL fullscreen = CGRectGetWidth(self.frame)  >= CGRectGetWidth(scr)  - 2 &&
                          CGRectGetHeight(self.frame) >= CGRectGetHeight(scr) - 2;
        BOOL looksAd = [name containsString:@"Splash"] ||
                       (fullscreen && [name containsString:@"Ad"]);
        if (looksAd) {
            ZSLog(@"remove launch ad view: %@ frame=%@", name, NSStringFromCGRect(self.frame));
            [self removeFromSuperview];
            return;
        }
    }
}

#pragma mark - 启动期广告类名 dump（便于真机复现后精修）

static void ZSDumpAdClasses(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return;
    NSMutableArray *hits = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *n = class_getName(classes[i]);
        if (!n) continue;
        NSString *name = [NSString stringWithUTF8String:n];
        NSString *low = name.lowercaseString;
        if ([low containsString:@"splash"] || [low containsString:@"reward"] ||
            [low containsString:@"interstit"] || [low containsString:@"nativead"] ||
            ([low containsString:@"ad"] && ([low hasPrefix:@"wind"] || [low hasPrefix:@"gdt"] ||
                                            [low hasPrefix:@"sigmob"] || [low hasPrefix:@"beizi"]))) {
            [hits addObject:name];
        }
    }
    free(classes);
    ZSLog(@"[class-dump] %lu ad-like classes: %@", (unsigned long)hits.count,
          [hits componentsJoinedByString:@", "]);
}

#pragma mark - 安装

__attribute__((constructor))
static void ZSAdBlockInit(void) {
    // 计时基准
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    gTimebase = (double)tb.numer / (double)tb.denom;
    gStartAbs = mach_absolute_time();

    ZSLog(@"==== ZSAdBlock loaded (block=%d) ====", gBlock);

    // 展示方法交换尽量早做；类可能尚未加载，故延时再补一轮
    ZSNukeAllDisplayMethods();
    ZSDumpAdClasses();

    // UIWindow / UIView 两层兜底
    ZSSwizzle([UIWindow class], @selector(makeKeyAndVisible),
              (IMP)new_makeKeyAndVisible, &orig_makeKeyAndVisible);
    ZSSwizzle([UIWindow class], @selector(setHidden:),
              (IMP)new_setHidden, &orig_setHidden);
    ZSSwizzle([UIView class], @selector(didMoveToWindow),
              (IMP)new_didMoveToWindow, &orig_didMoveToWindow);

    // 广告 SDK 常常在 App 启动后才 lazy-load 其类，二次补交换
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        ZSNukeAllDisplayMethods();
        ZSDumpAdClasses();
    });
}
