with Ada.Text_IO;
with Interfaces.C;
with System;

--  /!\ Mlock and Mlockall require privileges /!\ --

procedure Huge_Alloc_Mlock is

   function mlockall (Flags : Interfaces.C.int)
      return Interfaces.C.int;
   pragma Import (C, mlockall, "mlockall");

   function mlock (Addr : System.Address;
                   Len  : Interfaces.C.size_t)
            return Interfaces.C.int;
   pragma Import (C, mlock, "mlock");

   procedure Perror (Message : String);
   pragma Import (C, Perror, "perror");

   type Integer_Array is array (Integer range <>) of Integer;
   type Array_Acces is access all Integer_Array;
   Toto : Array_Acces;
   Ret  : Interfaces.C.int;
   use type Interfaces.C.int;
begin
   Ret := mlockall (2);
   loop
      Toto := new Integer_Array (0 .. 1024 * 100);
      Ret := mlock (Toto'Address, Toto'Size);
      if Ret = -1 then
         Perror ("Mlock Err");
      end if;
      Ada.Text_IO.Put_Line ("New Buf, Size : " & Toto.all'Size'Img);
      delay 1.0;
   end loop;
end Huge_Alloc_Mlock;
