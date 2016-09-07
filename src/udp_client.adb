with Ada.Text_IO;
with Ada.Command_Line;
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
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Interfaces.C.int;
   use type Ada.Streams.Stream_Element_Offset;

   type Jumbo_U8 is
      array (1 .. Base_Udp.Load_Size) of Interfaces.Unsigned_8;

      Address  : GNAT.Sockets.Sock_Addr_Type;
      Socket   : GNAT.Sockets.Socket_Type;


      Packet   : Jumbo_U8 := (others => 0);
      Seq_Nb   : Base_Udp.Header := 0;
      Pkt_Data : Interfaces.Unsigned_64 := 0;

      for Pkt_Data'Address use Packet (5)'Address;
      for Seq_Nb'Address use Packet'Address;

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
         Seq      : Base_Udp.Header;

         for Seq'Address use Packet_Nb'Address;
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
         Ack_U8   : Jumbo_U8 := (others => 0);
         Header   : Reliable_Udp.Header;
         Ack      : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
         Seq      : Base_Udp.Header;
         Data     : Ada.Streams.Stream_Element_Array (1 .. 64);
         Res      : Interfaces.C.int;

         for Ack'Address use Ack_U8'Address;
         for Data'Address use Ack'Address;
         for Header'Address use Ack'Address;
         for Seq'Address use Data'Address;
      begin
         loop
            Res := GNAT.Sockets.Thin.C_Recv
               (To_Int (Socket), Data (Data'First)'Address, Data'Length, 64);
            exit when Res = -1;
            ---------- DBG -----------
            Ada.Text_IO.Put_Line ("ACK [" & Res'Img & " ]: Dropped :" & Seq'Img);
            --------------------------

            Send_Packet (Ack_U8, True);
         end loop;

      end Rcv_Ack;

begin
   Address.Port := 50001;
   if Ada.Command_Line.Argument_Count = 0 then
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
   else
      Address.Addr := GNAT.Sockets.Inet_Addr
                                 (Ada.Command_Line.Argument (1));
   end if;
   GNAT.Sockets.Create_Socket (Socket,
                               GNAT.Sockets.Family_Inet,
                               GNAT.Sockets.Socket_Datagram);
   loop
      Send_Packet (Packet, False);
      Rcv_Ack;
      if Seq_Nb = Base_Udp.Pkt_Max then
         Seq_Nb := 0;
      else
         Seq_Nb := Seq_Nb + 1;
      end if;
      Pkt_Data := Pkt_Data + 1;

      --  DBG --
      --  delay 0.000000001;
      ---------
   end loop;
end UDP_Client;
