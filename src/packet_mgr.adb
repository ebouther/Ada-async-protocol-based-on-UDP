with Ada.Text_IO;
with Interfaces;
with Ada.Exceptions;
with System.Multiprocessors.Dispatching_Domains;
with System.Storage_Elements;

package body Packet_Mgr is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;


   Buffer_Handler : Buf_Handler;


   -------------------------
   --  Init_Handle_Array  --
   -------------------------

   procedure Init_Handle_Array is
   begin

      --  Need a "+ 1" otherwise it cannot get a free buffer in Release_Full_Buf
      Buffer_Handler.Buffer.Initialise (PMH_Buf_Nb + 1, Size => Buffers.Buffer_Size_Type
         (Base_Udp.Sequence_Size * Base_Udp.Load_Size));

      Buffer_Handler.First := Buffer_Handler.Handlers'First;

      --  Is incremented to First when Recv_Packets asks for new Buf
      Buffer_Handler.Current := Buffer_Handler.Handlers'Last;

      --  Please kernel give me some physical memory. Don't keep it as virtual.
      for I in Buffer_Handler.Handlers'Range loop
         Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handlers (I).Handle);
         declare
            Message : Base_Udp.Packet_Payload;
            for Message'Address use Buffer_Handler.Handlers (I).Handle.Get_Address;
         begin
            for N in Message'Range loop
               Message (N) := 0;
            end loop;
            Ada.Text_IO.Put_Line (Message (Message'Last)'Img);
         end;
      end loop;
      Ada.Text_IO.Put_Line ("_Initialization Finished_");

   end Init_Handle_Array;


   ------------------------------
   --  Release_Free_Buffer_At  --
   ------------------------------

   procedure Release_Free_Buffer_At (Index : in Handle_Index) is
   begin

      Buffers.Set_Used_Bytes (Buffer_Handler.Handlers (Index).Handle,
               Packet_Buffers.To_Bytes (Integer (Base_Udp.Sequence_Size)));

      Buffer_Handler.Buffer.Release_Free_Buffer
                        (Buffer_Handler.Handlers
                           (Index).Handle);

      Buffer_Handler.Handlers (Index).State := Empty;

   end Release_Free_Buffer_At;


  ---------------------------
  --  Check_Buf_Integrity  --
  ---------------------------

   task body Check_Buf_Integrity is
      Index : Handle_Index := Handle_Index'First;
      Addr  : System.Address;
      N     : Integer;
      use System.Storage_Elements;
   begin
      accept Start;
      loop
         if Buffer_Handler.Handlers (Index).State = Near_Full then
            Addr := Buffer_Handler.Handlers (Index).Handle.Get_Address;
            N := 0;
            Parse_Buffer :
               while N <= Base_Udp.Pkt_Max loop
                  declare
                     Data  :  Interfaces.Unsigned_32;
                     for Data'Address use Addr + Storage_Offset
                                                   (N * Base_Udp.Load_Size);
                  begin
                     exit Parse_Buffer when Data = 16#DEAD_BEEF#;
                  end;
                  N := N + 1;
               end loop Parse_Buffer;
            if N = Base_Udp.Pkt_Max then
               Buffer_Handler.Handlers (Index).State := Full;
            end if;
         end if;
         Index := Index + 1;
      end loop;
   end Check_Buf_Integrity;

  ------------------------
  --  Release_Full_Buf  --
  ------------------------

   task body Release_Full_Buf is

   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (11));
      accept Start;
      loop
         delay 0.000001; -- Doesn't work without delay :/
         if Buffer_Handler.Handlers (Buffer_Handler.First).State = Full then

            Release_Free_Buffer_At (Buffer_Handler.First);

            Buffer_Handler.Handlers (Buffer_Handler.First).Handle.Reuse;

            Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handlers (Buffer_Handler.First).Handle);

            Buffer_Handler.First := Buffer_Handler.First + 1;

            Get_Filled_Buf;

         end if;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end Release_Full_Buf;


   -----------------------
   --  PMH_Buffer_Addr  --
   -----------------------

   task body PMH_Buffer_Addr is
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (12));
      loop
         select
            accept Stop;
               --  Set_Used_Bytes_At (Buffer_Handler.Prod_Cursor, Integer (Base_Udp.Sequence_Size));
               --  Ada.Text_IO.Put_Line ("*** Released Buffer before Quitting Task ***");
               --  Release_Free_Buffer_At (Buffer_Handler.Prod_Cursor);
               --  Buffer_Handler.Handlers.Delete (Buffer_Handler.Prod_Cursor);
               exit;
         or
            accept New_Buffer_Addr (Buffer_Ptr   : in out System.Address) do

               Buffer_Ptr := Buffer_Handler.Handlers
                                (Buffer_Handler.Current + 1).Handle.Get_Address;
            end New_Buffer_Addr;
               Buffer_Handler.Handlers (Buffer_Handler.Current).State := Near_Full;

               Buffer_Handler.Current := Buffer_Handler.Current + 1;
         end select;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end PMH_Buffer_Addr;


   ----------------
   --  Save_Ack  --
   ----------------

   procedure Save_Ack (Seq_Nb          :  in Reliable_Udp.Pkt_Nb;
                       Packet_Number   :  in Reliable_Udp.Pkt_Nb;
                       Data            :  in Base_Udp.Packet_Stream) is

      use Packet_Buffers;
      use type Reliable_Udp.Pkt_Nb;
   begin
      --  Ack belongs to a previous buffer.
      declare
         type Data_Array is new Element_Array
            (1 .. Integer (Base_Udp.Sequence_Size));

         Datas    : Data_Array;
         Content  : Interfaces.Unsigned_32;
         Header   : Reliable_Udp.Header;

         for Datas'Address use Buffer_Handler.Handlers
            (if Seq_Nb > Packet_Number then
               Buffer_Handler.Current - 1
             else
               Buffer_Handler.Current
            ).Handle.Get_Address;
         for Content'Address use Datas (Integer (Seq_Nb) + 1)'Address;
         for Header'Address use Datas (Integer (Seq_Nb))'Address;
      begin
         if Content = 16#DEAD_BEEF# then --  #16DEAD_BEEF#
            --  Ada.Text_IO.Put_Line ("Found");
            Datas (Integer (Seq_Nb) + 1) := Data;
         --  else
         --     --  Not managed yet. Should check if every Near-Full buffer are complete before
         --     --  switching to Full State.
         --     Ada.Text_IO.Put_Line ("Content : " & Content'Img);
         --     Ada.Text_IO.Put_Line ("Seq_Nb : " & Seq_Nb'Img);
         --     Ada.Text_IO.Put_Line ("Prev Seq_Nb : " & Header.Seq_Nb'Img);
         --     Ada.Text_IO.Put_Line ("Might comes from an older buffer (< current - 1)");
         end if;
      end;
   end Save_Ack;


   ----------------------
   --  Get_Filled_Buf  --
   ----------------------

   procedure Get_Filled_Buf (To_File   : in Boolean := True) is
      Log_File : Ada.Text_IO.File_Type;
   begin
      declare
         Handle  : Buffers.Buffer_Handle_Type;

         use Packet_Buffers;
      begin
         select
            Buffer_Handler.Buffer.Get_Full_Buffer (Handle);
         or
            delay 1.0;
            Ada.Text_IO.Put_Line ("/!\ Error : Cannot Get A Full Buffer /!\");
            return;
         end select;

         if To_File then
            Ada.Text_IO.Open (Log_File, Ada.Text_IO.Append_File, "buffers.log");
         end if;

         declare
            type Data_Array is new Element_Array
               (1 .. To_Word_Count
                  (Buffers.Get_Used_Bytes (Handle)));

            Datas    : Data_Array;

            for Datas'Address use Buffers.Get_Address (Handle);
         begin
            for I in Datas'Range loop
               declare
                  Pkt_Nb   : Base_Udp.Header;
                  Dead_Beef      : Interfaces.Unsigned_32;

                  for Pkt_Nb'Address use Datas (I)'Address;
                  for Dead_Beef'Address use Datas (I)'Address;
               begin
                  if Dead_Beef = 16#DEAD_BEEF# then
                     if To_File then
                        Ada.Text_IO.Put_Line (Log_File, "Buffer (" & I'Img & " ) : ** DROPPED **");
                     else
                        Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) : ** DROPPED **");
                     end if;
                  else
                     if To_File then
                        Ada.Text_IO.Put_Line (Log_File, "Buffer (" & I'Img & " ) :" &
                           Pkt_Nb'Img);
                     else
                        Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) :" &
                           Pkt_Nb'Img);
                     end if;
                  end if;
               end;
            end loop;
         end;

         Buffer_Handler.Buffer.Release_Full_Buffer (Handle);
         if To_File then
            Ada.Text_IO.Close (Log_File);
         end if;

      exception
         when E : others =>
            Ada.Text_IO.Put_Line ("exception : " &
               Ada.Exceptions.Exception_Name (E) &
               " message : " &
               Ada.Exceptions.Exception_Message (E));
      end;
   end Get_Filled_Buf;

end Packet_Mgr;
