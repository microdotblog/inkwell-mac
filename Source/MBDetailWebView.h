#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBDetailWebView : WKWebView

@property (copy, nullable) BOOL (^focusSidebarHandler)(void);
@property (copy, nullable) BOOL (^scrollPageUpHandler)(void);
@property (copy, nullable) BOOL (^scrollPageDownHandler)(void);
@property (copy, nullable) void (^deleteHoveredHighlightHandler)(void);
@property (copy, nullable) BOOL (^shouldShowHighlightMenuItemHandler)(void);
@property (copy, nullable) BOOL (^shouldShowDeleteHighlightMenuItemHandler)(void);

@end

NS_ASSUME_NONNULL_END
