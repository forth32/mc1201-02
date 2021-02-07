//
//  Файл конфигурации проекта МС1201-02.
//

// Тип процессорной платы
`define BOARD mc1201_02
//`define BOARD mc1201_01

//
//  Включаемые компоненты
//  Закомментируйте ненужные модули, если хотите исключить их из схемы.
//

`define KSM_module        // текстовый контроллер КСМ
`define KGD_module        // графический контроллер КГД
`define IRPS2_module      // второй последовательный порт ИРПС
`define IRPR_module       // параллельный порт ИРПР
`define RK_module         // диск RK-11/RK05
`define DW_module         // жесткий диск DW
`define DX_module         // гибкий диск RX01
`define MY_module         // гибкий диск двойной плотности MY

//  Индексы скорости последовательного порта:
//  0 - 1200
//  1 - 2400
//  2 - 4800
//  3 - 9600
//  4 - 19200
//  5 - 38400
//  6 - 57600
//  7 - 115200

// начальная скорость терминала
`define TERMINAL_SPEED 3'd5

// скорость второго последовательного интерфейса
`define UART2SPEED 3'd5

//------------------ конец списка настраиваемых параметров -------------------------------------------------------------

// удаление графического модуля при отсутствии текcтового терминала
`ifndef KSM_module
`undef KGD_module
`endif

// Выбор ведущего и ведомых SDSPI
`ifdef RK_module
  `define RK_sdmode 1'b1  
  `define MY_sdmode 1'b0
  `define DX_sdmode 1'b0
  `define DW_sdmode 1'b0
  `define def_mosi rk_mosi
  `define def_cs   rk_cs
  
`elsif MY_module
  `define MY_sdmode 1'b1
  `define RK_sdmode 1'b0  
  `define DX_sdmode 1'b0
  `define DW_sdmode 1'b0
  `define def_mosi my_mosi
  `define def_cs   my_cs

`elsif DX_module
  `define DX_sdmode 1'b1
  `define MY_sdmode 1'b0
  `define RK_sdmode 1'b0  
  `define DW_sdmode 1'b0
  `define def_mosi dx_mosi
  `define def_cs   dx_cs
  
`else
  `define DW_sdmode 1'b1
  `define DX_sdmode 1'b0
  `define MY_sdmode 1'b0
  `define RK_sdmode 1'b0  
  `define def_mosi dw_mosi
  `define def_cs   dw_cs
  
`endif  
  
  
  