-- =============================================================
-- 04_bonus.sql : 보너스 과제
-- DB   : SQLite 3
-- 실행 : sqlite3 library.db < sql/04_bonus.sql   (01, 02, 03 실행 후)
--
--   B1  같은 요구를 JOIN / 서브쿼리 두 방식으로 풀기
--   B2  데이터 정합성 깨뜨려 보기 (FK 에러) — 에러가 나는 것이 정상
--   B3  미니 리포트: 핵심 지표 3개
-- =============================================================

PRAGMA foreign_keys = ON;   -- [SQLite 전용]


-- ───────────── [B1] JOIN vs 서브쿼리 ─────────────
-- 요구: "현재 연체(OVERDUE) 중인 대여의 회원 이름과 책 제목"

-- [B1-a] JOIN 방식
SELECT r.id AS rental_id, m.name AS member_name, b.title AS book_title, r.due_date
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.status = 'OVERDUE'
ORDER BY r.id;

-- [B1-b] 서브쿼리 방식 (SELECT 절 상관 서브쿼리)
SELECT r.id AS rental_id,
       (SELECT m.name  FROM member m WHERE m.id = r.member_id) AS member_name,
       (SELECT b.title FROM book   b WHERE b.id = r.book_id)   AS book_title,
       r.due_date
FROM rental r
WHERE r.status = 'OVERDUE'
ORDER BY r.id;

-- 비교
--  * 결과는 같다. 둘 다 rental 1행마다 member·book 을 PK 로 찾아오기 때문이다.
--  * JOIN: 여러 컬럼을 가져올 때 한 번의 연결로 끝나고, 옵티마이저가 조인 순서를 고를 수 있다.
--          가져올 컬럼이 늘어도 쿼리가 거의 그대로다.
--  * 서브쿼리: 컬럼 하나마다 서브쿼리가 하나씩 필요해 컬럼이 늘면 길어지고 반복 조회가 생긴다.
--          대신 "연결 대상이 없으면 NULL" 이라 LEFT JOIN 과 비슷하게 동작하며,
--          하나의 값만 곁들일 때는 읽기 쉽다.
--  * SELECT 절 서브쿼리는 값 1개만 돌려줘야 한다. 2행 이상이면 MySQL/PostgreSQL 은 에러,
--    SQLite 는 조용히 첫 행만 쓴다. 그래서
--    1:N 의 N 쪽을 가져올 때는 JOIN 이 맞다.


-- ───────────── [B2] 데이터 정합성 깨뜨려 보기 ─────────────

-- [B2-a] 존재하지 않는 회원(999번)으로 대여 기록 입력 → FK 에러
INSERT INTO rental (id, member_id, book_id, rented_at, due_date, status)
VALUES (100, 999, 1, '2026-09-28', '2026-10-12', 'RENTED');
-- 결과: Error: FOREIGN KEY constraint failed
-- 이유: rental.member_id 는 member.id 를 참조한다. member 에 999번이 없으므로
--       "주인 없는 대여 기록"이 생기는 것을 DB 가 막는다.
-- 해결: 부모(member)를 먼저 넣은 뒤 자식(rental)을 넣는다. ↓

-- [B2-b] 대여 기록이 있는 회원(1번)을 삭제 시도 → FK 에러
DELETE FROM member WHERE id = 1;
-- 결과: Error: FOREIGN KEY constraint failed
-- 이유: rental 에 member_id = 1 인 기록이 남아 있다. 부모를 지우면 자식이 고아가 된다.
--       (review 는 ON DELETE CASCADE 라 같이 지워지지만, rental 은 기본값 NO ACTION 이라 막힌다.)
-- 해결: 대여 기록을 보존해야 하므로 회원을 물리 삭제하지 말고, 탈퇴 여부 컬럼을 두는 식의
--       논리 삭제가 적절하다. 정말 지워야 한다면 자식(rental)을 먼저 정리한다.

-- [B2-c] 고쳐서 다시 입력: 부모(member 999) 먼저, 그다음 자식(rental)
INSERT INTO member (id, name, email, grade, joined_at)
VALUES (999, '테스트회원', 'test999@example.com', 'BASIC', '2026-09-28');
INSERT INTO rental (id, member_id, book_id, rented_at, due_date, status)
VALUES (100, 999, 1, '2026-09-28', '2026-10-12', 'RENTED');

SELECT r.id, m.name, r.book_id, r.status
FROM rental r INNER JOIN member m ON m.id = r.member_id
WHERE r.id = 100;

-- 실습용 데이터 정리 (자식 → 부모 순서로 삭제)
DELETE FROM rental WHERE id = 100;
DELETE FROM member WHERE id = 999;


-- ───────────── [B3] 미니 리포트: 핵심 지표 3개 ─────────────

-- [B3-1] 월별 대여 건수 추이와 전월 대비 증감
-- [SQLite 전용] SUBSTR. LAG() 윈도 함수는 표준 SQL(SQL:2003)이며 SQLite 3.25+ 지원.
SELECT rent_month,
       rental_count,
       rental_count - LAG(rental_count) OVER (ORDER BY rent_month) AS diff_from_prev
FROM (
    SELECT SUBSTR(rented_at, 1, 7) AS rent_month, COUNT(*) AS rental_count
    FROM rental
    GROUP BY SUBSTR(rented_at, 1, 7)
) AS monthly
ORDER BY rent_month;

-- [B3-2] 인기 도서 TOP 5 (대여 횟수 기준 순위 5위 이내) + 평균 평점
-- LIMIT 5 로 자르면 동률인 책이 임의로 잘리므로, RANK() 로 순위를 매긴 뒤 순위로 거른다.
-- RANK() 는 표준 SQL 윈도 함수 (SQLite 3.25+ 지원)
SELECT rank_no, title, rental_count, avg_rating
FROM (
    SELECT RANK() OVER (ORDER BY COUNT(r.id) DESC) AS rank_no,
           b.id,
           b.title,
           COUNT(r.id) AS rental_count,
           (SELECT ROUND(AVG(rv.rating), 2) FROM review rv WHERE rv.book_id = b.id) AS avg_rating
    FROM book b
    INNER JOIN rental r ON r.book_id = b.id
    GROUP BY b.id, b.title
) AS ranked
WHERE rank_no <= 5
ORDER BY rank_no, avg_rating DESC, id;

-- [B3-3] 회원별 연체율 (연체 발생 건수 / 전체 대여 건수)
-- 연체 = 늦게 반납(late_fee > 0) 했거나 현재 OVERDUE 인 대여
SELECT m.name,
       COUNT(*) AS rental_count,
       SUM(CASE WHEN r.late_fee > 0 OR r.status = 'OVERDUE' THEN 1 ELSE 0 END) AS late_count,
       ROUND(100.0 * SUM(CASE WHEN r.late_fee > 0 OR r.status = 'OVERDUE' THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS late_rate_pct
FROM member m
INNER JOIN rental r ON r.member_id = m.id
GROUP BY m.id, m.name
HAVING SUM(CASE WHEN r.late_fee > 0 OR r.status = 'OVERDUE' THEN 1 ELSE 0 END) > 0
ORDER BY late_rate_pct DESC, late_count DESC;
