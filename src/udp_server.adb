with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams;
with Ada.Unchecked_Conversion;
with Ada.Calendar;
with Interfaces.C;
with System.Multiprocessors.Dispatching_Domains;
with System.Storage_Elements;

with GNAT.Traceback.Symbolic;
with System;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;
with Output_Data;
with Reliable_Udp;
with Packet_Mgr;
with Queue;

procedure UDP_Server is
   use GNAT.Sockets;

   use type Base_Udp.Header;
   use type Interfaces.Unsigned_64;

   task type Timer is
      entry Start;
      entry Stop;
   end Timer;

   task type Process_Packets is
      entry Start;
      entry Stop;
   end Process_Packets;

   task type Recv_Socket is
      entry Start;
      entry Stop;
   end Recv_Socket;


   package Sync_Queue is new Queue (System.Address);
   Buffer               : Sync_Queue.Synchronized_Queue;

   Append_Task          : Reliable_Udp.Append_Task;
   Remove_Task          : Reliable_Udp.Remove_Task;
   Ack_Task             : Reliable_Udp.Ack_Task;
   Recv_Socket_Task     : Recv_Socket;
   Log_Task             : Timer;

   PMH_Buffer_Task      : Packet_Mgr.PMH_Buffer_Addr;

   Server               : Socket_Type;
   Address, From        : Sock_Addr_Type;
   Start_Time           : Ada.Calendar.Time;
   Elapsed_Time         : Duration;
   Nb_Packet_Received   : Interfaces.Unsigned_64 := 0;
   Packet_Number        : Base_Udp.Header := 0;
   Missed               : Interfaces.Unsigned_64 := 0;
   Last_Nb              : Interfaces.Unsigned_64 := 0;
   Nb_Output            : Natural := 0;
   Log_File             : Ada.Text_IO.File_Type;
   Process_Pkt          : Process_Packets;
   Busy                 : Interfaces.C.int := 50;
   Opt_Return           : Interfaces.C.int;

   function To_Int is
      new Ada.Unchecked_Conversion (GNAT.Sockets.Socket_Type, Interfaces.C.int);

   pragma Warnings (Off);
   procedure Stop_Server;
   pragma Warnings (On);
   procedure Stop_Server is
   begin
      Log_Task.Stop;
      Ack_Task.Stop;
      Process_Pkt.Stop;
      PMH_Buffer_Task.Stop;
      Remove_Task.Stop;
      Append_Task.Stop;
      delay 0.1;
      Recv_Socket_Task.Stop;
   end Stop_Server;

   procedure Init_Udp;
   procedure Init_Udp is
   begin
      Create_Socket (Server, Family_Inet, Socket_Datagram);
      Set_Socket_Option
         (Server,
         Socket_Level,
         (Reuse_Address, True));
      Set_Socket_Option
         (Server,
         Socket_Level,
         (Receive_Timeout,
         Timeout => 1.0));
      Opt_Return := Thin.C_Setsockopt (S        => To_Int (Server),
                                       Level    => 1,
                                       Optname  => 46,
                                       Optval   => Busy'Address,
                                       Optlen   => 4);
      Ada.Text_IO.Put_Line ("opt return" & Opt_Return'Img);
      Address.Addr := Any_Inet_Addr;
      Address.Port := 50001;
      Bind_Socket (Server, Address);
   end Init_Udp;


   task body Timer is
      use type Ada.Calendar.Time;
   begin
      accept Start;
      loop
         select
            accept Stop;
            exit;
         else
            delay 1.0;
            Ada.Text_IO.Put_Line ("Buf len : " & Buffer.Cur_Count'Img);
            Elapsed_Time := Ada.Calendar.Clock - Start_Time;
            Output_Data.Display
               (True,
               Elapsed_Time,
               Interfaces.Unsigned_64 (Packet_Number),
               Missed,
               Nb_Packet_Received,
               Last_Nb,
               Nb_Output);
               Last_Nb := Nb_Packet_Received;
            Nb_Output := Nb_Output + 1;
         end select;
      end loop;
   end Timer;

   task body Recv_Socket is
      Last        : Ada.Streams.Stream_Element_Offset;
      Watchdog    : Natural := 0;
      Data_Addr   : System.Address;
      I           : Integer := Base_Udp.Pkt_Max + 1;

      use type Interfaces.C.int;
      use System.Storage_Elements;
   begin
      accept Start;
      loop
         select
            accept Stop;
               exit;
         else
            if I > Base_Udp.Pkt_Max then
               select
                  PMH_Buffer_Task.New_Buffer_Addr (Buffer_Ptr => Data_Addr);
               or
                  delay 0.1;
                  Ada.Text_IO.Put_Line ("New_Buffer_Addr Takes too much time");
               end select;
               I := 0;
            end if;

            declare
               Data  : Base_Udp.Packet_Stream;
               for Data'Address use Data_Addr + Storage_Offset
                                                   (I * Base_Udp.Load_Size);
            begin
               GNAT.Sockets.Receive_Socket (Server, Data, Last, From);
               Buffer.Append_Wait (Data'Address);
               I := I + 1;
            exception
               when Socket_Error =>
                  Watchdog := Watchdog + 1;
                  Ada.Text_IO.Put_Line ("Socket Error");
                  exit when Watchdog = 10;
            end;
         end select;
      end loop;
   end Recv_Socket;


   task body Process_Packets is
      use type Ada.Calendar.Time;

      Data_Addr   : System.Address;

   begin
      accept Start;
      loop
         select
            accept Stop;
            exit;
         else
            Buffer.Remove_First_Wait (Data_Addr);
            declare
               Data     : Base_Udp.Packet_Stream;
               Seq_Nb   : Base_Udp.Header;
               Header   : Reliable_Udp.Header;

               for Data'Address use Data_Addr;
               for Header'Address use Data'Address;
               for Seq_Nb'Address use Header'Address;
            begin
               if Header.Ack then
                  Header.Ack := False;

                  Remove_Task.Remove (Seq_Nb);
               else
                  ---  New_Seq := False;
                  Nb_Packet_Received := Nb_Packet_Received + 1;
                  if Nb_Packet_Received = 1 then
                     Start_Time := Ada.Calendar.Clock;
                  end if;

                  if Seq_Nb /= Packet_Number then
                     if Seq_Nb > Packet_Number then
                        Missed := Missed + Interfaces.Unsigned_64 (Seq_Nb - Packet_Number);
                     else
                        --  Doesn't manage disordered packets
                        --  if a packet is received before the previous sent.

                        --  Missed := Missed + Interfaces.Unsigned_64 (Seq_Nb
                        --     + (Base_Udp.Pkt_Max - Packet_Number));
                        Ada.Text_IO.Put_Line ("BAD ORDER");

                        --  New_Seq := True;
                     end if;

                        --  Append_Task.Append (Packet_Number,
                        --                       Seq_Nb,
                        --                       From);
                        Packet_Number := Seq_Nb;
                  end if;

                  if Seq_Nb >= Base_Udp.Pkt_Max then
                     Packet_Number := 0;

                     ---  New_Seq := True;
                  else
                     Packet_Number := Packet_Number + 1;
                  end if;

               end if;
            end;
         end select;
      end loop;
   end Process_Packets;

begin

   Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "log.csv");
   Ada.Text_IO.Put_Line (Log_File, "Nb_Output;Nb_Received;Packet_Nb;Dropped;Elapsed_Time");
   Ada.Text_IO.Close (Log_File);

   if Ada.Command_Line.Argument_Count = 1 then
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range'Value (Ada.Command_Line.Argument (1)));
   end if;

   Init_Udp;
   Log_Task.Start;
   Recv_Socket_Task.Start;
   Process_Pkt.Start;
   Ack_Task.Start;

   --  delay 20.0;
   --  Stop_Server;

exception
   when E : others =>
      Ada.Text_IO.Put_Line (GNAT.Traceback.Symbolic.Symbolic_Traceback (E));
end UDP_Server;
