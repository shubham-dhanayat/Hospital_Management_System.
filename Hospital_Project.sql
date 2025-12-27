/* =============================================================================
   PROJECT: ORACLE HRIE (Hospital Resource & Insurance Engine)
   FULL STACK DATABASE ERP SYSTEM
   AUTHOR: Shubham Dhanayat
   
   DESCRIPTION: 
   A comprehensive PL/SQL project featuring Finite State Machines, 
   Pessimistic Locking, FEFO Inventory Algorithms, and Financial Aggregation.
============================================================================= */

-- =============================================================================
-- SECTION 0: USER CREATION & PRIVILEGES (ADMIN TASKS)
-- Note: Run this section as SYS/SYSTEM only if the user does not exist.
-- =============================================================================
/*
CREATE USER hospital_p IDENTIFIED BY hsm;
GRANT CREATE SESSION TO hospital_p;
ALTER USER hospital_p DEFAULT TABLESPACE users;
ALTER USER hospital_p TEMPORARY TABLESPACE temp;
ALTER USER hospital_p QUOTA UNLIMITED ON users;
GRANT CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, 
      CREATE TRIGGER, CREATE SYNONYM TO hospital_p;
GRANT CONNECT, RESOURCE TO hospital_p;
*/

-- *****************************************************************************
-- MODULE 1: FOUNDATION & MASTER DATA MANAGEMENT (MDM)
-- *****************************************************************************

-- 1. CLEANUP
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE HMS_PATIENT_MASTER CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE HMS_DOCTOR_MASTER CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE HMS_DEPARTMENTS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE HMS_LOOKUPS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_PATIENT_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_DOCTOR_ID';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;


-- 2. CREATE SEQUENCES (NOCACHE for strict audit gaps)
CREATE SEQUENCE SEQ_PATIENT_ID START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_DOCTOR_ID START WITH 500 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_DEPT_ID START WITH 10 INCREMENT BY 10 NOCACHE;

-- 3. LOOKUP MASTER (Configuration Table)
CREATE TABLE HMS_LOOKUPS (
    LOOKUP_TYPE       VARCHAR2(30) NOT NULL,
    LOOKUP_CODE       VARCHAR2(30) NOT NULL,
    MEANING           VARCHAR2(100) NOT NULL,
    DESCRIPTION       VARCHAR2(255),
    IS_ACTIVE         CHAR(1) DEFAULT 'Y' CHECK (IS_ACTIVE IN ('Y', 'N')),
    CONSTRAINT PK_HMS_LOOKUPS PRIMARY KEY (LOOKUP_TYPE, LOOKUP_CODE)
);

