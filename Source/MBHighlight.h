//
//  MBHighlight.h
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBHighlight : NSObject

@property (nonatomic, assign) NSInteger entryID;
@property (nonatomic, copy, nullable) NSString* selectionText;
@property (nonatomic, assign) NSInteger selectionStart;
@property (nonatomic, assign) NSInteger selectionEnd;
@property (nonatomic, strong, nullable) NSDate* updatedDate;

@end

NS_ASSUME_NONNULL_END
