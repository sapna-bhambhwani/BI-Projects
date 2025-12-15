# Retrieve the number of unique customers by country and city along with their average purchase value.

SELECT 
	c.name,
    c.Country,
    c.City,
    COUNT(DISTINCT c.`Customer ID`) AS unique_customers,
    AVG(t.`Invoice Total`) AS avg_purchase_value
FROM customers c
JOIN transactions t
    ON  CAST(c.`Customer ID` AS UNSIGNED) = CAST(t.`Customer ID` AS UNSIGNED)
GROUP BY 
	c.name,
    c.Country,
    c.City
ORDER BY 
	c.name,
    c.Country,
    c.City;


# Calculate the percentage of returns compared to total transactions and track how it changes monthly.

SELECT 
    DATE_FORMAT(
        STR_TO_DATE(Date, '%d-%m-%Y %H:%i'),
        '%Y-%m'
    ) AS YearMonth,
    COUNT(*) AS total_transactions,
    SUM(CASE 
            WHEN `Transaction Type` = 'Return' THEN 1 
            ELSE 0 
        END) AS total_returns,
    ROUND(
        (SUM(CASE WHEN `Transaction Type` = 'Return' THEN 1 ELSE 0 END) 
        / COUNT(*)) * 100,
        2
    ) AS return_percentage
FROM transactions
GROUP BY 
    DATE_FORMAT(
        STR_TO_DATE(Date, '%d-%m-%Y %H:%i'),
        '%Y-%m'
    )
ORDER BY YearMonth;

# Identify the top categories by total revenue and their share in overall sales.

WITH category_revenue AS (
    SELECT 
        p.Category,
        SUM(t.Quantity * t.`Unit Price`) AS TotalRevenue
    FROM transactions t
    JOIN products p 
        ON CAST(t.`Product ID` AS UNSIGNED) = CAST(p.`Product ID` AS UNSIGNED)
    GROUP BY p.Category
),
total_sales AS (
    SELECT SUM(TotalRevenue) AS OverallRevenue
    FROM category_revenue
)
SELECT 
    c.Category,
    c.TotalRevenue,
    ROUND((c.TotalRevenue / t.OverallRevenue) * 100, 2) AS RevenueSharePercent
FROM category_revenue c
CROSS JOIN total_sales t
ORDER BY c.TotalRevenue DESC;


# Compare total sales volume and average basket value across payment methods.

SELECT 
    `Payment Method`,
     COUNT(DISTINCT `Invoice ID`) AS total_transactions,
    SUM(`Line Total`) AS total_sales_volume,
    ROUND(AVG(`Invoice Total`), 2) AS avg_basket_value
FROM transactions
GROUP BY 
    `Payment Method`
ORDER BY 
    total_sales_volume DESC;
    
# Compare sales volume and revenue during discount periods versus non-discount periods.

SELECT
    CASE 
        WHEN Discount > 0 THEN 'Discount Period'
        ELSE 'Non-Discount Period'
    END AS discount_flag,
    COUNT(DISTINCT `Invoice ID`) AS total_transactions,
    SUM(Quantity) AS total_sales_volume,
    SUM(`Line Total`) AS total_revenue,
    ROUND(AVG(`Invoice Total`), 2) AS avg_basket_value
FROM transactions
GROUP BY discount_flag
ORDER BY total_revenue DESC;

# Measure the proportion of new versus repeat customers each month along with their average spend.

WITH cleaned_transactions AS (
    SELECT
        `Customer ID`,
        `Invoice ID`,
        `Invoice Total`,
        STR_TO_DATE(Date, '%d-%m-%Y %H:%i') AS dt
    FROM transactions
),
first_purchase AS (
    SELECT 
        `Customer ID`,
        MIN(dt) AS first_purchase_date
    FROM cleaned_transactions
    GROUP BY `Customer ID`
),
labeled_customers AS (
    SELECT 
        c.`Customer ID`,
        c.`Invoice ID`,
        c.`Invoice Total`,
        DATE_FORMAT(c.dt, '%Y-%m') AS YearMonth,
        CASE
            WHEN DATE_FORMAT(c.dt, '%Y-%m') = DATE_FORMAT(f.first_purchase_date, '%Y-%m')
                THEN 'New Customer'
            ELSE 'Repeat Customer'
        END AS customer_type
    FROM cleaned_transactions c
    JOIN first_purchase f 
        ON c.`Customer ID` = f.`Customer ID`
)
SELECT 
    YearMonth,
    customer_type,
    COUNT(DISTINCT `Customer ID`) AS customer_count,
    ROUND(AVG(`Invoice Total`), 2) AS avg_spend
