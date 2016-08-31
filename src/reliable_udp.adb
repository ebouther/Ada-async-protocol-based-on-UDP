with Ada.Streams;
with Ada.Text_IO;

package body Reliable_Udp is

   Ack_Mgr      : Ack_Management;

   task body Append_Task is
      Packet_Lost      : Reliable_Udp.Loss;
      Client_Addr      : GNAT.Sockets.Sock_Addr_Type;
      First_D, Last_D  : Base_Udp.Header;

   begin
      loop
         accept Append (First_Dropped, Last_Dropped   : Base_Udp.Header;
                        Client_Address                : GNAT.Sockets.Sock_Addr_Type) do
            First_D        := First_Dropped;
            Last_D         := Last_Dropped;
            Client_Addr    := Client_Address;
         end Append;

         --  if First_D < Last_D then
            for I in Base_Udp.Header range First_D .. Last_D loop
               Packet_Lost := (Packet     => I,
                               Last_Ack   => Ada.Real_Time."-"(Ada.Real_Time.Clock,
                               Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)),
                               From       => Client_Addr);
               Ack_Mgr.Append (Packet_Lost);
            end loop;
         --  else
         --     for I in Base_Udp.Header range First_D .. Base_Udp.Pkt_Max loop
         --        Packet_Lost := (Packet     => I,
         --                        Last_Ack   => Ada.Real_Time."-"(Ada.Real_Time.Clock,
         --                        Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)),
         --                        From       => Client_Addr);

         --        Ack_Mgr.Append (Packet_Lost);
         --        
         --     end loop;

         --     for I in Base_Udp.Header range 0 .. Last_D loop
         --        Packet_Lost := (Packet     => I,
         --                        Last_Ack   => Ada.Real_Time."-"(Ada.Real_Time.Clock,
         --                        Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)),
         --                        From       => Client_Addr);
         --        Ack_Mgr.Append (Packet_Lost);
         --     end loop;
         --  end if;
      end loop;
   end Append_Task;


   task body Remove_Task is
      Pkt   : Base_Udp.Header;
   begin
      loop
            accept Remove (Packet : in Base_Udp.Header) do
               Pkt   := Packet;
            end Remove;
            Ack_Mgr.Remove (Pkt);
      end loop;
   end Remove_Task;


   task body Ack_Task is
   begin
      Ack_Mgr.Init_Socket;
      accept Start;
      loop
         Ack_Mgr.Ack;
      end loop;
   end Ack_Task;


   protected body Ack_Management is

      procedure Init_Socket is
      begin
         GNAT.Sockets.Create_Socket (Socket,
                                     GNAT.Sockets.Family_Inet,
                                     GNAT.Sockets.Socket_Datagram);
      end Init_Socket;


      procedure Append (Packet_Lost : in Loss) is
      begin
         Losses_Container.Append (Container  => Losses,
                                 New_Item    => Packet_Lost);
      end Append;


      procedure Update_AckTime (Position   : in Losses_Container.Cursor;
         Ack_Time    :  in Ada.Real_Time.Time) is
         Element     :  Loss;
      begin
         Element := Losses_Container.Element (Position);
         Element.Last_Ack := Ack_Time;
         Losses_Container.Replace_Element (Losses, Position, Element);
      end Update_AckTime;


      procedure Remove (Packet   : Base_Udp.Header) is
         Cursor      : Losses_Container.Cursor := Losses.First;
      begin

         --  Ada.Text_IO.Put_Line ("Rm_container" & Rm_Container.Element (Rm_Cursor)'Img);

         while Losses_Container.Has_Element (Cursor) loop
            if Interfaces."=" (Losses_Container.Element (Cursor).Packet, Packet) then
               Losses_Container.Delete (Container => Losses,
                                        Position  => Cursor);
            end if;
            Losses_Container.Next (Cursor);
         end loop;
      end Remove;

      function Length return Ada.Containers.Count_Type is
      begin
         return Losses.Length;
      end Length;

      procedure Ack is
         Ack_Array   : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
         Seq_Nb      : Base_Udp.Header;
         Header      : Reliable_Udp.Header;
         Data        : Ada.Streams.Stream_Element_Array (1 .. 64);
         Offset      : Ada.Streams.Stream_Element_Offset;
         Cur_Time    : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
         Cursor      : Losses_Container.Cursor := Losses.First;
         Element     : Loss;
         --  First       : Boolean := True;

         for Data'Address use Ack_Array'Address;
         for Seq_Nb'Address use Ack_Array'Address;
         for Header'Address use Ack_Array'Address;
         use type Ada.Real_Time.Time;
         use type Ada.Real_Time.Time_Span;
      begin
         if Losses_Container.Is_Empty (Losses) = False then

            while Losses_Container.Has_Element (Cursor) loop
               Element := Losses_Container.Element (Cursor);
               if Cur_Time - Element.Last_Ack >
                  Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)
               then
                  Element.Last_Ack := Ada.Real_Time.Clock;
                  Losses_Container.Replace_Element (Losses, Cursor, Element);
                  Seq_Nb := Element.Packet;
                  --Ada.Text_IO.Put_Line ("Send Ack : " & Seq_Nb'Img);
                  GNAT.Sockets.Send_Socket (Socket, Data, Offset, Element.From);
                  Update_AckTime (Cursor, Ada.Real_Time.Clock);
               end if;
               Losses_Container.Next (Cursor);
            end loop;
         end if;
      end Ack;

   end Ack_Management;

end Reliable_Udp;
