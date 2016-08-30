package body Queue is

   protected body Synchronized_Queue is
      entry Append_Wait (Data : in Element_Type)
         when Count < Pool'Length is
      begin
         Append (Data);
      end Append_Wait;

      procedure Append (Data : in Element_Type) is
      begin
         if Count = Pool'Length then
            raise Queue_Error with "Buffer Full";
         end if;
         Pool (In_Index) := Data;
         In_Index        := (In_Index mod Pool'Length) + 1;
         Count           := Count + 1;
      end Append;

      entry Remove_First_Wait(Data : out Element_Type)
         when Count > 0 is
      begin
         Remove_First (Data);
      end Remove_First_Wait;

      procedure Remove_First (Data : out Element_Type) is
      begin
         if Count = 0 then
            raise Queue_Error with "Buffer Empty";
         end if;
         Data      := Pool (Out_Index);
         Out_Index := (Out_Index mod Pool'Length) + 1;
         Count     := Count - 1;
      end Remove_First;

      function Cur_Count return Natural is
      begin
          return Synchronized_Queue.Count;
      end Cur_Count;

      function Max_Count return Natural is
      begin
          return Pool'Length;
      end Max_Count;
   end Synchronized_Queue;

end Queue;
