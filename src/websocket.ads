with AWS.Net.WebSocket;
with AWS.Status;

package WebSocket is

   type MySocket is new AWS.Net.WebSocket.Object with null record;

   function Create
     (Socket  : AWS.Net.Socket_Access;
      Request : AWS.Status.Data) return AWS.Net.WebSocket.Object'Class;

end WebSocket;