FROM labeled_customers
GROUP BY 
    YearMonth,
    customer_type
ORDER BY 
    YearMonth,
    customer_type;


# Identify the top and bottom stores by revenue and return rates.
WITH store_metrics AS (
    SELECT
        stores.`Store ID`, stores.`Store Name`, stores.`City`, stores.`Country`,
        SUM(transactions.`Line Total`) AS Revenue,
        COUNT(DISTINCT transactions.`Invoice ID`) AS `Total Transactions`,
        COUNT(DISTINCT CASE
            WHEN transactions.`Transaction Type` = 'Return'
            THEN transactions.`Invoice ID`
        END) AS `Return Count`,
        ROUND(
            COUNT(DISTINCT CASE
                WHEN transactions.`Transaction Type` = 'Return'
                THEN transactions.`Invoice ID`
            END)
            / COUNT(DISTINCT transactions.`Invoice ID`),
            4
        ) AS `Return Rate`
    FROM stores
    INNER JOIN transactions
        ON stores.`Store ID` = CAST(transactions.`Store ID` AS UNSIGNED)
    GROUP BY
        stores.`Store ID`,
        stores.`Store Name`,
        stores.`City`,
        stores.`Country`
),
ranked AS (
    SELECT
        store_metrics.`Store ID`,
        store_metrics.`Store Name`,
        store_metrics.`City`,
        store_metrics.`Country`,
        store_metrics.Revenue,
        store_metrics.`Return Count`,
        store_metrics.`Total Transactions`,
        store_metrics.`Return Rate`,
        DENSE_RANK() OVER (ORDER BY Revenue DESC) AS rev_rank_desc,
        DENSE_RANK() OVER (ORDER BY Revenue ASC)  AS rev_rank_asc,
        DENSE_RANK() OVER (ORDER BY `Return Rate` DESC) AS ret_rank_desc,
        DENSE_RANK() OVER (ORDER BY `Return Rate` ASC)  AS ret_rank_asc
    FROM store_metrics)
SELECT * FROM (
    SELECT
        'Top Revenue' AS Category,
        `Store ID`, `Store Name`, `City`, `Country`,
        Revenue, `Return Count`, `Total Transactions`, `Return Rate`
    FROM ranked WHERE rev_rank_desc = 1
    UNION ALL
    SELECT
        'Bottom Revenue',
        `Store ID`, `Store Name`, `City`, `Country`,
        Revenue, `Return Count`, `Total Transactions`, `Return Rate`
    FROM ranked WHERE rev_rank_asc = 1
    UNION ALL
    SELECT
        'Top Return Rate',
        `Store ID`, `Store Name`, `City`, `Country`,
        Revenue, `Return Count`, `Total Transactions`, `Return Rate`
    FROM ranked WHERE ret_rank_desc = 1
    UNION ALL
    SELECT
        'Bottom Return Rate',
        `Store ID`, `Store Name`, `City`, `Country`,
        Revenue, `Return Count`, `Total Transactions`, `Return Rate`
    FROM ranked WHERE ret_rank_asc = 1
) final_result
ORDER BY Category;

# Segment products into price bands and analyze their contribution to total revenue and returns.

