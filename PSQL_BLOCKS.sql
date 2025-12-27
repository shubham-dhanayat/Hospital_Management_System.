--DATA LOADING 
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



--DATA SIMULATION
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



DATA SIMULATION 
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



--FEFO SIMULATION
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



--END-TO-END SIMULATION
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
