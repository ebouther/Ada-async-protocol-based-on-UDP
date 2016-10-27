with Ada.Text_IO;
with Ada.Exceptions;
with AWS.Server;
with AWS.Net.WebSocket.Registry.Control;

with Ratp.WebSocket;

package body Ratp.Web_Interface is

   WS  : AWS.Server.HTTP;

   Rcp : constant AWS.Net.WebSocket.Registry.Recipient :=
            AWS.Net.WebSocket.Registry.Create (URI => "/echo");

   procedure Init_WebServer (Port : Integer := 80) is
   begin
      AWS.Server.Start
        (WS, "RATP Interface", Callback => WebSocket.HW_CB'Unrestricted_Access, Port => Port);
      AWS.Net.WebSocket.Registry.Control.Start;
      AWS.Net.WebSocket.Registry.Register ("/echo", WebSocket.Create'Access);
      Ada.Text_IO.Put_Line (ASCII.ESC & "[32;1m" & "WebServer [✓]" & ASCII.ESC & "[0m");
   exception
      when E : others =>
      Ada.Text_IO.Put_Line (ASCII.ESC & "[31;1m" & "WebServer [x]" & ASCII.ESC & "[0m");
      Ada.Text_IO.Put_Line (ASCII.ESC & "[33m"
         & "Make sure that AWS Port is not used."
         & ASCII.LF & " (use --aws-port to change)"
         & ASCII.ESC & "[0m");

         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end  Init_WebServer;


   procedure Send_To_Client (Id     : String;
                             Data   : String) is
   begin
      AWS.Net.WebSocket.Registry.Send (Rcp, Id & "|" & Data);
   end Send_To_Client;

end Ratp.Web_Interface;
