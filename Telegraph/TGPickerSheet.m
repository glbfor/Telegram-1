#import "TGPickerSheet.h"

#import "TGOverlayControllerWindow.h"
#import "TGOverlayController.h"
#import "TGNavigationController.h"

#import "TGModernButton.h"
#import "TGFont.h"

#import "TGSecretTimerValueControllerItemView.h"
#import "TGPopoverController.h"

@interface TGPickerSheetOverlayController : TGOverlayController <UIPickerViewDelegate, UIPickerViewDataSource>
{
    UIView *_backgroundView;
    UIView *_containerView;
    UIImageView *_containerBackgroundView;
    UIButton *_cancelButton;
    UIPickerView *_pickerView;
    TGModernButton *_doneButton;
}

@property (nonatomic, copy) void (^onDismiss)();
@property (nonatomic, copy) void (^onDone)(id item);
@property (nonatomic, strong) NSArray *timerValues;
@property (nonatomic) NSUInteger selectedIndex;

@end

@implementation TGPickerSheetOverlayController

- (void)loadView
{
    [super loadView];
    
    static UIImage *buttonBackgroundImage = nil;
    static UIImage *buttonBackgroundImageHighlighted = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        int radius = 6;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(radius * 2, radius * 2), false, 0.0f);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextFillEllipseInRect(context, CGRectMake(0.0f, 0.0f, radius * 2, radius * 2));
        buttonBackgroundImage = [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:radius topCapHeight:radius];
        
        CGContextClearRect(context, CGRectMake(0.0f, 0.0f, radius * 2, radius * 2));
        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.95f alpha:1.0f].CGColor);
        CGContextFillEllipseInRect(context, CGRectMake(0.0f, 0.0f, radius * 2, radius * 2));
        buttonBackgroundImageHighlighted = [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:radius topCapHeight:radius];
        
        UIGraphicsEndImageContext();
    });
    
    _backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    _backgroundView.backgroundColor = UIColorRGBA(0x000000, 0.4f);
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_backgroundView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)]];
    [self.view addSubview:_backgroundView];
    
    _containerView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, self.view.frame.size.height - 281.0f, self.view.frame.size.width, 281.0f)];
    _containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    
    _containerBackgroundView = [[UIImageView alloc] initWithFrame:CGRectMake(8.0f, 0.0f, _containerView.frame.size.width - 16.0f, 221.0f)];
    _containerBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _containerBackgroundView.image = buttonBackgroundImage;
    [_containerView addSubview:_containerBackgroundView];
    
    _cancelButton = [[UIButton alloc] initWithFrame:CGRectMake(8.0f, _containerView.frame.size.height - 44.0f - 8.0f, _containerView.frame.size.width - 16.0f, 44.0f)];
    [_cancelButton setBackgroundImage:buttonBackgroundImage forState:UIControlStateNormal];
    [_cancelButton setBackgroundImage:buttonBackgroundImageHighlighted forState:UIControlStateHighlighted];
    _cancelButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_cancelButton setTitle:TGLocalized(@"Common.Cancel") forState:UIControlStateNormal];
    [_cancelButton setTitleColor:TGAccentColor() forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = TGMediumSystemFontOfSize(21.0f);
    [_cancelButton addTarget:self action:@selector(cancelButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_cancelButton];
    
    _pickerView = [[UIPickerView alloc] initWithFrame:CGRectMake(8.0f, CGFloor((221.0f - 216.0f) / 2.0f), _containerView.frame.size.width - 16.0f, 216.0)];
    _pickerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _pickerView.dataSource = self;
    _pickerView.delegate = self;
    [_pickerView reloadAllComponents];
    [_containerView addSubview:_pickerView];
    
    _doneButton = [[TGModernButton alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 74.0f, 40.0f)];
    [_doneButton setTitleColor:TGAccentColor()];
    [_doneButton setTitle:TGLocalized(@"Common.OK") forState:UIControlStateNormal];
    [_doneButton setTitleEdgeInsets:UIEdgeInsetsMake(8.0f, 8.0f, 8.0f, 16.0f)];
    _doneButton.titleLabel.font = TGMediumSystemFontOfSize(16.0f);
    _doneButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    _doneButton.frame = CGRectMake(_containerView.frame.size.width - 8.0f - _doneButton.frame.size.width, CGFloor((221.0f - _doneButton.frame.size.height) / 2.0f), _doneButton.frame.size.width, _doneButton.frame.size.height);
    _doneButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_doneButton addTarget:self action:@selector(doneButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_doneButton];
    
    [self.view addSubview:_containerView];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateRecognized)
    {
        if (_onDismiss)
            _onDismiss();
    }
}

