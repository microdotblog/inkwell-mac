//
//  MBPathUtilities.h
//  Inkwell
//
//  Created by Codex on 3/15/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBPathUtilities : NSObject

+ (NSURL* _Nullable) appContainerDirectoryURLForSearchPathDirectory:(NSSearchPathDirectory) search_path_directory createIfNeeded:(BOOL) create_if_needed;
+ (NSURL* _Nullable) appSubdirectoryURLForSearchPathDirectory:(NSSearchPathDirectory) search_path_directory relativePath:(NSString*) relative_path createIfNeeded:(BOOL) create_if_needed;
+ (NSURL* _Nullable) appFileURLForSearchPathDirectory:(NSSearchPathDirectory) search_path_directory filename:(NSString*) filename createDirectoryIfNeeded:(BOOL) create_directory_if_needed;
+ (void) cleanupLegacyFiles;

@end

NS_ASSUME_NONNULL_END
