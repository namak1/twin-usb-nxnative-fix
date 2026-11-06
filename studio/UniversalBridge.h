#import <Foundation/Foundation.h>
@interface UniversalBridge : NSObject
@property(copy) void (^stateChanged)(NSInteger state,NSString *message);
@property(copy) BOOL (^capture)(BOOL exclusive);
@property(copy) void (^rumble)(int player,uint8_t strong,uint8_t weak);
@property(readonly) NSInteger state;
@property NSArray *maps;
- (void)startWithProfile:(NSString*)profile;
- (void)stop;
- (void)input:(int)player bytes:(const uint8_t*)bytes length:(NSUInteger)length;
+ (NSDictionary*)frameForReport:(NSData*)data map:(NSArray*)map;
@end
