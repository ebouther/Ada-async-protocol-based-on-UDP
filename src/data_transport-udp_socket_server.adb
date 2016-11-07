with Ada.Text_IO;
with Ada.Calendar;
with Ada.Exceptions;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

--  with Network_Utils;

package body Data_Transport.Udp_Socket_Server is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Interfaces.C.int;
   use type Ada.Streams.Stream_Element_Offset;

   use type Reliable_Udp.Packet_Number_Type;

   task body Socket_Server_Task is
      Packet_Number  : Reliable_Udp.Packet_Number_Type := 0;
      Producer       : Producer_Access;
   begin
      select
         accept Initialise
           (Obj               : Producer_Access;
            Network_Interface : String;
            Port              : GNAT.Sockets.Port_Type)
         do
            Producer := Obj;
            Producer.Address.Addr := GNAT.Sockets.Addresses
                                    (GNAT.Sockets.Get_Host_By_Name (Network_Interface));
            Producer.Address.Port := Port;
            GNAT.Sockets.Create_Socket
               (Producer.Socket,
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
      Consumer_HandShake (Producer);
      Producer.Acquisition := True;
      delay 0.0001;
      Ada.Text_IO.Put_Line ("Consumer ready, start sending packets...");

      loop
         select
            accept Disconnect;
               GNAT.Sockets.Close_Socket (Producer.Socket);
               exit;
         else
            if Producer.Acquisition then
               Rcv_Ack (Producer);
               select
                  Buffer_Set.Block_Full;
                  Send_Buffer_Data (Producer, Buffer_Set, Packet_Number);
               else
                  null;
               end select;
            else
               declare
                  Start_Time  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
                  use type Ada.Calendar.Time;
               begin
                  loop
                     Rcv_Ack (Producer);
                     --  Give consumer 2s to be sure it has all packets
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
   --  Consumer_HandShake  --
   ------------------------

   procedure Consumer_HandShake (Producer : Producer_Access) is
      Send_Data, Recv_Data : Base_Udp.Packet_Stream;
      Send_Head, Recv_Head : Reliable_Udp.Header_Type;

      for Send_Head'Address use Send_Data'Address;
      for Recv_Head'Address use Recv_Data'Address;
      Recv_Msg    : Reliable_Udp.Packet_Number_Type renames Recv_Head.Seq_Nb;
      Send_Msg    : Reliable_Udp.Packet_Number_Type renames Send_Head.Seq_Nb;
      Not_A_Msg   : Boolean renames Recv_Head.Ack;
   begin
      Send_Msg := 0;
      loop
         Send_Packet (Producer => Producer,
                      Payload => Send_Data);
         --  Wait a little bit for consumer's response.
         delay 0.1;
         exit when GNAT.Sockets.Thin.C_Recv
               (To_Int (Producer.Socket),
                Recv_Data (Recv_Data'First)'Address,
                Recv_Data'Length,
                64) /= -1
               and Not_A_Msg = False
               and Recv_Msg = Send_Msg;
         --  If consumer did not reply, wait for it's timeout (1s),
         --  otherwise it'd be considered as a packet ack.
         delay 1.5;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
            Ada.Exceptions.Exception_Name (E)
            & ASCII.LF & ASCII.ESC & "[33m"
            & Ada.Exceptions.Exception_Message (E)
            & ASCII.ESC & "[0m");
         raise;
   end Consumer_HandShake;


   ------------------------
   --  Send_Buffer_Data  --
   ------------------------

   procedure Send_Buffer_Data (Producer      : Producer_Access;
                               Buffer_Set    : Buffers.Buffer_Consume_Access;
                               Packet_Number : in out Reliable_Udp.Packet_Number_Type) is

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
         Header   : Reliable_Udp.Header_Type;

         for Data'Address use Buffers.Get_Address (Buffer_Handle);
         for Header'Address use Producer.Last_Packets (Packet_Number).Data'Address;
         for Buffer_Size'Address use Producer.Last_Packets (Packet_Number).Data
                                       (Base_Udp.Header_Size + 1)'Address;
      begin
         if Buffer_Size = 0 then
            raise Null_Buffer_Size with "Buffer's Size Equal 0";
         end if;
         Header := (Ack => False,
                    Seq_Nb => Packet_Number);
         Producer.Last_Packets (Packet_Number).Is_Buffer_Size := True;
         Send_Packet (Producer, Producer.Last_Packets (Packet_Number).Data, True);
         Packet_Number := Packet_Number + 1;
         Send_All_Stream (Producer, Data, Packet_Number);
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

   procedure Send_All_Stream (Producer       : Producer_Access;
                              Payload        : Ada.Streams.Stream_Element_Array;
                              Packet_Number  : in out Reliable_Udp.Packet_Number_Type) is
      use type Ada.Streams.Stream_Element_Array;

      First : Ada.Streams.Stream_Element_Offset := Payload'First;
      Index : Ada.Streams.Stream_Element_Offset := First - 1;
      Last  : Ada.Streams.Stream_Element_Offset;
   begin
      loop
         Rcv_Ack (Producer);
         declare
            Head     : Ada.Streams.Stream_Element_Array (1 .. 2);
            Header   : Reliable_Udp.Header_Type := (Ack => False,
                                               Seq_Nb => Packet_Number);

            for Header'Address use Head'Address;
         begin
            Last := First + (Base_Udp.Load_Size - Base_Udp.Header_Size) - 1;

            if Last > Payload'Last then
               declare
                  Pad   : constant Ada.Streams.Stream_Element_Array
                           (1 .. Last - Payload'Last) := (others => 0);
               begin
                  Producer.Last_Packets (Packet_Number).Data := Head & Payload
                        (First .. Payload'Last) & Pad;
               end;
            else
               Producer.Last_Packets (Packet_Number).Data := Head & Payload
                     (First .. Last);
            end if;
            Producer.Last_Packets (Packet_Number).Is_Buffer_Size := False;
            GNAT.Sockets.Send_Socket (Producer.Socket, Producer.Last_Packets (Packet_Number).Data,
                                       Index, Producer.Address);

            Packet_Number := Packet_Number + 1;
         end;
         First := Last + 1;
         exit when First > Payload'Last;
      end loop;
   end Send_All_Stream;


   -------------------
   --  Send_Packet  --
   -------------------

   procedure Send_Packet (Producer        : Producer_Access;
                          Payload         : Base_Udp.Packet_Stream;
                          Is_Buffer_Size  : Boolean := False)
   is
      Offset   : Ada.Streams.Stream_Element_Offset;
      Data     : Ada.Streams.Stream_Element_Array
                     (1 .. (if Is_Buffer_Size then 6 else Base_Udp.Load_Size));

      for Data'Address use Payload'Address;
      pragma Unreferenced (Offset);
   begin
      GNAT.Sockets.Send_Socket (Producer.Socket, Data, Offset, Producer.Address);
   end Send_Packet;


   ---------------
   --  Rcv_Ack  --
   ---------------

   procedure Rcv_Ack (Producer   : Producer_Access) is
      Payload     : Base_Udp.Packet_Stream;
      Head        : Reliable_Udp.Header_Type;
      Ack         : array (1 .. 64) of Interfaces.Unsigned_8;
      Data        : Ada.Streams.Stream_Element_Array (1 .. 64);
      Res         : Interfaces.C.int;

      for Ack'Address use Payload'Address;
      for Data'Address use Ack'Address;
      for Head'Address use Ack'Address;

      Is_Not_Msg  : Boolean renames Head.Ack;
      Message     : Reliable_Udp.Packet_Number_Type renames Head.Seq_Nb;
   begin
      loop
         Res := GNAT.Sockets.Thin.C_Recv
            (To_Int (Producer.Socket), Data (Data'First)'Address, Data'Length, 64);

         exit when Res = -1;

         if Is_Not_Msg then
            declare
               Ack_Header  : Reliable_Udp.Header_Type;
               for Ack_Header'Address use Producer.Last_Packets (Head.Seq_Nb).Data'Address;
            begin
               Ack_Header.Ack := True;
               Send_Packet (Producer, Producer.Last_Packets (Head.Seq_Nb).Data,
                            Producer.Last_Packets (Head.Seq_Nb).Is_Buffer_Size);
               --  DBG
               if Producer.Last_Packets (Head.Seq_Nb).Is_Buffer_Size then
                  Ada.Text_IO.Put_Line ("ReSent a Buffer Size :" & Head.Seq_Nb'Img);
               end if;
            end;
         else
            if Message = 2 then
               Ada.Text_IO.Put_Line ("...Consumer asked to PAUSE ACQUISITION...");
               Producer.Acquisition := False;
               exit;
            elsif Message = 1 then
               Ada.Text_IO.Put_Line ("...Consumer asked to START ACQUISITION...");
               Producer.Acquisition := True;
               exit;
            end if;
         end if;
      end loop;
   end Rcv_Ack;

end Data_Transport.Udp_Socket_Server;
