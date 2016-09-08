with Ada.Real_Time;
with Ada.Containers.Vectors;
with Ada.Containers;
with Interfaces;
with System;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;

package Reliable_Udp is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   type Pkt_Nb is mod 2 ** (Base_Udp.Header'Size - 1);

   type Loss is
      record
         Packet      : Pkt_Nb;
         Last_Ack    : Ada.Real_Time.Time;
         From        : GNAT.Sockets.Sock_Addr_Type;
      end record;

   type Header is
      record
         Seq_Nb      : Pkt_Nb;
         Ack         : Boolean;
      end record;

   for Header use
      record
         Seq_Nb   at 0 range 0 .. Base_Udp.Header'Size - 2;
         Ack      at 0 range Base_Udp.Header'Size - 1 .. Base_Udp.Header'Size - 1;
      end record;

   for Header'Alignment use Base_Udp.Header_Size;

   package Losses_Container is
      new Ada.Containers.Vectors (Natural, Loss);

   task type Ack_Task is
      pragma Priority (System.Priority'First);
      entry Start;
      entry Stop;
   end Ack_Task;

   task type Append_Task is
      entry Stop;
      entry Append (First_Dropped, Last_Dropped : Base_Udp.Header;
                   Client_Address               : GNAT.Sockets.Sock_Addr_Type);
   end Append_Task;

   task type Remove_Task is
      entry Stop;
      entry Remove (Packet : in Pkt_Nb);
   end Remove_Task;

   protected type Ack_Management is
      procedure Init_Socket;
      procedure Append (Packet_Lost : in Loss);
      procedure Update_AckTime (Position  : in Losses_Container.Cursor;
                               Ack_Time   : in Ada.Real_Time.Time);
      procedure Remove (Packet   : Pkt_Nb);
      procedure Ack;
      function Length return Ada.Containers.Count_Type;

      private
      Socket      : GNAT.Sockets.Socket_Type;
      Losses      : Losses_Container.Vector;
   end Ack_Management;

end Reliable_Udp;
