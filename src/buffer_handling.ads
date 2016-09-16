with System;
with Interfaces;

with Reliable_Udp;
with Base_Udp;

with Buffers;

package Buffer_Handling is

   --  Number of pmh buffers initialized
   PMH_Buf_Nb     : constant := 15;

   --  Index Type for "Handlers" array
   --  "is mod type" enables a circular parsing
   type Handle_Index is mod PMH_Buf_Nb;

   --  State of Buffer:
   --  Empty =>  Buf is released
   --  Near_Full => Buf is waiting for acks
   --  Full => Ready to be Released
   type State_Enum is (Empty, Near_Full, Full);

   type Handler is limited
      record
         Handle    : Buffers.Buffer_Handle_Type;
         State     : State_Enum := Empty;
         Missing   : Base_Udp.Header := 0;
      end record;

   --  Contains all the Handlers
   type Handle_Array is array (Handle_Index) of Handler;

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Base_Udp.Packet_Stream);


   type Buf_Handler is
      record
         Handlers          : Handle_Array;
         First             : Handle_Index;
         Current           : Handle_Index;
      end record;

   --  Initialize "PMH_Buf_Nb" of Buffer and attach a buffer
   --  to each Handler of Handle_Array
   procedure Init_Buffers;

   --  Release Buffer at Handlers (Index) and change its State to Empty
   procedure Release_Free_Buffer_At (Index : in Handle_Index);

   --  Get Content of Released Buffers and Log it to File (buffers.log)
   --  or Display it. Depends on To_File Boolean.
   procedure Get_Filled_Buf (To_File   : in Boolean := True);


   --  Search position of ack received in current and previous buffers
   --  and then store content in it.
   function Search_Empty_Mark
                        (First, Last            : Handle_Index;
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

end Buffer_Handling;
