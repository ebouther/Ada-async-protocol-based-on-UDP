with Ada.Text_IO;
with Interfaces;
with Ada.Exceptions;

package body Packet_Mgr is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;


   Buffer_Handler : Buf_Handler;


   -------------------
   --  Init_Buffer  --
   -------------------

   procedure Init_Buffer is
   begin

      Buffer_Handler.Buffer.Initialise (10, Size => Buffers.Buffer_Size_Type
         (Base_Udp.Sequence_Size * Base_Udp.Load_Size));

      Append_New_Buffer;

   end Init_Buffer;

   -------------------------
   --  Append_New_Buffer  --
   -------------------------

   procedure Append_New_Buffer is
      Handler  : access Buffers.Buffer_Handle_Type;
   begin

      Handle_Vector.Append (Buffer_Handler.Handle, New_Item => new Buffers.Buffer_Handle_Type);

      Buffer_Handler.Prod_Cursor := Buffer_Handler.Handle.Last;

      Handler := Handle_Vector.Element (Buffer_Handler.Prod_Cursor);

      Buffer_Handler.Buffer.Get_Free_Buffer (Handler.all);

      Handle_Vector.Replace_Element (Container  => Buffer_Handler.Handle,
                                     Position   => Buffer_Handler.Prod_Cursor,
                                     New_Item   => Handler);
   end Append_New_Buffer;


   ------------------------------
   --  Release_Free_Buffer_At  --
   ------------------------------

   procedure Release_Free_Buffer_At (Cursor : Handle_Vector.Cursor) is
      Handler  : access Buffers.Buffer_Handle_Type;
   begin
      Handler := Handle_Vector.Element (Cursor);

      Ada.Text_IO.Put_Line ("Release Free Buffer");
      Buffer_Handler.Buffer.Release_Free_Buffer (Handler.all);

      Ada.Text_IO.Put_Line ("Free Handler");
      Free_Buffer_Handle (Handler);

   end Release_Free_Buffer_At;


   -------------------------
   --  Set_Used_Bytes_At  --
   -------------------------

   procedure Set_Used_Bytes_At (Cursor : in Handle_Vector.Cursor;
                                Length : in Integer) is
      Handler  : access Buffers.Buffer_Handle_Type;
   begin

      Handler  := Handle_Vector.Element (Cursor);

      Buffers.Set_Used_Bytes (Handler.all,
                              Packet_Buffers.To_Bytes (Length));

      --  Handle_Vector.Replace_Element (Container  => Buffer_Handler.Handle,
      --                                 Position   => Cursor,
      --                                 New_Item   => Handler);
   end Set_Used_Bytes_At;

   -------------------------
   --  Release_First_Buf  --
   -------------------------

   task body Release_First_Buf is

   begin
      loop
         accept Release;
            Set_Used_Bytes_At (Handle_Vector.First (Buffer_Handler.Handle), Integer (Base_Udp.Sequence_Size));

            Release_Free_Buffer_At (Handle_Vector.First (Buffer_Handler.Handle));
            Buffer_Handler.Handle.Delete_First;

            Get_Filled_Buf;
      end loop;
   end Release_First_Buf;


   -------------------------
   --  Store_Packet_Task  --
   -------------------------

   task body Store_Packet_Task is

   begin
      Init_Buffer;
      loop
         select
            accept Stop;
               Set_Used_Bytes_At (Buffer_Handler.Prod_Cursor, Integer (Base_Udp.Sequence_Size));
               Ada.Text_IO.Put_Line ("*** Released Buffer before Quitting Task ***");
               Release_Free_Buffer_At (Buffer_Handler.Prod_Cursor);
               Buffer_Handler.Handle.Delete (Buffer_Handler.Prod_Cursor);
               exit;
         or
            accept New_Buffer_Addr (Buffer_Ptr   : in out System.Address) do
               Buffer_Ptr := Handle_Vector.Element (Buffer_Handler.Prod_Cursor).Get_Address;
            end New_Buffer_Addr;
               Ada.Text_IO.Put_Line ("*** Create a New Handler with New Buffer ***");
               Append_New_Buffer;
         end select;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end Store_Packet_Task;


   ----------------------
   --  Get_Filled_Buf  --
   ----------------------

   procedure Get_Filled_Buf is
   begin
      declare
         use Packet_Buffers;
         Handler  : Buffers.Buffer_Handle_Type;
      begin
         select
            Buffer_Handler.Buffer.Get_Full_Buffer (Handler);
            Ada.Text_IO.Put_Line ("---  Got Filled Buffer ---");
         or
            delay 1.0;
            Ada.Text_IO.Put_Line ("-x-  No Buf -x-");
            return;
         end select;
         declare
            type Data_Array is new Element_Array
               (1 .. To_Word_Count
                  (Buffers.Get_Used_Bytes (Handler)));

            Datas    : Data_Array;

            for Datas'Address use Buffers.Get_Address (Handler);
         begin
            for I in Datas'Range loop
               declare
                  Pkt_Nb   : Base_Udp.Header;
                  for Pkt_Nb'Address use Datas (I)'Address;
               begin
                  Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) :" &
                     Pkt_Nb'Img);
               end;
            end loop;
         end;

         Buffer_Handler.Buffer.Release_Full_Buffer (Handler);

      exception
         when E : others =>
            Ada.Text_IO.Put_Line ("exception : " &
               Ada.Exceptions.Exception_Name (E) &
               " message : " &
               Ada.Exceptions.Exception_Message (E));
      end;
   end Get_Filled_Buf;

end Packet_Mgr;
