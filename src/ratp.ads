with Interfaces;
with System;
with Ada.Streams;
with GNAT.Sockets;

package Ratp is

   pragma Optimize (Time);

   use type Interfaces.Unsigned_64;

   Acquisition : Boolean := True;

   --  Network throughput in Gb/s, used to regulate packet send
   --  as RATP doesn't have flow control.
   Throughput_Gbs : constant Float := 0.5;

   --  Size of the Header in Bytes.
   --  8 or 16 otherwise it's too big for Set_Used_Bytes parameter (Integer)
   Header_Size    : constant := 2;

   --  Number of pmh buffers used (PMH_Buf_Nb + 1 are initialized)
   PMH_Buf_Nb     : constant := 15;

   --  Packet Payload size in Bytes
   Load_Size      : constant := 1472;

   --  Round Time Trip maximum value in micro seconds
   RTT_US_Max     : Integer := 150;


   --  Size of sequence (first bit used for Ack)
   Sequence_Size  : constant Interfaces.Unsigned_64 := 2 ** (Header_Size * System.Storage_Unit - 1);

   --  Packet max nb in sequence (0 - Pkt_Max)
   Pkt_Max        : constant := Sequence_Size - 1;

   --  Used by Buffers' Set_Name
   Buffer_Name    : String := "toto";

   --  Size of PMH Buffers, has to be a multiple of 4096
   PMH_Buffer_Size    : Integer := ((Integer (Sequence_Size
                                 * Load_Size) / 4096) + 1) * 4096;

   --  Consumer Addr
   End_Point      : String := "http://127.0.0.1:5678";

   --  WebServer Port
   AWS_Port       : Integer := 8080;

   --  Server socket Port
   UDP_Port       : GNAT.Sockets.Port_Type := 50001;


   type Packet_Payload is
      array (1 .. Ratp.Load_Size) of Interfaces.Unsigned_8;

   subtype Packet_Stream is
      Ada.Streams.Stream_Element_Array (1 .. Ratp.Load_Size);

   type Sequence_Type is array (1 .. Ratp.Sequence_Size) of Packet_Stream;

   type Packet_Stream_Access is access all Packet_Stream;

end Ratp;