with Ada.Text_IO;
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
      Buffer_Handler.Buffer.Initialise (PMH_Buf_Nb + 1,
         Size => Buffers.Buffer_Size_Type
         (Base_Udp.Sequence_Size * Base_Udp.Load_Size));

      Buffer_Handler.First := Buffer_Handler.Handlers'First;

      --  Current is incremented to First when Recv_Packets asks for new Buf
      Buffer_Handler.Current := Buffer_Handler.Handlers'Last;

      --  Kernel keeps memory as virtual till I write inside.
      for I in Buffer_Handler.Handlers'Range loop
         Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handlers (I).Handle);
         declare
            Message : Base_Udp.Packet_Payload;
            for Message'Address use Buffer_Handler.Handlers (I).Handle.Get_Address;
         begin
            Message := (others => 16#FA#);
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
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (4));
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
                     --  Ada.Text_IO.Put_Line ("DEAD_BEEF at : " & N'Img);
                     exit Parse_Buffer when Data = 16#DEAD_BEEF#;
                  end;
                  N := N + 1;
               end loop Parse_Buffer;
            if N = Base_Udp.Pkt_Max + 1 then
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
         delay 0.0; -- Doesn't work without rescheduling;
         if Buffer_Handler.Handlers (Buffer_Handler.First).State = Full then

            Release_Free_Buffer_At (Buffer_Handler.First);

            Buffer_Handler.Handlers (Buffer_Handler.First).Handle.Reuse;

            Buffer_Handler.Buffer.Get_Free_Buffer
               (Buffer_Handler.Handlers
                  (Buffer_Handler.First).Handle);

            Buffer_Handler.First := Buffer_Handler.First + 1;
            Ada.Text_IO.Put_Line ("First : " & Buffer_Handler.First'Img);

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
      Not_Released_Fast_Enough   : exception;
      Init                       : Boolean := True;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (12));
      loop
         select
            accept Stop;
               exit;
         or
            accept New_Buffer_Addr (Buffer_Ptr   : in out System.Address) do

               if Buffer_Handler.Current + 1 = Buffer_Handler.First
                  and not Init
               then
                  raise Not_Released_Fast_Enough;
                  --  Release Buffer even if it is not full
                  --  Buffer_Handler.Handlers (Buffer_Handler.First).State := Full;
               end if;
               Buffer_Ptr := Buffer_Handler.Handlers
                                (Buffer_Handler.Current + 1).Handle.Get_Address;
            end New_Buffer_Addr;
               if not Init then
                  Buffer_Handler.Handlers (Buffer_Handler.Current).State := Near_Full;
               end if;
               Buffer_Handler.Current := Buffer_Handler.Current + 1;
               Ada.Text_IO.Put_Line ("Current : " & Buffer_Handler.Current'Img);
               Init := False;
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

      Location_Not_Found   : exception;

      use Packet_Buffers;
      use System.Storage_Elements;
      use type Reliable_Udp.Pkt_Nb;
      use type Handle_Index;
   begin
      --  Parsing from Buffer_Handler.First to Last should be sufficient
      --  but it raises Location_Not_Found at buffer 15
      if Buffer_Handler.First > Buffer_Handler.Current then
         for N in Buffer_Handler.First .. Handle_Index'Last loop
            declare
               type Data_Array is new Element_Array
                  (1 .. Integer (Base_Udp.Sequence_Size));

               Datas    : Data_Array;
               Content  : Interfaces.Unsigned_32;

               for Datas'Address use Buffer_Handler.Handlers (N)
                  .Handle.Get_Address;
               for Content'Address use Datas (Integer (Seq_Nb) + 1)'Address;
            begin
               if Seq_Nb >= Packet_Number
                  and N = Buffer_Handler.Current
               then
                  raise Location_Not_Found;
               end if;
               if Content = 16#DEAD_BEEF# then
                  Datas (Integer (Seq_Nb) + 1) := Data;
                  return;
               end if;
            end;
         end loop;

         for N in Handle_Index'First .. Buffer_Handler.Current loop
            declare
               type Data_Array is new Element_Array
                  (1 .. Integer (Base_Udp.Sequence_Size));

               Datas    : Data_Array;
               Content  : Interfaces.Unsigned_32;

               for Datas'Address use Buffer_Handler.Handlers (N)
                  .Handle.Get_Address;
               for Content'Address use Datas (Integer (Seq_Nb) + 1)'Address;
            begin
               if Seq_Nb >= Packet_Number
                  and N = Buffer_Handler.Current
               then
                  raise Location_Not_Found;
               end if;
               if Content = 16#DEAD_BEEF# then
                  Datas (Integer (Seq_Nb) + 1) := Data;
                  return;
               end if;
            end;
         end loop;
      else
         for N in Buffer_Handler.First .. Buffer_Handler.Current loop
            declare
               type Data_Array is new Element_Array
                  (1 .. Integer (Base_Udp.Sequence_Size));

               Datas    : Data_Array;
               Content  : Interfaces.Unsigned_32;

               for Datas'Address use Buffer_Handler.Handlers (N)
                  .Handle.Get_Address;
               for Content'Address use Datas (Integer (Seq_Nb) + 1)'Address;
            begin
               if Seq_Nb >= Packet_Number
                  and N = Buffer_Handler.Current
               then
                  raise Location_Not_Found;
               end if;
               if Content = 16#DEAD_BEEF# then
                  Datas (Integer (Seq_Nb) + 1) := Data;
                  return;
               end if;
            end;
         end loop;
      end if;
      Ada.Text_IO.Put_Line ("Not Found : " & Seq_Nb'Img);
      raise Location_Not_Found;
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


   --------------------------------
   --  Copy_To_Correct_Location  --
   --------------------------------

   procedure Copy_To_Correct_Location (I, Nb_Missed   : Interfaces.Unsigned_64;
                                       Data           : Base_Udp.Packet_Stream;
                                       Data_Addr      : System.Address) is

      Good_Loc_Index :  constant Interfaces.Unsigned_64 := I + Nb_Missed
                           mod Base_Udp.Sequence_Size;
      Good_Location  :  Base_Udp.Packet_Stream;

      use System.Storage_Elements;
      for Good_Location'Address use Data_Addr + Storage_Offset
                                 (Good_Loc_Index * Base_Udp.Load_Size);
   begin
            Good_Location := Data;
   end Copy_To_Correct_Location;

end Packet_Mgr;
