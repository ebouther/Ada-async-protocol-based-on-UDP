with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Streams;
with Interfaces;
with Interfaces.C;
with Ada.Unchecked_Conversion;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;
with Reliable_Udp;

procedure UDP_Client is
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;
   use type Interfaces.C.int;
   use type Ada.Streams.Stream_Element_Offset;

   type Jumbo_U8 is
      array (1 .. Base_Udp.Load_Size) of Interfaces.Unsigned_8;

      Address  : GNAT.Sockets.Sock_Addr_Type;
      Socket   : GNAT.Sockets.Socket_Type;
      Packet   : Jumbo_U8 := (others => 0);
      Ack_U8   : Jumbo_U8 := (others => 0);
      Pkt_Data : Interfaces.Unsigned_64 := 0;

      for Pkt_Data'Address use Packet (2)'Address;

      procedure Send_Packet (Packet_Nb : Jumbo_U8;
                             Ack       : Boolean);
      procedure Rcv_Ack;

      function To_Int is
         new Ada.Unchecked_Conversion (GNAT.Sockets.Socket_Type, Interfaces.C.int);

      procedure Send_Packet (Packet_Nb : Jumbo_U8;
                             Ack : Boolean) is
         Offset   : Ada.Streams.Stream_Element_Offset;
         Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
         Header   : Reliable_Udp.Header;

         for Data'Address use Packet_Nb'Address;
         for Header'Address use Data'Address;
         pragma Unreferenced (Offset);
      begin
         if Ack then
            Header.Ack := True;
         else
            Header.Ack := False;
         end if;
         GNAT.Sockets.Send_Socket (Socket, Data, Offset, Address);
      end Send_Packet;

      procedure Rcv_Ack is
         Ack      : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
         Data     : Ada.Streams.Stream_Element_Array (1 .. 64);
         Res      : Interfaces.C.int;
         for Data'Address use Ack'Address;
      begin
         Res := GNAT.Sockets.Thin.C_Recv
            (To_Int (Socket), Data (Data'First)'Address, Data'Length, 64);
         if Res /= -1 then
            ---------- DBG -----------
            Ada.Text_IO.Put_Line ("ACK [" & Res'Img & " ]: Dropped :" & Ack (1)'Img);
            --------------------------
            Ack_U8 (1) := Ack (1);
            Ack_U8 (2) := 1;
            Send_Packet (Ack_U8, True);
         end if;
      end Rcv_Ack;

begin
   Address.Port := 50001;
   if Ada.Command_Line.Argument_Count = 0 then
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
   else
      Address.Addr := GNAT.Sockets.Inet_Addr (Ada.Command_Line.Argument (1));
   end if;
   GNAT.Sockets.Create_Socket (Socket,
                               GNAT.Sockets.Family_Inet,
                               GNAT.Sockets.Socket_Datagram);
   loop
      Send_Packet (Packet, False);
      Rcv_Ack;
      if Packet (1) = Base_Udp.Pkt_Max then
         Packet (1) := 0;
      else
         Packet (1) := Packet (1) + 1;
      end if;
      Pkt_Data := Pkt_Data + 1;
      -- DBG --
      --  delay 0.00000001;
      ---------
   end loop;
end UDP_Client;
