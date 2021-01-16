//
//  Контроллер дисковода MY
//
module my (

// шина wishbone
    input			         wb_clk_i,	// тактовая частота шины
	input			         wb_rst_i,	// сброс
	input	 [1:0]           wb_adr_i,	// адрес 
	input	 [15:0]          wb_dat_i,	// входные данные
    output reg [15:0]	     wb_dat_o,	// выходные данные
	input					 wb_cyc_i,	// начало цикла шины
	input					 wb_we_i,		// разрешение записи (0 - чтение)
	input					 wb_stb_i,	// строб цикла шины
	input	 [1:0]           wb_sel_i,   // выбор конкретных байтов для записи - старший, младший или оба
	output reg			     wb_ack_o,	// подтверждение выбора устройства

// обработка прерывания	
	output reg	    		 irq,	      // запрос
	input				     iack,    	// подтверждение
	
// DMA
   output reg 				dma_req,    // запрос DMA
   input 					dma_gnt,    // подтверждение DMA
   output reg[15:0]     dma_adr_o,  // выходной адрес при DMA-обмене
   input[15:0] 			dma_dat_i,  // входная шина данных DMA
   output reg[15:0] 		dma_dat_o,  // выходная шина данных DMA
	output reg 				dma_stb_o,  // строб цикла шины DMA
	output reg 				dma_we_o,   // направление передачи DMA (0 - память->диск, 1 - диск->память) 
   input 					dma_ack_i,  // Ответ от устройства, с которым идет DMA-обмен
	
// интерфейс SD-карты
   output sdcard_cs, 
   output sdcard_mosi, 
   output sdcard_sclk, 
   input sdcard_miso, 
	output reg sdreq,    // запрос доступа к карте
	input	sdack,			// подтверждение доступа к карте
	
// тактирование SD-карты
   input sdclock,	
	
// Адрес начала банка на карте
	input [22:0] start_offset,
	
// отладочные сигналы
   output [3:0] sdcard_debug
	); 
//-----------------------------------------------
//  Регистры контроллера
//
// 177170  MYCSR  - регистр управления/состояния
//                    D0      W    go - запуск команды
//                    D1-D4   W    код команды:
//                                   0000 - RD - чтение данных
//                                   0001 - WR - запись данных
//                                   0010 - RMD - чтение с меткой
//                                   0011 - WRM - запись с меткой
//                                   0100 - RDTR - чтение дорожки
//                                   0101 - RDID - чтение заголовка
//                                   0110 - FORMAT - форматирование дорожки
//                                   0111 - SEEK - переход на дорожку
//                                   1000 - SET - установка параметров
//                                   1001 - RDER - чтение регистра состояния и ошибок
//                                   1010 -----------------------
//                                   1011 -
//                                   1100 -    Р Е З Е Р В
//                                   1101 -
//                                   1110 -----------------------
//                                   1111 - LOAD -чтение загрузочного блока
//                    D5    R     DONE, признак завершения операции
//                    D6    R/W   IE, разрешение прерывания
//                    D7    R     DRQ  запрос на запись регистра данных
//                    D8-D13 W    расширение адреса, здесь не используется
//                    D14   W     сброс
//                    D15   R     ошибка
//
// 177172 MYDR   - регистр данных - адрес блока параметров или код ошибки
//
//        Регистр ошибок и состояния
//   D0    ошибка CRC данных или диск защищен от записи
//   D1    ошибка CRC заголовка 
//   D2    начальная установка завершена   
//   D3    ошибка возврата на дорожку 0 
//   D4    ошибка поиска дорожки 
//   D5    не найден сектор
//   D6    прочитан сектор с меткой
//   D7    нет сигнала от индексного датчика вращения диска
//   D8,9  номер дисковода, с которым работала последняя команда
//   D10   головка, с которой работала последняя команда
//   D11   ошибка DMA - обращение по несуществующему адресу
//   D12   не найден адресный маркер
//   D13   не найден маркер данных
//   D14   неправильный формат разметки дискеты
//   D15   внутренняя ошибка контроллера
//-----------------------------------------------

// Сигналы упраления обменом с шиной
	
wire bus_strobe = wb_cyc_i & wb_stb_i;         // строб цикла шины
wire bus_read_req = bus_strobe & ~wb_we_i;     // запрос чтения
wire bus_write_req = bus_strobe & wb_we_i;     // запрос записи
wire reset=wb_rst_i;
 
