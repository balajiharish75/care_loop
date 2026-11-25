-- ============================================================================
-- CareLoop Clinics — No-Show Guard
-- Part 2: SQL business analysis (02_queries.sql)
--
-- Dialect: MySQL 8 (SQLite-compatible syntax used where practical)
-- These queries operate on the tables loaded from output/load_data.sql,
-- which is produced by Part 1 (notebook 01_ingest_clean.ipynb).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Task 2.1 — Database creation and loading
-- ----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS noshowguard;
USE noshowguard;

-- Clinics dimension table.
CREATE TABLE IF NOT EXISTS clinics (
    clinic_id   VARCHAR(10) NOT NULL,
    clinic_name VARCHAR(100) NOT NULL,
    city        VARCHAR(100) NOT NULL,
    tier        VARCHAR(20) NOT NULL,
    latitude    DECIMAL(8, 6) NOT NULL,
    longitude   DECIMAL(9, 6) NOT NULL,
    temp_c      DECIMAL(5, 2) NULL,            -- NULL when Open-Meteo unavailable
    PRIMARY KEY (clinic_id)
);

-- Appointments fact table with a foreign key to clinics.
CREATE TABLE IF NOT EXISTS appointments (
    appointment_id  VARCHAR(10) NOT NULL,
    patient_id      VARCHAR(10) NOT NULL,
    clinic_id       VARCHAR(10) NOT NULL,
    booked_on       DATE NOT NULL,
    appt_date       DATE NOT NULL,
    age             INT NOT NULL,
    gender          CHAR(1) NOT NULL,
    distance_km     DECIMAL(5, 2) NOT NULL,
    fee_inr         INT NOT NULL,
    booking_channel VARCHAR(20) NOT NULL,
    visit_type      VARCHAR(20) NOT NULL,
    reminder_sent   CHAR(3) NOT NULL,          -- 'Yes' / 'No'
    prior_no_shows  INT NOT NULL,
    status          VARCHAR(20) NOT NULL,
    lead_days       INT NOT NULL,
    no_show         TINYINT(1) NOT NULL,       -- 1 = No-Show, 0 = Attended
    PRIMARY KEY (appointment_id),
    FOREIGN KEY (clinic_id) REFERENCES clinics(clinic_id)
);

-- Load the data exported by Part 1 (8 clinic INSERTs, then 990 appointment INSERTs).
-- source load_data.sql;

-- Verification counts (run after loading):
SELECT COUNT(*) AS clinic_count FROM clinics;
SELECT COUNT(*) AS appointment_count FROM appointments;
SELECT SUM(no_show) AS no_show_count FROM appointments;

-- Integrity check: attempt inserting a second row with appointment_id 'A0001'.
-- The PRIMARY KEY constraint rejects it. The actual error recorded when this
-- statement was executed in SQLite was:
--   UNIQUE constraint failed: appointments.appointment_id
-- (MySQL reports this class of violation as a "Duplicate entry" error; the exact
-- wording depends on the server version and was not fabricated here.)
-- Statement used for the check:
-- INSERT INTO appointments (appointment_id, patient_id, clinic_id, booked_on,
--   appt_date, age, gender, distance_km, fee_inr, booking_channel, visit_type,
--   reminder_sent, prior_no_shows, status, lead_days, no_show)
-- VALUES ('A0001', 'P509', 'C05', '2025-01-24', '2025-01-25', 60, 'F', 18.0,
--   850, 'Phone', 'Consultation', 'Yes', 1, 'No-Show', 1, 1);


-- ----------------------------------------------------------------------------
-- Task 2.2 — No-show rate by clinic
-- Business question: which clinics have the highest no-show rates, and are the
-- high rates based on enough appointments to be reliable?
-- ----------------------------------------------------------------------------

-- Restricted view: only clinics with at least 95 appointments (filters out
-- small-sample clinics such as Gomti Nagar Care Point, which has 90).
SELECT
    c.clinic_name,
    c.city,
    COUNT(a.appointment_id) AS appointments,
    SUM(a.no_show) AS no_shows,
    ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1) AS no_show_pct
