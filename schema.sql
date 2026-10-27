-- =============================================================
-- schema.sql : 도서 대여 서비스 스키마
-- DB   : SQLite 3
-- 실행 : sqlite3 library.db < schema.sql
--
-- 테이블 (4개)
--   category  카테고리
--   member    회원
--   book      도서          (category 1 : N book)
--   rental    대여 기록     (member 1 : N rental, book 1 : N rental)
-- =============================================================

-- [SQLite 전용] SQLite는 기본적으로 FK 검사가 꺼져 있다.
-- 접속(세션)마다 켜야 없는 값 참조가 실제로 막힌다.
PRAGMA foreign_keys = ON;

-- 재실행 가능하도록 자식 테이블부터 삭제
DROP TABLE IF EXISTS rental;
DROP TABLE IF EXISTS book;
DROP TABLE IF EXISTS member;
DROP TABLE IF EXISTS category;

-- 1) 카테고리 --------------------------------------------------
CREATE TABLE category (
    id          INTEGER      PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    description VARCHAR(200)
);

-- 2) 회원 ------------------------------------------------------
CREATE TABLE member (
    id          INTEGER      PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL,
    email       VARCHAR(100) NOT NULL UNIQUE,
    phone       VARCHAR(20),
    grade       VARCHAR(10)  NOT NULL DEFAULT 'BASIC'
                CHECK (grade IN ('BASIC', 'SILVER', 'GOLD')),
    joined_at   DATE         NOT NULL
);

-- 3) 도서 ------------------------------------------------------
CREATE TABLE book (
    id           INTEGER      PRIMARY KEY,
    category_id  INTEGER      NOT NULL,
    title        VARCHAR(200) NOT NULL,
    author       VARCHAR(100) NOT NULL,
    isbn         VARCHAR(20)  NOT NULL UNIQUE,
    published_year INTEGER    CHECK (published_year BETWEEN 1800 AND 2100),
    price        INTEGER      NOT NULL CHECK (price >= 0),
    stock        INTEGER      NOT NULL DEFAULT 1 CHECK (stock >= 0),
    FOREIGN KEY (category_id) REFERENCES category (id)
);

-- 4) 대여 기록 -------------------------------------------------
-- status: RENTED(대여중) / RETURNED(반납) / OVERDUE(연체)
CREATE TABLE rental (
    id          INTEGER     PRIMARY KEY,
    member_id   INTEGER     NOT NULL,
    book_id     INTEGER     NOT NULL,
    rented_at   DATE        NOT NULL,
    due_date    DATE        NOT NULL,
    returned_at DATE,                        -- 미반납이면 NULL
    status      VARCHAR(10) NOT NULL DEFAULT 'RENTED'
                CHECK (status IN ('RENTED', 'RETURNED', 'OVERDUE')),
    late_fee    INTEGER     NOT NULL DEFAULT 0 CHECK (late_fee >= 0),
    CHECK (due_date >= rented_at),
    FOREIGN KEY (member_id) REFERENCES member (id),
    FOREIGN KEY (book_id)   REFERENCES book (id)
);

