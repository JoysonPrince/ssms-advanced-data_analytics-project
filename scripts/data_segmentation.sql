/*
====================================================================================================
### DATA SEGMENTATION:
====================================================================================================

-- Grouping the data based on specific range.
-- This will help in understanding the correlation between 2 measures.
-- Eg: total customers by age, total products by sales range.

====================================================================================================
*/

-- Segment the products into cost ranges & count how many products fall into each segment.

SELECT * FROM gold.dim_products;

WITH product_segments AS 
(SELECT product_key, product_name, cost,
	   CASE WHEN cost < 100 THEN 'Below 100'
	        WHEN cost BETWEEN 100 AND 500 THEN '100-500'
			WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
			ELSE 'Above 1000'
	   END AS cost_range
FROM gold.dim_products)

SELECT cost_range, COUNT(product_key) total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC;

/*
WITH product_segments AS 
(SELECT product_key, product_name, cost,
	   CASE WHEN cost < 100 THEN 'Below 100'
	        WHEN cost BETWEEN 100 AND 500 THEN '100-500'
			WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
			ELSE 'Above 1000'
	   END AS cost_range
FROM gold.dim_products)

SELECT *, COUNT(product_key) OVER (PARTITION BY cost_range) total_products
FROM product_segments
ORDER BY total_products DESC;
*/
-- 2 different results, it really depends on what is the business query.
-- 2nd query seems irrelevant here, 1st one is clean.

/*
Group customers into 3 segments based on their spending behaviour:
1. VIP: at least 12 months of history & spending more than 5000
2. Regular: at least 12 months of history but spending 5000 or less
3. New: lifespan less than 12 months

Finally, find the total number of customers by each group.
*/

SELECT * FROM gold.dim_customers;

/* Solution step-by-step:

# Collect all the columns that will be needed
1. sales_amount --> because we need spending --> fact_sales
2. customer_key --> to find the total # of customers --> dim_customers
3. order_date --> to find the first & last order dates for a customer which will give lifespan --> fact_sales

# To find the lifespan of a customer:
--> Find the first order date & the last order date of a customer. This will give a lifespan.

--> No need of order_date in the CTE, once MIN(fs.order_date) & MAX(fs.order_date) are found.
--> Lifespan could have been calculated within the main query itself. CTE was used just to make things clearer.

*/

WITH product_spending AS 
(SELECT dc.customer_key, 
	   SUM(fs.sales_amount) total_spending,
	   MIN(fs.order_date) first_order,                                  -- first order date of a customer
	   MAX(fs.order_date) last_order,                                   -- last order date of a customer
	   DATEDIFF(MONTH, MIN(fs.order_date), MAX(fs.order_date)) lifespan -- order history in months
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc ON fs.customer_key = dc.customer_key
--WHERE fs.order_date IS NOT NULL
GROUP BY dc.customer_key),
--SELECT * FROM product_spending
cs AS 
(SELECT customer_key, total_spending, lifespan,
	   	   CASE WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
			WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
			ELSE 'New'
	   END AS customer_segment
FROM product_spending)

SELECT customer_segment, COUNT(customer_key) total_customers
FROM cs
GROUP BY customer_segment;
