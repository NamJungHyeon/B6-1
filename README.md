# 디지털 서랍장 — 도서 대여 DB

SQL만으로 **도서 대여 서비스**의 테이블을 설계하고, 샘플 데이터를 넣고, 쿼리 15개로 요구사항을 확인한 실습입니다.

- DB: **SQLite 3** · 실행 도구: `sqlite3` CLI (macOS 기본 포함)
- 기준일(오늘): **2026-09-28** — 결과가 매번 같도록 날짜를 고정

## 파일 구성

| 제출물 | 파일 |
| --- | --- |
| 스키마 생성 SQL | [schema.sql](schema.sql) |
| 샘플 데이터 INSERT SQL | [data.sql](data.sql) |
| 핵심 쿼리 SQL (15개) | [queries.sql](queries.sql) |
| 실행 결과 | [results/result.txt](results/result.txt) — 쿼리 원문 + 결과 표 |
| ERD | [erd.png](erd.png) |

## 실행 방법

```bash
rm -f library.db
sqlite3 library.db < schema.sql
sqlite3 library.db < data.sql
sqlite3 -header -box -echo library.db < queries.sql > results/result.txt
```

> SQLite는 FK 검사가 기본으로 꺼져 있고 **접속마다** 켜야 합니다.
> 그래서 모든 `.sql` 파일 맨 위에 `PRAGMA foreign_keys = ON;`(SQLite 전용)을 넣었습니다.

## 데이터 모델

![ERD](erd.png)

| 테이블 | 역할 | 행 수 |
| --- | --- | --- |
| `category` | 도서 카테고리 | 10 |
| `member` | 회원 | 12 |
| `book` | 도서 | 15 |
| `rental` | 대여 기록 (대여일·반납 기한·반납일·상태·연체료) | 25 |

**1:N 관계 3개**

| 부모 (1) | 자식 (N) | FK |
| --- | --- | --- |
| category | book | `book.category_id → category.id` |
| member | rental | `rental.member_id → member.id` |
| book | rental | `rental.book_id → book.id` |

`member`와 `book`은 `rental`을 사이에 두고 **N:M** 관계가 됩니다.
한 회원은 여러 책을, 한 책은 여러 회원이 빌릴 수 있어서 "빌렸다는 사건"을 별도 테이블로 뺐습니다.

**제약조건**

- `NOT NULL`: `member.name`, `member.email`, `book.title`, `rental.rented_at` 등
- `UNIQUE`: `category.name`, `member.email`, `book.isbn`
- `CHECK`: `rental.status IN ('RENTED','RETURNED','OVERDUE')`, `price >= 0`, `due_date >= rented_at`

**일부러 넣은 데이터** (쿼리 결과가 의미 있게 나오도록)

- 대여 기록이 없는 회원 2명(11, 12번) → LEFT JOIN(Q07), DELETE(Q14)
- 한 번도 대여되지 않은 도서 2권(14, 15번) → LEFT JOIN + IS NULL(Q08)
- 반납 기한이 지났는데 상태가 아직 `RENTED`인 대여 2건(19, 20번) → UPDATE(Q13)

## 쿼리 목록

| # | 범주 | 무엇을 확인하는가 |
| --- | --- | --- |
| Q01 | 기본 조회 | 2만 5천 원 이상 도서를 비싼 순으로 (`WHERE`, `ORDER BY`) |
| Q02 | 기본 조회 | GOLD 등급 회원 (`WHERE`) |
| Q03 | 기본 조회 | 최근 대여 5건 (`ORDER BY`, `LIMIT`) |
| Q04 | 기본 조회 | 제목에 'SQL'이 들어간 도서 (`LIKE`) |
| Q05 | INNER JOIN | 도서 제목 + 카테고리 이름 |
| Q06 | INNER JOIN | 미반납 대여 + 회원 이름 + 책 제목 |
| Q07 | LEFT JOIN | 회원별 대여 횟수, 0회 회원 포함 |
| Q08 | LEFT JOIN | 한 번도 대여되지 않은 도서 (`IS NULL`) |
| Q09 | 집계 | 상태별 대여 건수 (`COUNT`) |
| Q10 | 집계 | 카테고리별 평균 가격 (`AVG`) |
| Q11 | 집계 | 회원별 연체료 합계 (`SUM`) |
| Q12 | 서브쿼리 | 평균 가격보다 비싼 도서 |
| Q13 | UPDATE | 기한 지난 `RENTED` → `OVERDUE` |
| Q14 | DELETE | 대여 기록 없는 12번 회원 삭제 |
| Q15 | 인덱스 | `rental(member_id)` 생성 + 실행 계획 전/후 |

Q15 결과에서 인덱스 생성 전에는 `SCAN rental`(전체 훑기),
생성 후에는 `SEARCH rental USING INDEX idx_rental_member (member_id=?)`로 바뀝니다.

## 정리

**엑셀과 DB는 뭐가 다른가?**
엑셀은 대여 기록 행마다 회원 이름·전화번호·책 제목을 반복해 적게 됩니다. 전화번호가 바뀌면 모든 행을 고쳐야 합니다.
DB는 회원·도서·대여를 테이블로 나눠 **한 사실을 한 곳에만** 저장하고, "없는 회원의 대여는 안 된다" 같은 **규칙을 DB가 직접 막아줍니다**.

**PK / FK**
PK는 행 하나를 구분하는 값(`member.id`), FK는 다른 테이블의 PK를 가리키는 값(`rental.member_id`)입니다.
회원 1명에 대여가 여러 개 붙는 것이 1:N이고, FK는 N쪽(`rental`)에 둡니다.

**JOIN과 GROUP BY**
JOIN은 나눠 둔 테이블을 FK = PK 조건으로 다시 이어 붙이는 것, GROUP BY는 같은 값끼리 묶어 `COUNT/SUM/AVG`로 요약하는 것입니다.
INNER JOIN은 짝이 있는 행만, LEFT JOIN은 왼쪽 행을 모두 남기고 짝이 없으면 NULL을 채웁니다 (Q07에서 0회 회원이 나오는 이유).

**인덱스**
책 뒤의 "찾아보기"처럼 특정 컬럼 값으로 행을 바로 찾게 해줍니다. 자주 검색·조인하는 컬럼에 걸고,
INSERT/UPDATE 때마다 같이 갱신되는 비용이 있어서 아무 컬럼에나 걸지는 않습니다.

## SQLite 전용 문법

| 위치 | 문법 | 비고 |
| --- | --- | --- |
| 모든 파일 상단 | `PRAGMA foreign_keys = ON` | MySQL(InnoDB)/PostgreSQL은 FK 기본 활성 |
| Q15 | `EXPLAIN QUERY PLAN` | MySQL/PostgreSQL은 `EXPLAIN` |
