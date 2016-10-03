with Buffers.Local;
with GNAT.Sockets;

with Data_Transport.Udp_Socket_Server;

procedure Udp_Producer is
   Buffer : aliased Buffers.Local.Local_Buffer_Type;
   Server : Data_Transport.Udp_Socket_Server.Socket_Server_Task (Buffer'Unchecked_Access);
   Port   : constant GNAT.Sockets.Port_Type := 50001;

begin
   Server.Initialise ("10.0.0.3", Port);
   Server.Connect;
   loop
      null;
   end loop;
end Udp_Producer;
