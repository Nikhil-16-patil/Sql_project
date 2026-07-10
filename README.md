Layoffs Dataset: SQL Data Cleaning & Exploratory Analysis

A MySQL project that cleans a real-world dataset of global tech layoffs and explores trends across industry, country, company stage, and time.

Dataset

The raw dataset (layoffs) contains layoff events reported across companies worldwide, including:


company, location, industry, country
total_laid_off, percentage_laid_off
date, stage (company funding stage), funds_raised_millions


Source: [add your dataset link here, e.g. Kaggle "Layoffs 2022" dataset]

Process

1. Staging & duplicate removal
Copied raw data into a staging table, then used ROW_NUMBER() partitioned across every column to flag exact duplicate rows, and deleted them.

2. Standardization


Trimmed stray whitespace from text fields
Collapsed inconsistent category names (e.g. Crypto, CryptoCurrency, Crypto Currency → Crypto; United States, United States. → United States)
Converted date from text (MM/DD/YYYY) to a proper DATE type


3. Handling missing data


Converted blank strings to true NULLs
Backfilled missing industry values using a self-join on company (if one row for a company had its industry filled in, that value was used to fill other rows for the same company)
Removed rows with no usable layoff data (total_laid_off and percentage_laid_off both NULL)


4. Type correction
Converted numeric columns stored as varchar (a side effect of the raw import) to proper INT/DATE types, since aggregate functions like MAX() and SUM() behave incorrectly on numbers stored as text (e.g. '99' was treated as "larger" than '12000' under string comparison).

5. Exploratory analysis
Aggregated layoffs by company, industry, country, stage, month, and year. Built rolling-total queries using window functions to track cumulative layoffs over time, both industry-wide and per company, and ranked the top 5 most-affected companies per year using DENSE_RANK().

Key Insights

(Fill these in with your actual results — run the EDA queries in layoffs_analysis.sql and drop the numbers in here. A few examples of the kind of insight to look for:)


[Industry] had the highest total layoffs overall, at [X] employees.
[Year] was the worst year for layoffs, with [X] total reported.
The [stage] funding stage (e.g. Post-IPO / Series C) accounted for the largest share of layoffs, suggesting [your interpretation].
[Company] had the single largest layoff event, cutting [X]% of its workforce in [month/year].


Tech Used


MySQL (window functions, CTEs, self-joins, aggregate functions)
MySQL Workbench


Files


layoffs_analysis.sql — full cleaning + EDA script, ready to run top to bottom on a fresh import of the raw dataset


Possible Next Steps


Export cleaned data to Tableau / Power BI / Excel for a visual dashboard of layoffs over time
Add a Python notebook for statistical analysis or forecasting
