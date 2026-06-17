--Question1 

/*
Which employees handled more orders in the first half of their career 
(measured by their earliest to latest order date) than in the second half 
— and by how much?
*/

CREATE OR REPLACE FUNCTION sp_FirstOrder(
    p_EMPLOYEEID int
)
RETURNS TIMESTAMP
LANGUAGE plpgsql
AS $$
DECLARE 
    v_first_order_date TIMESTAMP;
BEGIN
    SELECT min(o.orderdate) INTO v_first_order_date
    FROM orders o
    JOIN Employees e
    ON o.employeeid = e.employeeid
    where e.employeeid = p_EMPLOYEEID;

    RETURN v_first_order_date;
END;
$$;

CREATE OR REPLACE FUNCTION sp_LastOrder(
    p_EMPLOYEEID int
)
RETURNS TIMESTAMP
LANGUAGE plpgsql
AS $$
DECLARE
    v_first_order_date TIMESTAMP;
BEGIN
    SELECT max(o.orderdate) INTO v_first_order_date
    FROM orders o
    JOIN Employees e
    ON o.employeeid = e.employeeid
    where e.employeeid = p_EMPLOYEEID;

    RETURN v_first_order_date;
END;
$$;

CREATE OR REPLACE FUNCTION sp_MidpointCareer(
    p_Start TIMESTAMP,
    p_END TIMESTAMP
)
RETURNS TIMESTAMP
LANGUAGE plpgsql
AS $$
DECLARE 
    midpoint TIMESTAMP;
BEGIN
    
    midpoint :=p_Start + ((p_End - p_Start)/2);

    RETURN midpoint;
END;
$$;

CREATE OR REPLACE FUNCTION sp_ordersInFirstHalf(
    p_Employee int,
    p_midpoint TIMESTAMP
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE 
    number_of_orders INT;
BEGIN
    SELECT Count(o.orderid) INTO number_of_orders
    FROM orders o 
    JOIN employees e
    ON o.employeeid = e.employeeid
    AND e.employeeid = p_Employee
    where o.orderdate < p_midpoint
    Group by p_employee;

    RETURN number_of_orders;
END;
$$;

CREATE OR REPLACE FUNCTION sp_ordersInSecondHalf(
    p_Employee int,
    p_midpoint TIMESTAMP
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE 
    number_of_orders INT;
BEGIN
    SELECT Count(o.orderid) INTO number_of_orders
    FROM orders o 
    JOIN employees e
    ON o.employeeid = e.employeeid
    AND e.employeeid = p_Employee
    where o.orderdate > p_midpoint
    Group by p_employee;

    RETURN number_of_orders;
END;
$$;

-- WIRING ALL THE FUNCTIONS TOGETHER

SELECT * 
FROM Employees e
where (
    SELECT sp_OrdersinFirstHalf(
                                e.employeeid,
                                sp_midpointCareer(
                                                    sp_FirstOrder(e.employeeid),
                                                    sp_LastOrder(e.employeeid)
                                                   )
                                )
) 
<
(
    SELECT sp_OrdersinSecondHalf(
                                e.employeeid,
                                sp_midpointCareer(
                                                    sp_FirstOrder(e.employeeid),
                                                    sp_LastOrder(e.employeeid)
                                                    )
                                )
);

/*
Tells you which employees started strong but slowed down over time. 
Useful for spotting burnout or disengagement patterns.
*/

--Question 2

/*
For each category, what percentage of total category revenue comes 
from the single most dominant supplier — and which categories are 
"at risk" (over 60% from one supplier)?
*/

SELECT 
        x.categoryid,
        x.supplierid,
        x.supplier_revenue,
        ROUND((x.supplier_revenue/x.category_total)*100,2)  as Percentage_Revenue_Contribution_To_Total,
        CASE WHEN (x.supplier_revenue/x.category_total) > 0.6 then 'RISK'
            ELSE 'EASY PEASY' END AS Risk_flag
FROM (
    SELECT 
            p.categoryid,
            p.supplierid,
            sum(od.quantity*p.price)  as supplier_revenue,
            sum(sum(od.quantity*p.price)) over (partition by p.categoryid) as category_total,
            rank() over(partition by p.categoryid order by sum(od.quantity*p.price) desc) as rnk
    FROM products p 
    JOIN ORDERDETAILS od
    ON od.productid = p.productid
    GROUP BY p.categoryid,p.supplierid
    
) x
Where x.rnk < 2

/*
Tells you which product categories are dangerously dependent on a single supplier. 
If that supplier disappears, that whole category is in trouble.
*/

--Question 3

/*
For each customer who has placed at least 3 orders, 
is the time between their orders getting shorter or longer 
— i.e., are they ordering more frequently over time or drifting away?
*/
select 
        x.customerid,
        CASE WHEN avg(x.early_gap) > avg(x.late_gap) THEN 'ORDERING MORE FREQUENTLY OVER TIME'
        ELSE 'DRIFTING AWAY :/' END AS CUSTOMER_ORDER_TREND_STATUS
from
(
    select 
            y.customerid,
            y.rn,
            y.total,
            y.gap_days,
            case when y.rn <= y.total/2 then y.gap_days end as early_gap,
            case when y.rn >  y.total/2 then y.gap_days end as late_gap
    from
    (
        select 
                ee.customerid,
                oo.orderdate,
                lead(oo.orderdate) over(partition by ee.customerid order by oo.orderdate) - oo.orderdate as gap_days,
                row_number() over(partition by ee.customerid order by oo.orderdate) as rn,
                count(*) over(partition by ee.customerid) as total
        from customers ee
        join orders oo
        on ee.customerid = oo.customerid
        where ee.customerid in (
            select 
                    e.customerid
            from customers e
            join orders o
            on e.customerid = o.customerid
            group by e.customerid
            having count(o.orderid) > 2
        )
    )y
)x
group by x.customerid

/*
Tells you which customers are warming up vs cooling off. 
The ones drifting away are your churn risk, reach out to them.
*/

--Question 4
/*
Find products that are neither in the top 25% nor the bottom
25% of total quantity sold, but whose price is in the top 25%
— products that are expensive but selling at a mediocre volume.
*/
with percentiles
as
(
    select 
            p.productid,
            productname,
            price,
            sum(quantity) as total_quanity,
            ntile(100) over(order by sum(quantity)) as quantity_percentile,
            ntile(100) over(order by price) as price_percentile
    from products p
    join orderdetails od
    On p.productid = od.productid
    group by p.productid,p.productname,price
)

select 
        productid,
        productname,
        price,
        total_quanity,
        price_percentile,
        quantity_percentile
From 
        percentiles 
where
        price_percentile > 75
and
        quantity_percentile < 75
and 
        quantity_percentile > 25

/*
Tells you which expensive products aren't selling well enough to justify their price. 
Either the price needs to drop or the marketing needs work.
*/

--Question5
/*
How many orders did each employee handle per month, and how many of those were shipped vs not shipped?
*/

select 
        ee.firstname || ' ' || ee.lastname as employee_name,
        date_trunc('month', oo.orderdate) as month,
        count(*) as total_orders,
        count(*) filter(where ss.shippername is not null) as shipped,
        count(*) filter(where ss.shippername is null) as not_shipped
from employees ee
join orders oo
on ee.employeeid = oo.employeeid
left join shippers ss
on ss.shipperid = oo.shipperid
group by ee.employeeid, ee.firstname, ee.lastname, date_trunc('month', oo.orderdate)
order by month, employee_name

/*
Tells you each employee's monthly workload and how reliably orders are actually getting shipped.
 A high "not shipped" count on a specific employee or month is worth investigating.
*/