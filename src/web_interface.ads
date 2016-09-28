with AWS.Net.WebSocket;
with AWS.Response;
with AWS.Status;

package Web_Interface is

   function Create
     (Socket  : AWS.Net.Socket_Access;
      Request : AWS.Status.Data) return AWS.Net.WebSocket.Object'Class;

   function HW_CB (Request : in AWS.Status.Data)
     return AWS.Response.Data;

   procedure Init_WebServer (Port : Integer := 80);

   procedure Send_To_Client (Id     : String;
                             Data   : String);

   type Object is new AWS.Net.WebSocket.Object with null record;

   overriding procedure On_Close
     (Socket  : in out Object;
      Message : in     String);

   overriding procedure On_Message
     (Socket  : in out Object;
      Message : in     String);

   overriding procedure On_Open
     (Socket  : in out Object;
      Message : in     String);

end Web_Interface;
