-- ==================================================================================
-- TRABAJO N°6 — TRANSACCIONES RELACIONALES EN ORACLE DATABASE
-- Autor: Benites Meza, Marco Fabricio.

-- ==================================================================================

SET SERVEROUTPUT ON SIZE 1000000;
PROMPT ================================================================
PROMPT ⿡ EJERCICIO 01 — CONTROL BÁSICO DE TRANSACCIONES
PROMPT Objetivo: uso de SAVEPOINT, ROLLBACK TO y COMMIT.
PROMPT ================================================================

/*
 Contexto:
 - Aumentar 10% salario de empleados del departamento 90.
 - Crear SAVEPOINT.
 - Intentar aumentar 5% salarios del departamento 60 y luego deshacer SOLO lo posterior al SAVEPOINT.
 - Confirmar cambios (COMMIT).
*/

DECLARE
  v_afectados_dept90 NUMBER;
  v_afectados_dept60 NUMBER;
BEGIN
  -- Aumentar 10% salario de empleados del departamento 90
  UPDATE hr.employees
     SET salary = salary * 1.10
   WHERE department_id = 90;
  v_afectados_dept90 := SQL%ROWCOUNT;

  SAVEPOINT punto1;

  -- Aumentar 5% salario de empleados del departamento 60
  UPDATE hr.employees
     SET salary = salary * 1.05
   WHERE department_id = 60;
  v_afectados_dept60 := SQL%ROWCOUNT;

  -- Revertir solo lo hecho después de punto1
  ROLLBACK TO punto1;

  -- Confirmar la transacción (persistir cambios anteriores a punto1)
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('EJ1: Afectados dept 90 = ' || v_afectados_dept90);
  DBMS_OUTPUT.PUT_LINE('EJ1: Afectados dept 60 (REVERTIDOS) = ' || v_afectados_dept60);
  DBMS_OUTPUT.PUT_LINE('EJ1: Bloque finalizado: cambios confirmados.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('EJ1: Error: ' || SQLERRM);
END;
/
-- RESPUESTAS (EJERCICIO 01)
-- a) ¿Qué departamento mantuvo los cambios?
--    El departamento 90 mantuvo el incremento del 10% porque se hizo ANTES del SAVEPOINT punto1.
--    El aumento del 5% para el departamento 60 fue deshecho por el ROLLBACK TO punto1.
-- b) Efecto del ROLLBACK parcial:
--    ROLLBACK TO <savepoint> revierte solo las operaciones ejecutadas DESPUÉS del savepoint;
--    lo efectuado antes del savepoint permanece.
-- c) Si se ejecutara ROLLBACK sin SAVEPOINT:
--    Desharía TODA la transacción (todos los cambios desde el último COMMIT), devolviendo la sesión
--    al estado previo a la transacción.


PROMPT ================================================================
PROMPT ⿢ EJERCICIO 02 — BLOQUEOS ENTRE SESIONES (CONCURRENCY / LOCKING)
PROMPT Objetivo: demostrar bloqueo de registros entre sesiones y cómo se libera.
PROMPT ================================================================

/*
 Instrucciones: este ejercicio requiere DOS SESIONES distintAS conectadas a la misma BD.
 Recomendación: ejecutar los bloques de SESIÓN A y SESIÓN B en conexiones separadas.

 --- SESIÓN A --- (ejecutar en la primera conexión)
*/
-- Naming opcional de transacción (no afecta el lock)
-- SET TRANSACTION NAME 'sesion_a';

-- Bloquea la fila del empleado 103 sin confirmar:
UPDATE hr.employees
   SET salary = salary + 500
 WHERE employee_id = 103;
-- Importante: NO HACER COMMIT ni ROLLBACK todavía; el registro queda bloqueado por esta sesión.

