package testutil

import (
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"testing"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	_ "github.com/lib/pq"

	dbmigrations "wordchain/backend/migrations"
)

// NewPostgres returns a connection to a fresh, fully migrated database created
// on the server named by TEST_DATABASE_URL (e.g.
// postgres://wordchain:wordchain@localhost:5432/wordchain?sslmode=disable) and
// dropped when the test ends. The test is skipped when the variable is unset,
// so `go test ./...` stays green without a database.
func NewPostgres(t *testing.T) *sql.DB {
	t.Helper()
	base := os.Getenv("TEST_DATABASE_URL")
	if base == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	admin, err := sql.Open("postgres", base)
	if err != nil {
		t.Fatalf("open admin db: %v", err)
	}
	name := fmt.Sprintf("wc_test_%d_%d", os.Getpid(), testCounter())
	if _, err := admin.Exec("CREATE DATABASE " + name); err != nil {
		admin.Close()
		t.Fatalf("create test database: %v", err)
	}

	u, err := url.Parse(base)
	if err != nil {
		t.Fatalf("parse TEST_DATABASE_URL: %v", err)
	}
	u.Path = "/" + name
	db, err := sql.Open("postgres", u.String())
	if err != nil {
		t.Fatalf("open test db: %v", err)
	}
	t.Cleanup(func() {
		db.Close()
		admin.Exec("DROP DATABASE IF EXISTS " + name + " WITH (FORCE)")
		admin.Close()
	})

	src, err := iofs.New(dbmigrations.FS, ".")
	if err != nil {
		t.Fatalf("iofs: %v", err)
	}
	driver, err := postgres.WithInstance(db, &postgres.Config{})
	if err != nil {
		t.Fatalf("migrate driver: %v", err)
	}
	m, err := migrate.NewWithInstance("iofs", src, "postgres", driver)
	if err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if err := m.Up(); err != nil {
		t.Fatalf("migrate up: %v", err)
	}
	return db
}

var pgCounter int

func testCounter() int {
	pgCounter++
	return pgCounter
}
