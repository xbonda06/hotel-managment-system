-- Name:
-- IDS Project 2023/24
-- Hotel

-- Authors:
-- Dmitrii Adamovich (xadamo04)
-- Andrii Bondarenko (xbonda06)


----------------------------------------DROP TRIGGERS-----------------------------------------------------

DROP TRIGGER client_status_control;
DROP TRIGGER room_availability_on_reservation_change_true;

----------------------------------------DROP TABLES----------------------------------------------------------
DROP TABLE Reservation_Room;
DROP TABLE Reservation;
DROP TABLE Service_Personnel;
DROP TABLE Service_Customer;
DROP TABLE Service;
DROP TABLE Payment;
DROP TABLE Room;
DROP TABLE Room_type;
DROP TABLE Personnel;
DROP TABLE Customer;
DROP TABLE Person;



---------------------------------------CREATE PERSON TABLES--------------------------------------------------

-- In our realization, we decided to use the following method of generalization/specification
-- Person has unique primary key, which generates, as we add new person
-- Than this primary key is used manually, when we add new customer or personnel
-- In this realization one person can be both customer and personnel

CREATE TABLE Person (
    person_id INT GENERATED AS IDENTITY NOT NULL PRIMARY KEY,
    name VARCHAR2(20) NOT NULL,
    surname VARCHAR2(30) NOT NULL,
    contact_Number NCHAR(13) NOT NULL
                      CHECK (REGEXP_LIKE(contact_Number, '^\+[0-9]{12}$')),
    age INT NOT NULL
                      CHECK(age >= 18),
    gender VARCHAR2(8) NOT NULL
                      CHECK (gender IN ('male', 'female', 'another')),
    date_of_birth DATE NOT NULL
);

CREATE TABLE Customer (
    -- customer takes the person`s id, so customer and person would have the same primary key
    customer_id INT PRIMARY KEY REFERENCES Person (person_id),
    pas_number INT NOT NULL
            CHECK (REGEXP_LIKE(pas_number, '^[0-9]{9}$')),
    status VARCHAR(10) DEFAULT 'Basic'
            CHECK (status IN ('VIP', 'Basic', 'Regular') ),
    citizenship CHAR(2) NOT NULL
            CHECK ( REGEXP_LIKE(citizenship, '^[a-zA-Z]{2}$'))
);


CREATE TABLE Personnel (
    -- personnel takes the person`s id, so customer and person would have the same primary key
    personnel_id INT PRIMARY KEY REFERENCES Person (person_id),
    job_title VARCHAR2(20) NOT NULL
        CHECK ( job_title IN ('Receptionist', 'Cleaner', 'Cook', 'Guard', 'Bellboy') ),
    access_level VARCHAR2(20) DEFAULT 'LOW'
        CHECK ( access_level IN ('LOW', 'MEDIUM', 'HIGH') )
);

---------------------------------------------ROOM TABLES----------------------------------------------

CREATE TABLE Room_type (
    type_id INT GENERATED AS IDENTITY NOT NULL PRIMARY KEY,
    name VARCHAR2(20) NOT NULL,
    capacity INT NOT NULL,
    pet_friendly SMALLINT DEFAULT 0 NOT NULL,
    smoke_friendly SMALLINT DEFAULT 0 NOT NULL,
    description VARCHAR2(100) DEFAULT NULL
);

CREATE TABLE Room (
    room_number INT PRIMARY KEY NOT NULL
            CHECK (REGEXP_LIKE(room_number, '^[0-9]{3}')),
    floor INT NOT NULL
            CHECK (floor BETWEEN 0 AND 9),
    cost DECIMAL NOT NULL,
    is_reserved NUMBER(1) DEFAULT 0 NOT NULL -- 0 - not reserved, 1 - reserved
            CHECK (is_reserved IN (0, 1)),
    description VARCHAR2(100) DEFAULT NULL,
    room_type_id INT NOT NULL,
    CONSTRAINT room_room_type_fk
            FOREIGN KEY (room_type_id) REFERENCES Room_type (type_id)
            ON DELETE SET NULL
);

-----------------------------------------PAYMENT AND SERVICES-------------------------------------

