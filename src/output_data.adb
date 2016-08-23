with Ada.Text_IO;
with Text_IO.Unbounded_IO;
with Ada.Strings.Unbounded;

with Base_Udp;

package body Output_Data is
   use type Interfaces.Unsigned_64;

   procedure Log_CSV (Elapsed_Time        : in Duration;
                     Last_Packet          : in Interfaces.Unsigned_64;
                     Missed               : in Interfaces.Unsigned_64;
                     Nb_Packet_Received   : in Interfaces.Unsigned_64;
                     Nb_Output            : in Natural) is

      CSV      : Ada.Strings.Unbounded.Unbounded_String;
      Log_File : Ada.Text_IO.File_Type;
   begin

      Ada.Text_IO.Open (Log_File, Ada.Text_IO.Append_File, "log.csv");
      CSV := Ada.Strings.Unbounded.To_Unbounded_String
              (Nb_Output'Img & ";" &
              Nb_Packet_Received'Img & ";" &
              Last_Packet'Img & ";" &
              Missed'Img & ";" &
              Duration'Image (Elapsed_Time));
      Ada.Text_IO.Unbounded_IO.Put_Line (Log_File, CSV);
      Ada.Text_IO.Close (Log_File);

   end Log_CSV;

   procedure Display (Log : in Boolean;
      Elapsed_Time         : in Duration;
      Last_Packet          : in Interfaces.Unsigned_64;
      Missed               : in Interfaces.Unsigned_64;
      Nb_Packet_Received   : in Interfaces.Unsigned_64;
      Last_Nb              : in Interfaces.Unsigned_64;
      Nb_Output            : in Natural) is

      Ratio : Long_Float;
   begin

      Ratio := Long_Float (Missed) / Long_Float (Nb_Packet_Received + Missed);
      Ada.Text_IO.Put_Line ("-- Nb output                     : "
        & Nb_Output'Img);
      Ada.Text_IO.Put_Line ("-- Nb_received                   : "
        & Nb_Packet_Received'Img);
      Ada.Text_IO.Put_Line ("-- Last Packet Received          : "
        & Last_Packet'Img);
      Ada.Text_IO.Put_Line ("-- Dropped                       : "
        & Missed'Img);
      Ada.Text_IO.Put_Line ("-- Delta in bits                 : "
        & Interfaces.Unsigned_64'Image
              (Interfaces."*"(Base_Udp.Load_Size,
              Interfaces."*" (8,
              (Interfaces."-"(Nb_Packet_Received, Last_Nb))))));
      Ada.Text_IO.Put_Line ("-- Ratio (dropped / total_sent)  : "
        & Ratio'Img);
      Ada.Text_IO.Put_Line ("-- Elapsed Time                  : "
        & Duration'Image (Elapsed_Time));
      Ada.Text_IO.Put_Line ("-- Pps                           : "
        & Long_Float'Image
              (Long_Float (Nb_Packet_Received) / Long_Float (Elapsed_Time)));
      Ada.Text_IO.New_Line;

      if Log then
         Log_CSV (Elapsed_Time,
         Last_Packet,
         Missed,
         Nb_Packet_Received,
         Nb_Output);
      end if;

   end Display;

end Output_Data;
