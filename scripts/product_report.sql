/*
==================================================================================================================
Product Report:
==================================================================================================================
Purpose:
		-- This report consolidates key product metrics and behaviours.

Highlights:
	1. Gathers essential fields such as product names, category, subcategory and cost.
	2. Segments products by revenue to identify High-Performers, Mid-Range & Low-Performers.
	3. Aggregates product-level metrics:
		-- Total orders
		-- Total sales
		-- Total quantity sold
		-- Total customers (Unique)
		-- Lifespan in Months
	4. Calculates valuable KPIs:
		-- Recency (# of months since last sale)
		-- average order revenue (AOR): total sales/total # of orders
		-- average monthly revenue (AMR): total sales/ # of months or lifespan

==================================================================================================================
*/

/* Why each column was used ???
--> fs.order_number -- MEASURE 1: # of orders
--> fs.customer_key -- MEASURE 2: # of customers
--> fs.sales_amount -- MEASURE 3: total sales 
--> fs.quantity -- MEASURE 4: total qty
--> fs.order_date -- to find the lifespan by using MAX(fs.order_date) & MIN(fs.order_date)

--> dp.product_key, dp.product_name, dp.category, dp.subcategory, dp.cost -- product attributes.
--> These dimensions are the grains for the product report.
*/

IF OBJECT_ID('gold.report_products', 'V') IS NOT NULL
	DROP VIEW gold.report_products;

GO
CREATE VIEW gold.report_products AS

WITH base_query AS (
/* ---------------------------------------------------------------------
1. Base query: Retrieve	core columns from fact_sales and dim_products.
------------------------------------------------------------------------*/
SELECT fs.order_number, fs.customer_key, fs.order_date, fs.sales_amount, fs.quantity,
       dp.product_key, dp.product_name, dp.category, dp.subcategory, dp.cost
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON fs.product_key = dp.product_key
WHERE fs.order_date IS NOT NULL  -- filter to include only valid sales dates
),

product_aggregates AS (
/* ---------------------------------------------------------------------
2. Aggregates product-level metrics.
------------------------------------------------------------------------*/
SELECT product_key, product_name, category, subcategory, cost,
	   COUNT(DISTINCT order_number) total_orders,
	   SUM(sales_amount) total_sales,
	   SUM(quantity) total_qty,
	   COUNT(DISTINCT customer_key) total_customers,
	   MAX(order_date) last_sale_date,
	   DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) lifespan,
	   AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity,0)) avg_selling_price  -- if qty is 0, then NULL to avoid Div by Zero error
FROM base_query
GROUP BY product_key, product_name, category, subcategory, cost)

/* ---------------------------------------------------------------------
3. Final query: Combines all the CTE product results into one o/p
------------------------------------------------------------------------*/
SELECT product_key, product_name, category, subcategory, cost,
	   CASE WHEN total_sales > 50000 THEN 'High-Performers'
			WHEN total_sales >= 10000 THEN 'Mid-Range'
			ELSE 'Low-Performers'
	   END AS product_segment,
	   total_orders,
	   total_sales,
	   total_customers,
	   total_qty,
	   last_sale_date,
	   lifespan,
	   avg_selling_price,
	   DATEDIFF(MONTH, last_sale_date, GETDATE()) recency_in_months,
	   CASE WHEN total_sales = 0 THEN 0
			ELSE total_sales / total_orders
	   END AS AOR,
	   CASE WHEN lifespan = 0 THEN 0
			ELSE total_sales / lifespan
	   END AS AMR
FROM product_aggregates;

SELECT TOP 5 * FROM gold.dim_products;

/* Why was 'cost' never aggregated ???

### Mental model:
Think of the GROUP BY columns in two categories here:
Column						Role						Why in GROUP BY
product_key					Grain setter				Defines one row per product
product_name, category,     Dimension attributes        Just carried along — they describe the product
subcategory, cost

### 'cost' is a product attribute, not a transactional metric.
-- The grain of this CTE is one row per product. 'cost' is a fixed property of the product — it lives in 'dim_products'.
   and doesn't change per order or per customer.
-- So including it in GROUP BY doesn't actually change the grouping,
   since 'product_key' already guarantees one unique product per row, 'cost' just tags along for the ride.
-- It's the same reason 'product_name', 'category', & 'subcategory' are in GROUP BY — none of them are being aggregated,
   they're just descriptive attributes of the product that you want to carry forward into the final SELECT.
-- AVG(cost) AS Avg_Cost:
This would be semantically wrong — you'd be averaging a value that is already constant per product. It adds noise to the intent of the query.
*/

SELECT TOP 10 * FROM gold.report_products;
