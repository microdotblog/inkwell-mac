//
//  MBNewPostController.h
//  Inkwell
//
//  Created by Codex on 5/3/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBNewPostController : NSWindowController

@property (nonatomic, strong, readonly) NSTextField* blogHostnameField;
@property (nonatomic, copy, nullable) NSArray* _Nullable (^destinationsProvider)(void);
@property (nonatomic, copy, nullable) void (^didCloseHandler)(MBNewPostController* controller);
@property (nonatomic, copy, nullable) void (^didUpdatePostHandler)(void);

+ (void) resetPostWindowCascade;

- (void) showWithMarkdownText:(NSString *)markdownText;
- (void) showWithMarkdownText:(NSString *)markdownText destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID token:(NSString *)token;
- (void) showWithMarkdownText:(NSString *)markdownText destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID destinations:(NSArray *)destinations token:(NSString *)token;
- (void) showEditingPostURL:(NSString *)postURLString destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID destinations:(NSArray *)destinations token:(NSString *)token;
- (BOOL) isPreviewEnabled;
- (IBAction) preview:(id) sender;
- (IBAction) toggleTitleField:(id) sender;

@end

NS_ASSUME_NONNULL_END
