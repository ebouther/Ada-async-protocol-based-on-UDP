with Ada.Text_IO;
with Ada.Exceptions;
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with GNAT.Sockets;
with GNAT.OS_Lib;

with Passive_Directory;
with Broadcast_Stuff;

with Dcod_Pmh_Service.Client;
with Buffers.Shared.Consume;

with GNAT.Traceback;
with GNAT.Traceback.Symbolic;

procedure Test_Ctl_Cons is
   use Dcod_Pmh_Service.Client;
   use Ada.Strings.Unbounded;

   task type Consume_Remote_Buffer is
      entry Request (Name : String);
   end Consume_Remote_Buffer;

   task body Consume_Remote_Buffer is
      use type Buffers.Buffer_Size_Type;

      Consumption : Buffers.Shared.Consume.Consume_Couple_Type;
      Name        : Unbounded_String;
   begin
      accept Request (Name : String) do
         Consume_Remote_Buffer.Name := To_Unbounded_String (Name);
      end Request;
      Passive_Directory.Start;
      Ada.Text_IO.Put_Line ("Passive_Directory Started");
      declare
         Pmh_Endpoint : constant String :=
            Broadcast_Stuff.Get_Process (Passive_Directory.Directory,
               Broadcast_Stuff.Posix_Memory_Handler,
               "dcod",
               GNAT.Sockets.Host_Name);
      begin
         Ada.Text_IO.Put_Line ("Endpoint : " & Pmh_Endpoint);
         Request_Buffer (To_String (Name), Pmh_Endpoint);
         Ada.Text_IO.Put_Line ("Request toto");
      end;
      Ada.Text_IO.Put_Line ("Passive_Directory Stopped");


      if GNAT.OS_Lib.Is_Directory ("/dev/mqueue/") then
         Ada.Text_IO.Put_Line ("*** on_initialise mqueue directory available ***");
      else
         Ada.Text_IO.Put_Line ("*** on_initialise mqueue directory not available - 0.5 seconds delay ***");
         delay 0.5;
      end if;

      declare
         use Buffers.Shared.Consume;
         Watchdog       : Natural := 0;
         Watchdog_Limit : constant := 20;
      begin
         if GNAT.OS_Lib.Is_Directory ("/dev/mqueue/") then
            loop
               exit when Watchdog = Watchdog_Limit;
               exit when GNAT.OS_Lib.Is_Regular_File ("/dev/mqueue" & To_String (Name));
               Ada.Text_IO.Put_Line ("*** on_initialise check" & Watchdog'Img & " ***");
               delay 0.1;
               Watchdog := Watchdog + 1;
            end loop;
         end if;
         Ada.Text_IO.Put_Line ("Set_Name");
         Consumption.Consumer.Set_Name (To_String (Name));
         Ada.Text_IO.Put_Line ("Set_Name OK");
         Consumption.Message_Handling.Start (1.0);
         Ada.Text_IO.Put_Line ("Msg Handling Start OK");
         Consumption.Consumer.Is_Initialised;
         Ada.Text_IO.Put_Line ("Is_Initialised OK");

         loop
            declare
               Buffer_Handle : Buffers.Buffer_Handle_Type;
            begin
               select
                  Consumption.Consumer.Get_Full_Buffer (Buffer_Handle);
               or
                  delay 5.0;
                  Ada.Text_IO.Put_Line ("no buffers available");
                  exit;
               end select;
               Ada.Text_IO.Put_Line ("Got A Buffer");
               declare
                  Data : array (1 .. Buffers.Get_Used_Bytes (Buffer_Handle) / Integer'Size) of Integer;
                  for Data'Address use Buffers.Get_Address (Buffer_Handle);
               begin
                  Ada.Text_IO.Put_Line ("Used Bytes :"
                     & Buffers.Get_Used_Bytes (Buffer_Handle)'Img);
                  Ada.Text_IO.Put_Line ("FIRST : " & Data (1)'Img &
                                        "SECOND : " & Data (2)'Img &
                                        "LAST : " & Data (Data'Last)'Img);
               end;
               Consumption.Consumer.Release_Full_Buffer (Buffer_Handle);
               --  Delete_Buffer (To_String (Name)); -- Test
            end;
         end loop;
         --  Passive_Directory.Stop;
      end;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : "
            & Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m" & ASCII.LF
            & "Traceback :" & GNAT.Traceback.Symbolic.Symbolic_Traceback (E));
   end Consume_Remote_Buffer;

   Consumer : array (1 .. Ada.Command_Line.Argument_Count) of Consume_Remote_Buffer;

begin
   if Ada.Command_Line.Argument_Count = 0 then
      Ada.Text_IO.Put_Line (ASCII.ESC & "[32m" &
         "Usage: test_ctl_cons buffer_1 buffer_2 ... buffer_n" &
         ASCII.LF &
         "       Request & Consume buffer_1 - buffer_n" &
         ASCII.ESC & "[0m");
   end if;

   for I in 1 .. Ada.Command_Line.Argument_Count loop
      Consumer (I).Request (Ada.Command_Line.Argument (I));
   end loop;
end Test_Ctl_Cons;
