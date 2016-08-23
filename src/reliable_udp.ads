with Ada.Real_Time;
with Ada.Containers.Vectors;
with Ada.Containers;

with Interfaces;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;

package Reliable_Udp is

   use type Interfaces.Unsigned_8;

   type Loss is
      record
         Packet      : Interfaces.Unsigned_8;
         Last_Ack    : Ada.Real_Time.Time;
         From        : GNAT.Sockets.Sock_Addr_Type;
         --  Buffer_Ptr  : System.Address;
      end record;

   --  type Pkt_Nb is range 0 .. 7;

   type Header is
      record
         Ack         : Boolean;
         --  Packet      : Pkt_Nb;
      end record;

   for Header use
      record
         Ack      at 0 range 7 .. 7;
         --  Packet   at 0 range 0 .. Base_Udp.Header_Size * 8 - 2;
      end record;

   for Header'Alignment use Base_Udp.Header_Size;

   package Rm_Container is
      new Ada.Containers.Vectors (Natural, Interfaces.Unsigned_8);

   package Losses_Container is
      new Ada.Containers.Vectors (Natural, Loss);

   task type Rm_Task is
      entry Start;
   end Rm_Task;

   task type Ack_Task is
      entry Start;
   end Ack_Task;

   task type Append_Task is
      entry Append (First_Dropped, Last_Dropped : Interfaces.Unsigned_8;
                   Client_Address               : GNAT.Sockets.Sock_Addr_Type);
   end Append_Task;

   task type Remove_Task is
      entry Remove (Packet : in Interfaces.Unsigned_8);
   end Remove_Task;

   protected type Ack_Management is
      procedure Init_Socket;
      procedure Append (Packet_Lost : in Loss);
      procedure Update_AckTime (Position  : in Losses_Container.Cursor;
                               Ack_Time   : in Ada.Real_Time.Time);
      procedure Remove;
      procedure Add_To_Remove_List (Packet : in Interfaces.Unsigned_8);
      procedure Ack;
      function Length return Ada.Containers.Count_Type;

      private
      Socket      : GNAT.Sockets.Socket_Type;
      Remove_List : Rm_Container.Vector;
      Losses      : Losses_Container.Vector;
   end Ack_Management;

end Reliable_Udp;
