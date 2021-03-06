//
//  Процессорный модуль - плата МС1260 (Электроника-60)
//  Центральный процессор - М2 (LSI-11)
// 
// ======================================================================================

module mc1260 (
// Синхросигналы  
   input  clk50,               // входная тактовая частота платы - 50 МГц
   output busclk,              // Основной синхросигнал общей шины
   output sdclk,               // Синхросигнал SD-карты
   output clkrdy,              // сигнал готовности тактового генератора
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

// Таймер
   input  timer_button,        // кнопка включения-отключения таймера
   output reg timer_status     // линия индикатора состояния таймера
);

// синхросигналы 
wire clk_p;
wire clk_n;
// Системной памяти здесь нет
assign sysram_stb=1'b0;

//************************************************
//* тактовый генератор 
//************************************************
assign busclk  = clk_p;   // тактовая частота шины wishbone

pll100 corepll
(
   .inclk0(clk50),
   .c0(clk_p),     // 100МГц прямая фаза, основная тактовая частота
   .c1(clk_n),     // 100МГц инверсная фаза
   .c2(sdclk),     // 12.5 МГц тактовый сигнал SD-карты
   .locked(clkrdy) // флаг готовности PLL
);

//*************************************
// счетчик замедления процессора
//*************************************
reg [4:0] cpudelay;
reg cpu_clk_enable;

always @ (posedge clk_p) begin
    if (cpudelay != 5'd21) begin
        cpudelay <= cpudelay + 1'b1;  // считаем от 0 до 22
        cpu_clk_enable <= 1'b0;
    end     
    else begin
        cpudelay <= 5'd0;
        cpu_clk_enable <= 1'b1;
    end     
end    

//*************************************
//*  Процессор LSI-11 (M2)
//*************************************
lsi_wb cpu
(
// Синхросигналы  
   .vm_clk_p(clk_p),                // Положительный синхросигнал
   .vm_clk_n(clk_n),                // Отрицательный синхросигнал
   .vm_clk_slow(cpuslow),           // Режим замедления процессора - определяется переключателем 3
   .vm_clk_ena(cpu_clk_enable),     // счетчик замедления

// Шина Wishbone                                       
   .wbm_gnt_i(cpu_gnt_i),           // 1 - разрешение cpu работать с шиной
                                    // 0 - DMA с внешними устройствами, cpu отключен от шины и бесконечно ждет ответа wb_ack
   .wbm_adr_o(cpu_adr_o),           // выход шины адреса
   .wbm_dat_o(cpu_dat_o),           // выход шины данных
   .wbm_dat_i(cpu_dat_i),           // вход шины данных
   .wbm_cyc_o(cpu_cyc_o),           // Строб цила wishbone
   .wbm_we_o(cpu_we_o),             // разрешение записи
   .wbm_sel_o(cpu_sel_o),           // выбор байтов для передачи
   .wbm_stb_o(cpu_stb_o),           // строб данных
   .wbm_ack_i(global_ack),             // вход подтверждения данных

// Сбросы и прерывания
   .vm_init(vm_init),               // Выход сброса для периферии
   .vm_dclo(dclo),                  // Вход сброса процессора
   .vm_aclo(aclo),                  // Сигнал аварии питания
   .vm_halt(halt),                  // Прерывание входа в пультовоый режим
   .vm_evnt(timer_50&timer_status), // Прерывание от таймера 
   .vm_virq(virq),                  // Векторное прерывание

// Шины обработки прерываний                                       
   .wbi_dat_i(ivec),                // Шина приема вектора прерывания
   .wbi_stb_o(istb),                // Строб приема вектора прерывания
   .wbi_ack_i(iack),                // Подтверждение приема вектора прерывания

// Режим начального пуска
//     00 - start reserved MicROM
//     01 - start from 173000
//     10 - break into ODT
//     11 - load vector 24
   .vm_bsel(2'b10)
);

//*************************************************************************
//* Генератор прерываний от таймера
//* Сигнал имеет частоту 50 Гц и  коэффициент заполнения 1/2000000
//*************************************************************************
reg timer_50;
reg [21:0] timercnt;

always @ (posedge clk_p) begin
  if (timercnt == 21'd1999999) begin
     timercnt <= 21'd0;
     timer_50 <= 1'b1;
  end  
  else begin
     timercnt <= timercnt + 1'b1;
     timer_50 <= 1'b0;
  end     
end

//**********************************
//* Сигнал разрешения таймера
//**********************************
reg [1:0] tbshift;
reg tbevent;

// подавление дребезга кнопки
always @ (posedge timer_50) begin
  // отключение таймера по сбросу
  if (dclo) timer_status <= 1'b0;
  else begin
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
end  

endmodule