CREATE TABLE Payment (
    payment_Id INT GENERATED AS IDENTITY NOT NULL PRIMARY KEY,
    amount DECIMAL NOT NULL,
    pay_time DATE DEFAULT CURRENT_DATE,
    method VARCHAR2(4) NOT NULL
               CHECK (method IN ('cash', 'card')),
    status VARCHAR2(10) NOT NULL
               CHECK (status IN ('Pending', 'Completed', 'Failed')),
    currency VARCHAR2(3) NOT NULL
               CHECK (REGEXP_LIKE(currency, '^[a-z]{3}', 'i')),
    customer_id INT NOT NULL,
    CONSTRAINT payment_customer_id_fk
               FOREIGN KEY (customer_id) REFERENCES Customer (customer_id)
               ON DELETE CASCADE
);

CREATE TABLE Service (
    service_id INT GENERATED AS IDENTITY NOT NULL PRIMARY KEY,
    name VARCHAR2(20) NOT NULL
        CHECK (name IN ('Room Cleaning', 'Breakfast', 'Spa Access', 'Gym Access', 'Wi-Fi')),
    price DECIMAL NOT NULL,
    required_status VARCHAR(10) DEFAULT 'Basic'
            CHECK (required_status IN ('VIP', 'Basic', 'Regular') )
);

-----------------------------------------LINK TABLES------------------------------------------------

CREATE TABLE Service_Customer (
    service_id INT NOT NULL,
    customer_id INT NOT NULL,
    CONSTRAINT service_customer_id_pk
            PRIMARY KEY (service_id, customer_id),
    CONSTRAINT service_customer_service_id_fk
            FOREIGN KEY (service_id) REFERENCES Service (service_id)
            ON DELETE CASCADE,
    CONSTRAINT service_customer_customer_id_fk
            FOREIGN KEY (customer_id) REFERENCES Customer (customer_id)
            ON DELETE CASCADE
);

CREATE TABLE Service_Personnel (
    service_id INT NOT NULL,
    personnel_id INT NOT NULL,
    CONSTRAINT service_personnel_pk
            PRIMARY KEY (service_id, personnel_id),
    CONSTRAINT service_personnel_service_id_fk
            FOREIGN KEY (service_id) REFERENCES Service (service_id)
            ON DELETE CASCADE,
    CONSTRAINT service_personnel_personnel_id_fk
            FOREIGN KEY (personnel_id) REFERENCES Personnel (personnel_id)
            ON DELETE CASCADE
);

-----------------------------------------RESERVATION TABLE---------------------------------------

CREATE TABLE Reservation (
    reservation_id INT GENERATED AS IDENTITY NOT NULL PRIMARY KEY,
    customer_id INT NOT NULL,
    CONSTRAINT reservation_customer_id
        FOREIGN KEY (customer_id) REFERENCES Customer(customer_id)
        ON DELETE CASCADE,
    arrival DATE NOT NULL,
    departure DATE NOT NULL,
    total DECIMAL NOT NULL,
    people_amount INT NOT NULL,
    CONSTRAINT check_dates CHECK (arrival <= departure)
);

CREATE TABLE Reservation_Room (
    reservation_id INT NOT NULL,
    room_id INT NOT NULL,
    CONSTRAINT reservation_room_id_pk
            PRIMARY KEY (reservation_id, room_id),
    CONSTRAINT reservation_room_reservation_id_fk
            FOREIGN KEY (reservation_id) REFERENCES Reservation (reservation_id)
            ON DELETE CASCADE,
    CONSTRAINT reservation_room_room_id_fk
            FOREIGN KEY (room_id) REFERENCES Room (room_number)
            ON DELETE CASCADE
);

-----------------------------------------TRIGGERS---------------------------------------------------

-- Trigger that checks if the customer can order the service
CREATE OR REPLACE TRIGGER client_status_control
    BEFORE INSERT OR UPDATE
    OF customer_id, service_id ON Service_Customer
    FOR EACH ROW
DECLARE
    client_status VARCHAR2(20);
    service_req_status VARCHAR2(20);
