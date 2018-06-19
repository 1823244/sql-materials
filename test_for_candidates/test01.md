http://kirillov-blog.blogspot.com/2014/09/sql.html

Тестовые SQL-задачи от работодателя
Как-то раз мне пришлось решать тестовые задачи от одного работодателя. Компания занимается поддержкой и разработкой веб-сервисов на основе технологий Microsoft. Я претендовал на должность системного аналитика и разработчика баз данных, работающего с Microsoft SQL Server.  Данный тест мною был успешно пройден, но я не устроил кадровиков компании по желаемой зарплате. В итоге, предпочтение отдали другому, менее притязательному кандидату. По-моему, зарплата в 60000 руб по Москве является небольшой для человека, владеющими подобными технологиями. Таково уж мое мнение. Итак, следующие задачи:


Вопрос 1
Дана таблица:

CREATE TABLE dbo.call 
  ( 
     subscriber_name VARCHAR(64) NOT NULL, 
     event_date      DATETIME NOT NULL, 
     event_cnt       INT NOT NULL 
  ) 

Требуется написать запрос, возвращающий для каждого абонента минимальную дату, когда количество событий было максимально, и максимальную дату, когда количество событий было минимально, а также количество событий.

Результат:

subscriber_name |	min_date	|	max_event_cnt	|	max_date	|	min_event_cnt
Subscriber1		|	20091012	|	15				|	20061012	|	10
Subscriber2		|	20080301	|	20				|	20090513	|	8


Решение задачи:

Достаточно простой запрос c with, который на первой стадии  группирует абонентов и получает минимальное и максимальное количество событий. На втором этапе запрос делает выборку дат при минимальном и максимальном количестве событий.

with ish as (select subscriber_name,max(event_cnt) as max_event_cnt,min(event_cnt) as min_event_cnt from call
group by subscriber_name)
select
subscriber_name,
(select min(event_date) from call where subscriber_name=ish.subscriber_name and event_cnt=ish.max_event_cnt) as min_date,
max_event_cnt,
(select max(event_date) from call where subscriber_name=ish.subscriber_name and event_cnt=ish.min_event_cnt) as max_date,
min_event_cnt
from ish;


Вопрос 2 
Как бы вы оптимизировали следующий запрос (показан полный скрипт таблицы; приведите обоснование своего выбора)?

CREATE TABLE dbo.call 
  ( 
     id              INT IDENTITY PRIMARY KEY CLUSTERED, 
     subscriber_name VARCHAR(64) NOT NULL, 
     event_date      DATETIME NOT NULL, 
     subtype         VARCHAR(32) NOT NULL, 
     type            VARCHAR(128) NOT NULL, 
     event_cnt       INT NOT NULL 
  ) 

SELECT * 
FROM   dbo.call 
WHERE  subscriber_name = @a 
       AND event_date > @b 
       AND subtype = @c 


Решение задачи:

Необходимо создать некластерный и отфильтрованный индекс.
Скорей всего поле subtype, участвующее в запросе, имеет ограниченный набор значений.  По каждому из этих значений было бы необходимо создать отфильтрованный индекс, пример:


create nonclustered index call_idx_subtype_val1 on dbo.call(subscriber_name,event_date,subtype) where subtype='val1';
create nonclustered index call_idx_subtype_val1 on dbo.call(subscriber_name,event_date,subtype) where subtype='val2';

...

--Пример запроса, использующего индекс

select *
from dbo.call
where subscriber_name = 'Ivanov' and event_date >
convert(datetime, '2014-08-22 00:00:00.000',  121)
 and subtype = 'val1';




Вопрос 3
Из таблицы следующей структуры:
CREATE partition FUNCTION pf_monthly(datetime) AS range RIGHT FOR VALUES ( 
'20120201', '20120301', '20120401', '20120501', '20120601', '20120701', 
'20120801', '20120901', '20121001', '20121101', '20121201') 

go 

CREATE partition scheme ps_monthly AS partition pf_monthly ALL TO ([primary]) 

go 

CREATE TABLE dbo.order_detail 
  ( 
     order_id      INT NOT NULL, 
     product_id    INT NOT NULL, 
     customer_id   INT NOT NULL, 
     purchase_date DATETIME NOT NULL, 
     amount        MONEY NOT NULL 
  ) 
