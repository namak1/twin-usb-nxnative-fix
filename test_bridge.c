#define TF_TEST 1
#include "twinfix.c"
#include <assert.h>
static int calls,slot;static uint64_t actual;static uint32_t mask;static int32_t ax[4];
static void receive(int p,uint64_t b,int32_t x,int32_t y,int32_t rx,int32_t ry){calls++;slot=p;actual=b;ax[0]=x;ax[1]=y;ax[2]=rx;ax[3]=ry;}
static void connected_players(uint32_t m){mask=m;}
int main(){setpad=receive;players=connected_players;int checks=0;
 for(int mode=0;mode<3;mode++){
  memcpy(button_maps[1],tf_default,sizeof tf_default);
  if(mode==1){button_maps[1][0]=1;button_maps[1][2]=2;}
  if(mode==2){button_maps[1][0]=-1;button_maps[1][1]=1;}
  for(unsigned b=0;b<4096;b++){
   uint8_t data[]={2,128,128,128,128,(uint8_t)(((b&15)<<4)|15),(uint8_t)(b>>4),0};
   report(NULL,0,NULL,kIOHIDReportTypeInput,2,data,sizeof data);
   assert(slot==1&&mask==3&&actual==tf_buttons(b,button_maps[1]));assert(!ax[0]&&!ax[1]&&!ax[2]&&!ax[3]);checks++;
  }
 }
 int before=calls;uint8_t invalid[]={1,128,128,128,128,15,0,0};report(NULL,0,NULL,0,1,invalid,8);report(NULL,0,NULL,0,2,invalid,8);invalid[0]=2;report(NULL,0,NULL,0,2,invalid,6);assert(calls==before);
 uint8_t d[]={2,0,255,255,0,0,0,0};report(NULL,0,NULL,0,2,d,8);assert(actual==(1ull<<13));assert(ax[0]==32766&&ax[1]==32767&&ax[2]==-32767&&ax[3]==-32766);
 assert(magnitude(0)==0&&magnitude(NAN)==0&&magnitude(.5f)>0&&magnitude(1)==127);
 char file[]="/tmp/twin-map-test-XXXXXX";int fd=mkstemp(file);FILE*f=fdopen(fd,"w");for(int p=0;p<2;p++)for(int i=0;i<12;i++)fprintf(f,"%d ",tf_default[i]);fclose(f);int loaded[24];assert(tf_read_map(file,loaded,24));assert(!memcmp(loaded,tf_default,sizeof tf_default));f=fopen(file,"a");fputs("garbage",f);fclose(f);assert(!tf_read_map(file,loaded,24));unlink(file);
 printf("PASS: %d Player 2 HID combinations, player routing, malformed reports, axes, D-pad, rumble magnitude and strict config parser\n",checks);return 0;}
