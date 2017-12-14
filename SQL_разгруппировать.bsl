7.	(SQL) Имеем таблицы
NUM--таблица целых чисел, в которой ID имеет значения, допустим, от 1 до 1000 с инкрементом +1
(
  ID Int
),
  TBL
(
  StockID	Int,	--идентификатор выпуска ценной бумаги
  Quantity	Int	--количество ценных бумаг в выпуске (предполагаем, что не может быть больше 230 штук)
)
Необходимо "размножить" данные (сделать обратную операцию группировке), т.е. 
в ожидаемой выборке вместо одной записи по каждой позиции должно появиться количество записей,
равное количеству ценных бумаг в выпуске (реализовать с наименьшим количеством запросов).


Решение

Функция взята отсюда https://professorweb.ru/my/sql-server/window-functions/level3/3_1.php

/*func begins*/
IF OBJECT_ID('dbo.GetNums', 'IF') IS NOT NULL DROP FUNCTION dbo.GetNums;

GO
CREATE FUNCTION dbo.GetNums(@low AS BIGINT, @high AS BIGINT) 
    RETURNS TABLE
AS
RETURN
  WITH
    L0   AS (SELECT c FROM (VALUES(1),(1)) AS D(c)),
    L1   AS (SELECT 1 AS c FROM L0 AS A CROSS JOIN L0 AS B),
    L2   AS (SELECT 1 AS c FROM L1 AS A CROSS JOIN L1 AS B),
    L3   AS (SELECT 1 AS c FROM L2 AS A CROSS JOIN L2 AS B),
    L4   AS (SELECT 1 AS c FROM L3 AS A CROSS JOIN L3 AS B),
    L5   AS (SELECT 1 AS c FROM L4 AS A CROSS JOIN L4 AS B),
    Nums AS (SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS rownum
            FROM L5)
  SELECT TOP(@high - @low + 1) @low + rownum - 1 AS n
  FROM Nums
  ORDER BY rownum;
  GO
/*func ends*/

--создаем тестовый пример
select
	1 as ID
into
	NUM
union all
select
	2 as ID
union all
select
	3 as ID
go

--создаем тестовый пример
select
	1 as StockID,
	10 as Quantity
into
	TBL
union all
select
	2 as StockID,
	20 as Quantity
union all
select
	3 as StockID,
	30 as Quantity
go

--получаем результат
select * from NUM inner join TBL on TBL.StockID = NUM.ID cross apply GetNums(1, TBL.Quantity)
go