reg interrupt_trigger;     // триггер запроса прерывания

// Регистр ошибок/состояния
//                          15    14   13   12  11  10  9-8  7    6     5    4    3    2    1    0
wire [15:0] errstatus = {cmderr,1'b0,1'b0,1'b0,nxp,hd, drv,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b0,1'b0};

// состояние машины обработки прерывания
parameter[1:0] i_idle = 0; 
parameter[1:0] i_req = 1; 
parameter[1:0] i_wait = 2; 
reg[1:0] interrupt_state; 
reg done;     // операция завершена
reg ie;       // разрешение прерывания
reg drq;      // запрос на чтение-запись регистра данных

// блок параметров
reg [14:0] parm_addr; // адрес блока параметров в ОЗУ системы
reg [6:0] cyl;   // цилиндр 0 - 79
reg hd;          // головка 
reg [3:0] sec;   // сектор 0 - 10
reg [1:0] drv;         // номер привода
reg [15:0] wordcount;  // число читаемых слов
reg [15:0] ioadr;      // адрес для чтения-записи данных
reg disklimit;			// признак достижения конца диска

reg start;       // признак запуска команды на выполнение (go)
reg [3:0] cmd;

reg cmderr;      // ошибка выполнения команды
reg rstreq;      // запрос на программный сброс
reg nxp;         // ошибка при DMA-обмене


// интерфейс к SDSPI
wire [22:0] sdcard_addr;        // адрес сектора карты
wire sdcard_read_done;    // флаг окончагия чтения
wire sdcard_write_done;   // флаг окончания записи
wire sdcard_error;        // флаг ошибки
wire [15:0] sdbuf_dataout;  // слово; читаемое из буфера чтения
wire sdcard_idle;         // признак готовности контроллера
reg sdcard_read_ack;          // флаг подтверждения окончания чтения
reg sdcard_write_ack;         // флаг подтверждения команды записи
reg [7:0] sdbuf_addr;    // адрес в буфере чтния/записи
reg [15:0] sdbuf_datain;     // слово; записываемое в буфер записи
reg sdbuf_we;				// разрешение записи в буфер
reg read_start;        // строб начала чтения
reg write_start;       // строб начала записи

//  Интерфейс к DMA-контроллеру 
reg start_loadparm;    // начало загрузки параметров
reg start_rd;          // чтение данных
reg start_wr;          // запись данных
reg io_complete;       // окончание процедуры передачи данных
reg [15:0] pdata;      // слово, загрузаемое из списка параметров

// Состояния процесса обработки команд
reg [3:0] cmdstate;
parameter [3:0] CMD_START = 0;
parameter [3:0] CMD_WAITDATA = 1;
parameter [3:0] CMD_LOADPARM = 2;
parameter [3:0] CMD_WAITDMA = 3;
parameter [3:0] CMD_DCOMPLETE = 4;
parameter [3:0] CMD_STARTSECTOR = 5;

// Состояния DMA-контроллера
reg [5:0] dma_state;
reg [5:0] dmanextstate;
parameter [5:0] DMA_IDLE = 0;
parameter [5:0] DMA_LOADPARM1 = 1;
parameter [5:0] DMA_LOADPARM2 = 2;
parameter [5:0] DMA_LOADPARM3 = 3;
parameter [5:0] DMA_LOADPARM4 = 4;
parameter [5:0] DMA_LOADPARM5 = 5;
parameter [5:0] DMA_LOADWORD = 6;
parameter [5:0] DMA_LW_WAITREPLY = 7;
parameter [5:0] DMA_STARTREAD = 8;
parameter [5:0] DMA_START_SD2HOST = 9;
parameter [5:0] DMA_WORD2HOST = 10;
parameter [5:0] DMA_SD2HOST_NEXT = 11;
parameter [5:0] DMA_SD2HOST_COMPLETE = 12;
parameter [5:0] DMA_READ_WAITSDSPI = 13;
reg [7:0] dma_timer;

//***********************************************
//*  Контроллер SD-карты
//***********************************************

