with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;
with System;

with Base_Udp;
with Buffers.Local;


package Packet_Mgr is

   type Buf_Handler is
      record
         Buffer      : aliased Buffers.Local.Local_Buffer_Type;
         Handle      : Handle_Vector.Vector;
         Prod_Cursor : Handle_Vector.Cursor;
      end record;

   package Handle_Vector is
      new Ada.Containers.Vectors (Natural,
         Buffers.Buffer_Handle_Access, Buffers."=");

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Base_Udp.Packet_Stream);


   procedure Init_Buffer;
   procedure Set_Used_Bytes_At (Cursor : Handle_Vector.Cursor;
                                Length : Integer);
   procedure Release_Free_Buffer_At (Cursor : Handle_Vector.Cursor);
   procedure Free_Buffer_Handle is
      new Ada.Unchecked_Deallocation
         (Buffers.Buffer_Handle_Type, Buffers.Buffer_Handle_Access);
   procedure Get_Filled_Buf;
   procedure Append_New_Buffer;

   task type Release_First_Buf is
      entry Release;
   end Release_First_Buf;

   task type PMH_Buffer_Addr is
      entry Stop;
      entry New_Buffer_Addr (Buffer_Ptr : in out System.Address);
   end PMH_Buffer_Addr;

end Packet_Mgr;
