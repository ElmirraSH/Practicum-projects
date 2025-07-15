* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Шайхутдинова Эльмира
 * Дата: 06.05.2025
Задача 1. Время активности объявлений


WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Категоризируем объявления по времени активности и отфильтруем объявления только по городам :
by_city AS (SELECT
CASE WHEN 
city ='Санкт-Петербург' THEN 'Санкт-Петербург'
ELSE 'ЛенОбл'
END AS city_category,
CASE WHEN days_exposition > 0 AND days_exposition <=30
THEN 'sold_in_month'
WHEN days_exposition> 30 AND days_exposition <= 90
THEN 'sold_in_three_months'
WHEN days_exposition > 90 AND days_exposition <= 180
THEN 'sold_in_six_months'
WHEN days_exposition > 180 
THEN 'sold_in_more_then_six'
END AS act_category,
last_price/total_area AS square,
total_area,
rooms,
balcony,
"floor",
id
FROM real_estate.flats 
JOIN real_estate.city USING (city_id)
JOIN real_estate.TYPE USING (type_id)
JOIN real_estate.advertisement using(id)
WHERE "type"='город')
SELECT 
city_category,
act_category,
round(avg(square)::numeric,2) AS avg_sum_per_square,
round(avg(total_area)::numeric,2) AS avg_total_area,
percentile_disc(0.5) WITHIN GROUP (ORDER BY rooms) AS mediana_rooms,
percentile_disc(0.5) WITHIN GROUP (ORDER BY balcony) AS mediana_balcony ,
percentile_disc(0.5) WITHIN GROUP (ORDER BY "floor") AS mediana_floor,
count(id) AS total_ads
FROM by_city
WHERE id IN (SELECT * FROM filtered_id) AND act_category IS NOT null
GROUP BY city_category, act_category
ORDER BY city_category



Задача 2 Сезонность объявлений

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_l
    FROM real_estate.flats
    JOIN real_estate.advertisement using(id)
),
-- Найдём id объявлений, которые не содержат выбросы по площади и цене:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    JOIN real_estate.type AS t using(type_id)
    JOIN real_estate.advertisement a using(id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND ((a.last_price < (SELECT last_price_limit_h FROM limits) and a.last_price > (SELECT last_price_limit_l FROM limits)) OR a.last_price IS NULL)
        AND "type"='город'
    ),
first_day  AS
(SELECT extract(MONTH from first_day_exposition) AS month_first_day,
round(avg(last_price/total_area)::numeric,2) AS avg_meter_cost,
round(avg(total_area)::NUMERIC,2) AS avg_total_area,
count(id) AS count_ads
FROM real_estate.advertisement a 
JOIN real_estate.flats f using(id)
WHERE days_exposition IS NOT NULL AND first_day_exposition BETWEEN '2015-01-01' AND '2019-01-01' AND id IN (SELECT * FROM filtered_id) 
GROUP BY month_first_day),
last_day AS (SELECT extract(MONTH FROM (first_day_exposition + days_exposition*interval'1day')::date) AS month_last_day,
round(avg(last_price/total_area)::numeric,2) AS avg_meter_cost,
round(avg(total_area)::NUMERIC,2) AS avg_total_area,
count(id) AS count_ads
FROM real_estate.advertisement a 
JOIN real_estate.flats f using(id)
WHERE days_exposition IS NOT NULL AND first_day_exposition BETWEEN '2015-01-01' AND '2019-01-01' AND id IN (SELECT * FROM filtered_id)
GROUP BY month_last_day) 
SELECT 
'публикация' AS TYPE,
*,
RANK () OVER (ORDER BY count_ads desc) AS month_rank
FROM first_day
UNION ALL
SELECT 'cнятие' AS TYPE,
*,
RANK () OVER (ORDER BY count_ads desc) AS month_rank
FROM last_day

Задача 3: Анализ рынка недвижимости Ленобласти


При расчете показателей количества объявлений по населенным пунктам, получила большой разброс и разницу более, чем в 5 раз между медианой и средним.
Значит выборка смещена в сторону больших значений. 

WITH request AS (SELECT DISTINCT c.city,
count(id) OVER(PARTITION BY city) AS amount_ids
FROM real_estate.flats
JOIN real_estate.city c using(city_id) 
WHERE city!='Санкт-Петербург')
SELECT min(amount_ids),
max(amount_ids),
avg(amount_ids),
percentile_disc(0.5) WITHIN group(ORDER BY amount_ids) AS mediana,
percentile_disc(0.99) WITHIN group(ORDER BY amount_ids) AS perc_up,
percentile_disc(0.01) WITHIN group(ORDER BY amount_ids) AS perc_down
FROM request


Cделаю отбор топ15 по количеству объявлений.
  
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_l
    FROM real_estate.flats
    JOIN real_estate.advertisement using(id)
),
-- Найдём id объявлений, которые не содержат выбросы по площади и цене:
filtered_id AS(
    SELECT id
    FROM real_estate.flats f
    JOIN real_estate.advertisement a using(id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND ((a.last_price < (SELECT last_price_limit_h FROM limits) and a.last_price > (SELECT last_price_limit_l FROM limits)) OR a.last_price IS NULL)
       ),
request as( SELECT DISTINCT c.city,
count(id) OVER(PARTITION BY city) AS amount_ids
FROM real_estate.flats
JOIN real_estate.city c using(city_id) 
WHERE city!='Санкт-Петербург' AND id IN (SELECT * FROM filtered_id)),
--Подзапрос ранжирующий населенные пункты по кол-ву объявлений
city_rank AS (SELECT *,
DENSE_RANK () OVER (ORDER BY amount_ids desc ) AS city_rank
FROM request 
LIMIT 15)
-- Основной запрос с отбором топ15 городов по кол-ву объявлени
SELECT city, count(id) AS amount_ids, 
round((count(id) FILTER (WHERE days_exposition IS NOT null))/(count(id)::NUMERIC),2) AS selled_share,
round(avg(last_price/total_area)::NUMERIC,2) AS avg_cost_per_square_meter,
round(avg(total_area)::NUMERIC,2) AS avg_total_area, 
round(count(id) FILTER (WHERE days_exposition <30)/count(id) FILTER (WHERE days_exposition IS NOT NULL)::NUMERIC,2) AS share_of_selled_in_month,
round(count(id) FILTER (WHERE days_exposition >=30 AND days_exposition<90)/count(id) FILTER (WHERE days_exposition IS NOT NULL)::NUMERIC,2) AS share_of_selled_in_three_month,
round(count(id) FILTER (WHERE days_exposition >=90 AND days_exposition<180)/count(id) FILTER (WHERE days_exposition IS NOT NULL)::NUMERIC,2) AS share_of_selled_in_six_month,
round(count(id) FILTER (WHERE days_exposition >=180)/count(id) FILTER (WHERE days_exposition IS NOT NULL)::NUMERIC,2) AS share_of_selled_in_morethansix
FROM real_estate.flats f 
JOIN real_estate.advertisement a using(id)
JOIN real_estate.city c using(city_id)
WHERE city IN (SELECT city FROM city_rank WHERE city_rank <=15) AND id IN (SELECT * FROM filtered_id)
GROUP BY city
ORDER BY selled_share DESC, amount_ids Desc