sdspi_slave sd1 (
	   // интерфейс к карте
      .sdcard_cs(sdcard_cs), 
      .sdcard_mosi(sdcard_mosi), 
      .sdcard_sclk(sdcard_sclk), 
      .sdcard_miso(sdcard_miso),
      .sdcard_debug(sdcard_debug), 	              // информационные индикаторы	
	
      .sdcard_addr(sdcard_addr),                      // адрес блока на карте
      .sdcard_idle(sdcard_idle),                  // сигнал готовности модуля к обмену
		
		// сигналы управления чтением 
      .sdcard_read_start(read_start),       // строб начала чтения
      .sdcard_read_ack(sdcard_read_ack),           // флаг подтверждения команды чтения
      .sdcard_read_done(sdcard_read_done),         // флаг окончагия чтения
      
		// сигналы управления записью
		.sdcard_write_start(write_start),     // строб начала записи
      .sdcard_write_ack(sdcard_write_ack),         // флаг подтверждения команды записи
      .sdcard_write_done(sdcard_write_done),       // флаг окончания записи
      .sdcard_error(sdcard_error),                 // флаг ошибки

      // интерфейс к буферной памяти контроллера
      .sdcard_xfer_addr(sdbuf_addr),         // текущий адрес в буферах чтения и записи
      .sdcard_xfer_out(sdbuf_dataout),           // слово, читаемое из буфера чтения
      .sdcard_xfer_in(sdbuf_datain),             // слово, записываемое в буфер записи
      .sdcard_xfer_write(sdbuf_we),     // разрешение записи буфера
      .controller_clk(wb_clk_i),                   // синхросигнал общей шины
      .reset(reset),                               // сброс
		.sdclk(sdclock)                               // синхросигнал SD-карты
); 
	
// формирователь ответа на цикл шины	
wire reply=wb_cyc_i & wb_stb_i & ~wb_ack_o;

//**************************************
//*  Сигнал ответа 
//**************************************
always @(posedge wb_clk_i or posedge wb_rst_i)
    if (wb_rst_i == 1) wb_ack_o <= 0;
    else wb_ack_o <= reply;

