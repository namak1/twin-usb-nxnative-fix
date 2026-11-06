#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <objc/runtime.h>
#include "mapping.h"

// Remap only button objects belonging to this adapter. The host still owns all
// sampling, focus handling, stick axes, player assignment and haptic callbacks.
@interface TFButtonGroup : NSObject
@property NSPointerArray *buttons;
@property NSArray<NSNumber*> *mapping;
@end
@implementation TFButtonGroup
@end
@interface TFBinding : NSObject
@property TFButtonGroup *group;
@property int destination;
@property IMP original;
@end
@implementation TFBinding
@end
static char bindingKey,originalKey,profileKey;
static int player1_map[12];
static IMP originalForClass(Class cls) {
 for(Class k=cls;k;k=class_getSuperclass(k)) {
  NSValue *v=objc_getAssociatedObject(k,&originalKey);
  if(v)return (IMP)v.pointerValue;
 }
 return NULL;
}
static BOOL remappedPressed(id button,SEL sel) {
 TFBinding *b=objc_getAssociatedObject(button,&bindingKey);
 if(!b){IMP impl=originalForClass(object_getClass(button));return impl ? ((BOOL(*)(id,SEL))impl)(button,sel) : NO;}
 TFButtonGroup *g=b.group;
 for(int i=0;i<12;i++) if(g.mapping[i].intValue==b.destination) {
  id source=[g.buttons pointerAtIndex:i];
  TFBinding *src=source ? objc_getAssociatedObject(source,&bindingKey):nil;
  if(src && ((BOOL(*)(id,SEL))src.original)(source,sel))return YES;
 }
 return NO;
}
// Also exercised by the snapshot-based regression test; no hardware injection.
void tf_bind_profile(GCExtendedGamepad *g,const int map[12]) {
 if(objc_getAssociatedObject(g,&profileKey))return;
 NSArray *elements=@[g.buttonY ?: NSNull.null,g.buttonB ?: NSNull.null,
  g.buttonA ?: NSNull.null,g.buttonX ?: NSNull.null,
  g.leftTrigger ?: NSNull.null,g.rightTrigger ?: NSNull.null,
  g.leftShoulder ?: NSNull.null,g.rightShoulder ?: NSNull.null,
  g.buttonOptions ?: NSNull.null,g.buttonMenu ?: NSNull.null,
  g.leftThumbstickButton ?: NSNull.null,g.rightThumbstickButton ?: NSNull.null];
 TFButtonGroup *group=[TFButtonGroup new];group.buttons=[NSPointerArray weakObjectsPointerArray];
 NSMutableArray *values=[NSMutableArray array];for(int i=0;i<12;i++){[values addObject:@(map[i])];[group.buttons addPointer:elements[i]==NSNull.null?NULL:(__bridge void*)elements[i]];}group.mapping=values;
 for(int i=0;i<12;i++) {
  id button=elements[i];if(button==NSNull.null)continue;
  Class cls=object_getClass(button);SEL sel=@selector(isPressed);
  IMP original=class_getMethodImplementation(cls,sel);
  if(original==(IMP)remappedPressed)original=originalForClass(cls);
  if(!original)continue;
  TFBinding *binding=[TFBinding new];binding.group=group;binding.destination=tf_default[i];binding.original=original;
  objc_setAssociatedObject(button,&bindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  // Add an override to the concrete class, leaving superclass implementations intact.
  if(class_getMethodImplementation(cls,sel)!=(IMP)remappedPressed){
   objc_setAssociatedObject(cls,&originalKey,[NSValue valueWithPointer:original],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   const char *types=method_getTypeEncoding(class_getInstanceMethod(cls,sel));
   if(!class_addMethod(cls,sel,(IMP)remappedPressed,types))class_replaceMethod(cls,sel,(IMP)remappedPressed,types);
  }
 }
 objc_setAssociatedObject(g,&profileKey,group,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void discover(void) {
 for(GCController *c in GCController.controllers){
  NSString *name=[c.vendorName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if(![name isEqualToString:@"Twin USB Gamepad"] || !c.extendedGamepad)continue;
  if(!objc_getAssociatedObject(c.extendedGamepad,&profileKey)){
   tf_bind_profile(c.extendedGamepad,player1_map);
   fprintf(stderr,"[twinfix] player 1 independent button mapping enabled\n");
  }
 }
}
void tf_start_player1(const int map[12]) {
 memcpy(player1_map,map,sizeof player1_map);
 dispatch_async(dispatch_get_main_queue(), ^{
  discover();
  [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){(void)n;discover();}];
  // Discovery can finish after the native controller-connected notification.
  static dispatch_source_t timer;timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
  dispatch_source_set_event_handler(timer,^{discover();});dispatch_resume(timer);
 });
}
