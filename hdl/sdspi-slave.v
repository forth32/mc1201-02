//**************************************************************************
//*            Упрощенный контроллер SD-карты
//*
//* Этот контроллер не содержит кода инициализации карты,
//* и используется для всех дисков разделяемой SD-карты, кроме первичного
//**************************************************************************

module sdspi_slave (

   // порты SDкарты
   output sdcard_cs, 
   output reg sdcard_mosi, 
   output sdcard_sclk, 
   input sdcard_miso,
   
   output reg[3:0] sdcard_debug,   // отладочные сигналы

   input[22:0] sdcard_addr,        // адрес сектора карты
   output reg sdcard_idle,         // признак готовности контроллера
   input sdcard_read_start,        // строб начала чтения
   input sdcard_read_ack,          // флаг подтверждения окончания чтения
   output reg sdcard_read_done,    // флаг окончагия чтения
   input sdcard_write_start,       // строб начала записи
   input sdcard_write_ack,         // флаг подтверждения команды записи
   output reg sdcard_write_done,   // флаг окончания записи
   output reg sdcard_error,        // флаг ошибки
   input[7:0] sdcard_xfer_addr,    // адрес в буфере чтния/записи
   output reg[15:0] sdcard_xfer_out,  // слово, читаемое из буфера чтения
   input sdcard_xfer_write,        // строб записи буфера
   input[15:0] sdcard_xfer_in,     // слово, записываемое в буфер записи
   input controller_clk,           // тактирование буферных операций - тактовый сигнал процессорной шины
   input sdclk,                    // тактовый сигнал SD-карты
   input reset 
);

//  процесс записи:                                  процесс чтения
//   - заполняем буфер
//  host            sdspi                           host            sdspi
//-------------------------------                   -------------------------------
//  write_start=1                                   read_start=1
//                  write_done=1                                     read_done=1
//  write_ack=1                                      read_ack=1 
//                  write_done=0                                     read_done=0
//  write_ack=0                                     read_ack=0
//

   //****************************
    // буферная память
   //****************************
   reg[15:0] rsector[0:255]; // буфер чтения
   reg[15:0] wsector[0:255]; // буфер записи

   
   //****************************
   // Машина состояний SDкарты
   //****************************
   parameter[4:0] sd_sendcmd0 = 1; 
   parameter[4:0] sd_checkcmd0 = 2; 
   parameter[4:0] sd_checkcmd8 = 3; 
   parameter[4:0] sd_checkcmd55 = 4; 
   parameter[4:0] sd_checkacmd41 = 5; 
   parameter[4:0] sd_checkcmd58 = 6; 
   parameter[4:0] sd_checkcmd16 = 7; 
   parameter[4:0] sd_checkcmd1 = 8; 
   parameter[4:0] sd_read_data = 9; 
   parameter[4:0] sd_read_data_waitstart = 10; 
   parameter[4:0] sd_read_crc = 11; 
   parameter[4:0] sd_write_data_startblock = 12; 
   parameter[4:0] sd_write = 13; 
   parameter[4:0] sd_write_checkresponse = 14; 
   parameter[4:0] sd_write_last = 15; 
   parameter[4:0] sd_write_crc = 16; 
   parameter[4:0] sd_read_dr = 17; 
   parameter[4:0] sd_waitwritedone = 18; 
   parameter[4:0] sd_send_cmd = 19; 
   parameter[4:0] sd_readr1wait = 20; 
   parameter[4:0] sd_readr1 = 21; 
   parameter[4:0] sd_readr3 = 22; 
   parameter[4:0] sd_readr7 = 23; 
   parameter[4:0] sd_wait = 24; 
   parameter[4:0] sd_error = 25; 
   parameter[4:0] sd_idle = 26; 

   reg[4:0] sd_state; 
   reg[4:0] sd_nextstate; 

   // регистры для обмена с картой
   reg[47:0] sd_cmd;   // команда к карте
   reg[6:0] sd_r1;  // ответ R1
   reg[31:0] sd_r3; // ответ R2 
   reg[31:0] sd_r7; // ответ R7
   reg[7:0] sd_dr; 
   reg do_readr3; 
   reg do_readr7; 

   reg[9:0] counter; 
   reg[7:0] sectorindex; 
   reg[15:0] sd_word; 
   wire clk; 
   reg[3:0] idle_filter; 
   reg[3:0] read_start_filter; 
   reg[3:0] read_ack_filter; 
   reg[3:0] read_done_filter; 
   reg[3:0] write_start_filter; 
   reg[3:0] write_ack_filter; 
   reg[3:0] write_done_filter; 
   reg[3:0] card_error_filter; 
   
   reg idle; 
   reg read_start; 
   reg read_ack; 
   reg read_done; 
   reg write_start; 
   reg write_ack; 
   reg write_done; 
   reg card_error; 


