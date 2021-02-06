//
//  Процессорный модуль - плата МС1201.02 (ДВК-3)
// 
// ======================================================================================

module mc1201_02 (
// Синхросигналы  
   input  clk_p,               // Положительный синхросигнал
   input  clk_n,               // Отрицательный синхросигнал
   input  cpuslow,             // Режим замедления процессора

// Шина Wishbone                                       
   input  cpu_gnt_i,           // 1 - разрешение cpu работать с шиной
                               // 0 - DMA с внешними устройствами, cpu отключен от шины и бесконечно ждет ответа wb_ack
   output [15:0] cpu_adr_o,    // выход шины адреса
   output [15:0] cpu_dat_o,    // выход шины данных
   input  [15:0] cpu_dat_i,    // вход шины данных
   output cpu_cyc_o,           // Строб цила wishbone
   output cpu_we_o,            // разрешение записи
   output [1:0] cpu_sel_o,     // выбор байтов для передачи
   output cpu_stb_o,           // строб данных

   output sysram_stb,          // строб обращения к системной памяти
   input  global_ack,          // подтверждение обмена от памяти и устройств страницы ввода-вывода
   
// Сбросы и прерывания
   output vm_init,             // Выход сброса для периферии
   input  dclo,                // Вход сброса процессора
   input  aclo,                // Сигнал аварии питания
   input  halt,                // Прерывание входа в пультовоый режим
   input  virq,                // Векторное прерывание

// Шины обработки прерываний                                       
   input  [15:0] ivec,         // Шина приема вектора прерывания
   output istb,                // Строб приема вектора прерывания
   input  iack,                // Подтверждение приема вектора прерывания

	input  timer_50,            // Сигнал таймерного прерывания 50 Гц
	input  timer_button,        // кнопка включения-отключения таймера
	output reg timer_status     // линия индикатора состояния таймера
);


// Стартовый регистр
wire [15:0] startup_reg = 16'o140001;

wire cpu_ack;
wire [15:0] local_dat_i;
wire [16:0] full_adr;
wire local_cyc;
wire una;
wire [15:0] vector;
assign cpu_cyc_o=local_cyc & (~full_adr[16]);

assign cpu_adr_o=full_adr[15:0];
assign vector=(una)? startup_reg : ivec ;

reg una_iack;
reg una_irq;
always @ (posedge clk_p) begin
  if (vm_init == 1'b1) begin
		una_iack <= 1'b0;
		una_irq <= 1'b0;
  end		
  else  begin
    una_iack <= istb & una & ~una_iack;
    una_irq <= una;
  end 
end

//*************************************
//*  Процессор К1801ВМ2
//*************************************

// счетчик замедления процессора
reg [4:0] cpudelay;

always @ (posedge clk_p) begin
    if (cpudelay != 5'd21) cpudelay <= cpudelay + 1'b1;  // считаем от 0 до 22
    else cpudelay <= 5'd0;
end    
wire cpu_clk_enable=~(|cpudelay);  // формирователь импульса с заполнением 1/21

vm2_wb #(.VM2_CORE_FIX_PREFETCH(0)) cpu
(
// Синхросигналы  
   .vm_clk_p(clk_p),                // Положительный синхросигнал
   .vm_clk_n(clk_n),                // Отрицательный синхросигнал
   .vm_clk_slow(cpuslow),           // Режим замедления процессора - определяется переключателем 3
   .vm_clk_ena(cpu_clk_enable),     // счетчик замедления

// Шина Wishbone                                       
   .wbm_gnt_i(cpu_gnt_i),           // 1 - разрешение cpu работать с шиной
                                    // 0 - DMA с внешними устройствами, cpu отключен от шины и бесконечно ждет ответа wb_ack
   .wbm_adr_o(full_adr),            // выход шины адреса
   .wbm_dat_o(cpu_dat_o),           // выход шины данных
   .wbm_dat_i(local_dat_i),         // вход шины данных
   .wbm_cyc_o(local_cyc),           // Строб цила wishbone
   .wbm_we_o(cpu_we_o),             // разрешение записи
   .wbm_sel_o(cpu_sel_o),           // выбор байтов для передачи
   .wbm_stb_o(cpu_stb_o),           // строб данных
   .wbm_ack_i(cpu_ack),             // вход подтверждения данных

// Сбросы и прерывания
   .vm_init(vm_init),               // Выход сброса для периферии
   .vm_dclo(dclo),                  // Вход сброса процессора
   .vm_aclo(aclo),                  // Сигнал аварии питания
   .vm_halt(halt),                  // Прерывание входа в пультовоый режим
   .vm_evnt(timer_50&timer_status), // Прерывание от таймера 
   .vm_virq(virq|una_irq),          // Векторное прерывание

// Шины обработки прерываний                                       
   .wbi_dat_i(vector),              // Шина приема вектора прерывания
   .wbi_stb_o(istb),                // Строб приема вектора прерывания
   .wbi_ack_i(iack|una_iack),       // Подтверждение приема вектора прерывания
   .wbi_una_o(una)                  // Строб безадресного чтения
);

//******************************************************************
//* Модуль ROM с монитором 1201-055/276
//******************************************************************
wire [15:0] rom_dat;
wire rom_stb;
wire rom_ack;

rom_monitor rom(
   .wb_clk_i(clk_p),
   .adr_i(full_adr[12:1]),
   .wb_dat_o(rom_dat),
   .wb_cyc_i(local_cyc),
   .wb_stb_i(rom_stb),
   .wb_ack_o(rom_ack)
);

// Размещение ROM с монитором 055/279 в теневой области с адреса 140000         
assign rom_stb = cpu_stb_o & local_cyc & (full_adr[16:13] == 4'b1110);

// Размещение системной теневой памяти :  160000 - 177776 - в режиме пульта
assign sysram_stb = cpu_stb_o & local_cyc & (full_adr[16:13] == 4'b1111);

// Сигнал подтвреждения обмена - от общей шины и модуля ROM
assign cpu_ack = global_ack | rom_ack;

// мультиплексор входной шины данных - подключается к общей шине или к ROM
assign local_dat_i = (rom_stb   ? rom_dat   : cpu_dat_i);

//**********************************
//* Сигнал разрешения таймера
//**********************************
initial timer_status=1;  // после подачи питания таймер включен
reg [1:0] tbshift;
reg tbevent;

// подавление дребезга кнопки
always @ (posedge timer_50) begin
  // вводим кнопку в сдвиговый регистр
  tbshift[0] <= timer_button;
  tbshift[1] <= tbshift[0];
  // регистр заполнен - кнопка стабильно нажата
  if (&tbshift == 1'b1) begin
      if (tbevent == 1'b0) begin
        timer_status <= ~timer_status;  // переключаем состояние таймера
        tbevent <= 1'b1;                              // запрещаем дальнейшие изменения состояния таймиера
      end
  end
  // регистр очищен - кнопка стабильно отпущена
  else if (|tbshift == 1'b0) tbevent <= 1'b0;     // разрешаем изменения состояния таймера
end  

endmodule
