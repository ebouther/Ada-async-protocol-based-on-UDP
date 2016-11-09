with Interfaces;
with Ada.Strings.Unbounded;
with Data_Transport.Udp_Socket_Server;
with Buffers.Local;
with GNAT.Sockets;
with GNAT.Command_Line;
with Ada.Text_IO;

with Utiles_Task;

procedure Udp_Producer is
   use type Buffers.Buffer_Size_Type;
   use type Interfaces.Unsigned_64;
   use type GNAT.Sockets.Port_Type;
   use Ada.Strings.Unbounded;


   Buffer               : aliased Buffers.Local.Local_Buffer_Type;
   Buffer_Name          : Unbounded_String := To_Unbounded_String ("blue");
   Buf_Num              : Integer := 0;
   Used_Bytes           : constant Interfaces.Unsigned_64 := 409600000;
   type Data_Array is array (1 .. Used_Bytes / Integer'Size) of Integer;

   Server               : access Data_Transport.Udp_Socket_Server.Socket_Server_Task;
   Port                 : GNAT.Sockets.Port_Type := 50000;
   Network_Interface    : Unbounded_String := To_Unbounded_String ("stare-2");
   Prod_Nb              : Natural := 1;

   Options              : constant String := "buffer_name= port= hostname= nb_prod=";

   A_Task_Communication : aliased Utiles_Task.Task_Communication;
   A_Terminate_Task     : Utiles_Task.Terminate_Task (A_Task_Communication'Access);

begin
   loop
      case GNAT.Command_Line.Getopt (Options) is
         when ASCII.NUL =>
            exit;
         when 'b' =>
            Buffer_Name := To_Unbounded_String (GNAT.Command_Line.Parameter);
         when 'h' =>
            Network_Interface :=
              To_Unbounded_String (GNAT.Command_Line.Parameter);
         when 'p' =>
            Port := GNAT.Sockets.Port_Type'Value (GNAT.Command_Line.Parameter);
         when 'n' =>
            Prod_Nb := Natural'Value (GNAT.Command_Line.Parameter);
         when others =>
            raise Program_Error;
      end case;
   end loop;

   Buffer.Set_Name (To_String (Buffer_Name));
   Buffer.Initialise (10, Size => Buffers.Buffer_Size_Type (Used_Bytes));

   Init_Connect_Servers :
      for I in 1 .. Prod_Nb loop
         Server := new Data_Transport.Udp_Socket_Server.Socket_Server_Task
                     (Buffer'Unchecked_Access);
         Server.Initialise (To_String (Network_Interface), Port + GNAT.Sockets.Port_Type (I));
         Ada.Text_IO.Put_Line ("Prod [" & I'Img & " ] Port :" & Natural (Port + GNAT.Sockets.Port_Type (I))'Img);
         Server.Connect;
         Ada.Text_IO.Put_Line ("Prod [" & I'Img & " ] connected.");
      end loop Init_Connect_Servers;

   Get_Fill_Buffers :
      loop
         exit Get_Fill_Buffers when A_Task_Communication.Stop_Enabled;
         declare
            Buffer_Handle : Buffers.Buffer_Handle_Type;
         begin
            Buffer.Get_Free_Buffer (Buffer_Handle);
            declare
               Data : Data_Array;
               for Data'Address use Buffers.Get_Address (Buffer_Handle);
            begin
               --  for I in Data'Range loop
               --     Data (I) := I;
               --  end loop;
               Data (1) := Buf_Num;
               Data (Used_Bytes / Integer'Size) := Buf_Num;
               Buf_Num := Buf_Num + 1;
            end;
            Buffers.Set_Used_Bytes (Buffer_Handle, Buffers.Buffer_Size_Type (Used_Bytes));
            Buffer.Release_Free_Buffer (Buffer_Handle);
         end;
      end loop Get_Fill_Buffers;

   Ada.Text_IO.Put_Line ("[Disconnect]");
   --  Should disconnect all producers..
   Server.Disconnect;
   Ada.Text_IO.Put_Line ("Exit");
end Udp_Producer;
