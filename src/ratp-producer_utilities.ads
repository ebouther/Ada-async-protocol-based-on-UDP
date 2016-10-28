with Ada.Calendar;
with Ada.Unchecked_Conversion;
with Interfaces.C;

with Buffers;

with Ratp.Reliable_Udp;

package Ratp.Producer_Utilities is

   Socket                  : GNAT.Sockets.Socket_Type;
   Send_Throughput_Gb      : Float := 0.0;
   Send_Throughput_Start   : Ada.Calendar.Time;
   Address                 : GNAT.Sockets.Sock_Addr_Type;
   Acquisition             : Boolean := True;

   --  Used to contain the data of a packet already sent in case of drops
   --  Is_Buffer_Size equal True if the Stream Data contains the size of the buffer sent.
   type History_Type is
      record
         Data           : Ratp.Packet_Stream;
         Is_Buffer_Size : Boolean := False;
      end record;

   --  [CTL] Gets Full Buffers, sends the Buffer Size and then all Stream
   --  and finally releases buffer.
   procedure Send_Buffer_Data (Buffer_Set    : Buffers.Buffer_Consume_Access;
                               Packet_Number : in out Ratp.Reliable_Udp.Pkt_Nb);

   --  Gets all the content of a buffer as a stream,
   --  divides it into packets and sends them to consumer.
   procedure Send_All_Stream (Payload        : Ada.Streams.Stream_Element_Array;
                              Packet_Number  : in out Ratp.Reliable_Udp.Pkt_Nb);

   --  Sends a packet to consumer,
   --  if Is_Buffer_Size is true the packet sent's length will only be 6 Bytes
   --  (Header + u_int32)
   procedure Send_Packet (Payload            : Ratp.Packet_Stream;
                          Is_Buffer_Size     : Boolean := False);

   --  Receives packets, checks if it is a packet request or a Msg / Cmd,
   --  if it's a request, it sends to Consumer the data of the index
   --  of Last_Packets corresponding to packet header.
   --  Otherwise it does the action matching with Msg.
   procedure Rcv_Ack;

   --  Checks if Consumer is ready to start Acquisition.
   procedure Consumer_HandShake;

   function To_Int is
      new Ada.Unchecked_Conversion (GNAT.Sockets.Socket_Type,
         Interfaces.C.int);

   --  Used to reset Send_Throughput_Gbs
   --  which is incremented in Send_Packet each seconds
   task Reset_Send_Throughput;

end Ratp.Producer_Utilities;
