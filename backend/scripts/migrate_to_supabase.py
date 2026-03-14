import argparse
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import MetaData, Table, and_, create_engine, select
from sqlalchemy.exc import IntegrityError

# Add backend directory to import path
BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.append(str(BACKEND_DIR))

from database import Base


def _load_environment() -> None:
    load_dotenv(BACKEND_DIR / ".env", override=True)


def _build_source_url(cli_source: str | None) -> str:
    if cli_source:
        return cli_source
    sqlite_path = BACKEND_DIR / "calm_clarity.db"
    return f"sqlite:///{sqlite_path}"


def _build_destination_url(cli_dest: str | None) -> str:
    resolved = (cli_dest or os.getenv("DATABASE_URL") or "").strip()
    if not resolved or resolved.startswith("sqlite"):
        raise RuntimeError(
            "DATABASE_URL is not set to a PostgreSQL URL. "
            "Set DATABASE_URL in backend/.env or pass --dest-url."
        )
    return resolved


def _reflect_tables(engine) -> MetaData:
    metadata = MetaData()
    metadata.reflect(bind=engine)
    return metadata


def _row_exists(dest_conn, dest_table: Table, row: dict) -> bool:
    primary_keys = [column.name for column in dest_table.primary_key.columns]
    if not primary_keys:
        return False

    predicate = and_(*[dest_table.c[key] == row[key] for key in primary_keys])
    probe = select(dest_table).where(predicate).limit(1)
    return dest_conn.execute(probe).first() is not None


def migrate_data(*, source_url: str, dest_url: str, dry_run: bool = False) -> None:
    source_engine = create_engine(source_url)
    dest_engine = create_engine(dest_url)

    print(f"Source: {source_url}")
    print(f"Destination: {dest_url}")
    print(f"Mode: {'DRY RUN' if dry_run else 'WRITE'}")

    # Ensure destination schema exists from SQLAlchemy models.
    Base.metadata.create_all(bind=dest_engine)

    source_meta = _reflect_tables(source_engine)
    dest_meta = _reflect_tables(dest_engine)

    shared_names = sorted(set(source_meta.tables).intersection(dest_meta.tables))
    if not shared_names:
        print("No shared tables found between source and destination.")
        return

    totals = {"copied": 0, "skipped": 0, "failed": 0, "tables": 0}

    with source_engine.connect() as source_conn, dest_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    ) as dest_conn:
        for table_name in shared_names:
            src_table = source_meta.tables[table_name]
            dst_table = dest_meta.tables[table_name]

            src_rows = [dict(row._mapping) for row in source_conn.execute(select(src_table)).fetchall()]
            copied = 0
            skipped = 0
            failed = 0

            dst_columns = set(dst_table.c.keys())
            for row in src_rows:
                filtered = {key: value for key, value in row.items() if key in dst_columns}
                if not filtered:
                    skipped += 1
                    continue

                try:
                    if _row_exists(dest_conn, dst_table, filtered):
                        skipped += 1
                        continue

                    if not dry_run:
                        dest_conn.execute(dst_table.insert().values(**filtered))
                    copied += 1
                except IntegrityError:
                    skipped += 1
                except Exception as exc:
                    failed += 1
                    skipped += 1
                    print(
                        f"  [warn table={table_name}] row skipped due to error: {type(exc).__name__}: {exc}"
                    )

            totals["copied"] += copied
            totals["skipped"] += skipped
            totals["failed"] += failed
            totals["tables"] += 1
            print(
                f"[table={table_name}] source_rows={len(src_rows)} copied={copied} skipped={skipped} failed={failed}"
            )

    print("\nMigration completed.")
    print(
        "Tables processed="
        f"{totals['tables']} copied={totals['copied']} "
        f"skipped={totals['skipped']} failed={totals['failed']}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Migrate SQLite data to Supabase/Postgres")
    parser.add_argument(
        "--source-url",
        default=None,
        help="SQLAlchemy source URL (default: sqlite:///backend/calm_clarity.db)",
    )
    parser.add_argument(
        "--dest-url",
        default=None,
        help="Destination PostgreSQL URL (default: DATABASE_URL env)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Inspect and report copy plan without writing rows",
    )
    return parser.parse_args()


if __name__ == "__main__":
    _load_environment()
    args = parse_args()
    src_url = _build_source_url(args.source_url)
    dst_url = _build_destination_url(args.dest_url)
    migrate_data(source_url=src_url, dest_url=dst_url, dry_run=args.dry_run)
