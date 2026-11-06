#pragma once
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
static const int tf_default[12]={2,0,1,3,8,9,6,7,11,10,4,5};
// Strict parse: incomplete files, out-of-range entries and trailing junk never apply.
static int tf_read_map(const char *path, int *out, int count) {
 FILE *f=fopen(path,"r"); if(!f)return 0; int tmp[24],ok=1;
 for(int i=0;i<count;i++)if(fscanf(f,"%d",tmp+i)!=1||tmp[i]<-1||tmp[i]>11){ok=0;break;}
 int ch;while(ok&&(ch=fgetc(f))!=EOF)if(!isspace((unsigned char)ch))ok=0;
 fclose(f);if(ok)memcpy(out,tmp,count*sizeof(int));return ok;
}
static uint64_t tf_buttons(unsigned bits,const int *map){uint64_t m=0;for(int i=0;i<12;i++)if((bits&(1u<<i))&&map[i]>=0)m|=1ull<<map[i];return m;}
