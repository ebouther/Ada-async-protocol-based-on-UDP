with GNAT.Sockets;

with Buffers.Local;

with Data_Transport.Udp_Socket_Client;

procedure Udp_Consumer is
   Buffer : aliased Buffers.Local.Local_Buffer_Type;
   Client : Data_Transport.Udp_Socket_Client.Socket_Client_Task (Buffer'Unchecked_Access);
   Port   : constant GNAT.Sockets.Port_Type := 50001;

begin
   Client.Initialise ("10.0.0.2", Port);
   Client.Connect;
   loop
      null;
   end loop;
end Udp_Consumer;
