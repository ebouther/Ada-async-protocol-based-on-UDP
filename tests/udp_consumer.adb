with Data_Transport.Udp_Socket_Client;
with Buffers.Local;
with GNAT.Sockets;
with GNAT.Command_Line;
with Interfaces;
with Ada.Text_IO;
with Ada.Strings.Unbounded;
with Ada.Exceptions;
with Log4ada.Loggers;
with Log4ada.Appenders.Consoles;

procedure Udp_Consumer is
   use Ada.Strings.Unbounded;

   Total_Bytes_Received : Interfaces.Unsigned_64 := 0;
   Buffer      : aliased Buffers.Local.Local_Buffer_Type;
   Client      : access Data_Transport.Udp_Socket_Client.Socket_Client_Task;
   Options     : constant String := "buffer_name= port= hostname= watchdog= nb_cons=";
   Buffer_Name : Unbounded_String := To_Unbounded_String ("blue");
   Cons_Nb     : Natural := 1;

   Logger      : aliased Log4ada.Loggers.Logger_Type;
   Console     : aliased Log4ada.Appenders.Consoles.Console_Type;
   Port        : GNAT.Sockets.Port_Type := 0;
   --  AWS_Port    : constant Integer := 8080;

   --  Consumer ip
   Network_Interface    : Unbounded_String := To_Unbounded_String ("10.0.0.3");

   pragma Warnings (Off);
   Disconnect  : Boolean   := False;
   pragma Warnings (On);

   use type Buffers.Buffer_Size_Type;

   task type Debit_Task is
      entry Start;
   end Debit_Task;

   task body Debit_Task is
      Elapsed_Sec   : Integer := 0;
   begin
      accept Start;
      loop
         Ada.Text_IO.Put_Line ("////////////\\\// DEBIT : "
            & Long_Float'Image (Long_Float (Total_Bytes_Received) / Long_Float (Elapsed_Sec) * 8.0));
         delay 5.0;
         --  Disconnect := True;
         Elapsed_Sec := Elapsed_Sec + 5;
      end loop;
   end Debit_Task;

   Debit : Debit_Task;
   use Ada.Strings.Unbounded;
   use type GNAT.Sockets.Port_Type;
begin
   Logger.Set_Level (Log4ada.Debug);
   Logger.Set_Name ("Udp_Producer");
   Logger.Add_Appender (Console'Unchecked_Access);

   loop
      case GNAT.Command_Line.Getopt (Options) is
         when ASCII.NUL =>
            exit;
         when 'b' =>
            Buffer_Name := To_Unbounded_String (GNAT.Command_Line.Parameter);
         when 'p' =>
            Port := GNAT.Sockets.Port_Type'Value (GNAT.Command_Line.Parameter);
         when 'n' =>
            Cons_Nb := Natural'Value (GNAT.Command_Line.Parameter);
         when 'h' =>
            Network_Interface :=
              To_Unbounded_String (GNAT.Command_Line.Parameter);
         when others =>
            raise Program_Error;
      end case;
   end loop;
   Buffer.Set_Name (To_String (Buffer_Name));
   Buffer.Initialise (10, Size => 409600000);
   for I in 1 .. Cons_Nb loop
      Client := new Data_Transport.Udp_Socket_Client.Socket_Client_Task
                     (Buffer'Unchecked_Access);
      Client.Initialise (To_String (Network_Interface),
                         Port,
                         Logger'Unchecked_Access); -- name of ratp consumer's internal shared buffer.
      Client.Connect;
   end loop;

   loop
      if Disconnect then
         Client.Disconnect;
      end if;
      Buffer.Block_Full;
      select
         Debit.Start;
      else
         null;
      end select;
      declare
         Buffer_Handle : Buffers.Buffer_Handle_Type;
         use type Interfaces.Unsigned_64;
      begin
         Buffer.Get_Full_Buffer (Buffer_Handle);

         Total_Bytes_Received := Total_Bytes_Received
                                    + Interfaces.Unsigned_64
                                       (Buffers.Get_Used_Bytes (Buffer_Handle));
         --  declare
         --     Data : array (1 .. Buffers.Get_Used_Bytes (Buffer_Handle) / Integer'Size) of Integer;
         --     for Data'Address use Buffers.Get_Address (Buffer_Handle);
         --  begin
         --     Ada.Text_IO.Put_Line ("Used Bytes :"
         --        & Buffers.Get_Used_Bytes (Buffer_Handle)'Img);
         --     Ada.Text_IO.Put_Line ("FIRST : " & Data (1)'Img &
         --                           "SECOND : " & Data (2)'Img &
         --                           "LAST : " & Data (Data'Last)'Img);
         --  end;
         Buffer.Release_Full_Buffer (Buffer_Handle);
      end;
   end loop;
exception
   when E : others =>
      Logger.Error_Out (ASCII.ESC & "[31m" & "Exception : " &
         Ada.Exceptions.Exception_Name (E)
         & ASCII.LF & ASCII.ESC & "[33m"
         & Ada.Exceptions.Exception_Message (E)
         & ASCII.ESC & "[0m");

end Udp_Consumer;