-- 4. INSERT SEED DATA
INSERT INTO HMS_LOOKUPS VALUES ('GENDER', 'M', 'Male', 'Male Patient', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('GENDER', 'F', 'Female', 'Female Patient', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('GENDER', 'O', 'Other', 'Other', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'O+', 'O Positive', 'Universal Donor', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'A+', 'A Positive', '', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'B+', 'B Positive', '', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'AB+', 'AB Positive', '', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'O-', 'O Negative', '', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'A-', 'A Negative', '', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'B-', 'B Negative', '', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('BLOOD_GROUP', 'AB-', 'AB Negative', '', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('CITY', 'MUM', 'Mumbai', 'Metro City', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('CITY', 'PUN', 'Pune', 'IT Hub', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('CITY', 'DEL', 'Delhi', 'Capital', 'Y');
INSERT INTO HMS_LOOKUPS VALUES ('CITY', 'BLR', 'Bangalore', 'Tech City', 'Y');
COMMIT;

-- 5. DEPARTMENT MASTER
CREATE TABLE HMS_DEPARTMENTS (
    DEPT_ID           NUMBER(5) primary key,
    DEPT_NAME         VARCHAR2(100) NOT NULL,
    DEPT_CODE         VARCHAR2(10) UNIQUE,
    IS_ACTIVE         CHAR(1) DEFAULT 'Y' CHECK (IS_ACTIVE IN ('Y', 'N'))
);

--Added Trigger to Simulate Identity Column behavior
CREATE OR REPLACE TRIGGER TRG_DEPT_ID
BEFORE INSERT ON HMS_DEPARTMENTS
FOR EACH ROW
BEGIN
    IF :NEW.DEPT_ID IS NULL THEN
        SELECT SEQ_DEPT_ID.NEXTVAL INTO :NEW.DEPT_ID FROM DUAL;
    END IF;
END;

INSERT INTO HMS_DEPARTMENTS (DEPT_NAME, DEPT_CODE) VALUES ('General Medicine', 'GENMED');
INSERT INTO HMS_DEPARTMENTS (DEPT_NAME, DEPT_CODE) VALUES ('Orthopedics', 'ORTHO');
INSERT INTO HMS_DEPARTMENTS (DEPT_NAME, DEPT_CODE) VALUES ('Cardiology', 'CARDIO');
INSERT INTO HMS_DEPARTMENTS (DEPT_NAME, DEPT_CODE) VALUES ('Pediatrics', 'PEDIA');
COMMIT;

-- 6. DOCTOR MASTER
CREATE TABLE HMS_DOCTOR_MASTER (
    DOCTOR_ID         NUMBER(10) PRIMARY KEY,
    FULL_NAME         VARCHAR2(100) NOT NULL,
    SPECIALIZATION    VARCHAR2(50),
    DEPT_ID           NUMBER(5) REFERENCES HMS_DEPARTMENTS(DEPT_ID),
    MOBILE_NO         VARCHAR2(15) UNIQUE NOT NULL,
    EMAIL             VARCHAR2(100) CHECK (EMAIL LIKE '%@%'),
    CONSULTATION_FEE  NUMBER(10, 2) DEFAULT 500,
    JOINING_DATE      DATE DEFAULT SYSDATE,
    IS_ACTIVE         CHAR(1) DEFAULT 'Y' CHECK (IS_ACTIVE IN ('Y', 'N')),
    -- Audit Columns
    CREATED_BY        VARCHAR2(50),
    CREATION_DATE     DATE,
    LAST_UPDATED_BY   VARCHAR2(50),
    LAST_UPDATE_DATE  DATE
);

-- 7. PATIENT MASTER
CREATE TABLE HMS_PATIENT_MASTER (
    PATIENT_ID        NUMBER(10) PRIMARY KEY,
    UHID              VARCHAR2(20) UNIQUE NOT NULL,
    FIRST_NAME        VARCHAR2(50) NOT NULL,
    LAST_NAME         VARCHAR2(50) NOT NULL,
    DATE_OF_BIRTH     DATE NOT NULL, 
    GENDER            VARCHAR2(10) NOT NULL CHECK (GENDER IN ('M', 'F', 'O')),
    MOBILE_NO         VARCHAR2(15) NOT NULL,
    EMAIL             VARCHAR2(100) CHECK (EMAIL LIKE '%@%'),
    ADDRESS           VARCHAR2(255),
    CITY              VARCHAR2(50),
    BLOOD_GROUP       VARCHAR2(5),
    -- Audit Columns
    REGISTERED_DATE   DATE DEFAULT SYSDATE,
    CREATED_BY        VARCHAR2(50),
    LAST_UPDATED_BY   VARCHAR2(50),
    LAST_UPDATE_DATE  DATE,
    IS_ACTIVE         CHAR(1) DEFAULT 'Y'
);

--Trigger to check DATE_OF_BIRTH is not greater that SYSDATE (No future DOBs)
CREATE OR REPLACE TRIGGER trg_check_dob
BEFORE INSERT OR UPDATE ON hms_patient_master
FOR EACH ROW
BEGIN
  IF :NEW.date_of_birth > SYSDATE THEN
    RAISE_APPLICATION_ERROR(-20001, 'Date of birth cannot be in the future');
  END IF;
END;

-- 8. AUDIT TRIGGERS
CREATE OR REPLACE TRIGGER TRG_PATIENT_AUDIT
BEFORE INSERT OR UPDATE ON HMS_PATIENT_MASTER
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        :NEW.CREATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
        :NEW.REGISTERED_DATE := SYSDATE;
    END IF;
    :NEW.LAST_UPDATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
    :NEW.LAST_UPDATE_DATE := SYSDATE;
END;

-- Trigger for Doctor Audit
CREATE OR REPLACE TRIGGER TRG_DOCTOR_AUDIT
BEFORE INSERT OR UPDATE ON HMS_DOCTOR_MASTER
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        :NEW.CREATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
        :NEW.CREATION_DATE := SYSDATE;
    END IF;
    :NEW.LAST_UPDATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
    :NEW.LAST_UPDATE_DATE := SYSDATE;
END;

--9.Package specification
CREATE OR REPLACE PACKAGE PKG_PATIENT_MGMT IS
  FUNCTION FN_GENERATE_UHID(p_city IN VARCHAR2) RETURN VARCHAR2;
  PROCEDURE PRC_REGISTER_PATIENT(p_first_name  IN VARCHAR2,
                                 p_last_name   IN VARCHAR2,
                                 p_dob         IN DATE,
                                 p_gender      IN VARCHAR2,
                                 p_mobile      IN VARCHAR2,
                                 p_city        IN VARCHAR2,
                                 p_address     IN VARCHAR2,
                                 p_blood_group IN VARCHAR2,
                                 p_email       IN VARCHAR2 DEFAULT NULL,
                                 p_uhid_out    OUT VARCHAR2);
END PKG_PATIENT_MGMT;


--10.LOGIC PACKAGE
CREATE OR REPLACE PACKAGE BODY PKG_PATIENT_MGMT IS
    FUNCTION FN_GENERATE_UHID(p_city IN VARCHAR2) RETURN VARCHAR2 IS
        v_year VARCHAR2(4);
        v_seq  NUMBER;
        v_clean_city VARCHAR2(3);
    BEGIN
        v_year := TO_CHAR(SYSDATE, 'YYYY');
        v_clean_city := SUBSTR(UPPER(NVL(p_city, 'GEN')), 1, 3);   
        
        SELECT SEQ_PATIENT_ID.NEXTVAL INTO v_seq FROM DUAL;
        
        RETURN v_clean_city || '-' || v_year || '-' || v_seq;
    END FN_GENERATE_UHID;

    PROCEDURE PRC_REGISTER_PATIENT (
        p_first_name    IN VARCHAR2,
        p_last_name     IN VARCHAR2,
        p_dob           IN DATE,
        p_gender        IN VARCHAR2,
        p_mobile        IN VARCHAR2,
        p_city          IN VARCHAR2,
        p_address       IN VARCHAR2,
        p_blood_group   IN VARCHAR2,
        p_email         IN VARCHAR2 DEFAULT NULL,
        p_uhid_out      OUT VARCHAR2
    ) IS
        v_count NUMBER;
        v_new_uhid VARCHAR2(20);
    BEGIN
        SELECT COUNT(1) INTO v_count 
        FROM HMS_PATIENT_MASTER 
        WHERE MOBILE_NO = p_mobile AND UPPER(FIRST_NAME) = UPPER(p_first_name);

        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Duplicate Error: Patient '||p_first_name||' is already registered with Mobile '||p_mobile);
        END IF;

        v_new_uhid := FN_GENERATE_UHID(p_city);

        -- Insert Data
        INSERT INTO HMS_PATIENT_MASTER (
            PATIENT_ID, UHID, FIRST_NAME, LAST_NAME, DATE_OF_BIRTH, 
            GENDER, MOBILE_NO, CITY, ADDRESS, BLOOD_GROUP, EMAIL
        ) VALUES (
            SEQ_PATIENT_ID.CURRVAL, v_new_uhid, p_first_name, p_last_name, p_dob,
            p_gender, p_mobile, p_city, p_address, p_blood_group, p_email
        );

        p_uhid_out := v_new_uhid; 
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END PRC_REGISTER_PATIENT;

END PKG_PATIENT_MGMT;


--11. DATA LOADING 
DECLARE
    v_uhid VARCHAR2(20);
BEGIN
    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Rajesh', 'Sharma', TO_DATE('1985-06-15','YYYY-MM-DD'), 'M', '9876543210', 'MUM', 'Andheri West', 'O+', 'rajesh.s@email.com', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Priya', 'Patel', TO_DATE('1992-11-20','YYYY-MM-DD'), 'F', '9123456789', 'PUN', 'Kothrud', 'A+', 'priya.p@email.com', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Amit', 'Verma', TO_DATE('1978-03-10','YYYY-MM-DD'), 'M', '9988776655', 'MUM', 'Dadar', 'B+', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Sneha', 'Iyer', TO_DATE('1995-07-25','YYYY-MM-DD'), 'F', '9876500001', 'PUN', 'Viman Nagar', 'AB+', 'sneha.i@test.com', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Vikram', 'Singh', TO_DATE('1960-01-05','YYYY-MM-DD'), 'M', '9876500002', 'MUM', 'Bandra', 'O-', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Anjali', 'Deshmukh', TO_DATE('1988-09-12','YYYY-MM-DD'), 'F', '9876500003', 'MUM', 'Thane', 'A-', 'anjali.d@web.com', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Rahul', 'Gupta', TO_DATE('2000-02-14','YYYY-MM-DD'), 'M', '9876500004', 'PUN', 'Hinjewadi', 'B-', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Kavita', 'Reddy', TO_DATE('1975-12-30','YYYY-MM-DD'), 'F', '9876500005', 'MUM', 'Powai', 'O+', 'kavita.r@mail.com', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Suresh', 'Nair', TO_DATE('1955-08-20','YYYY-MM-DD'), 'M', '9876500006', 'BLR', 'Whitefield', 'AB-', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Meera', 'Joshi', TO_DATE('1999-05-05','YYYY-MM-DD'), 'F', '9876500007', 'PUN', 'Aundh', 'A+', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Rohan', 'Mehta', TO_DATE('1982-10-10','YYYY-MM-DD'), 'M', '9876500008', 'MUM', 'Malad', 'B+', 'rohan.m@site.com', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Pooja', 'Chavan', TO_DATE('1990-04-18','YYYY-MM-DD'), 'F', '9876500009', 'MUM', 'Goregaon', 'O+', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Arjun', 'Rao', TO_DATE('1970-06-22','YYYY-MM-DD'), 'M', '9876500010', 'PUN', 'Magarpatta', 'A+', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Neha', 'Kulkarni', TO_DATE('1994-01-30','YYYY-MM-DD'), 'F', '9876500011', 'MUM', 'Vashi', 'B+', 'neha.k@cloud.com', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Manish', 'Tiwari', TO_DATE('1986-11-11','YYYY-MM-DD'), 'M', '9876500012', 'DEL', 'Dwarka', 'O-', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Sana', 'Khan', TO_DATE('1997-03-03','YYYY-MM-DD'), 'F', '9876500013', 'PUN', 'Baner', 'AB+', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Deepak', 'Mishra', TO_DATE('1968-08-08','YYYY-MM-DD'), 'M', '9876500014', 'MUM', 'Colaba', 'A-', 'deepak.m@gov.in', v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Riya', 'Sen', TO_DATE('2001-09-19','YYYY-MM-DD'), 'F', '9876500015', 'MUM', 'Borivali', 'O+', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Karan', 'Johar', TO_DATE('1979-12-25','YYYY-MM-DD'), 'M', '9876500016', 'PUN', 'Wakad', 'B+', NULL, v_uhid);

    PKG_PATIENT_MGMT.PRC_REGISTER_PATIENT('Simran', 'Kaur', TO_DATE('1993-07-07','YYYY-MM-DD'), 'F', '9876500017', 'DEL', 'Saket', 'A+', 'simran.k@live.com', v_uhid);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Success: 20 Patients Registered with Smart IDs.');
END;


-- *****************************************************************************
-- MODULE 2: OPD & CONCURRENCY ENGINE
-- *****************************************************************************

-- 1. CLEANUP
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE OPD_APPOINTMENTS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE OPD_SCHEDULE_MASTER CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_APPOINTMENT_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_SCHEDULE_ID'; 
EXCEPTION WHEN OTHERS THEN NULL;
END;


-- 2. SEQUENCES
CREATE SEQUENCE SEQ_APPOINTMENT_ID START WITH 100000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_SCHEDULE_ID START WITH 1 INCREMENT BY 1 NOCACHE; 

-- 3. SCHEDULE MASTER (The Rules)
CREATE TABLE OPD_SCHEDULE_MASTER (
    SCHEDULE_ID       NUMBER(10) PRIMARY KEY,
    DOCTOR_ID         NUMBER(10) NOT NULL REFERENCES HMS_DOCTOR_MASTER(DOCTOR_ID),
    DAY_OF_WEEK       VARCHAR2(3) NOT NULL CHECK (DAY_OF_WEEK IN ('MON','TUE','WED','THU','FRI','SAT','SUN')),
    START_TIME        VARCHAR2(5) NOT NULL CHECK (REGEXP_LIKE(START_TIME, '^([0-1][0-9]|2[0-3]):[0-5][0-9]$')), 
    END_TIME          VARCHAR2(5) NOT NULL CHECK (REGEXP_LIKE(END_TIME, '^([0-1][0-9]|2[0-3]):[0-5][0-9]$')),
    AVG_CONSULT_TIME  NUMBER(3) DEFAULT 15,
    IS_ACTIVE         CHAR(1) DEFAULT 'Y' CHECK (IS_ACTIVE IN ('Y', 'N')),
    -- Audit
    CREATED_BY        VARCHAR2(50),
    CREATION_DATE     DATE DEFAULT SYSDATE,
    LAST_UPDATED_BY   VARCHAR2(50),
    LAST_UPDATE_DATE  DATE,
    CONSTRAINT UK_DOC_DAY UNIQUE (DOCTOR_ID, DAY_OF_WEEK)
);

-- Trigger to simulate Identity for Schedule ID
CREATE OR REPLACE TRIGGER TRG_SCHED_ID_GEN
BEFORE INSERT ON OPD_SCHEDULE_MASTER
FOR EACH ROW
BEGIN
    IF :NEW.SCHEDULE_ID IS NULL THEN
        SELECT SEQ_SCHEDULE_ID.NEXTVAL INTO :NEW.SCHEDULE_ID FROM DUAL;
    END IF;
END;


-- 4. APPOINTMENT TRANSACTION (The Booking)
CREATE TABLE OPD_APPOINTMENTS (
    APPOINTMENT_ID    NUMBER(18) PRIMARY KEY,
    APPOINTMENT_NO    VARCHAR2(20) UNIQUE NOT NULL,
    DOCTOR_ID         NUMBER(10) NOT NULL REFERENCES HMS_DOCTOR_MASTER(DOCTOR_ID),
    PATIENT_ID        NUMBER(10) NOT NULL REFERENCES HMS_PATIENT_MASTER(PATIENT_ID),
    APPOINTMENT_DATE  DATE NOT NULL, 
    SLOT_START_TIME   VARCHAR2(5) NOT NULL CHECK (REGEXP_LIKE(SLOT_START_TIME, '^([0-1][0-9]|2[0-3]):[0-5][0-9]$')),
    TOKEN_NUMBER      NUMBER(4) NOT NULL,
    STATUS            VARCHAR2(20) DEFAULT 'BOOKED' CHECK (STATUS IN ('BOOKED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED')),
    CONSULTATION_FEE  NUMBER(10,2), 
    -- Audit
    BOOKED_DATE       DATE DEFAULT SYSDATE,
    CREATED_BY        VARCHAR2(50),
    LAST_UPDATED_BY   VARCHAR2(50),
    LAST_UPDATE_DATE  DATE,
    CONSTRAINT UK_DOC_SLOT UNIQUE (DOCTOR_ID, APPOINTMENT_DATE, SLOT_START_TIME)
);

CREATE INDEX IDX_APP_PATIENT ON OPD_APPOINTMENTS(PATIENT_ID);
CREATE INDEX IDX_APP_DATE_DOC ON OPD_APPOINTMENTS(APPOINTMENT_DATE, DOCTOR_ID);


--5. Trigger for Schedule Master Audit
CREATE OR REPLACE TRIGGER TRG_SCHED_AUDIT
BEFORE INSERT OR UPDATE ON OPD_SCHEDULE_MASTER
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        :NEW.CREATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
        :NEW.CREATION_DATE := SYSDATE;
    END IF;
    :NEW.LAST_UPDATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
    :NEW.LAST_UPDATE_DATE := SYSDATE;
END;


-- Trigger for Appointment Audit
CREATE OR REPLACE TRIGGER TRG_APP_AUDIT
BEFORE INSERT OR UPDATE ON OPD_APPOINTMENTS
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        :NEW.CREATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
        :NEW.BOOKED_DATE := SYSDATE;
    END IF;
    :NEW.LAST_UPDATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
    :NEW.LAST_UPDATE_DATE := SYSDATE;
END;



-- 6: THE APPOINTMENT ENGINE PACKAGE
CREATE OR REPLACE PACKAGE PKG_APPOINTMENT_ENGINE IS
  PROCEDURE PRC_ADD_SCHEDULE(p_doctor_id  IN NUMBER,
                             p_day        IN VARCHAR2, 
                             p_start_time IN VARCHAR2,
                             p_end_time   IN VARCHAR2);

  PROCEDURE PRC_BOOK_APPOINTMENT(p_uhid       IN VARCHAR2,
                                 p_doctor_id  IN NUMBER,
                                 p_req_date   IN DATE,
                                 p_req_time   IN VARCHAR2,
                                 p_app_no_out OUT VARCHAR2,
                                 p_token_out  OUT NUMBER);

END PKG_APPOINTMENT_ENGINE;


CREATE OR REPLACE PACKAGE BODY PKG_APPOINTMENT_ENGINE IS
    PROCEDURE PRC_ADD_SCHEDULE (
        p_doctor_id  IN NUMBER,
        p_day        IN VARCHAR2,
        p_start_time IN VARCHAR2,
        p_end_time   IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO OPD_SCHEDULE_MASTER (DOCTOR_ID, DAY_OF_WEEK, START_TIME, END_TIME)
        VALUES (p_doctor_id, UPPER(p_day), p_start_time, p_end_time);
        COMMIT;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20002, 'Schedule rule for '||p_day||' already exists for this doctor.');
    END PRC_ADD_SCHEDULE;


    PROCEDURE PRC_BOOK_APPOINTMENT (
        p_uhid           IN VARCHAR2,
        p_doctor_id      IN NUMBER,
        p_req_date       IN DATE,
        p_req_time       IN VARCHAR2,
        p_app_no_out     OUT VARCHAR2,
        p_token_out      OUT NUMBER
    ) IS
        v_patient_id     NUMBER;
        v_day_of_week    VARCHAR2(3);
        v_sched_start    VARCHAR2(5);
        v_sched_end      VARCHAR2(5);
        v_fee            NUMBER;
        v_next_token     NUMBER;
        v_app_no         VARCHAR2(20);
        v_seq_val        NUMBER;
    BEGIN
        -- 1. Past Date Validation
        IF TRUNC(p_req_date) < TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(-20010, 'Cannot book appointments for past dates.');
        END IF;

        -- 2. Get Patient ID
        BEGIN
            SELECT PATIENT_ID INTO v_patient_id FROM HMS_PATIENT_MASTER WHERE UHID = p_uhid;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20003, 'Invalid UHID: Patient not found.');
        END;

        -- 3. Check Schedule Availability (NLS Independent)
        v_day_of_week := TO_CHAR(p_req_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH');
        
        BEGIN
            SELECT START_TIME, END_TIME INTO v_sched_start, v_sched_end
            FROM OPD_SCHEDULE_MASTER
            WHERE DOCTOR_ID = p_doctor_id 
              AND DAY_OF_WEEK = UPPER(v_day_of_week)
              AND IS_ACTIVE = 'Y';
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'Doctor is not available on ' || v_day_of_week);
        END;

        -- 4. Check Time Range
        IF p_req_time < v_sched_start OR p_req_time >= v_sched_end THEN
            RAISE_APPLICATION_ERROR(-20005, 'Time '||p_req_time||' is outside working hours ('||v_sched_start||'-'||v_sched_end||')');
        END IF;

        -- 5. Get Fee (Snapshot)
        SELECT CONSULTATION_FEE INTO v_fee FROM HMS_DOCTOR_MASTER WHERE DOCTOR_ID = p_doctor_id;

        -- 6. Generate Token
        SELECT NVL(MAX(TOKEN_NUMBER), 0) + 1 INTO v_next_token
        FROM OPD_APPOINTMENTS
        WHERE DOCTOR_ID = p_doctor_id AND APPOINTMENT_DATE = TRUNC(p_req_date);

        -- 7. Generate App ID
        SELECT SEQ_APPOINTMENT_ID.NEXTVAL INTO v_seq_val FROM DUAL;
        v_app_no := 'APP-' || TO_CHAR(SYSDATE, 'YYYY') || '-' || v_seq_val;

        -- 8. Insert (The Concurrency Lock)
        INSERT INTO OPD_APPOINTMENTS (
            APPOINTMENT_ID, APPOINTMENT_NO, DOCTOR_ID, PATIENT_ID,
            APPOINTMENT_DATE, SLOT_START_TIME, TOKEN_NUMBER, CONSULTATION_FEE, STATUS
        ) VALUES (
            v_seq_val, v_app_no, p_doctor_id, v_patient_id,
            TRUNC(p_req_date), p_req_time, v_next_token, v_fee, 'BOOKED'
        );

        p_app_no_out := v_app_no;
        p_token_out  := v_next_token;
        
        COMMIT;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20006, 'Slot ' || p_req_time || ' is already booked for this doctor.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END PRC_BOOK_APPOINTMENT;

END PKG_APPOINTMENT_ENGINE;


--7: DATA SIMULATION
DECLARE
  v_doc_1 NUMBER;
  v_doc_2 NUMBER;
  v_uhid  VARCHAR2(20);
  v_app   VARCHAR2(20);
  v_tok   NUMBER;
  v_count NUMBER;

  -- Helper to get random patient
  FUNCTION get_random_uhid RETURN VARCHAR2 IS
    v_res VARCHAR2(20);
  BEGIN
    SELECT UHID
      INTO v_res
      FROM (SELECT UHID FROM HMS_PATIENT_MASTER ORDER BY DBMS_RANDOM.VALUE)
     WHERE ROWNUM = 1;
    RETURN v_res;
  
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      INSERT INTO HMS_PATIENT_MASTER
        (PATIENT_ID,
         UHID,
         FIRST_NAME,
         LAST_NAME,
         DATE_OF_BIRTH,
         GENDER,
         MOBILE_NO,
         REGISTERED_DATE)
      VALUES
        (SEQ_PATIENT_ID.NEXTVAL,
         'PAT-TEST-001',
         'Test',
         'Patient',
         SYSDATE - 10000,
         'M',
         '9999999999',
         SYSDATE);
      COMMIT;
      RETURN 'PAT-TEST-001';
  END;

BEGIN
  -- 1. SAFETY CHECK: Ensure Doctors Exist
  SELECT COUNT(1) INTO v_count FROM HMS_DOCTOR_MASTER;

  IF v_count < 2 THEN
    DBMS_OUTPUT.PUT_LINE('No Doctors found. Creating test doctors...');
  
    -- Create Doctor 1
    INSERT INTO HMS_DOCTOR_MASTER
      (DOCTOR_ID, FULL_NAME, MOBILE_NO, CONSULTATION_FEE, IS_ACTIVE)
    VALUES
      (SEQ_DOCTOR_ID.NEXTVAL, 'Dr. Test One', '9000000001', 500, 'Y');
  
    -- Create Doctor 2
    INSERT INTO HMS_DOCTOR_MASTER
      (DOCTOR_ID, FULL_NAME, MOBILE_NO, CONSULTATION_FEE, IS_ACTIVE)
    VALUES
      (SEQ_DOCTOR_ID.NEXTVAL, 'Dr. Test Two', '9000000002', 800, 'Y');
  
    COMMIT;
  END IF;

  -- 2. Find Doctors (Dynamically)
  -- We use min and max to ensure we get two different IDs that actually exist
  SELECT MIN(DOCTOR_ID) INTO v_doc_1 FROM HMS_DOCTOR_MASTER;
  SELECT MAX(DOCTOR_ID) INTO v_doc_2 FROM HMS_DOCTOR_MASTER;

  -- Ensure they are different (edge case where only 1 doc exists)
  IF v_doc_1 = v_doc_2 THEN
    INSERT INTO HMS_DOCTOR_MASTER
      (DOCTOR_ID, FULL_NAME, MOBILE_NO, CONSULTATION_FEE, IS_ACTIVE)
    VALUES
      (SEQ_DOCTOR_ID.NEXTVAL, 'Dr. Test Extra', '9000000003', 800, 'Y');
    SELECT MAX(DOCTOR_ID) INTO v_doc_2 FROM HMS_DOCTOR_MASTER;
    COMMIT;
  END IF;

  DBMS_OUTPUT.PUT_LINE('Using Doctor IDs: ' || v_doc_1 || ' and ' ||
                       v_doc_2);

  -- 3. Cleanup Old Schedules for these doctors (Prevent Duplicates)
  DELETE FROM OPD_APPOINTMENTS WHERE DOCTOR_ID IN (v_doc_1, v_doc_2);
  DELETE FROM OPD_SCHEDULE_MASTER WHERE DOCTOR_ID IN (v_doc_1, v_doc_2);
  COMMIT;

  -- 4. Setup Rules
  PKG_APPOINTMENT_ENGINE.PRC_ADD_SCHEDULE(v_doc_1, 'MON', '09:00', '13:00');
  PKG_APPOINTMENT_ENGINE.PRC_ADD_SCHEDULE(v_doc_1, 'WED', '09:00', '13:00');
  PKG_APPOINTMENT_ENGINE.PRC_ADD_SCHEDULE(v_doc_1, 'FRI', '09:00', '13:00');

  PKG_APPOINTMENT_ENGINE.PRC_ADD_SCHEDULE(v_doc_2, 'TUE', '14:00', '18:00');
  PKG_APPOINTMENT_ENGINE.PRC_ADD_SCHEDULE(v_doc_2, 'THU', '14:00', '18:00');

  DBMS_OUTPUT.PUT_LINE('Schedule Configuration Complete.');

  -- 5. Book Test Appointments (Next MONDAY)
  DECLARE
    v_target_date DATE := NEXT_DAY(SYSDATE, 'MONDAY');
    v_slot_time   VARCHAR2(5);
  BEGIN
    -- Book 3 Slots
    FOR i IN 0 .. 2 LOOP
      v_slot_time := TO_CHAR(TO_DATE('09:00', 'HH24:MI') + (i * 15 / 1440),
                             'HH24:MI');
      v_uhid      := get_random_uhid();
    
      PKG_APPOINTMENT_ENGINE.PRC_BOOK_APPOINTMENT(p_uhid       => v_uhid,
                                                  p_doctor_id  => v_doc_1,
                                                  p_req_date   => v_target_date,
                                                  p_req_time   => v_slot_time,
                                                  p_app_no_out => v_app,
                                                  p_token_out  => v_tok);
    
      DBMS_OUTPUT.PUT_LINE('Success: ' || v_app || ' for ' || v_slot_time);
    END LOOP;
  END;
END;


-- *****************************************************************************
-- MODULE 3: IPD & RESOURCE STATE MACHINE
-- *****************************************************************************

-- 1. CLEANUP
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ADT_BED_MOVEMENT_LOG CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE ADT_ADMISSIONS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE ADT_BED_MASTER CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE ADT_WARD_MASTER CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_ADMISSION_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_WARD_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_BED_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_LOG_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;


-- 2. SEQUENCES
CREATE SEQUENCE SEQ_ADMISSION_ID START WITH 200000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_WARD_ID START WITH 10 INCREMENT BY 10 NOCACHE;
CREATE SEQUENCE SEQ_BED_ID START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_LOG_ID START WITH 500000 INCREMENT BY 1 NOCACHE;

-- 3. WARD MASTER
CREATE TABLE ADT_WARD_MASTER (
    WARD_ID           NUMBER(5) PRIMARY KEY,
    WARD_NAME         VARCHAR2(50) NOT NULL,
    WARD_TYPE         VARCHAR2(20) CHECK (WARD_TYPE IN ('CRITICAL', 'GENERAL', 'PRIVATE')),
    BASE_COST_PER_DAY NUMBER(10,2) NOT NULL,
    IS_ACTIVE         CHAR(1) DEFAULT 'Y'
);

-- Trigger for Ward ID
CREATE OR REPLACE TRIGGER TRG_WARD_ID_GEN
BEFORE INSERT ON ADT_WARD_MASTER FOR EACH ROW
BEGIN
    IF :NEW.WARD_ID IS NULL THEN
        SELECT SEQ_WARD_ID.NEXTVAL INTO :NEW.WARD_ID FROM DUAL;
    END IF;
END;


-- 4. BED MASTER (The Asset)
CREATE TABLE ADT_BED_MASTER (
    BED_ID            NUMBER(10) PRIMARY KEY, 
    BED_NUMBER        VARCHAR2(10) UNIQUE NOT NULL, 
    WARD_ID           NUMBER(5) NOT NULL REFERENCES ADT_WARD_MASTER(WARD_ID),
    CURRENT_STATUS    VARCHAR2(20) DEFAULT 'VACANT' 
                      CONSTRAINT CHK_BED_STATUS CHECK (CURRENT_STATUS IN ('VACANT', 'OCCUPIED', 'HOUSEKEEPING', 'MAINTENANCE')),
    LAST_UPDATED_BY   VARCHAR2(50),
    LAST_UPDATE_DATE  DATE
);

-- Trigger for Bed ID
CREATE OR REPLACE TRIGGER TRG_BED_ID_GEN
BEFORE INSERT ON ADT_BED_MASTER FOR EACH ROW
BEGIN
    IF :NEW.BED_ID IS NULL THEN
        SELECT SEQ_BED_ID.NEXTVAL INTO :NEW.BED_ID FROM DUAL;
    END IF;
END;


-- 5. ADMISSIONS (The Stay)
CREATE TABLE ADT_ADMISSIONS (
    ADMISSION_ID      NUMBER(18) PRIMARY KEY,
    ADMISSION_NO      VARCHAR2(20) UNIQUE NOT NULL,
    PATIENT_ID        NUMBER(10) NOT NULL REFERENCES HMS_PATIENT_MASTER(PATIENT_ID),
    DOCTOR_ID         NUMBER(10) NOT NULL REFERENCES HMS_DOCTOR_MASTER(DOCTOR_ID),
    ADMISSION_DATE    DATE DEFAULT SYSDATE NOT NULL,
    DISCHARGE_DATE    DATE, 
    ADMISSION_TYPE    VARCHAR2(20) CHECK (ADMISSION_TYPE IN ('EMERGENCY', 'PLANNED')),
    STATUS            VARCHAR2(20) DEFAULT 'ADMITTED' CHECK (STATUS IN ('ADMITTED', 'DISCHARGED')),
    -- Audit
    CREATED_BY        VARCHAR2(50),
    CREATION_DATE     DATE DEFAULT SYSDATE,
    LAST_UPDATE_DATE  DATE
);

-- 6. BED MOVEMENT LOG (The Immutable Billing Ledger)
CREATE TABLE ADT_BED_MOVEMENT_LOG (
    LOG_ID            NUMBER(18) PRIMARY KEY, 
    ADMISSION_ID      NUMBER(18) NOT NULL REFERENCES ADT_ADMISSIONS(ADMISSION_ID),
    BED_ID            NUMBER(10) NOT NULL REFERENCES ADT_BED_MASTER(BED_ID),
    CHECK_IN_TIME     DATE NOT NULL,
    CHECK_OUT_TIME    DATE, 
    COST_PER_DAY      NUMBER(10,2), 
    CREATED_BY        VARCHAR2(50)
);

-- Trigger for Log ID
CREATE OR REPLACE TRIGGER TRG_LOG_ID_GEN
BEFORE INSERT ON ADT_BED_MOVEMENT_LOG FOR EACH ROW
BEGIN
    IF :NEW.LOG_ID IS NULL THEN
        SELECT SEQ_LOG_ID.NEXTVAL INTO :NEW.LOG_ID FROM DUAL;
    END IF;
END;


-- Indexes for performance
CREATE INDEX IDX_BED_WARD ON ADT_BED_MASTER(WARD_ID);
CREATE INDEX IDX_ADM_PAT ON ADT_ADMISSIONS(PATIENT_ID);
CREATE INDEX IDX_LOG_ADM ON ADT_BED_MOVEMENT_LOG(ADMISSION_ID);

-- 7. AUDIT TRIGGERS
CREATE OR REPLACE TRIGGER TRG_ADM_AUDIT
BEFORE INSERT OR UPDATE ON ADT_ADMISSIONS
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        :NEW.CREATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
        :NEW.CREATION_DATE := SYSDATE;
    END IF;
    :NEW.LAST_UPDATE_DATE := SYSDATE;
END;


CREATE OR REPLACE TRIGGER TRG_BED_AUDIT
BEFORE UPDATE ON ADT_BED_MASTER
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_BY := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
    :NEW.LAST_UPDATE_DATE := SYSDATE;
END;

-- 8: THE STATE MACHINE PACKAGE
CREATE OR REPLACE PACKAGE PKG_IPD_ADMISSION IS
  PROCEDURE PRC_ADD_BED(p_ward_id IN NUMBER, p_bed_num IN VARCHAR2);

  PROCEDURE PRC_ADMIT_PATIENT(p_uhid       IN VARCHAR2,
                              p_doctor_id  IN NUMBER,
                              p_bed_id     IN NUMBER,
                              p_adm_type   IN VARCHAR2,
                              p_adm_no_out OUT VARCHAR2);

  PROCEDURE PRC_TRANSFER_BED(p_admission_id IN NUMBER,
                             p_new_bed_id   IN NUMBER);

  PROCEDURE PRC_COMPLETE_CLEANING(p_bed_id IN NUMBER);
END PKG_IPD_ADMISSION;


CREATE OR REPLACE PACKAGE BODY PKG_IPD_ADMISSION IS
  -- 1. Helper to setup beds
  PROCEDURE PRC_ADD_BED(p_ward_id IN NUMBER, p_bed_num IN VARCHAR2) IS
  BEGIN
    INSERT INTO ADT_BED_MASTER
      (BED_NUMBER, WARD_ID)
    VALUES
      (p_bed_num, p_ward_id);
  END PRC_ADD_BED;

  -- 2. ADMIT (Locks the Bed)
  PROCEDURE PRC_ADMIT_PATIENT(p_uhid       IN VARCHAR2,
                              p_doctor_id  IN NUMBER,
                              p_bed_id     IN NUMBER,
                              p_adm_type   IN VARCHAR2,
                              p_adm_no_out OUT VARCHAR2) IS
    v_pat_id     NUMBER;
    v_bed_status VARCHAR2(20);
    v_bed_cost   NUMBER;
    v_adm_seq    NUMBER;
    v_adm_no     VARCHAR2(20);
  BEGIN
    -- Find Patient
    BEGIN
      SELECT PATIENT_ID
        INTO v_pat_id
        FROM HMS_PATIENT_MASTER
       WHERE UHID = p_uhid;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20021, 'Patient UHID not found.');
    END;
  
    -- PESSIMISTIC LOCK: Lock Bed Row to prevent concurrent booking
    BEGIN
      SELECT CURRENT_STATUS, w.BASE_COST_PER_DAY
        INTO v_bed_status, v_bed_cost
        FROM ADT_BED_MASTER b
        JOIN ADT_WARD_MASTER w
          ON b.WARD_ID = w.WARD_ID
       WHERE b.BED_ID = p_bed_id
         FOR UPDATE OF b.CURRENT_STATUS;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20022, 'Bed ID not found.');
    END;
  
    -- Check State
    IF v_bed_status != 'VACANT' THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20020,
                              'Bed ' || p_bed_id ||
                              ' is not VACANT. Status: ' || v_bed_status);
    END IF;
  
    -- Generate ID
    SELECT SEQ_ADMISSION_ID.NEXTVAL INTO v_adm_seq FROM DUAL;
    v_adm_no := 'IPD-' || TO_CHAR(SYSDATE, 'YYYY') || '-' || v_adm_seq;
  
    -- Insert Header
    INSERT INTO ADT_ADMISSIONS
      (ADMISSION_ID, ADMISSION_NO, PATIENT_ID, DOCTOR_ID, ADMISSION_TYPE)
    VALUES
      (v_adm_seq, v_adm_no, v_pat_id, p_doctor_id, p_adm_type);
  
    -- Update Bed State
    UPDATE ADT_BED_MASTER
       SET CURRENT_STATUS = 'OCCUPIED'
     WHERE BED_ID = p_bed_id;
  
    -- Start Billing Log
    INSERT INTO ADT_BED_MOVEMENT_LOG
      (ADMISSION_ID, BED_ID, CHECK_IN_TIME, COST_PER_DAY, CREATED_BY)
    VALUES
      (v_adm_seq, p_bed_id, SYSDATE, v_bed_cost, USER);
  
    p_adm_no_out := v_adm_no;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END PRC_ADMIT_PATIENT;

  -- 3. TRANSFER (Switch Beds)
  PROCEDURE PRC_TRANSFER_BED(p_admission_id IN NUMBER,
                             p_new_bed_id   IN NUMBER) IS
    v_old_bed_id NUMBER;
    v_new_status VARCHAR2(20);
    v_new_cost   NUMBER;
    v_adm_status VARCHAR2(20);
  BEGIN
    -- Validate Admission is Active
    SELECT STATUS
      INTO v_adm_status
      FROM ADT_ADMISSIONS
     WHERE ADMISSION_ID = p_admission_id;
    IF v_adm_status = 'DISCHARGED' THEN
      RAISE_APPLICATION_ERROR(-20025,
                              'Cannot transfer a Discharged patient.');
    END IF;
  
    -- Identify Current Bed (Active Log)
    SELECT BED_ID
      INTO v_old_bed_id
      FROM ADT_BED_MOVEMENT_LOG
     WHERE ADMISSION_ID = p_admission_id
       AND CHECK_OUT_TIME IS NULL;
  
    -- Lock & Validate NEW Bed
    SELECT CURRENT_STATUS, w.BASE_COST_PER_DAY
      INTO v_new_status, v_new_cost
      FROM ADT_BED_MASTER b
      JOIN ADT_WARD_MASTER w
        ON b.WARD_ID = w.WARD_ID
     WHERE b.BED_ID = p_new_bed_id
       FOR UPDATE OF b.CURRENT_STATUS;
  
    IF v_new_status != 'VACANT' THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20022, 'Target Bed is not VACANT.');
    END IF;
  
    -- Close Old Log
    UPDATE ADT_BED_MOVEMENT_LOG
       SET CHECK_OUT_TIME = SYSDATE
     WHERE ADMISSION_ID = p_admission_id
       AND CHECK_OUT_TIME IS NULL;
  
    -- Update Old Bed -> Housekeeping (Standard Hospital Protocol)
    UPDATE ADT_BED_MASTER
       SET CURRENT_STATUS = 'HOUSEKEEPING'
     WHERE BED_ID = v_old_bed_id;
  
    -- Update New Bed -> Occupied
    UPDATE ADT_BED_MASTER
       SET CURRENT_STATUS = 'OCCUPIED'
     WHERE BED_ID = p_new_bed_id;
  
    -- Open New Log
    INSERT INTO ADT_BED_MOVEMENT_LOG
      (ADMISSION_ID, BED_ID, CHECK_IN_TIME, COST_PER_DAY, CREATED_BY)
    VALUES
      (p_admission_id, p_new_bed_id, SYSDATE, v_new_cost, USER);
  
    COMMIT;
  END PRC_TRANSFER_BED;

  -- 4. CLEAN (Housekeeping)
  PROCEDURE PRC_COMPLETE_CLEANING(p_bed_id IN NUMBER) IS
  BEGIN
    UPDATE ADT_BED_MASTER
       SET CURRENT_STATUS = 'VACANT'
     WHERE BED_ID = p_bed_id
       AND CURRENT_STATUS = 'HOUSEKEEPING';
  
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20023,
                              'Action Failed: Bed is not in HOUSEKEEPING status.');
    END IF;
    COMMIT;
  END PRC_COMPLETE_CLEANING;

