with System;

package body Plugin_Interfaces.Ratp_Cons is

   procedure Buffer_Handling
     (Object : access Ratp_Consumer_Type) is
   begin
      for Input_Buffer of Object.Inputs loop
         declare
            Full_Buffer_Handle   : Buffers.Buffer_Handle_Type;
            Input_Address        : System.Address;
            pragma Unreferenced (Input_Address);
         begin
            select
               Input_Buffer.Get_Full_Buffer (Full_Buffer_Handle);
               Input_Address := Full_Buffer_Handle.Get_Address;
               Display (Object, "Got Full Buffer");
               Input_Buffer.Release_Full_Buffer (Full_Buffer_Handle);
            or
               delay 1.0;
               Display (Object, "nothing to consume");
            end select;
         end;
      end loop;
   end Buffer_Handling;

   function Constructor (Name : String) return Actor_Class is
      New_Object : constant Ratp_Consumer_Class := new Ratp_Consumer_Type (Length => Name'Length);
   begin
      New_Object.Name := Name;
      return Actor_Class (New_Object);
   end Constructor;


end Plugin_Interfaces.Ratp_Cons;
