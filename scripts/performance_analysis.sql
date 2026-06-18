-- ========================
-- PERFORMANCE ANALYSIS:
-- ========================

/*
## Analyze the yearly performance of the products by comparing each product's sales to both its avg sales performance & its PY Sales

--> When the task says 'yearly perfromance' -- use YEAR().
--> there shouldn't be any confusion in which DATE function to use.
--> 'yearly performance of the products' -- use product names not product keys
--> then find total sales, average sales and PY sales -- using LAG()
*/

SELECT TOP 10 * FROM gold.fact_sales;

-- Find total sales along with dimension - product name and YEAR from order_date:
SELECT YEAR(fs.order_date) order_year, dp.product_name, SUM(fs.sales_amount) current_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON dp.product_key = fs.product_key
WHERE fs.order_date IS NOT NULL
GROUP BY YEAR(fs.order_date), dp.product_name
ORDER BY 2,1 ASC;


-- sorted the data first by product name & then by order year. WHY ???
-- This way, I can see all the years when this product was sold.
-- DO NOT CALCULATE AVERAGE SALES on top of the above result . It will have identical sales values as in total_sales, which is wrong.
-- BASIC RULE: Cannot query 2 measures in a single query.

/*
2012	All-Purpose Bike Stand	159
2013	All-Purpose Bike Stand	37683
2014	All-Purpose Bike Stand	1749
-- This product was sold in 3 different years
-- We have to use these sales across 3 years to find the avg sales for this product
-- Using basic AVG() will not solve this task. Because, that will take avg of all products across all years.
-- Use WF to solve the task. PARTITION BY product name because we need avg sales for products.
-- No ORDER BY within WF, WHY ??? because avg will be same for this window
*/

-- average sales:
WITH X1 AS 
(SELECT YEAR(fs.order_date) order_year, dp.product_name, SUM(fs.sales_amount) current_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON dp.product_key = fs.product_key
WHERE fs.order_date IS NOT NULL
GROUP BY YEAR(fs.order_date), dp.product_name)

SELECT order_year, product_name, current_sales, 
	   AVG(current_sales) OVER (PARTITION BY product_name) average_sales,
	   current_sales - AVG(current_sales) OVER (PARTITION BY product_name) diff_avg,
	   CASE WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above average'
			WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below average'
			ELSE 'Average'
	   END AS avg_change,
	   
	   -- PY sales
	   LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) PY_sales,
	   current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) diff_py,
	   CASE WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
			WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
			ELSE 'No change'
	   END AS py_change
FROM X1
ORDER BY 2,1 ASC;

/*
2012	All-Purpose Bike Stand	159	    13197	-13038	Below average	NULL	 NULL	No change
2013	All-Purpose Bike Stand	37683	13197	 24486	Above average	159	     37524	Increase
2014	All-Purpose Bike Stand	1749	13197	-11448	Below average	37683	-35934	Decrease

-- In 2012, sales 159 | avg sales 13197 | 'below avg' sale | no PY sales to compare.
-- Similarly, in 2014, sales 37683 | avg sales 13197 | 'above avg' sale | increase in sales compared to PY sales 159.
-- In 2014, sales 1749 | avg sales 13197 | 'below avg' sale | decrease in sales compared to PY sales 37683.

-- Replace YEAR with DATETRUNC(MONTH, .....) for month-over-month analysis.
--> LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) -- Why ORDER BY order_year ??
--> We need to get PY sales value for a given product window sorted by the earliest year, so, that's why ORDER BY order_year
*/

WITH X1 AS 
(SELECT DATETRUNC(MONTH,fs.order_date) order_month, dp.product_name, SUM(fs.sales_amount) current_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON dp.product_key = fs.product_key
WHERE fs.order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH,fs.order_date), dp.product_name)

SELECT order_month, product_name, current_sales, 
	   AVG(current_sales) OVER (PARTITION BY product_name) average_sales,
	   current_sales - AVG(current_sales) OVER (PARTITION BY product_name) diff_avg,
	   CASE WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above average'
			WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below average'
			ELSE 'Average'
	   END AS avg_change,
	   -- M-o-M analysis
	   LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) PY_sales,
	   current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) diff_py,
	   CASE WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) > 0 THEN 'Increase'
			WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) < 0 THEN 'Decrease'
			ELSE 'No change'
	   END AS py_change
FROM X1
ORDER BY 2,1 ASC;

--> AVG(current_sales) OVER (PARTITION BY product_name) average_sales
--> This will give an avg across all months across all years for that product — not just within a year.
--> This query is correct for this business query.

--> If the query is:
--> How does this month compare to the average monthly sales of this product within the same year?
-- Then, use AVG(current_sales) OVER (PARTITION BY product_name, YEAR(order_month)).

WITH X1 AS 
(SELECT DATETRUNC(MONTH,fs.order_date) order_month, dp.product_name, SUM(fs.sales_amount) current_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON dp.product_key = fs.product_key
WHERE fs.order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH,fs.order_date), dp.product_name)

SELECT order_month, product_name, current_sales, 
	   AVG(current_sales) OVER (PARTITION BY product_name, YEAR(order_month)) average_sales,
	   current_sales - AVG(current_sales) OVER (PARTITION BY product_name) diff_avg,
	   CASE WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above average'
			WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below average'
			ELSE 'Average'
	   END AS avg_change,
	   -- M-o-M analysis
	   LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) PY_sales,
	   current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) diff_py,
	   CASE WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) > 0 THEN 'Increase'
			WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_month) < 0 THEN 'Decrease'
			ELSE 'No change'
	   END AS py_change
FROM X1
ORDER BY 2,1 ASC;
