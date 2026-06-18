-- ==========================
-- PART-to-WHOLE ANALYSIS:
-- ==========================

/* What is this analysis all about ???

-- Analyze how an individual part is performing compared to the overall.
-- Helps in understanding which category has the biggest impact in the business.
*/


-- Which categories contribute the most to overall sales ???

SELECT * FROM gold.fact_sales WHERE order_date IS NULL;
SELECT TOP 5 * FROM gold.dim_products;

-- To display aggregations at multiple levels in the results, use WF

SELECT dp.category, SUM(sales_amount) total_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON fs.product_key = dp.product_key
--WHERE fs.order_date IS NOT NULL --> still not clear why this was not used
GROUP BY dp.category
ORDER BY 1 ASC;

/*
-- In the above query, we have total sales for all categories. Granularity level: category.
-- contribution % is measured by individual dimension, i.e category sales / total sales
-- While using WF, no need to use PARTITION BY or ORDER BY -- Why?
-- Because we need overall total sales without any dimension affecting that value.
*/

-- Overall sales without any dimension affecting it: 29356250
SELECT SUM(sales_amount) FROM gold.fact_sales;


WITH category_sales AS 
(SELECT dp.category, SUM(sales_amount) total_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON fs.product_key = dp.product_key
GROUP BY dp.category)

SELECT category, total_sales,
	   SUM(total_sales) OVER () overall_sales,
	   CONCAT(ROUND((CAST(total_sales AS FLOAT) / SUM(total_sales) OVER ())*100, 2), '%') percentage_of_total
FROM category_sales
ORDER BY 2 DESC;

/*
In the annual product performance query, order_date IS NOT NULL filter was applied. 
But, it wasn't applied in part-to-whole analysis. 
WHY ??

-- The general principle:
Filter out NULL on a column only when that column is actively used in your query logic.
*/
--------------------------------------------------------------------------------------------------
/*Your marketing team wants to understand customer value distribution.

"What is each customer's percentage contribution to the overall total revenue — and how much has each customer contributed in absolute sales?"
*/

WITH customer_sales AS 
(SELECT dc.customer_key, dc.first_name, dc.last_name, SUM(fs.sales_amount) total_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc ON dc.customer_key = fs.customer_key
GROUP BY dc.customer_key, dc.first_name, dc.last_name)

SELECT customer_key, first_name, last_name, total_sales, 
       SUM(total_sales) OVER () overall_sales,
	   CONCAT(ROUND((CAST(total_sales AS FLOAT) / SUM(total_sales) OVER ())*100, 4), '%') percentage_to_total_contribution
FROM customer_sales
ORDER BY 6 DESC;
