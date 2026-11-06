#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface Screenshots : NSObject <WKNavigationDelegate>
@property NSWindow *window;
@property WKWebView *web;
@property NSInteger player;
@end

@implementation Screenshots
- (void)capture {
 [self.web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
  if(error || !image){NSLog(@"Screenshot failed: %@",error);exit(1);}
  NSBitmapImageRep *bitmap=[NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
  NSData *jpeg=[bitmap representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor:@0.86}];
  NSString *path=[NSString stringWithFormat:@"screenshots/player-%ld.jpg",(long)self.player+1];
  if(![jpeg writeToFile:path atomically:YES])exit(1);
  if(self.player==0){
   self.player=1;
   [self.web evaluateJavaScript:@"switchPlayer(1); choose(8,true)" completionHandler:^(id result,NSError *jsError){(void)result;if(jsError)exit(1);[self capture];}];
  }else{puts("Rendered two interface screenshots");exit(0);}
 }];
}
- (void)webView:(WKWebView*)web didFinishNavigation:(WKNavigation*)navigation {
 (void)navigation;
 // Use the tested default bindings for both players; the USB is connected,
 // but no controller input is synthesized for these idle screenshots.
 NSString *script=@"receiveNative({type:'load',maps:[[2,0,1,3,8,9,6,7,11,10,4,5],[2,0,1,3,8,9,6,7,11,10,4,5]],connected:true})";
 [web evaluateJavaScript:script completionHandler:^(id result,NSError *error){(void)result;if(error)exit(1);[self capture];}];
}
@end

int main(void){@autoreleasepool{
 [NSApplication sharedApplication];
 Screenshots *preview=[Screenshots new];
 preview.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1240,790) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 preview.web=[[WKWebView alloc]initWithFrame:preview.window.contentView.bounds];
 preview.window.contentView=preview.web;preview.web.navigationDelegate=preview;
 [preview.window orderBack:nil];
 NSString *path=[[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"studio"]stringByAppendingPathComponent:@"index.html"];
 NSURL *url=[NSURL fileURLWithPath:path];
 [preview.web loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
 [NSApp run];
}return 0;}
