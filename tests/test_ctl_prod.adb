with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Exceptions;

with Dcod_Pmh_Service.Client;
with Buffers.Shared.Produce;

with GNAT.Traceback;
with GNAT.Traceback.Symbolic;

procedure Test_Ctl_Prod is
   use Dcod_Pmh_Service.Client;
   use Ada.Strings.Unbounded;


   task type Handle_Buffer is
      entry New_Buffer (Name : String);
   end Handle_Buffer;

   task body Handle_Buffer is
      Buf_Size       : constant := 409600000;
      Depth          : constant := 5;
      Name           : Unbounded_String;

      Production     : Buffers.Shared.Produce.Produce_Couple_Type;
   begin
      accept New_Buffer (Name : String) do
         Handle_Buffer.Name := To_Unbounded_String (Name);
      end New_Buffer;

      Provide_Buffer (Name => To_String (Name),
                   Size => Buf_Size,
                   Depth => Depth,
                   Endpoint => "http://localhost:5678");

      Ada.Text_IO.Put_Line ("Provide Buffer ok");

      Production.Producer.Set_Name (To_String (Name));
      Ada.Text_IO.Put_Line ("Set_Name ok ");
      Production.Message_Handling.Start (1.0);
      Ada.Text_IO.Put_Line ("Message_Handling Start ok ");
      Production.Producer.Is_Initialised;
      Ada.Text_IO.Put_Line ("Producer is initialised ok");

      delay 3.0;
      Ada.Text_IO.Put_Line ("Start production");
      loop
         declare
            Buffer_Handle : Buffers.Buffer_Handle_Type;
         begin
            --  select
            Production.Producer.Get_Free_Buffer (Buffer_Handle);
            --  or
            --     delay 5.0;
            --     Ada.Text_IO.Put_Line ("no buffers available");
            --     exit;
            --  end select;
            Ada.Text_IO.Put_Line ("Got a Buffer");
            declare
               Data : array (1 .. Buf_Size / Integer'Size) of Integer;
               for Data'Address use Buffers.Get_Address (Buffer_Handle);
            begin
               Data (1) := 42;
               Data (2) := 43;
               Data (Buf_Size / Integer'Size) := 4242;
            end;
            Buffers.Set_Used_Bytes (Buffer_Handle, Buffers.Buffer_Size_Type (Buf_Size));
            Production.Producer.Release_Free_Buffer (Buffer_Handle);
         end;
      end loop;

   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : "
            & Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m" & ASCII.LF
            & "Traceback :" & GNAT.Traceback.Symbolic.Symbolic_Traceback (E));
   end Handle_Buffer;

   Buffer   : array (1 .. Ada.Command_Line.Argument_Count) of Handle_Buffer;
begin
   if Ada.Command_Line.Argument_Count = 0 then
      Ada.Text_IO.Put_Line (ASCII.ESC & "[32m" &
         "Usage: test_ctl_prod buffer_1 buffer_2 ... buffer_n" &
         ASCII.LF &
         "       Provide buffer_1 - buffer_n" &
         ASCII.ESC & "[0m");
   end if;

   for I in 1 .. Ada.Command_Line.Argument_Count loop
      Buffer (I).New_Buffer (Ada.Command_Line.Argument (I));
   end loop;

end Test_Ctl_Prod;
