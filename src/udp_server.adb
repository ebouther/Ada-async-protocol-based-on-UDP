with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Unchecked_Conversion;
with Ada.Calendar;
with Interfaces.C;
with System.Multiprocessors.Dispatching_Domains;
with System.Storage_Elements;
with Ada.Real_Time;

with GNAT.Command_Line;
with GNAT.Traceback.Symbolic;
with System;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Base_Udp;
with Output_Data;
with Reliable_Udp;
with Buffer_Handling;
with Web_Interface;


procedure UDP_Server is
   pragma Optimize (Time);

   use GNAT.Sockets;

   use type Base_Udp.Header;
   use type Interfaces.Unsigned_64;

   task type Timer is
      entry Start;
      entry Stop;
   end Timer;

   task type Recv_Socket is
      entry Start;
      entry Stop;
   end Recv_Socket;

   pragma Warnings (Off);
   procedure Wait_Client_HandShake;
   pragma Warnings (On);

   procedure Process_Packet (Data      : in Base_Udp.Packet_Stream;
                             Header    : in Reliable_Udp.Header;
                             I         : in out Interfaces.Unsigned_64;
                             Data_Addr : in out System.Address;
                             From      : in Sock_Addr_Type);


   function To_Int is
      new Ada.Unchecked_Conversion
         (GNAT.Sockets.Socket_Type, Interfaces.C.int);

   procedure Parse_Arguments;

   procedure Init_Udp (Server       : in out Socket_Type;
                       TimeOut_Opt  : Boolean := True);

   pragma Warnings (Off);
   procedure Stop_Server;
   pragma Warnings (On);


   Remove_Task          : Reliable_Udp.Remove_Task;
   Ack_Task             : Reliable_Udp.Ack_Task;

   Recv_Socket_Task     : Recv_Socket;
   Log_Task             : Timer;

   Check_Integrity_Task : Buffer_Handling.Check_Buf_Integrity;
   PMH_Buffer_Task      : Buffer_Handling.PMH_Buffer_Addr;
   Release_Buf_Task     : Buffer_Handling.Release_Full_Buf;

   Start_Time           : Ada.Calendar.Time;
   Elapsed_Time         : Duration;
   Nb_Packet_Received   : Interfaces.Unsigned_64 := 0;
   Packet_Number        : Reliable_Udp.Pkt_Nb := 0;
   Missed               : Interfaces.Unsigned_64 := 0;
   Nb_Output            : Natural := 0;
   Log_File             : Ada.Text_IO.File_Type;
   Busy                 : Interfaces.C.int := 50;
   Opt_Return           : Interfaces.C.int;
   pragma Unreferenced (Opt_Return);


   -------------------
   --  Stop_Server  --
   -------------------

   procedure Stop_Server is
   begin
      Log_Task.Stop;
      Ack_Task.Stop;
      Remove_Task.Stop;
      PMH_Buffer_Task.Stop;
      Recv_Socket_Task.Stop;

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
               Base_Udp.End_Point := Parameter;
            elsif Full_Switch = "-aws-port" then
               Base_Udp.AWS_Port := Integer'Value (Parameter);
            elsif Full_Switch = "-buf-name" then
               Base_Udp.Buffer_Name := Parameter;
            elsif Full_Switch = "-rtt-us-max" then
               Base_Udp.RTT_US_Max := Integer'Value (Parameter);
            elsif Full_Switch = "-udp-port" then
               Base_Udp.UDP_Port := GNAT.Sockets.Port_Type'Value (Parameter);
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

   procedure Init_Udp (Server     : in out Socket_Type;
                      TimeOut_Opt : Boolean := True) is
      Address  : Sock_Addr_Type;
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
            Timeout => 2.0));
      end if;
      Opt_Return := Thin.C_Setsockopt (S        => To_Int (Server),
                                       Level    => 1,
                                       Optname  => 46,
                                       Optval   => Busy'Address,
                                       Optlen   => 4);
      Address.Addr := Any_Inet_Addr;
      Address.Port := Base_Udp.UDP_Port;
      Bind_Socket (Server, Address);
   end Init_Udp;


   -------------
   --  Timer  --
   -------------

   task body Timer is
      use type Ada.Calendar.Time;

      Last_Missed : Interfaces.Unsigned_64 := 0;
      Last_Nb     : Interfaces.Unsigned_64 := 0;
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
            Ada.Text_IO.Put_Line ("FIFO Len : " & Reliable_Udp.Fifo.Cur_Count'Img);
            Elapsed_Time := Ada.Calendar.Clock - Start_Time;
            Output_Data.Display
               (True,
               Elapsed_Time,
               Packet_Number,
               Missed,
               Last_Missed,
               Nb_Packet_Received,
               Last_Nb,
               Nb_Output);
            Last_Nb := Nb_Packet_Received;
            Last_Missed := Missed;
            Nb_Output := Nb_Output + 1;
         end select;
      end loop;
   end Timer;


   ----------------------
   --  Process_Packet  --
   ----------------------

   --  0.000007
   --  7.25E-05 ratio
   procedure Process_Packet (Data      : in Base_Udp.Packet_Stream;
                             Header    : in Reliable_Udp.Header;
                             I         : in out Interfaces.Unsigned_64;
                             Data_Addr : in out System.Address;
                             From      : in Sock_Addr_Type)
   is
      Last_Addr            : System.Address;
      Nb_Missed            : Interfaces.Unsigned_64;

      use type Reliable_Udp.Pkt_Nb;
      use type Ada.Real_Time.Time;
   begin

      if Header.Ack then
         Buffer_Handling.Save_Ack (Header.Seq_Nb, Packet_Number, Data);
         Remove_Task.Remove (Header.Seq_Nb);
         I := I - 1;
      else
         Nb_Packet_Received := Nb_Packet_Received + 1;
         if Nb_Packet_Received = 1 then
            Start_Time := Ada.Calendar.Clock;
         end if;

         if Header.Seq_Nb /= Packet_Number then
            if Header.Seq_Nb > Packet_Number then
               Nb_Missed := Interfaces.Unsigned_64
                              (Header.Seq_Nb - Packet_Number);
               Missed := Missed + Nb_Missed;
            else
               Nb_Missed := Interfaces.Unsigned_64 (Header.Seq_Nb
                              + (Base_Udp.Pkt_Max - Packet_Number)) + 1;
               Missed := Missed + Nb_Missed;
               Ada.Text_IO.Put_Line ("Append From "
                              & Packet_Number'Img & " To"
                              & Integer ((Header.Seq_Nb - 1))'Img);
            end if;

            Reliable_Udp.Fifo.Append_Wait ((From, Packet_Number, Header.Seq_Nb - 1));
            Packet_Number := Header.Seq_Nb;
            Last_Addr := Data_Addr;
            if I + Nb_Missed >= Base_Udp.Sequence_Size then
               PMH_Buffer_Task.New_Buffer_Addr (Buffer_Ptr => Data_Addr);
            end if;
            Buffer_Handling.Copy_To_Correct_Location
                                          (I, Nb_Missed, Data, Data_Addr);
            Buffer_Handling.Mark_Empty_Cell (I, Data_Addr, Last_Addr, Nb_Missed);
            I := I + Nb_Missed;
         end if;
         --  mod type (doesn't need to be set to 0 on max value)
         Packet_Number := Packet_Number + 1;
      end if;
   end Process_Packet;


   procedure Wait_Client_HandShake is
      Socket   : Socket_Type;
      Data     : Base_Udp.Packet_Stream;
      Head     : Reliable_Udp.Header;
      From     : Sock_Addr_Type;
      Last     : Ada.Streams.Stream_Element_Offset;

      --  Client is waiting for handshake (acquisition was stopped)
      Acq_Stop : Boolean := (if Nb_Packet_Received /= 0 then True else False);

      for Head'Address use Data'Address;

      use type Interfaces.Unsigned_32;
      use type Interfaces.C.int;
      use type Reliable_Udp.Pkt_Nb;
      pragma Unreferenced (Last);
   begin
      Init_Udp (Socket, False);
      loop
         if Acq_Stop = False then  -- Could fail if packet is lost !!
            GNAT.Sockets.Receive_Socket (Socket, Data, Last, From);
            Reliable_Udp.Client_Address := From;
            Acq_Stop := True;
         end if;

         exit when Head.Seq_Nb = 0;  --  Means client is ready.
      end loop;
      Head.Ack := False;
      GNAT.Sockets.Send_Socket (Socket, Data, Last, From);
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end Wait_Client_HandShake;


   -------------------
   --  Recv_Socket  --
   -------------------

   task body Recv_Socket is
      Server               : Socket_Type;
      From                 : Sock_Addr_Type;
      Last                 : Ada.Streams.Stream_Element_Offset;
      Watchdog             : Natural := 0;
      Data_Addr            : System.Address;
      I                    : Interfaces.Unsigned_64;

      use System.Storage_Elements;
      use type Interfaces.C.int;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (16));

      Buffer_Handling.Init_Buffers;

      accept Start;

      <<HandShake>>
      I := Base_Udp.Pkt_Max + 1;

      Ada.Text_IO.Put_Line ("...Waiting for Client...");
      Wait_Client_HandShake;
      Ada.Text_IO.Put_Line ("Client is ready...");

      --  Would get stuck if Handshake is re-called
      select
         Log_Task.Start;
      else
         null;
      end select;

      Init_Udp (Server);

      loop
         select
            accept Stop;
               exit;
         else
            if I > Base_Udp.Pkt_Max then
               PMH_Buffer_Task.New_Buffer_Addr (Buffer_Ptr => Data_Addr);
               I := I mod Base_Udp.Sequence_Size;
            end if;

            declare
               Data     : Base_Udp.Packet_Stream;
               Header   : Reliable_Udp.Header;

               for Data'Address use Data_Addr + Storage_Offset
                                                   (I * Base_Udp.Load_Size);
               for Header'Address use Data'Address;
            begin
               GNAT.Sockets.Receive_Socket (Server, Data, Last, From);
               Process_Packet (Data, Header, I, Data_Addr, From);
               I := I + 1;
            exception
               when Socket_Error =>
                  Watchdog := Watchdog + 1;
                  Ada.Text_IO.Put_Line ("Socket Error");
                  exit when Watchdog = 10;
                  goto HandShake;
            end;
         end select;
      end loop;
   end Recv_Socket;

begin
   Parse_Arguments;

   Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "log.csv");
   Ada.Text_IO.Put_Line (Log_File,
               "Nb_Output;Nb_Received;Packet_Nb;Dropped;Elapsed_Time");
   Ada.Text_IO.Close (Log_File);

   Ada.Text_IO.Create (Log_File, Ada.Text_IO.Out_File, "buffers.log");
   Ada.Text_IO.Close (Log_File);

   Web_Interface.Init_WebServer (Base_Udp.AWS_Port);

   Recv_Socket_Task.Start;
   Release_Buf_Task.Start;
   --  Process_Pkt.Start;
   Ack_Task.Start;
   Check_Integrity_Task.Start;

   --  delay 40.0;
   --  Stop_Server;

exception
   when E : others =>
      Ada.Text_IO.Put_Line (GNAT.Traceback.Symbolic.Symbolic_Traceback (E));
end UDP_Server;
