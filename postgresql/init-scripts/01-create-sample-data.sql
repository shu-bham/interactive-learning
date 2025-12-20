-- Create learning_db if it doesn't exist (handled by Docker env but good to have)
-- \c learning_db

-- Users table
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    age INT,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Orders table
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    order_date DATE DEFAULT CURRENT_DATE,
    amount DECIMAL(10, 2),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Page views for analytics
CREATE TABLE page_views (
    view_id BIGSERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    page_url VARCHAR(500),
    view_date DATE DEFAULT CURRENT_DATE,
    view_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    device_type VARCHAR(20)
);

-- Insert sample users
INSERT INTO users (username, email, first_name, last_name, age, status) VALUES
('john_doe', 'john@example.com', 'John', 'Doe', 30, 'active'),
('alice_smith', 'alice@example.com', 'Alice', 'Smith', 28, 'active'),
('bob_wilson', 'bob@example.com', 'Bob', 'Wilson', 35, 'active'),
('charlie_brown', 'charlie@example.com', 'Charlie', 'Brown', 22, 'inactive'),
('david_miller', 'david@example.com', 'David', 'Miller', 40, 'active');

-- Insert sample orders
INSERT INTO orders (user_id, amount, status) VALUES
(1, 150.00, 'completed'),
(1, 45.50, 'completed'),
(2, 200.00, 'pending'),
(3, 10.99, 'completed'),
(5, 500.00, 'processing');

-- Insert sample page views
INSERT INTO page_views (user_id, page_url, device_type) VALUES
(1, '/home', 'desktop'),
(1, '/products', 'desktop'),
(2, '/home', 'mobile'),
(2, '/cart', 'mobile'),
(3, '/home', 'tablet'),
(5, '/checkout', 'desktop');

-- Create an index to demonstrate later
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_page_views_date ON page_views(view_date);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for users table
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
