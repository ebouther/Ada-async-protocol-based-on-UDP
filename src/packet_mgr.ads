with Interfaces;

with Base_Udp;
with Buffers.Local;

package Packet_Mgr is

   package Unsigned_32_Buffers is new
     Buffers.Generic_Buffers (Element_Type => Interfaces.Unsigned_32);

   task type Producer_Task
     (Buffer : Buffers.Local.Local_Buffer_Access) is
     entry Start;
     entry Stop;
   end Producer_Task;

   task type Consumer_Task
     (Buffer : Buffers.Local.Local_Buffer_Access) is
     entry Start;
     entry Stop;
   end Consumer_Task;

   type Packet_Content is
      array (1 .. Base_Udp.Load_Size)
         of Interfaces.Unsigned_8;

   type Sequence is
      array (1 .. Base_Udp.Sequence_Size)
         of Packet_Content;

   type Container is
      record
         Buffer      : Sequence;
         Free_Space  : Base_Udp.Header := Base_Udp.Header (Base_Udp.Sequence_Size);
      end record;

   type Container_Ptr is access Container;

   type Containers is
      record
         Swap        : Container_Ptr := new Container;
         Near_Full   : Container_Ptr := new Container;
         Full        : Container_Ptr := new Container;
      end record;

   task type Store_Packet_Task is
      entry Store (Data          : Packet_Content;
                   New_Sequence  : Boolean;
                   Is_Ack        : Boolean);
   end Store_Packet_Task;

  --   task type Container_To_CSV is
  --      entry Log (Buffer  : Container);
  --   end Container_To_CSV;


   protected type Buffer_Management is
      procedure Store_Packet (Data           : Packet_Content;
                              New_Sequence   : Boolean;
                              Is_Ack         : Boolean);

      private
         Pkt_Containers : Containers;
         --  Container_To_CSV_Task   : Container_To_CSV;
   end Buffer_Management;

end Packet_Mgr;
