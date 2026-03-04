Hello, robots!

This is a Mac app using Objective-C and AppKit.

# Code style

Please use real tabs instead of spaces.

For method declarations, add a space after the type and a return before the opening curly brace, for example like this:

- (void) setupWindowIfNeeded
{
}

Local variables use snake_case with underscores.

Pointers to Obj-C objects should have a space after the `*`, like:

NSString* s = @"Hello";

Avoid including the type of items in arrays, e.g. just use `NSArray* items` not `NSArray<NSNumber *>* items`.