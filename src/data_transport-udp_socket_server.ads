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

   type Producer_Type is new Base_Udp.Producer_Type with private;
   type Producer_Access is access Producer_Type;

   --  Main Task
   task type Socket_Server_Task (Buffer_Set : Buffers.Buffer_Consume_Access)
         is new Transport_Layer_Interface with
      entry Initialise (Obj               : Producer_Access;
                        Network_Interface : String;
                        Port              : GNAT.Sockets.Port_Type);
      overriding entry Connect;
      overriding entry Disconnect;
   end Socket_Server_Task;

   type Socket_Server_Access is access all Socket_Server_Task;

   procedure Free is new Ada.Unchecked_Deallocation (Socket_Server_Task,
                                                     Socket_Server_Access);

   --  Gets Full Buffers, sends the Buffer Size and then All Stream
   --  and finally releases buffer.
   procedure Send_Buffer_Data (Producer      : Producer_Access;
                               Buffer_Set    : Buffers.Buffer_Consume_Access;
                               Packet_Number : in out Reliable_Udp.Packet_Number_Type);

   --  Gets all the content of a buffer as a stream,
   --  divides it into packets and sends them to consumer.
   procedure Send_All_Stream (Producer       : Producer_Access;
                              Payload        : Ada.Streams.Stream_Element_Array;
                              Packet_Number  : in out Reliable_Udp.Packet_Number_Type);

   --  Sends a packet to consumer,
   --  if Is_Buffer_Size is true the packet sent's length will only be 6 Bytes
   --  (Header + Size as u_int32)
   procedure Send_Packet (Producer           : Producer_Access;
                          Payload            : Base_Udp.Packet_Stream;
                          Is_Buffer_Size     : Boolean := False);

   --  Receives packets, checks if it is a packet request or a Msg,
   --  if it's a request, it sends to Consumer the data of the index
   --  of Last_Packets corresponding to packet header.
   --  Otherwise it does the action matching with Msg.
   procedure Rcv_Ack (Producer   : Producer_Access);

   --  Sends messages to producer, wait for its reply
   --  with the same message to start / stop acquisition
   procedure Consumer_HandShake (Producer : Producer_Access;
                                 Msg      : Reliable_Udp.Packet_Number_Type);

   function To_Int is
      new Ada.Unchecked_Conversion (GNAT.Sockets.Socket_Type,
         Interfaces.C.int);
private

   --  Used to contain the data of a packet already sent in case of drops
   --  Is_Buffer_Size equal True if the Stream Data contains the size of the buffer sent.
   type History_Type is
      record
         Data           : Base_Udp.Packet_Stream;
         Is_Buffer_Size : Boolean := False;
      end record;

   type History_Array is array (Reliable_Udp.Packet_Number_Type)
                                 of History_Type;

   type Producer_Type is new Base_Udp.Producer_Type with record
      Socket            : GNAT.Sockets.Socket_Type;
      Address           : GNAT.Sockets.Sock_Addr_Type;
      Acquisition       : Boolean := True;
      Last_Packets      : History_Array;
   end record;

end Data_Transport.Udp_Socket_Server;
