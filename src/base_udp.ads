with Interfaces;
with System;
with Ada.Streams;
with Ada.Unchecked_Deallocation;

package Base_Udp is

   use type Interfaces.Unsigned_64;

   --  8 or 16 otherwise it's too big for Set_Used_Bytes parameter (Integer)
   subtype Header is Interfaces.Unsigned_16;

   --  Packet Payload size in Bytes
   Load_Size      : constant := 8972;

   --  Round Time Trip maximum value in ms
   RTT_MS_Max     : constant := 107;

   --  Size of header in Bytes
   Header_Size    : constant := Header'Size / System.Storage_Unit;

   --  Size of sequence (first bit used for Ack)
   Sequence_Size  : constant Interfaces.Unsigned_64 := 2 ** (Header'Size - 1);

   --  Packet max nb in sequence (0 - Pkt_Max)
   Pkt_Max        : constant := Sequence_Size - 1;

   type Packet_Payload is
      array (1 .. Base_Udp.Load_Size) of Interfaces.Unsigned_8;

   type Packet_Stream_Ptr is
      access all Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);

   subtype Packet_Stream is
      Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);

   procedure Free_Stream is
      new Ada.Unchecked_Deallocation
         (Base_Udp.Packet_Stream, Base_Udp.Packet_Stream_Ptr);

end Base_Udp;
