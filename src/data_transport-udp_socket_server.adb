with Ada.Text_IO;
with Ada.Calendar;
with Ada.Exceptions;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Ratp.Producer_Utilities;
with Ratp.Reliable_Udp;

package body Data_Transport.Udp_Socket_Server is

   use type Ratp.Reliable_Udp.Pkt_Nb;

   task body Socket_Server_Task is
      Packet_Number : Ratp.Reliable_Udp.Pkt_Nb := 0;
   begin
      select
         accept Initialise
           (Network_Interface : String;
            Port : GNAT.Sockets.Port_Type) do

            Ratp.Producer_Utilities.Address.Addr := GNAT.Sockets.Addresses
                            (GNAT.Sockets.Get_Host_By_Name (Network_Interface));
            Ratp.Producer_Utilities.Address.Port := Port;
            GNAT.Sockets.Create_Socket
               (Ratp.Producer_Utilities.Socket,
                GNAT.Sockets.Family_Inet,
                GNAT.Sockets.Socket_Datagram);
         end Initialise;
      or
         terminate;
      end select;
      loop
         select
            accept Connect;
            exit;
         or
            terminate;
         end select;
      end loop;

      <<HandShake>>
      Ratp.Producer_Utilities.Consumer_HandShake;
      Ratp.Producer_Utilities.Acquisition := True;
      delay 0.0001;
      Ada.Text_IO.Put_Line ("Consumer ready, start sending packets...");

      loop
         select
            accept Disconnect;
               GNAT.Sockets.Close_Socket (Ratp.Producer_Utilities.Socket);
               exit;
         else
            if Ratp.Producer_Utilities.Acquisition then
               Ratp.Producer_Utilities.Rcv_Ack;
               select
                  Buffer_Set.Block_Full;
                  Ratp.Producer_Utilities.Send_Buffer_Data
                        (Buffer_Set, Packet_Number);
               else
                  null;
               end select;
            else
               declare
                  Start_Time  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
                  use type Ada.Calendar.Time;
               begin
                  loop
                     Ratp.Producer_Utilities.Rcv_Ack;
                     --  Give server 2s to be sure it has all packets
                     if Ada.Calendar.Clock - Start_Time > 2.0 then
                        goto HandShake;
                     end if;
                  end loop;
               end;
            end if;
         end select;
      end loop;

   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Socket_Server_Task;


end Data_Transport.Udp_Socket_Server;
