#include <IOKit/hid/IOHIDManager.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static void (*setpad)(int,uint64_t,int32_t,int32_t,int32_t,int32_t);
static void (*players)(uint32_t);
static IOHIDManagerRef manager;
static uint8_t input[64];
static int connected;
static int axis(uint8_t x) { int a=((int)x-128)*258; return a < -32767 ? -32767 : a > 32767 ? 32767 : a; }
static void report(void *ctx,IOReturn result,void *sender,IOHIDReportType type,uint32_t id,uint8_t *b,CFIndex n) {
 (void)ctx;(void)sender;(void)type;
 if(result || id!=2 || n<8 || b[0]!=2 || !setpad || !players) return;
 unsigned bits=(b[5]>>4)|((unsigned)b[6]<<4); uint64_t m=0;
 const int map[12]={3,1,0,2,6,7,8,9,11,10,4,5};
 for(int i=0;i<12;i++) if(bits&(1u<<i)) m|=1ull<<map[i];
 int h=b[5]&15; if(h==7||h<=1)m|=1ull<<13; if(h>=1&&h<=3)m|=1ull<<14; if(h>=3&&h<=5)m|=1ull<<15; if(h>=5&&h<=7)m|=1ull<<12;
 players(3); setpad(1,m,axis(b[3]),-axis(b[4]),axis(b[1]),-axis(b[2]));
 static int once; if(!once++){fprintf(stderr,"[twinfix] receiving second controller, Player 2 enabled\n");}
}
static void found(void *c,IOReturn r,void *s,IOHIDDeviceRef d) { (void)c;(void)r;(void)s; connected=1; fprintf(stderr,"[twinfix] twin adapter connected\n"); IOHIDDeviceRegisterInputReportCallback(d,input,sizeof input,report,NULL); }
static void removed(void *c,IOReturn r,void *s,IOHIDDeviceRef d) { (void)c;(void)r;(void)s;(void)d; if(connected){connected=0; setpad(1,0,0,0,0,0); players(1); fprintf(stderr,"[twinfix] twin adapter disconnected\n");} }
__attribute__((constructor)) static void init(void) {
 setpad=dlsym(RTLD_DEFAULT,"dm_pad_set_player"); players=dlsym(RTLD_DEFAULT,"dm_pad_players");
 if(!setpad||!players){fprintf(stderr,"[twinfix] input interface unavailable\n");return;}
 dispatch_async(dispatch_get_main_queue(), ^{
 manager=IOHIDManagerCreate(NULL,0); int v=0x0810,p=1;
 CFNumberRef vn=CFNumberCreate(NULL,kCFNumberIntType,&v),pn=CFNumberCreate(NULL,kCFNumberIntType,&p);
 const void *keys[]={CFSTR(kIOHIDVendorIDKey),CFSTR(kIOHIDProductIDKey)},*vals[]={vn,pn};
 CFDictionaryRef match=CFDictionaryCreate(NULL,keys,vals,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 IOHIDManagerSetDeviceMatching(manager,match); CFRelease(match); CFRelease(vn); CFRelease(pn);
 IOHIDManagerRegisterDeviceMatchingCallback(manager,found,NULL); IOHIDManagerRegisterDeviceRemovalCallback(manager,removed,NULL);
 IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
 IOReturn r=IOHIDManagerOpen(manager,0); fprintf(stderr,"[twinfix] input manager open: 0x%x\n",r);
 });
}