END PKG_IPD_ADMISSION;

-- 9: DATA SIMULATION 
DECLARE
  v_icu_id  NUMBER;
  v_gen_id  NUMBER;
  v_bed_icu NUMBER;
  v_bed_gen NUMBER;
  v_doc_id  NUMBER;
  v_uhid    VARCHAR2(20);
  v_adm_no  VARCHAR2(20);
  v_adm_id  NUMBER;
  v_count   NUMBER;

  -- Helper to get random patient
  FUNCTION get_uhid RETURN VARCHAR2 IS
    v_res VARCHAR2(20);
  BEGIN
    SELECT UHID
      INTO v_res
      FROM (SELECT UHID FROM HMS_PATIENT_MASTER ORDER BY DBMS_RANDOM.VALUE)
     WHERE ROWNUM = 1;
    RETURN v_res;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- If no patients, create one on the fly
      INSERT INTO HMS_PATIENT_MASTER
        (PATIENT_ID,
         UHID,
         FIRST_NAME,
         LAST_NAME,
         DATE_OF_BIRTH,
         GENDER,
         MOBILE_NO,
         REGISTERED_DATE)
      VALUES
        (SEQ_PATIENT_ID.NEXTVAL,
         'PAT-TEST-IPD',
         'Test',
         'Patient',
         SYSDATE - 10000,
         'M',
         '8888888888',
         SYSDATE);
      COMMIT;
      RETURN 'PAT-TEST-IPD';
  END;
