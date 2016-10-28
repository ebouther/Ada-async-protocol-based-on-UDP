with Ada.Text_IO;
with Ada.Exceptions;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

package body Ratp.Producer_Utilities is

   Last_Packets            : array (Ratp.Reliable_Udp.Pkt_Nb)
                              of History_Type;

   use type Ratp.Reliable_Udp.Pkt_Nb;

   -----------------------------
   --  Reset_Send_Throughput  --
   -----------------------------

   task body Reset_Send_Throughput is
   begin
      loop
         Send_Throughput_Gb := 0.0;
         Send_Throughput_Start := Ada.Calendar.Clock;
         delay 20.0;
      end loop;
   end Reset_Send_Throughput;


   --------------------------
   --  Consumer_HandShake  --
   --------------------------

   procedure Consumer_HandShake is
      Send_Data, Recv_Data : Ratp.Packet_Stream;
      Send_Head, Recv_Head : Ratp.Reliable_Udp.Header;

      for Send_Head'Address use Send_Data'Address;
      for Recv_Head'Address use Recv_Data'Address;
      Recv_Msg    : Ratp.Reliable_Udp.Pkt_Nb renames Recv_Head.Seq_Nb;
      Send_Msg    : Ratp.Reliable_Udp.Pkt_Nb renames Send_Head.Seq_Nb;
      Not_A_Msg   : Boolean renames Recv_Head.Ack;
      use type Interfaces.C.int;
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
   end Consumer_HandShake;


   ------------------------
   --  Send_Buffer_Data  --
   ------------------------

   procedure Send_Buffer_Data (Buffer_Set    : Buffers.Buffer_Consume_Access;
                               Packet_Number : in out Ratp.Reliable_Udp.Pkt_Nb) is

      Null_Buffer_Size  : exception;
      Buffer_Handle     : Buffers.Buffer_Handle_Type;
      use type Ada.Streams.Stream_Element_Offset;
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
         use type Interfaces.Unsigned_32;
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
      use type Ada.Streams.Stream_Element_Offset;

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
      use type Ada.Streams.Stream_Element_Offset;
   begin

      while Float (Duration (Send_Throughput_Gb)
         / (Ada.Calendar.Clock - Send_Throughput_Start))
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
      use type Interfaces.C.int;
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

end Ratp.Producer_Utilities;
