with Ada.Calendar;
with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with Ada.Streams;
with GNAT.Sockets;
with Interfaces.C;
with System;

with Buffers;

with Base_Udp;
with Reliable_Udp;
with Buffer_Handling;
with Log4ada.Loggers;

package Data_Transport.Udp_Socket_Client is
   --  pragma Optimize (Time);

   use GNAT.Sockets;

   use type Base_Udp.Header;
   use type Interfaces.Unsigned_64;

   --  Main Task
   task type Socket_Client_Task (Buffer_Set : Buffers.Buffer_Produce_Access)
      is new Transport_Layer_Interface with

      entry Initialise (Host       : String;
                        Port       : GNAT.Sockets.Port_Type;
                        Logger     : Log4ada.Loggers.Logger_Access);
      overriding entry Connect;
      overriding entry Disconnect;
   end Socket_Client_Task;

   type Socket_Client_Access is access all Socket_Client_Task;

   procedure Free is new Ada.Unchecked_Deallocation (Socket_Client_Task,
                                                     Socket_Client_Access);
   function To_Int is
      new Ada.Unchecked_Conversion
         (GNAT.Sockets.Socket_Type, Interfaces.C.int);

   --  Append some stuff to Base_Udp.Consumer_Type.
   --  Cannot do it in Base_Udp because of circular dependencies.
   type Consumer_Type is new Base_Udp.Consumer_Type with private;
   type Consumer_Access is access Consumer_Type;

   --  Log Data every seconds.
   task type Timer is
      entry Start (Cons      : Consumer_Access);
      entry Stop;
   end Timer;

   --  A "connect" alternative for udp. Enables to wait for producer.
   --  Returns the msg number sent by client. 1 = connect, 0 = Disconnect
   function Wait_Producer_HandShake (Consumer  : Consumer_Access;
                                     Logger    : Log4ada.Loggers.Logger_Access) return Reliable_Udp.Packet_Number_Type;

   --  Main part of algorithm, does all the processing once a packet is receive.
   procedure Process_Packet (Consumer     : Consumer_Access;
                             Data         : in Base_Udp.Packet_Stream;
                             Last         : in Ada.Streams.Stream_Element_Offset;
                             Recv_Offset  : in out Interfaces.Unsigned_64;
                             Data_Addr    : in out System.Address;
                             From         : in Sock_Addr_Type);

   --  Get command line parameters and modify default values if needed.
   procedure Parse_Arguments (Consumer : Consumer_Access);

   --  Starts all tasks used by client.
   procedure Init_Consumer (Consumer : Consumer_Access;
                            Logger   : Log4ada.Loggers.Logger_Access);

   --  Creates socket and Sets Socket Opt.
   procedure Init_Udp (Server       : in out Socket_Type;
                       Host         : GNAT.Sockets.Inet_Addr_Type;
                       Port         : GNAT.Sockets.Port_Type;
                       TimeOut_Opt  : Boolean := True);

private

   type Consumer_Type is new Base_Udp.Consumer_Type with
      record
         Ack_Mgr              : Reliable_Udp.Ack_Management_Access :=
                                    new Reliable_Udp.Ack_Management;

         Ack_Fifo             : Reliable_Udp.Synchronized_Queue_Access :=
                                    new Reliable_Udp.Sync_Queue.Synchronized_Queue;

         Buffer_Handler       : Buffer_Handling.Buffer_Handler_Obj_Access :=
                                    new Buffer_Handling.Buffer_Handler_Obj;

         Log_Task             : Timer;

         Remove_Task          : Reliable_Udp.Remove_Task;
         Append_Task          : Reliable_Udp.Append_Task;
         Ack_Task             : Reliable_Udp.Ack_Task;

         Check_Integrity_Task : Buffer_Handling.Check_Buf_Integrity_Task;
         PMH_Buffer_Task      : Buffer_Handling.PMH_Buffer_Addr_Task;
         Release_Buf_Task     : Buffer_Handling.Release_Full_Buf_Task;

         Start_Time           : Ada.Calendar.Time;
         Nb_Packet_Received   : Interfaces.Unsigned_64 := 0;
         Packet_Number        : Reliable_Udp.Packet_Number_Type := 0;
         Total_Missed         : Interfaces.Unsigned_64 := 0;
         Nb_Output            : Natural := 0;

         Addr                 : GNAT.Sockets.Inet_Addr_Type;
         Port                 : GNAT.Sockets.Port_Type;

      end record;

end Data_Transport.Udp_Socket_Client;
