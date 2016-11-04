with AWS.Net.WebSocket;
with AWS.Response;
with AWS.Status;

package WebSocket is

   function HW_CB (Request : in AWS.Status.Data)
     return AWS.Response.Data;

   type Object is new AWS.Net.WebSocket.Object with private;

   function Create
     (Socket  : AWS.Net.Socket_Access;
      Request : AWS.Status.Data) return AWS.Net.WebSocket.Object'Class;

   overriding procedure On_Message
     (Obj : in out Object; Message : String);
   overriding procedure On_Open (Obj   : in out Object; Message : String);
   overriding procedure On_Close (Obj  : in out Object; Message : String);

   function Get_Acquisition_State (Obj : in out Object) return Boolean;

private
   type Object is new AWS.Net.WebSocket.Object with
      record
         Acquisition : Boolean := True;
      end record;
end WebSocket;