BEGIN
  -- 0. Safety Check for Doctor
  SELECT COUNT(1) INTO v_count FROM HMS_DOCTOR_MASTER;
  IF v_count = 0 THEN
    INSERT INTO HMS_DOCTOR_MASTER
      (DOCTOR_ID, FULL_NAME, MOBILE_NO, CONSULTATION_FEE, IS_ACTIVE)
    VALUES
      (SEQ_DOCTOR_ID.NEXTVAL, 'Dr. IPD Test', '7000000001', 500, 'Y');
    COMMIT;
  END IF;

  -- 1. Setup Wards
  INSERT INTO ADT_WARD_MASTER
    (WARD_NAME, WARD_TYPE, BASE_COST_PER_DAY)
  VALUES
    ('ICU', 'CRITICAL', 15000)
  RETURNING WARD_ID INTO v_icu_id;
  INSERT INTO ADT_WARD_MASTER
    (WARD_NAME, WARD_TYPE, BASE_COST_PER_DAY)
  VALUES
    ('General', 'GENERAL', 2000)
  RETURNING WARD_ID INTO v_gen_id;

  -- 2. Setup Beds
  INSERT INTO ADT_BED_MASTER
    (BED_NUMBER, WARD_ID)
  VALUES
    ('ICU-99', v_icu_id)
  RETURNING BED_ID INTO v_bed_icu;
  INSERT INTO ADT_BED_MASTER
    (BED_NUMBER, WARD_ID)
  VALUES
    ('GEN-99', v_gen_id)
  RETURNING BED_ID INTO v_bed_gen;
  COMMIT;

  -- 3. Admit Patient
  v_uhid := get_uhid();
  SELECT MIN(DOCTOR_ID) INTO v_doc_id FROM HMS_DOCTOR_MASTER;

  PKG_IPD_ADMISSION.PRC_ADMIT_PATIENT(v_uhid,
                                      v_doc_id,
                                      v_bed_icu,
                                      'EMERGENCY',
                                      v_adm_no);
  DBMS_OUTPUT.PUT_LINE('Admitted: ' || v_adm_no || ' to ICU.');

  -- 4. Transfer Patient (ICU -> GEN)
  SELECT ADMISSION_ID
    INTO v_adm_id
    FROM ADT_ADMISSIONS
   WHERE ADMISSION_NO = v_adm_no;

  PKG_IPD_ADMISSION.PRC_TRANSFER_BED(v_adm_id, v_bed_gen);
  DBMS_OUTPUT.PUT_LINE('Transferred to General Bed.');

  -- 5. Clean Old Bed
  PKG_IPD_ADMISSION.PRC_COMPLETE_CLEANING(v_bed_icu);
  DBMS_OUTPUT.PUT_LINE('ICU Bed Cleaned.');
