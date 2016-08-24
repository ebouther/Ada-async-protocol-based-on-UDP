with Interfaces;

with Base_Udp;

package Packet_Mgr is

   type Packet_Content is
      array (1 .. Base_Udp.Load_Size)
         of Interfaces.Unsigned_8;

   type Sequence is
      array (1 .. Base_Udp.Sequence_Size)
         of Packet_Content;

   type Container is
      record
         Buffer      : Sequence;
         Free_Space  : Base_Udp.Header := Base_Udp.Sequence_Size;
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
