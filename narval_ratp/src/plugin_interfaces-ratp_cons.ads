package Plugin_Interfaces.Ratp_Cons is

   type Ratp_Consumer_Type (Length : Natural) is new Actor_Skeleton_Type (Length) with record
      Inputs : Buffers.Buffer_Consume_Vectors.Vector;
   end record;

   procedure Buffer_Handling (Object : access Ratp_Consumer_Type);
   procedure On_Unload (Object : access Ratp_Consumer_Type) is null;
   procedure On_Start (Object : access Ratp_Consumer_Type) is null;
   procedure On_Stop (Object : access Ratp_Consumer_Type) is null;
   procedure On_Suspend (Object : access Ratp_Consumer_Type) is null;
   procedure On_Resume (Object : access Ratp_Consumer_Type) is null;
   procedure On_Initialise (Object : access Ratp_Consumer_Type) is null;
   procedure On_Reset_Com (Object : access Ratp_Consumer_Type) is null;
   procedure Add_Input (Object : access Ratp_Consumer_Type; Input : Buffers.Buffer_Consume_Access) is null;
   procedure Add_Output (Object : access Ratp_Consumer_Type; Output : Buffers.Buffer_Produce_Access) is null;
   procedure Clear_IO
      (Object : access Ratp_Consumer_Type) is null;
   procedure Append_Parameters
      (Object : access Ratp_Consumer_Type;
      Vector : in out Parameters.Parameter_Vector_Package.Vector) is null;

   procedure Set_Logger
      (Object : access Ratp_Consumer_Type;
      Logger : Log4ada.Loggers.Logger_Class_Access) is null;

   type Ratp_Consumer_Class is access all Ratp_Consumer_Type'Class;

   function Constructor (Name : String) return Actor_Class;
   pragma Export (Ada, Constructor, "plugin_constructor");

end Plugin_Interfaces.Ratp_Cons;
