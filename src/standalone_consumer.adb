with Ada.Text_IO;
with Ada.Streams;
with Ada.Exceptions;
with System.Multiprocessors.Dispatching_Domains;
with System.Storage_Elements;
with Interfaces.C;

pragma Warnings (Off);
with GNAT.Sockets.Thin;
pragma Warnings (On);

with Ratp.Consumer_Utilities;

procedure Standalone_Consumer is

   use type Interfaces.Unsigned_64;

   Server            : GNAT.Sockets.Socket_Type;
   Cons_Addr         : constant GNAT.Sockets.Inet_Addr_Type := GNAT.Sockets.Any_Inet_Addr;
   Cons_Port         : constant GNAT.Sockets.Port_Type := 50001;

   From              : GNAT.Sockets.Sock_Addr_Type;
   Last              : Ada.Streams.Stream_Element_Offset;
   Data_Addr         : System.Address;
   Recv_Offset       : Interfaces.Unsigned_64 := Ratp.Pkt_Max + 1;

   use System.Storage_Elements;
   use type Interfaces.C.int;
begin

   System.Multiprocessors.Dispatching_Domains.Set_CPU
      (System.Multiprocessors.CPU_Range (16));

   Ratp.Consumer_Utilities.Parse_Arguments;

   Ratp.Consumer_Utilities.Init_Consumer;
   Ratp.Consumer_Utilities.Init_Udp (Server, Cons_Addr, Cons_Port);

   <<HandShake>>
   Ada.Text_IO.Put_Line ("...Waiting for Producer...");
   Ratp.Consumer_Utilities.Wait_Producer_HandShake (Cons_Addr, Cons_Port);
   Ada.Text_IO.Put_Line ("Producer is ready...");

   loop
      if Recv_Offset > Ratp.Pkt_Max then
         Ratp.Consumer_Utilities.PMH_Buffer_Task.New_Buffer_Addr
            (Buffer_Ptr => Data_Addr);
         Recv_Offset := Recv_Offset mod Ratp.Sequence_Size;
      end if;

      declare
         Data     : Ratp.Packet_Stream;

         for Data'Address use Data_Addr + Storage_Offset
               (Recv_Offset * Ratp.Load_Size);
         use type Ada.Streams.Stream_Element_Offset;
      begin
         GNAT.Sockets.Receive_Socket (Server, Data, Last, From);
         Ratp.Consumer_Utilities.Process_Packet
            (Data, Last, Recv_Offset, Data_Addr, From);
         Recv_Offset := Recv_Offset + 1;
      exception
         when GNAT.Sockets.Socket_Error =>
            Ada.Text_IO.Put_Line ("Socket Timeout");
            goto HandShake;
      end;
   end loop;
exception
   when E : others =>
      Ada.Text_IO.Put_Line (ASCII.ESC & "[31m" & "Exception : " &
         Ada.Exceptions.Exception_Name (E)
         & ASCII.LF & ASCII.ESC & "[33m"
         & Ada.Exceptions.Exception_Message (E)
         & ASCII.ESC & "[0m");
   raise;
end Standalone_Consumer;
