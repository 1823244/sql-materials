Актуально для больших регистров, если есть 300 000 000 записей за год, а надо отобрать 3 000 000 за 1 месяц.

Если коротко:
В срез добавляем условие по дате из ресурса.
Это существенно экономит время построения данного среза.
Затем на основе полученной выборки определяем актуальные значения для всех измерений+период.
Последний этап - inner join первых двух. Если поля Период не равны, то строку отбрасываем.

Полный текст - в документе ОптимизацияЗапросов_Исходный_С_Доработками.docx



set dateformat ymd;

if object_id ( N'tempdb.dbo.#t1', N'U' ) is not null
drop table #t1;

create table #t1 (_period datetime, id int, _date datetime, amount decimal);
insert into #t1 values ('2018-02-01',1,'2018-02-01',100),
('2018-02-02',1,'2018-02-10',200),
('2018-02-05',1,'2018-02-05',300),
('2018-02-10',1,'2018-02-02',400),
('2018-03-01',1,'2018-02-15',500),
('2018-03-05',1,'2018-02-20',600)

insert into #t1 values 
('2018-02-01',2,'2018-02-01',100),
('2018-02-02',2,'2018-02-10',200),
('2018-02-05',2,'2018-02-05',300),
('2018-02-10',2,'2018-02-02',400),
('2018-03-01',2,'2018-02-15',500),
('2018-03-05',2,'2018-02-20',600)

insert into #t1 values 
('2018-02-01',3,'2018-02-01',100),
('2018-02-02',3,'2018-02-10',200),
('2018-02-05',3,'2018-02-05',300),
('2018-02-10',3,'2018-02-02',400),
('2018-03-01',3,'2018-02-15',500),
('2018-03-05',3,'2018-02-20',600)

insert into #t1 values 
('2018-02-01',4,'2018-02-01',100),
('2018-02-02',4,'2018-02-10',200),
('2018-02-05',4,'2018-02-05',300),
('2018-02-10',4,'2018-02-02',400),
('2018-03-01',4,'2018-02-15',500),
('2018-03-05',4,'2018-02-20',600),
('2018-03-06',4,'2018-02-01',700)

insert into #t1 values 
('2018-02-02',5,'2018-02-10',100),
('2018-02-27',5,'2018-02-01',200)

insert into #t1 values 
('2018-02-01',6,'2018-02-28',100),
('2018-02-05',6,'2018-02-27',200)

SET ANSI_PADDING ON
GO

CREATE UNIQUE CLUSTERED INDEX t1_ix ON [dbo].#t1
(
	_period ASC,
	id ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO


 
 --   select * from #t1 where id = 6;

declare @periodSreza datetime;
set @periodSreza = '20991231';

declare @startdate date;
set @startdate = '20180202';

declare @enddate date;
set @enddate = '20180228';


if object_id ( N'tempdb.dbo.#t_ТранзакцииПоИндексуБезРеквизитов', N'U' ) is not null
drop table #t_ТранзакцииПоИндексуБезРеквизитов;

if object_id ( N'tempdb.dbo.#t_АктуальныеВерсииТранзакцииПоИндексуБезРеквизитов', N'U' ) is not null
drop table #t_АктуальныеВерсииТранзакцииПоИндексуБезРеквизитов;

if object_id ( N'tempdb.dbo.#t_ПоследниВерсииПоУсловиям', N'U' ) is not null
drop table #t_ПоследниВерсииПоУсловиям;

-- это срез последних, как его делает 1С
SELECT
--T1.Period_,
T1.id
--T1._date,
--T1.amount

into #t_ТранзакцииПоИндексуБезРеквизитов 

FROM (SELECT
	T5._Period AS Period_,
	T5.id AS id,
	T5._Date AS _date,
	T5.amount AS amount
	FROM (SELECT
			T3.id AS id,
			MAX(T3._Period) AS MAXPERIOD_
		FROM #t1 as T3 WITH(NOLOCK)
		WHERE T3._Period <= @periodSreza 

		and (T3._date >= @startdate) AND (T3._date <= @enddate) -- условие по ДатаТранз поместили в срез

		GROUP BY T3.id) as T2
	INNER JOIN #t1 as T5 WITH(NOLOCK)
ON T2.id = T5.id AND T2.MAXPERIOD_ = T5._Period
) as T1

--WHERE (T1._date >= @startdate) AND (T1._date <= @enddate)
;

SELECT
	MAX(t._Period) as _period,
	t.id

into #t_АктуальныеВерсииТранзакцииПоИндексуБезРеквизитов

FROM
	 #t_ТранзакцииПоИндексуБезРеквизитов as d
	 inner join #t1 as t
	 on d.id = t.id
group by
	t.id
;



SELECT
	t._Period as _period,
	t.id
	,t._date
	,t.amount

into #t_ПоследниВерсииПоУсловиям

FROM
	 #t_АктуальныеВерсииТранзакцииПоИндексуБезРеквизитов as d
	 inner join #t1 as t
	 on d.id = t.id
	 and d._period = t._period

WHERE (t._date >= @startdate) AND (t._date <= @enddate)
;


select * from #t_ТранзакцииПоИндексуБезРеквизитов;

select * from #t_АктуальныеВерсииТранзакцииПоИндексуБезРеквизитов;

-- в этой таблице не должно быть id = 4
select * from #t_ПоследниВерсииПоУсловиям;

-- проверяем
-- это срез последних, как его делает 1С, без наших доработок
SELECT
T1.Period_,
T1.id,
T1._date,
T1.amount

FROM (SELECT
	T5._Period AS Period_,
	T5.id AS id,
	T5._Date AS _date,
	T5.amount AS amount
	FROM (SELECT
			T3.id AS id,
			MAX(T3._Period) AS MAXPERIOD_
		FROM #t1 as T3 WITH(NOLOCK)
		WHERE T3._Period <= @periodSreza 

		--and (T3._date >= @startdate) AND (T3._date <= @enddate) -- условие по ДатаТранз поместили в срез

		GROUP BY T3.id) as T2
	INNER JOIN #t1 as T5 WITH(NOLOCK)
ON T2.id = T5.id AND T2.MAXPERIOD_ = T5._Period
) as T1

WHERE (T1._date >= @startdate) AND (T1._date <= @enddate)
;
