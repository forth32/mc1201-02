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
    {"DW", 0xc000,  131072},
    {"DX", 0x2c000,   4096},
    {0,0}
};   
