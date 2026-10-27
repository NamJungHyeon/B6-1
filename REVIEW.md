# 동료 평가 설명서

평가 항목 순서대로, 근거가 되는 파일과 실행 결과를 함께 적었습니다.
모든 쿼리 결과는 [results/result.txt](results/result.txt) 한 파일에 쿼리 원문과 함께 있습니다.

---

## 1. 기능 동작 검증

### 최소 4개 테이블 + 각 테이블 PK

4개 테이블이고 모두 `id INTEGER PRIMARY KEY` 를 가집니다. → [schema.sql](schema.sql)

| 테이블 | PK | 역할 |
| --- | --- | --- |
| `category` | `id` | 도서 분류 |
| `member` | `id` | 회원 |
| `book` | `id` | 도서 |
| `rental` | `id` | 대여 기록 (누가 · 무엇을 · 언제 빌리고 반납했나) |

### FK 1:N 관계 2개 이상

1:N 관계는 3개입니다.

```
category 1 ── N book      book.category_id  → category.id
member   1 ── N rental    rental.member_id  → member.id
book     1 ── N rental    rental.book_id    → book.id
```

없는 값이 막히는지 직접 확인할 수 있습니다.

```sql
-- 없는 회원 999번으로 대여 입력
INSERT INTO rental (id, member_id, book_id, rented_at, due_date, status)
VALUES (100, 999, 1, '2026-09-28', '2026-10-12', 'RENTED');
-- Error: FOREIGN KEY constraint failed
```

SQLite 는 FK 검사가 **기본으로 꺼져 있고 접속할 때마다 켜야** 합니다.
그래서 모든 `.sql` 파일 첫 줄에 `PRAGMA foreign_keys = ON;` 을 넣었습니다.

### 각 테이블 10행 이상

| category | member | book | rental |
| --- | --- | --- | --- |
| 10 | 12 | 15 | 25 |

### 쿼리 15개 (범주별 최소 개수)

→ [queries.sql](queries.sql)

| 범주 | 요구 | 작성 | 쿼리 |
| --- | --- | --- | --- |
| 기본 조회 (`WHERE`/`ORDER BY`/`LIMIT`) | 4 | 4 | Q01–Q04 |
| 조인 (INNER 2+, LEFT 1+) | 4 | 4 (INNER 2, LEFT 2) | Q05–Q08 |
| 집계 (`COUNT`/`SUM`/`AVG` + `GROUP BY`) | 3 | 3 | Q09–Q11 |
| 서브쿼리 | 1 | 1 | Q12 |
| 수정·삭제 | 2 | 2 (UPDATE 1, DELETE 1) | Q13, Q14 |
| 인덱스 (+ 이유 1줄) | 1 | 1 | Q15 |

---

## 2. 코드 구조 및 설계

### 테이블을 왜 이렇게 나눴나

- `member`, `book`, `category` 는 대여가 없어도 존재하는 **대상**입니다.
- `rental` 은 회원과 책 사이에서 일어나는 **사건**입니다. 한 번 빌릴 때마다 한 행이 생깁니다.

`book` 에 `borrower_name` 컬럼을 두면 책 한 권을 여러 번 빌린 이력을 남길 수 없습니다.
반대로 `rental` 에 회원 이름·전화번호를 직접 적으면 같은 정보가 대여 건수만큼 복사됩니다.
그래서 `rental` 은 **번호(FK)만 들고 있고**, 필요할 때 JOIN 으로 붙여 봅니다.

### 1:N 관계가 뜻하는 것

회원 **김민지(member.id = 1)** 한 명에게 대여 기록 **4건**이 붙어 있습니다 (Q07).

- **member 1 : N rental** — 한 회원은 여러 번 빌리지만, 대여 한 건의 주인은 한 명
- **book 1 : N rental** — "달빛 서점의 비밀"은 5번 대여됨
- **category 1 : N book** — "컴퓨터/IT" 카테고리에 도서 3권

`member` 와 `book` 은 `rental` 을 사이에 둔 **N:M** 입니다.

### 컬럼 타입 선택 이유

| 컬럼 | 타입 | 이유 |
| --- | --- | --- |
| `id`, `*_id` | `INTEGER` | 비교·JOIN 이 빠르고 단순 |
| `price`, `late_fee` | `INTEGER` | 원화는 소수점이 없음. 실수(`REAL`)는 오차가 생겨 돈에 부적합 |
| `name`, `title` | `VARCHAR(n)` | 문자열 |
| `rented_at`, `due_date`, `returned_at` | `DATE` | 날짜만 필요. `'2026-09-28'` 형식이라 문자열 비교 = 날짜 비교 |
| `status` | `VARCHAR` + `CHECK IN (...)` | 정해진 값만 허용. 오타(`RENTD`)는 INSERT 실패 |

`returned_at` 만 NULL 을 허용했습니다. **"아직 반납 안 함"을 NULL 로 표현**하기 위해서입니다 (Q06).

### 인덱스: 어디에, 왜

```sql
CREATE INDEX idx_rental_member ON rental (member_id);
```

- `rental` 은 대여할 때마다 행이 쌓이는, 가장 빨리 커지는 테이블입니다.
- "회원별 대여 내역"을 찾을 때 `member_id` 로 자주 검색·조인합니다.
- PK 는 자동으로 인덱스가 생기지만 **FK 컬럼에는 자동으로 생기지 않습니다.**

