#import "UniversalBridge.h"
#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <math.h>
@interface UniversalBridge () {
 NSTask *_tasks[2]; NSFileHandle *_writers[2]; NSMutableData *_errors[2],*_outputs[2];
 BOOL _ready[2]; NSData *_raw[2],*_lastFrame[2]; double _sent[2];
 uint8_t _wanted[2][2],_motors[2][2],_held[2][2]; double _until[2][2],_durationUntil[2];
 dispatch_source_t _timer; NSUInteger _generation;
 BOOL _nativeProfile; NSSet *_existingControllers; NSMutableArray<GCController*> *_nativeControllers;
}
@property(readwrite) NSInteger state;
@end
@implementation UniversalBridge
static double now(void){return NSProcessInfo.processInfo.systemUptime;}
- (instancetype)init {self=[super init];if(self)for(int p=0;p<2;p++){_outputs[p]=[NSMutableData data];_errors[p]=[NSMutableData data];}return self;}
- (void)announce:(NSInteger)state text:(NSString*)text {self.state=state;if(self.stateChanged)self.stateChanged(state,text);}
+ (NSDictionary*)frameForReport:(NSData*)data map:(NSArray*)map {
 if(data.length<8||map.count!=12)return @{};
 const uint8_t*b=data.bytes;unsigned bits=(b[5]>>4)|((unsigned)b[6]<<4),targets=0;
 for(int i=0;i<12;i++){int t=[map[i]intValue];if((bits&(1u<<i))&&t>=0&&t<12)targets|=1u<<t;}
 NSArray *names=@[@"East",@"South",@"North",@"West",@"LeftStickClick",@"RightStickClick",@"LeftShoulder",@"RightShoulder",@"",@"",@"Start",@"Back"];
 NSMutableArray *buttons=[NSMutableArray array],*hat=[NSMutableArray array];for(int t=0;t<12;t++)if((targets&(1u<<t))&&[names[t]length])[buttons addObject:names[t]];
 int h=b[5]&15;if(h==7||h<=1)[hat addObject:@"DpadUp"];if(h>=1&&h<=3)[hat addObject:@"DpadRight"];if(h>=3&&h<=5)[hat addObject:@"DpadDown"];if(h>=5&&h<=7)[hat addObject:@"DpadLeft"];
 NSMutableDictionary *axes=[NSMutableDictionary dictionary];NSArray *axisNames=@[@"LeftStickX",@"LeftStickY",@"RightStickX",@"RightStickY"];int raw[]={b[3],b[4],b[1],b[2]};
 for(int i=0;i<4;i++){int delta=raw[i]-128;double v=delta<0?delta/128.0:delta/127.0;axes[axisNames[i]]=@(v);}
 axes[@"LeftTrigger"]=@((targets>>8)&1);axes[@"RightTrigger"]=@((targets>>9)&1);
 return @{@"buttons":buttons,@"dpad":hat,@"axes":axes};
}
- (NSString*)toolPath {
 NSFileManager*fm=NSFileManager.defaultManager;
 NSString *app=[NSHomeDirectory()stringByAppendingPathComponent:@"Applications/OpenJoystickDriver.app"];
 if(![fm fileExistsAtPath:app])app=@"/Applications/OpenJoystickDriver.app";
 NSString*target=[app stringByAppendingPathComponent:@"Contents/MacOS/OpenJoystickDriver"];
 if(![fm isExecutableFileAtPath:target])return nil;
 NSString*dir=[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/Twin Universal Mapper/bin"];
 [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 NSString*link=[dir stringByAppendingPathComponent:@"ojd"];
 NSString*existing=[fm destinationOfSymbolicLinkAtPath:link error:nil];
 if(existing&&![existing isEqual:target])[fm removeItemAtPath:link error:nil];
 if(![fm fileExistsAtPath:link]&&![fm createSymbolicLinkAtPath:link withDestinationPath:target error:nil])return nil;
 return [[fm destinationOfSymbolicLinkAtPath:link error:nil]isEqual:target]?link:nil;
}
- (void)startWithProfile:(NSString*)profile {
 if(self.state)return;
 if(![@[@"game-controller-compatible",@"sdl-compatible",@"generic"]containsObject:profile])return;
 if([NSRunningApplication runningApplicationsWithBundleIdentifier:@"org.nxnative.0100f9f00c696000"].count){[self announce:0 text:@"Crash uses the saved layout directly. Quit Crash to start virtual controllers for other games."];return;}
 NSString*tool=[self toolPath];if(!tool){[self announce:0 text:@"OpenJoystickDriver is missing. Install the signed helper to start virtual controllers."];return;}
 [self announce:1 text:@"Starting the signed controller driver…"];NSUInteger generation=++_generation;
 // Start is bounded; never block the editor while the signed service launches.
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  NSTask *service=[NSTask new];service.executableURL=[NSURL fileURLWithPath:tool];service.arguments=@[@"--timeout",@"5",@"service",@"start"];
  NSPipe*err=[NSPipe pipe];service.standardError=err;service.standardOutput=[NSFileHandle fileHandleWithNullDevice];NSError*error=nil;
  BOOL launched=[service launchAndReturnError:&error];if(launched)[service waitUntilExit];
  NSString*reason=launched?[[NSString alloc]initWithData:[err.fileHandleForReading readDataToEndOfFile]encoding:NSUTF8StringEncoding]:error.localizedDescription;
  dispatch_async(dispatch_get_main_queue(),^{if(self->_generation!=generation)return;
   if(!launched||service.terminationStatus){[self announce:0 text:reason.length?reason:@"The driver service could not start."];return;}
   [self launchFeeds:tool profile:profile generation:generation];
  });
 });
}
- (void)launchFeeds:(NSString*)tool profile:(NSString*)profile generation:(NSUInteger)generation {
 _nativeProfile=[profile isEqual:@"game-controller-compatible"];_existingControllers=[NSSet setWithArray:GCController.controllers];_nativeControllers=[NSMutableArray array];
 [self launchFeed:0 tool:tool profile:profile generation:generation];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self->_generation==generation&&self.state==1){[self stop];[self announce:0 text:@"The virtual-controller driver did not become ready. Check OpenJoystickDriver’s Access page."];}});
}
- (void)launchFeed:(int)p tool:(NSString*)tool profile:(NSString*)profile generation:(NSUInteger)generation {
  _errors[p]=[NSMutableData data];_outputs[p]=[NSMutableData data];_ready[p]=NO;
  NSTask*t=[NSTask new];_tasks[p]=t;t.executableURL=[NSURL fileURLWithPath:tool];t.arguments=@[@"--timeout",@"5",@"virtual",@"feed",@"--as",profile];
  NSPipe*in=[NSPipe pipe],*out=[NSPipe pipe],*err=[NSPipe pipe];t.standardInput=in;t.standardOutput=out;t.standardError=err;_writers[p]=in.fileHandleForWriting;
  fcntl(_writers[p].fileDescriptor,F_SETFL,O_NONBLOCK);
  __weak UniversalBridge*weak=self;
  out.fileHandleForReading.readabilityHandler=^(NSFileHandle*h){NSData*d=h.availableData;if(!d.length){h.readabilityHandler=nil;return;}dispatch_async(dispatch_get_main_queue(),^{UniversalBridge*s=weak;if(s&&s->_generation==generation)[s output:d player:p];});};
  err.fileHandleForReading.readabilityHandler=^(NSFileHandle*h){NSData*d=h.availableData;if(!d.length){h.readabilityHandler=nil;return;}dispatch_async(dispatch_get_main_queue(),^{UniversalBridge*s=weak;if(!s||s->_generation!=generation)return;
   if(s->_errors[p].length+d.length<8192)[s->_errors[p]appendData:d];
   NSString*text=[[NSString alloc]initWithData:s->_errors[p]encoding:NSUTF8StringEncoding];
   if([text containsString:@"Publishing "]){s->_ready[p]=YES;if(p==0&&!s->_tasks[1])[s launchFeed:1 tool:tool profile:profile generation:generation];if(s->_ready[0]&&s->_ready[1]&&s.state==1){
    if(s.capture&&!s.capture(YES)){[s stop];[s announce:0 text:@"Could not take exclusive control of the Twin USB adapter. Close other controller tools and retry."];return;}
    [s beginTimer];[s announce:2 text:@"Two virtual controllers are active. Choose the two virtual controllers in your game."];
   }}
  });};
  t.terminationHandler=^(NSTask*ended){(void)ended;dispatch_async(dispatch_get_main_queue(),^{UniversalBridge*s=weak;if(!s||s->_generation!=generation)return;
   NSString*text=[[NSString alloc]initWithData:s->_errors[p]encoding:NSUTF8StringEncoding];[s stop];[s announce:0 text:text.length?text:@"The controller driver stopped. Press Start controllers to retry."];
  });};
  NSError*error=nil;if(![t launchAndReturnError:&error]){[self stop];[self announce:0 text:error.localizedDescription];return;}
  // The feed starts before consuming its first input line.
  [self writeFrame:@{} player:p];if(self.state!=1)return;
}
- (void)beginTimer {
 _timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(_timer,DISPATCH_TIME_NOW,16*NSEC_PER_MSEC,2*NSEC_PER_MSEC);
 __weak UniversalBridge*weak=self;dispatch_source_set_event_handler(_timer,^{[weak tick];});dispatch_resume(_timer);
}
- (void)input:(int)p bytes:(const uint8_t*)b length:(NSUInteger)n {
 if(p<0||p>1||n<8)return;NSData*d=[NSData dataWithBytes:b length:n];
 BOOL edge=NO;if(_raw[p]){const uint8_t*old=_raw[p].bytes;edge=old[5]!=b[5]||old[6]!=b[6];}_raw[p]=d;
 if(self.state==2&&edge)[self sendPlayer:p force:YES];
}
- (NSArray*)effectiveMap:(int)p {
 NSArray *map=self.maps[p];if(!_nativeProfile)return map;
 for(GCController*c in GCController.controllers)if([c.productCategory isEqual:GCProductCategoryXboxOne]&&![_existingControllers containsObject:c]&&![_nativeControllers containsObject:c])[_nativeControllers addObject:c];
 if(_nativeControllers.count<=(NSUInteger)p)return map;
 GCPhysicalInputProfile*profile=_nativeControllers[p].physicalInputProfile;
 if(!profile.hasRemappedElements)return map;
 NSArray*names=@[GCInputButtonB,GCInputButtonA,GCInputButtonY,GCInputButtonX,GCInputLeftThumbstickButton,GCInputRightThumbstickButton,GCInputLeftShoulder,GCInputRightShoulder,GCInputLeftTrigger,GCInputRightTrigger,GCInputButtonMenu,GCInputButtonOptions];
 NSMutableArray*result=[map mutableCopy];
 for(int i=0;i<12;i++){int target=[map[i]intValue];if(target<0||target>=12)continue;NSString*desired=names[target];NSSet*physical=[profile mappedPhysicalInputNamesForElementAlias:desired];
  // Invert reversible macOS remaps only for the native output profile. SDL reads raw HID.
  if([physical containsObject:desired])continue;
  for(int j=0;j<12;j++)if([physical containsObject:names[j]]){result[i]=@(j);break;}
 }
 return result;
}
- (void)sendPlayer:(int)p force:(BOOL)force {
 NSDictionary*f=(_raw[p]&&self.maps.count==2)?[UniversalBridge frameForReport:_raw[p] map:[self effectiveMap:p]]:@{};
 NSData*d=[NSJSONSerialization dataWithJSONObject:f options:NSJSONWritingSortedKeys error:nil];
 if(force||![_lastFrame[p]isEqual:d]||now()-_sent[p]>.25){_lastFrame[p]=d;[self writeFrame:f player:p];}
}
- (void)writeFrame:(NSDictionary*)frame player:(int)p {
 if(!_writers[p])return;
 NSMutableData*d=[[NSJSONSerialization dataWithJSONObject:frame options:0 error:nil]mutableCopy];[d appendBytes:"\n" length:1];
 ssize_t n=write(_writers[p].fileDescriptor,d.bytes,d.length);
 if(n!=(ssize_t)d.length){[self stop];[self announce:0 text:@"Controller output stalled. Both virtual controllers were stopped to release their buttons."];return;}_sent[p]=now();
}
- (void)output:(NSData*)data player:(int)p {
 if(_outputs[p].length+data.length>65536){[_outputs[p]setLength:0];return;}[_outputs[p]appendData:data];
 for(;;){const uint8_t*b=_outputs[p].bytes;NSUInteger n=_outputs[p].length,i=0;while(i<n&&b[i]!='\n')i++;if(i==n)break;
  NSData*line=[_outputs[p]subdataWithRange:NSMakeRange(0,i)];[_outputs[p]replaceBytesInRange:NSMakeRange(0,i+1)withBytes:NULL length:0];
  NSDictionary*j=[NSJSONSerialization JSONObjectWithData:line options:0 error:nil];if(![j isKindOfClass:NSDictionary.class])continue;
  if([j[@"type"]isEqual:@"StopRumble"]){_wanted[p][0]=_wanted[p][1]=0;_durationUntil[p]=0;}
  else if([j[@"type"]isEqual:@"SetRumble"]){NSDictionary*v=j[@"intensities"];NSArray*keys=@[@"lowFrequency",@"highFrequency"];
   for(int m=0;m<2;m++){double x=[v[keys[m]]doubleValue]/65535.;uint8_t value=(!isfinite(x)||x<=.04)?0:(uint8_t)(64+fmin(1,x)*63);_wanted[p][m]=value;if(value){_held[p][m]=value;_until[p][m]=now()+.15;}}
   double duration=[j[@"durationMilliseconds"]doubleValue];_durationUntil[p]=duration>0?now()+duration/1000:0;
  }
 }
}
- (void)tick {
 if(self.state!=2)return;
 for(int p=0;p<2;p++){
  [self sendPlayer:p force:NO];if(self.state!=2)return;
  if(_durationUntil[p]>0&&now()>=_durationUntil[p]){_wanted[p][0]=_wanted[p][1]=0;_durationUntil[p]=0;}
  BOOL change=NO;for(int m=0;m<2;m++){uint8_t value=_wanted[p][m];if(!value&&now()<_until[p][m])value=_held[p][m];if(value!=_motors[p][m]){_motors[p][m]=value;change=YES;}}
  if(change&&self.rumble)self.rumble(p,_motors[p][0],_motors[p][1]);
 }
}
- (void)stop {
 ++_generation;if(_timer){dispatch_source_cancel(_timer);_timer=nil;}
 for(int p=0;p<2;p++){
  if(self.rumble)self.rumble(p,0,0);
  if(_writers[p]){write(_writers[p].fileDescriptor,"{}\n",3);[_writers[p]closeFile];_writers[p]=nil;}
  NSTask*t=_tasks[p];if(t.running)[t terminate];_tasks[p]=nil;_raw[p]=nil;_lastFrame[p]=nil;_ready[p]=NO;
  memset(_wanted[p],0,2);memset(_motors[p],0,2);memset(_held[p],0,2);memset(_until[p],0,sizeof _until[p]);_durationUntil[p]=0;
 }
 if(self.capture)self.capture(NO);[self announce:0 text:@"Virtual controllers stopped. The original controller is available again."];
}
@end
