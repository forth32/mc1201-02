module dio (
   input                  wb_clk_i,   // тактовая частота шины
   input                  wb_rst_i,   // сброс
   input    [1:0]         wb_adr_i,   // адрес 
   input      [15:0]      wb_dat_i,   // входные данные
   output reg [15:0]      wb_dat_o,   // выходные данные
   input                  wb_cyc_i,   // начало цикла шины
   input                  wb_we_i,    // разрешение записи (0 - чтение)
   input                  wb_stb_i,   // строб цикла шины
   input      [1:0]       wb_sel_i,   // выбор байтов для записи 
   output reg             wb_ack_o,   // подтверждение выбора устройства

// обработка прерывания   
   output reg             irq,        // запрос
   input                  iack,       // подтверждение
   
// интерфейс ввода-вывода дискретных сигналов
   output reg             do1,    // выходная линия 1
   output reg             do2,    // выходная линия 2
   input                  di1,    // входной сигнал 1
   input                  di2     // входной сигнал 2
 );
 
// Сигналы упраления обменом с шиной
wire bus_strobe = wb_cyc_i & wb_stb_i;         // строб цикла шины
wire bus_read_req = bus_strobe & ~wb_we_i;     // запрос чтения
wire bus_write_req = bus_strobe & wb_we_i;     // запрос записи
wire reset=wb_rst_i;
 
reg interrupt_trigger;     // триггер запроса прерывания
reg ie;                    // флаг разрешения прерываний

wire di1f, di2f;           // отфильтрованные входные сигналы
reg di1old, di2old;        // предыдущие значения входных сигналов
reg [1:0] di1_filter;
reg [1:0] di2_filter;

// состояние машины обработки прерывания
parameter[1:0] i_idle = 0;    // ожидание прерывания
parameter[1:0] i_req = 1;     // запрос векторного прерывания
parameter[1:0] i_wait = 2;    // ожидание обработки прерывания со стороны процессора
reg[1:0] interrupt_state; 

//*************************************  
//* Фильтрация входных сигналов
//*************************************  
always @ (posedge wb_clk_i) begin
     // вводим каждый сигнал в сдвиговый регистр
     di1_filter[0] <= di1;
	  di1_filter[1] <= di1_filter[0];

     di2_filter[0] <= di2;
	  di2_filter[1] <= di2_filter[0];
end
// выходы сдвиговых регистров - это отфильтрованные сигналы
assign di1f=di1_filter[1];
assign di2f=di2_filter[1];
 
//**************************************
// формирователь ответа на цикл шины   
//**************************************
wire reply=wb_cyc_i & wb_stb_i & ~wb_ack_o;     // сигнал ответа на шинную транзакцию

always @(posedge wb_clk_i or posedge wb_rst_i)
    if (wb_rst_i == 1'b1) wb_ack_o <= 1'b0;     // при системном сбросе сбрасываем сигнал подтверждения
    else wb_ack_o <= reply;                     // выводим сигнал ответа на шину

//**************************************************
// Работа с шиной 
//**************************************************
always @(posedge wb_clk_i)   begin
    if (reset == 1'b1) begin
	    //******************
       // сброс системы
	    //******************
       interrupt_state <= i_idle ; 
       irq <= 1'b0 ;    // снимаем запрос на прерывания
       ie <= 1'b0;
       interrupt_trigger <= 1'b1;
		 di1old <= 1'b0;
		 di2old <= 1'b0;
		 do1 <= 1'b0;
		 do2 <= 1'b0;
    end
      
    // рабочие состояния
    else   begin
      //******************************
      //* обработка прерывания
      //******************************
      case (interrupt_state)
        // нет активного прерывания
        i_idle :  begin
          //  Если поднят флаг - переходим в состояние активного прерывания
          if ((ie == 1'b1) & (interrupt_trigger == 1'b1))  begin
               interrupt_state <= i_req ; 
               irq <= 1'b1 ;    // запрос на прерывание
          end 
			 // иначе снимаем запрос на прерывание
          else   irq <= 1'b0 ;    
        end
          // Формирование запроса на прерывание         
        i_req :   
		    if (ie == 1'b0)    interrupt_state <= i_idle;     // прерывания запрещены
          else if (iack == 1'b1) begin
          // если получено подтверждение прерывания от процессора
              irq <= 1'b0 ;               // снимаем запрос
              interrupt_trigger <= 1'b0;  // очищаем триггер прерывания
              interrupt_state <= i_wait ; // переходим к ожиданию окончания обработки
          end 
          // Ожидание окончания обработки прерывания         
        i_wait : if (iack == 1'b0)  interrupt_state <= i_idle ; // ждем снятия сигнала iack
      endcase
            
      //*********************************************
      //* Обработка шинных транзакций 
      //*********************************************
		
      // чтение регистров
      if (bus_read_req == 1'b1)   begin
         case (wb_adr_i[1])
           1'b0 : // 175300 - CSR
                     wb_dat_o <= {9'o0, ie, interrupt_trigger,5'o0};   
           1'b1 : // 175302 - DR
                     wb_dat_o <= {12'o0, do2, do1, di2f, di1f};   
         endcase 
      end
         
      // запись регистров   
      else if (bus_write_req == 1'b1)  begin
        if (wb_sel_i[0] == 1'b1)  
        // запись младших байтов
           case (wb_adr_i[1])
           // 175300 - CSR
              1'b0:  begin
				           ie <= wb_dat_i[6];   // флаг разрешения прерывания
					        if (wb_dat_i[5] == 1'b1) interrupt_trigger <= 1'b0; // сброс триггера запроса прерывания
							end  
           // 175302 - DR
              1'b1 : begin
				           do1<=wb_dat_i[2];
				           do2<=wb_dat_i[3];
		              	end	
            endcase 
      end

      //*********************************************
      //* Детектор изменения входных сигналов
      //*********************************************
		
		if ((di1old != di1f) || (di2old != di2f)) interrupt_trigger <= 1'b1;
		di1old <= di1f;
		di2old <= di2f;
	end	
end

endmodule
