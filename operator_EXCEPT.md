https://sqlperformance.com/2012/12/t-sql-queries/left-anti-semi-join  

'''
SELECT CustomerID 
FROM Sales.Customer AS c 
EXCEPT
SELECT CustomerID
FROM Sales.SalesOrderHeaderEnlarged;
'''

Работает, как такой запрос (т.е. строится аналогичный план):  

'''
SELECT CustomerID 
FROM Sales.Customer 
WHERE CustomerID NOT IN 
(
  SELECT CustomerID 
  FROM Sales.SalesOrderHeaderEnlarged
);
'''