END;

commit ;

-- *****************************************************************************
-- MODULE 4: PHARMACY & FEFO INVENTORY ENGINE
-- *****************************************************************************

-- 1. CLEANUP
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE INV_MATERIAL_TRANSACTIONS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE INV_ITEM_BATCHES CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE INV_ITEM_MASTER CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_TRANS_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_BATCH_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_ITEM_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;


-- 2. SEQUENCES
CREATE SEQUENCE SEQ_TRANS_ID START WITH 500000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_BATCH_ID START WITH 10000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_ITEM_ID START WITH 1000 INCREMENT BY 1 NOCACHE; 

-- 3. ITEM MASTER
CREATE TABLE INV_ITEM_MASTER (
    ITEM_ID           NUMBER(10) PRIMARY KEY,
    ITEM_CODE         VARCHAR2(20) UNIQUE NOT NULL, 
    ITEM_NAME         VARCHAR2(100) NOT NULL,
    GENERIC_NAME      VARCHAR2(100),
    UOM               VARCHAR2(10) NOT NULL,
    REORDER_LEVEL     NUMBER(5) DEFAULT 50,
    IS_ACTIVE         CHAR(1) DEFAULT 'Y',
    CREATED_BY        VARCHAR2(50),
    CREATION_DATE     DATE DEFAULT SYSDATE
);

