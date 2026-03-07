//
//  MBMention.h
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBMention : NSObject

@property (nonatomic, copy) NSString* avatarURL;
@property (nonatomic, copy) NSString* fullName;
@property (nonatomic, copy) NSString* username;
@property (nonatomic, copy) NSString* text;
@property (nonatomic, strong, nullable) NSDate* date;

@end

NS_ASSUME_NONNULL_END