/*
 --- SESIÓN B --- (ejecutar en la segunda conexión)
 Intento concurrente sobre la misma fila: quedará esperando (lock) hasta que A haga COMMIT o ROLLBACK.
*/
-- UPDATE hr.employees
--    SET salary = salary + 200
--  WHERE employee_id = 103;

-- Esta sentencia en SESIÓN B quedará BLOQUEADA hasta que la SESIÓN A libere el lock.
-- Para liberar el bloqueo, volver a SESIÓN A y decidir:
--   a) Si no deseas conservar el cambio: ROLLBACK;
--   b) Si deseas persistir:         COMMIT;

-- Verificación (requiere privilegios apropiados, típicamente DBA/SELECT_CATALOG_ROLE):
-- SELECT sid, serial#, username, status, event FROM v$session WHERE username IS NOT NULL;
-- SELECT l.session_id, s.username, l.locked_mode, o.object_name
--   FROM v$locked_object l
--   JOIN dba_objects o ON l.object_id = o.object_id
--   JOIN v$session s ON l.session_id = s.sid;
-- SELECT * FROM v$lock WHERE block = 1; -- bloqueadores

-- RESPUESTAS (EJERCICIO 02)
-- a) ¿Por qué la segunda sesión quedó bloqueada?
--    Porque la primera sesión obtuvo un bloqueo exclusivo de FILA (row-level lock) sobre employee_id = 103
--    al ejecutar el UPDATE sin COMMIT; Oracle impide cambios conflictivos hasta liberar el lock.
-- b) ¿Qué comando libera los bloqueos?
--    COMMIT (si se desea persistir) o ROLLBACK (si se desea deshacer); ambos liberan los locks.
-- c) ¿Qué vistas permiten verificar sesiones bloqueadas?
--    V$LOCK, V$SESSION, V$LOCKED_OBJECT, DBA_BLOCKERS, DBA_WAITERS (según privilegios).
--    También V$SESSION_WAIT / V$SESSION para ver eventos de espera.


PROMPT ================================================================
PROMPT ⿣ EJERCICIO 03 — TRANSACCIÓN ATÓMICA (EMPLOYEES + JOB_HISTORY)
PROMPT Objetivo: garantizar atomicidad entre la actualización en EMPLOYEES y la inserción en JOB_HISTORY.
PROMPT ================================================================

/*
 Asume las tablas del esquema HR:
   - HR.EMPLOYEES (employee_id, department_id, job_id, salary, ...)
   - HR.JOB_HISTORY (employee_id, start_date, end_date, job_id, department_id, ...)
*/
DECLARE
  v_emp_id     NUMBER   := 104;
  v_new_dept   NUMBER   := 110;
  v_old_dept   NUMBER;
  v_job_id     VARCHAR2(10);
  v_start_date DATE;
  v_end_date   DATE;
BEGIN
  -- 1) Consultar estado actual del empleado (y BLOQUEAR la fila para esta transacción)
  SELECT department_id, job_id
    INTO v_old_dept, v_job_id
    FROM hr.employees
   WHERE employee_id = v_emp_id
   FOR UPDATE;  -- asegura que la fila está bloqueada por esta transacción

  -- 2) Registrar salida del puesto anterior en JOB_HISTORY (fechas de ejemplo)
  v_start_date := SYSDATE - 30;
  v_end_date   := SYSDATE - 1;
  INSERT INTO hr.job_history(employee_id, start_date, end_date, job_id, department_id)
  VALUES (v_emp_id, v_start_date, v_end_date, v_job_id, v_old_dept);

  -- 3) Actualizar department_id del empleado
  UPDATE hr.employees
     SET department_id = v_new_dept
   WHERE employee_id = v_emp_id;

  -- 4) Confirmar la transacción (ambas operaciones deben persistir juntas)
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('EJ3: Transferencia completada y JOB_HISTORY actualizado.');
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('EJ3: Error: empleado no encontrado.');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('EJ3: Error inesperado: ' || SQLERRM);
END;
/
-- RESPUESTAS (EJERCICIO 03)
-- a) ¿Por qué se debe garantizar la atomicidad entre las 2 operaciones?
--    Porque ambas operaciones representan una sola acción lógica (traslado del empleado). Si una ocurre y la otra falla,
--    los datos quedarían inconsistentes (empleado en nuevo depto sin registro en JOB_HISTORY, o viceversa).
-- b) ¿Qué pasaría si se produce un error antes del COMMIT?
--    Si ocurre un error y se ejecuta ROLLBACK, tanto el INSERT en JOB_HISTORY como el UPDATE en EMPLOYEES se desharán,
--    preservando la integridad.
-- c) ¿Cómo se asegura la integridad entre EMPLOYEES y JOB_HISTORY?
--    Mediante transacciones (COMMIT/ROLLBACK) que envuelven las operaciones; además, mediante restricciones de
--    integridad referencial (FK) si existen, y validaciones previas (p. ej., verificar existencia del departamento destino).


