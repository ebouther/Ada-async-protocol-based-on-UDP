with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with Ada.Streams;
with GNAT.Sockets;
with Interfaces.C;
with System;

with Buffers;

with Base_Udp;

package Data_Transport.Udp_Socket_Client is
   pragma Optimize (Time);

   use GNAT.Sockets;

   use type Base_Udp.Header;
   use type Interfaces.Unsigned_64;

   type Socket_Client_Access is access all Socket_Client_Task;

   --  Main Task
   task type Socket_Client_Task (Buffer_Set : Buffers.Buffer_Produce_Access)
      is new Transport_Layer_Interface with
      entry Initialise (Host : String;
                        Port : GNAT.Sockets.Port_Type);
      overriding entry Connect;
      overriding entry Disconnect;
   end Socket_Client_Task;

   procedure Free is new Ada.Unchecked_Deallocation (Socket_Client_Task,
                                                     Socket_Client_Access);
   function To_Int is
      new Ada.Unchecked_Conversion
         (GNAT.Sockets.Socket_Type, Interfaces.C.int);

   --  Log Data every seconds.
   task type Timer is
      entry Start;
      entry Stop;
   end Timer;

   --  A "connect" alternative for udp. Enables to wait for producer.
   procedure Wait_Producer_HandShake (Host         : GNAT.Sockets.Inet_Addr_Type;
                                      Port         : GNAT.Sockets.Port_Type);

   --  Main part of algorithm, does all the processing once a packet is receive.
   procedure Process_Packet (Data         : in Base_Udp.Packet_Stream;
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

end Data_Transport.Udp_Socket_Client;
