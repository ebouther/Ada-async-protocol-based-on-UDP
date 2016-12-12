with Ada.Strings.Unbounded;
with GNAT.Sockets;
with AWS.Net.WebSocket;
with AWS.Net.WebSocket.Registry;
with AWS.Server;

package Web_Interfaces is

   type Web_Interface is tagged limited private;
   type Web_Interface_Access is access all Web_Interface;

   procedure Init_WebServer (Obj    : Web_Interface_Access);

   procedure Send_To_Client (Obj    : Web_Interface_Access;
                             Id     : String;
                             Data   : String);

   procedure Set_Port (Obj       : Web_Interface_Access;
                       AWS_Port  : Integer);

   procedure Set_URI (Obj   : Web_Interface_Access;
                      URI   : String);

   procedure Set_Prod_Addr (Obj        : Web_Interface_Access;
                            Prod_Addr  : GNAT.Sockets.Sock_Addr_Type);

   function Get_Prod_Addr (Obj   : Web_Interface_Access) return GNAT.Sockets.Sock_Addr_Type;
private

   type Web_Interface is tagged limited record
      WS          : AWS.Server.HTTP;

      URI         : Ada.Strings.Unbounded.Unbounded_String;

      Rcp         : AWS.Net.WebSocket.Registry.Recipient;

      Prod_Addr   : GNAT.Sockets.Sock_Addr_Type;

      Port        : Integer;
   end record;

end Web_Interfaces;
