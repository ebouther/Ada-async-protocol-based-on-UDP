with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with Ada.Streams;
with GNAT.Sockets;
with Interfaces;
with Interfaces.C;

with Buffers;

with Reliable_Udp;
with Base_Udp;

package Data_Transport.Udp_Socket_Server is

   task type Socket_Server_Task (Buffer_Set : Buffers.Buffer_Consume_Access)
         is new Transport_Layer_Interface with
      entry Initialise (Network_Interface : String;
                        Port : GNAT.Sockets.Port_Type);
      overriding entry Connect;
      overriding entry Disconnect;
   end Socket_Server_Task;
   type Socket_Server_Access is access all Socket_Server_Task;

   procedure Free is new Ada.Unchecked_Deallocation (Socket_Server_Task,
                                                     Socket_Server_Access);


   procedure Send_Buffer_Data (Buffer_Set    : Buffers.Buffer_Consume_Access;
                               Packet_Number : in out Reliable_Udp.Pkt_Nb);


   procedure Send_All_Stream (Payload         : Ada.Streams.Stream_Element_Array;
                              Packet_Number   : in out Reliable_Udp.Pkt_Nb);
   procedure Send_Packet (Payload : Base_Udp.Packet_Stream);

   procedure Rcv_Ack;

   pragma Warnings (Off);
   procedure Server_HandShake;
   pragma Warnings (On);

   function To_Int is
      new Ada.Unchecked_Conversion (GNAT.Sockets.Socket_Type,
         Interfaces.C.int);

end Data_Transport.Udp_Socket_Server;