-- Trigger for Item ID
CREATE OR REPLACE TRIGGER TRG_ITEM_ID
BEFORE INSERT ON INV_ITEM_MASTER FOR EACH ROW
BEGIN
    IF :NEW.ITEM_ID IS NULL THEN
        SELECT SEQ_ITEM_ID.NEXTVAL INTO :NEW.ITEM_ID FROM DUAL;
    END IF;
END;


-- 4. BATCH INVENTORY
CREATE TABLE INV_ITEM_BATCHES (
    BATCH_ID          NUMBER(10) PRIMARY KEY,
    BATCH_NO          VARCHAR2(50) NOT NULL,
    ITEM_ID           NUMBER(10) NOT NULL REFERENCES INV_ITEM_MASTER(ITEM_ID),
    EXPIRY_DATE       DATE NOT NULL,
    CURRENT_QTY       NUMBER(10) DEFAULT 0 CHECK (CURRENT_QTY >= 0), 
    PURCHASE_RATE     NUMBER(10,2), 
    MRP               NUMBER(10,2), 
    -- Audit
    RECEIVED_DATE     DATE DEFAULT SYSDATE,
    LAST_UPDATED_DATE DATE,
    CONSTRAINT UK_ITEM_BATCH UNIQUE (ITEM_ID, BATCH_NO)
);

-- 5. STOCK LEDGER (The Immutable Audit Trail)
CREATE TABLE INV_MATERIAL_TRANSACTIONS (
    TRANS_ID          NUMBER(18) PRIMARY KEY,
    TRANS_DATE        DATE DEFAULT SYSDATE,
    TRANS_TYPE        VARCHAR2(20) CHECK (TRANS_TYPE IN ('GRN', 'ISSUE', 'RETURN')),
    ITEM_ID           NUMBER(10) REFERENCES INV_ITEM_MASTER(ITEM_ID),
    BATCH_ID          NUMBER(10) REFERENCES INV_ITEM_BATCHES(BATCH_ID),
    QTY               NUMBER(10) NOT NULL, 
    SOURCE_REF_ID     NUMBER(18), 
    REMARKS           VARCHAR2(255),
    CREATED_BY        VARCHAR2(50)
);

-- Index for FEFO Speed (Earliest Expiry First)
CREATE INDEX IDX_BATCH_EXPIRY ON INV_ITEM_BATCHES(ITEM_ID, EXPIRY_DATE ASC);

-- 6: AUDIT TRIGGERS
CREATE OR REPLACE TRIGGER TRG_BATCH_AUDIT
BEFORE UPDATE ON INV_ITEM_BATCHES
FOR EACH ROW
BEGIN
    :NEW.LAST_UPDATED_DATE := SYSDATE;
END;

-- 7: THE FEFO LOGIC PACKAGE
CREATE OR REPLACE PACKAGE PKG_PHARMACY_ENGINE IS
  -- Inward Stock (GRN)
  PROCEDURE PRC_RECEIVE_STOCK(p_item_id  IN NUMBER,
                              p_batch_no IN VARCHAR2,
                              p_expiry   IN DATE,
                              p_qty      IN NUMBER,
                              p_rate     IN NUMBER,
                              p_mrp      IN NUMBER);
  -- Outward Stock (FEFO Algorithm)
  PROCEDURE PRC_ISSUE_MEDICINE(p_item_id   IN NUMBER,
                               p_req_qty   IN NUMBER,
                               p_ref_id    IN NUMBER,
                               p_issue_log OUT VARCHAR2);
END PKG_PHARMACY_ENGINE;


CREATE OR REPLACE PACKAGE BODY PKG_PHARMACY_ENGINE IS
  -- 1. RECEIVE STOCK (UPSERT Logic)
  PROCEDURE PRC_RECEIVE_STOCK(p_item_id  IN NUMBER,
                              p_batch_no IN VARCHAR2,
                              p_expiry   IN DATE,
                              p_qty      IN NUMBER,
                              p_rate     IN NUMBER,
                              p_mrp      IN NUMBER) IS
    v_batch_id NUMBER;
  BEGIN
    -- Attempt to update existing batch
    UPDATE INV_ITEM_BATCHES
       SET CURRENT_QTY = CURRENT_QTY + p_qty, LAST_UPDATED_DATE = SYSDATE
     WHERE ITEM_ID = p_item_id
       AND BATCH_NO = p_batch_no
    RETURNING BATCH_ID INTO v_batch_id;
  
    -- If not found, create new batch
    IF SQL%ROWCOUNT = 0 THEN
      SELECT SEQ_BATCH_ID.NEXTVAL INTO v_batch_id FROM DUAL;
    
      INSERT INTO INV_ITEM_BATCHES
        (BATCH_ID,
         BATCH_NO,
         ITEM_ID,
         EXPIRY_DATE,
         CURRENT_QTY,
         PURCHASE_RATE,
         MRP)
      VALUES
        (v_batch_id, p_batch_no, p_item_id, p_expiry, p_qty, p_rate, p_mrp);
    END IF;
  
    -- Audit Log
    INSERT INTO INV_MATERIAL_TRANSACTIONS
      (TRANS_ID, TRANS_TYPE, ITEM_ID, BATCH_ID, QTY, REMARKS, CREATED_BY)
    VALUES
      (SEQ_TRANS_ID.NEXTVAL,
       'GRN',
       p_item_id,
       v_batch_id,
       p_qty,
       'Opening Stock',
       USER);
  
    COMMIT;
  END PRC_RECEIVE_STOCK;

  -- 2. ISSUE MEDICINE (FEFO Algorithm)
  PROCEDURE PRC_ISSUE_MEDICINE(p_item_id   IN NUMBER,
                               p_req_qty   IN NUMBER,
                               p_ref_id    IN NUMBER,
                               p_issue_log OUT VARCHAR2) IS
    -- Cursor: Get available batches sorted by Expiry Date (Ascending)
    CURSOR c_batches IS
      SELECT BATCH_ID, BATCH_NO, CURRENT_QTY, EXPIRY_DATE
        FROM INV_ITEM_BATCHES
       WHERE ITEM_ID = p_item_id
         AND CURRENT_QTY > 0
         AND EXPIRY_DATE > SYSDATE
       ORDER BY EXPIRY_DATE ASC
         FOR UPDATE;
  
    v_remaining_qty NUMBER := p_req_qty;
    v_deduct_qty    NUMBER;
    v_log_str       VARCHAR2(4000) := '';
  BEGIN
    FOR rec IN c_batches LOOP
      EXIT WHEN v_remaining_qty <= 0;
    
      -- Determine deduction amount
      IF rec.CURRENT_QTY >= v_remaining_qty THEN
        v_deduct_qty := v_remaining_qty;
      ELSE
        v_deduct_qty := rec.CURRENT_QTY;
      END IF;
    
      -- Deduct from Batch
      UPDATE INV_ITEM_BATCHES
         SET CURRENT_QTY = CURRENT_QTY - v_deduct_qty
       WHERE BATCH_ID = rec.BATCH_ID;
    
      -- Add to Ledger
      INSERT INTO INV_MATERIAL_TRANSACTIONS
        (TRANS_ID,
         TRANS_TYPE,
         ITEM_ID,
         BATCH_ID,
         QTY,
         SOURCE_REF_ID,
         REMARKS,
         CREATED_BY)
      VALUES
        (SEQ_TRANS_ID.NEXTVAL,
         'ISSUE',
         p_item_id,
         rec.BATCH_ID,
         -v_deduct_qty,
         p_ref_id,
         'Prescription Issue',
         USER);
    
      v_log_str       := v_log_str || 'Batch: ' || rec.BATCH_NO || ' (-' ||
                         v_deduct_qty || '); ';
      v_remaining_qty := v_remaining_qty - v_deduct_qty;
    END LOOP;
  
    IF v_remaining_qty > 0 THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20030,
                              'Insufficient Stock! Shortage: ' ||
                              v_remaining_qty);
    END IF;
  
    p_issue_log := v_log_str;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END PRC_ISSUE_MEDICINE;

