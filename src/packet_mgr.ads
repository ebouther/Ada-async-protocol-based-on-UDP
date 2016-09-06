with System;

with Base_Udp;
with Buffers.Local;


package Packet_Mgr is

   type Handle_Index is mod Base_Udp.PMH_Buf_Nb;

   type State_Enum is (Empty, Near_Full, Full);

   type Handler is
      record
         Handle   : Buffers.Buffer_Handle_Type;
         State    : State_Enum := Empty;
      end record;

   --  Do not forget to check if current = first after a complete cycle
   --  as Index_Handle is used in a circular way. Must not happen.
   type Handle_Array is array (1 .. Base_Udp.PMH_Buf_Nb) of Handler;

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Base_Udp.Packet_Stream);

   type Buf_Handler is
      record
         Buffer      : aliased Buffers.Local.Local_Buffer_Type;
         Handle      : Handle_Array;
         First       : Handle_Index;
         Current     : Handle_Index;
      end record;

   procedure Init_Handle_Array;
   procedure Release_Free_Buffer_At (Index : Handle_Index);
   procedure Get_Filled_Buf;

   --  task Release_Full_Buf;

   task type PMH_Buffer_Addr is
      entry Stop;
      entry New_Buffer_Addr (Buffer_Ptr : in out System.Address);
   end PMH_Buffer_Addr;

end Packet_Mgr;
