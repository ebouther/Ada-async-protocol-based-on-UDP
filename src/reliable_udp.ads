with Ada.Real_Time;
with Ada.Containers.Vectors;
with Ada.Containers;
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

   Client_Address    : GNAT.Sockets.Sock_Addr_Type;

   --  Stored in packet header to identify which packet was lost
   type Pkt_Nb is mod 2 ** (Base_Udp.Header'Size - 1);

   --  Used to store lost packet and when it can be resend if needed
   type Loss is
      record
         Is_Empty    : Boolean := True;
         Last_Ack    : Ada.Real_Time.Time;
         From        : GNAT.Sockets.Sock_Addr_Type;
      end record;

   type Loss_Index is mod Base_Udp.Sequence_Size;

   type Losses_Array is array (Loss_Index) of Loss;

   --  Header used at packet payload begin to manage drops
   type Header is
      record
         Seq_Nb      : Pkt_Nb;
         Ack         : Boolean;
      end record;

   for Header use
      record
         Seq_Nb   at 0 range 0 .. Pkt_Nb'Size - 1;
         Ack      at 0 range Pkt_Nb'Size .. Pkt_Nb'Size;
      end record;

   for Header'Alignment use Base_Udp.Header_Size;

   --  Vector of "Loss" Type which stores acks
   package Losses_Container is
      new Ada.Containers.Vectors (Natural, Loss);

   type Append_Ack_Type is
      record
         From     : GNAT.Sockets.Sock_Addr_Type;
         First_D  : Reliable_Udp.Pkt_Nb;
         Last_D   : Reliable_Udp.Pkt_Nb;
      end record;

   package Sync_Queue is new Queue (Append_Ack_Type);

   Fifo  : Sync_Queue.Synchronized_Queue;

   procedure Send_Cmd_Client (Cmd : Pkt_Nb);

   procedure Append_Ack (First_D          : in Reliable_Udp.Pkt_Nb;
                         Last_D           : in Reliable_Udp.Pkt_Nb;
                         Client_Addr      : in GNAT.Sockets.Sock_Addr_Type);

   --  Send acks to client if it's necessary
   task type Ack_Task is
      pragma Priority (System.Priority'First);
      entry Start;
      entry Stop;
   end Ack_Task;

   --  Appends packets to Losses Container
   task Append_Task;

   --  Removes Pkt_Nb from Losses Container
   task type Remove_Task is
      entry Stop;
      entry Remove (Packet : in Pkt_Nb);
   end Remove_Task;

   protected type Ack_Management is

      procedure Set (Index    : in Loss_Index;
                     Data     : in Loss);

      procedure Get (Index : in Loss_Index;
                     Data  : in out Loss);

      function Get (Index : in Loss_Index) return Loss;

      procedure Clear (Index    : in Loss_Index);

      function Is_Empty (Index    : in Loss_Index) return Boolean;

      private
         Losses            : Losses_Array;
   end Ack_Management;

end Reliable_Udp;