END PKG_PHARMACY_ENGINE;


-- 8: FEFO SIMULATION
DECLARE
  v_item_id NUMBER;
  v_log     VARCHAR2(4000);
  v_sku     VARCHAR2(20);
BEGIN
  -- Generate unique SKU to avoid unique constraint errors during multiple runs
  v_sku := 'MED-PARA-' || TO_CHAR(SYSDATE, 'HH24MI');

  -- 1. Create Product
  INSERT INTO INV_ITEM_MASTER
    (ITEM_CODE, ITEM_NAME, UOM)
  VALUES
    (v_sku, 'Paracetamol 500mg', 'STRIP')
  RETURNING ITEM_ID INTO v_item_id;

  DBMS_OUTPUT.PUT_LINE('Created Product ID: ' || v_item_id);

  -- 2. Receive Batch A (Expires Jan 2026) - 10 Qty (OLDER - Should go first)
  PKG_PHARMACY_ENGINE.PRC_RECEIVE_STOCK(p_item_id  => v_item_id,
                                        p_batch_no => 'BATCH-OLD',
                                        p_expiry   => TO_DATE('2026-01-01',
                                                              'YYYY-MM-DD'),
                                        p_qty      => 10,
                                        p_rate     => 10,
                                        p_mrp      => 20);

  -- 3. Receive Batch B (Expires Dec 2026) - 50 Qty (NEWER - Should go second)
  PKG_PHARMACY_ENGINE.PRC_RECEIVE_STOCK(p_item_id  => v_item_id,
                                        p_batch_no => 'BATCH-NEW',
                                        p_expiry   => TO_DATE('2026-12-31',
                                                              'YYYY-MM-DD'),
                                        p_qty      => 50,
                                        p_rate     => 12,
                                        p_mrp      => 25);

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Inventory Loaded. Testing FEFO logic...');

  -- 4. Issue 15 Units
  -- Correct Logic: Should take 10 from BATCH-OLD, then 5 from BATCH-NEW.
  PKG_PHARMACY_ENGINE.PRC_ISSUE_MEDICINE(p_item_id   => v_item_id,
                                         p_req_qty   => 15,
                                         p_ref_id    => 1001,
                                         p_issue_log => v_log);

  DBMS_OUTPUT.PUT_LINE('FEFO Allocation Result: ' || v_log);
END;

commit ;


-- *****************************************************************************
-- MODULE 5: FINANCIAL AGGREGATOR (BILLING & INSURANCE)
-- *****************************************************************************

-- 1. CLEANUP
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE FIN_INSURANCE_CLAIMS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE FIN_BILL_DETAILS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE FIN_BILL_HEADERS CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE FIN_TARIFF_MASTER CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_BILL_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_CLAIM_ID';
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_TARIFF_ID'; 
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_DETAIL_ID'; 
EXCEPTION WHEN OTHERS THEN NULL;
END;


-- 2. SEQUENCES
CREATE SEQUENCE SEQ_BILL_ID START WITH 900000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CLAIM_ID START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TARIFF_ID START WITH 100 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_DETAIL_ID START WITH 1000000 INCREMENT BY 1 NOCACHE;

-- 3. TARIFF MASTER
CREATE TABLE FIN_TARIFF_MASTER (
    SERVICE_ID        NUMBER(10) PRIMARY KEY, 
    SERVICE_CODE      VARCHAR2(20) UNIQUE NOT NULL,
    SERVICE_NAME      VARCHAR2(100) NOT NULL,
    CHARGE_AMOUNT     NUMBER(10,2) NOT NULL CHECK (CHARGE_AMOUNT >= 0),
    EFFECTIVE_FROM    DATE DEFAULT SYSDATE,
    EFFECTIVE_TO      DATE,
    IS_ACTIVE         CHAR(1) DEFAULT 'Y'
);

-- Trigger for Tariff ID
CREATE OR REPLACE TRIGGER TRG_TARIFF_ID
BEFORE INSERT ON FIN_TARIFF_MASTER FOR EACH ROW
BEGIN
    IF :NEW.SERVICE_ID IS NULL THEN
        SELECT SEQ_TARIFF_ID.NEXTVAL INTO :NEW.SERVICE_ID FROM DUAL;
    END IF;
END;


-- 4. BILL HEADER
CREATE TABLE FIN_BILL_HEADERS (
    BILL_ID           NUMBER(18) PRIMARY KEY,
    BILL_NO           VARCHAR2(20) UNIQUE NOT NULL,
    PATIENT_ID        NUMBER(10) NOT NULL REFERENCES HMS_PATIENT_MASTER(PATIENT_ID),
    ADMISSION_ID      NUMBER(18) REFERENCES ADT_ADMISSIONS(ADMISSION_ID), 
    BILL_DATE         DATE DEFAULT SYSDATE NOT NULL,
    TOTAL_AMOUNT      NUMBER(12,2) DEFAULT 0,
    DISCOUNT_AMOUNT   NUMBER(12,2) DEFAULT 0,
    NET_PAYABLE       NUMBER(12,2) DEFAULT 0,
    PAYMENT_STATUS    VARCHAR2(20) DEFAULT 'PENDING' CHECK (PAYMENT_STATUS IN ('PENDING', 'PARTIAL', 'PAID', 'CLAIM_SUBMITTED')),
    -- Audit
    CREATED_BY        VARCHAR2(50),
    CREATION_DATE     DATE DEFAULT SYSDATE
);

-- 5. BILL DETAILS (Line Items)
CREATE TABLE FIN_BILL_DETAILS (
    DETAIL_ID         NUMBER(18) PRIMARY KEY, 
    BILL_ID           NUMBER(18) NOT NULL REFERENCES FIN_BILL_HEADERS(BILL_ID),
    SERVICE_TYPE      VARCHAR2(20) CHECK (SERVICE_TYPE IN ('OPD', 'BED_CHARGE', 'PHARMACY', 'PROCEDURE')),
    ITEM_DESCRIPTION  VARCHAR2(200) NOT NULL,
    QTY               NUMBER(10,2) NOT NULL CHECK (QTY > 0),
    UNIT_PRICE        NUMBER(10,2) NOT NULL CHECK (UNIT_PRICE >= 0),
    TOTAL_PRICE       NUMBER(12,2) NOT NULL,
    SOURCE_REF_ID     NUMBER(18) 
);

-- Trigger for Bill Detail ID
CREATE OR REPLACE TRIGGER TRG_DETAIL_ID
BEFORE INSERT ON FIN_BILL_DETAILS FOR EACH ROW
BEGIN
    IF :NEW.DETAIL_ID IS NULL THEN
        SELECT SEQ_DETAIL_ID.NEXTVAL INTO :NEW.DETAIL_ID FROM DUAL;
    END IF;
END;


-- 6. INSURANCE CLAIMS (Payer Logic)
CREATE TABLE FIN_INSURANCE_CLAIMS (
    CLAIM_ID          NUMBER(18) PRIMARY KEY,
    CLAIM_NO          VARCHAR2(20) UNIQUE NOT NULL, 
    BILL_ID           NUMBER(18) NOT NULL REFERENCES FIN_BILL_HEADERS(BILL_ID),
    POLICY_NUMBER     VARCHAR2(50),
    CLAIM_STATUS      VARCHAR2(20) DEFAULT 'SUBMITTED' CHECK (CLAIM_STATUS IN ('SUBMITTED', 'APPROVED', 'REJECTED')),
    CLAIMED_AMOUNT    NUMBER(12,2) NOT NULL,
    APPROVED_AMOUNT   NUMBER(12,2) DEFAULT 0,
    DEDUCTION_REASON  VARCHAR2(255),
    -- Audit
    SUBMITTED_DATE    DATE DEFAULT SYSDATE,
    PROCESSED_DATE    DATE
);

-- Indexes
CREATE INDEX IDX_BILL_PATIENT ON FIN_BILL_HEADERS(PATIENT_ID);
CREATE INDEX IDX_CLAIM_BILL ON FIN_INSURANCE_CLAIMS(BILL_ID);


-- 7: AUDIT TRIGGERS
CREATE OR REPLACE TRIGGER TRG_BILL_AUDIT
  BEFORE INSERT ON FIN_BILL_HEADERS
  FOR EACH ROW
BEGIN
  :NEW.CREATED_BY    := NVL(SYS_CONTEXT('USERENV', 'OS_USER'), USER);
  :NEW.CREATION_DATE := SYSDATE;
END;


-- 8: THE BILLING ENGINE PACKAGE
CREATE OR REPLACE PACKAGE PKG_BILLING_ENGINE IS
  -- Setup Price List
  PROCEDURE PRC_ADD_TARIFF(p_code IN VARCHAR2,
                           p_name IN VARCHAR2,
                           p_cost IN NUMBER);

  -- Core: Generate Bill (Aggregates Mod 3 & 4)
  PROCEDURE PRC_GENERATE_IPD_BILL(p_admission_id IN NUMBER,
                                  p_bill_no_out  OUT VARCHAR2);

  -- Workflow: Process Insurance Claim
  PROCEDURE PRC_PROCESS_CLAIM(p_claim_id     IN NUMBER,
                              p_approved_amt IN NUMBER,
                              p_status       IN VARCHAR2,
                              p_reason       IN VARCHAR2);
