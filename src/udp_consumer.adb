with Ada.Command_Line;
with GNAT.Sockets;

with Buffers.Local;

with Data_Transport.Udp_Socket_Client;

procedure Udp_Consumer is
   Buffer : aliased Buffers.Local.Local_Buffer_Type;
   Client : Data_Transport.Udp_Socket_Client.Socket_Client_Task (Buffer'Unchecked_Access);
   use type Buffers.Buffer_Size_Type;
begin
   Buffer.Initialise (10, Size => 1024 * 2000);
   Client.Initialise (Ada.Command_Line.Argument (1),
                     GNAT.Sockets.Port_Type'Value (Ada.Command_Line.Argument (2)));
   Client.Connect;
   loop
      null;
   end loop;
end Udp_Consumer;