BEGIN
    SELECT status INTO client_status
    FROM Customer C WHERE C.customer_id = :NEW.customer_id;
    SELECT required_status INTO service_req_status
    FROM Service S WHERE S.service_id = :NEW.service_id;
    IF client_status <> service_req_status THEN
        RAISE_APPLICATION_ERROR(-20001, 'this customer cannot order this service');
    END IF;
END;
/

-- Trigger that marks the room as reserved when it is added to the reservation
CREATE OR REPLACE TRIGGER room_availability_on_reservation_change_true
    AFTER INSERT OR UPDATE
    OF room_id ON Reservation_Room
    FOR EACH ROW
BEGIN
    UPDATE Room SET is_reserved = 1
    WHERE room_number = :NEW.room_id;
END;
/

-----------------------------------------PROCEDURES---------------------------------------------------

CREATE OR REPLACE PROCEDURE create_reservation(
    p_customer_id IN Reservation.customer_id%TYPE,
    p_arrival IN Reservation.arrival%TYPE,
    p_departure IN Reservation.departure%TYPE,
    p_people_amount IN Reservation.people_amount%TYPE,
    p_room_number IN Room.room_number%TYPE
) AUTHID CURRENT_USER
IS
    v_total Reservation.total%TYPE;
    v_room_cost Room.cost%TYPE;
    v_room_status Room.is_reserved%TYPE;
    v_reservation_exists NUMBER := 0;
    v_max_people Room_type.capacity%TYPE;
    v_stay_duration NUMBER;
    v_reservation_id Reservation.reservation_id%TYPE;
    CURSOR reservation_cursor IS
        SELECT arrival, departure
        FROM Reservation_Room
        JOIN Reservation ON Reservation_Room.reservation_id = Reservation.reservation_id
        WHERE room_id = p_room_number;
BEGIN
    SELECT cost INTO v_room_cost
    FROM Room
    WHERE room_number = p_room_number;

    SELECT is_reserved INTO v_room_status
    FROM Room
    WHERE room_number = p_room_number;

    SELECT capacity INTO v_max_people
    FROM Room R JOIN Room_type Rt ON R.room_type_id = Rt.type_id
    WHERE R.room_number = p_room_number;

    IF(p_people_amount > v_max_people) THEN
        RAISE_APPLICATION_ERROR(-20002, 'This room cannot accommodate this number of people');
    END IF;

    IF v_room_status = 1 THEN
        FOR reservation_rec IN reservation_cursor
        LOOP
            IF (p_arrival BETWEEN reservation_rec.arrival AND reservation_rec.departure) OR
               (p_departure BETWEEN reservation_rec.arrival AND reservation_rec.departure) THEN
                v_reservation_exists := 1;
                EXIT;
            END IF;
        END LOOP;

        IF v_reservation_exists = 1 THEN
            RAISE_APPLICATION_ERROR(-20003, 'This room is already reserved for this period');
        END IF;

        v_stay_duration := p_departure - p_arrival;

        v_total := v_stay_duration * v_room_cost;

        INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
        VALUES (p_customer_id, p_arrival, p_departure, v_total, p_people_amount);

        SELECT reservation_id INTO v_reservation_id
        FROM Reservation
        WHERE customer_id = p_customer_id AND arrival = p_arrival AND departure = p_departure;

        INSERT INTO Reservation_Room (reservation_id, room_id)
        VALUES (v_reservation_id, p_room_number);
    END IF;
END;
/
show errors;

CREATE OR REPLACE PROCEDURE calculate_customer_balance(
    p_customer_id IN Customer.customer_id%TYPE
)
IS
    v_customer_name Person.name%TYPE;
    v_customer_surname Person.surname%TYPE;
    v_total_due DECIMAL(10, 2);
    v_total_paid DECIMAL(10, 2);
    v_total_amount DECIMAL(10, 2);
