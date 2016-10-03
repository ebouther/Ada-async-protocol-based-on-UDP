package Data_Transport is

   pragma Preelaborate;

   type Transport_Layer_Interface is synchronized interface;
   procedure Connect
     (Transport : in out Transport_Layer_Interface) is abstract;
   procedure Disconnect
     (Transport : in out Transport_Layer_Interface) is abstract;

   type Transport_Layer_Access is access all Transport_Layer_Interface'Class;

end Data_Transport;
