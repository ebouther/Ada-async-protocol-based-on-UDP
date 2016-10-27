with Ada.Streams;
with Ada.Unchecked_Conversion;
with System;
with Interfaces.C;
with GNAT.Sockets;

with Ratp;
with Ratp.Buffer_Handling;


package Ratp.Consumer_Utilities is

   use GNAT.Sockets;

   PMH_Buffer_Task      : Buffer_Handling.PMH_Buffer_Addr;

   --  Log Data every seconds.
   task type Timer is
      entry Start;
      entry Stop;
   end Timer;

   function To_Int is
      new Ada.Unchecked_Conversion
         (GNAT.Sockets.Socket_Type, Interfaces.C.int);

   --  A "connect" alternative for udp. Enables to wait for producer.
   procedure Wait_Producer_HandShake (Host         : GNAT.Sockets.Inet_Addr_Type;
                                      Port         : GNAT.Sockets.Port_Type);

   --  Main part of algorithm, does all the processing once a packet is received.
   procedure Process_Packet (Data         : in Ratp.Packet_Stream;
                             Last         : in Ada.Streams.Stream_Element_Offset;
                             Recv_Offset  : in out Interfaces.Unsigned_64;
                             Data_Addr    : in out System.Address;
                             From         : in Sock_Addr_Type);


   --  Get command line parameters and modify default values if needed.
   procedure Parse_Arguments;

   --  Starts all tasks used by client.
   procedure Init_Consumer;

   --  Creates socket and Sets Socket Opt.
   procedure Init_Udp (Server       : in out Socket_Type;
                       Host         : GNAT.Sockets.Inet_Addr_Type;
                       Port         : GNAT.Sockets.Port_Type;
                       TimeOut_Opt  : Boolean := True);

   pragma Warnings (Off);
   procedure Stop_Server;
   pragma Warnings (On);

end Ratp.Consumer_Utilities;
