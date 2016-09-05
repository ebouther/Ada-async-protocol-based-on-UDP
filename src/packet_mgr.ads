with Interfaces;
with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;

with Base_Udp;
with Buffers.Local;


package Packet_Mgr is

   package Handle_Vector is
      new Ada.Containers.Vectors (Natural,
         Buffers.Buffer_Handle_Access, Buffers."=");

   type Buf_Handler is
      record
         Buffer      : aliased Buffers.Local.Local_Buffer_Type;
         Handle      : Handle_Vector.Vector;
         Prod_Cursor : Handle_Vector.Cursor;
      end record;

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Interfaces.Unsigned_64);

   procedure Free_Buffer_Handle is
      new Ada.Unchecked_Deallocation
         (Buffers.Buffer_Handle_Type, Buffers.Buffer_Handle_Access);
   procedure Init_Buffer;
   procedure Append_New_Buffer;
   procedure Release_Free_Buffer_At (Cursor : Handle_Vector.Cursor);
   procedure Set_Used_Bytes_At (Cursor : Handle_Vector.Cursor;
                                Length : Integer);
   procedure Get_Filled_Buf;


   task type Store_Packet_Task is
      entry Stop;
      entry Store (Data          : Base_Udp.Packet_Stream_Ptr;
                   New_Sequence  : Boolean;
                   Is_Ack        : Boolean);
   end Store_Packet_Task;

end Packet_Mgr;
