with Interfaces;

with Ratp.Reliable_Udp;

package Ratp.Output_Data is

   procedure Display (Log : in Boolean;
      Elapsed_Time         : in Duration;
      Last_Packet          : in Reliable_Udp.Pkt_Nb;
      Missed, Last_Missed  : in Interfaces.Unsigned_64;
      Nb_Packet_Received   : in Interfaces.Unsigned_64;
      Last_Nb              : in Interfaces.Unsigned_64;
      Nb_Output            : in Natural);

   procedure Log_CSV (Elapsed_Time  :  in Duration;
      Last_Packet          : in Reliable_Udp.Pkt_Nb;
      Missed               : in Interfaces.Unsigned_64;
      Nb_Packet_Received   : in Interfaces.Unsigned_64;
      Nb_Output            : in Natural);
end Ratp.Output_Data;