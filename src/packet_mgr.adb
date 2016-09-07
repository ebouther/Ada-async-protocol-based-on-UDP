with Ada.Text_IO;
with Interfaces;
with Ada.Exceptions;
with System.Multiprocessors.Dispatching_Domains;

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

      Buffer_Handler.Buffer.Initialise (PMH_Buf_Nb, Size => Buffers.Buffer_Size_Type
         (Base_Udp.Sequence_Size * Base_Udp.Load_Size));

      Buffer_Handler.First := Buffer_Handler.Handlers'First;

      --  Is incremented to First when Recv_Packets asks for new Buf
      Buffer_Handler.Current := Buffer_Handler.Handlers'Last;

      for I in Buffer_Handler.Handlers'Range loop
         Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handlers (I).Handle);
         declare
            Message : Base_Udp.Packet_Payload;
            for Message'Address use Buffer_Handler.Handlers (I).Handle.Get_Address;
         begin
            Message (Message'First) := 16#FA#;
            Message (Message'Last) := 16#DA#;
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


  -----------------------
  --  Release_Full_Buf  --
  -----------------------

   task body Release_Full_Buf is

   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (11));
      accept Start;
      loop
         delay 0.000001;
         if Buffer_Handler.Handlers (Buffer_Handler.First).State = Full then
            Ada.Text_IO.Put_Line (" *** Release first Buf *** ");

            Release_Free_Buffer_At (Buffer_Handler.First);

            Buffer_Handler.Handlers (Buffer_Handler.First).Handle.Reuse;

            Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handlers (Buffer_Handler.First).Handle);

            Buffer_Handler.First := Buffer_Handler.First + 1;

            --  Get_Filled_Buf;

         end if;
      end loop;
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
               Buffer_Handler.Handlers (Buffer_Handler.Current).State := Full;

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


   ----------------------
   --  Get_Filled_Buf  --
   ----------------------

   procedure Get_Filled_Buf is
   begin
      declare
         use Packet_Buffers;
         Handle  : Buffers.Buffer_Handle_Type;
      begin
         select
            Buffer_Handler.Buffer.Get_Full_Buffer (Handle);
            Ada.Text_IO.Put_Line ("---  Got Filled Buffer  ---");
         or
            delay 1.0;
            Ada.Text_IO.Put_Line ("-x-  No Buf -x-");
            return;
         end select;
         declare
            type Data_Array is new Element_Array
               (1 .. To_Word_Count
                  (Buffers.Get_Used_Bytes (Handle)));

            Datas    : Data_Array;

            for Datas'Address use Buffers.Get_Address (Handle);
         begin
            for I in Datas'Range loop
               declare
                  First_Pkt_Nb   : Base_Udp.Header;
                  Dead_Beef      : Interfaces.Unsigned_32;
                  --  Last_Pkt_Nb   : Base_Udp.Header;
                  for First_Pkt_Nb'Address use Datas (I)'Address;
                  for Dead_Beef'Address use Datas (I)'Address;
                  --  for Last_Pkt_Nb'Address use Datas (Datas'Last)'Address;
               begin
                  if Dead_Beef = 16#DEAD_BEEF# then
                     Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) : ** DEADBEEF **");
                  else
                     Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) :" &
                        First_Pkt_Nb'Img);
                  end if;
                  --  Ada.Text_IO.Put_Line ("Buffer (" & Datas'Last'Img & " ) :" &
                  --     Last_Pkt_Nb'Img);
               end;
            end loop;
         end;

         Buffer_Handler.Buffer.Release_Full_Buffer (Handle);

      exception
         when E : others =>
            Ada.Text_IO.Put_Line ("exception : " &
               Ada.Exceptions.Exception_Name (E) &
               " message : " &
               Ada.Exceptions.Exception_Message (E));
      end;
   end Get_Filled_Buf;

end Packet_Mgr;
