with Data_Transport.Udp_Socket_Client;
with Buffers.Local;
with GNAT.Sockets;
with GNAT.Command_Line;
with Ada.Text_IO;
with Ada.Strings.Unbounded;

procedure Udp_Consumer is
   Buffer : aliased Buffers.Local.Local_Buffer_Type;
   Client : Data_Transport.Udp_Socket_Client.Socket_Client_Task
     (Buffer'Unchecked_Access);
   type Data_Array is array (1 .. 1024) of Integer;
   Options : constant String := "buffer_name= host_name= port= watchdog=";
   use Ada.Strings.Unbounded;
   Host_Name : Unbounded_String := To_Unbounded_String ("localhost");
   Buffer_Name : Unbounded_String := To_Unbounded_String ("blue");
   Port : GNAT.Sockets.Port_Type := 8042;
   Watchdog_Counter : Natural;
   Watchdog_Limit : Positive := 10;
   use type Buffers.Buffer_Size_Type;
begin
   loop
      case GNAT.Command_Line.Getopt (Options) is
         when ASCII.NUL =>
            exit;
         when 'b' =>
            Buffer_Name := To_Unbounded_String (GNAT.Command_Line.Parameter);
         when 'h' =>
            Host_Name := To_Unbounded_String (GNAT.Command_Line.Parameter);
         when 'p' =>
            Port := GNAT.Sockets.Port_Type'Value (GNAT.Command_Line.Parameter);
         when 'w' =>
            Watchdog_Limit := Positive'Value (GNAT.Command_Line.Parameter);
         when others =>
            raise Program_Error;
      end case;
   end loop;
   Buffer.Set_Name (To_String (Buffer_Name));
   Buffer.Initialise (10, Size => 10240);
   Client.Initialise (To_String (Host_Name), Port);
   Client.Connect;
   loop
      Ada.Text_IO.Put_Line ("consuming buffer loop");
      Watchdog_Counter := 0;
      loop
         select
            Buffer.Block_Full;
            Ada.Text_IO.Put_Line ("block full seen");
            exit;
         or
            delay 1.0;
            Ada.Text_IO.Put_Line ("watchdog" & Watchdog_Counter'Img);
            Watchdog_Counter := Watchdog_Counter + 1;
            if Watchdog_Counter = Watchdog_Limit then
               Client.Disconnect;
               Ada.Text_IO.Put_Line ("end of test");
               return;
            end if;
         end select;
      end loop;
      declare
         Buffer_Handle : Buffers.Buffer_Handle_Type;
      begin
         Buffer.Get_Full_Buffer (Buffer_Handle);
         declare
            Data : Data_Array;
            for Data'Address use Buffers.Get_Address (Buffer_Handle);
         begin
            Ada.Text_IO.Put_Line (Buffers.Get_Used_Bytes (Buffer_Handle)'Img);
            Ada.Text_IO.Put_Line ("FIRST : " & Data (1)'Img &
                                  "SECOND : " & Data (2)'Img &
                                  "LAST : " & Data (1024)'Img);
         end;
         Buffer.Release_Full_Buffer (Buffer_Handle);
      end;
   end loop;
end Udp_Consumer;

