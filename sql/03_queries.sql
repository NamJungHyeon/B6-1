-- =============================================================
-- 03_queries.sql : 핵심 쿼리 18개
-- DB   : SQLite 3
-- 실행 : sqlite3 library.db < sql/03_queries.sql   (01, 02 실행 후)
--
-- 기준일(오늘)은 2026-09-28 로 고정한다. 결과를 재현할 수 있도록
-- DATE('now') 대신 날짜 리터럴을 쓴다.
--
-- 범주            | 쿼리
-- ----------------+--------------------------
-- 기본 조회  (5)  | Q01 ~ Q05
-- 조인       (4)  | Q06 ~ Q09  (INNER 2, LEFT 2)
-- 집계       (4)  | Q10 ~ Q13
-- 서브쿼리   (2)  | Q14 ~ Q15
-- 수정/삭제  (2)  | Q16 (UPDATE), Q17 (DELETE)
-- 인덱스     (1)  | Q18
--
-- Q16, Q17 은 데이터를 바꾸므로 순서대로 한 번만 실행한다.
-- 다시 돌리려면 01_schema.sql → 02_data.sql 부터 재실행한다.
-- =============================================================

PRAGMA foreign_keys = ON;   -- [SQLite 전용]


-- ─────────────────────────── 기본 조회 ───────────────────────────

-- [Q01] 2만 원 이상인 도서를 가격이 비싼 순으로 조회 (WHERE + ORDER BY)
SELECT id, title, author, price
FROM book
WHERE price >= 20000
ORDER BY price DESC;

-- [Q02] GOLD·SILVER 등급 회원을 가입일이 빠른 순으로 조회 (WHERE IN + ORDER BY)
SELECT id, name, grade, joined_at
FROM member
WHERE grade IN ('GOLD', 'SILVER')
ORDER BY joined_at ASC;

-- [Q03] 가장 최근에 발생한 대여 5건 (ORDER BY + LIMIT)
SELECT id, member_id, book_id, rented_at, status
FROM rental
ORDER BY rented_at DESC
LIMIT 5;

-- [Q04] 제목에 '의'가 들어간 도서 검색 (LIKE 부분 일치 검색)
SELECT id, title, author, published_year
FROM book
WHERE title LIKE '%의%'
ORDER BY published_year DESC;

-- [Q05] 최근 30일(2026-08-29 ~ 2026-09-28) 대여 기록 (날짜 범위 조회)
SELECT id, member_id, book_id, rented_at, due_date, status
FROM rental
WHERE rented_at BETWEEN '2026-08-29' AND '2026-09-28'
ORDER BY rented_at;


-- ───────────────────────────── 조인 ─────────────────────────────

-- [Q06] 현재 대여 중(미반납)인 책과 빌린 회원 목록 (INNER JOIN 3개 테이블)
SELECT r.id        AS rental_id,
       m.name      AS member_name,
       b.title     AS book_title,
       r.rented_at,
       r.due_date,
       r.status
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.returned_at IS NULL
ORDER BY r.due_date;

-- [Q07] 리뷰 목록을 도서 카테고리·작성자와 함께 조회 (INNER JOIN 4개 테이블)
SELECT c.name   AS category,
       b.title  AS book_title,
       m.name   AS reviewer,
       rv.rating,
       rv.content
FROM review rv
INNER JOIN book     b ON b.id = rv.book_id
INNER JOIN category c ON c.id = b.category_id
INNER JOIN member   m ON m.id = rv.member_id
WHERE rv.rating >= 4
ORDER BY rv.rating DESC, c.name, rv.id;

-- [Q08] 모든 회원의 대여 횟수 — 한 번도 안 빌린 회원도 0으로 표시 (LEFT JOIN)
SELECT m.id, m.name, COUNT(r.id) AS rental_count
FROM member m
LEFT JOIN rental r ON r.member_id = m.id
GROUP BY m.id, m.name
ORDER BY rental_count DESC, m.id;

-- [Q09] 한 번도 대여되지 않은 도서 찾기 (LEFT JOIN + IS NULL)
SELECT b.id, b.title, b.author
FROM book b
LEFT JOIN rental r ON r.book_id = b.id
WHERE r.id IS NULL;


-- ───────────────────────────── 집계 ─────────────────────────────

-- [Q10] 카테고리별 소장 도서 수와 평균 가격 (COUNT + AVG + GROUP BY)
SELECT c.name                 AS category,
       COUNT(b.id)            AS book_count,
       ROUND(AVG(b.price), 0) AS avg_price
FROM category c
LEFT JOIN book b ON b.category_id = c.id
GROUP BY c.id, c.name
ORDER BY book_count DESC, c.id;

