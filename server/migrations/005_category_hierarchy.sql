ALTER TABLE accounts
ADD COLUMN IF NOT EXISTS parent_account_id TEXT;

CREATE INDEX IF NOT EXISTS idx_accounts_parent_account_id
ON accounts (parent_account_id);

WITH defaults(key, name, account_type, parent_key) AS (
    VALUES
        ('acc_food', 'Food', 'expense', NULL),
        ('acc_food_meals', 'Meals', 'expense', 'acc_food'),
        ('acc_food_drinks', 'Drinks & Snacks', 'expense', 'acc_food'),
        ('acc_transport', 'Transport', 'expense', NULL),
        ('acc_transport_public', 'Public Transport', 'expense', 'acc_transport'),
        ('acc_transport_taxi', 'Taxi', 'expense', 'acc_transport'),
        ('acc_transport_car', 'Car Expenses', 'expense', 'acc_transport'),
        ('acc_shopping', 'Shopping', 'expense', NULL),
        ('acc_shopping_daily', 'Daily Essentials', 'expense', 'acc_shopping'),
        ('acc_shopping_clothing', 'Clothing', 'expense', 'acc_shopping'),
        ('acc_shopping_digital', 'Electronics', 'expense', 'acc_shopping'),
        ('acc_housing', 'Housing', 'expense', NULL),
        ('acc_housing_rent', 'Rent & Mortgage', 'expense', 'acc_housing'),
        ('acc_housing_utilities', 'Utilities', 'expense', 'acc_housing'),
        ('acc_housing_property', 'Property Services', 'expense', 'acc_housing'),
        ('acc_leisure', 'Leisure', 'expense', NULL),
        ('acc_leisure_entertainment', 'Entertainment', 'expense', 'acc_leisure'),
        ('acc_leisure_fitness', 'Fitness', 'expense', 'acc_leisure'),
        ('acc_leisure_travel', 'Travel', 'expense', 'acc_leisure'),
        ('acc_healthcare', 'Healthcare', 'expense', NULL),
        ('acc_healthcare_medical', 'Medical Care', 'expense', 'acc_healthcare'),
        ('acc_healthcare_medicine', 'Medicine', 'expense', 'acc_healthcare'),
        ('acc_education', 'Education', 'expense', NULL),
        ('acc_education_books', 'Books', 'expense', 'acc_education'),
        ('acc_education_courses', 'Courses', 'expense', 'acc_education'),
        ('acc_other_expense', 'Other Expense', 'expense', NULL),
        ('acc_salary', 'Salary', 'income', NULL),
        ('acc_salary_base', 'Base Salary', 'income', 'acc_salary'),
        ('acc_salary_bonus', 'Bonus', 'income', 'acc_salary'),
        ('acc_side_income', 'Side Income', 'income', NULL),
        ('acc_side_income_freelance', 'Freelance', 'income', 'acc_side_income'),
        ('acc_side_income_business', 'Business Income', 'income', 'acc_side_income'),
        ('acc_investment_income', 'Investment Income', 'income', NULL),
        ('acc_investment_income_interest', 'Interest', 'income', 'acc_investment_income'),
        ('acc_investment_income_dividends', 'Dividends', 'income', 'acc_investment_income'),
        ('acc_other_income', 'Other Income', 'income', NULL)
), inserted AS (
    INSERT INTO accounts (
        id, book_id, name, account_type, currency_code,
        parent_account_id, version
    )
    SELECT
        b.id || ':' || d.key,
        b.id,
        d.name,
        d.account_type,
        'CNY',
        CASE
            WHEN d.parent_key IS NULL THEN NULL
            ELSE b.id || ':' || d.parent_key
        END,
        1
    FROM books b
    CROSS JOIN defaults d
    ON CONFLICT (id) DO NOTHING
    RETURNING id, book_id, name, account_type, currency_code,
              parent_account_id, version
)
INSERT INTO sync_changes (
    book_id, commit_id, entity_type, entity_id,
    operation, entity_version, payload
)
SELECT
    book_id,
    'category-defaults-v2:' || book_id,
    'account',
    id,
    'upsert',
    version,
    jsonb_build_object(
        'name', name,
        'accountType', account_type,
        'currency', currency_code,
        'parentAccountId', parent_account_id
    )
FROM inserted;
