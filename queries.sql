-- =============================================================
-- queries.sql : 핵심 쿼리 15개
-- DB   : SQLite 3
-- 실행 : sqlite3 -header -box -echo library.db < queries.sql > results/result.txt
--        (schema.sql, data.sql 실행 후)
--
-- 기준일(오늘)은 2026-09-28 로 고정한다.
--
-- 범주            | 쿼리
-- ----------------+--------------------------
-- 기본 조회  (4)  | Q01 ~ Q04
-- 조인       (4)  | Q05 ~ Q08  (INNER 2, LEFT 2)
-- 집계       (3)  | Q09 ~ Q11
-- 서브쿼리   (1)  | Q12
-- 수정/삭제  (2)  | Q13 (UPDATE), Q14 (DELETE)
-- 인덱스     (1)  | Q15
--
-- Q13, Q14 는 데이터를 바꾸므로 한 번만 실행한다.
-- 다시 돌리려면 schema.sql → data.sql 부터 재실행한다.
-- =============================================================

PRAGMA foreign_keys = ON;   -- [SQLite 전용]


-- ─────────────────────────── 기본 조회 ───────────────────────────

-- [Q01] 2만 5천 원 이상인 도서를 비싼 순으로
SELECT id, title, author, price
FROM book
WHERE price >= 25000
ORDER BY price DESC;

-- [Q02] GOLD 등급 회원
SELECT id, name, grade, joined_at
FROM member
WHERE grade = 'GOLD';

-- [Q03] 가장 최근 대여 5건
SELECT id, member_id, book_id, rented_at, status
FROM rental
ORDER BY rented_at DESC
LIMIT 5;

-- [Q04] 제목에 'SQL'이 들어간 도서
SELECT id, title, author
FROM book
WHERE title LIKE '%SQL%';


-- ───────────────────────────── 조인 ─────────────────────────────

-- [Q05] 도서 제목과 카테고리 이름 (INNER JOIN)
SELECT b.title, c.name AS category
FROM book b
INNER JOIN category c ON c.id = b.category_id
ORDER BY b.id;

-- [Q06] 아직 반납하지 않은 대여: 회원 이름 + 책 제목 (INNER JOIN)
SELECT r.id AS rental_id, m.name AS member_name, b.title AS book_title, r.due_date
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.returned_at IS NULL
ORDER BY r.due_date;

-- [Q07] 모든 회원의 대여 횟수 — 안 빌린 회원도 0으로 (LEFT JOIN)
SELECT m.id, m.name, COUNT(r.id) AS rental_count
FROM member m
LEFT JOIN rental r ON r.member_id = m.id
GROUP BY m.id, m.name
ORDER BY m.id;

-- [Q08] 한 번도 대여되지 않은 도서 (LEFT JOIN + IS NULL)
SELECT b.id, b.title
FROM book b
LEFT JOIN rental r ON r.book_id = b.id
WHERE r.id IS NULL;


-- ───────────────────────────── 집계 ─────────────────────────────

-- [Q09] 상태별 대여 건수 (COUNT + GROUP BY)
SELECT status, COUNT(*) AS rental_count
FROM rental
GROUP BY status;

-- [Q10] 카테고리별 도서 평균 가격 (AVG + GROUP BY)
SELECT category_id, COUNT(*) AS book_count, AVG(price) AS avg_price
FROM book
GROUP BY category_id
ORDER BY category_id;

-- [Q11] 회원별 연체료 합계 (SUM + GROUP BY)
SELECT member_id, SUM(late_fee) AS total_late_fee
FROM rental
GROUP BY member_id
ORDER BY total_late_fee DESC, member_id;


-- ─────────────────────────── 서브쿼리 ───────────────────────────

-- [Q12] 전체 평균 가격보다 비싼 도서
SELECT id, title, price
FROM book
WHERE price > (SELECT AVG(price) FROM book)
ORDER BY price DESC;


-- ─────────────────────────── 수정 / 삭제 ─────────────────────────

-- [Q13] 반납 기한이 지났는데 아직 RENTED 인 대여를 OVERDUE 로 변경 (UPDATE)
UPDATE rental
SET status = 'OVERDUE'
WHERE status = 'RENTED'
  AND due_date < '2026-09-28';

SELECT id, due_date, status FROM rental WHERE status = 'OVERDUE';

-- [Q14] 대여 기록이 없는 12번 회원 삭제 (DELETE)
DELETE FROM member WHERE id = 12;

SELECT COUNT(*) AS member_count FROM member;


-- ──────────────────────────── 인덱스 ────────────────────────────

-- [Q15] rental.member_id 인덱스
-- 이유: "회원별 대여 내역"을 찾을 때 member_id 로 자주 검색·조인하는데,
--       FK 컬럼에는 인덱스가 자동으로 생기지 않아 전체 rental 을 훑게 되므로.
EXPLAIN QUERY PLAN SELECT * FROM rental WHERE member_id = 1;   -- 생성 전

CREATE INDEX idx_rental_member ON rental (member_id);

EXPLAIN QUERY PLAN SELECT * FROM rental WHERE member_id = 1;   -- 생성 후
