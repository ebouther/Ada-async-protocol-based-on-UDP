with Interfaces;
with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;

with Base_Udp;
with Buffers.Local;


package Packet_Mgr is


   package Handle_Vector is
      new Ada.Containers.Vectors (Natural, Buffers.Buffer_Handle_Access, Buffers."=");

   type Buf_Handler is
      record
         Buffer      : aliased Buffers.Local.Local_Buffer_Type;
         Handle      : Handle_Vector.Vector;
         Prod_Cursor : Handle_Vector.Cursor;
      end record;

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Interfaces.Unsigned_64);

   --  type Container is
   --     record
   --        Buffer      : Sequence;
   --        Free_Space  : Base_Udp.Header := Base_Udp.Header (Base_Udp.Sequence_Size);
   --     end record;

   --  type Container_Ptr is access Container;

   --  type Containers is
   --     record
   --        Swap        : Container_Ptr := new Container;
   --        Near_Full   : Container_Ptr := new Container;
   --        Full        : Container_Ptr := new Container;
   --     end record;

   procedure Free_Buffer_Handle is
      new Ada.Unchecked_Deallocation
         (Buffers.Buffer_Handle_Type, Buffers.Buffer_Handle_Access);

   procedure Init_Buffer;
   procedure Append_New_Buffer;
   procedure Release_Free_Buffer_At (Cursor : Handle_Vector.Cursor);
   procedure Delete_Buffer_At (Cursor : in out Handle_Vector.Cursor);
   procedure Set_Used_Bytes_At (Cursor : Handle_Vector.Cursor;
                                Length : Integer);

   task Consumer_Task is
      entry Start;
   end Consumer_Task;

   task type Store_Packet_Task is
      entry Store (Data          : Base_Udp.Packet_Stream;
                   New_Sequence  : Boolean;
                   Is_Ack        : Boolean);
   end Store_Packet_Task;

  --   task type Container_To_CSV is
  --      entry Log (Buffer  : Container);
  --   end Container_To_CSV;


  --   protected type Buffer_Management is
  --      procedure Store_Packet (Data           : Base_Udp.Packet_Payload;
  --                              New_Sequence   : Boolean;
  --                              Is_Ack         : Boolean);

  --      private
  --         Pkt_Containers : Containers;
  --         --  Container_To_CSV_Task   : Container_To_CSV;
  --   end Buffer_Management;

end Packet_Mgr;