- (void)cancelButtonPressed
{
    if (_onDismiss)
        _onDismiss();
}

- (void)doneButtonPressed
{
    if (_onDone)
    {
        NSInteger index = [_pickerView selectedRowInComponent:0];
        if (index >= 0 && index < (NSInteger)_timerValues.count)
        {
            _onDone(_timerValues[index]);
        }
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [_pickerView reloadAllComponents];
    [_pickerView selectRow:_selectedIndex inComponent:0 animated:false];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)__unused pickerView
{
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)__unused pickerView numberOfRowsInComponent:(NSInteger)__unused component
{
    return _timerValues.count;
}

- (UIView *)pickerView:(UIPickerView *)__unused pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)__unused component reusingView:(TGSecretTimerValueControllerItemView *)view
{
    if (view != nil)
    {
        view.seconds = [_timerValues[row] intValue];
        return view;
    }
    
    TGSecretTimerValueControllerItemView *newView = [[TGSecretTimerValueControllerItemView alloc] init];
    newView.seconds = [_timerValues[row] intValue];
    return newView;
}

- (void)animateIn
{
    _containerView.frame = CGRectMake(0.0f, self.view.frame.size.height, self.view.frame.size.width, _containerView.frame.size.height);
    _backgroundView.alpha = 0.0f;
    
    [UIView animateWithDuration:0.12 delay:0.0 options:(7 << 16) | UIViewAnimationOptionAllowUserInteraction animations:^
    {
        _containerView.frame = CGRectMake(0.0f, self.view.frame.size.height - _containerView.frame.size.height, self.view.frame.size.width, _containerView.frame.size.height);
        _backgroundView.alpha = 1.0f;
    } completion:nil];
}

- (void)animateOut:(void (^)())completion
{
    [UIView animateWithDuration:0.15 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^
    {
        _containerView.frame = CGRectMake(0.0f, self.view.frame.size.height, self.view.frame.size.width, _containerView.frame.size.height);
        _backgroundView.alpha = 0.0f;
    } completion:^(__unused BOOL finished)
    {
        if (completion)
            completion();
    }];
}

@end

@interface TGPickerSheetPopoverContentController : TGViewController <UIPickerViewDataSource, UIPickerViewDelegate>
{
    UIPickerView *_pickerView;
}

@property (nonatomic, copy) void (^onDismiss)();
@property (nonatomic, copy) void (^onDone)(id item);
@property (nonatomic, strong) NSArray *timerValues;
@property (nonatomic) NSUInteger selectedIndex;

@end

@implementation TGPickerSheetPopoverContentController

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        [self setLeftBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:TGLocalized(@"Common.Cancel") style:UIBarButtonItemStylePlain target:self action:@selector(cancelButtonPressed)]];
        [self setRightBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:TGLocalized(@"Common.Done") style:UIBarButtonItemStyleDone target:self action:@selector(doneButtonPressed)]];
    }
    return self;
}

- (void)cancelButtonPressed
{
    if (_onDismiss)
        _onDismiss();
}

- (void)doneButtonPressed
{
    if (_onDone)
    {
        NSInteger index = [_pickerView selectedRowInComponent:0];
        if (index >= 0 && index < (NSInteger)_timerValues.count)
        {
            _onDone(_timerValues[index]);
        }
    }
}

- (CGSize)preferredContentSize
{
    return CGSizeMake(320.0f, 216.0f);
}

- (void)loadView
{
    [super loadView];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    _pickerView = [[UIPickerView alloc] initWithFrame:CGRectMake(0.0f, 44.0f, 320.0f, 216.0)];
    _pickerView.dataSource = self;
    _pickerView.delegate = self;
    [_pickerView reloadAllComponents];
    [self.view addSubview:_pickerView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [_pickerView reloadAllComponents];
    [_pickerView selectRow:_selectedIndex inComponent:0 animated:false];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [_pickerView reloadAllComponents];
    [_pickerView selectRow:_selectedIndex inComponent:0 animated:false];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)__unused pickerView
{
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)__unused pickerView numberOfRowsInComponent:(NSInteger)__unused component
{
    return _timerValues.count;
}

- (UIView *)pickerView:(UIPickerView *)__unused pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)__unused component reusingView:(TGSecretTimerValueControllerItemView *)view
{
    if (view != nil)
    {
        view.seconds = [_timerValues[row] intValue];
        return view;
    }
    
    TGSecretTimerValueControllerItemView *newView = [[TGSecretTimerValueControllerItemView alloc] init];
    newView.seconds = [_timerValues[row] intValue];
    return newView;
}

