//
// FPGA версия платы МС1201.02
//
//================================================================================
//
`timescale 1ns / 100ps

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

//***********************************
//*        Головной модуль          *
//***********************************
module mc1201_02 (

   input          clk50,         // clock input 50 MHz
   input    [3:0] button,        // кнопки 
   input    [3:0] sw,            // переключатели конфигурации
	
	// Интерфейс SDRAM
	inout	 [15:0]	DRAM_DQ,				   //	SDRAM Data bus 16 Bits
	output [12:0]	DRAM_ADDR,				//	SDRAM Address bus 12 Bits
	output			DRAM_LDQM,				//	SDRAM Low-byte Data Mask 
	output			DRAM_UDQM,				//	SDRAM High-byte Data Mask
	output			DRAM_WE_N,				//	SDRAM Write Enable
	output			DRAM_CAS_N,				//	SDRAM Column Address Strobe
	output			DRAM_RAS_N,				//	SDRAM Row Address Strobe
	output			DRAM_CS_N,				//	SDRAM Chip Select
	output			DRAM_BA_0,				//	SDRAM Bank Address 0
	output			DRAM_BA_1,				//	SDRAM Bank Address 0
	output			DRAM_CLK,				//	SDRAM Clock
	output			DRAM_CKE,				//	SDRAM Clock Enable

	// интерфейс SD-карты
   output         sdcard_cs, 
   output         sdcard_mosi, 
   output         sdcard_sclk, 
   input          sdcard_miso, 

   // индикаторные светодиоды	
   output [3:0]	led,                                  
	
	// VGA
	output vgah, 			// горизонтальная синхронизация
   output vgav, 			// вертикакльная синхронизация
   output [4:0]vgar, 	// красный видеосигнал
   output [5:0]vgag,    // зеленый видеосигнал
   output [4:0]vgab,    // синий видеосигнал

   // PS/2
   input ps2_clk, 
   input ps2_data,
	
   // пищалка 	
	output buzzer, 
	 
	// дополнительный UART 
   output         irps_txd,
   input          irps_rxd,
	
	// LPT
	output [7:0]         lp_data,    // данные для передачи к принтеру
	output               lp_stb_n,   // строб записи в принтер
	output               lp_init_n,  // строб сброса
	input                lp_busy,    // сигнал занятости принтера
	input                lp_err_n    // сигнал ошибки
	
);

wire [2:0] vspeed;   // индекс скорости порта

// Стартовый регистр
wire [15:0] startup_reg = 16'o140001;

wire        sys_clk_p;                 
wire        sys_clk_n;                 
wire        sys_init;                  // общий сброс
wire        sys_plock;                 // готовность PLL
wire        i50Hz;                     // выходы интервального таймера
wire        terminal_rst;

// шина WISHBONE                                       
wire        wb_clk;                    
wire [16:0] wb_adr;                    
wire [15:0] wb_out;                    
wire [15:0] wb_mux;                    
wire        wb_cyc;                    
wire        wb_we;                     
wire [1:0]  wb_sel;                    
wire        wb_stb;                    
wire        wb_ack;                    

// Основная шина процессора
wire        cpu_access_req;            // разрешение доступа к шине
wire [16:0]	cpu_adr;							// шина адреса
wire [15:0] cpu_data_out; 					// выход шины данных
wire			cpu_cyc;							// строб транзакции
wire			cpu_we;							// направление передачи (1 - от процессора)
wire [1:0]	cpu_bsel;						// выбор байтов из слова
wire			cpu_stb;							// строб обмена по шине
wire 	      cpu_ack;							// подтверждение транзакции

// шина векторов прерываний                                       
wire        vm_una;                   	// запрос безадресного чтения
wire        vm_istb;                   // Строб приема вектора прерывания 
wire        vm_iack;                   // подтверждение прерывания
wire [15:0] vm_ivec;                   // вектор прерывания

// сигналы выбора периферии
wire cpu_dev_stb;							
wire uart1_stb;
wire uart2_stb;
wire rom_stb;
wire bootrom_stb;
wire dram_stb;
wire rk11_stb;
wire lpt_stb;
wire dw_stb;
wire rx_stb;

// линии подтверждения обмена
wire cpu_dev_ack;
wire uart1_ack;
wire uart2_ack;
wire rom_ack;
wire bootrom_ack;
wire dram_ack;
wire rk11_ack;
wire lpt_ack;
wire dw_ack;
wire rx_ack;
wire rk11_dma_ack;

//  Шины данных от периферии
wire [15:0] uart1_dat;
wire [15:0] uart2_dat;
wire [15:0] dram_dat;
wire [15:0] rom_dat;
wire [15:0] bootrom_dat;
wire [15:0] rk11_dat;
wire [15:0] lpt_dat;
wire [15:0] dw_dat;
wire [15:0] rx_dat;

// флаг готовности динамической памяти.
wire 			dr_ready;									
                                       
wire        vm_init_out;               // выход сброса от прецессора к устройствам на шине
wire        vm_dclo_in;                // вход сброса
wire        vm_aclo_in;                // прерывание по аварии питания
wire        vm_virq;                   // запрос векторного прерывания
wire        vm_halt;                   // пультовое прерывание
wire        timer_irq;                 

// линии прерывания внешних устройств                                       
wire        irpstx_irq, irpstx_iack;            
wire        irpsrx_irq, irpsrx_iack;            
wire        irpstx2_irq, irpstx2_iack;            
wire        irpsrx2_irq, irpsrx2_iack;            
wire        rk11_irq, rk11_iack;
wire        lpt_irq, lpt_iack;
wire        dw_irq, dw_iack;
wire        rx_irq, rx_iack;

wire 			global_reset;   // кнопка сброса
wire			console_switch; // кнопка "пульт"
wire 			timer_switch; 	 // выключатель таймерного прерывания
wire 			reset_key;      // кнопка сброса

// Линии обмена с SD-картой от разных контроллеров
wire 			sdclock;        // тактирование SD-карты
wire			rk_mosi;			 // mosi от RK11
wire			rk_cs;			 // cs от RK11
wire			dw_mosi;			 // mosi от DW
wire			dw_cs;			 // cs от DW
wire			dx_mosi;			 // mosi от DW
wire			dx_cs;			 // cs от DW
// Сигналы диспетчера доступа к SD-карте
wire 			rk_sdreq;       // запрос доступа
reg			rk_sdack;		 // разрешение доступа
wire 			dw_sdreq;
reg			dw_sdack; 
wire 			dx_sdreq;
reg			dx_sdack; 

reg 			timer_on;		 // разрешение таймера

 
assign      sys_init = vm_init_out;
assign      vm_halt  = console_switch;
assign      timer_irq  = i50Hz & timer_on;   // сигнал прерывания от таймера с маской разрешения

// VGA
wire vgared,vgagreen,vgablue;
// выбор яркости каждого цвета - сигнал, подаваемый на видео-ЦАП для светящейся и темной точки.	
assign vgag = (vgagreen == 1'b1) ? 6'b101111 : 6'b000000 ;
assign vgab = (vgablue == 1'b1) ? 5'b11111 : 5'b00000 ;
assign vgar = (vgared == 1'b1) ? 5'b11111 : 5'b00000 ;

// пищалка
wire nbuzzer;
assign buzzer=~nbuzzer;

assign sdcard_sclk=sdclock;

//***************************************************
//*    Кнопки
//***************************************************
assign		reset_key=button[0];    // кнопка сброса
assign		console_switch=~button[1]; // кнопка "пульт"
assign		terminal_rst=~button[2] | ~sys_plock;  // сброс терминального модуля - от кнопки и автоматически по готовности PLL
assign		timer_switch=~button[3];	// выключатель таймерного прерывания
 
//********************************************
//* Светодиоды
//********************************************
assign led[0] = ~rk_sdreq;   // запрос обмена диска RK
assign led[1] = ~dw_sdreq;   // запрос обмена диска DW
assign led[2] = ~dx_sdreq;   // запрос обмена диска DX
assign led[3] = ~timer_on;   // индикация включения таймера

//************************************************
//* тактовый генератор 
//************************************************
assign wb_clk  = sys_clk_p;

pll100 corepll
(
   .inclk0(clk50),
   .c0(sys_clk_p), // 100МГц прямая фаза, основная тактовая частота
   .c1(sys_clk_n), // 100МГц инверсная фаза
	.c2(sdclock),   // 12.5 МГц тактовый сигнал SD-карты
   .locked(sys_plock)  // флаг готовности PLL
);

//**************************************************************
//*   Моудль формирования сбросов и сетевой таймер KW11L
//**************************************************************

wbc_rst reset
(
   .osc_clk(clk50),          // основной клок 50 МГц
   .sys_clk(wb_clk),         // сигнал синхронизации  wishbone
   .pll_lock(sys_plock),     // сигнал готовности PLL
   .button(reset_key),    	  // кнопка сброса
   .sys_ready(dr_ready),     // вход готовности системных компонентов (влияет на sys_rst)
   .sys_dclo(vm_dclo_in),   
   .sys_aclo(vm_aclo_in),
	.global_reset(global_reset),    // выход кнопки сброса 
   .sys_irq(i50Hz)          // сигнал прерывания KW11L с частотой 50 Гц.
);

//*************************************
//*  Процессор К1801ВМ2
//*************************************
vm2_wb #(.VM2_CORE_FIX_PREFETCH(0)) cpu
(
// Синхросигналы  
   .vm_clk_p(sys_clk_p),               // Положительный синхросигнал
   .vm_clk_n(sys_clk_n),               // Отрицательный синхросигнал
   .vm_clk_slow(1'b0),                 // Режим медленной синхронизации (для симуляции)

// Шина Wishbone                                       
	.wbm_gnt_i(cpu_access_req),			// 1 - разрешение cpu работать с шиной
	                                    // 0 - DMA с внешними устройствами, cpu отключен от шины и бесконечно ждет ответа wb_ack
	.wbm_adr_o(cpu_adr),						// выход шины адреса
	.wbm_dat_o(cpu_data_out),				// выход шины данных
   .wbm_dat_i(wb_mux),     				// вход шины данных
	.wbm_cyc_o(cpu_cyc),						// Строб цила wishbone
	.wbm_we_o(cpu_we),						// разрешение записи
	.wbm_sel_o(cpu_bsel),					// выбор байтов для передачи
	.wbm_stb_o(cpu_stb),						// строб данных
	.wbm_ack_i(cpu_ack),						// вход подтверждения данных

// Сбросы и прерывания
   .vm_init(vm_init_out),              // Выход сброса для периферии
   .vm_dclo(vm_dclo_in),               // Вход сброса процессора
   .vm_aclo(vm_aclo_in),               // Сигнал аварии питания
   .vm_halt(vm_halt),                  // Прерывание входа в пультовоый режим
   .vm_evnt(timer_irq),                // Прерывание от таймера KW11L
   .vm_virq(vm_virq),                  // Векторное прерывание

// Шины обработки прерываний                                       
   .wbi_dat_i(vm_ivec),                // Шина приема вектора прерывания
   .wbi_stb_o(vm_istb),                // Строб приема вектора прерывания
   .wbi_ack_i(vm_iack),                // Подтверждение приема вектора прерывания

   .wbi_una_o(vm_una)                  // Строб безадресного чтения
);

//******************************************************************
//* Модуль ROM с монитором 1201-055/276
//******************************************************************
rom_monitor rom(
	.wb_clk_i(wb_clk),
	.adr_i(wb_adr[12:1]),
   .wb_dat_o(rom_dat),
	.wb_cyc_i(wb_cyc),
	.wb_stb_i(rom_stb),
	.wb_ack_o(rom_ack)
);

//**********************************
//* Модуль динамической памяти
//**********************************

reg [1:0] dreset;
reg [2:0] dr_cnt;
reg drs;

// формирователь сброса
always @(posedge wb_clk)
begin
	dreset[0] <= global_reset; // 1 - сброс
	dreset[1] <= dreset[0];
	if (dreset[1] == 1) begin
	  drs<=0;
	  dr_cnt<=2'b0;
	end  
	else 
	  if (dr_cnt != 2'd3) dr_cnt<=dr_cnt+1'b1;
	  else drs<=1'b1;
end

// стробы чтения-записи
wire dram_wr=wb_we & dram_stb;
wire dram_rd=(~wb_we) & dram_stb;

// стробы подтверждения
wire sdr_wr_ack,sdr_rd_ack;
// тактовый сигнал на память
assign DRAM_CLK=sys_clk_n;

// Сигналы выбора старших-младших байтов
reg dram_h,dram_l;

always @ (posedge dram_stb) begin
  if (wb_we == 0) begin
   // чтение - всегда словное
   dram_h<=1'b0;
   dram_l<=1'b0;
  end
  else begin
   // определение записываемых байтов
   dram_h<=~wb_sel[1];  // старший
   dram_l<=~wb_sel[0];  // младший
  end
end  

assign DRAM_UDQM=dram_h; 
assign DRAM_LDQM=dram_l; 

sdram_top sdram(
				.clk(wb_clk),
				.rst_n(drs), // запускаем модуль, как только pll выйдет в рабочий режим, запуска процессора не ждем
				.sdram_wr_req(dram_wr),
				.sdram_rd_req(dram_rd),
				.sdram_wr_ack(sdr_wr_ack),
				.sdram_rd_ack(sdr_rd_ack),
				.sdram_byteenable(wb_sel),
				.sys_wraddr({8'b0000000,wb_adr[15:1]}),
				.sys_rdaddr({8'b0000000,wb_adr[15:1]}),
				.sys_data_in(wb_out),
				.sys_data_out(dram_dat),
				.sdwr_byte(1),
				.sdrd_byte(4),
				.sdram_cke(DRAM_CKE),
				.sdram_cs_n(DRAM_CS_N),
				.sdram_ras_n(DRAM_RAS_N),
				.sdram_cas_n(DRAM_CAS_N),
				.sdram_we_n(DRAM_WE_N),
				.sdram_ba({DRAM_BA_1,DRAM_BA_0}),
				.sdram_addr(DRAM_ADDR[12:0]),
				.sdram_data(DRAM_DQ),
				.sdram_init_done(dr_ready)
			);
			
// формирователь сигнала подверждения транзакции
reg [1:0]dack;

assign dram_ack = wb_cyc & dram_stb & (dack[1]);
// задержка сигнала подтверждения на 1 такт clk
always @ (posedge wb_clk)  begin
	dack[0] <= wb_cyc & dram_stb & (sdr_rd_ack | sdr_wr_ack);
	dack[1] <= wb_cyc & dack[0];
end

//**********************************
// Выбор консольного порта
//**********************************
wire 			console_selector;  	  // флаг выбора консольного порта, 0 - терминальный модуль, 1 - ИРПС 2
wire 			uart1_txd, uart1_rxd;  // линии ИРПС 1
wire			uart2_txd, uart2_rxd;  // линии ИРПС 2
wire 			terminal_tx,terminal_rx; // линии аппаратного терминала
assign console_selector=sw[2];    // выбор определяется переключателем 2
assign irps_txd = (console_selector == 0)? uart2_txd : uart1_txd;
assign terminal_rx = (console_selector == 0)? uart1_txd : uart2_txd;
assign uart1_rxd = (console_selector == 0)? terminal_tx : irps_rxd;
assign uart2_rxd = (console_selector == 0)? irps_rxd : terminal_tx;

// Выбор скорости последовательных портов
wire [31:0] uart1_speed;  // скорость ИРПС 1
wire [31:0] uart2_speed;  // скорость ИРПС 2
// Согласование скорости с терминальным модулем
wire [31:0]	terminal_baud;	 // делитель, соответствующий текущей скорости терминала							
assign  terminal_baud = 
  (vspeed == 3'd0)   ? 32'd767: // 1200
  (vspeed == 3'd1)   ? 32'd383: // 2400
  (vspeed == 3'd2)   ? 32'd191: // 4800
  (vspeed == 3'd3)   ? 32'd95:  // 9600
  (vspeed == 3'd4)  ?  32'd47:  // 19200
  (vspeed == 3'd5)  ?  32'd23:  // 38400
  (vspeed == 3'd6)  ?  32'd15:  // 57600
                    32'd7;  // 115200
// делитель скорости второго порта ИРПС
wire [31:0] baud2; 
assign  baud2 = 921600/`UART2SPEED-1;
// Селектор делителей скорости обоих портов в зависимости от того, кто из них подключен к терминалу
assign uart1_speed = (console_selector == 0)? terminal_baud : baud2;
assign uart2_speed = (console_selector == 0)? baud2 : terminal_baud;

