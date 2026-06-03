-- ===============================
-- Change-over-time analysis:
-- ===============================

-- Analyzing how a measure evolves over time.
-- Helps track trends and identify seasonality in the data.

USE DataWarehouse;

-- Month-level aggregation to check trends over time -- in this case, MONTHLY TRENDS
SELECT MONTH(order_date) order_month, SUM(sales_amount) total_sales
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY MONTH(order_date)
ORDER BY 1 ASC; -- 1 here stands for the 1st column i.e MONTH(order_date)


-- Year-level aggregation to check trends over time -- OR, YEARLY TRENDS
SELECT YEAR(order_date) order_year, SUM(sales_amount) total_sales,
									 COUNT(DISTINCT customer_key) total_customers,
									 SUM(quantity) total_qty
FROM gold.fact_sales
WHERE YEAR(order_date) IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY 1 ASC;
-- Changes over Years: A high-level overview insight that helps with strategic decision-making.

-- From the result, as an analyst, one should find out whether there was any increase in revenue over time (years).
-- If yes, good, but, if there wasn't any rev increase, it means that there is some issue & that needs further analysis.


-- Month-level business overview:
SELECT MONTH(order_date) order_month, SUM(sales_amount) total_sales,
									 COUNT(DISTINCT customer_key) total_customers,
									 SUM(quantity) total_qty
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY MONTH(order_date)
ORDER BY 1 ASC; --> -- MONTH() will give a INT o/p, so, sorting is not an issue.
-- Changes over Months: This is a detailed insight to discover seasonality in your data.

-- This result shows all the month aggregates i.e, all JAN months are clubbed into one, for every year present in the data.


-- Year-Month-level business overview:
SELECT YEAR(order_date) order_year,
	   MONTH(order_date) order_month,
	   SUM(sales_amount) total_sales,
	   COUNT(DISTINCT customer_key) total_customers,
	   SUM(quantity) total_qty
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY 1,2 ASC;
-- YEAR() will give a INT o/p, so, sorting is not an issue.


-- If you want to show a single DAY for every MONTH, then use DATETRUNC: This eliminates extra columns
SELECT DATETRUNC(MONTH, order_date) order_date,
	   SUM(sales_amount) total_sales,
	   COUNT(DISTINCT customer_key) total_customers,
	   SUM(quantity) total_qty
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY DATETRUNC(MONTH, order_date)
ORDER BY 1 ASC;
-- DATETRUNC() will truncate the DATE to 1st DAY of every MONTH present in the data


-- If you want to show a single day for every YEAR:
SELECT DATETRUNC(YEAR, order_date) order_year,
	   SUM(sales_amount) total_sales,
	   COUNT(DISTINCT customer_key) total_customers,
	   SUM(quantity) total_qty
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY DATETRUNC(YEAR, order_date)
ORDER BY 1 ASC;
-- It truncates every DATE down to JANUARY 1st of that YEAR

/* Why DATETRUNC over YEAR() alone ???
You might wonder — why not just GROUP BY YEAR(order_date)? You could, but:

YEAR(order_date) returns an integer like 2010 — loses the DATE data type
DATETRUNC(YEAR, order_date) returns a proper date 2010-01-01 — plays nicely with date formatting, charting tools, and further date calculations

Same grouping logic, but DATETRUNC keeps the result as a usable date value.
*/

-- FORMAT can be used to modify DATEs as well -- but DATE sorting will be lost
SELECT FORMAT(order_date, 'yyyy-MMM') order_year,
	   SUM(sales_amount) total_sales,
	   COUNT(DISTINCT customer_key) total_customers,
	   SUM(quantity) total_qty
FROM gold.fact_sales
WHERE MONTH(order_date) IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM')
ORDER BY FORMAT(order_date, 'yyyy-MMM') ASC;
-- FORMAT() gives a STRING o/p

-- How many new customers were added each year ???
SELECT YEAR(create_date) year_created, COUNT(customer_key) total_customers
FROM gold.dim_customers
GROUP BY YEAR(create_date)
ORDER BY 1 ASC;
-- OR --
SELECT DATETRUNC(YEAR, create_date) year_created, COUNT(customer_key) total_customers
FROM gold.dim_customers
GROUP BY DATETRUNC(YEAR, create_date)
ORDER BY 1 ASC;