@end

@interface TGPickerSheetPopoverController : TGPopoverController

@end

@implementation TGPickerSheetPopoverController

- (instancetype)init
{
    TGPickerSheetPopoverContentController *contentController = [[TGPickerSheetPopoverContentController alloc] init];
    
    TGNavigationController *navigationController = [TGNavigationController navigationControllerWithControllers:@[contentController]];
    navigationController.presentationStyle = TGNavigationControllerPresentationStyleRootInPopover;
    self = [super initWithContentViewController:navigationController];
    if (self != nil)
    {
        if (iosMajorVersion() < 8)
            self.popoverContentSize = [contentController preferredContentSize];
    }
    return self;
}

- (TGPickerSheetPopoverContentController *)pickerSheetContentController
{
    return (TGPickerSheetPopoverContentController *)(((TGNavigationController *)self.contentViewController).topViewController);
}

@end

@interface TGPickerSheet ()
{
    NSArray *_items;
    NSUInteger _selectedIndex;
    
    TGOverlayControllerWindow *_controllerWindow;
    TGPickerSheetPopoverController *_popoverController;
    
    void (^_action)(id);
}

@end

@implementation TGPickerSheet

- (instancetype)initWithItems:(NSArray *)items selectedIndex:(NSUInteger)selectedIndex action:(void (^)(id item))action
{
    self = [super init];
    if (self != nil)
    {
        _items = items;
        _selectedIndex = selectedIndex;
        _action = [action copy];
    }
    return self;
}

- (void)show
{
    if (_controllerWindow == nil)
    {
        _controllerWindow = [[TGOverlayControllerWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        _controllerWindow.windowLevel = UIWindowLevelAlert;
        _controllerWindow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _controllerWindow.hidden = false;
        _controllerWindow.rootViewController = [[TGPickerSheetOverlayController alloc] init];
        __weak TGPickerSheet *weakSelf = self;
        ((TGPickerSheetOverlayController *)_controllerWindow.rootViewController).timerValues = _items;
        ((TGPickerSheetOverlayController *)_controllerWindow.rootViewController).selectedIndex = _selectedIndex;
        
        ((TGPickerSheetOverlayController *)_controllerWindow.rootViewController).onDismiss = ^
        {
            __strong TGPickerSheet *strongSelf = weakSelf;
            if (strongSelf != nil)
                [strongSelf dismiss];
        };
        
        ((TGPickerSheetOverlayController *)_controllerWindow.rootViewController).onDone = ^(id item)
        {
            __strong TGPickerSheet *strongSelf = weakSelf;
            if (strongSelf != nil)
            {
                if (strongSelf->_action)
                    strongSelf->_action(item);
                
                [strongSelf dismiss];
            }
        };
        
        [((TGPickerSheetOverlayController *)_controllerWindow.rootViewController) animateIn];
    }
}

- (void)showFromRect:(CGRect)rect inView:(UIView *)view
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        _popoverController = [[TGPickerSheetPopoverController alloc] init];
        
        __weak TGPickerSheet *weakSelf = self;
        _popoverController.pickerSheetContentController.timerValues = _items;
        _popoverController.pickerSheetContentController.selectedIndex = _selectedIndex;
        
        _popoverController.pickerSheetContentController.onDismiss = ^
        {
            __strong TGPickerSheet *strongSelf = weakSelf;
            if (strongSelf != nil)
                [strongSelf dismiss];
        };
        
        _popoverController.pickerSheetContentController.onDone = ^(id item)
        {
            __strong TGPickerSheet *strongSelf = weakSelf;
            if (strongSelf != nil)
            {
                if (strongSelf->_action)
                    strongSelf->_action(item);
                
                [strongSelf dismiss];
            }
        };
        
        [_popoverController presentPopoverFromRect:rect inView:view permittedArrowDirections:UIPopoverArrowDirectionAny animated:true];
    }
}

- (void)dismiss
{
    if (_controllerWindow != nil)
    {
        __weak TGPickerSheet *weakSelf = self;
        [((TGPickerSheetOverlayController *)_controllerWindow.rootViewController) animateOut:^
        {
            __strong TGPickerSheet *strongSelf = weakSelf;
            if (strongSelf != nil)
            {
                strongSelf->_controllerWindow.hidden = true;
                strongSelf->_controllerWindow = nil;
            }
        }];
    }
    
    if (_popoverController != nil)
    {
        [_popoverController dismissPopoverAnimated:true];
    }
}

@end
