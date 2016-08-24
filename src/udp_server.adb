with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Ada.Calendar;
--  with Ada.Real_Time;
with Interfaces.C;
with System.Multiprocessors.Dispatching_Domains;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;
with Output_Data;
with Reliable_Udp;
with Packet_Mgr;

procedure UDP_Server is
   use GNAT.Sockets;

   use type Base_Udp.Header;
   use type Interfaces.Unsigned_64;

   task Timer;

   task type Receive_Packets is
      entry Start;
   end Receive_Packets;


   --  Store_Packet_Task    : Packet_Mgr.Store_Packet_Task;
   Append_Task          : Reliable_Udp.Append_Task;
   Remove_Task          : Reliable_Udp.Remove_Task;
   Ack_Task             : Reliable_Udp.Ack_Task;
   Rm_Task              : Reliable_Udp.Rm_Task;

   Server               : Socket_Type;
   Address, From        : Sock_Addr_Type;
   Watchdog             : Natural := 0;
   Start_Time           : Ada.Calendar.Time;
   Elapsed_Time         : Duration;
   Nb_Packet_Received   : Interfaces.Unsigned_64 := 0;
   Packet_Number        : Base_Udp.Header := 0;
   Missed               : Interfaces.Unsigned_64 := 0;
   Last_Nb              : Interfaces.Unsigned_64 := 0;
   Nb_Output            : Natural := 0;
   Log_File             : Ada.Text_IO.File_Type;
   Recv_Packets         : Receive_Packets;
   Busy                 : Interfaces.C.int := 50;
   Opt_Return           : Interfaces.C.int;

   function To_Int is
      new Ada.Unchecked_Conversion (GNAT.Sockets.Socket_Type, Interfaces.C.int);

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
      loop
         delay 1.0;
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
      end loop;
   end Timer;


   task body Receive_Packets is
      use type Ada.Calendar.Time;

      Packet   : Packet_Mgr.Packet_Content := (others => 0);
      Seq_Nb   : Base_Udp.Header;
      Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
      Header   : Reliable_Udp.Header;
      Last     : Ada.Streams.Stream_Element_Offset;
      --  New_Seq  : Boolean := False;

      for Data'Address use Packet'Address;
      for Header'Address use Data'Address;
      for Seq_Nb'Address use Data'Address;

      --  Exec_Start  : Ada.Real_Time.Time;
      --  Dur         : Duration;
      --  use Ada.Real_Time;
   begin
      accept Start;
      loop
         begin
            GNAT.Sockets.Receive_Socket (Server, Data, Last, From);

            if Header.Ack then
               Header.Ack := False;

               --  Exec_Start := Ada.Real_Time.Clock;

               Remove_Task.Remove (Seq_Nb);

               --  Dur := Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Exec_Start);
               --  Ada.Text_IO.Put_Line ("Remove : " & Dur'Img);
            else
               --  New_Seq := False;
               Nb_Packet_Received := Nb_Packet_Received + 1;
               if Nb_Packet_Received = 1 then
                  Start_Time := Ada.Calendar.Clock;
               end if;

               if Seq_Nb /= Packet_Number then
                  if Seq_Nb > Packet_Number then
                     Missed := Missed + Interfaces.Unsigned_64 (Seq_Nb - Packet_Number);
                  else
                     Missed := Missed + Interfaces.Unsigned_64 (Seq_Nb
                     + (Base_Udp.Pkt_Max - Packet_Number));
                     --  New_Seq := True;
                  end if;

                  --  Exec_Start := Ada.Real_Time.Clock;

                  Append_Task.Append (Packet_Number, Seq_Nb - 1, From);

                  --  Dur := Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Exec_Start);
                  --  Ada.Text_IO.Put_Line ("Append3 :     " & Dur'Img);

                  Packet_Number := Seq_Nb;
               end if;
               if Seq_Nb = Base_Udp.Pkt_Max then
                  Packet_Number := 0;
                  --  New_Seq := True;
               else
                  Packet_Number := Packet_Number + 1;
               end if;
            end if;
            --  Store_Packet_Task.Store (Data          => Packet,
            --                          New_Sequence  => New_Seq,
            --                          Is_Ack        => False);
         exception
            when Socket_Error =>
               Watchdog := Watchdog + 1;
               exit when Watchdog = 10;
         end;
      end loop;
   end Receive_Packets;

begin

   Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "log.csv");
   Ada.Text_IO.Put_Line (Log_File, "Nb_Output;Nb_Received;Packet_Nb;Dropped;Elapsed_Time");
   Ada.Text_IO.Close (Log_File);

   if Ada.Command_Line.Argument_Count = 1 then
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range'Value (Ada.Command_Line.Argument (1)));
   end if;

   Init_Udp;
   Ack_Task.Start;
   Rm_Task.Start;
   Recv_Packets.Start;
--  exception
--     when E : others =>
--        Ada.Text_IO.Put_Line (GNAT.Traceback.Symbolic.Symbolic_Traceback (E));
end UDP_Server;
