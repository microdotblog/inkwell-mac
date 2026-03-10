//
//  MBSubscription.h
//  Inkwell
//
//  Created by Manton Reece on 3/4/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBSubscription : NSObject

@property (nonatomic, assign) NSInteger subscriptionID;
@property (nonatomic, strong, nullable) NSDate* createdAt;
@property (nonatomic, assign) NSInteger feedID;
@property (nonatomic, copy, nullable) NSString* title;
@property (nonatomic, copy, nullable) NSString* feedURL;
@property (nonatomic, copy, nullable) NSString* siteURL;
@property (nonatomic, copy, nullable) NSString* avatarURL;

@end

NS_ASSUME_NONNULL_END
