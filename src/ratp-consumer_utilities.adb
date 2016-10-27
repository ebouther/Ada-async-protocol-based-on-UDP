with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Calendar;
with Ada.Real_Time;
with System.Multiprocessors.Dispatching_Domains;

with GNAT.Command_Line;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Ratp.Reliable_Udp;
with Ratp.Web_Interface;
with Ratp.Output_Data;

package body Ratp.Consumer_Utilities is

   Log_Task             : Ratp.Consumer_Utilities.Timer;

   Remove_Task          : Reliable_Udp.Remove_Task;
   Ack_Task             : Reliable_Udp.Ack_Task;

   Check_Integrity_Task : Buffer_Handling.Check_Buf_Integrity;
   Release_Buf_Task     : Buffer_Handling.Release_Full_Buf;

   Start_Time           : Ada.Calendar.Time;

   Nb_Packet_Received   : Interfaces.Unsigned_64 := 0;
   Packet_Number        : Reliable_Udp.Pkt_Nb := 0;
   Total_Missed         : Interfaces.Unsigned_64 := 0;
   Nb_Output            : Natural := 0;

   ---------------------
   --  Init_Consumer  --
   ---------------------

   procedure Init_Consumer is
      Log_File   : Ada.Text_IO.File_Type;
   begin
      Parse_Arguments;

      Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "log.csv");
      Ada.Text_IO.Put_Line (Log_File,
                  "Nb_Output;Nb_Received;Packet_Nb;Dropped;Elapsed_Time");
      Ada.Text_IO.Close (Log_File);

      Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "buffers.log");
      Ada.Text_IO.Close (Log_File);

      Web_Interface.Init_WebServer (Ratp.AWS_Port);

      Release_Buf_Task.Start;
      Ack_Task.Start;
      Check_Integrity_Task.Start;

      Buffer_Handling.Init_Buffers;

      Log_Task.Start;

   end Init_Consumer;


   -------------------
   --  Stop_Server  --
   -------------------

   procedure Stop_Server is
   begin
      Log_Task.Stop;
      Ack_Task.Stop;
      Remove_Task.Stop;
      PMH_Buffer_Task.Stop;

   end Stop_Server;


   -----------------------
   --  Parse_Arguments  --
   -----------------------

   procedure Parse_Arguments is
      use GNAT.Command_Line;
      use Ada.Command_Line;
      use Ada.Text_IO;
   begin
      loop
         if Getopt ("-end-point= -aws-port= -buf-name= -rtt-us-max= -udp-port= -help") = '-' then
            if Full_Switch = "-end-point" then
               Ratp.End_Point := Parameter;
            elsif Full_Switch = "-aws-port" then
               Ratp.AWS_Port := Integer'Value (Parameter);
            elsif Full_Switch = "-buf-name" then
               Ratp.Buffer_Name := Parameter;
            elsif Full_Switch = "-rtt-us-max" then
               Ratp.RTT_US_Max := Integer'Value (Parameter);
            elsif Full_Switch = "-udp-port" then
               Ratp.UDP_Port := GNAT.Sockets.Port_Type'Value (Parameter);
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
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (14));
      accept Start;
      loop
         select
            accept Stop;
            exit;
         else
            delay 1.0;
            Elapsed_Time := Ada.Calendar.Clock - Start_Time;
            Output_Data.Display
               (True,
               Elapsed_Time,
               Packet_Number,
               Total_Missed,
               Last_Missed,
               Nb_Packet_Received,
               Last_Nb,
               Nb_Output);
            Last_Nb := Nb_Packet_Received;
            Last_Missed := Total_Missed;
            Nb_Output := Nb_Output + 1;
         end select;
      end loop;
   end Timer;


   -------------------------------
   --  Wait_Producer_HandShake  --
   -------------------------------

   procedure Wait_Producer_HandShake (Host   : GNAT.Sockets.Inet_Addr_Type;
                                      Port   : GNAT.Sockets.Port_Type) is
      Socket   : Socket_Type;
      Data     : Ratp.Packet_Stream;
      Head     : Reliable_Udp.Header;
      From     : Sock_Addr_Type;
      Last     : Ada.Streams.Stream_Element_Offset;

      for Head'Address use Data'Address;

      Msg      : Reliable_Udp.Pkt_Nb renames Head.Seq_Nb;

      use type Interfaces.Unsigned_32;
      use type Interfaces.C.int;
      use type Reliable_Udp.Pkt_Nb;
      pragma Unreferenced (Last);
   begin
      Init_Udp (Socket, Host, Port, False);
      loop
         GNAT.Sockets.Receive_Socket (Socket, Data, Last, From);
         Reliable_Udp.Producer_Address := From;

         if Ratp.Acquisition and Msg = 0 then  --  Means producer is ready.
            exit;
         end if;
      end loop;
      Head.Ack := False;
      GNAT.Sockets.Send_Socket (Socket, Data, Last, From);
      GNAT.Sockets.Close_Socket (Socket);
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
      raise;
   end Wait_Producer_HandShake;


   ----------------------
   --  Process_Packet  --
   ----------------------

   procedure Process_Packet (Data         : in Ratp.Packet_Stream;
                             Last         : in Ada.Streams.Stream_Element_Offset;
                             Recv_Offset  : in out Interfaces.Unsigned_64;
                             Data_Addr    : in out System.Address;
                             From         : in Sock_Addr_Type)
   is
      Last_Addr            : System.Address;
      Nb_Missed            : Interfaces.Unsigned_64;
      Header               : Reliable_Udp.Header;

      for Header'Address use Data'Address;
      use type Reliable_Udp.Pkt_Nb;
      use type Ada.Real_Time.Time;
      use type Ada.Streams.Stream_Element_Offset;

   begin
      if Header.Ack then
         --  Activate Ack to differenciate size packets from "normal" packets.
         pragma Warnings (Off);
         Header.Ack := (if Last = 6 then True else False);
         pragma Warnings (On);

         Buffer_Handling.Save_Ack (Header.Seq_Nb, Packet_Number, Data);
         Remove_Task.Remove (Header.Seq_Nb);
         Recv_Offset := Recv_Offset - 1;
      else
         --  Activate Ack to differenciate size packets from "normal" packets.
         pragma Warnings (Off);
         Header.Ack := (if Last = 6 then True else False);
         pragma Warnings (On);

         Nb_Packet_Received := Nb_Packet_Received + 1;
         if Nb_Packet_Received = 1 then
            Start_Time := Ada.Calendar.Clock;
         end if;

         if Header.Seq_Nb /= Packet_Number then
            if Header.Seq_Nb > Packet_Number then
               Nb_Missed := Interfaces.Unsigned_64
                              (Header.Seq_Nb - Packet_Number);
               Total_Missed := Total_Missed + Nb_Missed;
            else
               Nb_Missed := Interfaces.Unsigned_64 (Header.Seq_Nb
                              + (Ratp.Pkt_Max - Packet_Number)) + 1;
               Total_Missed := Total_Missed + Nb_Missed;
            end if;

            Reliable_Udp.Fifo.Append_Wait ((From, Packet_Number, Header.Seq_Nb - 1));
            Packet_Number := Header.Seq_Nb;
            Last_Addr := Data_Addr;
            if Recv_Offset + Nb_Missed >= Ratp.Sequence_Size then
               PMH_Buffer_Task.New_Buffer_Addr (Buffer_Ptr => Data_Addr);
            end if;
            Buffer_Handling.Copy_To_Correct_Location
                                          (Recv_Offset, Nb_Missed, Data, Data_Addr);
            Buffer_Handling.Mark_Empty_Cell (Recv_Offset, Data_Addr, Last_Addr, Nb_Missed);
            Recv_Offset := Recv_Offset + Nb_Missed;
         end if;
         --  mod type (doesn't need to be set to 0 on max value)
         Packet_Number := Packet_Number + 1;
      end if;
   end Process_Packet;

end Ratp.Consumer_Utilities;
