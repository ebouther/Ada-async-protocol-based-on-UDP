with Data_Transport.Udp_Socket_Client;
with Buffers.Local;
with GNAT.Sockets;
with GNAT.Command_Line;
with Interfaces;
with Ada.Text_IO;
with Ada.Strings.Unbounded;

procedure Udp_Consumer is
   Total_Bytes_Received : Interfaces.Unsigned_64 := 0;
   Buffer : aliased Buffers.Local.Local_Buffer_Type;
   Client : Data_Transport.Udp_Socket_Client.Socket_Client_Task
      (null);
      --  (Buffer'Unchecked_Access);
   --  type Data_Array is array (1 .. 1024) of Integer;
   Options : constant String := "buffer_name= host_name= port= watchdog=";
   use Ada.Strings.Unbounded;
   Host_Name : Unbounded_String := To_Unbounded_String ("localhost");
   Buffer_Name : Unbounded_String := To_Unbounded_String ("blue");
   Port : GNAT.Sockets.Port_Type := 8042;
   --  Watchdog_Counter : Natural;
   --  Watchdog_Limit : Positive := 10;
   use type Buffers.Buffer_Size_Type;

   task type Timer_Task is
      entry Start;
   end Timer_Task;

   task body Timer_Task is
      Elapsed_Sec   : Integer := 0;
   begin
      accept Start;
      loop
         Ada.Text_IO.Put_Line ("////////////\\\// DEBIT : "
            & Long_Float'Image (Long_Float (Total_Bytes_Received) / Long_Float (Elapsed_Sec) * 8.0));
         delay 5.0;
         Elapsed_Sec := Elapsed_Sec + 5;
      end loop;
   end Timer_Task;

   Timer : Timer_Task;
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
         --  when 'w' =>
         --     Watchdog_Limit := Positive'Value (GNAT.Command_Line.Parameter);
         when others =>
            raise Program_Error;
      end case;
   end loop;
   Buffer.Set_Name (To_String (Buffer_Name));
   Buffer.Initialise (10, Size => 409600000);
   Client.Initialise (To_String (Host_Name), Port);
   Client.Connect;
   loop
      --  Ada.Text_IO.Put_Line ("consuming buffer loop");
      --  Watchdog_Counter := 0;
      loop
         --  select
         Buffer.Block_Full;
         select
            Timer.Start;
         else
            null;
         end select;
         --  Ada.Text_IO.Put_Line ("block full seen");
         exit;
         --  or
         --     delay 1.0;
         --     Ada.Text_IO.Put_Line ("watchdog" & Watchdog_Counter'Img);
         --     Watchdog_Counter := Watchdog_Counter + 1;
         --     if Watchdog_Counter = Watchdog_Limit then
         --        Client.Disconnect;
         --        Ada.Text_IO.Put_Line ("end of test");
         --        return;
         --     end if;
         --  end select;
      end loop;
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
end Udp_Consumer;

