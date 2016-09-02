with Ada.Text_IO;
--  with Interfaces;
with Ada.Exceptions;
--  with System;
with System;

package body Packet_Mgr is

   --  Log_Seq_Nb              : Natural := 1;

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   --   task body Container_To_CSV is
   --      Pkt_Content : Packet_Content;
   --      Filled_Buf  : Container;
   --      Log_File    : Ada.Text_IO.File_Type;
   --      Packet_U64  : Interfaces.Unsigned_64;
   --      for Packet_U64'Address use Pkt_Content (2)'Address;
   --   begin
   --      loop
   --         accept Log (Buffer   : Container) do
   --            Filled_Buf := Buffer;
   --         end Log;
   --         Ada.Text_IO.Open (Log_File, Ada.Text_IO.Append_File, "recv.csv");
   --         Ada.Text_IO.Put_Line (Log_File, "---------------- Full Buffer [" &
   --            Log_Seq_Nb'Img & "] State -----------------");
   --         for I in Natural range 1 .. Base_Udp.Sequence_Size loop
   --            Pkt_Content := Filled_Buf.Buffer (I);
   --            Ada.Text_IO.Put_Line (Log_File, I'Img & Packet_U64'Img);
   --         end loop;
   --         Ada.Text_IO.Put_Line (Log_File, "----------------------------------------------------");
   --         Ada.Text_IO.Close (Log_File);
   --         Log_Seq_Nb := Log_Seq_Nb + 1;
   --      end loop;
   --   end Container_To_CSV;

   Buffer_Handler : Buf_Handler;


   -------------------
   --  Init_Buffer  --
   -------------------

   procedure Init_Buffer is
   begin

      Buffer_Handler.Buffer.Initialise (10, Size => Buffers.Buffer_Size_Type
         (Base_Udp.Sequence_Size * System.Storage_Unit));

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

   procedure Release_Free_Buffer_At (Cursor : in Handle_Vector.Cursor) is
      Handler  : access Buffers.Buffer_Handle_Type;
   begin
      Handler := Handle_Vector.Element (Cursor);

      Buffer_Handler.Buffer.Release_Free_Buffer (Handler.all);

      Handle_Vector.Replace_Element (Container  => Buffer_Handler.Handle,
                                     Position   => Cursor,
                                     New_Item   => Handler);
   end Release_Free_Buffer_At;


   ------------------------
   --  Delete_Buffer_At  --
   ------------------------

   procedure Delete_Buffer_At (Cursor : in out Handle_Vector.Cursor) is
      Handler  : access Buffers.Buffer_Handle_Type;
   begin
      Handler := Handle_Vector.Element (Cursor);

      Buffer_Handler.Buffer.Release_Full_Buffer (Handler.all);

      --  Handle_Vector.Replace_Element (Container  => Buffer_Handler.Handle,
      --                                 Index      => Buffer_Handler.Handle.First_Index,
      --                                 New_Item   => Handler);

      Free_Buffer_Handle (Handler);
      Buffer_Handler.Handle.Delete (Cursor);

   end Delete_Buffer_At;


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

      Handle_Vector.Replace_Element (Container  => Buffer_Handler.Handle,
                                     Position   => Cursor,
                                     New_Item   => Handler);
   end Set_Used_Bytes_At;


   -------------------------
   --  Store_Packet_Task  --
   -------------------------

   task body Store_Packet_Task is
      Pkt_Content    : Base_Udp.Packet_Stream;
      Pkt_Nb         : Base_Udp.Header;

      pragma Warnings (Off);
      New_Seq, Ack   : Boolean;
      pragma Warnings (On);

      use Packet_Buffers;
      for Pkt_Nb'Address use Pkt_Content'Address;

   begin
      Init_Buffer;
      loop
         accept Store (Data            : in Base_Udp.Packet_Stream;
                       New_Sequence    : in Boolean;
                       Is_Ack          : in Boolean) do
            Pkt_Content := Data;
            New_Seq     := New_Sequence;
            Ack         := Is_Ack;
         end Store;

         if New_Seq then

            Set_Used_Bytes_At (Buffer_Handler.Prod_Cursor, Integer (Base_Udp.Sequence_Size));
            Ada.Text_IO.Put_Line ("Release Buffer");
            Release_Free_Buffer_At (Buffer_Handler.Prod_Cursor);

            Consumer_Task.Start;

            Ada.Text_IO.Put_Line ("Create a New Handler with New Buffer");
            Append_New_Buffer;

         end if;

         declare
            type Data_Array is new
               Packet_Buffers.Element_Array
                  (1 .. Packet_Buffers.To_Word_Count
                     (Buffers.Get_Available_Bytes
                        (Handle_Vector.Element (Buffer_Handler.Prod_Cursor).all)));

               Datas : Data_Array;
               for Datas'Address use Buffers.Get_Address
                  (Handle_Vector.Element (Buffer_Handler.Prod_Cursor).all);
         begin

            Datas (Integer (Pkt_Nb) + 1) := Interfaces.Unsigned_64 (Pkt_Nb);

         end;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end Store_Packet_Task;


   ---------------------
   --  Consumer_Task  --
   ---------------------

   task body Consumer_Task is
      --  Cursor   : Handle_Vector.Cursor;
   begin
      loop
         accept Start;
         if Handle_Vector.Is_Empty (Buffer_Handler.Handle) = False then
            declare
               use Packet_Buffers;
               Handler  : Buffers.Buffer_Handle_Type;
            begin

               --  Handler := Handle_Vector.First_Element (Buffer_Handler.Handle);
               Ada.Text_IO.Put_Line ("_________Waiting for full buffer__________");
               Buffer_Handler.Buffer.Get_Full_Buffer (Handler);
               Ada.Text_IO.Put_Line ("_________Got Full Buffer__________");
               --  Handle_Vector.Replace_Element (Container  => Buffer_Handler.Handle,
               --                                 Index      => Buffer_Handler.Handle.First_Index,
               --                                 New_Item   => Handler);

               declare
                  type Data_Array is new Element_Array
                     (1 .. To_Word_Count
                        (Buffers.Get_Used_Bytes (Handler)));

                  Datas : Data_Array;

                  for Datas'Address use Buffers.Get_Address (Handler);
               begin
                  for I in Datas'Range loop
                     Ada.Text_IO.Put_Line (I'Img &
                        Datas (I)'Img);
                  end loop;
               end;

             --   Cursor := Buffer_Handler.Handle.First;
             --   Delete_Buffer_At (Cursor);

               Buffer_Handler.Buffer.Release_Full_Buffer (Handler);

            exception
               when E : others =>
                  Ada.Text_IO.Put_Line ("exception : " &
                     Ada.Exceptions.Exception_Name (E) &
                     " message : " &
                     Ada.Exceptions.Exception_Message (E));
            end;
         end if;
      end loop;
   end Consumer_Task;


   --   protected body Buffer_Management is

   --      procedure Store_Packet (Data           : Packet_Content;
   --                              New_Sequence   : Boolean;
   --                              Is_Ack         : Boolean) is
   --         Seq_Nb         : Base_Udp.Header;
   --         Content        : Packet_Content;
   --         Cur_Container  : Container_Ptr := Pkt_Containers.Near_Full;
   --         Tmp            : array (1 .. 2) of Container_Ptr;
   --         for Content'Address use Data'Address;
   --         for Seq_Nb'Address use Data'Address;
   --      begin
   --         if New_Sequence then
   --            --  Cur_Container := Pkt_Containers.Swap;
   --            pragma Warnings (Off);
   --            pragma Warnings (On);
   --         end if;

   --         if Pkt_Containers.Near_Full.Free_Space = 0 then

   --            Tmp (1) := Pkt_Containers.Swap;
   --            Tmp (2) := Pkt_Containers.Full;
   --            Pkt_Containers.Full := Pkt_Containers.Near_Full;
   --            Pkt_Containers.Near_Full := Tmp (1);
   --            Pkt_Containers.Swap := Tmp (2);

   --            ------- DBG -----------
   --            pragma Warnings (Off);
   --            --  Container_To_CSV_Task.Log (Pkt_Containers.Full.all);
   --            pragma Warnings (On);
   --            ------------------------

   --            Pkt_Containers.Full.Buffer := (others => (others => 0));
   --            Pkt_Containers.Full.Free_Space := Base_Udp.Header (Base_Udp.Sequence_Size);
   --         end if;

   --         if Is_Ack then
   --            pragma Warnings (Off);
   --            pragma Warnings (On);
   --         end if;
   --         if Pkt_Containers.Near_Full.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) (42) = 0 then
   --            Cur_Container := Pkt_Containers.Near_Full;
   --         else
   --            Cur_Container := Pkt_Containers.Swap;
   --            if Pkt_Containers.Swap.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) (42) = 0 then
   --               Ada.Text_IO.Put_Line ("***********|| ERROR ||***********" &
   --                  "Not enough buffer (Swap already used)");
   --            end if;
   --         end if;
   --         --  end if;

   --         ------- DBG ------
   --         Cur_Container.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) (42) := 1;
   --         ------------------
   --         Cur_Container.Buffer (Interfaces.Unsigned_64 (Seq_Nb) + 1) := Content;
   --         Cur_Container.Free_Space := Cur_Container.Free_Space - 1;

   --      end Store_Packet;

   --   end Buffer_Management;

end Packet_Mgr;
