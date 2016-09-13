with Ada.Streams;
with System.Multiprocessors.Dispatching_Domains;
with Ada.Text_IO;

package body Reliable_Udp is

   Ack_Mgr      : Ack_Management;


   -------------------
   --  Append_Task  --
   -------------------

   task body Append_Task is
      Packet_Lost      : Reliable_Udp.Loss;
      Client_Addr      : GNAT.Sockets.Sock_Addr_Type;
      First_D, Last_D  : Reliable_Udp.Pkt_Nb;

   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (6));
      loop
         select
            accept Stop;
            exit;
         or
            accept Append (First_Dropped, Last_Dropped   : Reliable_Udp.Pkt_Nb;
                           Client_Address                : GNAT.Sockets.Sock_Addr_Type) do
               First_D        := First_Dropped;
               Last_D         := Last_Dropped;
               Client_Addr    := Client_Address;
            end Append;

            --  if First_D < Last_D then
            for I in Reliable_Udp.Pkt_Nb range First_D .. Last_D loop
               Packet_Lost.Last_Ack := Ada.Real_Time."-"(Ada.Real_Time.Clock,
                                 Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max));
               Packet_Lost.From := Client_Addr;
               Ack_Mgr.Set (Loss_Index (I), Packet_Lost);
            end loop;
            --  else
            --     for I in Base_Udp.Header range First_D .. Base_Udp.Pkt_Max loop
            --        Packet_Lost := (Packet     => I,
            --                        Last_Ack   => Ada.Real_Time."-"(Ada.Real_Time.Clock,
            --                        Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)),
            --                        From       => Client_Addr);

            --        Ack_Mgr.Append (Packet_Lost);

            --     end loop;

            --     for I in Base_Udp.Header range 0 .. Last_D loop
            --        Packet_Lost := (Packet     => I,
            --                        Last_Ack   => Ada.Real_Time."-"(Ada.Real_Time.Clock,
            --                        Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)),
            --                        From       => Client_Addr);
            --        Ack_Mgr.Append (Packet_Lost);
            --     end loop;
            --  end if;
         end select;
      end loop;
   end Append_Task;


   -------------------
   --  Remove_Task  --
   -------------------

   task body Remove_Task is
      Pkt   : Pkt_Nb;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (7));
      loop
         select
            accept Stop;
            exit;
         or
            accept Remove (Packet : in Pkt_Nb) do
               Pkt   := Packet;
            end Remove;
            Ack_Mgr.Clear (Loss_Index (Pkt));
         end select;
      end loop;
   end Remove_Task;

   ----------------
   --  Ack_Task  --
   ----------------

   --  Issue: Prevent from receiving packets when two much aks
   --  which create even more acks...
   task body Ack_Task is
      Socket      : GNAT.Sockets.Socket_Type;
      Ack_Array   : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
      Head        : Reliable_Udp.Header;
      Data        : Ada.Streams.Stream_Element_Array (1 .. 64);
      Offset      : Ada.Streams.Stream_Element_Offset;
      Element     : Loss;
      Index       : Loss_Index := Loss_Index'First;

      for Data'Address use Ack_Array'Address;
      for Head'Address use Ack_Array'Address;
      use type Ada.Real_Time.Time;
      use type Ada.Real_Time.Time_Span;
   begin
      System.Multiprocessors.Dispatching_Domains.Set_CPU
         (System.Multiprocessors.CPU_Range (8));

      GNAT.Sockets.Create_Socket (Socket,
                                  GNAT.Sockets.Family_Inet,
                                  GNAT.Sockets.Socket_Datagram);
      accept Start;
      loop
         select
            accept Stop;
               exit;
         else
            if not Ack_Mgr.Is_Empty (Index) then
               Ada.Text_IO.Put_Line ("Got Ack");
               Element := Ack_Mgr.Get (Index);
               if Ada.Real_Time.Clock - Element.Last_Ack >
                  Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)
               then
                  Ada.Text_IO.Put_Line ("Send Ack");
                  Element.Last_Ack := Ada.Real_Time.Clock;
                  Ack_Mgr.Set (Index, Element);
                  Head.Seq_Nb := Pkt_Nb (Index);
                  GNAT.Sockets.Send_Socket (Socket, Data, Offset, Element.From);
               end if;
            end if;
            Index := Index + 1;
         end select;
      end loop;
   end Ack_Task;


   protected body Ack_Management is


      -----------
      --  Set  --
      -----------

      procedure Set (Index    : in Loss_Index;
                     Data     : in Loss) is
      begin
         Losses (Index) := Data;
         Losses (Index).Is_Empty := False;
      end Set;


      -----------
      --  Get  --
      -----------

      procedure Get (Index : in Loss_Index;
                     Data  : in out Loss) is
      begin
         Data := Losses (Index);
      end Get;

      function Get (Index : in Loss_Index) return Loss is
      begin
         return Losses (Index);
      end Get;


      -------------
      --  Clear  --
      -------------

      procedure Clear (Index    : in Loss_Index) is
      begin
         Losses (Index).Is_Empty := True;
      end Clear;


      ----------------
      --  Is_Empty  --
      ----------------

      function Is_Empty (Index    : in Loss_Index) return Boolean is
      begin
         return Losses (Index).Is_Empty;
      end Is_Empty;

      --  --------------
      --  --  Append  --
      --  --------------

      --  procedure Append (Packet_Lost : in Loss) is
      --  begin
      --     Losses_Container.Append (Container  => Losses,
      --                              New_Item   => Packet_Lost);
      --  end Append;


      --  ----------------------
      --  --  Update_AckTime  --
      --  ----------------------

      --  procedure Update_AckTime (Position   : in Losses_Container.Cursor;
      --     Ack_Time    :  in Ada.Real_Time.Time) is
      --     Element     :  Loss;
      --  begin
      --     Element := Losses_Container.Element (Position);
      --     Element.Last_Ack := Ack_Time;
      --     Losses_Container.Replace_Element (Losses, Position, Element);
      --  end Update_AckTime;


      --  --------------
      --  --  Remove  --
      --  --------------

      --  procedure Remove (Packet   : Pkt_Nb) is
      --     Cursor      : Losses_Container.Cursor := Losses.First;
      --  begin

      --     while Losses_Container.Has_Element (Cursor) loop
      --        if Losses_Container.Element (Cursor).Packet = Packet then
      --           Losses_Container.Delete (Container => Losses,
      --                                    Position  => Cursor);
      --        end if;
      --        Losses_Container.Next (Cursor);
      --     end loop;
      --  end Remove;


      --  --------------
      --  --  Length  --
      --  --------------

      --  function Length return Ada.Containers.Count_Type is
      --  begin
      --     return Losses.Length;
      --  end Length;


      --  -----------
      --  --  Ack  --
      --  -----------

      --  procedure Ack is
      --     Ack_Array   : array (1 .. 64) of Interfaces.Unsigned_8 := (others => 0);
      --     Head        : Reliable_Udp.Header;
      --     Data        : Ada.Streams.Stream_Element_Array (1 .. 64);
      --     Offset      : Ada.Streams.Stream_Element_Offset;
      --     Cur_Time    : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      --     Cursor      : Losses_Container.Cursor := Losses.First;
      --     Element     : Loss;

      --     for Data'Address use Ack_Array'Address;
      --     for Head'Address use Ack_Array'Address;
      --     use type Ada.Real_Time.Time;
      --     use type Ada.Real_Time.Time_Span;
      --  begin
      --     if not Losses_Container.Is_Empty (Losses) then

      --        while Losses_Container.Has_Element (Cursor) loop
      --           Element := Losses_Container.Element (Cursor);
      --           if Cur_Time - Element.Last_Ack >
      --              Ada.Real_Time.Milliseconds (Base_Udp.RTT_MS_Max)
      --           then
      --              Element.Last_Ack := Ada.Real_Time.Clock;
      --              Losses_Container.Replace_Element (Losses, Cursor, Element);
      --              Head.Seq_Nb := Element.Packet;
      --              GNAT.Sockets.Send_Socket (Socket, Data, Offset, Element.From);
      --              Update_AckTime (Cursor, Ada.Real_Time.Clock);
      --           end if;
      --           Losses_Container.Next (Cursor);
      --        end loop;
      --     end if;
      --  end Ack;

   end Ack_Management;

end Reliable_Udp;