BEGIN
    SELECT NVL(SUM(R.total), 0) + NVL(SUM(S.price), 0)
    INTO v_total_due
    FROM Reservation R
    LEFT JOIN Service_Customer SC ON R.customer_id = SC.customer_id
    LEFT JOIN Service S ON SC.service_id = S.service_id
    WHERE R.customer_id = p_customer_id;

    SELECT NVL(SUM(P.amount), 0)
    INTO v_total_paid
    FROM Payment P
    WHERE P.customer_id = p_customer_id;

    SELECT name, surname INTO v_customer_name, v_customer_surname
    FROM Person
    WHERE person_id = p_customer_id;

    v_total_amount := v_total_due - v_total_paid;

    DBMS_OUTPUT.put_line('Customer ' || v_customer_name || ' ' || v_customer_surname || ' have total orders on: $' || v_total_due);
    DBMS_OUTPUT.put_line('Customer ' || v_customer_name || ' ' || v_customer_surname || ' paid: $' || v_total_paid);
    DBMS_OUTPUT.put_line('Customer ' || v_customer_name || ' ' || v_customer_surname || ' have to pay: $' || v_total_amount);

END;
/


--------------------------------------INSERTS-----------------------------------------------------

INSERT INTO Person (name, surname, contact_Number, age, gender, date_of_birth)
VALUES  ('Ondrej', 'Novak', '+420456789012', 24, 'male', DATE '2000-04-03');

INSERT INTO Person (name, surname, contact_Number, age, gender, date_of_birth)
VALUES  ('Andrii', 'Bohdan', '+380668883333', 29, 'male', DATE '1994-10-06');

INSERT INTO Person (name, surname, contact_Number, age, gender, date_of_birth)
VALUES  ('Dmitrii', 'Volkov', '+788002553535', 23, 'another', DATE '2001-04-03');

INSERT INTO Person (name, surname, contact_Number, age, gender, date_of_birth)
VALUES  ('John', 'Gold', '+123456789012', 30, 'male', DATE '1994-03-22');

INSERT INTO Person (name, surname, contact_Number, age, gender, date_of_birth)
VALUES ('Emily', 'Clark', '+123456789013', 44, 'female', DATE '1980-01-01');

INSERT INTO Person (name, surname, contact_Number, age, gender, date_of_birth)
VALUES ('Taylor', 'Smith', '+123456789014', 42, 'another', DATE '1982-02-02');

INSERT INTO Customer (customer_id, pas_number, status, citizenship)
VALUES (1, 987654321, 'VIP', 'CZ');

INSERT INTO Customer (customer_id, pas_number, status, citizenship)
VALUES (2, 123456789, 'Basic', 'UA');

INSERT INTO Customer (customer_id, pas_number, status, citizenship)
VALUES (3, 234567890, 'Regular', 'RU');

INSERT INTO Personnel (personnel_id, job_title, access_level)
VALUES (4, 'Receptionist', 'LOW');

INSERT INTO Personnel (personnel_id, job_title, access_level)
VALUES (5, 'Cook', 'MEDIUM');

INSERT INTO Personnel (personnel_id, job_title, access_level)
VALUES (6, 'Bellboy', 'LOW');

INSERT INTO Room_type (name, capacity, pet_friendly, smoke_friendly, description)
VALUES ('Single', 1, 0, 0, 'One single bed');

INSERT INTO Room_type (name, capacity, pet_friendly, smoke_friendly, description)
VALUES ('Double', 2, 1, 0, 'One double bed, pet friendly');

INSERT INTO Room_type (name, capacity, pet_friendly, smoke_friendly, description)
VALUES ('Suite', 4, 1, 1, 'Two bedrooms, pet and smoke friendly');

INSERT INTO Room (room_number, floor, cost, is_reserved, description, room_type_id)
VALUES (101, 1, 100.00, 1, 'First floor single room', 1);

INSERT INTO Room (room_number, floor, cost, is_reserved, description, room_type_id)
VALUES (202, 2, 150.00, 1, 'Second floor double room', 2);

INSERT INTO Room (room_number, floor, cost, is_reserved, description, room_type_id)
VALUES (303, 3, 250.00, 0, 'Third floor suite', 3);

INSERT INTO Payment (amount, pay_time, method, status, currency, customer_id)
VALUES (200.00, DATE '2023-04-01', 'card', 'Completed', 'usd', 1);

INSERT INTO Payment (amount, pay_time, method, status, currency, customer_id)
VALUES (800.00, DATE '2023-04-03', 'card', 'Completed', 'usd', 1);

