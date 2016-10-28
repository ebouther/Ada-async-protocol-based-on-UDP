with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with GNAT.Sockets;

with Buffers;

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

end Data_Transport.Udp_Socket_Server;
