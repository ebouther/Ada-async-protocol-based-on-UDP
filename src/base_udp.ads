with Interfaces;
with System;
with Ada.Streams;
with GNAT.Sockets;

package Base_Udp is

   use type Interfaces.Unsigned_64;

   Client_Addr : GNAT.Sockets.Sock_Addr_Type;

   Acquisition : Boolean := True;

   --  8 or 16 otherwise it's too big for Set_Used_Bytes parameter (Integer)
   subtype Header is Interfaces.Unsigned_16;

   --  Number of pmh buffers used (PMH_Buf_Nb + 1 are initialized)
   PMH_Buf_Nb     : constant := 15;

   --  Packet Payload size in Bytes
   Load_Size      : constant := 8972;

   --  Round Time Trip maximum value in micro seconds
   RTT_US_Max     : Integer := 150;

   --  Size of header in Bytes
   Header_Size    : constant := Header'Size / System.Storage_Unit;

   --  Size of sequence (first bit used for Ack)
   Sequence_Size  : constant Interfaces.Unsigned_64 := 2 ** (Header'Size - 1);

   --  Packet max nb in sequence (0 - Pkt_Max)
   Pkt_Max        : constant := Sequence_Size - 1;

   --  Used by Buffers' Set_Name
   Buffer_Name    : String := "toto";

   --  Buffer Size, has to be a multiple of 4096
   Buffer_Size    : Integer := ((Integer (Sequence_Size
                                 * Load_Size) / 4096) + 1) * 4096;

   --  Consumer Addr
   End_Point      : String := "http://127.0.0.1:5678";

   --  WebServer Port
   AWS_Port       : Integer := 8080;

   --  Server socket Port
   UDP_Port       : GNAT.Sockets.Port_Type := 50001;


   type Packet_Payload is
      array (1 .. Base_Udp.Load_Size) of Interfaces.Unsigned_8;

   subtype Packet_Stream is
      Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);

   type Packet_Stream_Access is access all Packet_Stream;

end Base_Udp;
