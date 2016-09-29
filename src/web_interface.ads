with AWS.Net.WebSocket;

package Web_Interface is

   procedure Init_WebServer (Port : Integer := 80);

   procedure Send_To_Client (Id     : String;
                             Data   : String);

end Web_Interface;
