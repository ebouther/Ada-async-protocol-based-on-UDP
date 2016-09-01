with Base_Udp;

with Interfaces;
with Buffers;

package Packet_Mgr is

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

   task Consumer_Task;

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