INSERT INTO Payment (amount, pay_time, method, status, currency, customer_id)
VALUES (150.00, DATE '2023-04-02', 'cash', 'Pending', 'eur', 2);

INSERT INTO Payment (amount, pay_time, method, status, currency, customer_id)
VALUES (300.00, DATE '2023-04-08', 'cash', 'Pending', 'eur', 2);

INSERT INTO Payment (amount, pay_time, method, status, currency, customer_id)
VALUES (500.00, DATE '2023-04-03', 'card', 'Failed', 'gbp', 3);

INSERT INTO Service (name, price, required_status)
VALUES ('Room Cleaning', 25.00, 'VIP');

INSERT INTO Service (name, price, required_status)
VALUES ('Breakfast', 10.00, 'Basic');

INSERT INTO Service (name, price, required_status)
VALUES ('Wi-Fi', 0.00, 'Regular');

INSERT INTO Service_Customer (service_id, customer_id)
VALUES (1, 1);

INSERT INTO Service_Customer (service_id, customer_id)
VALUES (2, 2);

INSERT INTO Service_Customer (service_id, customer_id)
VALUES (3, 3);

INSERT INTO Service_Personnel (service_id, personnel_id)
VALUES (1, 4);

INSERT INTO Service_Personnel (service_id, personnel_id)
VALUES (2, 5);

INSERT INTO Service_Personnel (service_id, personnel_id)
VALUES (3, 6);

INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
VALUES (1, DATE '2023-05-01', DATE '2023-05-05', 450.00, 1);

INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
VALUES (1, DATE '2023-11-01', DATE '2023-11-08', 822.00, 3);

INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
VALUES (1, DATE '2023-12-24', DATE '2023-12-29', 930.00, 2);

INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
VALUES (2, DATE '2023-06-01', DATE '2023-06-05', 750.00, 2);

INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
VALUES (2, DATE '2023-08-18', DATE '2023-08-25', 950.00, 2);

INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
VALUES (3, DATE '2023-07-01', DATE '2023-07-05', 1200.00, 4);

INSERT INTO Reservation (customer_id, arrival, departure, total, people_amount)
VALUES (3, DATE '2023-07-15', DATE '2023-07-20', 1400.00, 4);

INSERT INTO Reservation_Room (reservation_id, room_id)
VALUES (1, 101);

INSERT INTO Reservation_Room (reservation_id, room_id)
VALUES (2, 202);

INSERT INTO Reservation_Room (reservation_id, room_id)
VALUES (3, 303);

-- What types of rooms do the rooms have?
-- two tables joining
SELECT room_number, name
FROM Room R, Room_type Rt
WHERE R.room_type_id = Rt.type_id;

-- What job positions do the Personnel members have?
-- Two tables joining
SELECT name, surname, job_title
FROM Person Prsn, Personnel Prsnl
WHERE Prsn.person_id = Prsnl.personnel_id;

-- Print information about customers and their reservations
-- Three tables joining
SELECT name, surname, status, citizenship, arrival, departure, total, people_amount
FROM Person P, Customer C, Reservation R
WHERE P.person_id = C.customer_id AND C.customer_id = R.customer_id;

-- How much did each person payed?
-- GROUP BY using and aggregation function SUM
SELECT name, surname, SUM(amount) AS sum_of_pays
FROM Person P, Customer C, Payment Pmt
WHERE P.person_id = C.customer_id AND C.customer_id = Pmt.customer_id
GROUP BY name, surname;

-- Which is average value of reservation costs and count of reservation each person did?
-- Which is max value of people they had in reservations?
-- GROUP BY using and aggregation functions AVG, COUNT and MAX
SELECT name, surname, AVG(total) AS average_reservation_cost, COUNT(*) AS reservations_amount, MAX(people_amount) AS max_people
FROM Person P, Customer C, Reservation R
WHERE P.person_id = C.customer_id AND C.customer_id = R.customer_id
GROUP BY name, surname;

