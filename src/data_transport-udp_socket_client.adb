with Ada.Text_IO;
with Ada.Streams;
with Ada.Exceptions;
with System.Multiprocessors.Dispatching_Domains;
with System.Storage_Elements;
with Interfaces.C;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Ratp.Consumer_Utilities;
with Ratp.Buffer_Handling;

package body Data_Transport.Udp_Socket_Client is

   task body Socket_Client_Task is
      Handle_Data        : Ratp.Buffer_Handling.Handle_Data_Task;

      Server             : Socket_Type;
      Cons_Addr          : GNAT.Sockets.Inet_Addr_Type;
      Cons_Port          : GNAT.Sockets.Port_Type;

      From               : Sock_Addr_Type;
      Last               : Ada.Streams.Stream_Element_Offset;
      Data_Addr          : System.Address;
      Recv_Offset        : Interfaces.Unsigned_64 := Ratp.Pkt_Max + 1;

      use System.Storage_Elements;
      use type Interfaces.C.int;
      use type Buffers.Buffer_Produce_Access;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (16));
      select
         accept Initialise (Host : String;
                            Port : GNAT.Sockets.Port_Type) do

            --  Cons_Addr := GNAT.Sockets.Addresses
            --            (GNAT.Sockets.Get_Host_By_Name (Host));
            pragma Unreferenced (Host);

            Cons_Addr := Any_Inet_Addr;
            Cons_Port := Port;

            Ratp.Consumer_Utilities.Init_Consumer;
            Ratp.Consumer_Utilities.Init_Udp (Server, Cons_Addr, Cons_Port);

            if Buffer_Set /= null then
               Handle_Data.Start (Buffer_Set);
            end if;

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
      Ada.Text_IO.Put_Line ("...Waiting for Producer...");
      Ratp.Consumer_Utilities.Wait_Producer_HandShake (Cons_Addr, Cons_Port);
      Ada.Text_IO.Put_Line ("Producer is ready...");

      loop
         select
            accept Disconnect;
               Ada.Text_IO.Put_Line ("[Disconnect]");
               --  Send producer stop msg
               exit;
         else
            if Recv_Offset > Ratp.Pkt_Max then
               Ratp.Consumer_Utilities.PMH_Buffer_Task.New_Buffer_Addr
                  (Buffer_Ptr => Data_Addr);
               Recv_Offset := Recv_Offset mod Ratp.Sequence_Size;
            end if;

            declare
               Data     : Ratp.Packet_Stream;

               for Data'Address use Data_Addr + Storage_Offset
                     (Recv_Offset * Ratp.Load_Size);
               use type Ada.Streams.Stream_Element_Offset;
            begin
               GNAT.Sockets.Receive_Socket (Server, Data, Last, From);
               Ratp.Consumer_Utilities.Process_Packet
                  (Data, Last, Recv_Offset, Data_Addr, From);
               Recv_Offset := Recv_Offset + 1;
            exception
               when Socket_Error =>
                  Ada.Text_IO.Put_Line ("Socket Timeout");
                  goto HandShake;
            end;
         end select;
      end loop;
      exception
         when E : others =>
            Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
               Ada.Exceptions.Exception_Name (E)
               & ASCII.LF & ASCII.ESC & "[33m"
               & Ada.Exceptions.Exception_Message (E)
               & ASCII.ESC & "[0m");
   end Socket_Client_Task;

end Data_Transport.Udp_Socket_Client;
