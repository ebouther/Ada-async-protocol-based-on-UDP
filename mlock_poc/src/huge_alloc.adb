with Ada.Text_IO;

procedure Huge_Alloc is
   type Integer_Array is array (Integer range <>) of Integer;
   type Array_Acces is access all Integer_Array;
   Toto : Array_Acces;
begin
   loop
      Toto := new Integer_Array (0 .. 1024 * 100);
      Ada.Text_IO.Put_Line ("New Buf, Size : " & Toto.all'Size'Img);
      delay 1.0;
   end loop;
end Huge_Alloc;
