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

   task body Consumer_Task is
   begin
      Buffer_Handler.Buffer.Initialise (10, Size => Buffers.Buffer_Size_Type
         ((Base_Udp.Sequence_Size * System.Storage_Unit)));
      loop
         declare
            use Packet_Buffers;
         begin
            Buffer_Handler.Buffer.Get_Full_Buffer (Buffer_Handler.Handle);
            declare
               type Data_Array is new Element_Array
                  (1 .. To_Word_Count
                     (Buffers.Get_Used_Bytes (Buffer_Handler.Handle)));

               Datas : Data_Array;

               for Datas'Address use Buffers.Get_Address (Buffer_Handler.Handle);
            begin
               Ada.Text_IO.Put_Line ("------  data (data'first) : ------" &
               Datas (Datas'First)'Img);
               Ada.Text_IO.Put_Line ("------  data (data'last) : ------" &
               Datas (Datas'Last)'Img);
            end;
            --  Buffer_Handler.Buffer.Release_Full_Buffer (Buffer_Handler.Handle);
         exception
            when E : others =>
               Ada.Text_IO.Put_Line ("exception : " &
               Ada.Exceptions.Exception_Name (E) &
               " message : " &
               Ada.Exceptions.Exception_Message (E));
         end;
      end loop;
   end Consumer_Task;

   task body Store_Packet_Task is
      Pkt_Content    : Base_Udp.Packet_Stream;
      Pkt_Nb         : Base_Udp.Header;
      pragma Warnings (Off);
      New_Seq, Ack   : Boolean;
      pragma Warnings (On);
      Pos            : Integer;
      Buf_Per_Seq    : Integer := 1;

      use Packet_Buffers;
      for Pkt_Nb'Address use Pkt_Content'Address;
   begin
      --   if New_Seq then
      --      Buffer_Handler.Buffer.Release_Free_Buffer (Buffer_Handler.Handle);
      --      Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handle);
      --   end if;
      declare
      begin
         Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handle);
         loop
            accept Store (Data            : in Base_Udp.Packet_Stream;
                        New_Sequence    : in Boolean;
                        Is_Ack          : in Boolean) do
               Pkt_Content := Data;
               New_Seq     := New_Sequence;
               Ack         := Is_Ack;
            end Store;
            declare
               type Data_Array is new
                  Packet_Buffers.Element_Array
                     (1 .. Packet_Buffers.To_Word_Count
                        (Buffers.Get_Available_Bytes (Buffer_Handler.Handle)));
                  Datas : Data_Array;
                  for Datas'Address use Buffers.Get_Address (Buffer_Handler.Handle);
            begin
               Pos := Integer (Pkt_Nb);
               Ada.Text_IO.Put_Line ("Len : " & Datas'Length'Img);
               Ada.Text_IO.Put_Line ("Seq : " & Base_Udp.Sequence_Size'Img);
               --  Ada.Text_IO.Put_Line ("Bytes : " & Buffers.Get_Available_Bytes (Buffer_Handler.Handle)'Img);

               if Pos >= Datas'Length then
                  Pos := Pos mod Datas'Length;
               end if;

               Datas (Pos + 1) := Interfaces.Unsigned_64 (Pkt_Nb);

               if Integer (Pkt_Nb) + 1 >= Datas'Length * Buf_Per_Seq then
                  Buffers.Set_Used_Bytes (Buffer_Handler.Handle,
                     Packet_Buffers.To_Bytes (Datas'Length));
                  Buffer_Handler.Buffer.Release_Free_Buffer (Buffer_Handler.Handle);
                  Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handle);
                  Buf_Per_Seq := Buf_Per_Seq + 1;
               end if;
            end;
         end loop;
      end;

   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
         Ada.Exceptions.Exception_Name (E) &
         " message : " &
         Ada.Exceptions.Exception_Message (E));
   end Store_Packet_Task;


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