PROMPT ================================================================
PROMPT ⿤ EJERCICIO 04 — SAVEPOINT Y REVERSIÓN PARCIAL
PROMPT Objetivo: combinación de varios SAVEPOINT y ROLLBACK TO parcial, con actualizaciones y deletes.
PROMPT ================================================================

DECLARE
  v_afectados_100 NUMBER;
  v_afectados_80  NUMBER;
  v_borrados_50   NUMBER;
BEGIN
  -- Aumentar 8% salario para departamento 100
  UPDATE hr.employees
     SET salary = salary * 1.08
   WHERE department_id = 100;
  v_afectados_100 := SQL%ROWCOUNT;
  SAVEPOINT A;

  -- Aumentar 5% salario para departamento 80
  UPDATE hr.employees
     SET salary = salary * 1.05
   WHERE department_id = 80;
  v_afectados_80 := SQL%ROWCOUNT;
  SAVEPOINT B;

  -- Eliminar empleados del departamento 50
  DELETE FROM hr.employees
   WHERE department_id = 50;
  v_borrados_50 := SQL%ROWCOUNT;

  -- Revertir los cambios hasta SAVEPOINT B (deshace el DELETE y lo posterior a B)
  ROLLBACK TO B;

  -- Confirmar (persistir lo anterior a B: es decir, lo hecho hasta el savepoint B)
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('EJ4: +8% dept 100 = ' || v_afectados_100);
  DBMS_OUTPUT.PUT_LINE('EJ4: +5% dept 80  = ' || v_afectados_80);
  DBMS_OUTPUT.PUT_LINE('EJ4: DELETE dept 50 (REVERTIDO) = ' || v_borrados_50);
  DBMS_OUTPUT.PUT_LINE('EJ4: Operación finalizada: cambios hasta SAVEPOINT B confirmados.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('EJ4: Error: ' || SQLERRM);
END;
/
-- RESPUESTAS (EJERCICIO 04)
-- a) ¿Qué cambios quedan persistentes?
--    Permanecen el aumento del 8% para department_id = 100 (antes de A) y el aumento del 5% para department_id = 80 (antes de B).
--    El DELETE de empleados del departamento 50 fue revertido por ROLLBACK TO B, por lo tanto NO se persiste.
-- b) ¿Qué sucede con las filas eliminadas?
--    Como se ejecutó ROLLBACK TO B después del DELETE, las filas se restauran (asumiendo que no hubo COMMIT intermedio).
-- c) ¿Cómo verificar los cambios antes y después del COMMIT?
--    En la misma sesión puedes consultar y ver los efectos antes del COMMIT; en otras sesiones no verán cambios
--    hasta que se ejecute COMMIT. Ejemplo:
--      SELECT employee_id, first_name, salary, department_id
--      FROM hr.employees
--      WHERE department_id IN (100,80,50);
-- ==================================================================================
-- FIN DEL SCRIPT
-- ==================================================================================
