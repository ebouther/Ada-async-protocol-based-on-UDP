with Ada.Streams;
with Ada.Exceptions;
with System.Multiprocessors.Dispatching_Domains;
with Ada.Text_IO;

package body Reliable_Udp is

   Ack_Mgr        : Ack_Management;

   Socket         : GNAT.Sockets.Socket_Type;


   ----------------------------
   --  Send_Cmd_To_Producer  --
   ----------------------------

   procedure Send_Cmd_To_Producer (Cmd : Reliable_Udp.Packet_Number_Type) is
      Data        : Ada.Streams.Stream_Element_Array (1 .. Reliable_Udp.Header_Type'Size);
      Head        : Reliable_Udp.Header_Type;
      Offset      : Ada.Streams.Stream_Element_Offset;
      for Head'Address use Data'Address;
      pragma Unreferenced (Offset);
   begin
      Head.Seq_Nb := Cmd;
      Head.Ack    := False;
      GNAT.Sockets.Send_Socket (Socket, Data, Offset, Producer_Address);
   end Send_Cmd_To_Producer;


   ------------------
   --  Append_Ack  --
   ------------------

   procedure Append_Ack (First_D          : in Reliable_Udp.Packet_Number_Type;
                         Last_D           : in Reliable_Udp.Packet_Number_Type;
                         Client_Addr      : in GNAT.Sockets.Sock_Addr_Type)
   is
      Packet_Lost                      : Reliable_Udp.Loss_Type;
      Missed_2_Times_Same_Seq_Number   : exception;
      use type Ada.Real_Time.Time;
   begin
      for I in Reliable_Udp.Packet_Number_Type range First_D .. Last_D loop
         Packet_Lost.Last_Ack := Ada.Real_Time.Clock -
            Ada.Real_Time.Microseconds (Base_Udp.RTT_US_Max);
         Packet_Lost.From := Client_Addr;
         if not Ack_Mgr.Is_Empty (Loss_Index_Type (I)) then
            Ada.Text_IO.Put_Line
               ("/!\ Two packets with the same number:" & I'Img  & " were dropped /!\");
            raise Missed_2_Times_Same_Seq_Number;
         end if;
         Ack_Mgr.Set (Loss_Index_Type (I), Packet_Lost);
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Append_Ack;


   -------------------
   --  Append_Task  --
   -------------------

   task body Append_Task is
      Ack   :  Append_Ack_Type;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (6));
      loop
         Fifo.Remove_First_Wait (Ack);
         if Ack.First_D <= Ack.Last_D then
            Append_Ack (Ack.First_D, Ack.Last_D, Ack.From);
         else
            Append_Ack (Ack.First_D, Base_Udp.Pkt_Max, Ack.From);
            Append_Ack (Reliable_Udp.Packet_Number_Type'First, Ack.Last_D, Ack.From);
         end if;
      end loop;
   end Append_Task;


   -------------------
   --  Remove_Task  --
   -------------------

   task body Remove_Task is
      Pkt   : Packet_Number_Type;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (7));
      loop
         select
            accept Stop;
            exit;
         or
            accept Remove (Packet : in Packet_Number_Type) do
               Pkt   := Packet;
            end Remove;
            Ack_Mgr.Clear (Loss_Index_Type (Pkt));
         end select;
      end loop;
   end Remove_Task;


   ----------------
   --  Ack_Task  --
   ----------------

   --  Issue: Prevent from receiving packets when two much acks
   --  which create even more acks...
   task body Ack_Task is
      Ack_Array   : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
      Head        : Reliable_Udp.Header_Type;
      Data        : Ada.Streams.Stream_Element_Array (1 .. 64);
      Offset      : Ada.Streams.Stream_Element_Offset;
      Element     : Loss_Type;
      Index       : Loss_Index_Type := Loss_Index_Type'First;

      for Data'Address use Ack_Array'Address;
      for Head'Address use Ack_Array'Address;
      use type Ada.Real_Time.Time;
      use type Ada.Real_Time.Time_Span;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (8));

      GNAT.Sockets.Create_Socket (Socket,
                                  GNAT.Sockets.Family_Inet,
                                  GNAT.Sockets.Socket_Datagram);
      accept Start;
      loop
         delay 0.0;
         select
            accept Stop;
               exit;
         else
            if not Ack_Mgr.Is_Empty (Index) then
               Element := Ack_Mgr.Get (Index);
               if Ada.Real_Time.Clock - Element.Last_Ack >
                  Ada.Real_Time.Microseconds (Base_Udp.RTT_US_Max)
               then
                  Element.Last_Ack := Ada.Real_Time.Clock;
                  Ack_Mgr.Set (Index, Element);
                  Head.Seq_Nb := Packet_Number_Type (Index);
                  Head.Ack := True;
                  GNAT.Sockets.Send_Socket (Socket, Data, Offset, Element.From);
               end if;
            end if;
            Index := Index + 1;
         end select;
      end loop;
   end Ack_Task;


   protected body Ack_Management is


      -----------
      --  Set  --
      -----------

      procedure Set (Index    : in Loss_Index_Type;
                     Data     : in Loss_Type) is
      begin
         Losses (Index) := Data;
         Losses (Index).Is_Empty := False;
      end Set;


      -----------
      --  Get  --
      -----------

      procedure Get (Index : in Loss_Index_Type;
                     Data  : in out Loss_Type) is
      begin
         Data := Losses (Index);
      end Get;

      function Get (Index : in Loss_Index_Type) return Loss_Type is
      begin
         return Losses (Index);
      end Get;


      -------------
      --  Clear  --
      -------------

      procedure Clear (Index    : in Loss_Index_Type) is
      begin
         Losses (Index).Is_Empty := True;
      end Clear;


      ----------------
      --  Is_Empty  --
      ----------------

      function Is_Empty (Index    : in Loss_Index_Type) return Boolean is
      begin
         return Losses (Index).Is_Empty;
      end Is_Empty;


   end Ack_Management;

end Reliable_Udp;
