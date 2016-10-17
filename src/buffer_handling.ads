with Ada.Streams;
with System;
with Interfaces.C;

with Reliable_Udp;
with Base_Udp;

with Buffers;

package Buffer_Handling is

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Base_Udp.Packet_Stream);

   --  Index Type for "Handlers" array
   --  "is mod type" enables a circular parsing
   type Handle_Index_Type is mod Base_Udp.PMH_Buf_Nb;

   --  State of Buffer:
   --  Empty =>  Buf is released
   --  Near_Full => Buf is waiting for acks
   --  Full => Ready to be Released
   type State_Enum_Type is (Empty, Near_Full, Full);

   type Handler_Type is limited
      record
         Handle            : Buffers.Buffer_Handle_Type;
         --  First_Sub_Buf_Pos : Reliable_Udp.Pkt_Nb; --  [CTL] First Size Location, Size_Pos + Size to get next size
         State             : State_Enum_Type := Empty;
      end record;

   --  Contains all the Handlers
   type Handle_Array_Type is array (Handle_Index_Type) of Handler_Type;

   type Buffer_Handler_Type is
      record
         Handlers          : Handle_Array_Type;
         First             : Handle_Index_Type;
         Current           : Handle_Index_Type;
      end record;

   procedure Perror (Message : String);
   pragma Import (C, Perror, "perror");

   function mlockall (Flags : Interfaces.C.int)
      return Interfaces.C.int;
   pragma Import (C, mlockall, "mlockall");

   function mlock (Addr : System.Address;
                   Len  : Interfaces.C.size_t)
      return Interfaces.C.int;
   pragma Import (C, mlock, "mlock");

   --  Initialize "PMH_Buf_Nb" of Buffer and attach a buffer
   --  to each Handler of Handle_Array
   procedure Init_Buffers;

   --  Release Buffer at Handlers (Index) and change its State to Empty
   procedure Release_Free_Buffer_At (Index : in Handle_Index_Type);

   --  Get Content of Released Buffers and Log it to File (buffers.log)
   --  or Display it. Depends on To_File Boolean.
   procedure Get_Filled_Buf (To_File   : in Boolean := True);


   --  Search position of ack received in current and previous buffers
   --  and then store content in it.
   function Search_Empty_Mark
                        (First, Last            : Handle_Index_Type;
                         Data                   : in Base_Udp.Packet_Stream;
                         Seq_Nb                 : Reliable_Udp.Pkt_Nb) return Boolean;

   procedure Save_Ack (Seq_Nb          :  in Reliable_Udp.Pkt_Nb;
                       Packet_Number   :  in Reliable_Udp.Pkt_Nb;
                       Data            :  in Base_Udp.Packet_Stream);

   --  Move Data Received to good location (Nb_Missed Offset) if packets
   --  were dropped
   procedure Copy_To_Correct_Location
                      (I, Nb_Missed   : Interfaces.Unsigned_64;
                       Data           : Base_Udp.Packet_Stream;
                       Data_Addr      : System.Address);

   --  Write 16#DEAD_BEEF# at missed packets location.
   --  Enables Search_Empty_Mark to save ack in correct Cell
   procedure Mark_Empty_Cell (I           :  Interfaces.Unsigned_64;
                              Data_Addr   :  System.Address;
                              Last_Addr   :  System.Address;
                              Nb_Missed   :  Interfaces.Unsigned_64);

   function New_Dest_Buffer (Dest_Buffer     : Buffers.Buffer_Produce_Access;
                             Size            : Interfaces.Unsigned_32;
                             Buffer_Size     : in out Interfaces.Unsigned_32;
                             Packet_Nb       : in out Interfaces.Unsigned_64;
                             Src_Index       : in out Interfaces.Unsigned_64;
                             Src_Handle      : in out Buffers.Buffer_Handle_Access;
                             Dest_Size       : in out Interfaces.Unsigned_64;
                             Dest_Index      : in out Ada.Streams.Stream_Element_Offset;
                             Dest_Handle     : in out Buffers.Buffer_Handle_Access;
                             Src_Data_Stream : Base_Udp.Sequence_Type) return Integer;

   --  Src_Handle get a new Src_Buffer if it's necessary returns 1 otherwise 0
   function New_Src_Buffer (Src_Index       : in out Interfaces.Unsigned_64;
                            Src_Handle      : in out Buffers.Buffer_Handle_Access;
                            Src_Data_Stream : Base_Udp.Sequence_Type) return Integer;

   procedure  New_Src_Buffer (Src_Index       : in out Interfaces.Unsigned_64;
                              Src_Handle      : in out Buffers.Buffer_Handle_Access;
                              Src_Data_Stream : Base_Udp.Sequence_Type);

   procedure Copy_Packet_Data_To_Dest (Buffer_Size     : Interfaces.Unsigned_32;
                                       Src_Index       : in out Interfaces.Unsigned_64;
                                       Src_Handle      : in out Buffers.Buffer_Handle_Access;
                                       Dest_Handle     : Buffers.Buffer_Handle_Access;
                                       Dest_Index      : in out Ada.Streams.Stream_Element_Offset;
                                       Dest_Size       : in out Interfaces.Unsigned_64;
                                       Src_Data_Stream : Base_Udp.Sequence_Type);

   --  Release Buffer and Reuse Handler only if Buffer State is "Full"
   task type Release_Full_Buf is
      entry Start;
   end Release_Full_Buf;

   --  Get the address of a New Buffer
   task type PMH_Buffer_Addr is
      entry Stop;
      entry New_Buffer_Addr (Buffer_Ptr : in out System.Address);
   end PMH_Buffer_Addr;

   --  Change Buffer State from "Near_Full" to "Full" only if it contains
   --  all Packets
   task type Check_Buf_Integrity is
      entry Start;
   end Check_Buf_Integrity;

   --  procedure Save_Size_Pos (Seq_Pos :  Reliable_Udp.Pkt_Nb);
   --  pragma Inline (Save_Size_Pos);

   task type Handle_Data_Task is
      entry Start (Buffer_Set : Buffers.Buffer_Produce_Access);
   end Handle_Data_Task;

end Buffer_Handling;
