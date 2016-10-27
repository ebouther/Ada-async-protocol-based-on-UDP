with Ada.Text_IO;
with Ada.Calendar;
with Ada.Exceptions;
with System;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

package body Data_Transport.Udp_Socket_Server is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Interfaces.C.int;
   use type Ada.Streams.Stream_Element_Offset;

   use type Ratp.Reliable_Udp.Pkt_Nb;

   Socket                  : GNAT.Sockets.Socket_Type;
   Send_Throughput_Gb      : Float := 0.0;
   Send_Throughput_Start   : Ada.Calendar.Time;
   Address                 : GNAT.Sockets.Sock_Addr_Type;
   Acquisition             : Boolean := True;
   Last_Packets            : array (Ratp.Reliable_Udp.Pkt_Nb)
                              of History_Type;

   task body Reset_Send_Throughput is
   begin
      loop
         Send_Throughput_Gb := 0.0;
         Send_Throughput_Start := Ada.Calendar.Clock;
         delay 10.0;
      end loop;
   end Reset_Send_Throughput;


   task body Socket_Server_Task is
      Packet_Number : Ratp.Reliable_Udp.Pkt_Nb := 0;
   begin
      select
         accept Initialise
           (Network_Interface : String;
            Port : GNAT.Sockets.Port_Type) do

            Address.Addr := GNAT.Sockets.Addresses
                            (GNAT.Sockets.Get_Host_By_Name (Network_Interface));
            Address.Port := Port;
            GNAT.Sockets.Create_Socket
               (Socket,
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
      Server_HandShake;
      Acquisition := True;
      delay 0.0001;
      Ada.Text_IO.Put_Line ("Consumer ready, start sending packets...");

      loop
         select
            accept Disconnect;
               GNAT.Sockets.Close_Socket (Socket);
               exit;
         else
            if Acquisition then
               Rcv_Ack;
               select
                  Buffer_Set.Block_Full;
                  Send_Buffer_Data (Buffer_Set, Packet_Number);
               else
                  null;
               end select;
            else
               declare
                  Start_Time  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
                  use type Ada.Calendar.Time;
               begin
                  loop
                     Rcv_Ack;
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


   ------------------------
   --  Server_HandShake  --
   ------------------------

   procedure Server_HandShake is
      Send_Data, Recv_Data : Ratp.Packet_Stream;
      Send_Head, Recv_Head : Ratp.Reliable_Udp.Header;

      for Send_Head'Address use Send_Data'Address;
      for Recv_Head'Address use Recv_Data'Address;
      Recv_Msg    : Ratp.Reliable_Udp.Pkt_Nb renames Recv_Head.Seq_Nb;
      Send_Msg    : Ratp.Reliable_Udp.Pkt_Nb renames Send_Head.Seq_Nb;
      Not_A_Msg   : Boolean renames Recv_Head.Ack;
   begin
      Send_Msg := 0;
      loop
         Send_Packet (Send_Data);
         delay 0.2;
         exit when GNAT.Sockets.Thin.C_Recv
               (To_Int (Socket),
                Recv_Data (Recv_Data'First)'Address,
                Recv_Data'Length,
                64) /= -1
               and Not_A_Msg = False
               and Recv_Msg = Send_Msg;
      end loop;
   end Server_HandShake;


   ------------------------
   --  Send_Buffer_Data  --
   ------------------------

   procedure Send_Buffer_Data (Buffer_Set    : Buffers.Buffer_Consume_Access;
                               Packet_Number : in out Ratp.Reliable_Udp.Pkt_Nb) is

      Null_Buffer_Size  : exception;
      Buffer_Handle     : Buffers.Buffer_Handle_Type;
   begin
      Buffer_Set.Get_Full_Buffer (Buffer_Handle);
      declare
         Data_Size : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset
           (Buffers.Get_Used_Bytes (Buffer_Handle));

         Buffer_Size : Interfaces.Unsigned_32 :=
            --  Network_Utils.To_Network (Interfaces.Unsigned_32 (Buffer_Set.Full_Size));
            Interfaces.Unsigned_32 (Buffer_Set.Full_Size);

         Data     : Ada.Streams.Stream_Element_Array (1 .. Data_Size);
         Header   : Ratp.Reliable_Udp.Header;

         for Data'Address use Buffers.Get_Address (Buffer_Handle);
         for Header'Address use Last_Packets (Packet_Number).Data'Address;
         for Buffer_Size'Address use Last_Packets (Packet_Number).Data
                                       (Ratp.Header_Size + 1)'Address;
      begin
         if Buffer_Size = 0 then
            raise Null_Buffer_Size with "Buffer's Size Equal 0";
         end if;
         Header := (Ack => False,
                    Seq_Nb => Packet_Number);
         Last_Packets (Packet_Number).Is_Buffer_Size := True;
         Send_Packet (Last_Packets (Packet_Number).Data, True);
         Packet_Number := Packet_Number + 1;
         Send_All_Stream (Data, Packet_Number);
      exception
         when E : others =>
            Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
               Ada.Exceptions.Exception_Name (E)
               & ASCII.LF & ASCII.ESC & "[33m"
               & Ada.Exceptions.Exception_Message (E)
               & ASCII.ESC & "[0m");
            raise;
      end;
      Buffer_Set.Release_Full_Buffer (Buffer_Handle);
   end Send_Buffer_Data;


   -----------------------
   --  Send_All_Stream  --
   -----------------------

   procedure Send_All_Stream (Payload        : Ada.Streams.Stream_Element_Array;
                              Packet_Number  : in out Ratp.Reliable_Udp.Pkt_Nb) is
      use type Ada.Streams.Stream_Element_Array;

      First    : Ada.Streams.Stream_Element_Offset := Payload'First;
      Offset   : Ada.Streams.Stream_Element_Offset;
      Last     : Ada.Streams.Stream_Element_Offset;
   begin
      loop
         Rcv_Ack;
         declare
            Head     : Ada.Streams.Stream_Element_Array (1 .. 2);
            Header   : Ratp.Reliable_Udp.Header := (Ack => False,
                                               Seq_Nb => Packet_Number);

            for Header'Address use Head'Address;
            use type Ada.Calendar.Time;
         begin
            Last := First + (Ratp.Load_Size - Ratp.Header_Size) - 1;

            if Last > Payload'Last then
               declare
                  Pad   : constant Ada.Streams.Stream_Element_Array
                           (1 .. Last - Payload'Last) := (others => 0);
               begin
                  Last_Packets (Packet_Number).Data := Head & Payload
                        (First .. Payload'Last) & Pad;
               end;
            else
               Last_Packets (Packet_Number).Data := Head & Payload
                     (First .. Last);
            end if;
            Last_Packets (Packet_Number).Is_Buffer_Size := False;
            while Float (Duration (Send_Throughput_Gb)
               / (Ada.Calendar.Clock - Send_Throughput_Start))
                     > Ratp.Throughput_Gbs loop
               delay 0.0;
            end loop;
            GNAT.Sockets.Send_Socket (Socket, Last_Packets (Packet_Number).Data,
                                       Offset, Address);
            Send_Throughput_Gb := Send_Throughput_Gb
                                    + (Float (Last_Packets (Packet_Number).Data'Last + 28)
                                       * Float (System.Storage_Unit) / Float (10 ** 9));
            Packet_Number := Packet_Number + 1;
         end;
         First := Last + 1;
         exit when First > Payload'Last;
      end loop;
   end Send_All_Stream;


   -------------------
   --  Send_Packet  --
   -------------------

   procedure Send_Packet (Payload : Ratp.Packet_Stream;
                          Is_Buffer_Size : Boolean := False) is
      Offset   : Ada.Streams.Stream_Element_Offset;
      Data     : Ada.Streams.Stream_Element_Array
                     (1 .. (if Is_Buffer_Size then 6 else Ratp.Load_Size));

      for Data'Address use Payload'Address;
      pragma Unreferenced (Offset);
      use type Ada.Calendar.Time;
   begin

      while Float (Duration (Send_Throughput_Gb) / (Ada.Calendar.Clock - Send_Throughput_Start))
             > Ratp.Throughput_Gbs loop
         delay 0.0;
      end loop;
      GNAT.Sockets.Send_Socket (Socket, Data, Offset, Address);
      Send_Throughput_Gb := Send_Throughput_Gb + (Float (Payload'Last + 28)
                              * Float (System.Storage_Unit) / Float (10 ** 9));
   end Send_Packet;


   ---------------
   --  Rcv_Ack  --
   ---------------

   procedure Rcv_Ack is
      Payload     : Ratp.Packet_Stream;
      Head        : Ratp.Reliable_Udp.Header;
      Ack         : array (1 .. 64) of Interfaces.Unsigned_8;
      Data        : Ada.Streams.Stream_Element_Array (1 .. 64);
      Res         : Interfaces.C.int;

      for Ack'Address use Payload'Address;
      for Data'Address use Ack'Address;
      for Head'Address use Ack'Address;

      Not_A_Msg   : Boolean renames Head.Ack;
      Message     : Ratp.Reliable_Udp.Pkt_Nb renames Head.Seq_Nb;
   begin
      loop
         Res := GNAT.Sockets.Thin.C_Recv
            (To_Int (Socket), Data (Data'First)'Address, Data'Length, 64);

         exit when Res = -1;

         if Not_A_Msg then
            declare
               Ack_Header  : Ratp.Reliable_Udp.Header;
               for Ack_Header'Address use Last_Packets (Head.Seq_Nb).Data'Address;
            begin
               Ack_Header.Ack := True;
               Send_Packet (Last_Packets (Head.Seq_Nb).Data,
                            Last_Packets (Head.Seq_Nb).Is_Buffer_Size);
            end;
         else
            if Message = 2 then
               Ada.Text_IO.Put_Line ("...Consumer asked to PAUSE ACQUISITION...");
               Acquisition := False;
               exit;
            elsif Message = 1 then
               Ada.Text_IO.Put_Line ("...Consumer asked to START ACQUISITION...");
               Acquisition := True;
               exit;
            end if;
         end if;
      end loop;
   end Rcv_Ack;

end Data_Transport.Udp_Socket_Server;
