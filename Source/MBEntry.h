//
//  MBEntry.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBEntry : NSObject

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *summary;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *source;
@property (nonatomic, strong, nullable) NSDate *date;
@property (nonatomic, assign) BOOL isRead;

@end

NS_ASSUME_NONNULL_END