//**********************************
//*     ирпс1 (консоль)
//**********************************
wbc_uart uart
(
   .wb_clk_i(wb_clk),
   .wb_rst_i(sys_init),
   .wb_adr_i(wb_adr[2:0]),
   .wb_dat_i(wb_out),
   .wb_dat_o(uart1_dat),
   .wb_cyc_i(wb_cyc),
   .wb_we_i(wb_we),
   .wb_stb_i(uart1_stb),
   .wb_ack_o(uart1_ack),

   .tx_dat_o(uart1_txd),
   .rx_dat_i(uart1_rxd),

   .tx_cts_i(1'b0),
   .tx_irq_o(irpstx_irq),
   .tx_ack_i(irpstx_iack),
   .rx_irq_o(irpsrx_irq),
   .rx_ack_i(irpsrx_iack),

   .cfg_bdiv(uart1_speed),
   .cfg_nbit(2'b11),
   .cfg_nstp(1'b1),
   .cfg_pena(1'b0),
   .cfg_podd(1'b0)
);

//**********************************
//*     ирпс2
//**********************************
wbc_uart uart2
(
	.wb_clk_i(wb_clk),
	.wb_rst_i(sys_init),
	.wb_adr_i(wb_adr[2:0]),
	.wb_dat_i(wb_out),
   .wb_dat_o(uart2_dat),
	.wb_cyc_i(wb_cyc),
	.wb_we_i(wb_we),
	.wb_stb_i(uart2_stb),
	.wb_ack_o(uart2_ack),

	.tx_cts_i(1'b0),
   .tx_dat_o(uart2_txd),
   .rx_dat_i(uart2_rxd),

	.tx_irq_o(irpstx2_irq),
	.tx_ack_i(irpstx2_iack),
	.rx_irq_o(irpsrx2_irq),
	.rx_ack_i(irpsrx2_iack),

	.cfg_bdiv(uart2_speed),
	.cfg_nbit(2'b11),
	.cfg_nstp(1'b1),
	.cfg_pena(1'b0),
	.cfg_podd(1'b0)
);

//**********************************
//*   Терминал VT52
//**********************************

vt52 terminal(
   .vgahs(vgah), 
   .vgavs(vgav), 
	.vgared(vgared),
	.vgagreen(vgagreen),
	.vgablue(vgablue),
   .tx(terminal_tx), 
   .rx(terminal_rx), 
   .ps2_clk(ps2_clk), 
   .ps2_data(ps2_data), 
	.buzzer(nbuzzer),
	.vspeed(vspeed),
	.initspeed(`TERMINAL_SPEED),
   .clk50(clk50), 
   .reset(terminal_rst)
);

//**********************************
//*  ИРПР
//**********************************
irpr printer (
	.wb_clk_i(wb_clk),
	.wb_rst_i(sys_init),
	.wb_adr_i(wb_adr[1:0]),
	.wb_dat_i(wb_out),
   .wb_dat_o(lpt_dat),
	.wb_cyc_i(wb_cyc),
	.wb_we_i(wb_we),
	.wb_stb_i(lpt_stb),
	.wb_ack_o(lpt_ack),
   .irq(lpt_irq),
   .iack(lpt_iack),
	// интерфейс к принтеру
	.lp_data(lp_data),    // данные для передачи к принтеру
	.lp_stb_n(lp_stb_n),   // строб записи в принтер
	.lp_init_n(lp_init_n),  // строб сброса
	.lp_busy(lp_busy),    // сигнал занятости принтера
	.lp_err_n(lp_err_n)    // сигнал ошибки
);

//****************************************************
//*  Дисковый контроллер RK11D
//****************************************************

// Сигналы запроса-подтверждения DMA
wire rk11_dma_req;
wire rk11_dma_gnt;

// выходная шина DMA
wire [15:0]	rk11_adr;							
wire			rk11_dma_stb;
wire			rk11_dma_we;
wire [15:0] rk11_dma_out;

wire [3:0] sddebug;


rk11 rkdisk (

// шина wishbone
   .wb_clk_i(wb_clk),	// тактовая частота шины
	.wb_rst_i(sys_init),	// сброс
	.wb_adr_i(wb_adr[3:0]),	// адрес 
	.wb_dat_i(wb_out),	// входные данные
   .wb_dat_o(rk11_dat),	// выходные данные
	.wb_cyc_i(wb_cyc),   // начало цикла шины
	.wb_we_i(wb_we),		// разрешение записи (0 - чтение)
	.wb_stb_i(rk11_stb),	// строб цикла шины
	.wb_sel_i(wb_sel),   // выбор конкретных байтов для записи - старший, младший или оба
	.wb_ack_o(rk11_ack),	// подтверждение выбора устройства

// обработка прерывания	
	.irq(rk11_irq),      // запрос
	.iack(rk11_iack),    	// подтверждение
	
// DMA
   .dma_req(rk11_dma_req),    // запрос DMA
   .dma_gnt(rk11_dma_gnt),    // подтверждение DMA
   .dma_adr_o(rk11_adr),      // выходной адрес при DMA-обмене
   .dma_dat_i(wb_mux),        // входная шина данных DMA
   .dma_dat_o(rk11_dma_out),        // выходная шина данных DMA
	.dma_stb_o(rk11_dma_stb),  // строб цикла шины DMA
	.dma_we_o(rk11_dma_we),          // направление передачи DMA (0 - память->диск, 1 - диск->память) 
   .dma_ack_i(rk11_dma_ack),        // Ответ от устройства, с которым идет DMA-обмен
	
// интерфейс SD-карты
   .sdcard_cs(rk_cs), 
   .sdcard_mosi(rk_mosi), 
   .sdcard_miso(sdcard_miso), 

	.sdclock(sdclock),
	.sdreq(rk_sdreq),
	.sdack(rk_sdack),
	
// Адрес массива дисков на карте
	.start_offset({2'b00,sw[1:0],18'h0}),

// отладочные сигналы
   .sdcard_debug(sddebug)
	); 
  
//**********************************
//*   Дисковый контроллер DW
//**********************************
wire [3:0] dwsddebug;

dw hdd(
// шина wishbone
   .wb_clk_i(wb_clk),	// тактовая частота шины
	.wb_rst_i(sys_init),	// сброс
	.wb_adr_i(wb_adr[4:0]),	// адрес 
	.wb_dat_i(wb_out),	// входные данные
   .wb_dat_o(dw_dat),	// выходные данные
	.wb_cyc_i(wb_cyc),   // начало цикла шины
	.wb_we_i(wb_we),		// разрешение записи (0 - чтение)
	.wb_stb_i(dw_stb),	// строб цикла шины
	.wb_sel_i(wb_sel),   // выбор конкретных байтов для записи - старший, младший или оба
	.wb_ack_o(dw_ack),	// подтверждение выбора устройства

// обработка прерывания	
	.irq(dw_irq),      // запрос
	.iack(dw_iack),    // подтверждение
	
	
// интерфейс SD-карты
   .sdcard_cs(dw_cs), 
   .sdcard_mosi(dw_mosi), 
   .sdcard_miso(sdcard_miso), 
	.sdclock(sdclock),
	.sdreq(dw_sdreq),
	.sdack(dw_sdack),

// Адрес массива дисков на карте
	.start_offset({2'b00,sw[1:0],18'hc000}),
	
// отладочные сигналы
   .sdcard_debug(dwsddebug)
	); 

//**********************************
//*   Дисковый контроллер RX01
//**********************************
wire [3:0] rxsddebug;

rx01 dxdisk (
// шина wishbone
   .wb_clk_i(wb_clk),	// тактовая частота шины
	.wb_rst_i(sys_init),	// сброс
	.wb_adr_i(wb_adr[1:0]),	// адрес 
	.wb_dat_i(wb_out),	// входные данные
   .wb_dat_o(rx_dat),	// выходные данные
	.wb_cyc_i(wb_cyc),   // начало цикла шины
	.wb_we_i(wb_we),		// разрешение записи (0 - чтение)
	.wb_stb_i(rx_stb),	// строб цикла шины
	.wb_sel_i(wb_sel),   // выбор конкретных байтов для записи - старший, младший или оба
	.wb_ack_o(rx_ack),	// подтверждение выбора устройства

// обработка прерывания	
	.irq(rx_irq),      // запрос
	.iack(rx_iack),    // подтверждение
	
	
// интерфейс SD-карты
   .sdcard_cs(dx_cs), 
   .sdcard_mosi(dx_mosi), 
   .sdcard_miso(sdcard_miso), 


	.sdreq(dx_sdreq),
	.sdack(dx_sdack),
	.sdclock(sdclock),
	
// Адрес массива дисков на карте
	.start_offset({2'b00,sw[1:0],18'h2c000}),
	
// отладочные сигналы
   .sdcard_debug(rxsddebug)
	); 
	
//**********************************
//*  Диспетчер доступа к SD-карте
//**********************************
always @(posedge wb_clk) 
	if (sys_init == 1'b1) begin
		rk_sdack <= 1'b0;
		dw_sdack <= 1'b0;
		dx_sdack <= 1'b0;
	end	
   else
   // поиск контроллера, желающего доступ к карте
    if ((rk_sdack == 1'b0) && (dw_sdack == 1'b0) && (dx_sdack == 1'b0)) begin 
	    // неактивное состояние - ищем источник запроса 
	    if (rk_sdreq == 1'b1) rk_sdack <=1'b1;
       else if (dw_sdreq == 1'b1) dw_sdack <=1'b1;
       else if (dx_sdreq == 1'b1) dx_sdack <=1'b1;
    end    
    else 
    // активное состояние - ждем освобождения карты
       if ((rk_sdack == 1'b1) && rk_sdreq == 1'b0) rk_sdack <= 1'b0;
       else if ((dw_sdack == 1'b1) && (dw_sdreq == 1'b0)) dw_sdack <= 1'b0;
       else if ((dx_sdack == 1'b1) && (dx_sdreq == 1'b0)) dx_sdack <= 1'b0;
	
//**********************************
//* Мультиплексор линий SD-карты
//**********************************
assign sdcard_mosi =
			dw_sdack? dw_mosi: // DW
			dx_sdack? dx_mosi: // DX
			          rk_mosi; // RK по умолчанию

assign sdcard_cs =
			dw_sdack? dw_cs:	 // DW
			dx_sdack? dx_cs:	 // DX
			          rk_cs;   // RK по умолчанию
	
//**********************************
//*  Контроллер прерываний
//**********************************
wbc_vic #(.N(8)) vic
(
   .wb_clk_i(wb_clk),
   .wb_rst_i(vm_dclo_in),
   .wb_irq_o(vm_virq),
   .wb_dat_o(vm_ivec),
   .wb_stb_i(vm_istb),
   .wb_ack_o(vm_iack),
   .wb_una_i(vm_una),
   .rsel(startup_reg),    // содержимое регистра безадресного чтения
//         UART1-Tx     UART1-Rx   UART2-Tx    UART2-Rx     RK-11D        IRPR           DW         RX-11  
   .ivec({16'o000064, 16'o000060, 16'o000334,  16'o000330, 16'o000220,  16'o000330, 16'o000300, 16'o000264 }),   // векторы
   .ireq({irpstx_irq, irpsrx_irq, irpstx2_irq, irpsrx2_irq, rk11_irq,     lpt_irq,    dw_irq,     rx_irq}),   // запрос прерывания
   .iack({irpstx_iack,irpsrx_iack,irpstx2_iack,irpsrx2_iack,rk11_iack,    lpt_iack,   dw_iack,    rx_iack})    // подтверждение прерывания
);

//*******************************************************************
//* Диспетчер доступа к общей шине по запросу от разных мастеров
//*******************************************************************
reg rk11_dma_state;
assign rk11_dma_gnt = rk11_dma_state;
assign cpu_access_req = ~rk11_dma_state;

always @(posedge wb_clk) 
  if (sys_init == 1) rk11_dma_state <= 0;
  // переключение источника - только в отсутствии активного цикла шины
  else if (wb_cyc == 0) begin
     if (rk11_dma_req == 1)  rk11_dma_state <= 1; // запрос от RK11 - шина подключается к нему
     else rk11_dma_state <= 0;       // иначе шина подключается к процессору
  end

 
//*******************************************************************
//*  Коммутатор источника управления (мастера) шины wishbone
//*******************************************************************
assign wb_adr = (rk11_dma_state == 0) ? cpu_adr : {1'b0,rk11_adr};							
assign wb_out = (rk11_dma_state == 0) ? cpu_data_out : rk11_dma_out;     				
assign wb_cyc = (rk11_dma_state == 0) ? cpu_cyc : rk11_dma_req;					
assign wb_we =  (rk11_dma_state == 0) ? cpu_we : rk11_dma_we;						
assign wb_sel = (rk11_dma_state == 0) ? cpu_bsel : 2'b11;					
assign wb_stb = (rk11_dma_state == 0) ? cpu_stb : rk11_dma_stb;					
assign cpu_ack = (rk11_dma_state == 0) ? wb_ack: 1'b0;
assign rk11_dma_ack = (rk11_dma_state == 1) ? wb_ack: 1'b0;
  
//*******************************************************************
//*  Сигналы управления шины wishbone
//******************************************************************* 

// Страница ввода-выводв
assign uart1_stb  = wb_stb & wb_cyc & (wb_adr[16:3] == (17'o177560 >> 3));   // ИРПС консольный - 177560-177566 
assign uart2_stb  = wb_stb & wb_cyc & (wb_adr[16:3] == (17'o176500 >> 3));   // ИРПС дополнительный - 176500-177506
assign rk11_stb   = wb_stb & wb_cyc & (wb_adr[16:4] == (17'o177400 >> 4));   // диск RK-11D  177400-177416
assign lpt_stb    = wb_stb & wb_cyc & (wb_adr[16:2] == (17'o177514 >> 2));   // ИРПР - 177514-177516
assign dw_stb     = wb_stb & wb_cyc & (wb_adr[16:5] == (17'o174000 >> 5));   // DW - 174000-174026
assign rx_stb     = wb_stb & wb_cyc & (wb_adr[16:2] == (17'o177170 >> 2));   // RX - 177170-177172

// ROM с монитором 055/279 в теневой области с адреса 140000         
assign rom_stb = wb_stb & wb_cyc & (wb_adr[16:13] == 4'b1110);

// Все банки динамической памяти. 
//   000000 - 160000 - в юзерском режиме
//   160000 - 177776 - в режиме пульта
assign dram_stb = wb_stb & wb_cyc & ((wb_adr[15:13] != 3'b111) ^ wb_adr[16]);

// Сигналы подтверждения - собираются через OR со всех устройств
assign wb_ack     = rom_ack | dram_ack | uart1_ack | uart2_ack | rk11_ack | lpt_ack | dw_ack | rx_ack;

// Мультиплексор выходных шин данных всех устройств
assign wb_mux = 
       (rom_stb   ? rom_dat   : 16'o000000)
     | (dram_stb  ? dram_dat  : 16'o000000)
     | (uart1_stb ? uart1_dat : 16'o000000)
     | (uart2_stb ? uart2_dat : 16'o000000)
     | (rk11_stb  ? rk11_dat  : 16'o000000)
     | (lpt_stb   ? lpt_dat   : 16'o000000)
     | (dw_stb    ? dw_dat   : 16'o000000)
     | (rx_stb    ? rx_dat   : 16'o000000)
;

//**********************************
//* Сигнал разрешения таймера
//**********************************
initial timer_on=1;

always @ (posedge timer_switch)
  if (timer_switch == 1) timer_on <= ~timer_on;
  

endmodule
