with AWS.Response;
with AWS.Server;
with AWS.Status;
with AWS.Messages;
with AWS.MIME;
with AWS.Templates;
with AWS.Net.WebSocket.Registry.Control;
with WebSocket;

procedure Web_Interface is

   WS  : AWS.Server.HTTP;

   Rcp : constant AWS.Net.WebSocket.Registry.Recipient :=
           AWS.Net.WebSocket.Registry.Create (URI => "/echo");

   function HW_CB (Request : in AWS.Status.Data)
     return AWS.Response.Data;

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

begin
   AWS.Server.Start
     (WS, "RATP Interface", Callback => HW_CB'Unrestricted_Access, Port => 4242);
   AWS.Net.WebSocket.Registry.Register ("/echo", WebSocket.Create'Access);
   AWS.Net.WebSocket.Registry.Control.Start;

   loop
      AWS.Net.WebSocket.Registry.Send (Rcp, "A simple message");
   end loop;
end Web_Interface;
