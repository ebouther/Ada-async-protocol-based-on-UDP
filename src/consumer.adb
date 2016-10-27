with Ada.Text_IO;
with Ada.Exceptions;
with Interfaces;

with Ratp.Reliable_Udp;

with Buffers.Shared.Consume;

procedure Consumer is

   Consumption       : Buffers.Shared.Consume.Consume_Couple_Type;
   Buffer_Cons       : Buffers.Shared.Consume.Consume_Type
                           renames Consumption.Consumer;

   package Packet_Buffers is new
      Buffers.Generic_Buffers
         (Element_Type => Ratp.Packet_Stream);

   procedure Get_Filled_Buf (To_File   : in Boolean := True);


   ----------------------
   --  Get_Filled_Buf  --
   ----------------------

   procedure Get_Filled_Buf (To_File   : in Boolean := True) is
      Log_File : Ada.Text_IO.File_Type;
      Handle   : Buffers.Buffer_Handle_Type;

      use Packet_Buffers;
      use type Interfaces.Unsigned_32;
   begin
      select
         Buffer_Cons.Get_Full_Buffer (Handle);
      or
         delay 5.0;
         Ada.Text_IO.Put_Line
               ("/!\ Timeout : Cannot Get A Full Buffer /!\");
         return;
      end select;

      if To_File then
         Ada.Text_IO.Open
            (Log_File, Ada.Text_IO.Append_File, "buffers.log");
      end if;

      declare
         type Data_Array is new Element_Array
            (1 .. To_Word_Count
               (Buffers.Get_Used_Bytes (Handle)));

         Datas    : Data_Array;

         for Datas'Address use Buffers.Get_Address (Handle);
      begin
         for I in Datas'Range loop
            declare
               Pkt_U8      : array (1 .. Ratp.Load_Size)
                              of Interfaces.Unsigned_8;
               Header      : Ratp.Reliable_Udp.Header;
               Content     : Interfaces.Unsigned_64;
               Dead_Beef   : Interfaces.Unsigned_32;

               for Header'Address use Datas (I)'Address;
               for Dead_Beef'Address use Datas (I)'Address;
               for Pkt_U8'Address use Datas (I)'Address;
               for Content'Address use Pkt_U8 (5)'Address;
            begin
               if Dead_Beef = 16#DEAD_BEEF# then
                  if To_File then
                     Ada.Text_IO.Put_Line
                        (Log_File, "Buffer (" & I'Img
                           & " ) : ** DROPPED **");
                  else
                     Ada.Text_IO.Put_Line ("Buffer (" & I'Img
                        & " ) : ** DROPPED **");
                  end if;
               else
                  if To_File then
                     Ada.Text_IO.Put_Line
                        (Log_File, "Buffer (" & I'Img & " ) :" &
                           Header.Seq_Nb'Img & Content'Img);
                  else
                     Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) :" &
                        Header.Seq_Nb'Img & Content'Img);
                  end if;
               end if;
            end;
         end loop;
      end;

      Buffer_Cons.Release_Full_Buffer (Handle);
      if To_File then
         Ada.Text_IO.Close (Log_File);
      end if;

   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end Get_Filled_Buf;
begin

   Buffer_Cons.Set_Name (Ratp.Buffer_Name);
   Consumption.Message_Handling.Start (1.0);
   loop
      Get_Filled_Buf;
   end loop;
   --  Consumption.Message_Handling.Stop;

end Consumer;
