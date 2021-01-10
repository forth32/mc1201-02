// Размер одного полного банка в блоках
#define banksize 0x20000

struct devtable_t{
    char* name;       // имя устройства
    uint32_t doffset; // смещение от начала банка
    uint32_t usize;   // размер одного диска на карте
};

// Описатель структуры дискового банка
struct devtable_t devtable[] = {
    {"RK", 0,         6144},
    {"DW", 0xc000,   65536},
    {"DX", 0x1c000,   4096},
    {0,0}
};   
