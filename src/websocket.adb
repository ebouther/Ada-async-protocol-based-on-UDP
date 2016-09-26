
package body WebSocket is

   function Create
     (Socket  : AWS.Net.Socket_Access;
      Request : AWS.Status.Data) return AWS.Net.WebSocket.Object'Class
   is
   begin
      return MySocket'
        (AWS.Net.WebSocket.Object
          (AWS.Net.WebSocket.Create (Socket, Request)) with null record);
   end Create;

end WebSocket;