END PKG_BILLING_ENGINE;


CREATE OR REPLACE PACKAGE BODY PKG_BILLING_ENGINE IS
  -- 1. ADD TARIFF
  PROCEDURE PRC_ADD_TARIFF(p_code IN VARCHAR2,
                           p_name IN VARCHAR2,
                           p_cost IN NUMBER) IS
  BEGIN
    INSERT INTO FIN_TARIFF_MASTER
      (SERVICE_CODE, SERVICE_NAME, CHARGE_AMOUNT)
    VALUES
      (p_code, p_name, p_cost);
  END PRC_ADD_TARIFF;

  -- 2. GENERATE BILL (The Aggregator)
  PROCEDURE PRC_GENERATE_IPD_BILL(p_admission_id IN NUMBER,
                                  p_bill_no_out  OUT VARCHAR2) IS
    v_bill_id   NUMBER;
    v_bill_no   VARCHAR2(20);
    v_pat_id    NUMBER;
    v_total     NUMBER := 0;
    v_days      NUMBER;
    v_bed_total NUMBER;
  BEGIN
    -- Verify Admission Exists
    BEGIN
      SELECT PATIENT_ID
        INTO v_pat_id
        FROM ADT_ADMISSIONS
       WHERE ADMISSION_ID = p_admission_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20050, 'Admission ID not found.');
    END;
  
    -- Create Header (Draft State)
    SELECT SEQ_BILL_ID.NEXTVAL INTO v_bill_id FROM DUAL;
    v_bill_no := 'INV-' || TO_CHAR(SYSDATE, 'YYYY') || '-' || v_bill_id;
  
    INSERT INTO FIN_BILL_HEADERS
      (BILL_ID, BILL_NO, PATIENT_ID, ADMISSION_ID, BILL_DATE)
    VALUES
      (v_bill_id, v_bill_no, v_pat_id, p_admission_id, SYSDATE);
  
    -- A. AGGREGATE BED CHARGES (Module 3 Integration)
    FOR rec IN (SELECT BED_ID,
                       CHECK_IN_TIME,
                       NVL(CHECK_OUT_TIME, SYSDATE) AS END_TIME,
                       COST_PER_DAY
                  FROM ADT_BED_MOVEMENT_LOG
                 WHERE ADMISSION_ID = p_admission_id) LOOP
      -- Calculate duration (Partial day = 1 day logic)
      v_days      := GREATEST(1, CEIL(rec.END_TIME - rec.CHECK_IN_TIME));
      v_bed_total := v_days * rec.COST_PER_DAY;
    
      INSERT INTO FIN_BILL_DETAILS
        (BILL_ID,
         SERVICE_TYPE,
         ITEM_DESCRIPTION,
         QTY,
         UNIT_PRICE,
         TOTAL_PRICE,
         SOURCE_REF_ID)
      VALUES
        (v_bill_id,
         'BED_CHARGE',
         'Inpatient Bed Charges (Days)',
         v_days,
         rec.COST_PER_DAY,
         v_bed_total,
         rec.BED_ID);
    
      v_total := v_total + v_bed_total;
    END LOOP;
  
    -- B. AGGREGATE PHARMACY CHARGES (Module 4 Integration)
    FOR rec IN (SELECT t.ITEM_ID,
                       i.ITEM_NAME,
                       ABS(t.QTY) as QTY,
                       b.MRP,
                       t.TRANS_ID
                  FROM INV_MATERIAL_TRANSACTIONS t
                  JOIN INV_ITEM_MASTER i
                    ON t.ITEM_ID = i.ITEM_ID
                  JOIN INV_ITEM_BATCHES b
                    ON t.BATCH_ID = b.BATCH_ID
                 WHERE t.TRANS_TYPE = 'ISSUE'
                   AND t.SOURCE_REF_ID = p_admission_id) LOOP
      INSERT INTO FIN_BILL_DETAILS
        (BILL_ID,
         SERVICE_TYPE,
         ITEM_DESCRIPTION,
         QTY,
         UNIT_PRICE,
         TOTAL_PRICE,
         SOURCE_REF_ID)
      VALUES
        (v_bill_id,
         'PHARMACY',
         rec.ITEM_NAME,
         rec.QTY,
         rec.MRP,
         (rec.QTY * rec.MRP),
         rec.TRANS_ID);
    
      v_total := v_total + (rec.QTY * rec.MRP);
    END LOOP;
  
    -- Update Header Totals
    UPDATE FIN_BILL_HEADERS
       SET TOTAL_AMOUNT = v_total, NET_PAYABLE = v_total
     WHERE BILL_ID = v_bill_id;
  
    p_bill_no_out := v_bill_no;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END PRC_GENERATE_IPD_BILL;

  -- 3. PROCESS INSURANCE CLAIM
  PROCEDURE PRC_PROCESS_CLAIM(p_claim_id     IN NUMBER,
                              p_approved_amt IN NUMBER,
                              p_status       IN VARCHAR2,
                              p_reason       IN VARCHAR2) IS
    v_bill_id NUMBER;
    v_total   NUMBER;
  BEGIN
    -- Get Bill Info
    SELECT BILL_ID
      INTO v_bill_id
      FROM FIN_INSURANCE_CLAIMS
     WHERE CLAIM_ID = p_claim_id;
    SELECT TOTAL_AMOUNT
      INTO v_total
      FROM FIN_BILL_HEADERS
     WHERE BILL_ID = v_bill_id;
  
    -- Update Claim
    UPDATE FIN_INSURANCE_CLAIMS
       SET CLAIM_STATUS     = p_status,
           APPROVED_AMOUNT  = p_approved_amt,
           DEDUCTION_REASON = p_reason,
           PROCESSED_DATE   = SYSDATE
     WHERE CLAIM_ID = p_claim_id;
  
    -- Adjust Bill Header Logic
    IF p_status = 'APPROVED' THEN
      -- Patient pays the difference (Total - Insurance)
      UPDATE FIN_BILL_HEADERS
         SET NET_PAYABLE    = v_total - p_approved_amt,
             PAYMENT_STATUS = 'PARTIAL'
       WHERE BILL_ID = v_bill_id;
    END IF;
  
    COMMIT;
  END PRC_PROCESS_CLAIM;
END PKG_BILLING_ENGINE;


-- 9: END-TO-END SIMULATION
DECLARE
  v_adm_id  NUMBER;
  v_bill_no VARCHAR2(20);
  v_item_id NUMBER;
  v_check   NUMBER;

  --  Added a large variable to catch the long pharmacy log
  v_pharm_log VARCHAR2(4000);
BEGIN
  -- 0. Safety Check: Verify Admission Exists
  SELECT MAX(ADMISSION_ID) INTO v_adm_id FROM ADT_ADMISSIONS;

  IF v_adm_id IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('No Admission found. Cannot generate bill. Please Run Module 3 First.');
    RETURN;
  END IF;

  -- 1. Simulate a Pharmacy Purchase (If Mod 4 exists)
  SELECT COUNT(1) INTO v_check FROM INV_ITEM_MASTER;

  IF v_check > 0 THEN
    SELECT MIN(ITEM_ID) INTO v_item_id FROM INV_ITEM_MASTER;
  
    -- Issue 5 units linked to this Admission
    BEGIN
      PKG_PHARMACY_ENGINE.PRC_ISSUE_MEDICINE(p_item_id   => v_item_id,
                                             p_req_qty   => 5,
                                             p_ref_id    => v_adm_id,
                                             p_issue_log => v_pharm_log 
                                             );
      DBMS_OUTPUT.PUT_LINE('Simulated Pharmacy Issue for Admission ID: ' ||
                           v_adm_id);
      DBMS_OUTPUT.PUT_LINE('Pharmacy Log: ' || v_pharm_log); 
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Pharmacy Issue Failed: ' || SQLERRM);
    END;
  END IF;

  -- 2. GENERATE THE BILL
  PKG_BILLING_ENGINE.PRC_GENERATE_IPD_BILL(p_admission_id => v_adm_id,
                                           p_bill_no_out  => v_bill_no);
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Bill Generated: ' || v_bill_no);

  -- 3. PRINT BILL DETAILS (The Final Receipt)
  FOR rec IN (SELECT d.SERVICE_TYPE,
                     d.ITEM_DESCRIPTION,
                     d.QTY,
                     d.TOTAL_PRICE
                FROM FIN_BILL_DETAILS d
                JOIN FIN_BILL_HEADERS h
                  ON d.BILL_ID = h.BILL_ID
               WHERE h.BILL_NO = v_bill_no) LOOP
    DBMS_OUTPUT.PUT_LINE(' - ' || rec.SERVICE_TYPE || ': ' ||
                         rec.ITEM_DESCRIPTION || ' (Qty: ' || rec.QTY ||
                         ') = Rs.' || rec.TOTAL_PRICE);
  END LOOP;

  -- 4. PRINT GRAND TOTAL
  FOR rec IN (SELECT TOTAL_AMOUNT
                FROM FIN_BILL_HEADERS
               WHERE BILL_NO = v_bill_no) LOOP
    DBMS_OUTPUT.PUT_LINE('-------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('GRAND TOTAL: Rs.' || rec.TOTAL_AMOUNT);
    DBMS_OUTPUT.PUT_LINE('-------------------------------------------');
  END LOOP;

END;

commit ;
--