FROM appointments AS a
JOIN clinics AS c ON a.clinic_id = c.clinic_id
GROUP BY c.clinic_id, c.clinic_name, c.city
HAVING COUNT(*) >= 95
ORDER BY no_show_pct DESC;

-- Unrestricted view: all eight clinics, including low-sample-size clinics.
SELECT
    c.clinic_name,
    c.city,
    COUNT(a.appointment_id) AS appointments,
    SUM(a.no_show) AS no_shows,
    ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1) AS no_show_pct
FROM appointments AS a
JOIN clinics AS c ON a.clinic_id = c.clinic_id
GROUP BY c.clinic_id, c.clinic_name, c.city
ORDER BY no_show_pct DESC;


-- ----------------------------------------------------------------------------
-- Task 2.3 — Booking lead-time analysis
-- Business question: does the chance of a no-show change with how far ahead
-- the appointment was booked?
-- Bands: 1-7, 8-14, 15-30, 31+ (inclusive upper limits).
-- Sorted by MIN(lead_days), not alphabetically.
-- ----------------------------------------------------------------------------

SELECT
    CASE
        WHEN lead_days BETWEEN 1 AND 7 THEN '1-7'
        WHEN lead_days BETWEEN 8 AND 14 THEN '8-14'
        WHEN lead_days BETWEEN 15 AND 30 THEN '15-30'
        ELSE '31+'
    END AS lead_band,
    MIN(lead_days) AS min_lead_days,
    COUNT(*) AS appointments,
    SUM(no_show) AS no_shows,
    ROUND(100.0 * SUM(no_show) / COUNT(*), 1) AS no_show_pct
FROM appointments
GROUP BY lead_band
ORDER BY min_lead_days;


-- ----------------------------------------------------------------------------
-- Task 2.4 — Monthly trend
-- Business question: how does the no-show rate evolve month over month?
-- Uses a CTE named monthly and LAG() to compute the percentage-point change
-- from the previous month (January is NULL).
-- ----------------------------------------------------------------------------

WITH monthly AS (
    SELECT
        SUBSTR(appt_date, 1, 7) AS month,
        COUNT(*) AS appointments,
        ROUND(100.0 * SUM(no_show) / COUNT(*), 1) AS no_show_pct
    FROM appointments
    GROUP BY month
)
SELECT
    month,
    appointments,
    no_show_pct,
    ROUND(no_show_pct - LAG(no_show_pct) OVER (ORDER BY month), 1) AS pct_point_change
FROM monthly
ORDER BY month;


-- ----------------------------------------------------------------------------
-- Task 2.5 — Rank clinics inside cities
-- Business question: within each city, how does each clinic's no-show rate
-- rank, and how does it compare to the overall no-show rate?
-- Uses CTE clinic_rates, RANK() partitioned by city, and a scalar subquery
-- for the overall rate.
-- ----------------------------------------------------------------------------

WITH clinic_rates AS (
    SELECT
        c.city,
        c.clinic_name,
        COUNT(a.appointment_id) AS appointments,
        ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1) AS no_show_pct
    FROM appointments AS a
    JOIN clinics AS c ON a.clinic_id = c.clinic_id
    GROUP BY c.city, c.clinic_id, c.clinic_name
),
overall AS (
    SELECT ROUND(100.0 * SUM(no_show) / COUNT(*), 1) AS overall_pct
    FROM appointments
)
SELECT
    cr.city,
    cr.clinic_name,
    cr.appointments,
    cr.no_show_pct,
    o.overall_pct,
    RANK() OVER (PARTITION BY cr.city ORDER BY cr.no_show_pct DESC) AS city_rank,
    CASE
        WHEN cr.no_show_pct > o.overall_pct THEN 'above'
        WHEN cr.no_show_pct < o.overall_pct THEN 'below'
        ELSE 'equal'
    END AS vs_overall
FROM clinic_rates AS cr
CROSS JOIN overall AS o
ORDER BY cr.city, city_rank;
