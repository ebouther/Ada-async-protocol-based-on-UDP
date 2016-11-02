with Ada.Text_IO;
with Text_IO.Unbounded_IO;
with Ada.Strings.Unbounded;

with Base_Udp;
with Web_Interface;

package body Output_Data is
   use type Interfaces.Unsigned_64;

   procedure Log_CSV (Elapsed_Time        : in Duration;
                     Last_Packet          : in Reliable_Udp.Packet_Number_Type;
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
      Last_Packet          : in Reliable_Udp.Packet_Number_Type;
      Missed, Last_Missed  : in Interfaces.Unsigned_64;
      Nb_Packet_Received   : in Interfaces.Unsigned_64;
      Last_Nb              : in Interfaces.Unsigned_64;
      Nb_Output            : in Natural)
   is
      use type Long_Float;

      Ratio : Long_Float;
      Pps   : Long_Float;
      Debit : Interfaces.Unsigned_64;
   begin

      Ratio := Long_Float (Missed) / Long_Float (Nb_Packet_Received + Missed);
      Debit := Base_Udp.Load_Size * 8 * (Nb_Packet_Received -  Last_Nb);
      Pps   := Long_Float (Nb_Packet_Received) / Long_Float (Elapsed_Time);

      Ada.Text_IO.Put_Line ("-- Nb output                     : "
        & Nb_Output'Img);
      Ada.Text_IO.Put_Line ("-- Nb_received                   : "
        & Nb_Packet_Received'Img);
      Ada.Text_IO.Put_Line ("-- Last Packet Received          : "
        & Last_Packet'Img);
      Ada.Text_IO.Put_Line ("-- Dropped                       : "
        & Missed'Img);
      Ada.Text_IO.Put_Line ("-- Delta in bits                 : "
        & Debit'Img);
      Ada.Text_IO.Put_Line ("-- Ratio (dropped / total_sent)  : "
        & Ratio'Img);
      Ada.Text_IO.Put_Line ("-- Elapsed Time                  : "
        & Duration'Image (Elapsed_Time));
      Ada.Text_IO.Put_Line ("-- Pps                           : "
        & Pps'Img);
      Ada.Text_IO.New_Line;

      --  WebSocket --
      Web_Interface.Send_To_Client ("debit", Debit'Img);
      Web_Interface.Send_To_Client ("pps", Pps'Img);
      Web_Interface.Send_To_Client ("total_drops", Missed'Img);
      Web_Interface.Send_To_Client ("drops",
         Interfaces.Unsigned_64'Image (Missed - Last_Missed));
      Web_Interface.Send_To_Client ("uptime", Nb_Output'Img);
      Web_Interface.Send_To_Client ("total_pkt", Nb_Packet_Received'Img);
      Web_Interface.Send_To_Client ("ratio", Ratio'Img);

      if Log then
         Log_CSV (Elapsed_Time,
         Last_Packet,
         Missed,
         Nb_Packet_Received,
         Nb_Output);
      end if;

   end Display;

end Output_Data;
