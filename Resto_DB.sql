
-- ==========================================
-- PL/SQL Capstone Project: Small Restaurant Order Management System
-- Student: Christian Gwiza
-- Academic Year: 2024–2025
-- ==========================================

-- PHASE I: Entities and Tables
CREATE TABLE customers (
    customer_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(50) NOT NULL,
    phone VARCHAR2(15) UNIQUE,
    email VARCHAR2(100),
    join_date DATE DEFAULT SYSDATE
);

CREATE TABLE employees (
    employee_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(50) NOT NULL,
    position VARCHAR2(20) NOT NULL,
    hire_date DATE DEFAULT SYSDATE,
    active CHAR(1) DEFAULT 'Y' CHECK (active IN ('Y','N'))
);

CREATE TABLE menu (
    item_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(100) NOT NULL,
    price NUMBER(6,2) NOT NULL CHECK (price > 0),
    category VARCHAR2(50) NOT NULL,
    available CHAR(1) DEFAULT 'Y' CHECK (available IN ('Y','N')),
    created_at DATE DEFAULT SYSDATE
);

CREATE TABLE orders (
    order_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id NUMBER NOT NULL,
    employee_id NUMBER NOT NULL,
    order_time TIMESTAMP DEFAULT SYSTIMESTAMP,
    status VARCHAR2(20) DEFAULT 'RECEIVED',
    total_amount NUMBER(8,2) DEFAULT 0,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);

CREATE TABLE order_items (
    order_item_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id NUMBER NOT NULL,
    item_id NUMBER NOT NULL,
    quantity NUMBER NOT NULL CHECK (quantity > 0),
    unit_price NUMBER(6,2) NOT NULL,
    CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_menu_item FOREIGN KEY (item_id) REFERENCES menu(item_id)
);

CREATE TABLE inventory (
    inventory_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id NUMBER NOT NULL UNIQUE,
    current_stock NUMBER DEFAULT 0 CHECK (current_stock >= 0),
    reorder_level NUMBER DEFAULT 5,
    last_update DATE DEFAULT SYSDATE,
    CONSTRAINT fk_menu_item_inv FOREIGN KEY (item_id) REFERENCES menu(item_id)
);

CREATE TABLE holidays (
    holiday_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    holiday_name VARCHAR2(100) NOT NULL,
    holiday_date DATE NOT NULL,
    is_recurring CHAR(1) DEFAULT 'N' CHECK (is_recurring IN ('Y','N'))
);

CREATE TABLE audit_log (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id VARCHAR2(50) NOT NULL,
    action_time TIMESTAMP DEFAULT SYSTIMESTAMP,
    table_name VARCHAR2(50) NOT NULL,
    operation VARCHAR2(10) NOT NULL,
    record_id NUMBER,
    status VARCHAR2(10) NOT NULL,
    comments VARCHAR2(200)
);

-- Sample Data Inserts
INSERT INTO customers (name, phone, email) VALUES ('John Doe', '+250788123456', 'john@example.com');
INSERT INTO customers (name, phone) VALUES ('Alice Smith', '+250788654321');
INSERT INTO customers (name, phone, email) VALUES ('Bob Johnson', '+250788111222', 'bob@example.com');

INSERT INTO employees (name, position) VALUES ('Emma Watson', 'Waiter');
INSERT INTO employees (name, position) VALUES ('James Brown', 'Chef');
INSERT INTO employees (name, position) VALUES ('Sarah Connor', 'Manager');

INSERT INTO menu (name, price, category) VALUES ('Cheeseburger', 8.99, 'Main Course');
INSERT INTO menu (name, price, category) VALUES ('French Fries', 3.99, 'Side Dish');
INSERT INTO menu (name, price, category) VALUES ('Chicken Salad', 7.50, 'Main Course');
INSERT INTO menu (name, price, category) VALUES ('Ice Cream', 4.50, 'Dessert');

INSERT INTO inventory (item_id, current_stock, reorder_level) VALUES (1, 50, 10);
INSERT INTO inventory (item_id, current_stock, reorder_level) VALUES (2, 200, 50);
INSERT INTO inventory (item_id, current_stock, reorder_level) VALUES (3, 30, 15);
INSERT INTO inventory (item_id, current_stock, reorder_level) VALUES (4, 40, 20);

-- View
CREATE OR REPLACE VIEW order_details AS
SELECT 
    o.order_id,
    o.order_time,
    c.name AS customer_name,
    e.name AS employee_name,
    o.status,
    o.total_amount,
    COUNT(oi.order_item_id) AS item_count
