package Base_Udp is

   Load_Size      : constant := 8972;
   Array_Size     : constant := Load_Size / 4;
   RTT_MS_Max     : constant := 107; -- Round Time Trip maximum value in ms
   Header_Size    : constant := 1; --  Size of packets header in Bytes
   Sequence_Size  : constant := Header_Size * 256 / 2;
   Pkt_Max        : constant := Sequence_Size - 1; -- Packet max nb in sequence (0 - Pkt_Max)
end Base_Udp;
