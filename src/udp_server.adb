with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Ada.Calendar;
with Interfaces.C;
with System.Multiprocessors.Dispatching_Domains;
with Ada.Containers.Vectors;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;
with Output_Data;
with Reliable_Udp;
with Packet_Mgr;

procedure UDP_Server is
   use GNAT.Sockets;
   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_8;

   type Packet is --  aliased
      record
         Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
         Offset   : Ada.Streams.Stream_Element_Offset;
         From     : Sock_Addr_Type;
      end record;

   task Timer;

   task type Append_Packet is

      entry Append (Pkt : in Packet);
   end Append_Packet;

   task type Process_Packets is
      entry Start;
   end Process_Packets;

   task type Receive_Packets is
      entry Start;
   end Receive_Packets;



   package Pkt_Container is
      new Ada.Containers.Vectors (Natural, Packet);

   protected type Packets_To_Process is
      procedure Process;
      procedure Append (Pkt   : in Packet);
   private
      Packet_List : Pkt_Container.Vector;
   end Packets_To_Process;

   Packet_Processing    : Packets_To_Process;
   Process_Pkt          : Process_Packets;
   App_Packet           : Append_Packet;

   Store_Packet_Task    : Packet_Mgr.Store_Packet_Task;
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
   Packet_Number        : Interfaces.Unsigned_8 := 0;
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

      task body Process_Packets is
      begin
         accept Start;
         Packet_Processing.Process;
      end Process_Packets;

      task body Append_Packet is
         New_Packet  : Packet;
      begin
            accept Append (Pkt : in Packet) do
               New_Packet := Pkt;
            end Append;

            Packet_Processing.Append (New_Packet);

      end Append_Packet;


      task body Receive_Packets is
         Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
         Last     : Ada.Streams.Stream_Element_Offset;
         Pkt      : Packet;
      begin
         accept Start;
         loop
            begin
               Ada.Text_IO.Put_Line ("Waiting");
               GNAT.Sockets.Receive_Socket (Server, Data, Last, From);
               Ada.Text_IO.Put_Line ("Received Packet");
               Pkt.Data := Data;
               Pkt.Offset := Last;
               Pkt.From := From;
               App_Packet.Append (Pkt);
               Ada.Text_IO.Put_Line ("Done");
               exception
               when Socket_Error =>
                  Watchdog := Watchdog + 1;
                  exit when Watchdog = 10;
            end;
         end loop;
      end Receive_Packets;

      protected body Packets_To_Process is

         procedure Process is
            --  Emitter  : Sock_Addr_Type;
            Pkt      : Packet_Mgr.Packet_Content := (others => 0);
            Data     : Ada.Streams.Stream_Element_Array (1 .. Base_Udp.Load_Size);
            Header   : Reliable_Udp.Header;

            for Data'Address use Pkt'Address;
            for Header'Address use Data'Address;
         begin
            loop
               if Pkt_Container.Is_Empty (Packet_List) = False then

                  Data := Pkt_Container.First_Element (Container => Packet_List).Data; -- Should dereference instead
                  --  Emitter := Pkt_Container.First_Element (Container => Packet_List).From;

                  if Header.Ack then
                     Header.Ack := False;
                     --  pragma Warnings (Off);
                     --  Remove_Task.Remove (Pkt (1));
                     --  pragma Warnings (On);
                  else
                     --  New_Seq := False;
                     Nb_Packet_Received := Nb_Packet_Received + 1;
                     if Nb_Packet_Received = 1 then
                        Start_Time := Ada.Calendar.Clock;
                     end if;

                     if Pkt (1) /= Packet_Number then
                        if Pkt (1) > Packet_Number then
                           Missed := Missed + (Interfaces.Unsigned_64 (Pkt (1))
                              - Interfaces.Unsigned_64 (Packet_Number));
                        else
                           Missed := Missed + (Interfaces.Unsigned_64 (Pkt (1))
                              + (Base_Udp.Pkt_Max - Interfaces.Unsigned_64 (Packet_Number)));
                           --  New_Seq := True;
                        end if;
                        --  pragma Warnings (Off);
                        --  Append_Task.Append (Packet_Number, Pkt (1) - 1, Emitter);
                        --  pragma Warnings (On);
                        Packet_Number := Pkt (1);
                     end if;
                     if Pkt (1) = Base_Udp.Pkt_Max then
                        Packet_Number := 0;
                        --  New_Seq := True;
                     else
                        Packet_Number := Packet_Number + 1;
                     end if;
                  end if;
                  --  Store_Packet_Task.Store (Data          => Packet,
                  --                          New_Sequence  => New_Seq,
                  --                          Is_Ack        => False);
                  Pkt_Container.Delete_First (Packet_List);
               end if;
            end loop;
         end Process;

         procedure Append (Pkt  : in Packet) is
         begin
            Pkt_Container.Append (Container  => Packet_List,
                                  New_Item   => Pkt);
         end Append;
      end Packets_To_Process;

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
      --  Process_Pkt.Start;
      Recv_Packets.Start;

end UDP_Server;
