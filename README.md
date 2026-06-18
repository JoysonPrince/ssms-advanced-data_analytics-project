# 📊 Advanced SQL Data Analysis — SSMS Project

> **"Raw data is just noise. This project turns it into decisions."**

This project goes beyond basic SELECT statements. It's a deep dive into how a real analyst thinks — breaking down business questions, choosing the right SQL tools, and building reusable report objects on top of a production-grade data warehouse.

**Platform:** Microsoft SQL Server (SSMS)  
**Warehouse Layer:** `gold` — the analytics-ready layer of a Medallion Architecture (Bronze → Silver → Gold)  
**Star Schema Tables:** `gold.fact_sales` · `gold.dim_products` · `gold.dim_customers`

---

## 📁 What's Inside

| # | Analysis | The Business Question It Answers |
|---|---|---|
| 1 | [Change Over Time](#1-change-over-time-analysis) | Is the business growing month over month? Year over year? |
| 2 | [Cumulative Analysis](#2-cumulative-analysis) | How much have we built up — and is momentum increasing or slowing? |
| 3 | [Performance Analysis](#3-performance-analysis) | Which products are punching above their weight — and which are slipping? |
| 4 | [Data Segmentation](#4-data-segmentation) | Who are our VIPs? Where do most products sit by cost? |
| 5 | [Part-to-Whole Analysis](#5-part-to-whole-analysis) | Which category actually drives the revenue? |
| 6 | [Product Report (VIEW)](#6-product-report-view) | One reusable object for all product-level KPIs |
| 7 | [Customer Report (VIEW)](#7-customer-report-view) | One reusable object for all customer-level KPIs |

---

## 1. Change Over Time Analysis

### 🧠 The Thinking

Before touching the keyboard, ask: **what granularity of time does this question actually need?**

- **Yearly** → strategic decisions, growth narratives
- **Monthly** → seasonality, campaign impact, dips and spikes
- **Year-Month combined** → the most honest view — no year gets blended into another

Getting this wrong doesn't throw an error. It just gives you a silently wrong answer — which is worse.

### ⚙️ Functions & Why They Were Used

| Function | What it does | When to use it |
|---|---|---|
| `YEAR(order_date)` | Returns an integer like `2013` | Fine for yearly grouping — integers sort correctly |
| `MONTH(order_date)` | Returns an integer `1–12` | **Dangerous alone** — merges all Januaries across all years into one row |
| `DATETRUNC(MONTH, order_date)` | Returns `2013-01-01` — a real date | Best for monthly analysis — preserves date type for sorting, charting, and date math |
| `DATETRUNC(YEAR, order_date)` | Returns `2013-01-01` — first day of the year | Best for yearly analysis — same grouping as `YEAR()` but keeps the date type |
| `FORMAT(order_date, 'yyyy-MMM')` | Returns `'2013-Jan'` as a string | Display-only — readable labels but **kills chronological sorting** |

### 🔑 The `DATETRUNC` vs `YEAR()` Decision

```sql
-- This works, but returns an integer — loses the DATE type
GROUP BY YEAR(order_date)               -- output: 2013

-- This is better — returns a proper date
GROUP BY DATETRUNC(YEAR, order_date)    -- output: 2013-01-01
```

Same grouping logic. But `DATETRUNC` keeps it as a date — which matters when results flow into Power BI visuals or further date calculations downstream.

### ⚠️ The `MONTH()` Trap

```sql
-- This merges ALL Januaries across ALL years into a single row
GROUP BY MONTH(order_date)

-- This correctly keeps each Jan-2011, Jan-2012 etc. separate
GROUP BY DATETRUNC(MONTH, order_date)
```

When `YEAR()` and `MONTH()` are used **together** in the same `GROUP BY`, they produce correct results. But `MONTH()` alone for trend analysis is a silent bug.

### 💡 Bonus Query — New Customer Acquisition by Year

```sql
SELECT DATETRUNC(YEAR, create_date) year_created,
       COUNT(customer_key) total_customers
FROM gold.dim_customers
GROUP BY DATETRUNC(YEAR, create_date)
ORDER BY 1 ASC;
```

A simple but powerful signal — how fast is the customer base growing year over year?

---

## 2. Cumulative Analysis

### 🧠 The Thinking

Monthly sales tell you **what happened this month**. A running total tells you **where the business stands overall**. These are two completely different questions — and they need different SQL patterns.

The real design challenge here isn't the `SUM()` — it's deciding **when the accumulation should reset**. Across all time? Or per year?

### ⚙️ Functions & Why They Were Used

| Function | What it does | Why it was used |
|---|---|---|
| `SUM(total_sales) OVER (ORDER BY order_month)` | Accumulates sales row by row in date order | Produces the running total across all time |
| `SUM(total_sales) OVER (PARTITION BY YEAR(order_date) ORDER BY order_date)` | Resets the accumulation at each new year | Produces a per-year running total |
| `AVG(avg_price) OVER (ORDER BY order_date)` | Tracks how the average price shifts over time | Moving average — smooths out single-month noise |
| `DATETRUNC(MONTH, order_date)` | Groups dates to first of each month | Critical — `MONTH()` alone destroys year awareness |

### 🪤 The Design Problem — and How It Was Caught

```sql
-- WRONG — looks right, but it's broken
SUM(total_sales) OVER (PARTITION BY order_date ORDER BY order_date)
```

Why is this broken? Because `order_date` was already truncated to month-level in the subquery — so **every row has a unique value**. Each partition ends up containing exactly one row. The window never accumulates. `running_total` just mirrors `total_sales`.

```sql
-- CORRECT — extracts the year from the truncated date to partition
SUM(total_sales) OVER (PARTITION BY YEAR(order_date) ORDER BY order_date)
```

Now 2011 is one partition, 2012 is another. The window accumulates month by month within each year — then resets cleanly at the start of the next.

### Subquery vs CTE — Two Ways to the Same Place

Both approaches were explored. The CTE version wins on readability when the inner aggregation gets complex:

```sql
-- CTE approach (preferred for clarity)
WITH X1 AS (
    SELECT DATETRUNC(MONTH, order_date) order_month,
           SUM(sales_amount) total_sales
    FROM gold.fact_sales
    WHERE MONTH(order_date) IS NOT NULL
    GROUP BY DATETRUNC(MONTH, order_date)
)
SELECT order_month, total_sales,
       SUM(total_sales) OVER (ORDER BY order_month ASC) running_total
FROM X1;
```

### Edge Case — Running Quantity by Shipping Date

A shipping-date-based running total was also built to track fulfillment volume accumulation over time. Key insight from the result: no shipping records appear for 2010 because those orders were physically shipped in January 2011.

---

## 3. Performance Analysis

### 🧠 The Thinking

Benchmarking product performance requires **two separate reference points**:

1. How does this year's sales compare to this product's **own historical average**?
2. How does this year's sales compare to **what this product did last year**?

These are two different window functions with different partitioning logic — but they run in the same query. The CTE handles the aggregation first, then the window functions do the benchmarking on top.

### ⚙️ Functions & Why They Were Used

| Function | What it does | Why it was used |
|---|---|---|
| `AVG(current_sales) OVER (PARTITION BY product_name)` | Average sales across all years for a given product | Benchmark: how does this year compare to the product's historical norm? |
| `LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year)` | Pulls the previous year's sales for the same product | Benchmark: year-over-year change |
| `CASE WHEN ... END` | Labels the difference as `Above average` / `Below average` / `Increase` / `Decrease` | Converts numbers into analyst-readable signals |

### Why No `ORDER BY` Inside `AVG() OVER (...)`?

```sql
AVG(current_sales) OVER (PARTITION BY product_name)
```

The average across all years for a product is the same regardless of row order. Adding `ORDER BY` would turn it into a **cumulative average** — which grows as rows are added. That's not the intent. The historical average is static for the entire product window.

### Why `ORDER BY order_year` Inside `LAG()`?

```sql
LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year)
```

`LAG` looks at "the row before this one." Without `ORDER BY`, SQL has no concept of sequence — it doesn't know which year is prior. The `ORDER BY order_year` establishes the timeline within each product's partition.

### What the Output Looks Like

```
Year  Product                   Sales   Avg     Diff     Label          PY Sales  PY Diff   Trend
2012  All-Purpose Bike Stand    159     13197   -13038   Below average  NULL      NULL      No change
2013  All-Purpose Bike Stand    37683   13197   +24486   Above average  159       +37524    Increase
2014  All-Purpose Bike Stand    1749    13197   -11448   Below average  37683     -35934    Decrease
```

A clean, readable picture of how each product performed relative to its own baseline and its own prior year — without a single pivot table.

### Scaling to Month-over-Month

Swap `YEAR()` for `DATETRUNC(MONTH, ...)` and adjust `LAG`'s `ORDER BY` to `order_month`. The entire analytical pattern stays identical — just at finer granularity.

---

## 4. Data Segmentation

### 🧠 The Thinking

Segmentation answers: **"how is the population distributed across meaningful ranges?"** It's one of the fastest ways to spot correlations — between cost and product volume, or between spending behaviour and customer loyalty.

The key upfront decision: **what is the grain?** Products come from `dim_products`. Customer spending requires joining `fact_sales` + `dim_customers`. Wrong grain = wrong answer.

### ⚙️ Functions & Why They Were Used

| Function | What it does | Why it was used |
|---|---|---|
| `CASE WHEN ... END` | Assigns each row to a defined bucket | The segmentation engine — cost ranges for products, loyalty tiers for customers |
| `CTE` | Isolates the segmentation logic | Keeps the bucket-building separate from the final count — easier to read, debug, and extend |
| `DATEDIFF(MONTH, MIN(order_date), MAX(order_date))` | Customer's order history in months | Lifespan signal — combined with spending to classify VIP, Regular, or New |
| `COUNT(customer_key)` | Counts customers per segment | The final answer — how many fall into each group |

### Two-CTE Pattern for Customer Segmentation

```
CTE 1 — product_spending:
  → Joins fact_sales + dim_customers
  → Computes total_spending, first_order, last_order, lifespan per customer

CTE 2 — cs:
  → Reads from CTE 1
  → Applies CASE WHEN to classify each customer as VIP / Regular / New

Final SELECT:
  → Groups by customer_segment
  → Counts customers in each group
```

### `GROUP BY` vs Window Function — Choosing the Right Tool

```sql
-- Option 1: Summary view — 1 row per segment (use GROUP BY)
SELECT cost_range, COUNT(product_key) total_products
FROM product_segments
GROUP BY cost_range;

-- Option 2: Row-level view — every product row + its group count (use Window Function)
SELECT *, COUNT(product_key) OVER (PARTITION BY cost_range) total_products
FROM product_segments;
```

For a segment summary report, `GROUP BY` is the clean choice. The window function version is useful when you need row-level detail alongside the group context — but for this business question, Option 1 wins.

---

## 5. Part-to-Whole Analysis

### 🧠 The Thinking

Part-to-whole answers: **"which slice of the pie matters most?"** It's about contribution — not just absolute numbers. A category with $5M in sales means nothing until you know whether that's 2% or 70% of total revenue.

The analytical challenge: you need a **grand total** attached to every row — without collapsing the per-category detail. That's a job for a window function, not a `GROUP BY`.

### ⚙️ Functions & Why They Were Used

| Function | What it does | Why it was used |
|---|---|---|
| `SUM(total_sales) OVER ()` | Grand total across the entire result — no partitioning | Attaches the overall revenue figure to every category row without collapsing them |
| `CAST(total_sales AS FLOAT)` | Converts integer to decimal before division | Prevents SQL from truncating `5 / 29` to `0` — integer division kills percentages |
| `ROUND(..., 2)` | Rounds to 2 decimal places | Keeps percentage output clean |
| `CONCAT(..., '%')` | Appends the percent symbol | Readable display label |

### Why No `PARTITION BY` or `ORDER BY` in the Window?

```sql
SUM(total_sales) OVER ()                       -- ✅ grand total — spans all rows
SUM(total_sales) OVER (PARTITION BY category)  -- ❌ wrong — just returns the category's own total
```

Any partitioning would narrow the window scope. The goal is one single number — the overall revenue — repeated on every row so the percentage formula works.

### The NULL Filter Design Decision

In performance analysis, `WHERE order_date IS NOT NULL` was applied. In part-to-whole, it wasn't. Why?

> **General principle: filter NULL on a column only when that column is actively driving your query logic** — inside a `GROUP BY`, `ORDER BY`, or date function. If it's not in the logic, filtering it just silently drops rows without adding any value.

### Customer Contribution Query

The same pattern was applied at the customer level — every customer's share of total revenue:

```sql
CONCAT(ROUND((CAST(total_sales AS FLOAT) / SUM(total_sales) OVER ()) * 100, 4), '%')
AS percentage_to_total_contribution
```

4 decimal places here (vs 2 for categories) — because individual customer contributions are tiny fractions and rounding to 2 would make most of them show `0.00%`.

---

## 6. Product Report (VIEW)

### 🧠 The Thinking

An ad-hoc query answers one question once. A **VIEW** answers any question — forever. `gold.report_products` is a pre-built analytical layer that any downstream query, dashboard, or analyst can plug into without re-joining tables or re-computing metrics from scratch.

The design questions before writing a single line:
- **What is the grain?** → One row per product (`product_key`)
- **What are dimension attributes vs metrics?** → Attributes (`product_name`, `category`, `cost`) go in `GROUP BY`. Metrics (`sales_amount`, `quantity`) get aggregated.
- **Which computed columns belong in the view vs ad-hoc on top?** → Anything reusable across multiple business questions belongs in the view.

**View:** `gold.report_products`

### CTE Architecture

```
CTE 1 — base_query
  → LEFT JOIN fact_sales + dim_products
  → Pulls raw transactional columns + product attributes
  → Filters: WHERE order_date IS NOT NULL (date is used in aggregation logic)

CTE 2 — product_aggregates
  → Groups by product grain
  → Computes all product-level metrics

Final SELECT
  → Carries over all aggregated results
  → Adds product_segment classification
  → Computes KPIs: recency, AOR, AMR, avg_selling_price
```

### Metrics Reference

| Metric | Formula | What it tells you |
|---|---|---|
| `total_orders` | `COUNT(DISTINCT order_number)` | How many unique orders included this product |
| `total_sales` | `SUM(sales_amount)` | Total revenue generated |
| `total_customers` | `COUNT(DISTINCT customer_key)` | How many unique customers bought it |
| `total_qty` | `SUM(quantity)` | Total units sold |
| `lifespan` | `DATEDIFF(MONTH, MIN(order_date), MAX(order_date))` | Months between first and last sale |
| `recency_in_months` | `DATEDIFF(MONTH, last_sale_date, GETDATE())` | How recently was it sold? |
| `avg_selling_price` | `AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0))` | Actual selling price per unit — `NULLIF` guards against divide-by-zero |
| `AOR` | `total_sales / total_orders` | Average revenue per order |
| `AMR` | `total_sales / lifespan` | Average monthly revenue — 0 if lifespan is 0 |

### The `GROUP BY` Grain Question

```sql
GROUP BY product_key, product_name, category, subcategory, cost
```

`product_key` sets the grain. The others — `product_name`, `category`, `subcategory`, `cost` — are stable product attributes that don't vary per transaction. They ride in `GROUP BY` not because they split the grouping further, but because SQL requires every non-aggregated column to be declared there. Aggregating `cost` (e.g. `AVG(cost)`) would be semantically wrong — it's a fixed property of the product, not a transactional metric.

### Product Segmentation Logic

```sql
CASE WHEN total_sales > 50000  THEN 'High-Performers'
     WHEN total_sales >= 10000 THEN 'Mid-Range'
     ELSE                           'Low-Performers'
END AS product_segment
```

---

## 7. Customer Report (VIEW)

### 🧠 The Thinking

The customer report follows the same two-CTE layering pattern as the product report — but the business lens shifts entirely. Here, the questions are about **loyalty, lifetime value, and behavioural patterns** rather than revenue performance per product.

The grain, the metrics, and the segmentation logic all flow from one question: **how do we rank and classify customers based on how long they've been with us and how much they've spent?**

**View:** `gold.report_customers`

### CTE Architecture

```
CTE 1 — base_query
  → LEFT JOIN fact_sales + dim_customers
  → Pulls order-level columns + customer identity fields
  → Derives customer_age: DATEDIFF(YEAR, birthdate, GETDATE())
  → Filters: WHERE order_date IS NOT NULL

CTE 2 — customer_aggregates
  → Groups by customer grain (customer_key + customer_number + customer_name + customer_age)
  → Computes all customer-level metrics including lifespan and last_order_date

Final SELECT
  → Carries over all aggregated results
  → Adds age_groups and customer_segment via CASE WHEN
  → Computes KPIs: recency, AVO, AMS
```

### Metrics Reference

| Metric | Formula | What it tells you |
|---|---|---|
| `customer_age` | `DATEDIFF(YEAR, birthdate, GETDATE())` | Age at time of query — time-sensitive |
| `total_orders` | `COUNT(DISTINCT order_number)` | How frequently they buy |
| `total_products` | `COUNT(DISTINCT product_key)` | Breadth of purchasing behaviour |
| `total_qty` | `SUM(quantity)` | Volume of goods purchased |
| `lifespan` | `DATEDIFF(MONTH, MIN(order_date), MAX(order_date))` | How long they've been an active customer |
| `recency` | `DATEDIFF(MONTH, last_order_date, GETDATE())` | Months since their most recent order |
| `AVO` | `total_sales / total_orders` | Average spend per order — 0 if no sales |
| `AMS` | `total_sales / lifespan` | Average monthly spend — equals `total_sales` if lifespan is 0 (new customer, single month) |

### Segmentation Logic

```sql
-- Loyalty tier
CASE WHEN lifespan >= 12 AND total_sales > 5000  THEN 'VIP'
     WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
     ELSE                                             'New'
END AS customer_segment

-- Age group
CASE WHEN customer_age < 20                THEN 'Under 20'
     WHEN customer_age BETWEEN 20 AND 29   THEN '20 to 29'
     WHEN customer_age BETWEEN 30 AND 39   THEN '30 to 39'
     WHEN customer_age BETWEEN 40 AND 49   THEN '40 to 49'
     ELSE                                       '50 and above'
END AS age_groups
```

### ⚠️ This View Is Time-Sensitive — Here's Why It Matters

Both `customer_age` and `recency` use `GETDATE()`. This means:

- A customer who was 39 last year is now 40 — they've silently **moved from the `30 to 39` bucket to `40 to 49`**
- `recency` grows every month a customer doesn't place an order
- Running the same ad-hoc query on top of this view at different times will produce **different segment distributions** — with no error, no warning

This isn't a bug — it's a design choice. But it must be documented. If reproducible snapshots are required (e.g. for month-end reporting), replace `GETDATE()` with a fixed reference date.

---

## 💡 SQL Patterns That Appear Repeatedly

If there's one thing this project demonstrates, it's that advanced SQL isn't about knowing obscure syntax — it's about knowing **which pattern fits which problem**.

| Pattern | What it solves | Where it appears |
|---|---|---|
| **CTE for staged aggregation** | Separates complex logic into readable layers | Cumulative, Performance, Segmentation, both Reports |
| **`NULLIF` for divide-by-zero safety** | Turns dangerous zeros into NULL before division | Product Report (`avg_selling_price`, `AOR`, `AMR`), Customer Report (`AVO`, `AMS`) |
| **`DATETRUNC` over `MONTH()`/`YEAR()`** | Preserves date type for accurate grouping and sorting | Change Over Time, Cumulative |
| **`SUM() OVER ()` with no partition** | Computes grand total without collapsing rows | Part-to-Whole |
| **`PARTITION BY` + `ORDER BY` in window** | Accumulates within a group in sequence | Cumulative (running total), Performance (`LAG`) |
| **`PARTITION BY` without `ORDER BY`** | Computes static group-level aggregates | Performance (historical average per product) |
| **`CASE WHEN` for human-readable labels** | Converts raw numbers into analyst-friendly signals | Performance, Segmentation, both Reports |
| **`DATEDIFF(MONTH, MIN(), MAX())`** | Measures customer/product lifespan from transaction history | Segmentation, Product Report, Customer Report |

---

## 🛠️ Tools & Environment

- **SQL Server Management Studio (SSMS)**
- **Microsoft SQL Server**
- **Architecture:** Medallion (Bronze → Silver → Gold)
- **Modelling:** Star Schema — central fact table joined to dimension tables
- **Report objects:** SQL VIEWs (`gold.report_products`, `gold.report_customers`) — drop-and-recreate pattern with `IF OBJECT_ID(...) IS NOT NULL DROP VIEW`
