with Ada.Text_IO;
with Ada.Exceptions;
with Ada.Calendar;
with System.Multiprocessors.Dispatching_Domains;
with System.Storage_Elements;

with Dcod_Pmh_Service.Client;
with Buffers.Shared.Produce;
with Buffers.Shared.Consume;
with Common_Types;

package body Buffer_Handling is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;


   --------------------
   --  Init_Buffers  --
   --------------------

   procedure Init_Buffers (Obj                  : Buffer_Handler_Obj_Access;
                           Buffer_Name          : String;
                           End_Point            : String) is
      Ret  : Interfaces.C.int;

      use type Common_Types.Buffer_Size_Type;
      use type Interfaces.C.int;
   begin

      Ret := mlockall (2);
      if Ret = -1 then
         Perror ("Mlockall Error");
      end if;

      --  Need a "+ 1" otherwise it cannot get a
      --  free buffer in Release_Full_Buf
      Dcod_Pmh_Service.Client.Provide_Buffer (Name => Buffer_Name,
                                              Size => Base_Udp.Buffer_Size,
                                              Depth => Base_Udp.PMH_Buf_Nb + 1,
                                              Endpoint => End_Point);

      Ada.Text_IO.Put_Line ("Buffer   Size :" & Base_Udp.Buffer_Size'Img
         & " Depth : " & Integer (Base_Udp.PMH_Buf_Nb + 1)'Img);

      Obj.Buffer_Prod.Set_Name (Buffer_Name);
      Obj.Production.Message_Handling.Start (1.0);
      Obj.Buffer_Cons.Set_Name (Buffer_Name);
      Obj.Consumption.Message_Handling.Start (1.0);
      Obj.Buffer_Prod.Is_Initialised;

      Obj.Buffer_Handler.First := Obj.Buffer_Handler.Handlers'First;

      --  Current is incremented to First when Recv_Packets asks for new Buf
      Obj.Buffer_Handler.Current := Obj.Buffer_Handler.Handlers'Last;

      for I in Obj.Buffer_Handler.Handlers'Range loop
         Obj.Buffer_Prod.Get_Free_Buffer (Obj.Buffer_Handler.Handlers (I)
            .Handle);
      end loop;
      Ada.Text_IO.Put_Line (ASCII.ESC & "[32;1m" & "Buffers   [✓]" & ASCII.ESC & "[0m");

   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31;1m" & "Buffers   [x]" & ASCII.ESC & "[0m");
         Ada.Text_IO.Put_Line (ASCII.ESC & "[33m"
            & "Make sure that old buffers were removed"
            & " and that dcod is running before launching udp_server."
            & ASCII.LF & " (ex : $> rm -f /dev/shm/* /dev/mqueue/* &&"
            & " dcod_launch -i -m -l -L $LD_LIBRARY_PATH -v )"
            & ASCII.ESC & "[0m");

         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Init_Buffers;


   ------------------------------
   --  Release_Free_Buffer_At  --
   ------------------------------

   procedure Release_Free_Buffer_At (Obj     : Buffer_Handle_Obj_Access;
                                     Index   : in Handle_Index_Type) is
      use Base_Udp;
      Buf     : Handler_Type renames Obj.Buffer_Handler.Handlers (Index);
   begin

      Buffers.Set_Used_Bytes
         (Buf.Handle, Buffers.Buffer_Size_Type
            (Load_Size * Sequence_Size)); --  Size change on disconnect / end of prod data
      Buffer_Prod.Release_Free_Buffer (Buf.Handle);
      Buf.State := Empty;

   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Release_Free_Buffer_At;


  --------------------------------
  --  Check_Buf_Integrity_Task  --
  --------------------------------

   task body Check_Buf_Integrity_Task is
      Obj   : Buffer_Handle_Obj_Access;
      Index : Handle_Index_Type := Handle_Index_Type'First;
      Addr  : System.Address;
      N     : Integer;
      use System.Storage_Elements;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (4));
      accept Start (Buffer_H  :  Buffer_Handler_Obj_Access) do
         Obj   := Buffer_H;
      end Start;
      loop
         if Obj.Buffer_Handler.Handlers (Index).State = Near_Full then
            Addr := Obj.Buffer_Handler.Handlers (Index).Handle.Get_Address;
            N := 0;
            Parse_Buffer :
               while N <= Base_Udp.Pkt_Max loop
                  declare
                     Data  :  Interfaces.Unsigned_32;
                     for Data'Address use Addr + Storage_Offset
                                                   (N * Base_Udp.Load_Size);
                  begin
                     --  Exit if buffer is still waiting for dropped packet payload.
                     exit Parse_Buffer when Data = 16#DEAD_BEEF#;
                  end;
                  N := N + 1;
               end loop Parse_Buffer;
            if N = Base_Udp.Pkt_Max + 1 then
               Obj.Buffer_Handler.Handlers (Index).State := Full;
            end if;
         end if;
         Index := Index + 1;
      end loop;
   end Check_Buf_Integrity_Task;


  -----------------------
  --  Mark_Empty_Cell  --
  -----------------------

   procedure Mark_Empty_Cell (I           :  Interfaces.Unsigned_64;
                              Data_Addr   :  System.Address;
                              Last_Addr   :  System.Address;
                              Nb_Missed   :  Interfaces.Unsigned_64)
   is
      Addr        :  System.Address;
      Pos         :  Interfaces.Unsigned_64;

      use System.Storage_Elements;
      use type System.Address;
   begin
      for N in I .. I + Nb_Missed - 1 loop
         Pos := N;
         if N >= Base_Udp.Sequence_Size
            and I < Base_Udp.Sequence_Size
         then
            Addr  := Data_Addr;
            Pos   := N mod Base_Udp.Sequence_Size;
         else
            Addr  := Last_Addr;
         end if;

         declare
            Data_Missed  :  Interfaces.Unsigned_32;
            for Data_Missed'Address use Addr + Storage_Offset
                                             (Pos * Base_Udp.Load_Size);
         begin
            Data_Missed := 16#DEAD_BEEF#;
         end;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Mark_Empty_Cell;


  -----------------------------
  --  Release_Full_Buf_Task  --
  -----------------------------

   task body Release_Full_Buf_Task is
      Obj   : Buffer_Handle_Obj_Access;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (11));
      accept Start (Buffer_H  : Buffer_Handler_Obj_Access) do
         Obj := Buffer_H;
      end Start;
      loop
         delay 0.0; -- Doesn't work without rescheduling; -- edit: Might not be needed anymore
         if Buffer_Handler.Handlers (Buffer_Handler.First).State = Full then

            Release_Free_Buffer_At (Buffer_Handler.First);

            Buffer_Handler.Handlers (Buffer_Handler.First).Handle.Reuse;

            Buffer_Prod.Get_Free_Buffer
               (Buffer_Handler.Handlers
                  (Buffer_Handler.First).Handle);

            Buffer_Handler.First := Buffer_Handler.First + 1;
            Ada.Text_IO.Put_Line ("First : " & Buffer_Handler.First'Img);
         end if;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end Release_Full_Buf_Task;


   ----------------------------
   --  PMH_Buffer_Addr_Task  --
   ----------------------------

   task body PMH_Buffer_Addr_Task is
      Not_Released_Fast_Enough   : exception;
      Init                       : Boolean := True;
      Obj                        : Buffer_Handler_Obj_Access;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (12));
      accept Start (Buffer_H  : Buffer_Handler_Obj_Access) do
         Obj := Buffer_H; 
      end Start;
      loop
         select
            accept Stop;
               exit;
         or
            accept New_Buffer_Addr (Buffer_Ptr   : in out System.Address)
            do
               if Obj.Buffer_Handler.Current + 1 = Obj.Buffer_Handler.First
                  and not Init
               then
                  Ada.Exceptions.Raise_Exception (Not_Released_Fast_Enough'Identity,
                     "All buffers are used. Make sure a consumer was launched.");
               end if;
               Buffer_Ptr := Obj.Buffer_Handler.Handlers
                                (Obj.Buffer_Handler.Current + 1).
                                    Handle.Get_Address;
            end New_Buffer_Addr;
               if not Init then
                  Obj.Buffer_Handler.Handlers (Obj.Buffer_Handler.Current).
                                                      State := Near_Full;
               end if;
               Obj.Buffer_Handler.Current := Obj.Buffer_Handler.Current + 1;
               Init := False;
               Ada.Text_IO.Put_Line ("Current : " & Obj.Buffer_Handler.Current'Img);
         end select;
      end loop;
   exception
      when E : others =>

         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end PMH_Buffer_Addr_Task;


   -------------------------
   --  Search_Empty_Mark  --
   -------------------------

   function Search_Empty_Mark
                        (First, Last   : Handle_Index_Type;
                         Data          : in Base_Udp.Packet_Stream;
                         Seq_Nb        : Reliable_Udp.Packet_Number_Type) return Boolean

   is

      use System.Storage_Elements;
      use type Reliable_Udp.Packet_Number_Type;
      use type Handle_Index_Type;
   begin
      for N in First .. Last loop
         declare
            type Data_Array is new Packet_Buffers.Element_Array
               (1 .. Integer (Base_Udp.Sequence_Size));

            Datas    : Data_Array;
            Content  : Interfaces.Unsigned_32;

            for Datas'Address use Buffer_Handler.Handlers (N)
               .Handle.Get_Address;
            for Content'Address use Datas (Integer (Seq_Nb) + 1)'Address;
         begin
            --  This is "Empty Mark" (16#DEAD_BEEF#)
            if Content = 16#DEAD_BEEF# then
               Datas (Integer (Seq_Nb) + 1) := Data;
               return True;
            end if;
         end;
      end loop;
      return False;
   end Search_Empty_Mark;


   ----------------
   --  Save_Ack  --
   ----------------

   procedure Save_Ack (Obj             : Buffer_Handler_Obj_Access;
                       Seq_Nb          : in Reliable_Udp.Packet_Number_Type;
                       Packet_Number   : in Reliable_Udp.Packet_Number_Type;
                       Data            : in Base_Udp.Packet_Stream) is

      Location_Not_Found   : exception;
      use type Reliable_Udp.Packet_Number_Type;
      pragma Unreferenced (Packet_Number);
   begin
      if Buffer_Handler.First > Buffer_Handler.Current then

         if Search_Empty_Mark (Buffer_Handler.First,
                               Handle_Index_Type'Last,
                               Data,
                               Seq_Nb)
         or
            Search_Empty_Mark (Handle_Index_Type'First,
                               Buffer_Handler.Current,
                               Data,
                               Seq_Nb)
         then
            return;
         end if;
      else
         if Search_Empty_Mark (Buffer_Handler.First,
                               Buffer_Handler.Current,
                               Data,
                               Seq_Nb)
         then
            return;
         end if;
      end if;
      Ada.Text_IO.Put_Line ("Not Found : " & Seq_Nb'Img);
      raise Location_Not_Found;
   end Save_Ack;


   -----------------------
   --  New_Dest_Buffer  --
   -----------------------

   function New_Dest_Buffer (Dest_Buffer     : Buffers.Buffer_Produce_Access;
                             Size            : Interfaces.Unsigned_32;
                             Buffer_Size     : in out Interfaces.Unsigned_32;
                             Packet_Nb       : in out Interfaces.Unsigned_64;
                             Src_Index       : in out Interfaces.Unsigned_64;
                             Src_Handle      : in out Buffers.Buffer_Handle_Access;
                             Dest_Index      : in out Ada.Streams.Stream_Element_Offset;
                             Dest_Handle     : in out Buffers.Buffer_Handle_Access;
                             Src_Data_Stream : Base_Udp.Sequence_Type) return Boolean is

      Zero_Buf_Size  : exception;
      use type Buffers.Buffer_Handle_Access;
   begin
      Packet_Nb := 0;
      if Size = 0 then
         raise Zero_Buf_Size with "Buffer Size = 0";
      end if;
      if Dest_Handle /= null then
         Buffers.Set_Used_Bytes (Dest_Handle.all,
                                 Buffers.Buffer_Size_Type (Buffer_Size));
         Dest_Buffer.Release_Free_Buffer (Dest_Handle.all);
         Buffers.Free (Dest_Handle);
      end if;
      Dest_Handle := new Buffers.Buffer_Handle_Type;
      Dest_Buffer.Get_Free_Buffer (Dest_Handle.all);
      Buffer_Size := Size;
      Dest_Index := 0;
      --  This packet contains a buffer size,
      --  move directly to next packet which contains buffer's data.
      Src_Index := Src_Index + 1;
      return New_Src_Buffer (Src_Index, Src_Handle, Src_Data_Stream);
   end New_Dest_Buffer;


   ----------------------
   --  New_Src_Buffer  --
   ----------------------

   procedure New_Src_Buffer (Src_Index       : in out Interfaces.Unsigned_64;
                             Src_Handle      : in out Buffers.Buffer_Handle_Access;
                             Src_Data_Stream : Base_Udp.Sequence_Type) is
   begin
      if Src_Index > Src_Data_Stream'Last then
         Buffer_Cons.Release_Full_Buffer (Src_Handle.all);

         Buffers.Free (Src_Handle);
         Src_Handle := new Buffers.Buffer_Handle_Type;
         Buffer_Cons.Get_Full_Buffer (Src_Handle.all);
         Src_Index := 1;
      end if;
   end New_Src_Buffer;


   function New_Src_Buffer (Src_Index       : in out Interfaces.Unsigned_64;
                            Src_Handle      : in out Buffers.Buffer_Handle_Access;
                            Src_Data_Stream : Base_Udp.Sequence_Type) return Boolean is
   begin
      if Src_Index > Src_Data_Stream'Last then
         Buffer_Cons.Release_Full_Buffer (Src_Handle.all);

         Buffers.Free (Src_Handle);
         Src_Handle := new Buffers.Buffer_Handle_Type;
         Buffer_Cons.Get_Full_Buffer (Src_Handle.all);
         Src_Index := 1;
         return True;
      end if;
      return False;
   end New_Src_Buffer;


   --------------------------------
   --  Copy_Packet_Data_To_Dest  --
   --------------------------------

   procedure Copy_Packet_Data_To_Dest (Buffer_Size     : Interfaces.Unsigned_32;
                                       Src_Index       : in out Interfaces.Unsigned_64;
                                       Src_Handle      : in out Buffers.Buffer_Handle_Access;
                                       Dest_Handle     : Buffers.Buffer_Handle_Access;
                                       Dest_Index      : in out Ada.Streams.Stream_Element_Offset;
                                       Src_Data_Stream : Base_Udp.Sequence_Type) is
      use Ada.Streams;
      use Interfaces;

      Bad_Index            : exception;

      Dest_Data_Stream     : Stream_Element_Array
                            (1 .. Stream_Element_Offset
                               (Buffers.Get_Available_Bytes (Dest_Handle.all)));

      for Dest_Data_Stream'Address use Buffers.Get_Address (Dest_Handle.all);
      Offset               : Unsigned_64 :=
                              Base_Udp.Load_Size - Base_Udp.Header_Size;

   begin
      if Unsigned_64 (Dest_Index) + Offset > Unsigned_64 (Buffer_Size) then
         if Unsigned_32 (Dest_Index) > Buffer_Size then
            raise Bad_Index with "Index [" & Unsigned_32 (Dest_Index)'Img
                     & "] bigger that buffer size [" & Buffer_Size'Img & "]";
         end if;
         Offset := Unsigned_64 (Buffer_Size - Unsigned_32 (Dest_Index));
      end if;

      Dest_Data_Stream (Dest_Index + 1 .. Dest_Index + Stream_Element_Offset (Offset)) :=
         Src_Data_Stream
            (Src_Index)
               (Base_Udp.Header_Size + 1 .. Base_Udp.Header_Size + Stream_Element_Offset (Offset));

      Src_Index := Src_Index + 1;
      New_Src_Buffer (Src_Index, Src_Handle, Src_Data_Stream);
      Dest_Index := Dest_Index + (Base_Udp.Load_Size - Base_Udp.Header_Size);
   exception
      when E : others =>
      Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
         Ada.Exceptions.Exception_Name (E)
         & ASCII.LF & ASCII.ESC & "[33m"
         & Ada.Exceptions.Exception_Message (E)
         & ASCII.ESC & "[0m");
   end Copy_Packet_Data_To_Dest;


   ------------------------
   --  Handle_Data_Task  --
   ------------------------

   task body Handle_Data_Task is
         use Ada.Streams;

         Dest_Buffer    : Buffers.Buffer_Produce_Access;

         Src_Handle     : Buffers.Buffer_Handle_Access := null;
         Dest_Handle    : Buffers.Buffer_Handle_Access := null;

         Packet_Nb          : Interfaces.Unsigned_64 := 0;

         Src_Index          : Interfaces.Unsigned_64 := 1;
         Dest_Index         : Stream_Element_Offset := 0;

         Buffer_Size        : Interfaces.Unsigned_32 := 0;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (5));

      accept Start (Buffer_Set : Buffers.Buffer_Produce_Access)
      do
         Dest_Buffer := Buffer_Set;
      end Start;
      delay 0.0;
      Src_Handle := new Buffers.Buffer_Handle_Type;
      Buffer_Cons.Get_Full_Buffer (Src_Handle.all);
      loop
         declare
            Src_Data_Stream    : Base_Udp.Sequence_Type;
            for Src_Data_Stream'Address use Buffers.Get_Address (Src_Handle.all);

            Header      : Reliable_Udp.Header_Type;
            Size        : Interfaces.Unsigned_32;
            for Header'Address use Src_Data_Stream (Src_Index)'Address;
            for Size'Address use Src_Data_Stream (Src_Index) (Base_Udp.Header_Size + 1)'Address;
            New_Buffer  : Boolean renames Header.Ack;
         begin
            Packet_Nb := Packet_Nb + 1;
            if New_Buffer then
               --  Loop if True which means that the buffer data is in next src_buffer
               --  and src_data_stream (declared above) has to be reload with new buffer.
               if New_Dest_Buffer (Dest_Buffer,
                                   Size,
                                   Buffer_Size,
                                   Packet_Nb,
                                   Src_Index,
                                   Src_Handle,
                                   Dest_Index,
                                   Dest_Handle,
                                   Src_Data_Stream) = False
               then
                  Copy_Packet_Data_To_Dest (Buffer_Size,
                          Src_Index,
                          Src_Handle,
                          Dest_Handle,
                          Dest_Index,
                          Src_Data_Stream);

               end if;
            else
               Copy_Packet_Data_To_Dest (Buffer_Size,
                       Src_Index,
                       Src_Handle,
                       Dest_Handle,
                       Dest_Index,
                       Src_Data_Stream);
            end if;

         end;
      end loop;
      exception
         when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Handle_Data_Task;


   --------------------------------
   --  Copy_To_Correct_Location  --
   --------------------------------

   procedure Copy_To_Correct_Location
                                 (I, Nb_Missed   : Interfaces.Unsigned_64;
                                  Data           : Base_Udp.Packet_Stream;
                                  Data_Addr      : System.Address) is

      use System.Storage_Elements;

      Good_Loc_Index :  constant Interfaces.Unsigned_64 := (I + Nb_Missed)
                           mod Base_Udp.Sequence_Size;
      Good_Location  :  Base_Udp.Packet_Stream;

      for Good_Location'Address use Data_Addr + Storage_Offset
                                 (Good_Loc_Index * Base_Udp.Load_Size);
   begin
      Good_Location := Data;
   end Copy_To_Correct_Location;

end Buffer_Handling;
