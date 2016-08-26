with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams;
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
with Queue;

procedure UDP_Server is
   use GNAT.Sockets;

   use type Base_Udp.Header;
   use type Interfaces.Unsigned_64;

   task Timer;

   task type Receive_Packets is
      entry Start;
   end Receive_Packets;

   task type Recv_Socket is
      entry Start;
   end Recv_Socket;

   type Packet_Stream is new Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);

   type Socket_Data is
      record
         Data  : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
         From  : Sock_Addr_Type;
      end record;

   --  Store_Packet_Task    : Packet_Mgr.Store_Packet_Task;
   package Packet_Queue is new Queue (Packet_Stream);
   Buffer : Packet_Queue.Synchronized_Queue;

   Append_Task          : Reliable_Udp.Append_Task;
   Remove_Task          : Reliable_Udp.Remove_Task;
   Ack_Task             : Reliable_Udp.Ack_Task;
   Recv_Socket_Task     : Recv_Socket;

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

   task body Recv_Socket is
      Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
      Last     : Ada.Streams.Stream_Element_Offset;
   begin
      accept Start;
      loop
         GNAT.Sockets.Receive_Socket (Server, Data, Last, From);
         -- Buffer.Append_Wait (Data);
      end loop;
   end Recv_Socket;


   task body Receive_Packets is
      use type Ada.Calendar.Time;

      Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
      Packet   : array (1 .. Base_Udp.Load_Size) of Interfaces.Unsigned_8 := (others => 0);
      Seq_Nb   : Base_Udp.Header;
      Header   : Reliable_Udp.Header;
      --  New_Seq  : Boolean := False;

      for Data'Address use Packet'Address;
      for Header'Address use Data'Address;
      for Seq_Nb'Address use Data'Address;

   begin
      accept Start;
      loop
         begin
            -- Buffer.Remove_Wait (Data);
            if Header.Ack then
               Header.Ack := False;
               --  Ada.Text_IO.Put_Line ("Received Ack : " & Seq_Nb'Img);
               --  Remove_Task.Remove (Seq_Nb);

            else
               --  New_Seq := False;
               Nb_Packet_Received := Nb_Packet_Received + 1;
               if Nb_Packet_Received = 1 then
                  Start_Time := Ada.Calendar.Clock;
               end if;

               if Seq_Nb /= Packet_Number then
                  if Seq_Nb > Packet_Number then
                     Missed := Missed + Interfaces.Unsigned_64 (Seq_Nb - Packet_Number);
                  else -- Doesn't manage disordered packets, if a packet is received before the previous sent.
                     Missed := Missed + Interfaces.Unsigned_64 (Seq_Nb
                        + (Base_Udp.Pkt_Max - Packet_Number));
                     --  New_Seq := True;
                  end if;

                  --  Append_Task.Append (Packet_Number, Seq_Nb - 1, From);

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
   Recv_Socket_Task.Start;
   Ack_Task.Start;
   Recv_Packets.Start;
--  exception
--     when E : others =>
--        Ada.Text_IO.Put_Line (GNAT.Traceback.Symbolic.Symbolic_Traceback (E));
end UDP_Server;
