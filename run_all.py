"""DB를 새로 만들고 모든 SQL을 실행해 쿼리별 결과를 results/ 에 텍스트로 저장한다.

사용법: python3 run_all.py
필요  : sqlite3 CLI (macOS 기본 포함)
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).parent
SQL = ROOT / "sql"
DB = ROOT / "library.db"
RESULTS = ROOT / "results"

# "-- [Q01] 설명" / "-- [B1-a] 설명" 형태의 줄에서 쿼리 블록이 시작된다
MARKER = re.compile(r"^-- \[((?:Q|B)[\w-]+)\]\s*(.*)$", re.M)
# 블록 사이의 구분선 주석은 결과에서 뺀다
DIVIDER = re.compile(r"^-- ─.*$", re.M)


def sqlite(sql: str) -> str:
    """sqlite3 CLI 로 실행. 에러도 결과로 남기기 위해 stderr 를 합친다."""
    proc = subprocess.run(
        ["sqlite3", str(DB)],
        input=sql,
        capture_output=True,
        text=True,
    )
    return proc.stdout + proc.stderr


def run_file(name: str) -> None:
    text = (SQL / name).read_text()
    matches = list(MARKER.finditer(text))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = DIVIDER.sub("", text[m.start():end]).strip()
        qid, desc = m.group(1), m.group(2)
        script = "\n".join([
            "PRAGMA foreign_keys = ON;",
            ".headers on",
            ".mode box",
            ".echo on",
            block,
        ])
        out = sqlite(script)
        # 매 블록 앞에 붙인 설정 명령은 결과 파일에서 뺀다
        out = re.sub(r"^\.(headers|mode|echo) .*\n", "", out, flags=re.M)
        (RESULTS / f"{qid}.txt").write_text(f"# [{qid}] {desc}\n\n{out}")
        print(f"{qid:6} {desc}")


def main() -> None:
    DB.unlink(missing_ok=True)
    RESULTS.mkdir(exist_ok=True)
    for old in RESULTS.glob("*.txt"):
        old.unlink()

    for name in ("01_schema.sql", "02_data.sql"):
        out = sqlite((SQL / name).read_text())
        if out.strip():
            raise SystemExit(f"{name} 실행 실패:\n{out}")

    counts = sqlite(
        ".mode box\n.headers on\n"
        "SELECT 'category' AS table_name, COUNT(*) AS row_count FROM category UNION ALL "
        "SELECT 'member', COUNT(*) FROM member UNION ALL "
        "SELECT 'book',   COUNT(*) FROM book   UNION ALL "
        "SELECT 'rental', COUNT(*) FROM rental UNION ALL "
        "SELECT 'review', COUNT(*) FROM review;"
    )
    (RESULTS / "00_row_counts.txt").write_text("# 샘플 데이터 입력 직후 테이블별 행 수\n\n" + counts)

    run_file("03_queries.sql")
    run_file("04_bonus.sql")


if __name__ == "__main__":
    main()
