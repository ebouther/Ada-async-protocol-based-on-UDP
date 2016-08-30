generic
   type Element_Type is private;
package Queue is

   type Element_Type_Array is array (Integer range <>) of Element_Type;

   Queue_Error          : exception;

   protected type Synchronized_Queue is
      entry Append_Wait (Data : in Element_Type);
      entry Remove_First_Wait (Data : out Element_Type);
      function Cur_Count return Natural;
      function Max_Count return Natural;
      procedure Append (Data : in Element_Type);
      procedure Remove_First (Data : out Element_Type);
   private
      Pool                 : Element_Type_Array (1 .. 10000);
      Count                : Natural := 0;
      In_Index, Out_Index  : Positive := 1;
   end Synchronized_Queue;
end Queue;
