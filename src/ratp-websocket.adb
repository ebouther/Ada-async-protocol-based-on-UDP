with Ada.Text_IO;

with AWS.MIME;
with AWS.Templates;
with AWS.Messages;

with Ratp.Reliable_Udp;

package body Ratp.WebSocket is
   use Ada;
   use AWS;

   function HW_CB (Request : in AWS.Status.Data)
     return AWS.Response.Data
   is
      URI : constant String := AWS.Status.URI (Request);
      pragma Unreferenced (URI);

      Translations : AWS.Templates.Translate_Set;
   begin
      --  AWS.Templates.Insert
      --    (Translations, AWS.Templates.Assoc ("DATA", URI));

      return AWS.Response.Build
        (Content_Type  => AWS.MIME.Text_HTML,
         Message_Body  => AWS.Templates.Parse ("templates/index.thtml", Translations),
         Status_Code   => AWS.Messages.S200);
   end HW_CB;

   function Create
     (Socket  : AWS.Net.Socket_Access;
      Request : AWS.Status.Data) return AWS.Net.WebSocket.Object'Class
   is
   begin
      return Object'
        (AWS.Net.WebSocket.Object
          (AWS.Net.WebSocket.Create (Socket, Request)) with null record);
   end Create;

   -------------
   -- On_Open --
   -------------

   overriding procedure On_Open (Socket : in out Object; Message : String) is
      pragma Unreferenced (Socket);
   begin
      Text_IO.Put_Line ("On_Open : " & Message);
   end On_Open;

   ----------------
   -- On_Message --
   ----------------

   overriding procedure On_Message
     (Socket : in out Object; Message : String) is
      use type AWS.Net.WebSocket.Kind_Type;
   begin
      if Message = "START_ACQ"
         and Ratp.Acquisition = False
      then
         Reliable_Udp.Send_Cmd_To_Producer (1);
         Ratp.Acquisition := True;
      elsif Message = "STOP_ACQ"
         and Ratp.Acquisition
      then
         Reliable_Udp.Send_Cmd_To_Producer (2);
         Ratp.Acquisition := False;
      end if;
      Socket.Send (Message, Is_Binary => Socket.Kind = Net.WebSocket.Binary);
   end On_Message;

   --------------
   -- On_Close --
   --------------

   overriding procedure On_Close (Socket : in out Object; Message : String) is
   begin
      Text_IO.Put_Line
        ("On_Close : "
         & Net.WebSocket.Error_Type'Image (Socket.Error) & ", " & Message);
   end On_Close;

end Ratp.WebSocket;
