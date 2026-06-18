/*
==================================================================================================================
Customer Report:
==================================================================================================================
Purpose:
		-- This report consolidates key customer metrics and behaviours.

Highlights:
	1. Gathers essential fields such as names, ages and transaction details.
	2. Segments customers into categories (VIP, Regular and New) and age groups.
	3. Aggregates customer-level metrics:
		-- Total orders
		-- Total sales
		-- Total quantity purchased
		-- Total products
		-- Lifespan in Months
	4. Calculates valuable KPIs:
		-- Recency (# of months since last order)
		-- average order value: total sales/total # of orders
		-- average monthly spend: total sales/ # of months or lifespan

==================================================================================================================
*/

USE DataWarehouse;

/* Why each column was used ???
--> fs.order_number -- MEASURE 1: # of orders
--> fs.product_key -- MEASURE 2: # of products
--> fs.order_date -- to find the lifespan by using MAX(fs.order_date) & MIN(fs.order_date)
--> fs.sales_amount -- MEASURE 3: total sales 
--> fs.quantity -- MEASURE 4: total qty
--> dc.birthdate -- used within DATEDIFF() to get age
--> dc.firstname & dc.lastname -- used within CONCAT() to get customer name

--> dc.customer_key & dc.customer_number -- represents the customer granularity needed for this report along with
    derived customer names from CONCAT() & customer age derived from birthdate
*/

IF OBJECT_ID('gold.report_customers', 'V') IS NOT NULL
	DROP VIEW gold.report_customers;

GO
CREATE VIEW gold.report_customers AS 
WITH base_query AS (
/* ---------------------------------------------------------------------
1. Base query: Retrieve	core columns from fact_sales and dim_customers.
------------------------------------------------------------------------*/
SELECT fs.order_number, fs.product_key, fs.order_date, fs.sales_amount, fs.quantity,
	   dc.customer_key, dc.customer_number, 
	   CONCAT(dc.first_name, ' ', dc.last_name) customer_name, 
	   DATEDIFF(YEAR, dc.birthdate, GETDATE()) customer_age
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc 
ON fs.customer_key = dc.customer_key
WHERE fs.order_date IS NOT NULL),

customer_aggregates AS (
/* ---------------------------------------------------------------------
2. Aggregates customer-level metrics.
------------------------------------------------------------------------*/
SELECT customer_key, customer_number, customer_name, customer_age,
	   COUNT(DISTINCT order_number) total_orders,
	   SUM(sales_amount) total_sales,
	   SUM(quantity) total_qty,
	   COUNT(DISTINCT product_key) total_products,
	   MAX(order_date) last_order_date,  -- This metric is needed for calculating 'recency'
	   DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) lifespan
FROM base_query
GROUP BY customer_key, customer_number, customer_name, customer_age)

SELECT customer_key, customer_number, customer_name, customer_age,
	   CASE 
			WHEN customer_age < 20 THEN 'Under 20'
			WHEN customer_age BETWEEN 20 AND 29 THEN '20 to 29'
			WHEN customer_age BETWEEN 30 AND 39 THEN '30 to 39'
			WHEN customer_age BETWEEN 40 AND 49 THEN '40 to 49'
			ELSE '50 and above'
	   END AS age_groups,
	   CASE 
			WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
			WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
			ELSE 'New'
	   END AS customer_segment,
	   total_orders,
	   total_sales,
	   total_qty,
	   total_products,
	   last_order_date,
	   lifespan,
	   -- Computing recency
	   DATEDIFF(MONTH, last_order_date, GETDATE()) recency, -- how long has it been since the most recent order
	   -- Computing average order value aka AVO
	   CASE WHEN total_sales = 0 THEN 0
	   ELSE total_sales / total_orders 
	   END AS AVO,
	   -- Computing average monthly spend aka AMS
	   CASE WHEN lifespan = 0 THEN total_sales
	   ELSE total_sales / lifespan 
	   END AS AMS
FROM customer_aggregates;



/*
" CASE WHEN lifespan = 0 THEN total_sales
	   ELSE total_sales / lifespan 
	   END AS AMS "

## Note: WHEN lifespan = 0 THEN total_sales, WHY ???
--> If a customer bought on March and never bought again, that makes the lifespan = 0
--> So, whatever sales he did becomes the avg monthly spend because he ordered only once
*/

-- The customer report is built. Build a VIEW for this report to let others use this as well.

SELECT * FROM gold.report_customers
WHERE customer_age BETWEEN 30 AND 39;

-- Quick analysis any DA could do after the VIEW was created by DE
SELECT age_groups,
	   COUNT(customer_number) total_customers,
	   SUM(total_sales) total_sales
FROM gold.report_customers
GROUP BY age_groups;

/*
Result for DATEDIFF(YEAR, dc.birthdate, '2025-12-01') customer_age in the base query:
age_groups		total_customers		total_sales
30 to 39			196					279917
40 to 49			6103				9566103
50 and above		12183				19505238

-- DwB had '2025-12-01' this date while recording. And I coded in 2026, thus there is no 30-39 age group.
-- These ages have migrated to 40+, thus the difference in results observed.
*/
