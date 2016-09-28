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

   use type Reliable_Udp.Pkt_Nb;

   Socket   : GNAT.Sockets.Socket_Type;
   Address  : GNAT.Sockets.Sock_Addr_Type;

   procedure Send_Packet (Packet_Nb : Base_Udp.Packet_Stream);
   procedure Rcv_Ack;

   --  procedure Server_HandShake;

   function To_Int is
      new Ada.Unchecked_Conversion (GNAT.Sockets.Socket_Type,
         Interfaces.C.int);

   --  procedure Server_HandShake is
   --     Data
   --  begin
   --    Send_Packet ();
   --  end Server_HandShake;

   procedure Send_Packet (Packet_Nb : Base_Udp.Packet_Stream) is
      Offset   : Ada.Streams.Stream_Element_Offset;
      Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);

      for Data'Address use Packet_Nb'Address;
      pragma Unreferenced (Offset);
   begin
      GNAT.Sockets.Send_Socket (Socket, Data, Offset, Address);
   end Send_Packet;


   procedure Rcv_Ack is
      Ack_U8   : Base_Udp.Packet_Stream;
      Head     : Reliable_Udp.Header;
      Ack      : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
      Data     : Ada.Streams.Stream_Element_Array (1 .. 64);
      Res      : Interfaces.C.int;

      for Ack'Address use Ack_U8'Address;
      for Data'Address use Ack'Address;
      for Head'Address use Ack'Address;
   begin
      loop
         Res := GNAT.Sockets.Thin.C_Recv
            (To_Int (Socket), Data (Data'First)'Address, Data'Length, 64);
         exit when Res = -1;
         Head.Ack := True;
         Send_Packet (Ack_U8);
      end loop;
   end Rcv_Ack;

begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Ada.Text_IO.Put_Line ("Usage : "
         & Ada.Command_Line.Command_Name
         & " [udp_server_ip] [port]");
      return;
   else
      Address.Addr := GNAT.Sockets.Inet_Addr
                        (Ada.Command_Line.Argument (1));
      Address.Port := GNAT.Sockets.Port_Type'Value
                        (Ada.Command_Line.Argument (2));
   end if;

   GNAT.Sockets.Create_Socket
      (Socket,
       GNAT.Sockets.Family_Inet,
       GNAT.Sockets.Socket_Datagram);

   declare
      Packet   : Base_Udp.Packet_Stream;

      Header   : Reliable_Udp.Header := (Ack => False, Seq_Nb => 0);
      Pkt_Data : Interfaces.Unsigned_64 := 0;

      for Pkt_Data'Address use Packet (5)'Address;
      for Header'Address use Packet'Address;
   begin
      loop
         Send_Packet (Packet);

         Rcv_Ack;

         if Header.Seq_Nb = Base_Udp.Pkt_Max then
            Header.Seq_Nb := 0;
         else
            Header.Seq_Nb := Header.Seq_Nb + 1;
         end if;

         Pkt_Data := Pkt_Data + 1;

      end loop;
   end;
end UDP_Client;
