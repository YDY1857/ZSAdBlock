#import <UIKit/UIKit.h>

static NSString *const kIFLPShownKey = @"ZS_TRANSFORM_NOTICE_SHOWN_20260727_V1";
static NSString *const kIFLPTransformKey = @"flutter.7f5df8c5_d527649cacfdb0287553d9c1316d119a";
static NSString *const kIFLPAvatarBase64 = @"";
static NSString *const kIFLPTitle = @"恭喜您成功安装本应用";
static NSString *const kIFLPBrand = @"IOS果物集";
static NSString *const kIFLPWelcome = @"欢迎使用";
static NSString *const kIFLPNotice = @"严禁任何贩卖本插件/软件的盈利行为\n本插件仅供学习研究使用\n请在24小时内自觉删除本插件/软件";
static NSString *const kIFLPAction = @"进入应用";
static const NSInteger kIFLPSeconds = 10;

@class IFLPWelcomeViewController;
static IFLPWelcomeViewController *gIFLPController;
static id gIFLPObserver;

@interface IFLPWelcomeViewController : UIViewController
@property(nonatomic, strong) UIButton *enterButton;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSInteger secondsLeft;
@end

@implementation IFLPWelcomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.view.accessibilityViewIsModal = YES;

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 8;

    UILabel *title = [UILabel new];
    title.text = kIFLPTitle;
    title.font = [UIFont boldSystemFontOfSize:20];
    title.textColor = UIColor.blackColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 0;
    title.accessibilityTraits = UIAccessibilityTraitHeader;

    UILabel *brand = [UILabel new];
    brand.text = kIFLPBrand;
    brand.font = [UIFont boldSystemFontOfSize:18];
    brand.textColor = [UIColor colorWithRed:0.88 green:0.12 blue:0.15 alpha:1];

    NSData *avatarData = [[NSData alloc] initWithBase64EncodedString:kIFLPAvatarBase64 options:0];
    UIImageView *avatar = [[UIImageView alloc] initWithImage:[UIImage imageWithData:avatarData]];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.contentMode = UIViewContentModeScaleAspectFit;
    avatar.layer.cornerRadius = 6;
    avatar.clipsToBounds = YES;
    avatar.isAccessibilityElement = avatar.image != nil;
    avatar.accessibilityLabel = @"品牌头像";
    avatar.hidden = avatar.image == nil;
    [NSLayoutConstraint activateConstraints:@[
        [avatar.widthAnchor constraintEqualToConstant:36],
        [avatar.heightAnchor constraintEqualToConstant:36],
    ]];

    UIStackView *brandRow = [[UIStackView alloc] initWithArrangedSubviews:@[brand, avatar]];
    brandRow.axis = UILayoutConstraintAxisHorizontal;
    brandRow.alignment = UIStackViewAlignmentCenter;
    brandRow.spacing = 8;
    UIView *brandContainer = [UIView new];
    [brandContainer addSubview:brandRow];
    brandRow.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [brandRow.centerXAnchor constraintEqualToAnchor:brandContainer.centerXAnchor],
        [brandRow.topAnchor constraintEqualToAnchor:brandContainer.topAnchor],
        [brandRow.bottomAnchor constraintEqualToAnchor:brandContainer.bottomAnchor],
    ]];

    UILabel *welcome = [UILabel new];
    welcome.text = kIFLPWelcome;
    welcome.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    welcome.textAlignment = NSTextAlignmentCenter;

    UILabel *notice = [UILabel new];
    notice.text = kIFLPNotice;
    notice.font = [UIFont systemFontOfSize:14];
    notice.textColor = UIColor.darkTextColor;
    notice.textAlignment = NSTextAlignmentCenter;
    notice.numberOfLines = 0;

    self.enterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.enterButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.enterButton.backgroundColor = [UIColor colorWithRed:0 green:0.48 blue:1 alpha:1];
    self.enterButton.layer.cornerRadius = 8;
    self.enterButton.enabled = NO;
    self.enterButton.alpha = 0.55;
    [self.enterButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.enterButton addTarget:self action:@selector(enterApp) forControlEvents:UIControlEventTouchUpInside];
    [self.enterButton.heightAnchor constraintEqualToConstant:48].active = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, brandContainer, welcome, notice, self.enterButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 16;

    [self.view addSubview:card];
    [card addSubview:stack];
    NSLayoutConstraint *cardWidth = [card.widthAnchor constraintEqualToConstant:340];
    cardWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20],
        [card.widthAnchor constraintLessThanOrEqualToConstant:340],
        cardWidth,
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24],
    ]];

    self.secondsLeft = kIFLPSeconds;
    [self updateButton];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}

- (void)tick:(NSTimer *)timer {
    self.secondsLeft--;
    [self updateButton];
    if (self.secondsLeft == 0) {
        [self.timer invalidate];
        self.timer = nil;
        self.enterButton.enabled = YES;
        self.enterButton.alpha = 1;
    }
}

- (void)updateButton {
    NSString *title = self.secondsLeft > 0
        ? [NSString stringWithFormat:@"%@（%ld）", kIFLPAction, (long)self.secondsLeft]
        : kIFLPAction;
    [self.enterButton setTitle:title forState:UIControlStateNormal];
}

- (void)enterApp {
    [self.timer invalidate];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kIFLPShownKey];
    [UIView animateWithDuration:0.2 animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        [self.view removeFromSuperview];
        gIFLPController = nil;
    }];
}

@end

static UIWindow *IFLPWindow(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) return window;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static BOOL IFLPShowIfNeeded(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults integerForKey:kIFLPTransformKey] != 1 ||
        [defaults boolForKey:kIFLPShownKey] || gIFLPController) return NO;
    UIWindow *window = IFLPWindow();
    if (!window) return NO;

    gIFLPController = [IFLPWelcomeViewController new];
    gIFLPController.view.frame = window.bounds;
    gIFLPController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:gIFLPController.view];
    return YES;
}

__attribute__((constructor)) static void IFLPInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        gIFLPObserver = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                            object:nil
                                             queue:NSOperationQueue.mainQueue
                                        usingBlock:^(NSNotification *note) {
            if (IFLPShowIfNeeded()) {
                [center removeObserver:gIFLPObserver];
                gIFLPObserver = nil;
            }
        }];
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive && IFLPShowIfNeeded()) {
            [center removeObserver:gIFLPObserver];
            gIFLPObserver = nil;
        }
    });
}