assign sdcard_cs=1'b0;    // карта всегда выбрана   
   
   // Интерфейс к хост-модулю
   always @(posedge controller_clk) begin
         
         // операции с буферами
         sdcard_xfer_out <= rsector[sdcard_xfer_addr] ; // слово, читаемое из буфера чтения
         if (sdcard_xfer_write == 1'b1)  wsector[sdcard_xfer_addr] <= sdcard_xfer_in; // запись слова в буфер записи
         
         // сдвиговые регистры фильтров интерфейсных сигналов
         idle_filter <= {idle_filter[2:0], idle} ;  // фильтр сигнала готовности
         read_start_filter <= {read_start_filter[2:0], sdcard_read_start} ; // фильтр строба чтения
         read_ack_filter <= {read_ack_filter[2:0], sdcard_read_ack} ;       // фильтр подтверждения чтения
         read_done_filter <= {read_done_filter[2:0], read_done} ;           // фильтр сигнала окончания записи
         write_start_filter <= {write_start_filter[2:0], sdcard_write_start} ; // фильтр строба записи
         write_ack_filter <= {write_ack_filter[2:0], sdcard_write_ack} ; 
         write_done_filter <= {write_done_filter[2:0], write_done} ; 
         card_error_filter <= {card_error_filter[2:0], card_error} ; 
         
         // сброс контроллера
         if (reset == 1'b1)  begin
            sdcard_idle <= 1'b0 ; 
            read_start <= 1'b0 ; 
            read_ack <= 1'b0 ; 
            sdcard_read_done <= 1'b0 ; 
            write_start <= 1'b0 ; 
            write_ack <= 1'b0 ; 
            sdcard_write_done <= 1'b0 ; 
            sdcard_error <= 1'b0 ; 
         end
         
         // фильтры интерфейсных сигналов
         else  begin
            // сигнал готовности к обмену
            if (idle_filter == {4{1'b0}})     sdcard_idle <= 1'b0 ; 
            else if (idle_filter == {4{1'b1}}) sdcard_idle <= 1'b1 ;
            
            // сигнал начала чтения
            if (read_start_filter == {4{1'b0}}) read_start <= 1'b0 ; 
            else if (read_start_filter == {4{1'b1}})  read_start <= 1'b1 ; 

            // сигнал подтверждения чтения
            if (read_ack_filter == {4{1'b0}})      read_ack <= 1'b0 ; 
            else if (read_ack_filter == {4{1'b1}}) read_ack <= 1'b1 ; 

            // строб окончания чтения
            if (read_done_filter == {4{1'b0}}) sdcard_read_done <= 1'b0 ; 
            else if (read_done_filter == {4{1'b1}})  sdcard_read_done <= 1'b1 ; 

            // сигнал начала записи
            if (write_start_filter == {4{1'b0}})     write_start <= 1'b0 ; 
            else if (write_start_filter == {4{1'b1}})  write_start <= 1'b1 ; 

            // строб подтверждения записи
            if (write_ack_filter == {4{1'b0}})       write_ack <= 1'b0 ; 
            else if (write_ack_filter == {4{1'b1}})  write_ack <= 1'b1 ; 

            // строб окончания записи
            if (write_done_filter == {4{1'b0}}) sdcard_write_done <= 1'b0 ; 
            else if (write_done_filter == {4{1'b1}}) sdcard_write_done <= 1'b1 ; 

            // сигнал ошибки карты
            if (card_error_filter == {4{1'b0}}) sdcard_error <= 1'b0 ; 
            else if (card_error_filter == {4{1'b1}}) sdcard_error <= 1'b1 ; 
         end 
   end 

   // тактовый сигнал карты
   assign clk=sdclk;
   assign sdcard_sclk = clk ;

   // Интерфейс к SD-карте
   always @(posedge clk)  begin
   
     // сброс
         if (reset == 1'b1) begin
               sd_state <= sd_idle ; 
               idle <= 1'b1 ;          
               read_done <= 1'b0 ;       // снимаем флаг окончания чтения
               write_done <= 1'b0 ;       // и записи
               card_error <= 1'b0 ;     // снимаем флаг ошибки
               do_readr3 <= 1'b0 ; 
               do_readr7 <= 1'b0 ; 
               sdcard_mosi <= 1'b1 ;   // MOSI=1
               sdcard_debug <= 4'b0011 ; 
         end
         else  begin
            // машина состояний карты
            case (sd_state)
               // Ожидание команды обмена
               sd_idle :
                        begin
                           sdcard_debug[0] <= 1'b0 ;   
                           sdcard_debug[1] <= 1'b0;
                           sdcard_debug[3:2] <= 2'b00 ; 
                           idle <= 1'b1 ;   // флаг готовности к обмену 

                           // запуск чтения
                           if (read_start == 1'b1 
                            & read_done == 1'b0 
                            & write_done == 1'b0 
                            & read_ack == 1'b0 
                            & write_ack == 1'b0)  begin
                               card_error <= 1'b0 ; 
                               idle <= 1'b0 ;    // снимаем флаг готовности
                               counter <= 48 ;   // длина команды
                               // команда чтения сектора для SDHC
                               sd_cmd <= {8'h51, 9'b000000000, sdcard_addr, 8'h01} ; 
                               sd_state <= sd_send_cmd ; // отправляем команду
                               sd_nextstate <= sd_read_data_waitstart ; // и переходим к ожиданию стартового токена
                               sdcard_debug[2] <= 1'b1 ; 
                           end 
                           
                           // запуск записи
                           else if (write_start == 1'b1 
                            & read_done == 1'b0 
                            & write_done == 1'b0 
                            & read_ack == 1'b0 
                            & write_ack == 1'b0)  begin
                               card_error <= 1'b0 ; 
                               idle <= 1'b0 ; 
                               counter <= 48 ; 
                               sd_cmd <= {8'h58 , 9'b000000000, sdcard_addr, 8'h01 } ; 
                               sd_state <= sd_send_cmd ; 
                               sd_nextstate <= sd_write_checkresponse ; 
                               sdcard_debug[3] <= 1'b1 ; 
                           end 

                           // хост подтвержил окончание чтения
                           else if (read_ack == 1'b1)  begin
                              read_done <= 1'b0 ;  // снимаем строб готовности данных
                              card_error <= 1'b0 ; 
                           end 

                           // хост подтвердил окончание записи
                           else if (write_ack == 1'b1) begin
                              write_done <= 1'b0 ; 
                              card_error <= 1'b0 ; 
                           end 
                        end
                        
               // check r1 response after write command
               sd_write_checkresponse :
                        begin
                           if (sd_r1 == 7'b0000000)  begin
                              counter <= 7 ; 
                              sd_state <= sd_write_data_startblock ; 
                           end
                           else  sd_state <= sd_error ; 
                        end
                        
               sd_write_data_startblock :
                        begin
                           if (counter != 0)  begin
                              counter <= counter - 1'b1 ; 
                              sectorindex <= 0 ; 
                              sdcard_mosi <= 1'b1 ; 
                           end
                           else begin
                              sdcard_mosi <= 1'b0 ; 
                              sd_word <= {wsector[sectorindex][7:0], wsector[sectorindex][15:8]} ; 
                              sectorindex <= sectorindex + 1'b1 ; 
                              sd_state <= sd_write ; 
                              counter <= 15 ; 
                           end 
                        end
               sd_write :
                        begin
                           sdcard_mosi <= sd_word[15] ; 
                           sd_word <= {sd_word[14:0], 1'b0} ; 
                           counter <= counter - 1'b1 ; 
                           if (counter == 0) begin
                              sd_word <= {wsector[sectorindex][7:0], wsector[sectorindex][15:8]} ; 
                              if (sectorindex == 255)  sd_state <= sd_write_last ; 
                              sectorindex <= sectorindex + 1'b1 ; 
                              counter <= 15 ; 
                           end 
                        end
               sd_write_last :
                        begin
                           sdcard_mosi <= sd_word[15] ; 
                           sd_word <= {sd_word[14:0], 1'b0} ; 
                           counter <= counter - 1'b1 ; 
                           if (counter == 0) begin
                              sd_state <= sd_write_crc ; 
                              counter <= 15 ; 
                           end 
                        end
               sd_write_crc :
                        begin
                           sdcard_mosi <= 1'b0 ; 
                           counter <= counter - 1'b1 ; 
                           if (counter == 0)  begin
                              sd_state <= sd_read_dr ; 
                              counter <= 8 ; 
                           end 
                        end
               sd_read_dr :
                        begin
                           sd_dr <= {sd_dr[6:0], sdcard_miso} ; 
                           sdcard_mosi <= 1'b1 ; 
                           counter <= counter - 1'b1 ; 
                           if (counter == 0) sd_state <= sd_waitwritedone ; 
                        end
               sd_waitwritedone :
                        begin
                           if (sd_dr[3:0] != 4'b0101) sd_state <= sd_error ; 
                           else if (sdcard_miso == 1'b1)
                           begin
                              counter <= 7 ; 
                              sd_state <= sd_wait ; 
                              write_done <= 1'b1 ;         // поднимаем строб окончания записи
                              sd_nextstate <= sd_idle ; 
                           end 
                        end
               sd_read_data_waitstart :
                        begin
                           if (sd_r1 == 7'b0000000) begin
                              if (sdcard_miso == 1'b0) begin
                                 sd_state <= sd_read_data ; 
                                 counter <= 15 ; 
                                 sectorindex <= 0 ; 
                              end 
                           end
                           else  sd_state <= sd_error ; 
                        end
               // actual read
               sd_read_data :
                        begin
                           if (counter == 0)  begin
                              counter <= 15 ; 
                              rsector[sectorindex] <= {sd_word[6:0], sdcard_miso, sd_word[14:7]}; 
                              if (sectorindex == 255)  sd_state <= sd_read_crc ; 
                              else    sectorindex <= sectorindex + 1'b1 ; 
                           end
                           else   begin
                              sd_word <= {sd_word[14:0], sdcard_miso} ; 
                              counter <= counter - 1'b1 ; 
                           end 
                        end
               // read crc after data block
               sd_read_crc :
                        begin
                           if (counter == 0)  begin
                              counter <= 15 ; 
                              //                     crc <= sd_word(6 downto 0) & sdcard_miso & sd_word(14 downto 7);
                              sd_state <= sd_wait ; 
                              sd_nextstate <= sd_idle ; 
                              read_done <= 1'b1 ;       // поднимаем флаг окончания 
                           end
                           else  begin
                              sd_word <= {sd_word[14:0], sdcard_miso} ; 
                              counter <= counter - 1'b1 ; 
                           end 
                        end
               // clock out what is in the sd_cmd, then setup to wait for a r1 response
               sd_send_cmd :
                        begin
                           if (counter != 0)  begin
                              counter <= counter - 1'b1 ; 
                              sdcard_mosi <= sd_cmd[47] ; 
                              sd_cmd <= {sd_cmd[46:0], 1'b1} ; 
                           end
                           else  begin
                              counter <= 1023 ; 
                              sd_state <= sd_readr1wait ; 
                              sdcard_mosi <= 1'b1 ; 
                           end 
                        end
               // wait to read an r1 response token from the card
               sd_readr1wait :
                        begin
                           if (counter != 0)  begin
                              counter <= counter - 1'b1 ; 
                              if (sdcard_miso == 1'b0)  begin
                                 sd_state <= sd_readr1 ; 
                                 counter <= 7 ; 
                              end 
                           end
                           else  sd_state <= sd_error ; 
                        end
               // read the r1 token
               sd_readr1 :
                        begin
                           if (counter != 0) begin
                              sd_r1 <= {sd_r1[5:0], sdcard_miso} ; 
                              counter <= counter - 1'b1 ; 
                           end
                           else  begin
                              if (do_readr7 == 1'b1)  begin
                                 do_readr7 <= 1'b0 ; 
                                 counter <= 31 ; 
                                 sd_r7[0] <= sdcard_miso ; 
                                 sd_state <= sd_readr7 ; 
                              end
                              else if (do_readr3 == 1'b1)  begin
                                 do_readr3 <= 1'b0 ; 
                                 counter <= 31 ; 
                                 sd_r3[0] <= sdcard_miso ; 
                                 sd_state <= sd_readr3 ; 
                              end
                              else if (sd_nextstate == sd_read_data_waitstart)   sd_state <= sd_read_data_waitstart ; 
                              else  begin
                                 counter <= 8 ; 
                                 sd_state <= sd_wait ; 
                              end 
                           end 
                        end
               // read r3
               sd_readr3 :
                        begin
                           if (counter != 0)   begin
                              sd_r3 <= {sd_r3[30:0], sdcard_miso} ; 
                              counter <= counter - 1'b1 ; 
                           end
                           else  begin
                              counter <= 8 ; 
                              sd_state <= sd_wait ; 
                           end 
                        end
               // read r7
               sd_readr7 :
                        begin
                           if (counter != 0)   begin
                              sd_r7 <= {sd_r7[30:0], sdcard_miso} ; 
                              counter <= counter - 1'b1 ; 
                           end
                           else   begin
                              counter <= 8 ; 
                              sd_state <= sd_wait ; 
                           end 
                        end
               // wait 8 cycles after a command sequence
               sd_wait :
                        begin
                           if (counter != 0) counter <= counter - 1'b1 ; 
                           else    sd_state <= sd_nextstate ; 
                        end
               sd_error :
                        begin
                           read_done <= 1'b1 ;       // поднимаем флаг окончания 
                           card_error <= 1'b1 ; 
                           if ((read_ack == 1'b1) || (write_ack == 1'b1))  begin
                                 sd_state <= sd_idle ; 
                                 read_done <= 1'b0;
                              end   
                        end
            endcase 
         end 
   end 
endmodule
