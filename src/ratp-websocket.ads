with AWS.Net.WebSocket;
with AWS.Response;
with AWS.Status;

package Ratp.WebSocket is

   function HW_CB (Request : in AWS.Status.Data)
     return AWS.Response.Data;

   type Object is new AWS.Net.WebSocket.Object with null record;

   function Create
     (Socket  : AWS.Net.Socket_Access;
      Request : AWS.Status.Data) return AWS.Net.WebSocket.Object'Class;

   overriding procedure On_Message
     (Socket : in out Object; Message : String);
   overriding procedure On_Open (Socket : in out Object; Message : String);
   overriding procedure On_Close (Socket : in out Object; Message : String);

end Ratp.WebSocket;
