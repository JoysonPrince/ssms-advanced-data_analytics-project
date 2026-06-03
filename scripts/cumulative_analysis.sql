/*
CUMULATIVE ANALYSIS: Aggregating the data progressively over time 

-- How does it help?? --> It helps in understanding whether the business is growing or declining.

-- Some eg: running sales by year, moving average sales by month
*/

-- Calculate the total sales per month & the running total of sales over time.
SELECT TOP 10 * FROM gold.fact_sales;

-- Total sales per month
SELECT DATETRUNC(MONTH,order_date) order_month, SUM(sales_amount) total_sales
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH,order_date)
ORDER BY 1 ASC;

-- Total sales per month + Running sales per month 
-- Using subquery:
SELECT order_month, total_sales, SUM(total_sales) OVER (ORDER BY order_month ASC) running_total
FROM
(SELECT DATETRUNC(MONTH,order_date) order_month, SUM(sales_amount) total_sales
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY DATETRUNC(MONTH,order_date)) z1;

-- Using CTE:
WITH X1 AS (
SELECT DATETRUNC(MONTH,order_date) order_month, SUM(sales_amount) total_sales
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY DATETRUNC(MONTH,order_date))
SELECT order_month, total_sales, SUM(total_sales) OVER (ORDER BY order_month ASC) running_total
FROM X1;

/*
-- Use DATETRUNC() for running total, averages. 
-- MONTH() returns just an integer (1–12). It has no awareness of the year.
-- So January 2010 and January 2011 are treated as the same group and their sales get merged together.
-- Your running total would then be jumping across mixed years — completely meaningless.
-- What is running total exactly? jan sales + feb sales + mar sales of the same YEAR.
-- So, if using MONTH() merges months across years, then it is pointless and wrong.
*/

-- EDGE CASE:
-- Calculate the running total of quantity shipped, tracked by shipping date (month level) — 
-- to understand how fulfillment volume has accumulated over time.
SELECT TOP 10 * FROM gold.fact_sales;
--WHERE order_date LIKE '2010%';

WITH Y1 AS
(SELECT DATETRUNC(MONTH, shipping_date) shipping_month, SUM(quantity) monthly_qty_shipped
FROM gold.fact_sales
GROUP BY DATETRUNC(MONTH, shipping_date)
)
SELECT *, SUM(monthly_qty_shipped) OVER (ORDER BY shipping_month ASC) running_qty 
FROM Y1
ORDER BY shipping_month ASC;

-- Before finding the running qty calculation, we need total qty on a month level
-- To find total qty by month, we need to group the aggregation by month
-- Note: In the result, there is no ship date for 2010, because the shipping for those 2010 dates happened in 2011 Jan.

-- Running total extended calculation:
SELECT order_date, total_sales, SUM(total_sales) OVER (ORDER BY order_date ASC) running_total
FROM
(SELECT DATETRUNC(MONTH, order_date) order_date, SUM(sales_amount) total_sales
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH, order_date)) z1;

-- This query will give the running total for all the years present in the data.
-- How to separate the running totals for separate years ??? -- use PARTITION BY clause
-- PARTITION by what dimension ??? -- since we want running total for separate years, we need to do partition by date

SELECT order_date, total_sales, SUM(total_sales) OVER (PARTITION BY order_date ORDER BY order_date ASC) running_total
FROM
(SELECT DATETRUNC(MONTH,order_date) order_date, SUM(sales_amount) total_sales
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH,order_date)) z1;

-- we have hit a genuine SQL DESIGN PROBLEM
SELECT order_date, total_sales, SUM(total_sales) OVER (PARTITION BY YEAR(order_date) ORDER BY order_date ASC) running_total
FROM
(SELECT DATETRUNC(MONTH,order_date) order_date, SUM(sales_amount) total_sales
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH,order_date)) z1;

/* What was the DESIGN PROBLEM ???
-- PARTITION BY order_date tells the window function:
   "Reset and calculate SUM separately for each UNIQUE VALUE of order_date."
-- Since order_date is already DATETRUNC(MONTH, order_date), every row has a unique month value. 
-- So each partition contains exactly one row — and the sum of one row is just itself.
-- That's why total_sales and running_total are identical. 
-- The window never accumulates across months — it keeps resetting for every month.


## Why the 2nd query with " PARTITION BY YEAR(order_date) " works:
-- DATETRUNC(MONTH, order_date) in the subquery gives you unique monthly buckets like 2010-12-01, 2011-01-01 etc.
-- PARTITION BY YEAR(order_date) in the window function reads that truncated date and extracts just the year from it to partition — 
-- so 2010 is one partition, 2011 is another.
-- ORDER BY order_date ASC accumulates month by month within each year.
*/

-- Running total + total sales for a year + moving average price
SELECT order_date, total_sales, SUM(total_sales) OVER (ORDER BY order_date ASC) running_total,
								AVG(avg_price) OVER (ORDER BY order_date ASC) moving_avg_price
FROM
(SELECT DATETRUNC(YEAR,order_date) order_date, SUM(sales_amount) total_sales,
		AVG(price) avg_price
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(YEAR,order_date)) z1;
-- The only change: DATETRUNC(MONTH,order_date) --> DATETRUNC(YEAR,order_date)
-- PARTITION BY order_date or YEAR(order_date) not needed because the order_date is truncated to YEAR.
