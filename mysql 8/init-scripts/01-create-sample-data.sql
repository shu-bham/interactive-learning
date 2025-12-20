-- Sample database initialization for MySQL internals learning
-- This creates realistic data for exploring query optimization, indexing, and performance

USE learning_db;

-- Create a users table with various index types
CREATE TABLE users (
    user_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    status ENUM('active', 'inactive', 'suspended') DEFAULT 'active',
    age TINYINT UNSIGNED,
    country_code CHAR(2),
    INDEX idx_email (email),
    INDEX idx_status_created (status, created_at),
    INDEX idx_name (last_name, first_name),
    INDEX idx_country (country_code)
) ENGINE=InnoDB;

-- Create orders table for join and transaction analysis
CREATE TABLE orders (
    order_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2) NOT NULL,
    status ENUM('pending', 'processing', 'shipped', 'delivered', 'cancelled') DEFAULT 'pending',
    shipping_country CHAR(2),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    INDEX idx_user_date (user_id, order_date),
    INDEX idx_status (status),
    INDEX idx_order_date (order_date)
) ENGINE=InnoDB;

-- Create order_items for complex queries
CREATE TABLE order_items (
    item_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    product_id INT UNSIGNED NOT NULL,
    quantity SMALLINT UNSIGNED NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    INDEX idx_order (order_id),
    INDEX idx_product (product_id)
) ENGINE=InnoDB;

-- Create products table
CREATE TABLE products (
    product_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(200) NOT NULL,
    category VARCHAR(50),
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT UNSIGNED DEFAULT 0,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_price (price),
    FULLTEXT idx_description (description, product_name)
) ENGINE=InnoDB;

-- Create a table for partitioning experiments
CREATE TABLE user_activity_log (
    log_id BIGINT UNSIGNED AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    activity_type VARCHAR(50),
    activity_date DATE NOT NULL,
    details JSON,
    PRIMARY KEY (log_id, activity_date),
    INDEX idx_user_activity (user_id, activity_date)
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(activity_date)) (
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Insert sample users
INSERT INTO users (username, email, first_name, last_name, age, country_code, status) VALUES
('jdoe', 'john.doe@example.com', 'John', 'Doe', 30, 'US', 'active'),
('asmith', 'alice.smith@example.com', 'Alice', 'Smith', 28, 'UK', 'active'),
('bjones', 'bob.jones@example.com', 'Bob', 'Jones', 35, 'CA', 'active'),
('cwhite', 'carol.white@example.com', 'Carol', 'White', 42, 'AU', 'inactive'),
('dblack', 'david.black@example.com', 'David', 'Black', 25, 'US', 'active'),
('ebrown', 'emma.brown@example.com', 'Emma', 'Brown', 31, 'UK', 'suspended'),
('fgreen', 'frank.green@example.com', 'Frank', 'Green', 38, 'CA', 'active'),
('gwilson', 'grace.wilson@example.com', 'Grace', 'Wilson', 29, 'US', 'active'),
('hmoore', 'henry.moore@example.com', 'Henry', 'Moore', 45, 'AU', 'active'),
('itaylor', 'iris.taylor@example.com', 'Iris', 'Taylor', 27, 'UK', 'active');

-- Insert sample products
INSERT INTO products (product_name, category, price, stock_quantity, description) VALUES
('Laptop Pro 15', 'Electronics', 1299.99, 50, 'High-performance laptop with 16GB RAM and 512GB SSD'),
('Wireless Mouse', 'Electronics', 29.99, 200, 'Ergonomic wireless mouse with precision tracking'),
('Office Chair', 'Furniture', 249.99, 30, 'Comfortable ergonomic office chair with lumbar support'),
('Standing Desk', 'Furniture', 499.99, 15, 'Adjustable height standing desk for better posture'),
('USB-C Hub', 'Electronics', 49.99, 100, 'Multi-port USB-C hub with HDMI and ethernet'),
('Notebook Set', 'Stationery', 12.99, 500, 'Premium quality notebook set for professionals'),
('Mechanical Keyboard', 'Electronics', 149.99, 75, 'RGB mechanical keyboard with cherry MX switches'),
('Monitor 27"', 'Electronics', 349.99, 40, '4K UHD monitor with HDR support'),
('Desk Lamp', 'Furniture', 39.99, 120, 'LED desk lamp with adjustable brightness'),
('Webcam HD', 'Electronics', 79.99, 60, '1080p HD webcam with built-in microphone');

-- Insert sample orders
INSERT INTO orders (user_id, total_amount, status, shipping_country) VALUES
(1, 1329.98, 'delivered', 'US'),
(2, 249.99, 'shipped', 'UK'),
(3, 499.99, 'processing', 'CA'),
(1, 79.99, 'delivered', 'US'),
(4, 549.98, 'cancelled', 'AU'),
(5, 1299.99, 'delivered', 'US'),
(6, 29.99, 'pending', 'UK'),
(7, 199.98, 'shipped', 'CA'),
(8, 349.99, 'delivered', 'US'),
(9, 89.98, 'processing', 'AU');

-- Insert sample order items
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 1299.99),
(1, 2, 1, 29.99),
(2, 3, 1, 249.99),
(3, 4, 1, 499.99),
(4, 10, 1, 79.99),
(5, 1, 1, 1299.99),
(5, 3, 1, 249.99),
(6, 2, 1, 29.99),
(7, 7, 1, 149.99),
(7, 5, 1, 49.99),
(8, 8, 1, 349.99),
(9, 9, 1, 39.99),
(9, 5, 1, 49.99);

-- Insert sample activity logs
INSERT INTO user_activity_log (user_id, activity_type, activity_date, details) VALUES
(1, 'login', '2024-01-15', '{"ip": "192.168.1.1", "device": "Chrome/Mac"}'),
(1, 'purchase', '2024-02-20', '{"order_id": 1, "amount": 1329.98}'),
(2, 'login', '2024-03-10', '{"ip": "10.0.0.5", "device": "Firefox/Windows"}'),
(3, 'login', '2024-04-05', '{"ip": "172.16.0.10", "device": "Safari/Mac"}'),
(1, 'login', '2024-05-12', '{"ip": "192.168.1.1", "device": "Chrome/Mac"}'),
(4, 'purchase', '2024-06-18', '{"order_id": 5, "amount": 549.98}'),
(5, 'login', '2024-07-22', '{"ip": "192.168.2.50", "device": "Edge/Windows"}'),
(6, 'login', '2024-08-30', '{"ip": "10.1.1.1", "device": "Chrome/Linux"}'),
(7, 'purchase', '2024-09-14', '{"order_id": 8, "amount": 199.98}'),
(8, 'login', '2024-10-25', '{"ip": "192.168.3.100", "device": "Safari/iOS"}');

-- Create a stored procedure for testing
DELIMITER //
CREATE PROCEDURE GetUserOrders(IN p_user_id BIGINT)
BEGIN
    SELECT 
        o.order_id,
        o.order_date,
        o.total_amount,
        o.status,
        COUNT(oi.item_id) as item_count
    FROM orders o
    LEFT JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.user_id = p_user_id
    GROUP BY o.order_id, o.order_date, o.total_amount, o.status
    ORDER BY o.order_date DESC;
END //
DELIMITER ;

-- Create a view for complex query analysis
CREATE VIEW user_order_summary AS
SELECT 
    u.user_id,
    u.username,
    u.email,
    COUNT(DISTINCT o.order_id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_spent,
    MAX(o.order_date) as last_order_date
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.username, u.email;