```
-- 생성 전
`--SCAN rental                                                   ← 전체 행을 다 읽음
-- 생성 후
`--SEARCH rental USING INDEX idx_rental_member (member_id=?)     ← 인덱스로 바로 찾음
```

---

## 3. 핵심 기술 원리

### DB 는 엑셀과 무엇이 다른가

엑셀 대여 장부는 보통 한 시트에 이렇게 적습니다.

| 대여일 | 회원 | 전화번호 | 책 제목 |
| --- | --- | --- | --- |
| 06-02 | 김민지 | 010-1111-0001 | 달빛 서점의 비밀 |
| 06-20 | 김민지 | 010-1111-0001 | 오늘도 천천히 |

1. **중복** — 전화번호가 대여 건수만큼 반복됩니다.
2. **수정 이상** — 번호가 바뀌면 모든 행을 고쳐야 합니다.
3. **규칙이 없음** — 없는 회원, 오타 난 상태값이 그냥 들어갑니다.

DB 는 **한 사실을 한 곳에만** 저장하고, FK·UNIQUE·CHECK·NOT NULL 로 **규칙을 DB 가 강제**합니다.

### PK 와 FK

- **PK (`member.id`)**: 이 테이블 안에서 "나는 누구인가". 중복·NULL 불가.
- **FK (`rental.member_id`)**: "나는 누구의 것인가". 부모 PK 에 실제로 있는 값만 들어갈 수 있음.

**FK 는 항상 N 쪽 테이블에 둡니다.** `member` 에 `rental_id` 를 두면 회원 한 명당 대여 한 건밖에 적을 수 없기 때문입니다.

### INNER JOIN vs LEFT JOIN

같은 "회원별 대여 횟수"를 두 방식으로 뽑으면 행 수가 다릅니다.

| | 결과 행 수 | 서예린(11), 문재원(12) |
| --- | --- | --- |
| `INNER JOIN` | 10명 | 안 나옴 — rental 에 짝이 없음 |
| `LEFT JOIN` (Q07) | 12명 | 0 으로 나옴 — 왼쪽(member) 행은 무조건 남김 |

Q08 은 이 NULL 을 이용합니다. `LEFT JOIN` 후 `WHERE r.id IS NULL` 이면 한 번도 대여되지 않은 책만 남습니다.

**주의**: LEFT JOIN 에서 개수를 셀 때 `COUNT(*)` 가 아니라 `COUNT(r.id)` 를 썼습니다.
`COUNT(*)` 는 NULL 로 채워진 행도 1 로 세서, 대여 0회 회원이 1회로 나옵니다.

### GROUP BY 와 집계 함수

GROUP BY 는 **같은 값끼리 묶어서 묶음마다 한 줄로 요약**합니다.

```
Q09  rental 25행 → status 로 묶음 → RETURNED 16 / RENTED 7 / OVERDUE 2
Q10  book 15행   → category_id 로 묶음 → 6번(컴퓨터/IT) 평균 (28000+32000+30000)/3 = 30000
Q11  rental 25행 → member_id 로 묶음 → 5번 회원 연체료 합계 3000
```

`SELECT` 에는 `GROUP BY` 에 쓴 컬럼이나 집계 함수만 올 수 있습니다.

---

## 4. 심층 인터뷰

### 가장 복잡했던 쿼리: Q06 (3개 테이블 INNER JOIN)

"아직 반납하지 않은 대여를 회원 이름·책 제목과 함께" 보여주는 쿼리입니다.

```sql
SELECT r.id AS rental_id, m.name AS member_name, b.title AS book_title, r.due_date
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.returned_at IS NULL
ORDER BY r.due_date;
```

`rental` 에는 번호만 있으므로, `member_id` 로 회원 이름을, `book_id` 로 책 제목을 각각 붙였습니다.
미반납은 `= NULL` 이 아니라 `IS NULL` 로 찾아야 합니다 (NULL 은 `=` 비교가 항상 거짓).

### 어려웠던 부분과 해결

**① FK 를 걸어도 SQLite 는 기본으로 막지 않는다**
FK 검사는 접속마다 꺼져 있어서, 모든 `.sql` 파일 맨 위에 `PRAGMA foreign_keys = ON;` 을 넣었습니다.

**② 결과가 "의미 있게" 나오도록 데이터 설계하기**
모든 회원이 대여한 데이터면 LEFT JOIN 과 INNER JOIN 결과가 똑같아서 차이를 보여줄 수 없습니다.
그래서 일부러 케이스를 심었습니다.

| 의도한 케이스 | 심은 데이터 | 드러나는 쿼리 |
| --- | --- | --- |
| 대여 0회 회원 | 11, 12번 회원 | Q07, Q14 |
| 대여된 적 없는 책 | 14, 15번 도서 | Q08 |
| 기한 지났는데 상태 미갱신 | rental 19, 20번 | Q13 UPDATE |

**③ 실행할 때마다 결과가 바뀌는 문제**
`DATE('now')` 를 쓰면 실행하는 날마다 결과가 달라져 첨부한 결과와 맞지 않게 됩니다.
그래서 기준일을 **2026-09-28 로 고정**해 날짜를 직접 적었습니다.
