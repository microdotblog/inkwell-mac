//
//  MBEntry.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBEntry : NSObject

@property (nonatomic, copy, nullable) NSString* title;
@property (nonatomic, copy, nullable) NSString* url;
@property (nonatomic, copy, nullable) NSString* subscriptionTitle;
@property (nonatomic, copy, nullable) NSString* summary;
@property (nonatomic, copy, nullable) NSString* text;
@property (nonatomic, copy, nullable) NSString* source;
@property (nonatomic, copy, nullable) NSString* author;
@property (nonatomic, copy, nullable) NSString* avatarURL;
@property (nonatomic, copy, nullable) NSString* enclosureURL;
@property (nonatomic, copy, nullable) NSString* itunesDuration;
@property (nonatomic, assign) NSInteger entryID;
@property (nonatomic, assign) NSInteger feedID;
@property (nonatomic, copy, nullable) NSString* feedHost;
@property (nonatomic, strong, nullable) NSDate* date;
@property (nonatomic, assign) BOOL isRead;
@property (nonatomic, assign) BOOL isBookmarked;
@property (nonatomic, assign) BOOL isBookmarkEntry;

- (BOOL) hasEnclosure;

@end

NS_ASSUME_NONNULL_END
