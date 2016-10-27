with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with GNAT.Sockets;
with Interfaces;
with System;

with Buffers;

package Data_Transport.Udp_Socket_Client is
   pragma Optimize (Time);

   use GNAT.Sockets;

   use type Interfaces.Unsigned_64;

   task type Socket_Client_Task (Buffer_Set : Buffers.Buffer_Produce_Access)
      is new Transport_Layer_Interface with
      entry Initialise (Host : String;
                        Port : GNAT.Sockets.Port_Type);
      overriding entry Connect;
      overriding entry Disconnect;
   end Socket_Client_Task;

   type Socket_Client_Access is access all Socket_Client_Task;

   procedure Free is new Ada.Unchecked_Deallocation (Socket_Client_Task,
                                                     Socket_Client_Access);

end Data_Transport.Udp_Socket_Client;
