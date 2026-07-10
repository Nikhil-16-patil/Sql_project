-- ============================================================
-- LAYOFFS DATASET: DATA CLEANING & EXPLORATORY DATA ANALYSIS
-- ============================================================

-- ------------------------------------------------------------
-- 0. INITIAL DATA CHECK
-- ------------------------------------------------------------
SELECT 
    COUNT(*) AS total_rows,
    COUNT(company) AS companies,
    COUNT(total_laid_off) AS has_layoff_number,
    COUNT(percentage_laid_off) AS has_percentage,
    COUNT(funds_raised_millions) AS has_funds
FROM layoffs;

SELECT * FROM layoffs;

-- ------------------------------------------------------------
-- 1. CREATE STAGING TABLE (never work on raw data directly)
-- ------------------------------------------------------------
CREATE TABLE layoffs_staging
LIKE layoffs;

INSERT INTO layoffs_staging
SELECT * FROM layoffs;

SELECT * FROM layoffs_staging;

-- ------------------------------------------------------------
-- 2. IDENTIFY DUPLICATES
-- ------------------------------------------------------------
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY company, location, industry, total_laid_off,
                         percentage_laid_off, `date`, stage, country, funds_raised_millions
        ) AS row_num
    FROM layoffs_staging
) t
WHERE row_num > 1;

-- ------------------------------------------------------------
-- 3. CREATE SECOND STAGING TABLE (with row_num column) AND REMOVE DUPLICATES
-- ------------------------------------------------------------
CREATE TABLE `layoffs_staging2` (
  `company` varchar(100) DEFAULT NULL,
  `location` varchar(100) DEFAULT NULL,
  `industry` varchar(100) DEFAULT NULL,
  `total_laid_off` varchar(20) DEFAULT NULL,
  `percentage_laid_off` varchar(20) DEFAULT NULL,
  `date` varchar(20) DEFAULT NULL,
  `stage` varchar(50) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `funds_raised_millions` varchar(20) DEFAULT NULL,
  `row_num` int
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO layoffs_staging2
SELECT *,
    ROW_NUMBER() OVER (
        PARTITION BY company, location, industry, total_laid_off,
                     percentage_laid_off, `date`, stage, country, funds_raised_millions
    ) AS row_num
FROM layoffs_staging;

-- Safe update mode may need to be disabled for the DELETE below
SET SQL_SAFE_UPDATES = 0;

DELETE FROM layoffs_staging2
WHERE row_num > 1;

-- ------------------------------------------------------------
-- 4. STANDARDIZE DATA
-- ------------------------------------------------------------

-- Trim whitespace
UPDATE layoffs_staging2
SET 
    company = TRIM(company),
    location = TRIM(location),
    industry = TRIM(industry),
    country = TRIM(country);

-- Unify inconsistent industry naming (e.g. 'Crypto', 'CryptoCurrency', 'Crypto Currency' -> 'Crypto')
UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';

-- Unify inconsistent country naming (e.g. 'United States', 'United States.' -> 'United States')
UPDATE layoffs_staging2
SET country = 'United States'
WHERE country LIKE 'United States%';

-- Convert date from text (MM/DD/YYYY) to a proper DATE
UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;

-- ------------------------------------------------------------
-- 5. HANDLE NULL / BLANK VALUES
-- ------------------------------------------------------------

-- Convert blank industry strings to true NULLs
UPDATE layoffs_staging2
SET industry = NULL
WHERE industry = '';

-- Backfill missing industry values using other rows for the same company
UPDATE layoffs_staging2 t1
JOIN layoffs_staging2 t2
    ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
    AND t2.industry IS NOT NULL;

-- Remove rows where both layoff metrics are missing (unusable for analysis)
DELETE FROM layoffs_staging2
WHERE total_laid_off IS NULL
    AND percentage_laid_off IS NULL;

-- Drop the helper column now that duplicates are removed
ALTER TABLE layoffs_staging2
DROP COLUMN row_num;

-- Fix column types now that data is clean
ALTER TABLE layoffs_staging2
MODIFY COLUMN total_laid_off INT;

-- ============================================================
-- EXPLORATORY DATA ANALYSIS
-- ============================================================

-- Overall scale of layoffs
SELECT 
    MAX(CAST(total_laid_off AS UNSIGNED)) AS max_total_laid_off,
    MAX(percentage_laid_off) AS max_percentage_laid_off
FROM layoffs_staging2;

-- Total layoffs by company
SELECT 
    company,
    SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY company
ORDER BY total_laid_off DESC;

-- Total layoffs by industry, with date range
-- (FIX: previously grouped by industry + funds_raised_millions by mistake,
--  which fragmented each industry into many rows. Grouping by industry alone
--  gives one row per industry as intended.)
SELECT 
    industry,
    SUM(total_laid_off) AS total_laid_off,
    MAX(`date`) AS end_date,
    MIN(`date`) AS start_date
FROM layoffs_staging2
GROUP BY industry
ORDER BY total_laid_off DESC;

-- Total layoffs by date
SELECT 
    `date`,
    SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY `date`
ORDER BY 1 DESC;

-- Total layoffs by year
SELECT 
    YEAR(`date`) AS year,
    SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY YEAR(`date`)
ORDER BY 1 DESC;

-- Total layoffs by country and stage
SELECT 
    country,
    stage,
    SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY stage, country
ORDER BY stage;

-- Total layoffs by company stage
SELECT 
    stage,
    SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY stage
ORDER BY total_laid_off DESC;

-- Total layoffs by month
SELECT 
    SUBSTRING(`date`, 1, 7) AS month,
    SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
WHERE `date` IS NOT NULL
GROUP BY month
ORDER BY month;

-- ------------------------------------------------------------
-- ROLLING TOTAL: industry-wide layoffs accumulating over time
-- ------------------------------------------------------------
WITH rolling_total AS (
    SELECT 
        SUBSTRING(`date`, 1, 7) AS month,
        SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY month
)
SELECT 
    month,
    total_laid_off,
    SUM(total_laid_off) OVER (ORDER BY month) AS rolling_total
FROM rolling_total
ORDER BY month;

-- ------------------------------------------------------------
-- ROLLING TOTAL: per-company, per-month, with each company's own running total
-- ------------------------------------------------------------
WITH company_rolling_total AS (
    SELECT 
        company,
        SUBSTRING(`date`, 1, 7) AS month,
        SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY company, month
)
SELECT 
    company,
    month,
    total_laid_off,
    SUM(total_laid_off) OVER (PARTITION BY company ORDER BY month) AS company_rolling_total
FROM company_rolling_total
ORDER BY company, month;

-- ------------------------------------------------------------
-- TOP 5 COMPANIES BY LAYOFFS, PER YEAR
-- ------------------------------------------------------------
WITH company_year AS (
    SELECT 
        company,
        YEAR(`date`) AS years,
        SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    GROUP BY company, years
),
company_year_rank AS (
    SELECT 
        company,
        years,
        total_laid_off,
        DENSE_RANK() OVER (PARTITION BY years ORDER BY total_laid_off DESC) AS ranking
    FROM company_year
)
SELECT 
    company, 
    years, 
    total_laid_off,
    ranking
FROM company_year_rank
WHERE ranking <= 5
    AND years IS NOT NULL
ORDER BY years ASC, total_laid_off DESC;
