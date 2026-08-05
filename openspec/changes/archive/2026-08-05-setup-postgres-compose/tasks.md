## 1. Environment configuration

- [x] 1.1 Create `.env.example` at repo root with `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT` (placeholder values, `POSTGRES_PORT` defaulted to `5432`)
- [x] 1.2 Add `.env` to `.gitignore` (create `.gitignore` if it doesn't already exist)

## 2. Compose file

- [x] 2.1 Create `docker-compose.yml` at repo root with a `postgres` service using `pgvector/pgvector:pg18`
- [x] 2.2 Configure `environment:` block referencing `${POSTGRES_USER}`, `${POSTGRES_PASSWORD}` (no default), `${POSTGRES_DB}`
- [x] 2.3 Map host port via `${POSTGRES_PORT:-5432}:5432`
- [x] 2.4 Add named volume `postgres_data:/var/lib/postgresql` and declare it under top-level `volumes:` (pg18+ images require mounting at the parent path, not the legacy `/var/lib/postgresql/data`)
- [x] 2.5 Add a `healthcheck:` using `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}`

## 3. Verification

- [x] 3.1 Copy `.env.example` to `.env`, fill in real values, run `docker compose up -d postgres`, confirm `docker compose ps` shows `healthy`
- [x] 3.2 Connect via `docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB` and run `CREATE EXTENSION IF NOT EXISTS vector;` — confirm it succeeds
- [x] 3.3 In the same session, create a scratch table with a `tsvector` column and a GIN index — confirm it succeeds without extra extensions
- [x] 3.4 Confirm running without `POSTGRES_PASSWORD` set fails/refuses to start rather than booting with a blank password
- [x] 3.5 Write data, run `docker compose down` (no `-v`), `docker compose up -d postgres` again, confirm the data is still present
- [x] 3.6 Run `git status` and confirm `.env` does not appear as trackable/untracked
