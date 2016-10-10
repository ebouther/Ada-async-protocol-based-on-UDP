with Ada.Text_IO;
with Ada.Exceptions;
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


   Buffer_Handler    : Buffer_Handler_Type;

   Production        : Buffers.Shared.Produce.Produce_Couple_Type;
   Buffer_Prod       : Buffers.Shared.Produce.Produce_Type
                           renames Production.Producer;

   Consumption       : Buffers.Shared.Consume.Consume_Couple_Type;
   Buffer_Cons       : Buffers.Shared.Consume.Consume_Type
                           renames Consumption.Consumer;


   --------------------
   --  Init_Buffers  --
   --------------------

   procedure Init_Buffers is
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
      Dcod_Pmh_Service.Client.Provide_Buffer (Name => Base_Udp.Buffer_Name,
                                              Size => Base_Udp.Buffer_Size,
                                              Depth => Base_Udp.PMH_Buf_Nb + 1,
                                              Endpoint => Base_Udp.End_Point);

      Ada.Text_IO.Put_Line ("Buffer   Size :" & Base_Udp.Buffer_Size'Img
         & " Depth : " & Integer (Base_Udp.PMH_Buf_Nb + 1)'Img);

      Buffer_Prod.Set_Name (Base_Udp.Buffer_Name);
      Production.Message_Handling.Start (1.0);
      Buffer_Cons.Set_Name (Base_Udp.Buffer_Name);
      Consumption.Message_Handling.Start (1.0);
      Buffer_Prod.Is_Initialised;

      Buffer_Handler.First := Buffer_Handler.Handlers'First;

      --  Current is incremented to First when Recv_Packets asks for new Buf
      Buffer_Handler.Current := Buffer_Handler.Handlers'Last;

      for I in Buffer_Handler.Handlers'Range loop
         Buffer_Prod.Get_Free_Buffer (Buffer_Handler.Handlers (I)
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

   procedure Release_Free_Buffer_At (Index : in Handle_Index_Type) is
      Unknown_Buffer_Size  : exception;
      Buf                  : Handler_Type
                              renames Buffer_Handler.Handlers (Index);
      use Base_Udp;
   begin
      if Buf.Size = 0 then
         Ada.Exceptions.Raise_Exception (Unknown_Buffer_Size'Identity,
            "Attempting to release a buffer with unknown size. Cannot Set_Used_Bytes.");
      end if;
      Ada.Text_IO.Put_Line ("Recv_Buf Size : " & Buf.Size'Img);
      Ada.Text_IO.Put_Line ("Set_Used_Bytes : " & Integer (Buf.Size +
               (Buf.Size / Load_Size
                  + (if Buf.Size rem Load_Size /= 0 then
                     1 else 0))
               * Header_Size)'Img);

      Buffers.Set_Used_Bytes
         (Buf.Handle,
            Buffers.Buffer_Size_Type
               (Buf.Size +
               (Buf.Size / Load_Size
                  + (if Buf.Size rem Load_Size /= 0 then
                     1 else 0))
               * Header_Size));

      Buffer_Prod.Release_Free_Buffer (Buf.Handle);
      Buf.State := Empty;
      Buf.Size := 0;

   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Release_Free_Buffer_At;


  ---------------------------
  --  Check_Buf_Integrity  --
  ---------------------------

   task body Check_Buf_Integrity is
      Index : Handle_Index_Type := Handle_Index_Type'First;
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


  ------------------------
  --  Release_Full_Buf  --
  ------------------------

   task body Release_Full_Buf is
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (11));
      accept Start;
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
            accept New_Buffer_Addr (Buffer_Ptr   : in out System.Address)
            do
               if Buffer_Handler.Current + 1 = Buffer_Handler.First
                  and not Init
               then
                  Ada.Exceptions.Raise_Exception (Not_Released_Fast_Enough'Identity,
                     "All buffers are used. Make sure a consumer was launched.");
               end if;
               Buffer_Ptr := Buffer_Handler.Handlers
                                (Buffer_Handler.Current + 1).
                                    Handle.Get_Address;
            end New_Buffer_Addr;
               if not Init then
                  Buffer_Handler.Handlers (Buffer_Handler.Current).
                                                      State := Near_Full;
               end if;
               Buffer_Handler.Current := Buffer_Handler.Current + 1;
               Init := False;
               Ada.Text_IO.Put_Line ("Current : " & Buffer_Handler.Current'Img);
         end select;
      end loop;
   exception
      when E : others =>

         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end PMH_Buffer_Addr;


   -------------------------
   --  Search_Empty_Mark  --
   -------------------------

   function Search_Empty_Mark
                        (First, Last           : Handle_Index_Type;
                         Data                  : in Base_Udp.Packet_Stream;
                         Seq_Nb                : Reliable_Udp.Pkt_Nb) return Boolean
   is

      use Packet_Buffers;
      use System.Storage_Elements;
      use type Reliable_Udp.Pkt_Nb;
      use type Handle_Index_Type;
   begin
      for N in First .. Last loop
         declare
            type Data_Array is new Element_Array
               (1 .. Integer (Base_Udp.Sequence_Size));

            Datas    : Data_Array;
            Content  : Interfaces.Unsigned_32;

            for Datas'Address use Buffer_Handler.Handlers (N)
               .Handle.Get_Address;
            for Content'Address use Datas (Integer (Seq_Nb) + 1)'Address;
         begin
            if Content = 16#DEAD_BEEF# then
               Datas (Integer (Seq_Nb) + 1) := Data;
               return True;
            end if;
         end;
      end loop;
      return False;
   end Search_Empty_Mark;


   -----------------
   --  Save_Size  --
   -----------------

   procedure Save_Size (Data           : Ada.Streams.Stream_Element_Array;
                        Recv_Offset    : in out Interfaces.Unsigned_64) is

      Prod_Buf_Too_Big  : exception;

      Size     : Interfaces.Unsigned_32;
      Max_Size : Interfaces.Unsigned_32;
      Index    : constant Handle_Index_Type := Buffer_Handler.Current;
      for Size'Address use Data'Address;

      Offset   : Handle_Index_Type := 1;
   begin
      Max_Size := Interfaces.Unsigned_32
         (Base_Udp.Sequence_Size * (Base_Udp.Load_Size - Base_Udp.Header_Size));

      --  Producer has bigger buffer than the one used to receive packets.
      --  It may overlap several buffers
      --  if Buffer_Handler.Handlers (Buffer_Handler.Current).Size /= 0 then
      --     --  Would mean that several size informations were received for the same buffer
      --     Ada.Text_IO.Put_Line ("? Should not HAPPEN ?");
      --     Index := Buffer_Handler.Current + 1;
      --  end if;

      Buffer_Handler.Handlers (Index).Size := Size;

      if Size > Max_Size then
         Ada.Text_IO.Put_Line ("!!!! Size > Max_Size !!!" & Size'Img & Max_Size'Img);

         --  Store a size that exceed max_size to know that next packet(s)
         --  belong to the same buffer
         while Size > 0 loop
            pragma Warnings (Off);
            Size := Size - Max_Size;
            pragma Warnings (On);
            if Index + Offset = Buffer_Handler.Current then
               raise Prod_Buf_Too_Big
                  with "Unable to store all producer's buffer data."
                  & "Consider initializing more buffers with less data per buffer"
                  & "or incrementing Base_Udp.PMH_Buf_Nb constant.";
            end if;
            Buffer_Handler.Handlers (Index + Offset).Size := Size;
            Offset := Offset + 1;
         end loop;
      else
         --  If it's not already a new buffer.
         if Recv_Offset /= 0 then
            --  Forces to use a new buffer for the next packets.
            Recv_Offset := Base_Udp.Pkt_Max + 1;
         end if;
      end if;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Save_Size;


   ----------------
   --  Save_Ack  --
   ----------------

   procedure Save_Ack (Seq_Nb          :  in Reliable_Udp.Pkt_Nb;
                       Packet_Number   :  in Reliable_Udp.Pkt_Nb;
                       Data            :  in Base_Udp.Packet_Stream) is

      Location_Not_Found   : exception;
      use type Reliable_Udp.Pkt_Nb;
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


   ------------------------
   --  Handle_Data_Task  --
   ------------------------

   task body Handle_Data_Task is
         Dest_Buffer : Buffers.Buffer_Produce_Access;
         --  Size        : Integer := 0;

         Dest_Buffer_Too_Small   : exception;
         use Ada.Streams;
   begin
      accept Start (Buffer_Set : Buffers.Buffer_Produce_Access)
      do
         Dest_Buffer := Buffer_Set;
      end Start;
      loop
         delay 0.0;

         declare
            Src_Handle  : Buffers.Buffer_Handle_Type;
            Dest_Handle : Buffers.Buffer_Handle_Type;
         begin
            Dest_Buffer.Get_Free_Buffer (Dest_Handle);
            --  accept New_Src_Buffer (Buf_Size  : Integer) do
            --     Size := Buf_Size;
            --  end New_Src_Buffer;
            Buffer_Cons.Get_Full_Buffer (Src_Handle);

            declare
               Src_Data_Stream    : Stream_Element_Array
                                     (1 .. Stream_Element_Offset
                                             (Buffers.Get_Used_Bytes (Src_Handle)));
               Dest_Data_Stream   : Stream_Element_Array
                                     (1 .. Stream_Element_Offset
                                             (Buffers.Get_Available_Bytes (Dest_Handle)));

               Src_Index          : Stream_Element_Offset := Base_Udp.Header_Size;
               Dest_Index         : Stream_Element_Offset := 0;

               Dest_Size          : Integer := 0;

               for Src_Data_Stream'Address use Buffers.Get_Address (Src_Handle);
               for Dest_Data_Stream'Address use Buffers.Get_Address (Dest_Handle);

               First              : Integer;
               for First'Address use Src_Data_Stream (3)'Address;

            begin
               Ada.Text_IO.Put_Line ("FIRST : " & First'Img);
               loop
                  exit when Src_Index > Src_Data_Stream'Last;
                  --  There might be a better alternative than byte copy.
                  for I in Stream_Element_Offset range 1 .. Base_Udp.Load_Size - Base_Udp.Header_Size loop
                     exit when Src_Index + I > Src_Data_Stream'Last;
                     if (Dest_Index + I) > Dest_Data_Stream'Last then
                        Ada.Text_IO.Put_Line ("Dest Last : " & Dest_Data_Stream'Last'Img);
                        Ada.Text_IO.Put_Line ("Dest_Index + I : " & Integer (Dest_Index + I)'Img);
                        Ada.Text_IO.Put_Line ("Src Last : " & Src_Data_Stream'Last'Img);
                        Ada.Text_IO.Put_Line ("Src_Index + I : " & Integer (Src_Index + I)'Img);
                        raise Dest_Buffer_Too_Small
                           with "Cannot store all received data in buffer. Increase its size.";
                     end if;
                     Dest_Data_Stream (Dest_Index + I) := Src_Data_Stream (Src_Index + I);
                     --  Ada.Text_IO.Put_Line ("Copy Src (" & Integer (Src_Index + I)'Img & ") In : "
                     --     & Integer (Dest_Index + I)'Img);
                     Dest_Size := Dest_Size + 1;
                  end loop;
                  --  Ada.Text_IO.Put_Line ("*********************************************");
                  Src_Index := Src_Index + Base_Udp.Load_Size;
                  Dest_Index := Dest_Index + (Base_Udp.Load_Size - Base_Udp.Header_Size);
               end loop;
               Buffers.Set_Used_Bytes (Dest_Handle,
                                       Buffers.Buffer_Size_Type (Dest_Size));
               Dest_Buffer.Release_Free_Buffer (Dest_Handle);
               Buffer_Cons.Release_Full_Buffer (Src_Handle);
               Ada.Text_IO.Put_Line ("Released");
            exception
               when E : others =>
               Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
                  Ada.Exceptions.Exception_Name (E)
                  & ASCII.LF & ASCII.ESC & "[33m"
                  & Ada.Exceptions.Exception_Message (E)
                  & ASCII.ESC & "[0m");
            end;
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


   ----------------------
   --  Get_Filled_Buf  --
   ----------------------

   procedure Get_Filled_Buf (To_File   : in Boolean := True) is
      Log_File : Ada.Text_IO.File_Type;
   begin
      declare
         Handle         : Buffers.Buffer_Handle_Type;

         use Packet_Buffers;
      begin
         select
            Buffer_Cons.Get_Full_Buffer (Handle);
            Ada.Text_IO.Put_Line ("+++++++++++ Got A Buffer +++++++++++");
         or
            delay 1.0;
            Ada.Text_IO.Put_Line ("/!\ Error : Cannot Get A Full Buffer /!\");
            return;
         end select;

         if To_File then
            Ada.Text_IO.Open
               (Log_File, Ada.Text_IO.Append_File, "buffers.log");
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
                  Pkt_U8      : array (1 .. Base_Udp.Load_Size)
                                 of Interfaces.Unsigned_8;
                  Pkt_Nb      : Base_Udp.Header;
                  Content     : Interfaces.Unsigned_64;
                  Dead_Beef   : Interfaces.Unsigned_32;

                  for Pkt_Nb'Address use Datas (I)'Address;
                  for Dead_Beef'Address use Datas (I)'Address;
                  for Pkt_U8'Address use Datas (I)'Address;
                  for Content'Address use Pkt_U8 (5)'Address;
               begin
                  if Dead_Beef = 16#DEAD_BEEF# then
                     if To_File then
                        Ada.Text_IO.Put_Line
                           (Log_File, "Buffer (" & I'Img
                              & " ) : ** DROPPED **");
                     else
                        Ada.Text_IO.Put_Line ("Buffer (" & I'Img
                           & " ) : ** DROPPED **");
                     end if;
                  else
                     if To_File then
                        Ada.Text_IO.Put_Line
                           (Log_File, "Buffer (" & I'Img & " ) :" &
                              Pkt_Nb'Img & Content'Img);
                     else
                        Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) :" &
                           Pkt_Nb'Img & Content'Img);
                     end if;
                  end if;

               end;
            end loop;
         end;

         Buffer_Cons.Release_Full_Buffer (Handle);
         if To_File then
            Ada.Text_IO.Close (Log_File);
         end if;

      exception
         when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
      end;
   end Get_Filled_Buf;


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