//**************************************************
// Логика обработки прерываний 
//**************************************************
always @(posedge wb_clk_i)   begin
   case (interrupt_state)
 		         // нет активного прерывания
              i_idle :
                        begin
						   //  Если поднят флаг A или B - поднимаем триггер прерывания
                           if ((ie == 1'b1) & (interrupt_trigger == 1'b1))  begin
                              interrupt_state <= i_req ; 
                              irq <= 1'b1 ;    // запрос на прерывание
                           end 
                           else	irq <= 1'b0 ;    // снимаем запрос на прерывания

                        end
					// Формирование запроса на прерывание			
               i_req :			  if (ie == 1'b0) 	interrupt_state <= i_idle ; 	
                                else if (iack == 1'b1) begin
                                    // если получено подтверждение прерывания от процессора
                                    irq <= 1'b0 ;               // снимаем запрос
												interrupt_trigger <= 1'b0;
                                    interrupt_state <= i_wait ; // переходим к ожиданию окончания обработки
                                end 
					// Ожидание окончания обработки прерывания			
               i_wait :
                           if (iack == 1'b0)  interrupt_state <= i_idle ; 
    endcase

//**************************************************
// Работа с шиной
//**************************************************
    if (reset == 1'b1 || rstreq == 1'b1) begin
		 // сброс системы
        interrupt_state <= i_idle ; 
        irq <= 1'b0 ;    // снимаем запрос на прерывания
        start <= 1'b0 ; 
        done <= 1'b1;
        ie <= 1'b0;
        cmderr <= 1'b0;
        drq <= 1'b0;
        rstreq <= 1'b0;
		cmd <= 4'b0000;
		interrupt_trigger <= 1'b0;
    end
		
	// рабочие состояния
    else   begin
				
			//*********************************************
			//* Обработка unibus-транзакций 
			//*********************************************
            // чтение регистров
            if (bus_read_req == 1'b1)   begin
               case (wb_adr_i[1])
                  1'b0 : begin  // 177170 - MYCSR
				                    //       15                 7   6    5
									wb_dat_o <= {cmderr, 1'b0, 6'b0, drq, ie, done, 5'b0};   
						 end		
                  1'b1 :   // 177172 - MYDR
                                if (!drq) wb_dat_o <= errstatus;  // если нет активной команды - читается реистр ошибок
                                else wb_dat_o <= 16'o0;            // иначе пока нули
               endcase 
			end
			
            // запись регистров	
            else if (bus_write_req == 1'b1)  begin
                if (wb_sel_i[0] == 1'b1)  
                    // запись младших байтов
                    case (wb_adr_i[1])
                     // 177170 - MYCSR
                     1'b0:  
									 if (reply) begin
									     // принят бит GO при незапущенной операции
                                if ((start == 1'b0) && (wb_dat_i[0] == 1'b1)) begin 
										      // Ввод новой команды
												start <= 1'b1;					// признак активной команды
												done <= 1'b0;					// сбрасываем признак завершения команды
												drq <= 1'b0;
												cmd <= wb_dat_i[4:1];		// код команды
											   cmderr <= 1'b0;				// сбрасываем ошибки
												interrupt_trigger <= 1'b0;	// снимаем ранее запрошенное прерывание
												cmdstate <= CMD_START;     // первый этап обработки команды
										  end			
                                ie <= wb_dat_i[6];				// флаг разрешения прерывания - доступен для записи всегда
                            end
                    // 177172 - MYBUF
                     1'b1 : 	if (drq) begin
							            parm_addr[6:0] <= wb_dat_i[7:1];  // загрузка адреса параметров
											if (reply) drq <= 1'b0;           // снимаем DRQ
										end	
                    endcase
						  
               if (wb_sel_i[1] == 1'b1)  begin
                    // запись старших байтов
                    case (wb_adr_i[1])
                     // 177170 - MYCSR
                     1'b0:  rstreq <= wb_dat_i[14];
							// 177172 - MYBUF
							1'b1:  if (drq) parm_addr[14:7] <= wb_dat_i[15:8];
						  endcase	
               end 
            end
				
			//*********************************************
			// запуск команды
			//*********************************************
  			if (start == 1'b1)  begin
           case (cmd)  // выбор действия по коду функции 
				// чтение 		
				4'b0000:
				  case (cmdstate)
				    // этап 1 - взводим DRQ
				    CMD_START: begin
					   drq <= 1'b1;
						cmdstate <= CMD_WAITDATA;
						end
						
					 // этап 2 - ждем загрузки регистра данных
					 CMD_WAITDATA: 
					   if (drq == 1'b0) begin 
						   cmdstate <= CMD_LOADPARM;
							start_loadparm <= 1'b1;   // запускаем процедуру загрузки параметров через DMA, адрес у нас теперь есть
					   end
					
				    // этап 3 - загружаем параметры
					 CMD_LOADPARM:
						if (io_complete == 1'b1) begin
							start_loadparm <= 1'b0;     // снимаем запрос на загрузку параметров
							// проверяем допустимость номеров цилиндра и сектора
							if ((cyl > 7'd79) || (sec > 4'd10)) begin
							  cmderr <= 1'b0;
							  start <= 1'b0;
							  cmdstate <= CMD_START;
							end 
							else  begin
								cmdstate <= CMD_STARTSECTOR;
							end
				       end
				
				   CMD_STARTSECTOR: begin
								start_rd <= 1'b1;         // стартуем операцию чтения сектора
								cmdstate <= CMD_WAITDMA;
						 end
						 
					// ожидание завершения работы DMA-контролера		
					CMD_WAITDMA:
						if (io_complete == 1'b1) begin
							start_rd <= 1'b0;					// снимаем команду чтения
							if (|wordcount == 1'b0) begin		
							   // передано заказанное количество слов
								start <= 1'b0;  				// завершаем обработку команды
								done <= 1'b1;					// признак завершения обработки
								interrupt_trigger <= 1'b1;	// взводим триггер прерывания
								cmdstate <= CMD_START;
							end
							// счетчик слов не исчерпан - читсем следующий сектор
							else begin
								cmdstate <= CMD_STARTSECTOR;
							end	
						end	
					 endcase   // cmdstate
			  
			  // установка парметров
			  4'b1000:
				  case (cmdstate)
				    CMD_START: begin
					   drq <= 1'b1;	// поднимаем DRQ
						cmdstate <= CMD_DCOMPLETE; // уходим ждать записи в регистр данных
						end
						
					 // drq опустился, данные в регистр загружены, но нам они не нужны
					 CMD_DCOMPLETE: 
					   if (drq == 1'b0) begin 
							start <= 1'b0;
							done <= 1'b1;
							interrupt_trigger <= 1'b1;
							cmdstate <= CMD_START;
						end
					endcase	
					
		     default: begin	
							start <= 1'b0;
							done <= 1'b1;
							interrupt_trigger <= 1'b1;
							cmdstate <= CMD_START;
							cmderr <= 1'b1;
						  end	
			  endcase	
			  
			  
			end  // конец блок обработки команд
	end  // конец блок обработки рабочего состояния		
end   // конец всего always-блока


//   output reg[15:0]     dma_adr_o,  // выходной адрес при DMA-обмене
//   input[15:0] 			dma_dat_i,  // входная шина данных DMA
//   output reg[15:0] 		dma_dat_o,  // выходная шина данных DMA
//	output reg 				dma_stb_o,  // строб цикла шины DMA
//	output reg 				dma_we_o,   // направление передачи DMA (0 - память->диск, 1 - диск->память) 
//   input 					dma_ack_i,  // Ответ от устройства, с которым идет DMA-обмен

//*******************************************
//*   Контроллер DMA
//*******************************************
always @(posedge wb_clk_i) 
  if (reset == 1'b1 || rstreq == 1'b1) begin
	// Сброс контроллера
	dma_state=DMA_IDLE;
	io_complete <= 1'b0;
	sdbuf_we <= 1'b0;
	disklimit <= 1'b0;
	read_start <= 1'b0;
	sdcard_read_ack <= 1'b0;
	sdreq <= 1'b0;
	sdcard_write_ack <= 1'b0;
	write_start <= 1'b0;
  end
  
  else case (dma_state)
  // машина состояний контроллера
    // ожидание команды
    DMA_IDLE: begin
	   io_complete <= 1'b0;
		dma_stb_o <= 1'b0;
		dma_req <= 1'b0;
		if (start_loadparm == 1'b1) begin
		  nxp <= 1'b0;
		  dma_req <= 1'b1;
		  if (dma_gnt == 1'b1) dma_state <= DMA_LOADPARM1;
		end
		else if (start_rd == 1'b1) begin	
		  nxp <= 1'b0;
		  sdreq <= 1'b1;
		  dma_state <= DMA_STARTREAD;
		end
    end
	 
	 // загрузка блока параметров - подготовка
    DMA_LOADPARM1: begin
		dmanextstate <= DMA_LOADPARM2;
		dma_state <= DMA_LOADWORD;
		dma_adr_o <= {parm_addr, 1'b0};
		end
	 // загрузка блока параметров - слово 1	
	 DMA_LOADPARM2: begin
		drv <= pdata[1:0];
		hd <= pdata[2];
		dmanextstate <= DMA_LOADPARM3;
		dma_adr_o <= {parm_addr+1'b1, 1'b0};
		dma_state <= DMA_LOADWORD;
		end
	 // загрузка блока параметров - слово 2	
	 DMA_LOADPARM3: begin
		ioadr <= pdata;
		dmanextstate <= DMA_LOADPARM4;
		dma_adr_o <= {parm_addr+2'd2, 1'b0};
		dma_state <= DMA_LOADWORD;
		end
	 // загрузка блока параметров - слово 3	
	 DMA_LOADPARM4: begin
		cyl <= pdata[13:8];
		sec <= pdata[3:0]-1'b1;
		dmanextstate <= DMA_LOADPARM5;
		dma_adr_o <= {parm_addr+2'd3, 1'b0};
		dma_state <= DMA_LOADWORD;
		end
	 // загрузка блока параметров - слово4 и завершение процесса	
	 DMA_LOADPARM5: begin
	   dma_req <= 1'b0;      // снимаем запрос DMA
		wordcount <= pdata;
		io_complete <= 1'b1;
		if (start_loadparm == 0) dma_state <= DMA_IDLE;
		end
	 
    // загрузка одного слова из памяти - старт
	 DMA_LOADWORD: begin
	   dma_stb_o <= 1'b1;    // строб начала обмена
		dma_we_o <= 1'b0;     // чтение
		dma_timer <= 8'd200;  // взводим таймер ожидания ответа
		dma_state <= DMA_LW_WAITREPLY;
		end
		
	 // загрузка одного слова из памяти - ожидание ответа шины	
	 DMA_LW_WAITREPLY: begin
		dma_timer <= dma_timer-1'b1;   // таймер--
		if (|dma_timer == 0) begin
		   // таймаут шины
		   nxp <= 1'b1;    // флаг таймаута
			dma_state <= DMA_IDLE;  // завершаем процесс
		end
		else if (dma_ack_i == 1'b1) begin
			pdata <= dma_dat_i;   // вынимаем данные с шины
			dma_adr_o <= dma_adr_o + 2'd2; // адрес++
			dma_stb_o <= 1'b0;    // снимаем строб транзакции
			dma_state <= dmanextstate;  // возвращаемся в вызывающий узел
		end
	  end	
		// старт чтения блока данных
	 DMA_STARTREAD: 
	      if (sdack == 1'b1) begin
				read_start <= 1'b1;   		// запускаем SDSPI на чтение
				if (sdcard_read_done == 1'b1) begin
					sdcard_read_ack <= 1'b1;
					dma_state <= DMA_READ_WAITSDSPI;
				end
			end
			
		DMA_READ_WAITSDSPI: 
			if (sdcard_read_done == 1'b0) begin
			  sdcard_read_ack <= 1'b0;
			  read_start <= 1'b0;
			  dma_state <= DMA_START_SD2HOST;
			  dma_req <= 1'b1;
			 end 
			 
		// подготовка к передаче блока данныхиз буфера к хосту через DMA
		DMA_START_SD2HOST:
			if (dma_gnt == 1'b1) begin
				sdbuf_addr <= 8'o0;
				dma_we_o <= 1'b1;
				dma_adr_o <= {ioadr[15:1],1'b0};
				dma_state <= DMA_WORD2HOST;
			end
		// передача одного слова через DMA из буфера в хост-память
		DMA_WORD2HOST: begin
			dma_dat_o <= sdbuf_dataout;
			dma_stb_o <= 1'b1;
			if (dma_ack_i == 1'b1) dma_state <= DMA_SD2HOST_NEXT;
		  end	
		
	   // продолжение переноса данных в ОЗУ хоста
		DMA_SD2HOST_NEXT:	 begin
			dma_stb_o <= 1'b0;
			sdbuf_addr <= sdbuf_addr + 1'b1;
			dma_adr_o <= dma_adr_o + 2'd2;
			wordcount <= wordcount - 1'b1;
			if (wordcount == 16'o1) dma_state <= DMA_SD2HOST_COMPLETE;
			else if (&sdbuf_addr == 1'b1) begin
				// переход к следующему сектору
				if (sec != 4'd10) sec <= sec + 1'b1;
				else begin
					sec <= 4'd0;
					if (hd == 1'b0) hd <= 1'b1;
					else begin
						hd<= 1'b0;
						if (cyl != 7'd79) cyl <= cyl + 1'b1;
						else disklimit <= 1'b1;
					end	
				end
				ioadr <= ioadr + 16'o1000;
				dma_state <= DMA_STARTREAD;
			end	
			else dma_state <= DMA_WORD2HOST;
		 end
		
		DMA_SD2HOST_COMPLETE: begin
			dma_req <= 1'b0;
			sdreq <= 1'b0;
			io_complete <= 1'b1;
			if (start_rd == 1'b0) dma_state <= DMA_IDLE;
		 end		
		 
		 
	endcase	
	 
//********************************************
// Вычисление адреса блока на SD-карте
//********************************************
//
// Формат образа диска:
//  25 секторов (128 байт) на дорожку(1-26)
//  76 цилиндров
//
//reg [6:0] cyl;   // цилиндр 0 - 79
//reg hd;          // головка 
//reg [3:0] sec;   // сектор 0 - 10
//reg [1:0] drv;         // номер привода
//
// полный абсолютный адрес    
//
// cyl*20+hd*10+sec   cyl*16+cyl*4 + hd*8+hd*2 + sec
//                             *16   *4
//   cyl*20+hd*10+sec        cyl>>4+cyl>>2
//
// Смещение головки
wire [3:0] hd_offset = (hd == 1'b0)? 4'd0:4'd10; 
// Смещение цилиндра cyl*20
wire [11:0] cyl_offset = (cyl<<4)+(cyl<<2);
// Смещение номера привода
wire [12:0] drv_offset= (drv == 2'b00)? 13'h0:      // привод 0
								(drv == 2'b01)? 13'h640:	 // привод 1 +1600
								(drv == 2'b10)? 13'hc80:	 // привод 2 +3200					
								13'h12c0;                   // привод 3 +4800

assign sdcard_addr = start_offset + drv_offset + cyl_offset + hd_offset + sec;

endmodule
