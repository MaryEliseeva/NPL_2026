with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Real_Time;    use Ada.Real_Time;
with Ada.Numerics.Discrete_Random;

procedure Array_Stats is

   subtype Value is Integer range -1_000_000 .. 1_000_000;
   type Int_Array is array (Positive range <>) of Integer;
   type Int_Array_Access is access Int_Array;

   package Random_Value is new Ada.Numerics.Discrete_Random (Value);

   N       : Positive := 10_000_000;
   Workers : Positive := 4;
   Data    : Int_Array_Access;

   --  Защищённый объект: к нему одновременно может обращаться только одна
   --  задача, поэтому гонки данных при объединении результатов нет.
   protected Result is
      procedure Add (Part_Min, Part_Max : Integer; Part_Sum : Long_Long_Integer);
      function Min return Integer;
      function Max return Integer;
      function Sum return Long_Long_Integer;
   private
      G_Min : Integer := Integer'Last;
      G_Max : Integer := Integer'First;
      G_Sum : Long_Long_Integer := 0;
   end Result;

   protected body Result is
      procedure Add (Part_Min, Part_Max : Integer; Part_Sum : Long_Long_Integer) is
      begin
         G_Min := Integer'Min (G_Min, Part_Min);
         G_Max := Integer'Max (G_Max, Part_Max);
         G_Sum := G_Sum + Part_Sum;
      end Add;
      function Min return Integer is (G_Min);
      function Max return Integer is (G_Max);
      function Sum return Long_Long_Integer is (G_Sum);
   end Result;

   --  Задача-обработчик: получает границы своего участка через Start.
   task type Worker is
      entry Start (From, To : Positive);
   end Worker;

   task body Worker is
      Lo, Hi   : Positive;
      Part_Min : Integer := Integer'Last;
      Part_Max : Integer := Integer'First;
      Part_Sum : Long_Long_Integer := 0;
   begin
      accept Start (From, To : Positive) do
         Lo := From;
         Hi := To;
      end Start;
      for I in Lo .. Hi loop
         Part_Min := Integer'Min (Part_Min, Data (I));
         Part_Max := Integer'Max (Part_Max, Data (I));
         Part_Sum := Part_Sum + Long_Long_Integer (Data (I));
      end loop;
      Result.Add (Part_Min, Part_Max, Part_Sum);
   end Worker;

   Gen : Random_Value.Generator;
   T0, T1 : Time;

begin
   if Argument_Count >= 1 then
      N := Positive'Value (Argument (1));
   end if;
   if Argument_Count >= 2 then
      Workers := Positive'Value (Argument (2));
   end if;
   if Workers > N then
      Workers := N;
   end if;

   Data := new Int_Array (1 .. N);
   Random_Value.Reset (Gen, 2026);
   for I in Data'Range loop
      Data (I) := Random_Value.Random (Gen);
   end loop;
   Put_Line ("Элементов:" & N'Image & ", задач:" & Workers'Image);

   T0 := Clock;
   declare
      Pool  : array (1 .. Workers) of Worker;
      Chunk : constant Positive := N / Workers;
      From  : Positive := 1;
      To    : Positive;
   begin
      for W in Pool'Range loop
         To := (if W = Workers then N else From + Chunk - 1);
         Put_Line ("  задача" & W'Image & ": элементы" & From'Image & " .." & To'Image);
         Pool (W).Start (From, To);
         From := To + 1;
      end loop;
      --  Выход из блока ждёт завершения всех задач Pool.
   end;
   T1 := Clock;

   Put_Line ("Параллельно:");
   Put_Line ("  минимум  =" & Result.Min'Image);
   Put_Line ("  максимум =" & Result.Max'Image);
   Put_Line ("  среднее  =" & Long_Float'Image (Long_Float (Result.Sum) / Long_Float (N)));
   Put_Line ("  время, мс:" & Duration'Image (To_Duration (T1 - T0) * 1000));

   --  Последовательная проверка того же результата.
   declare
      Mn : Integer := Integer'Last;
      Mx : Integer := Integer'First;
      S  : Long_Long_Integer := 0;
   begin
      T0 := Clock;
      for X of Data.all loop
         Mn := Integer'Min (Mn, X);
         Mx := Integer'Max (Mx, X);
         S  := S + Long_Long_Integer (X);
      end loop;
      T1 := Clock;
      Put_Line ("Последовательно (проверка):");
      Put_Line ("  минимум =" & Mn'Image & ", максимум =" & Mx'Image
                & ", совпадает: "
                & Boolean'Image (Mn = Result.Min and Mx = Result.Max and S = Result.Sum));
      Put_Line ("  время, мс:" & Duration'Image (To_Duration (T1 - T0) * 1000));
   end;
end Array_Stats;
