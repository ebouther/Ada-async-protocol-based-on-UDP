with Ada.Text_IO;
with Interfaces;
with Ada.Exceptions;

package body Packet_Mgr is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;


   Buffer_Handler : Buf_Handler;


   -------------------------
   --  Init_Handle_Array  --
   -------------------------

   procedure Init_Handle_Array is
   begin

      Buffer_Handler.Buffer.Initialise (PMH_Buf_Nb, Size => Buffers.Buffer_Size_Type
         (Base_Udp.Sequence_Size * Base_Udp.Load_Size));

      Buffer_Handler.First := Buffer_Handler.Handlers'First;
      Buffer_Handler.Current := Buffer_Handler.Handlers'First;

      for I in Buffer_Handler.Handlers'Range loop
         Buffer_Handler.Buffer.Get_Free_Buffer (Buffer_Handler.Handlers (I).Handle);
      end loop;

   end Init_Handle_Array;


   ------------------------------
   --  Release_Free_Buffer_At  --
   ------------------------------

   procedure Release_Free_Buffer_At (Index : in Handle_Index) is
   begin

      --  Provoke a GNAT Bug Detected

      Buffer_Handler.Buffer.Release_Free_Buffer
                        (Buffer_Handler.Handlers
                           (Index).Handle);

      Buffer_Handler.Handlers (Index).State := Empty;

   end Release_Free_Buffer_At;


   --     -----------------------
   --     --  Release_Full_Buf  --
   --     -----------------------

   --     task body Release_Full_Buf is

   --     begin
   --        loop

   --              Buffers.Set_Used_Bytes (Buffer_Handler.Handlers (Integer (Index)).Handle,
   --                                Packet_Buffers.To_Bytes (Length));

   --              Release_Free_Buffer_At (Buffer_Handler.Handlers));
   --              Buffer_Handler.Handlers.Delete_First;

   --              --  Get_Filled_Buf;
   --        end loop;
   --     end Release_Full_Buf;


   -----------------------
   --  PMH_Buffer_Addr  --
   -----------------------

   task body PMH_Buffer_Addr is
   begin
      loop
         select
            accept Stop;
               --  Set_Used_Bytes_At (Buffer_Handler.Prod_Cursor, Integer (Base_Udp.Sequence_Size));
               --  Ada.Text_IO.Put_Line ("*** Released Buffer before Quitting Task ***");
               --  Release_Free_Buffer_At (Buffer_Handler.Prod_Cursor);
               --  Buffer_Handler.Handlers.Delete (Buffer_Handler.Prod_Cursor);
               exit;
         or
            accept New_Buffer_Addr (Buffer_Ptr   : in out System.Address) do

               Buffer_Ptr := Buffer_Handler.Handlers
                                (Buffer_Handler.Current + 1).Handle.Get_Address;
            end New_Buffer_Addr;
               Buffer_Handler.Handlers (Buffer_Handler.Current).State := Full;
               Buffer_Handler.Current := Buffer_Handler.Current + 1;
         end select;
      end loop;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("exception : " &
            Ada.Exceptions.Exception_Name (E) &
            " message : " &
            Ada.Exceptions.Exception_Message (E));
   end PMH_Buffer_Addr;


   ----------------------
   --  Get_Filled_Buf  --
   ----------------------

   procedure Get_Filled_Buf is
   begin
      declare
         use Packet_Buffers;
         Handle  : Buffers.Buffer_Handle_Type;
      begin
         select
            Buffer_Handler.Buffer.Get_Full_Buffer (Handle);
            Ada.Text_IO.Put_Line ("---  Got Filled Buffer  ---");
         or
            delay 1.0;
            Ada.Text_IO.Put_Line ("-x-  No Buf -x-");
            return;
         end select;
         declare
            type Data_Array is new Element_Array
               (1 .. To_Word_Count
                  (Buffers.Get_Used_Bytes (Handle)));

            Datas    : Data_Array;

            for Datas'Address use Buffers.Get_Address (Handle);
         begin
            for I in Datas'Range loop
               declare
                  Pkt_Nb   : Base_Udp.Header;
                  for Pkt_Nb'Address use Datas (I)'Address;
               begin
                  Ada.Text_IO.Put_Line ("Buffer (" & I'Img & " ) :" &
                     Pkt_Nb'Img);
               end;
            end loop;
         end;

         Buffer_Handler.Buffer.Release_Full_Buffer (Handle);

         Buffers.Reuse (Handle);

      exception
         when E : others =>
            Ada.Text_IO.Put_Line ("exception : " &
               Ada.Exceptions.Exception_Name (E) &
               " message : " &
               Ada.Exceptions.Exception_Message (E));
      end;
   end Get_Filled_Buf;

end Packet_Mgr;
