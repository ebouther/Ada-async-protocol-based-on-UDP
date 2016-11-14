with Ada.Real_Time;
with Interfaces;
with System;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;
with Queue;

package Reliable_Udp is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   --  Stored in packet header to identify which packet was lost
   type Packet_Number_Type is mod 2 ** (Base_Udp.Header'Size - 1);

   --  Used to store lost packet and when it can be resend if needed
   type Loss_Type is
      record
         Is_Empty    : Boolean := True;
         Last_Ack    : Ada.Real_Time.Time;
         From        : GNAT.Sockets.Sock_Addr_Type;
      end record;

   type Loss_Index_Type is mod Base_Udp.Sequence_Size;

   --  Header used at packet payload begin to manage drops
   type Header_Type is
      record
         Seq_Nb      : Packet_Number_Type;
         Ack         : Boolean;
      end record;

   for Header_Type use
      record
         Seq_Nb   at 0 range 0 .. Packet_Number_Type'Size - 1;
         Ack      at 0 range Packet_Number_Type'Size .. Packet_Number_Type'Size;
      end record;

   for Header_Type'Alignment use Base_Udp.Header_Size;

   type Append_Ack_Type is
      record
         From     : GNAT.Sockets.Sock_Addr_Type;
         First_D  : Packet_Number_Type;
         Last_D   : Packet_Number_Type;
      end record;

   type Losses_Array_Type is array (Loss_Index_Type) of Loss_Type;


   protected type Ack_Management is

      procedure Set
                  (Index   : in Loss_Index_Type;
                   Data    : in Loss_Type);

      procedure Get
                  (Index   : in Loss_Index_Type;
                   Data    : in out Loss_Type);

      function  Get
                  (Index   : in Loss_Index_Type) return Loss_Type;

      procedure Clear
                  (Index   : in Loss_Index_Type);

      function  Is_Empty
                  (Index   : in Loss_Index_Type) return Boolean;

      private
         Losses            : Losses_Array_Type;

   end Ack_Management;

   type Ack_Management_Access is access Ack_Management;


   package Sync_Queue is new Queue (Append_Ack_Type);

   type Synchronized_Queue_Access is access Sync_Queue.Synchronized_Queue;

   --  ** Move Send_Cmd_To_Producer somewhere else.
   procedure Send_Cmd_To_Producer (Cmd       : Reliable_Udp.Packet_Number_Type;
                                   Prod_Addr : GNAT.Sockets.Sock_Addr_Type);

   procedure Append_Ack (Ack_Mgr          : in Ack_Management_Access;
                         First_D          : in Reliable_Udp.Packet_Number_Type;
                         Last_D           : in Reliable_Udp.Packet_Number_Type;
                         Client_Addr      : in GNAT.Sockets.Sock_Addr_Type);

   --  Send acks to client if it's necessary
   task type Ack_Task is
      pragma Priority (System.Priority'First);
      entry Start (Ack_M   : in Ack_Management_Access);
   end Ack_Task;

   --  Appends packets to Losses Array
   task type Append_Task is
      entry Start (Ack_M      : Ack_Management_Access;
                   Ack_Fifo   : Synchronized_Queue_Access);
   end Append_Task;

   --  Removes Packet_Number from Losses Array
   task type Remove_Task is
      entry Initialize (Ack_M : Ack_Management_Access);
      entry Remove (Packet : in Packet_Number_Type);
   end Remove_Task;

end Reliable_Udp;
