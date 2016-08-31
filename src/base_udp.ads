with Interfaces;
with System;

package Base_Udp is

   use type Interfaces.Unsigned_64;

   subtype Header is Interfaces.Unsigned_16;

   Load_Size      : constant := 8972;
   Array_Size     : constant := Load_Size / 4;
   RTT_MS_Max     : constant := 107; -- Round Time Trip maximum value in ms
   Header_Size    : constant := Header'Size / System.Storage_Unit; -- Size of header in Bytes
   Sequence_Size  : constant Interfaces.Unsigned_64 := 2**(Header'Size); -- Size of sequence (first bit used for Ack)
   Pkt_Max        : constant := Sequence_Size - 1; -- Packet max nb in sequence (0 - Pkt_Max)

   type Packet_Payload is
      array (1 .. Base_Udp.Load_Size) of Interfaces.Unsigned_8;

end Base_Udp;
