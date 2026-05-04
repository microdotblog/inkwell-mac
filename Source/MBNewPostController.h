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

- (void) showWithMarkdownText:(NSString *)markdownText;
- (void) showWithMarkdownText:(NSString *)markdownText destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID token:(NSString *)token;
- (void) showWithMarkdownText:(NSString *)markdownText destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID destinations:(NSArray *)destinations token:(NSString *)token;
- (IBAction) preview:(id) sender;

@end

NS_ASSUME_NONNULL_END