ON ps_monthly(purchase_date) 

go 

CREATE CLUSTERED INDEX ix_purchase_date 
  ON dbo.order_detail(purchase_date) 

go 

Необходимо удалить случайно внесенные данные по клиенту с id 42, за период с мая по июнь (включительно) 2012-го года, что составляет более 80% записей за этот период. В таблице несколько миллиардов записей. Какие есть способы решения данной задачи?


Решение задачи:

Нужно в секционированной таблице order_detail, секции, отвечающие за май и июнь, сделать отдельными таблицами.  
Далее эти отдельные таблицы очистить от ошибочных данных и  сделать опять в качестве секций таблицы order_detail.
Пример:


declare @PartMay  int;
declare @PartJune  int;
--получаем номер секции за май
set @PartMay=(SELECT  $partition.order_detail('20120501'));
--получаем номер секции за июнь
set @PartJune=(SELECT  $partition.order_detail('20120501'));

--создание таблицы с данными по Маю
create table dbo.order_detailMay         (
                               order_id int       not null
                ,              product_id int   not null
                ,              customer_id int               not null
                ,              purchase_date datetime not null           
                ,              amount               money                 not null
);

--создание таблицы с данными по июню
create table dbo.order_detailJune         (
 order_id int      not null
                ,              product_id int   not null
                ,              customer_id int               not null
                ,              purchase_date datetime not null           
                ,              amount               money                 not null
);

--переключаем секции с маем и июнем на отдельные таблицы
alter table dbo.order_detail switch partition @PartMay to dbo.order_detailMay;
alter table dbo.order_detail switch partition @PartJune to dbo.order_detailJune;

--удаление ошибочных данным по клиенту 42
delete from dbo.order_detailMay where customer_id=42;
delete from dbo.order_detailJune where customer_id=42;

--переключим очищенные таблицы в качестве секций основной таблицы
ALTER TABLE dbo.order_detailMay switch TO dbo.order_detail PARTITION @PartMay;
ALTER TABLE dbo.order_detailJune switch TO dbo.order_detail PARTITION @PartJune;



Вопрос 4

Какое отличие(я) между delete from dbo.my_table и truncate table ?

Мои ответы:

1. delete логирует удаление построчно,  truncate – по страницам  данных в таблице, поэтому журнал транзакций у delete больше
2. delete блокирует каждую удаляемую строку, truncate – всю таблицу
3. триггеры срабатывают только на delete
4. truncate нельзя использовать, если на поле таблицы ссылается  внешний ключ
5. truncate нельзя использовать, если таблица участвует в репликации
6. truncate быстрее delete


Вопрос 5

Система успешно работала полгода, затем неожиданно производительность серьезно деградировала. Каковы возможные проблемы, пути решения?

Мои ответы:

1) Возможно проблема с блокировками ресурсов. Из консоли выполняем EXEC
sp_lock, находим блокировки с монопольным доступом (X), далее удаляем
монопольные блокировки с помощью команды kill.

2) Проблемы с аппаратной частью – возможно отказывает жесткий диск. Проверить DBCC CHECKDB

3) Фрагментация индексов.  Для проверки – выполняем

SELECT OBJECT_NAME(OBJECT_ID), index_id,index_type_desc,index_level,
avg_fragmentation_in_percent,avg_page_space_used_in_percent,page_count
FROM sys.dm_db_index_physical_stats
(DB_ID(N'database'), NULL, NULL, NULL, NULL)
ORDER BY avg_fragmentation_in_percent DESC


и проверяем значение avg_fragmentation_in_percent. Если оно малое (от 5 до 30 %), то выполняем ALTER INDEX REORGANIZE, если большее, то выполняем ALTER INDEX REBUILD. Индексы меньше фрагментируются, если их создавать с FILLFACTOR<100>

4) Медленные запросы на больших таблицах. Необходимо определить время выполнения запросов с помощью SQLProfiler. Для них  проанализировать планы выполнения, выявить использование индексов. Возможная ошибка проектирования – использование кластерных индексов на таблицах,  в которых столбцы обновляются очень часто.
