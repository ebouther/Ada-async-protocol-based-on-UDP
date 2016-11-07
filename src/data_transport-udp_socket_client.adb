with Ada.Text_IO;
with Ada.Exceptions;
--  with System.Multiprocessors.Dispatching_Domains;
with System.Storage_Elements;
with Ada.Real_Time;

with GNAT.Command_Line;
with Ada.Command_Line;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Output_Data;

package body Data_Transport.Udp_Socket_Client is


   task body Socket_Client_Task is
      Handle_Data       : Buffer_Handling.Handle_Data_Task;

      Server            : Socket_Type;
      Cons_Addr         : GNAT.Sockets.Inet_Addr_Type;
      Cons_Port         : GNAT.Sockets.Port_Type;

      From              : Sock_Addr_Type;
      Last              : Ada.Streams.Stream_Element_Offset;
      Data_Addr         : System.Address;
      Recv_Offset       : Interfaces.Unsigned_64 := Base_Udp.Pkt_Max + 1;

      Consumer          : constant Consumer_Access := new Consumer_Type;

      use System.Storage_Elements;
      use type Interfaces.C.int;
      use type Buffers.Buffer_Produce_Access;
   begin
      --  System.Multiprocessors.Dispatching_Domains.Set_CPU
      --     (System.Multiprocessors.CPU_Range (16));
      select
         accept Initialise (Buf_Name   : Ada.Strings.Unbounded.Unbounded_String;
                            End_Point  : Ada.Strings.Unbounded.Unbounded_String;
                            Host       : String;
                            Port       : GNAT.Sockets.Port_Type) do

            --  Cons_Addr := GNAT.Sockets.Addresses
            --            (GNAT.Sockets.Get_Host_By_Name (Host));
            pragma Unreferenced (Host);

            Cons_Addr := Any_Inet_Addr;
            Cons_Port := Port;

            Consumer.Buffer_Name := Buf_Name;
            Consumer.End_Point := End_Point;
            Init_Consumer (Consumer);

            Init_Udp (Server, Cons_Addr, Cons_Port);
            if Buffer_Set /= null then
               Handle_Data.Start (Consumer.Buffer_Handler, Buffer_Set);
            end if;

            Consumer.PMH_Buffer_Task.Start (Consumer.Buffer_Handler);

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
      Wait_Producer_HandShake (Consumer, Cons_Addr, Cons_Port);
      Ada.Text_IO.Put_Line ("Producer is ready...");

      loop
         select
            accept Disconnect;
               Ada.Text_IO.Put_Line ("[Disconnect]");
               --  Send producer stop msg
               exit;
         else
            if Recv_Offset > Base_Udp.Pkt_Max then
               Consumer.PMH_Buffer_Task.New_Buffer_Addr (Buffer_Ptr => Data_Addr);
               Recv_Offset := Recv_Offset mod Base_Udp.Sequence_Size;
            end if;

            declare
               Data     : Base_Udp.Packet_Stream;

               for Data'Address use Data_Addr + Storage_Offset
                                                   (Recv_Offset * Base_Udp.Load_Size);
               use type Ada.Streams.Stream_Element_Offset;
            begin
               GNAT.Sockets.Receive_Socket (Server, Data, Last, From);
               Process_Packet (Consumer, Data, Last, Recv_Offset, Data_Addr, From);
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


   ---------------------
   --  Init_Consumer  --
   ---------------------

   procedure Init_Consumer (Consumer : Consumer_Access) is

      --  Log_File : Ada.Text_IO.File_Type;
      use Ada.Strings.Unbounded;
   begin
      Parse_Arguments (Consumer);

      --  Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "log.csv");
      --  Ada.Text_IO.Put_Line (Log_File,
      --              "Nb_Output;Nb_Received;Packet_Nb;Dropped;Elapsed_Time");
      --  Ada.Text_IO.Close (Log_File);

      --  Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "buffers.log");
      --  Ada.Text_IO.Close (Log_File);

      --  Web_Interfaces.Init_WebServer (Consumer.Web_Interface); *********** DO NOT FORGET TO UNCOMMENT ***************

      Consumer.Release_Buf_Task.Start (Consumer.Buffer_Handler);
      Consumer.Ack_Task.Start (Consumer.Ack_Mgr);
      Consumer.Check_Integrity_Task.Start (Consumer.Buffer_Handler);

      Buffer_Handling.Init_Buffers (Consumer.Buffer_Handler,
                                    To_String (Consumer.Buffer_Name),
                                    To_String (Consumer.End_Point));

      Consumer.Log_Task.Start (Consumer);

      Consumer.Append_Task.Start (Consumer.Ack_Mgr, Consumer.Ack_Fifo);
      Consumer.Remove_Task.Initialize (Consumer.Ack_Mgr);

   end Init_Consumer;


   --  -------------------
   --  --  Stop_Server  --
   --  -------------------

   --  procedure Stop_Server is
   --  begin
   --     Log_Task.Stop;
   --     Ack_Task.Stop;
   --     Remove_Task.Stop;
   --     PMH_Buffer_Task.Stop;

   --  end Stop_Server;


   -----------------------
   --  Parse_Arguments  --
   -----------------------

   procedure Parse_Arguments (Consumer :  Consumer_Access) is
      use GNAT.Command_Line;
      use Ada.Command_Line;
      use Ada.Text_IO;
   begin
      loop
         if Getopt ("-end-point= -aws-port= -buf-name= -rtt-us-max= -udp-port= -help") = '-' then
            if Full_Switch = "-end-point" then
               Consumer.End_Point := Ada.Strings.Unbounded.To_Unbounded_String (Parameter);
            elsif Full_Switch = "-aws-port" then
               Consumer.AWS_Port := Integer'Value (Parameter);
            elsif Full_Switch = "-buf-name" then
               Consumer.Buffer_Name := Ada.Strings.Unbounded.To_Unbounded_String (Parameter);
            elsif Full_Switch = "-rtt-us-max" then
               Base_Udp.RTT_US_Max := Integer'Value (Parameter);
            elsif Full_Switch = "-udp-port" then
               Consumer.UDP_Port := GNAT.Sockets.Port_Type'Value (Parameter);
            elsif Full_Switch = "-help" then
               New_Line;
               Put_Line ("Options :");
               New_Line;
               Put_Line ("--end-point (default http://127.0.0.1:5678)");
               Put_Line ("--aws-port (default 80)");
               Put_Line ("--buf-name (default toto)");
               Put_Line ("--rtt-us-max (default 150 us)");
               Put_Line ("--udp-port (default 50001)");
               Put_Line ("--help");
               New_Line;
            else
               Put_Line ("/!\ Some arguments have not been taken into account. /!\");
               Put_Line ("Unknown argument :" & Full_Switch);
               Put_Line ("Use --help to see" & Command_Name & "'s options.");
               New_Line;
            end if;
         else
            exit;
         end if;
      end loop;
   end Parse_Arguments;


   ----------------
   --  Init_Udp  --
   ----------------
   procedure Init_Udp (Server       : in out Socket_Type;
                       Host         : GNAT.Sockets.Inet_Addr_Type;
                       Port         : GNAT.Sockets.Port_Type;
                       TimeOut_Opt  : Boolean := True) is
      Address     : Sock_Addr_Type;
      Busy        : Interfaces.C.int := 50;
      Opt_Return  : Interfaces.C.int;
      pragma Unreferenced (Opt_Return);
   begin
      Create_Socket (Server, Family_Inet, Socket_Datagram);
      Set_Socket_Option
         (Server,
         Socket_Level,
         (Reuse_Address, True));
      if TimeOut_Opt then
         Set_Socket_Option
            (Server,
            Socket_Level,
            (Receive_Timeout,
            Timeout => 1.0));
      end if;
      Opt_Return := Thin.C_Setsockopt (S        => To_Int (Server),
                                       Level    => 1,
                                       Optname  => 46,  --  BUSY_POLL
                                       Optval   => Busy'Address,
                                       Optlen   => 4);
      Address.Addr := Host;
      Address.Port := Port;
      Bind_Socket (Server, Address);
   end Init_Udp;


   -------------
   --  Timer  --
   -------------

   task body Timer is
      use type Ada.Calendar.Time;

      Last_Missed    : Interfaces.Unsigned_64 := 0;
      Last_Nb        : Interfaces.Unsigned_64 := 0;
      Elapsed_Time   : Duration;
      Consumer       : Consumer_Access;
   begin
      --  System.Multiprocessors.Dispatching_Domains.Set_CPU
      --     (System.Multiprocessors.CPU_Range (14));
      accept Start (Cons      : Consumer_Access) do
         Consumer := Cons;
      end Start;
      loop
         select
            accept Stop;
            exit;
         else
            delay 1.0;
            Elapsed_Time := Ada.Calendar.Clock - Consumer.Start_Time;
            Output_Data.Display
               (Consumer.Web_Interface,
                False,
                Elapsed_Time,
                Consumer.Packet_Number,
                Consumer.Total_Missed,
                Last_Missed,
                Consumer.Nb_Packet_Received,
                Last_Nb,
                Consumer.Nb_Output);
            Last_Nb := Consumer.Nb_Packet_Received;
            Last_Missed := Consumer.Total_Missed;
            Consumer.Nb_Output := Consumer.Nb_Output + 1;
         end select;
      end loop;
   end Timer;


   -------------------------------
   --  Wait_Producer_HandShake  --
   -------------------------------

   procedure Wait_Producer_HandShake (Consumer  : Consumer_Access;
                                      Host      : GNAT.Sockets.Inet_Addr_Type;
                                      Port      : GNAT.Sockets.Port_Type)
   is
      Dbg   : Boolean := False;
      Socket   : Socket_Type;
      Data     : Base_Udp.Packet_Stream;
      Head     : Reliable_Udp.Header_Type;
      From     : Sock_Addr_Type;
      Last     : Ada.Streams.Stream_Element_Offset;

      for Head'Address use Data'Address;

      Msg      : Reliable_Udp.Packet_Number_Type renames Head.Seq_Nb;

      use type Interfaces.Unsigned_32;
      use type Interfaces.C.int;
      use type Reliable_Udp.Packet_Number_Type;
      pragma Unreferenced (Last);
   begin
      Init_Udp (Socket, Host, Port, False);
      loop
         GNAT.Sockets.Receive_Socket (Socket, Data, Last, From);
         if Reliable_Udp.Producer_Address = From then
            Dbg := True;
         end if;
         Reliable_Udp.Producer_Address := From;

         if Consumer.Acquisition and Msg = 0 then  --  Means producer is ready.
            exit;
         end if;
      end loop;
      Head.Ack := False;
      if Dbg then
         GNAT.Sockets.Send_Socket (Socket, Data, Last, From);
      end if;
      GNAT.Sockets.Close_Socket (Socket);
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
   end Wait_Producer_HandShake;


   ----------------------
   --  Process_Packet  --
   ----------------------

   procedure Process_Packet (Consumer     : Consumer_Access;
                             Data         : in Base_Udp.Packet_Stream;
                             Last         : in Ada.Streams.Stream_Element_Offset;
                             Recv_Offset  : in out Interfaces.Unsigned_64;
                             Data_Addr    : in out System.Address;
                             From         : in Sock_Addr_Type)
   is
      Last_Addr            : System.Address;
      Nb_Missed            : Interfaces.Unsigned_64;
      Header               : Reliable_Udp.Header_Type;

      for Header'Address use Data'Address;
      use type Reliable_Udp.Packet_Number_Type;
      use type Ada.Real_Time.Time;
      use type Ada.Streams.Stream_Element_Offset;

   begin
      if Header.Ack then
         --  Activate Ack to differenciate size packets from "normal" packets.
         pragma Warnings (Off);
         Header.Ack := (if Last = 6 then True else False);
         pragma Warnings (On);

         Buffer_Handling.Save_Ack (Consumer.Buffer_Handler, Header.Seq_Nb, Consumer.Packet_Number, Data);
         Consumer.Remove_Task.Remove (Header.Seq_Nb);
         Recv_Offset := Recv_Offset - 1;
      else
         --  Activate Ack to differenciate size packets from "normal" packets.
         pragma Warnings (Off);
         Header.Ack := (if Last = 6 then True else False);
         pragma Warnings (On);

         Consumer.Nb_Packet_Received := Consumer.Nb_Packet_Received + 1;
         if Consumer.Nb_Packet_Received = 1 then
            Consumer.Start_Time := Ada.Calendar.Clock;
         end if;

         if Header.Seq_Nb /= Consumer.Packet_Number then
            if Header.Seq_Nb > Consumer.Packet_Number then
               Nb_Missed := Interfaces.Unsigned_64
                              (Header.Seq_Nb - Consumer.Packet_Number);
               Consumer.Total_Missed := Consumer.Total_Missed + Nb_Missed;
            else
               Nb_Missed := Interfaces.Unsigned_64 (Header.Seq_Nb
                              + (Base_Udp.Pkt_Max - Consumer.Packet_Number)) + 1;
               Consumer.Total_Missed := Consumer.Total_Missed + Nb_Missed;
            end if;

            Consumer.Ack_Fifo.all.Append_Wait ((From, Consumer.Packet_Number, Header.Seq_Nb - 1));
            Consumer.Packet_Number := Header.Seq_Nb;
            Last_Addr := Data_Addr;
            if Recv_Offset + Nb_Missed >= Base_Udp.Sequence_Size then
               Consumer.PMH_Buffer_Task.New_Buffer_Addr (Buffer_Ptr => Data_Addr);
            end if;
            Buffer_Handling.Copy_To_Correct_Location
                                          (Recv_Offset, Nb_Missed, Data, Data_Addr);
            Buffer_Handling.Mark_Empty_Cell (Recv_Offset, Data_Addr, Last_Addr, Nb_Missed);
            Recv_Offset := Recv_Offset + Nb_Missed;
         end if;
         --  mod type (doesn't need to be set to 0 on max value)
         Consumer.Packet_Number := Consumer.Packet_Number + 1;
      end if;
   end Process_Packet;


end Data_Transport.Udp_Socket_Client;
