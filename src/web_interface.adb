with AWS.Server;
with AWS.Net.WebSocket.Registry.Control;

with WebSocket;

package body Web_Interface is

   WS  : AWS.Server.HTTP;

   Rcp : constant AWS.Net.WebSocket.Registry.Recipient :=
            AWS.Net.WebSocket.Registry.Create (URI => "/echo");

   procedure Init_WebServer (Port : Integer := 80) is
   begin
      AWS.Server.Start
        (WS, "RATP Interface", Callback => WebSocket.HW_CB'Unrestricted_Access, Port => Port);
      AWS.Net.WebSocket.Registry.Control.Start;
      AWS.Net.WebSocket.Registry.Register ("/echo", WebSocket.Create'Access);
   end  Init_WebServer;


   procedure Send_To_Client (Id     : String;
                             Data   : String) is
   begin
      AWS.Net.WebSocket.Registry.Send (Rcp, Id & "|" & Data);
   end Send_To_Client;

end Web_Interface;