WITH price_band_metrics AS (
    SELECT 
        CASE
            WHEN t.`Unit Price` < 500 THEN 'Low (<500)'
            WHEN t.`Unit Price` BETWEEN 500 AND 1500 THEN 'Medium (500–1500)'
            WHEN t.`Unit Price` BETWEEN 1501 AND 3000 THEN 'High (1501–3000)'
            ELSE 'Premium (>3000)'
        END AS price_band,

        p.Category,
        p.`Sub Category`,

        COUNT(DISTINCT t.`Product ID`) AS total_products,

        -- Units sold (sales only)
        SUM(
            CASE 
                WHEN t.`Transaction Type` = 'Sale' THEN t.Quantity 
                ELSE 0 
            END
        ) AS units_sold,

        -- Net revenue (sales - returns)
        SUM(
            CASE 
                WHEN t.`Transaction Type` = 'Sale' THEN t.`Line Total`
                WHEN t.`Transaction Type` = 'Return' THEN -t.`Line Total`
                ELSE 0
            END
        ) AS net_revenue,

        -- Returns
        SUM(
            CASE 
                WHEN t.`Transaction Type` = 'Return' THEN t.Quantity 
                ELSE 0 
            END
        ) AS return_units,

        SUM(
            CASE 
                WHEN t.`Transaction Type` = 'Return' THEN t.`Line Total`
                ELSE 0 
            END
        ) AS return_value

    FROM transactions t
    LEFT JOIN products p
        ON t.`Product ID` = p.`Product ID`
    GROUP BY
        price_band,
        p.Category,
        p.`Sub Category`
),

overall_revenue AS (
    SELECT SUM(net_revenue) AS total_revenue
    FROM price_band_metrics
)

SELECT
    pb.price_band,
    pb.Category,
    pb.`Sub Category`,
    pb.total_products,
    pb.units_sold,
    pb.net_revenue,
    pb.return_units,
    pb.return_value,

    -- Return rate
    ROUND(
        pb.return_units / NULLIF(pb.units_sold, 0) * 100,
        2
    ) AS return_rate_percent,

    -- Revenue contribution
    ROUND(
        pb.net_revenue / NULLIF(o.total_revenue, 0) * 100,
        2
    ) AS revenue_contribution_percent

FROM price_band_metrics pb
CROSS JOIN overall_revenue o
ORDER BY
    pb.price_band,
    pb.net_revenue DESC;


# Calculate the average number of items and revenue per basket across different countries.

SELECT 
    c.Country,
    COUNT(DISTINCT t.`Invoice ID`) AS total_baskets,
    ROUND(
        SUM(CASE WHEN t.`Transaction Type` = 'Sale' THEN t.Quantity ELSE 0 END)
        / COUNT(DISTINCT t.`Invoice ID`),
        2
    ) AS avg_items_per_basket,
    ROUND(
        SUM(CASE WHEN t.`Transaction Type` = 'Sale' THEN t.`Line Total` ELSE 0 END)
        / COUNT(DISTINCT t.`Invoice ID`),
        2
    ) AS avg_revenue_per_basket
FROM transactions t
LEFT JOIN customers c 
    ON t.`Customer ID` = c.`Customer ID`
GROUP BY c.Country
ORDER BY avg_revenue_per_basket DESC;

# Analyze month-over-month revenue growth overall and for the top three categories.

WITH 
top_categories AS (
    SELECT 
        p.Category,
        SUM(t.`Line Total`) AS total_revenue
    FROM transactions t
    JOIN products p 
        ON CAST(t.`Product ID` AS UNSIGNED) = CAST(p.`Product ID` AS UNSIGNED)
    GROUP BY p.Category
    ORDER BY total_revenue DESC
    LIMIT 3
),
monthly_data AS (
    SELECT
        DATE_FORMAT(STR_TO_DATE(t.Date, '%d-%m-%Y %H:%i'), '%Y-%m') AS YearMonth,
        p.Category,
        SUM(t.`Line Total`) AS monthly_revenue
    FROM transactions t
    JOIN products p 
        ON CAST(t.`Product ID` AS UNSIGNED) = CAST(p.`Product ID` AS UNSIGNED)
    GROUP BY YearMonth, p.Category
),
mom_calc AS (
    SELECT
        YearMonth,
        Category,
        monthly_revenue,
        LAG(monthly_revenue, 1) OVER (PARTITION BY Category ORDER BY YearMonth) AS prev_month_rev,
        ROUND(
            (monthly_revenue - LAG(monthly_revenue, 1) OVER (PARTITION BY Category ORDER BY YearMonth)) /
            NULLIF(LAG(monthly_revenue, 1) OVER (PARTITION BY Category ORDER BY YearMonth), 0) * 100,
            2
        ) AS mom_growth_percent
    FROM monthly_data
)
SELECT 
    m.*
FROM mom_calc m
WHERE 
    m.Category IN (SELECT Category FROM top_categories)
ORDER BY 
    m.Category, m.YearMonth;



