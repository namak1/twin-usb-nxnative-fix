#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <IOKit/hid/IOHIDManager.h>
#include "mapping.h"
#import "UniversalBridge.h"
#include <signal.h>
@interface MapperApp : NSObject <NSApplicationDelegate,WKScriptMessageHandler,WKNavigationDelegate,NSWindowDelegate>
@property NSWindow *window;
@property WKWebView *web;
@property NSString *configDir;
@property BOOL dirty;
@property BOOL ready;
@property BOOL adapter;
@property IOHIDManagerRef manager;
@property NSMutableDictionary<NSValue*,NSMutableData*> *buffers;
@property NSArray *maps;
@property NSArray *crashMaps;
@property NSString *crashDir;
@property BOOL testMode;
@property UniversalBridge *bridge;
@property BOOL exclusive;
@property BOOL inputTest;
@end
static MapperApp *application;
static unsigned prior[2]={~0u,~0u};
static unsigned long inputCounts[2];
static double inputTimes[2];
@implementation MapperApp
- (void)send:(NSDictionary*)payload {
 if(!self.ready)return;
 NSData *d=[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
 NSString *js=[NSString stringWithFormat:@"window.receiveNative(%@)",[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]];
 [self.web evaluateJavaScript:js completionHandler:nil];
}
static void inputReport(void *ctx,IOReturn result,void *sender,IOHIDReportType type,uint32_t ident,uint8_t*b,CFIndex n){
 (void)ctx;(void)sender;(void)type;
 if(result||n<8||ident<1||ident>2||b[0]!=ident)return;
 inputCounts[ident-1]++;inputTimes[ident-1]=NSProcessInfo.processInfo.systemUptime;
 [application.bridge input:(int)ident-1 bytes:b length:n];
 unsigned bits=(b[5]>>4)|((unsigned)b[6]<<4);int p=(int)ident-1;
 // Send only changed state; no queue of hundreds of identical USB reports.
 static int axes[2][5];int next[]={b[3],b[4],b[1],b[2],b[5]&15};
 if(prior[p]==bits&&!memcmp(axes[p],next,sizeof next))return;
 unsigned edge=prior[p]==~0u?0:bits&~prior[p];prior[p]=bits;memcpy(axes[p],next,sizeof next);
 [application send:@{@"type":@"input",@"player":@(p),@"bits":@(bits),@"edge":@(edge),@"axes":@[@(next[0]),@(next[1]),@(next[2]),@(next[3])],@"hat":@(next[4])}];
}
static void found(void*c,IOReturn r,void*s,IOHIDDeviceRef d){
 (void)c;(void)s;if(r)return;
 NSMutableData *buffer=[NSMutableData dataWithLength:64];application.buffers[[NSValue valueWithPointer:d]]=buffer;
 IOHIDDeviceRegisterInputReportCallback(d,buffer.mutableBytes,buffer.length,inputReport,NULL);
 application.adapter=YES;prior[0]=prior[1]=~0u;
 [application send:@{@"type":@"connection",@"connected":@YES}];
}
static void removed(void*c,IOReturn r,void*s,IOHIDDeviceRef d){
 (void)c;(void)r;(void)s;[application.buffers removeObjectForKey:[NSValue valueWithPointer:d]];
 application.adapter=application.buffers.count>0;if(!application.adapter&&application.bridge.state)[application.bridge stop];prior[0]=prior[1]=~0u;
 [application send:@{@"type":@"connection",@"connected":@(application.adapter)}];
}
- (void)readMaps {
 int m[2][12];memcpy(m[0],tf_default,sizeof tf_default);memcpy(m[1],tf_default,sizeof tf_default);
 NSString *file=[self.configDir stringByAppendingPathComponent:@"controller-mappings.txt"];
 tf_read_map(file.fileSystemRepresentation,&m[0][0],24);
 NSMutableArray *maps=[NSMutableArray array];for(int p=0;p<2;p++){NSMutableArray *row=[NSMutableArray array];for(int i=0;i<12;i++)[row addObject:@(m[p][i])];[maps addObject:row];}self.maps=maps;
}
- (void)readCrashMaps {
 int m[2][12];memcpy(m[0],tf_default,sizeof tf_default);memcpy(m[1],tf_default,sizeof tf_default);
 NSString *file=[self.crashDir stringByAppendingPathComponent:@"controller-mappings.txt"];
 if(!tf_read_map(file.fileSystemRepresentation,&m[0][0],24))tf_read_map([self.crashDir stringByAppendingPathComponent:@"player2-buttons.txt"].fileSystemRepresentation,m[1],12);
 NSMutableArray*rows=[NSMutableArray array];for(int p=0;p<2;p++){NSMutableArray*row=[NSMutableArray array];for(int i=0;i<12;i++)[row addObject:@(m[p][i])];[rows addObject:row];}self.crashMaps=rows;
}
- (NSString*)mappingText:(NSArray*)maps {
 NSMutableString *data=[NSMutableString string];
 for(NSArray *row in maps){for(NSNumber *value in row)[data appendFormat:@"%d ",value.intValue];[data appendString:@"\n"];}
 return data;
}
- (BOOL)writeMaps:(NSArray*)maps error:(NSError**)error {
 NSFileManager *fm=NSFileManager.defaultManager;
 NSString *crashFile=[self.crashDir stringByAppendingPathComponent:@"controller-mappings.txt"];
 NSString *universalFile=[self.configDir stringByAppendingPathComponent:@"controller-mappings.txt"];
 if(![fm createDirectoryAtPath:self.crashDir withIntermediateDirectories:YES attributes:nil error:error]||
    ![fm createDirectoryAtPath:self.configDir withIntermediateDirectories:YES attributes:nil error:error])return NO;
 NSData *previous=[NSData dataWithContentsOfFile:crashFile];
 NSString *text=[self mappingText:maps];
 if(![text writeToFile:crashFile atomically:YES encoding:NSUTF8StringEncoding error:error])return NO;
 if(![text writeToFile:universalFile atomically:YES encoding:NSUTF8StringEncoding error:error]){
  if(previous)[previous writeToFile:crashFile atomically:YES];else[fm removeItemAtPath:crashFile error:nil];
  return NO;
 }
 self.maps=maps;self.crashMaps=maps;self.bridge.maps=maps;
 return YES;
}
- (void)applicationDidFinishLaunching:(NSNotification*)n {
 (void)n;self.testMode=[NSProcessInfo.processInfo.arguments containsObject:@"--self-test-ui"];
 self.configDir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Twin Universal Mapper"];
 self.crashDir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/nxnative/0100F9F00C696000"];
 signal(SIGPIPE,SIG_IGN);
 [self readMaps];[self readCrashMaps];self.bridge=[UniversalBridge new];
 // The existing, tested Crash layout is the shared layout on migration.
 NSError *migrationError=nil;
 if(!self.testMode&&![self.maps isEqual:self.crashMaps]&&![self writeMaps:self.crashMaps error:&migrationError])NSLog(@"Could not synchronize controller mappings: %@",migrationError);
 self.maps=self.crashMaps;self.bridge.maps=self.maps;
 __weak MapperApp *weak=self;
 self.bridge.stateChanged=^(NSInteger state,NSString*message){[weak send:@{@"type":@"backend",@"state":@(state),@"message":message}];};
 self.bridge.capture=^BOOL(BOOL exclusive){MapperApp*s=weak;if(!s)return NO;if(exclusive&&!s.adapter)return NO;if(s.exclusive==exclusive)return YES;BOOL ok=[s rebuildInput:exclusive];if(!ok&&exclusive)[s rebuildInput:NO];return ok;};
 self.bridge.rumble=^(int p,uint8_t strong,uint8_t weakMotor){MapperApp*s=weak;if(!s.adapter)return;NSValue *key=s.buffers.allKeys.firstObject;if(!key)return;IOHIDDeviceRef dev=key.pointerValue;uint8_t data[]={(uint8_t)(p+1),0,0,strong,weakMotor};IOHIDDeviceSetReport(dev,kIOHIDReportTypeOutput,p+1,data,sizeof data);};
 [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceWillSleepNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){(void)n;[weak.bridge stop];}];
 [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidLaunchApplicationNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){NSRunningApplication*a=n.userInfo[NSWorkspaceApplicationKey];if([a.bundleIdentifier isEqual:@"org.nxnative.0100f9f00c696000"]&&weak.bridge.state){[weak.bridge stop];[weak send:@{@"type":@"backend",@"state":@0,@"message":@"Stopped virtual output for Crash Team Racing. Its saved controls remain active."}];}}];
 self.buffers=[NSMutableDictionary dictionary];
 NSMenu *menu=[NSMenu new];NSMenuItem *appMenu=[NSMenuItem new];[menu addItem:appMenu];appMenu.submenu=[NSMenu new];
 [appMenu.submenu addItemWithTitle:@"Quit Twin Controller Studio" action:@selector(terminate:) keyEquivalent:@"q"];NSApp.mainMenu=menu;
 self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1240,790) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
 self.window.title=@"Twin Controller Studio";self.window.minSize=NSMakeSize(1100,760);self.window.delegate=self;
 self.window.backgroundColor=[NSColor colorWithRed:.035 green:.065 blue:.11 alpha:1];self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
 WKWebViewConfiguration *config=[WKWebViewConfiguration new];[config.userContentController addScriptMessageHandler:self name:@"mapper"];
 self.web=[[WKWebView alloc]initWithFrame:self.window.contentView.bounds configuration:config];self.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.web.navigationDelegate=self;
 [self.web setValue:@NO forKey:@"drawsBackground"];self.window.contentView=self.web;
 NSURL *url=[NSBundle.mainBundle URLForResource:@"index" withExtension:@"html"];
 [self.web loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
 [self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
 if(!self.testMode){
  [self rebuildInput:NO];
  [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer*t){(void)t;double time=NSProcessInfo.processInfo.systemUptime;[weak send:@{@"type":@"inputHealth",@"live":@[@(inputTimes[0]>0&&time-inputTimes[0]<2),@(inputTimes[1]>0&&time-inputTimes[1]<2)],@"counts":@[@(inputCounts[0]),@(inputCounts[1])]}];}];
  self.inputTest=[NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"];
  if(self.inputTest)[self testInputStage:0];
 }
}
- (BOOL)rebuildInput:(BOOL)exclusive {
 // IOHIDManagerClose invalidates input delivery. Reopening the same manager does
 // not restore the report callbacks; create a fresh reader for every transition.
 if(self.manager){
  IOHIDManagerRegisterDeviceMatchingCallback(self.manager,NULL,NULL);
  IOHIDManagerRegisterDeviceRemovalCallback(self.manager,NULL,NULL);
  IOHIDManagerUnscheduleFromRunLoop(self.manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
  IOHIDManagerClose(self.manager,0);CFRelease(self.manager);self.manager=NULL;
 }
 [self.buffers removeAllObjects];prior[0]=prior[1]=~0u;inputTimes[0]=inputTimes[1]=0;
 self.manager=IOHIDManagerCreate(NULL,0);
 IOHIDManagerSetDeviceMatching(self.manager,(__bridge CFDictionaryRef)@{@kIOHIDVendorIDKey:@2064,@kIOHIDProductIDKey:@1});
 IOHIDManagerRegisterDeviceMatchingCallback(self.manager,found,NULL);IOHIDManagerRegisterDeviceRemovalCallback(self.manager,removed,NULL);
 IOHIDManagerScheduleWithRunLoop(self.manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
 IOReturn result=IOHIDManagerOpen(self.manager,exclusive?kIOHIDOptionsTypeSeizeDevice:0);
 self.exclusive=exclusive&&!result;
 if(result)NSLog(@"HID reader open failed: %x",result);
 return result==0;
}
- (void)testInputStage:(int)stage {
 unsigned long before0=inputCounts[0],before1=inputCounts[1];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  unsigned long n0=inputCounts[0]-before0,n1=inputCounts[1]-before1;
  printf("INPUT stage %d (%s): P1=%lu P2=%lu\n",stage,self.exclusive?"exclusive":"shared",n0,n1);fflush(stdout);
  if(n0<30||n1<30){fprintf(stderr,"FAIL: live input did not continue\n");exit(1);}
  if(stage==4){puts("PASS: both physical controllers stream through two start/stop transitions");exit(0);}
  if(![self rebuildInput:!self.exclusive])exit(1);[self testInputStage:stage+1];
 });

}
- (void)webView:(WKWebView*)web didFinishNavigation:(WKNavigation*)navigation {
 (void)navigation;self.ready=YES;prior[0]=prior[1]=~0u;
 [self send:@{@"type":@"load",@"maps":self.maps,@"connected":@(self.adapter)}];
 if(self.testMode){[web evaluateJavaScript:@"runRegressionTests()" completionHandler:^(id result,NSError*error){
  if(error){fprintf(stderr,"UI TEST ERROR: %s\n",error.description.UTF8String);exit(1);}printf("UI TESTS: %s\n",[[result description]UTF8String]);fflush(stdout);exit(0);
 }];}
}
- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
 (void)controller;if(![message.body isKindOfClass:NSDictionary.class])return;
 NSDictionary *msg=message.body;NSString *type=msg[@"type"];
 if([type isEqual:@"dirty"]){self.dirty=[msg[@"value"]boolValue];self.window.documentEdited=self.dirty;return;}
 if([type isEqual:@"start"]){if(!self.testMode){if(!self.adapter){[self send:@{@"type":@"backend",@"state":@0,@"message":@"Connect the Twin USB adapter first."}];return;}[self.bridge startWithProfile:msg[@"profile"]];}return;}
 if([type isEqual:@"stop"]){[self.bridge stop];return;}
 if([type isEqual:@"save"]){
  if(self.testMode){[self send:@{@"type":@"saved"}];return;}
  id maps=msg[@"maps"];BOOL valid=[maps isKindOfClass:NSArray.class]&&[maps count]==2;
  if(valid)for(id row in maps){if(![row isKindOfClass:NSArray.class]||[row count]!=12){valid=NO;break;}for(id v in row){if(![v isKindOfClass:NSNumber.class]||[v doubleValue]!=[v intValue]||[v intValue]<-1||[v intValue]>11){valid=NO;break;}}}
  if(!valid){[self send:@{@"type":@"error",@"message":@"Invalid mapping. Nothing was saved."}];return;}
  NSError *error=nil;
  BOOL ok=[self writeMaps:maps error:&error];
  if(ok){self.dirty=NO;self.window.documentEdited=NO;[self send:@{@"type":@"saved",@"maps":maps}];}
  else [self send:@{@"type":@"error",@"message":error.localizedDescription?:@"Could not save. Please try again."}];
 }
}
- (BOOL)canClose {
 if(!self.dirty)return YES;
 NSAlert *alert=[NSAlert new];alert.messageText=@"Discard unsaved button changes?";alert.informativeText=@"Your last saved mappings will stay in place.";
 [alert addButtonWithTitle:@"Keep editing"];[alert addButtonWithTitle:@"Discard changes"];
 return [alert runModal]==NSAlertSecondButtonReturn;
}
- (BOOL)windowShouldClose:(NSWindow*)sender{(void)sender;return [self canClose];}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender{(void)sender;return self.window.visible&&![self canClose]?NSTerminateCancel:NSTerminateNow;}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{(void)app;return YES;}
- (void)applicationWillTerminate:(NSNotification*)n{(void)n;[self.bridge stop];if(self.manager){IOHIDManagerClose(self.manager,0);CFRelease(self.manager);}}
@end
int main(int argc,const char **argv){(void)argc;(void)argv;@autoreleasepool{
 if([NSProcessInfo.processInfo.arguments containsObject:@"--self-test-sync"]){
  NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  MapperApp *test=[MapperApp new];test.crashDir=[root stringByAppendingPathComponent:@"crash"];test.configDir=[root stringByAppendingPathComponent:@"universal"];test.bridge=[UniversalBridge new];
  NSArray *row=@[@2,@0,@1,@3,@8,@9,@6,@7,@11,@10,@4,@5];NSArray *maps=@[row,row];NSError *error=nil;
  BOOL ok=[test writeMaps:maps error:&error];
  NSData *crash=[NSData dataWithContentsOfFile:[test.crashDir stringByAppendingPathComponent:@"controller-mappings.txt"]];
  NSData *universal=[NSData dataWithContentsOfFile:[test.configDir stringByAppendingPathComponent:@"controller-mappings.txt"]];
  ok=ok&&crash.length>0&&[crash isEqualToData:universal]&&[test.maps isEqual:maps]&&[test.bridge.maps isEqual:maps];
  [NSFileManager.defaultManager removeItemAtPath:root error:nil];
  if(!ok){fprintf(stderr,"FAIL: shared map write: %s\n",error.description.UTF8String?:"mismatch");return 1;}
  puts("PASS: one save writes identical Crash and universal layouts");return 0;
 }
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];application=[MapperApp new];NSApp.delegate=application;[NSApp run];
}return 0;}
