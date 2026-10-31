#include <IOKit/hid/IOHIDManager.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
static void (*setpad)(int,uint64_t,int32_t,int32_t,int32_t,int32_t);
static void (*players)(uint32_t);
static IOHIDManagerRef manager;
static uint8_t input[64];
static int connected;
typedef struct { float amplitude_low, frequency_low, amplitude_high, frequency_high; } vibration;
typedef struct { int player; uint64_t epoch; vibration motor[2]; } haptic_state;
static void (*haptic_init)(void (*)(haptic_state), int);
static void (*haptic_route)(int, int);
static uint32_t (*haptic_available)(void);
static dispatch_queue_t output_queue;
static IOHIDDeviceRef output_device;
static int haptic_started;
static uint8_t last_strong[2], last_weak[2];
static unsigned vibration_log_count[2];
static void write_motor(int player, uint8_t strong, uint8_t weak) {
 if (!output_device || player < 0 || player > 1) return;
 uint8_t bytes[]={(uint8_t)(player+1),0,0,strong,weak};
 IOReturn r=IOHIDDeviceSetReport(output_device,kIOHIDReportTypeOutput,player+1,bytes,sizeof bytes);
 if(r) fprintf(stderr,"[twinfix] vibration report failed: 0x%x\n",r);
}
static void shutdown_output(void) {
 if(!output_queue) return;
 dispatch_sync(output_queue, ^{ if(output_device){write_motor(0,0,0);write_motor(1,0,0);} });
}
static uint8_t magnitude(float x) {
 if(!isfinite(x) || x<=0.01f) return 0;
 if(x>1) x=1;
 return (uint8_t)(x*127.f);
}
// Called under nxnative's haptic lock: enqueue the snapshot, never re-enter the host.
static void haptic_sink(haptic_state s) {
 if(s.player<0 || s.player>1) return;
 float lo=fmaxf(s.motor[0].amplitude_low,s.motor[1].amplitude_low);
 float hi=fmaxf(s.motor[0].amplitude_high,s.motor[1].amplitude_high);
 uint8_t strong=magnitude(lo), weak=magnitude(hi); int p=s.player;
 dispatch_async(output_queue, ^{
  if(strong==last_strong[p] && weak==last_weak[p]) return;
  last_strong[p]=strong; last_weak[p]=weak;
  write_motor(p,strong,weak);
  if((strong || weak) && vibration_log_count[p]++ < 5) fprintf(stderr,"[twinfix] vibration player %d: %u %u\n",p+1,strong,weak);
 });
}
static void haptic_start(void) {
 if(!connected || haptic_started || !haptic_init || !haptic_route || !haptic_available) return;
 const char *value=getenv("DM_RUMBLE");
 if(value && atoi(value)==0) { fprintf(stderr,"[twinfix] vibration disabled by DM_RUMBLE\n"); return; }
 haptic_init(haptic_sink,1); haptic_route(0,1); haptic_route(1,1); haptic_started=1;
 fprintf(stderr,"[twinfix] vibration enabled for both controllers\n");
}
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
static void found(void *c,IOReturn r,void *s,IOHIDDeviceRef d) { (void)c;(void)r;(void)s; connected=1; fprintf(stderr,"[twinfix] twin adapter connected\n"); IOHIDDeviceRegisterInputReportCallback(d,input,sizeof input,report,NULL);
 CFRetain(d); dispatch_async(output_queue, ^{ if(output_device) CFRelease(output_device); output_device=d; memset(last_strong,0,sizeof last_strong); memset(last_weak,0,sizeof last_weak); });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(), ^{ haptic_start(); });
}
static void removed(void *c,IOReturn r,void *s,IOHIDDeviceRef d) { (void)c;(void)r;(void)s;(void)d; if(connected){connected=0; setpad(1,0,0,0,0,0); players(1); if(haptic_started){ haptic_route(0,0); haptic_route(1,0); haptic_started=0; } dispatch_async(output_queue, ^{ if(output_device){write_motor(0,0,0);write_motor(1,0,0);CFRelease(output_device);output_device=NULL;} }); fprintf(stderr,"[twinfix] twin adapter disconnected\n");} }
__attribute__((constructor)) static void init(void) {
 setpad=dlsym(RTLD_DEFAULT,"dm_pad_set_player"); players=dlsym(RTLD_DEFAULT,"dm_pad_players");
 if(!setpad||!players){fprintf(stderr,"[twinfix] input interface unavailable\n");return;}
 haptic_init=dlsym(RTLD_DEFAULT,"dm_haptics_init"); haptic_route=dlsym(RTLD_DEFAULT,"dm_haptics_route"); haptic_available=dlsym(RTLD_DEFAULT,"dm_haptics_available");
 output_queue=dispatch_queue_create("twinfix.output",DISPATCH_QUEUE_SERIAL);
 atexit(shutdown_output);
 dispatch_async(dispatch_get_main_queue(), ^{
 manager=IOHIDManagerCreate(NULL,0); int v=0x0810,p=1;
 CFNumberRef vn=CFNumberCreate(NULL,kCFNumberIntType,&v),pn=CFNumberCreate(NULL,kCFNumberIntType,&p);
 const void *keys[]={CFSTR(kIOHIDVendorIDKey),CFSTR(kIOHIDProductIDKey)},*vals[]={vn,pn};
 CFDictionaryRef match=CFDictionaryCreate(NULL,keys,vals,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 IOHIDManagerSetDeviceMatching(manager,match); CFRelease(match); CFRelease(vn); CFRelease(pn);
 IOHIDManagerRegisterDeviceMatchingCallback(manager,found,NULL); IOHIDManagerRegisterDeviceRemovalCallback(manager,removed,NULL);
 IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),kCFRunLoopCommonModes);
 IOReturn r=IOHIDManagerOpen(manager,0); fprintf(stderr,"[twinfix] input manager open: 0x%x\n",r);
 dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
 dispatch_source_set_event_handler(timer, ^{ if(connected && haptic_started){uint32_t mask=haptic_available(); if(!(mask&1))haptic_route(0,1);if(!(mask&2))haptic_route(1,1);} });
 dispatch_resume(timer);
 });
}