-- [Q11] 연체료를 낸 회원별 전체 대여·연체 건수와 연체료 합계 (COUNT + SUM + GROUP BY + HAVING)
SELECT m.name,
       COUNT(*)                                        AS rental_count,
       SUM(CASE WHEN r.late_fee > 0 THEN 1 ELSE 0 END) AS late_count,
       SUM(r.late_fee)                                 AS total_late_fee
FROM rental r
INNER JOIN member m ON m.id = r.member_id
GROUP BY m.id, m.name
HAVING SUM(r.late_fee) > 0
ORDER BY total_late_fee DESC;

-- [Q12] 도서별 평균 평점·리뷰 수 랭킹 (AVG + COUNT + GROUP BY, 평점 같으면 리뷰 많은 순)
SELECT b.title,
       COUNT(rv.id)             AS review_count,
       ROUND(AVG(rv.rating), 2) AS avg_rating
FROM book b
INNER JOIN review rv ON rv.book_id = b.id
GROUP BY b.id, b.title
ORDER BY avg_rating DESC, review_count DESC, b.id;

-- [Q13] 월별 대여 건수 추이 (COUNT + GROUP BY)
-- [SQLite 전용] SUBSTR — 표준 SQL 은 SUBSTRING(rented_at FROM 1 FOR 7),
--               MySQL 은 DATE_FORMAT, PostgreSQL 은 TO_CHAR 를 주로 쓴다.
SELECT SUBSTR(rented_at, 1, 7) AS rent_month,
       COUNT(*)                AS rental_count
FROM rental
GROUP BY SUBSTR(rented_at, 1, 7)
ORDER BY rent_month;


-- ─────────────────────────── 서브쿼리 ───────────────────────────

-- [Q14] 대여 기록이 한 건도 없는 회원 찾기 (NOT EXISTS 상관 서브쿼리)
SELECT m.id, m.name, m.joined_at
FROM member m
WHERE NOT EXISTS (
    SELECT 1
    FROM rental r
    WHERE r.member_id = m.id
);

-- [Q15] 전체 평균 가격보다 비싼 도서 (스칼라 서브쿼리)
SELECT id, title, price,
       (SELECT ROUND(AVG(price), 0) FROM book) AS avg_price
FROM book
WHERE price > (SELECT AVG(price) FROM book)
ORDER BY price DESC;


-- ─────────────────────────── 수정 / 삭제 ─────────────────────────

-- [Q16] 반납 기한이 지났는데 아직 RENTED 인 대여를 OVERDUE 로 변경 (UPDATE)
-- 변경 전
SELECT id, member_id, due_date, status
FROM rental
WHERE status = 'RENTED' AND due_date < '2026-09-28';

UPDATE rental
SET status = 'OVERDUE'
WHERE status = 'RENTED'
  AND returned_at IS NULL
  AND due_date < '2026-09-28';

-- 변경 후 (연체 상태 전체)
SELECT id, member_id, due_date, status
FROM rental
WHERE status = 'OVERDUE'
ORDER BY id;

-- [Q17] 대여 기록이 없는 탈퇴 회원(12번 문재원) 삭제 (DELETE)
-- 대여 기록이 있는 회원은 FK 때문에 삭제되지 않는다 (bonus 참고).
DELETE FROM member
WHERE id = 12
  AND NOT EXISTS (SELECT 1 FROM rental WHERE member_id = 12);

-- 삭제 확인
SELECT COUNT(*) AS member_count,
       SUM(CASE WHEN id = 12 THEN 1 ELSE 0 END) AS id12_exists
FROM member;


-- ──────────────────────────── 인덱스 ────────────────────────────

-- [Q18] rental(member_id), rental(status, due_date) 인덱스 생성
-- 적용 이유: rental 은 가장 빨리 쌓이는 테이블이고, "회원별 대여 내역"(JOIN·WHERE member_id)과
--           "연체 대상 찾기"(WHERE status = ? AND due_date < ?)가 매일 반복되므로
--           전체 스캔 대신 인덱스 탐색을 하도록 한다.
-- [SQLite 전용] EXPLAIN QUERY PLAN 으로 실행 계획을 확인한다.
--               (MySQL/PostgreSQL 은 EXPLAIN)

-- 인덱스 생성 전 실행 계획
EXPLAIN QUERY PLAN
SELECT * FROM rental WHERE status = 'RENTED' AND due_date < '2026-09-28';

CREATE INDEX IF NOT EXISTS idx_rental_member     ON rental (member_id);
CREATE INDEX IF NOT EXISTS idx_rental_status_due ON rental (status, due_date);

-- 인덱스 생성 후 실행 계획
EXPLAIN QUERY PLAN
SELECT * FROM rental WHERE status = 'RENTED' AND due_date < '2026-09-28';

EXPLAIN QUERY PLAN
SELECT * FROM rental WHERE member_id = 1;