FROM 
    orders o
JOIN 
    customers c ON o.customer_id = c.customer_id
JOIN 
    employees e ON o.employee_id = e.employee_id
LEFT JOIN 
    order_items oi ON o.order_id = oi.order_id
GROUP BY 
    o.order_id, o.order_time, c.name, e.name, o.status, o.total_amount;

-- Trigger: Stock Alert
CREATE OR REPLACE TRIGGER trigger_stock_alert
AFTER UPDATE OF current_stock ON inventory
FOR EACH ROW
WHEN (NEW.current_stock < NEW.reorder_level)
BEGIN
    DBMS_OUTPUT.PUT_LINE('⚠️ Low stock alert: Item ID ' || :NEW.item_id ||
                         ' now has only ' || :NEW.current_stock || 
                         ' units (Reorder level: ' || :NEW.reorder_level || ').');
END;
/

-- Package: inventory_pkg
CREATE OR REPLACE PACKAGE inventory_pkg IS
    FUNCTION get_stock_level(p_item_id IN NUMBER) RETURN NUMBER;
    PROCEDURE add_order_item(p_order_id IN NUMBER, p_item_id IN NUMBER, p_quantity IN NUMBER);
END inventory_pkg;
/

CREATE OR REPLACE PACKAGE BODY inventory_pkg IS
    FUNCTION get_stock_level(p_item_id IN NUMBER) RETURN NUMBER IS
        v_stock_level NUMBER;
    BEGIN
        SELECT current_stock INTO v_stock_level
        FROM inventory
        WHERE item_id = p_item_id;
        RETURN v_stock_level;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN -1;
        WHEN OTHERS THEN RETURN -999;
    END get_stock_level;

    PROCEDURE add_order_item(p_order_id IN NUMBER, p_item_id IN NUMBER, p_quantity IN NUMBER) IS
        v_stock NUMBER;
        v_price NUMBER;
    BEGIN
        v_stock := inventory_pkg.get_stock_level(p_item_id);
        IF v_stock < p_quantity THEN
            RAISE_APPLICATION_ERROR(-20001, 'Not enough stock to fulfill the order.');
        END IF;

        SELECT price INTO v_price FROM menu WHERE item_id = p_item_id;

        INSERT INTO order_items (order_id, item_id, quantity, unit_price)
        VALUES (p_order_id, p_item_id, p_quantity, v_price);

        UPDATE inventory
        SET current_stock = current_stock - p_quantity
        WHERE item_id = p_item_id;

        UPDATE orders
        SET total_amount = (
            SELECT SUM(quantity * unit_price)
            FROM order_items
            WHERE order_id = p_order_id
        )
        WHERE order_id = p_order_id;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error in add_order_item: ' || SQLERRM);
            RAISE;
    END add_order_item;
END inventory_pkg;
/

-- Trigger: Audit for Orders
CREATE OR REPLACE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
DECLARE
    v_status VARCHAR2(10) := 'ALLOWED';
    v_operation VARCHAR2(10);
    v_record_id NUMBER;
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        v_record_id := :NEW.order_id;
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        v_record_id := :NEW.order_id;
    ELSIF DELETING THEN
        v_operation := 'DELETE';
        v_record_id := :OLD.order_id;
    END IF;

    INSERT INTO audit_log (user_id, action_time, table_name, operation, record_id, status)
    VALUES (USER, SYSTIMESTAMP, 'ORDERS', v_operation, v_record_id, v_status);
END;
/

-- Trigger: Weekday and Holiday Blocker
CREATE OR REPLACE TRIGGER trg_block_weekday_holiday_dml
BEFORE INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
DECLARE
    v_today DATE := TRUNC(SYSDATE);
    v_day VARCHAR2(15);
    v_holiday_count NUMBER;
BEGIN
    v_day := RTRIM(TO_CHAR(v_today, 'DAY', 'NLS_DATE_LANGUAGE=ENGLISH'));

    IF v_day IN ('MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY') THEN
        RAISE_APPLICATION_ERROR(-20001, '🔒 DML blocked: Not allowed on weekdays.');
    END IF;

    SELECT COUNT(*) INTO v_holiday_count
    FROM holidays
    WHERE holiday_date = v_today
      AND holiday_date BETWEEN v_today AND ADD_MONTHS(v_today, 1);

    IF v_holiday_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20002, '🔒 DML blocked: Not allowed on public holidays.');
    END IF;
END;
/


