with Ada.Strings.Unbounded;
with Data_Transport.Udp_Socket_Server;
with Buffers.Local;
with GNAT.Sockets;
with GNAT.Command_Line;
with Ada.Text_IO;

with Utiles_Task;

procedure Udp_Producer is
   use type Buffers.Buffer_Size_Type;
   Buffer : aliased Buffers.Local.Local_Buffer_Type;
   Server : Data_Transport.Udp_Socket_Server.Socket_Server_Task
     (Buffer'Unchecked_Access);
   type Data_Array is array (1 .. 1024) of Integer;
   Port : GNAT.Sockets.Port_Type := 8042;
   use Ada.Strings.Unbounded;
   Buffer_Name : Unbounded_String := To_Unbounded_String ("blue");
   Network_Interface : Unbounded_String := To_Unbounded_String ("lo");
   Buffer_Number : Integer := 1;
   Options : constant String := "buffer_name= port= interface=";
   A_Task_Communication : aliased Utiles_Task.Task_Communication;
   A_Terminate_Task : Utiles_Task.Terminate_Task (A_Task_Communication'Access);
begin
   loop
      case GNAT.Command_Line.Getopt (Options) is
         when ASCII.NUL =>
            exit;
         when 'b' =>
            Buffer_Name := To_Unbounded_String (GNAT.Command_Line.Parameter);
         when 'i' =>
            Network_Interface :=
              To_Unbounded_String (GNAT.Command_Line.Parameter);
         when 'p' =>
            Port := GNAT.Sockets.Port_Type'Value (GNAT.Command_Line.Parameter);
         when others =>
            raise Program_Error;
      end case;
   end loop;
   Buffer.Set_Name (To_String (Buffer_Name));
   Buffer.Initialise (10, Size => 1024 * 10);
   Server.Initialise (To_String (Network_Interface), Port);
   Ada.Text_IO.Put_Line ("Get port :" & Port'Img);
   Server.Connect;
   Ada.Text_IO.Put_Line ("Connect done");
   loop
      exit when A_Task_Communication.Stop_Enabled;
      declare
         Buffer_Handle : Buffers.Buffer_Handle_Type;
      begin
         Buffer.Get_Free_Buffer (Buffer_Handle);
         declare
            Data : Data_Array;
            for Data'Address use Buffers.Get_Address (Buffer_Handle);
         begin
            for I in Data'Range loop
               Data (I) := I;
            end loop;
            Data (Data'First) := Buffer_Number;
            Buffer_Number := Buffer_Number + 1;
         end;
         Buffers.Set_Used_Bytes (Buffer_Handle, 1024 * 10);
         Buffer.Release_Free_Buffer (Buffer_Handle);
      end;
      delay 1.0;
   end loop;
   Ada.Text_IO.Put_Line ("out of filling buffer loop");
   Ada.Text_IO.Put_Line ("Disconnect");
   Server.Disconnect;
   Ada.Text_IO.Put_Line ("exit : test");
end Udp_Producer;
