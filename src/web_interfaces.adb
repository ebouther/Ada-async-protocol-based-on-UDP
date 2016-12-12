with Ada.Text_IO;
with Ada.Exceptions;
with AWS.Net.WebSocket.Registry.Control;

with WebSocket;

package body Web_Interfaces is


   --------------------
   -- Init_WebServer --
   --------------------

   procedure Init_WebServer (Obj : Web_Interface_Access) is
      use Ada.Strings.Unbounded;
   begin
      Obj.Rcp := AWS.Net.WebSocket.Registry.Create (URI => To_String (Obj.URI));
      AWS.Server.Start
        (Obj.WS, "RATP Interface", Callback => WebSocket.HW_CB'Unrestricted_Access, Port => Obj.Port);
         AWS.Net.WebSocket.Registry.Control.Start;
         AWS.Net.WebSocket.Registry.Register (To_String (Obj.URI), WebSocket.Create'Access);
      Ada.Text_IO.Put_Line (ASCII.ESC & "[32;1m" & "WebServer [✓]" & ASCII.ESC & "[0m");
   exception
      when E : others =>
      Ada.Text_IO.Put_Line (ASCII.ESC & "[31;1m" & "WebServer [x]" & ASCII.ESC & "[0m");
      Ada.Text_IO.Put_Line (ASCII.ESC & "[33m"
         & "Make sure that AWS Port is not used."
         & ASCII.LF & " (use --aws-port to change)"
         & ASCII.ESC & "[0m");

         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end  Init_WebServer;


   --------------------
   -- Send_To_Client --
   --------------------

   procedure Send_To_Client (Obj    : Web_Interface_Access;
                             Id     : String;
                             Data   : String) is
   begin
      AWS.Net.WebSocket.Registry.Send (Obj.all.Rcp, Id & "|" & Data);
   end Send_To_Client;


   --------------
   -- Set_Port --
   --------------

   procedure Set_Port (Obj       : Web_Interface_Access;
                       AWS_Port  : Integer) is
   begin
      Obj.Port := AWS_Port;
   end Set_Port;


   --------------
   -- Set_URI --
   --------------

   procedure Set_URI (Obj   : Web_Interface_Access;
                      URI   : String) is
      use Ada.Strings.Unbounded;
   begin
      Obj.URI := To_Unbounded_String (URI);
   end Set_URI;


   -------------------
   -- Set_Prod_Addr --
   -------------------

   procedure Set_Prod_Addr (Obj        : Web_Interface_Access;
                            Prod_Addr  : GNAT.Sockets.Sock_Addr_Type) is
   begin
      Obj.Prod_Addr := Prod_Addr;
   end Set_Prod_Addr;


   -------------------
   -- Get_Prod_Addr --
   -------------------

   function Get_Prod_Addr (Obj   : Web_Interface_Access) return GNAT.Sockets.Sock_Addr_Type is
   begin
      return Obj.Prod_Addr;
   end Get_Prod_Addr;

end Web_Interfaces;
