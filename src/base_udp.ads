with Interfaces;
with System;

package Base_Udp is

   subtype Header is Interfaces.Unsigned_16;

   Load_Size      : constant := 8972;
   Array_Size     : constant := Load_Size / 4;
   RTT_MS_Max     : constant := 107; -- Round Time Trip maximum value in ms
   Header_Size    : constant := Header'Size / System.Storage_Unit; -- Size of header in Bytes
   Sequence_Size  : constant := Header_Size * 256 / 2; -- Size of sequence (first bit used for Ack)
   Pkt_Max        : constant := Sequence_Size - 1; -- Packet max nb in sequence (0 - Pkt_Max)
end Base_Udp;
