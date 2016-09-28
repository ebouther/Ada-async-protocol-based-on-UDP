with Ada.Text_IO;
with AWS.Server;
with AWS.Messages;
with AWS.MIME;
with AWS.Templates;
with AWS.Net.WebSocket.Registry.Control;
with WebSocket;

package body Web_Interface is

   WS  : AWS.Server.HTTP;

   Rcp : constant AWS.Net.WebSocket.Registry.Recipient :=
            AWS.Net.WebSocket.Registry.Create (URI => "/echo");

   function Create
     (Socket  : AWS.Net.Socket_Access;
      Request : AWS.Status.Data) return AWS.Net.WebSocket.Object'Class
   is
   begin
      return Object'
        (AWS.Net.WebSocket.Object
          (AWS.Net.WebSocket.Create (Socket, Request)) with null record);
   end Create;


   function HW_CB (Request : in AWS.Status.Data)
     return AWS.Response.Data
   is
      URI : constant String := AWS.Status.URI (Request);

      Translations : AWS.Templates.Translate_Set;
   begin
      AWS.Templates.Insert
        (Translations, AWS.Templates.Assoc ("DATA", URI));

      return AWS.Response.Build
        (Content_Type  => AWS.MIME.Text_HTML,
         Message_Body  => AWS.Templates.Parse ("templates/index.thtml", Translations),
         Status_Code   => AWS.Messages.S200);
   end HW_CB;


   procedure Init_WebServer (Port : Integer := 80) is
   begin
      AWS.Server.Start
        (WS, "RATP Interface", Callback => HW_CB'Unrestricted_Access, Port => Port);
      AWS.Net.WebSocket.Registry.Control.Start;
      AWS.Net.WebSocket.Registry.Register ("/echo", WebSocket.Create'Access);
   end  Init_WebServer;


   procedure Send_To_Client (Id     : String;
                             Data   : String) is
   begin
      AWS.Net.WebSocket.Registry.Send (Rcp, Id & "|" & Data);
   end Send_To_Client;

   overriding procedure On_Message
     (Socket  : in out Object;
      Message : in     String)
   is
   begin
      Socket.Send ("Server Received :" & Message);
      Ada.Text_IO.Put_Line ("==== Server Received :" & Message);
   end On_Message;

   overriding procedure On_Open
     (Socket  : in out Object;
      Message : in     String)
   is
   begin
      Socket.Send ("New client :" & Message);
      Ada.Text_IO.Put_Line ("===> New client :" & Message);
   end On_Open;

   overriding procedure On_Close
     (Socket  : in out Object;
      Message : in     String)
   is
      pragma Unreferenced (Socket);
   begin
      Ada.Text_IO.Put_Line ("<=== Client left :" & Message);
   end On_Close;

end Web_Interface;
