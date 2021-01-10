#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include "devtable.h"

void main(int argc, char* argv[]) {
    

FILE* card;
FILE* in;

char devname[100];
char* buf;
int bank=0,unit=0;
char filename[100];
int i;
uint32_t boffset, doffset, usize, cardoffset;
char DD[4];
char* outbuf;    
int cyl;
int sec;
int adr;
int pblock=0;

if (argc < 5) {
    printf("Запись образа диска на SD-карту\n\
Формат командной строки:\n\
%s DEV TYPE unit bank [file]\n\n\
DEV   - имя устройства SD-карты, например /dev/sdd\n\
TYPE  - тим диска, RK, DW, DX\n\
unit  - номер устройства для многодисковых устройств (для однодисковых - 0)\n\
bank  - номер банка дисков\n\
file  - имя файла для записи извлекаемого образа, по умолчанию B#-DD#.DSK\n\n\
 Пример: %s /dev/sdc RK 2 1 rt11.dsk - запись образа RK2: в банк 1\n\n",argv[0],argv[0]);
    return;
}

DD[0]=toupper((argv[2][0]));
DD[1]=toupper((argv[2][1]));
DD[3]=0;

// поиск устройства
for(i=0;;i++) {
    if (devtable[i].name == 0) {
        printf("Неверный тип устройства - %s",DD);
        return;
    }
    if (strncmp(DD,devtable[i].name,2) == 0) {
         doffset=devtable[i].doffset;
         usize=devtable[i].usize;
         break;
    }     
}
unit=atoi(argv[3]);
bank=atoi(argv[4]);                      
if (argc>5) strcpy(filename,argv[5]);
else sprintf(filename,"B%i-%s%i.dsk",bank,devtable[i].name,unit);

in=fopen(filename,"r");
if (in == 0) {
    printf("- ошибка открытия входного файла %s\n",filename);
    return;
}
card=fopen(argv[1],"w");
if (card == 0) {
    printf("- ошибка открытия SD-карты %s\n",argv[1]);
    return;
}

buf=malloc(usize*512);
if (buf == 0) {
    printf("- недостаточно памяти под буфер\n");
    return;
}

if (strncmp(DD,"DX",2) != 0)  fread(buf,512,usize,in);
else {
    // преобразование буфера для DX-дисков
    fread(buf,512,502,in);
    outbuf=malloc(4096*512);
    if (outbuf == 0) {
        printf("- недостаточно памяти под буфер\n");
        return;
    }
    memset(outbuf,0,4096*512);
    for (cyl=0;cyl<77;cyl++) {
        for(sec=1;sec<27;sec++) {
            adr=((cyl<<5) + sec)*512;
            for(i=0;i<128;i++) *(outbuf+adr+i*2)=buf[pblock+i];
            pblock+=128;
        }
    }
    free(buf);
    buf=outbuf;  // подставляем преобразованный буфер на место исходного
}
fclose(in);

// Запись образа на карту
cardoffset=bank*banksize+doffset+unit*usize;
printf("* Стартовый блок: %xh\n",cardoffset);
fseek(card,(cardoffset)*512,SEEK_SET);
fwrite(buf,512,usize,card);
fclose(card);
free(buf);
}
