#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#include <assert.h>
#include "mapping.h"
extern void tf_bind_profile(GCExtendedGamepad*,const int*);
static NSArray *sources(GCExtendedGamepad*g){return @[g.buttonY,g.buttonB,g.buttonA,g.buttonX,g.leftTrigger,g.rightTrigger,g.leftShoulder,g.rightShoulder,g.buttonOptions,g.buttonMenu,g.leftThumbstickButton,g.rightThumbstickButton];}
static uint64_t host_read(GCExtendedGamepad*g){return (g.buttonB.pressed?1:0)|(g.buttonA.pressed?2:0)|(g.buttonY.pressed?4:0)|(g.buttonX.pressed?8:0)|(g.leftThumbstickButton.pressed?16:0)|(g.rightThumbstickButton.pressed?32:0)|(g.leftShoulder.pressed?64:0)|(g.rightShoulder.pressed?128:0)|(g.leftTrigger.pressed?256:0)|(g.rightTrigger.pressed?512:0)|(g.buttonMenu.pressed?1024:0)|(g.buttonOptions.pressed?2048:0);}
int main(){@autoreleasepool{
 int cases=0;
 for(int mode=0;mode<4;mode++){
  GCController *c=[GCController controllerWithExtendedGamepad];GCExtendedGamepad*g=c.extendedGamepad;
  GCController *other=[GCController controllerWithExtendedGamepad];
  int map[12];memcpy(map,tf_default,sizeof map);
  if(mode==1){map[0]=1;map[2]=2;}
  if(mode==2)for(int i=0;i<12;i++)map[i]=11-i;
  if(mode==3){map[0]=-1;map[1]=1;map[2]=1;}
  NSArray *raw=sources(g);tf_bind_profile(g,map);
  // Exhaust all combinations, including simultaneous buttons and release.
  for(unsigned bits=0;bits<4096;bits++){
   for(int i=0;i<12;i++)[(GCControllerButtonInput*)raw[i] setValue:(bits>>i)&1];
   uint64_t want=tf_buttons(bits,map);assert(host_read(g)==want);cases++;
  }
  [other.extendedGamepad.buttonA setValue:1];assert(other.extendedGamepad.buttonA.pressed);assert(!other.extendedGamepad.buttonB.pressed);
  [g.dpad setValueForXAxis:0 yAxis:1];assert(g.dpad.up.pressed);[g.leftThumbstick.xAxis setValue:.75];assert(g.leftThumbstick.xAxis.value>.7);
 }
 printf("PASS: %d Player 1 button combinations; swaps, disabled/duplicate inputs, unrelated controllers, D-pad and axes\n",cases);
}return 0;}