-- Print all payments of customers, that had payments, that had been done by card and had been completed
-- EXISTS using
SELECT name, surname, amount, currency, pay_time, method, Pmt.status
FROM Person P, Customer C, Payment Pmt
WHERE P.person_id = C.customer_id AND C.customer_id = Pmt.customer_id AND EXISTS
    (SELECT *
    FROM Customer Cstmr, Payment Pmnt
    WHERE Cstmr.customer_id = Pmnt.customer_id
      AND C.customer_id = Cstmr.customer_id AND Pmnt.customer_id = Pmt.customer_id
      AND Pmt.method = 'card' AND Pmt.status = 'Completed'
    );

-- Print all payments, that each person had, had been provided in USD
-- IN using
SELECT name, surname, amount, pay_time
FROM Person P, Customer C, Payment Pmt
WHERE P.person_id = C.customer_id AND C.customer_id = Pmt.customer_id AND C.customer_id IN (
    SELECT customer_id
    FROM Payment Pmt
    WHERE Pmt.currency = 'usd'
);

-- Demonstrates client_status_control trigger
-- INSERT INTO Service_Customer (service_id, customer_id)
-- VALUES (1, 2);

-- Demonstrates room_availability_on_reservation_change trigger

-- add new not reserved room
INSERT INTO Room (room_number, floor, cost, is_reserved, description, room_type_id)
VALUES (404, 4, 300.00, 0, 'Fourth floor suite', 3);

-- check if room is not reserved
SELECT room_number, is_reserved FROM Room;

-- add room to reservation
INSERT INTO Reservation_Room (reservation_id, room_id)
VALUES (4, 404);

-- check if room is reserved
SELECT room_number, is_reserved FROM Room;

-- call create_reservation procedure
BEGIN create_reservation(1, DATE '2023-10-06', DATE '2023-10-25', 1, 101); END;/

-- check if reservation was added
SELECT R.reservation_id, room_id, customer_id, arrival, departure, total, people_amount
FROM Reservation R JOIN Reservation_Room RR ON R.reservation_id = RR.reservation_id
WHERE arrival = DATE '2023-10-06' AND departure = DATE '2023-10-25';


-- Demonstrates calculate_customer_balance procedure

-- add new Person
INSERT INTO Person (name, surname, contact_Number, age, gender, date_of_birth)
VALUES  ('Sana', 'Muden', '+420456789012', 24, 'male', DATE '2000-04-03');

-- add new Customer
INSERT INTO Customer (customer_id, pas_number, status, citizenship)
VALUES (7, 987654321, 'VIP', 'CZ');

-- create reservation for new customer
BEGIN create_reservation(7, DATE '2023-09-1', DATE '2023-09-25', 1, 101); END;/

-- check how much customer have to pay for reservation
-- in this demonstrative case, customer have to pay $2400
SELECT R.reservation_id, room_id, total
FROM Reservation R JOIN Reservation_Room RR ON R.reservation_id = RR.reservation_id
WHERE R.customer_id = 7;

-- add services to customer
INSERT INTO Service_Customer (service_id, customer_id)
VALUES (1, 7);

-- check how much customer have to pay for services
-- in this demonstrative case, customer have to pay $25 for room cleaning
-- total amount to pay is $2425
SELECT P.name, surname, price
FROM Person P, Customer C, Service S, Service_Customer SC
WHERE P.person_id = C.customer_id AND C.customer_id = SC.customer_id AND SC.service_id = S.service_id;

-- add payment for customer on $1000
INSERT INTO Payment (amount, pay_time, method, status, currency, customer_id)
VALUES (1000.00, DATE '2023-09-01', 'card', 'Completed', 'usd', 7);

-- check how much customer have to pay now
BEGIN calculate_customer_balance(7); END;/

GRANT ALL ON Person TO xadamo04;
GRANT ALL ON Customer TO xadamo04;
GRANT ALL ON Personnel TO xadamo04;
GRANT ALL ON Room TO xadamo04;
GRANT ALL ON Room_type TO xadamo04;
GRANT ALL ON Payment TO xadamo04;
GRANT ALL ON Service TO xadamo04;
GRANT ALL ON Service_Customer TO xadamo04;
GRANT ALL ON Service_Personnel TO xadamo04;
GRANT ALL ON Reservation TO xadamo04;
GRANT ALL ON Reservation_Room TO xadamo04;
GRANT EXECUTE ON create_reservation TO xadamo04;