--Package specification
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



--THE APPOINTMENT ENGINE PACKAGE
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



--THE STATE MACHINE PACKAGE
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



--THE FEFO LOGIC PACKAGE
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



--THE BILLING ENGINE PACKAGE
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
