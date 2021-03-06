Источник habrahabr.ru
Автор minamoto
https://habrahabr.ru/post/216309/

Статистика ожиданий SQL Server'а или пожалуйста, скажите мне, где болит
http://www.sqlskills.com/blogs/paul/wait-statistics-or-please-tell-me-where-it-hurts/
Администрирование баз данных, Microsoft SQL Server
Перевод
Сколько раз вы испытывали проблемы с производительностью SQL Server'а и решали, куда именно смотреть?

Одна из самых редко используемых методологий устранения проблем с производительностью SQL Server'а называется «Ожидания и очереди» (также известная как «статистика ожиданий»). Основная предпосылка методологии состоит в том, что SQL Server постоянно отслеживает, какие потоки выполнения должны ждать. Вы можете запросить у SQL Server'а эту информацию для того чтобы сократить перечень возможных причин проблем с производительностью. «Ожидания» — это то, что отслеживает SQL Server. «Очереди» — это ресурсы, доступ к которым ожидают потоки. Система обычно фиксирует огромное количество ожиданий, и все они означают ожидание доступа к различным ресурсам. Для примера, ожидание PAGEIOLATCH_EX означает, что поток ожидает чтения страницы данных с диска в буферный пул. Ожидание LCK_M_X означает, что поток ожидает возможности наложить эксклюзивную блокировку на что-то.

Отличная новость состоит в том, что SQL Server знает, в чем именно заключаются проблемы с производительностью, и все что вам нужно — это спросить у него… и потом правильно интерпретировать то, что он скажет, что может быть немного сложнее.

Следующая информация — для людей, которые переживают за каждое ожидание и понять, что его вызывает. Ожидания возникают всегда. Так уж устроена система планирования работы SQL Server'а.

Поток использует процессор и имеет статус «выполняется» (RUNNING) до тех пор, пока не сталкивается с необходимостью дождаться доступа к ресурсу. В этом случае он помещается в неупорядоченный список потоков в состоянии «приостановлен» (SUSPENDED). В то же время, следующий поток в очереди потоков, ожидающих доступ к процессору, организованной по принципу FIFO (первым поступил — первым выбыл), и имеющих статус «готов к выполнению» (RUNNABLE) получает доступ к процессору и становится «выполняющимся». Если поток в состоянии «приостановлен» получает уведомление о том, что его ресурс доступен, он становится «готовым к выполнению» и помещается в конец очереди готовых к выполнению потоков. Поток продолжает свое циклическое движение по цепочке «выполняется» — «приостановлен» — «готов к выполнению» до тех пор, пока задание не выполнено. Вы можете увидеть процессы и их состояния, использовав динамическое административное представление (Dynamic Management View, DMV) sys.dm_exec_requests.

SQL Server отслеживает время, которое проходит между выходом потока из состояния «выполняется» и его возвращением в это состояние, определяя его как «время ожидания» (wait time) и время, потраченное в состоянии «готов к выполнению», определяя его как «время ожидания сигнала» (signal wait time), т.е. сколько времени требуется потоку после получения сигнала о доступности ресурсов для того, чтобы получить доступ к процессору. Мы должны понять, сколько времени тратит поток в состоянии «приостановлен», называемом «временем ожидания ресурсов» (resource wait time), вычитая время ожидания сигнала из общего времени ожидания.

