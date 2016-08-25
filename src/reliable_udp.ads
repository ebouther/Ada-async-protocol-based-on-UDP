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
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   type Loss is
      record
         Packet      : Base_Udp.Header;
         Last_Ack    : Ada.Real_Time.Time;
         From        : GNAT.Sockets.Sock_Addr_Type;
      end record;

   type Header is
      record
         Ack         : Boolean;
         --  Packet      : Pkt_Nb;
      end record;

   for Header use
      record
         Ack      at Base_Udp.Header_Size - 1 range Base_Udp.Header'Size - 1 .. Base_Udp.Header'Size - 1;
         --  Packet   at 0 range 0 .. Base_Udp.Header_Size * 8 - 2;
      end record;

   for Header'Alignment use Base_Udp.Header_Size;

   package Rm_Container is
      new Ada.Containers.Vectors (Natural, Base_Udp.Header, Interfaces."=");

   package Losses_Container is
      new Ada.Containers.Vectors (Natural, Loss);

   task type Rm_Task is
      entry Start;
   end Rm_Task;

   task type Ack_Task is
      entry Start;
   end Ack_Task;

   task type Append_Task is
      entry Append (First_Dropped, Last_Dropped : Base_Udp.Header;
                   Client_Address               : GNAT.Sockets.Sock_Addr_Type);
   end Append_Task;

   task type Remove_Task is
      entry Remove (Packet : in Base_Udp.Header);
   end Remove_Task;

   protected type Ack_Management is
      procedure Init_Socket;
      procedure Append (Packet_Lost : in Loss);
      procedure Update_AckTime (Position  : in Losses_Container.Cursor;
                               Ack_Time   : in Ada.Real_Time.Time);
      procedure Remove;
      procedure Add_To_Remove_List (Packet : in Base_Udp.Header);
      procedure Ack;
      function Length return Ada.Containers.Count_Type;

      private
      Socket      : GNAT.Sockets.Socket_Type;
      Remove_List : Rm_Container.Vector;
      Losses      : Losses_Container.Vector;
   end Ack_Management;

end Reliable_Udp;
