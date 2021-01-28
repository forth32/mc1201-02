//  Включаемые компоненты

//`define KSM_module        // текстовый контроллер КСМ
`define KGD_module        // графический контроллер КГД
`define IRPS2_module      // второй последовательный порт ИРПС
`define IRPR_module       // параллельный порт ИРПР
`define RK_module         // диск RK-11/RK05
`define DW_module         // жесткий диск DW
`define DX_module         // гибкий диск RX01
`define MY_module         // гибкий диск двойной плотности MY


// начальная скорость терминала
//  0 - 1200
//  1 - 2400
//  2 - 4800
//  3 - 9600
//  4 - 19200
//  5 - 38400
//  6 - 57600
//  7 - 115200
`define TERMINAL_SPEED 3'd5

// скорость второго последовательного интерфейса
`define UART2SPEED 38400

// удаление графического модуля при отсутствии тектового терминала
`ifndef KSM_module
`undef KGD_module
`endif