Отличный источник информации, который я рекомендую прочитать по этому поводу — это новый (2014) документ по статистике ожидания [«Настройка производительности SQL Server с использованием статистики ожиданий: Пособие для новичка»](https://www.sqlskills.com/help/sql-server-performance-tuning-using-wait-statistics/) (английский), который я советую вам прочитать.
Также есть гораздо более старый документ [«Регулировка производительности с использованием ожиданий и очередей»](http://download.microsoft.com/download/4/7/a/47a548b9-249e-484c-abd7-29f31282b04d/Performance_Tuning_Waits_Queues.doc) (английский) с большим количеством полезной информации, но достаточно сильно устаревшей на текущий момент.
Лучшее пособие по различным типам ожиданий (и классам кратковременных блокировок) — моя исчерпывающая [библиотека ожиданий](https://www.sqlskills.com/help/waits/) (английский) и [кратковременных блокировок](https://www.sqlskills.com/help/latches/) (английский).

Вы можете запросить SQL Server о накопленной статистике ожидания, используя DMV sys.dm_os_wait_stats. Многие предпочитают обернуть вызов DMV в некий сводный код. Ниже находится самая последняя версия моего скрипта по состоянию на 2016 год, который работает со всеми версиями и включает типы ожиданий для SQL Server 2016 (версию скрипта для использования в Azure ищите [здесь](https://sqlperformance.com/2016/03/sql-performance/tuning-azure-sql-database)):

```
WITH [Waits] AS
    (SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
       100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR',
        N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH',
        N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
        N'CHKPT', N'CLR_AUTO_EVENT',
        N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
 
        -- Maybe uncomment these four if you have mirroring issues
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE',
        N'DBMIRROR_WORKER_QUEUE', N'DBMIRRORING_CMD',
 
        N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT',
        N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
 
        -- Maybe uncomment these six if you have AG issues
        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE',
        N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
 
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP',
        N'LOGMGR_QUEUE', N'MEMORY_ALLOCATION_EXT',
        N'ONDEMAND_TASK_QUEUE',
        N'PREEMPTIVE_XE_GETTARGETSTATE',
        N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_ASYNC_QUEUE',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK',
        N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH',
        N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP',
        N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT',
        N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH',
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'SQLTRACE_WAIT_ENTRIES', N'WAIT_FOR_RESULTS',
        N'WAITFOR', N'WAITFOR_TASKSHUTDOWN',
        N'WAIT_XTP_RECOVERY',
        N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN',
        N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT')
    AND [waiting_tasks_count] > 0
    )
SELECT
    MAX ([W1].[wait_type]) AS [WaitType],
    CAST (MAX ([W1].[WaitS]) AS DECIMAL (16,2)) AS [Wait_S],
    CAST (MAX ([W1].[ResourceS]) AS DECIMAL (16,2)) AS [Resource_S],
    CAST (MAX ([W1].[SignalS]) AS DECIMAL (16,2)) AS [Signal_S],
    MAX ([W1].[WaitCount]) AS [WaitCount],
    CAST (MAX ([W1].[Percentage]) AS DECIMAL (5,2)) AS [Percentage],
    CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgWait_S],
    CAST ((MAX ([W1].[ResourceS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgRes_S],
    CAST ((MAX ([W1].[SignalS]) / MAX ([W1].[WaitCount])) AS DECIMAL (16,4)) AS [AvgSig_S],
    CAST ('https://www.sqlskills.com/help/waits/' + MAX ([W1].[wait_type]) as XML) AS [Help/Info URL]
FROM [Waits] AS [W1]
INNER JOIN [Waits] AS [W2]
    ON [W2].[RowNum] <= [W1].[RowNum]
GROUP BY [W1].[RowNum]
HAVING SUM ([W2].[Percentage]) - MAX( [W1].[Percentage] ) < 95; -- percentage threshold
GO
```

Результат запроса покажет ожидания, сгруппированные по процентам от всех ожиданий в системе, в порядке убывания. Ожидания, на которые (потенциально) стоит обратить внимание, находятся в верхней части списка и представляют собой большую часть ожиданий, на которые тратит время SQL Server. Вы видите большой перечень ожиданий, которые убраны из рассмотрения — как я и говорил ранее, они возникают всегда и те, что перечислены выше, мы можем, как правило, игнорировать.

Вы также можете сбросить накопленную сервером статистику, используя этот код:

```
DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR);
GO
```

И, конечно же, вы можете придти к тому, чтобы сохранять результаты каждые несколько часов или каждый день и делать некоторый временной анализ для того, чтобы выяснить направление изменений, или автоматически отслеживать проблемы в случае, если они начинают появляться.
Вы можете также использовать панель мониторинга производительности (Performance Dashboard) для того, чтобы отобразить результаты графически в SQL Server 2005 и Сборщик данных (Data Collector) в SQL Server 2008. В в SQL Server 2000 вы можете использовать DBCC SQLPERF (N’waitstats’).

После того, как вы получите результаты, вы начнете думать, как их интерпретировать и куда смотреть. Документ, на который я ссылался ранее, имеет огромное количество информации по большинству типов ожиданий (за исключением добавленных в SQL Server 2008). 

Теперь мне хотелось бы предоставить результаты исследования, которое я опубликовал некоторое время назад. Я просил людей запустить код, представленный выше и сообщить мне о результатах. Я получил колоссальное количество результатов — с 1823 серверов – спасибо!

Ниже — графическое представление результатов:

![results](img01.png)

Я совсем не удивлен верхним 4 результатам, поскольку я видел их снова и снова на системах моих клиентов.

В продолжение своей статьи я собираюсь перечислить самые популярные типы ожиданий, предоставленные респондентами исследования, в порядке убывания, и прокомментировать в нескольких словах, что именно они могут значить в случае, если они являются основными для вашей системы. Формат списка показывает количество систем из опрошенных, в которых указанный тип ожидания является основным.

* 505: CXPACKET 
Означает параллелизм, но не обязательно в нем проблема. Поток-координатор в параллельном запросе всегда накапливает эти ожидания. Если параллельные потоки не заняты работой или один из потоков заблокирован, то ожидающие потоки также накапливают ожидание CXPACKET, что приводит к более быстрому накоплению статистики по этому типу — в этом и проблема. Один поток может иметь больше работы, чем остальные, и по этой причине весь запрос блокируется, пока долгий поток не закончит свою работу. Если этот тип ожидания совмещен с большими цифрами ожидания PAGEIOLATCH_XX, то это может быть сканирование больших таблиц по причине некорректных некластерных индексов или из-за плохого плана выполнения запроса. Если это не является причиной, вы можете попробовать применение опции MAXDOP со значениями 4, 2, или 1 для проблемных запросов или для всего экземпляра сервера (устанавливается на сервере параметром «max degree of parallelism»). Если ваша система основана на схеме NUMA, попробуйте установить MAXDOP в значение, равное количеству процессоров в одном узле NUMA для того, чтобы определить, не в этом ли проблема. Вам также нужно определить эффект от установки MAXDOP на системах со смешанной нагрузкой. Если честно, я бы поиграл с параметром «cost threshold for parallelism» (поднял его до 25 для начала), прежде чем снижать значение MAXDOP для всего экземпляра. И не забывайте про регулятор ресурсов (Resource Governor) в Enterprise версии SQL Server 2008, который позволяет установить количество процессоров для конкретной группы соединений с сервером.
* 304: PAGEIOLATCH_XX
Вот тут SQL Server ждет чтения страницы данных с диска в память. Этот тип ожидания может указывать на проблему в системе ввода/вывода (что является первой реакцией на этот тип ожидания), но почему система ввода/вывода должна обслуживать такое количество чтений? Возможно, давление оказывает буферный пул/память (недостаточно памяти для типичной нагрузки), внезапное изменение в планах выполнения, приводящее к большим параллельным сканированиям вместо поиска, раздувание кэша планов или некоторые другие причины. Не стоит считать, что основная проблема в системе ввода/вывода.
* 275: ASYNC_NETWORK_IO
Здесь SQL Server ждет, пока клиент закончит получать данные. Причина может быть в том, что клиент запросил слишком большое количество данных или просто получает их ооочень медленно из-за плохого кода — я почти никогда не не видел, чтобы проблема заключалась в сети. Клиенты часто читают по одной строке за раз — так называемый RBAR или «строка за агонизирующей строкой»(Row-By-Agonizing-Row) — вместо того, чтобы закешировать данные на клиенте и уведомить SQL Server об окончании чтения немедленно.
* 112: WRITELOG
Подсистема управления логом ожидает записи лога на диск. Как правило, означает, что система ввода/ввода не может обеспечить своевременную запись всего объема лога, но на высоконагруженных системах это может быть вызвано общими ограничениями записи лога, что может означать, что вам следует разделить нагрузку между несколькими базами, или даже сделать ваши транзакции чуть более долгими, чтобы уменьшить количество записей лога на диск. Для того, чтобы убедиться, что причина в системе ввода/вывода, используйте DMV sys.dm_io_virtual_file_stats для того, чтобы изучить задержку ввода/вывода для файла лога и увидеть, совпадает ли она с временем задержки WRITELOG. Если WRITELOG длится дольше, вы получили внутреннюю конкуренцию за запись на диск и должны разделить нагрузку. Если нет, выясняйте, почему вы создаете такой большой лог транзакций. Здесь (англ.) и здесь (англ.) можно почерпнуть некоторые идеи.
(прим переводчика: следующий запрос позволяет в простом и удобном виде получить статистику задержек ввода/вывода для каждого файла каждой базы данных на сервере:
```
-- Плохо: Ср.задержка одной операции > 20 мсек
USE master
GO
SELECT cast(db_name(a.database_id) AS VARCHAR) AS Database_Name
	 , b.physical_name
	 --, a.io_stall
	 , a.size_on_disk_bytes
	 , a.io_stall_read_ms / a.num_of_reads 'Ср.задержка одной операции чтения'
	 , a.io_stall_write_ms / a.num_of_writes 'Ср.задержка одной операции записи'
	 --, *
FROM
	sys.dm_io_virtual_file_stats(NULL, NULL) a
	INNER JOIN sys.master_files b
		ON a.database_id = b.database_id AND a.file_id = b.file_id
where num_of_writes > 0 and num_of_reads > 0
ORDER BY
	Database_Name
  , a.io_stall DESC
```
* 109: BROKER_RECEIVE_WAITFOR
Здесь Service Broker ждет новые сообщения. Я бы рекомендовал добавить это ожидание в список исключаемых и заново выполнить запрос со статистикой ожидания.
* 086: MSQL_XP
Здесь SQL Server ждет выполнения расширенных хранимых процедур. Это может означать наличие проблем в коде ваших расширенных хранимых процедур.
* 074: OLEDB
Как и предполагается из названия, это ожидание взаимодействия с использованием OLEDB — например, со связанным сервером. Однако, OLEDB также используется в DMV и командой DBCC CHECKDB, так что не думайте, что проблема обязательно в связанных серверах — это может быть внешняя система мониторинга, чрезмерно использующая вызовы DMV. Если это и в самом деле связанный сервер — тогда проведите анализ ожиданий на связанном сервере и определите, в чем проблема с производительностью на нем.
* 054: BACKUPIO
Показывает, когда вы делаете бэкап напрямую на ленту, что ооочень медленно. Я бы предпочел отфильтровать это ожидание. (прим. переводчика: я встречался с этим типом ожиданий при записи бэкапа на диск, при этом бэкап небольшой базы выполнялся очень долго, не успевая выполниться в технологический перерыв и вызывая проблемы с производительностью у пользователей. Если это ваш случай, возможно дело в системе ввода/вывода, используемой для бэкапирования, необходимо рассмотреть возможность увеличения ее производительности либо пересмотреть план обслуживания (не выполнять полные бэкапы в короткие технологические перерывы, заменив их дифференциальными))
* 041: LCK_M_XX
Здесь поток просто ждет доступа для наложения блокировки на объект и означает проблемы с блокировками. Это может быть вызвано нежелательной эскалацией блокировок или плохим кодом, но также может быть вызвано тем, что операции ввода/вывода занимают слишком долгое время и держат блокировки дольше, чем обычно. Посмотрите на ресурсы, связанные с блокировками, используя DMV sys.dm_os_waiting_tasks. Не стоит считать, что основная проблема в блокировках.
* 032: ONDEMAND_TASK_QUEUE
Это нормально и является частью системы фоновых задач (таких как отложенный сброс, очистка в фоне). Я бы добавил это ожидание в список исключаемых и заново выполнил запрос со статистикой ожидания.
* 031: BACKUPBUFFER
Показывает, когда вы делаете бэкап напрямую на ленту, что ооочень медленно. Я бы предпочел отфильтровать это ожидание.
* 027: IO_COMPLETION
SQL Server ждет завершения ввода/вывода и этот тип ожидания может быть индикатором проблемы с системой ввода/вывода.
* 024: SOS_SCHEDULER_YIELD
Чаще всего это код, который не попадает в другие типы ожидания, но иногда это может быть конкуренция в циклической блокировке.
* 022: DBMIRROR_EVENTS_QUEUE
* 022: DBMIRRORING_CMD
Эти два типа показывают, что система управления зеркальным отображением (database mirroring) сидит и ждет, чем бы ей заняться. Я бы добавил эти ожидания в список исключаемых и заново выполнил запрос со статистикой ожидания.
* 018: PAGELATCH_XX
Это конкуренция за доступ к копиям страниц в памяти. Наиболее известные случаи — это конкуренция PFS, SGAM, и GAM, возникающие в базе tempdb при определенных типах нагрузок (англ.). Для того, чтобы выяснить, за какие страницы идет конкуренция, вам нужно использовать DMV sys.dm_os_waiting_tasks для того, чтобы выяснить, из-за каких страниц возникают блокировки. По проблемам с базой tempdb Роберт Дэвис (его блог, твиттер) написал хорошую статью, показывающую, как их решать (англ.) Другая частая причина, которую я видел — часто обновляемый индекс с конкурирующими вставками в индекс, использующий последовательный ключ (IDENTITY).
* 016: LATCH_XX
Это конкуренция за какие либо не страничные структуры в SQL Server'е — так что это не связано с вводом/выводом и данными вообще. Причину такого типа задержки может быть достаточно сложно понять и вам необходимо использовать DMV sys.dm_os_latch_stats.
* 013: PREEMPTIVE_OS_PIPEOPS
Здесь SQL Server переключается в режим упреждающего планирования для того, чтобы запросить о чем-то Windows. Этот тип ожидания был добавлен в 2008 версии и еще не был документирован. Самый простой способ выяснить, что он означает — это убрать начальные PREEMPTIVE_OS_ и поискать то, что осталось, в MSDN — это будет название API Windows.
* 013: THREADPOOL
Такой тип говорит, что недостаточно рабочих потоков в системе для того, чтобы удовлетворить запрос. Обычно причина в большом количестве сильно параллелизованных запросов, пытающихся выполниться. (прим. переводчика: также это может быть намеренно урезанное значение параметра сервера «max worker threads»)
* 009: BROKER_TRANSMITTER
Здесь Service Broker ждет новых сообщений для отправки. Я бы рекомендовал добавить это ожидание в список исключаемых и заново выполнить запрос со статистикой ожидания.
* 006: SQLTRACE_WAIT_ENTRIES
Часть слушателя (trace) SQL Server'а. Я бы рекомендовал добавить это ожидание в список исключаемых и заново выполнить запрос со статистикой ожидания.
* 005: DBMIRROR_DBM_MUTEX
Это один из недокументированных типов и в нем конкуренция возникает за отправку буфера, который делится между сессиями зеркального отображения (database mirroring). Может означать, что у вас слишком много сессий зеркального отображения.
* 005: RESOURCE_SEMAPHORE
Здесь запрос ждет память для исполнения (память, используемая для обработки операторов запроса — таких, как сортировка). Это может быть недостаток памяти при конкурентной нагрузке.
* 003: PREEMPTIVE_OS_AUTHENTICATIONOPS
* 003: PREEMPTIVE_OS_GENERICOPS
Здесь SQL Server переключается в режим упреждающего планирования для того, чтобы запросить о чем-то Windows. Этот тип ожидания был добавлен в 2008 версии и еще не был документирован. Самый простой способ выяснить, что он означает — это убрать начальные PREEMPTIVE_OS_ и поискать то, что осталось, в MSDN — это будет название API Windows.
* 003: SLEEP_BPOOL_FLUSH
Это ожидание можно часто увидеть и оно означает, что контрольная точка ограничивает себя для того, чтобы избежать перегрузки системы ввода/вывода. Я бы рекомендовал добавить это ожидание в список исключаемых и заново выполнить запрос со статистикой ожидания.
* 002: MSQL_DQ
Здесь SQL Server ожидает, пока выполнится распределенный запрос. Это может означать проблемы с распределенными запросами или может быть просто нормой.
* 002: RESOURCE_SEMAPHORE_QUERY_COMPILE
Когда в системе происходит слишком много конкурирующих перекомпиляций запросов, SQL Server ограничивает их выполнение. Я не помню уровня ограничения, но это ожидание может означать излишнюю перекомпиляцию или, возможно, слишком частое использование одноразовых планов.
* 001: DAC_INIT
Я никогда раньше этого не видел и BOL говорит, что причина в инициализации административного подключения. Я не могу представить, как это может быть преимущественным ожиданием на чьей либо системе...
* 001: MSSEARCH
Этот тип является нормальным при полнотекстовых операциях. Если это преимущественное ожидание, это может означать, что ваша система тратит больше всего времени на выполнение полнотекстовых запросов. Вы можете рассмотреть возможность добавить этот тип ожидания в список исключаемых.
* 001: PREEMPTIVE_OS_FILEOPS
* 001: PREEMPTIVE_OS_LIBRARYOPS
* 001: PREEMPTIVE_OS_LOOKUPACCOUNTSID
* 001: PREEMPTIVE_OS_QUERYREGISTRY
Здесь SQL Server переключается в режим упреждающего планирования для того, чтобы запросить о чем-то Windows. Этот тип ожидания был добавлен в 2008 версии и еще не был документирован. Самый простой способ выяснить, что он означает — это убрать начальные PREEMPTIVE_OS_ и поискать то, что осталось, в MSDN — это будет название API Windows.
* 001: SQLTRACE_LOCK
Часть слушателя (trace) SQL Server'а. Я бы рекомендовал добавить это ожидание в список исключаемых и заново выполнить запрос со статистикой ожидания.


Надеюсь, это было интересно! Дайте мне знать, если вы заинтересованы в чем то конкретно или что вы прочитали эту статью и получили удовольствие от этого!


Добавлено пользователем AlanDenton

Прикреплю тут два скрипта, вдруг кому будет еще полезным.

1. Очистка sys.dm_os_wait_stats:
```
DBCC SQLPERF("sys.dm_os_wait_stats", CLEAR)
```
2. И слегка модифицированный запрос на выборку статистики ожиданий:
```
SELECT TOP(20)
      wait_type
    , wait_time = wait_time_ms / 1000.
    , wait_resource = (wait_time_ms - signal_wait_time_ms) / 1000.
    , wait_signal = signal_wait_time_ms / 1000.
    , waiting_tasks_count
    , percentage = 100.0 * wait_time_ms / SUM(wait_time_ms) OVER ()
    , avg_wait = wait_time_ms / 1000. / waiting_tasks_count
    , avg_wait_resource = (wait_time_ms - signal_wait_time_ms) / 1000. / [waiting_tasks_count]
    , avg_wait_signal = signal_wait_time_ms / 1000.0 / waiting_tasks_count
FROM sys.dm_os_wait_stats
WHERE [waiting_tasks_count] > 0
    AND max_wait_time_ms > 0
    AND [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR',
        N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH',
        N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
        N'CHKPT', N'CLR_AUTO_EVENT',
        N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE',
        N'DBMIRROR_WORKER_QUEUE', N'DBMIRRORING_CMD',
        N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT',
        N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE',
        N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP',
        N'LOGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE',
        N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH',
        N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP',
        N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT',
        N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH',
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'SQLTRACE_WAIT_ENTRIES', N'WAIT_FOR_RESULTS',
        N'WAITFOR', N'WAITFOR_TASKSHUTDOWN',
        N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN',
        N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
    )
ORDER BY [wait_time_ms] DESC
```

The End.