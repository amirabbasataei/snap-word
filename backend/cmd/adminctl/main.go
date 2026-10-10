// adminctl bootstraps and maintains admin panel accounts. It talks straight to
// the database (DATABASE_URL), so it works before any admin exists.
//
//	adminctl create-user <username> [owner|operator|viewer]   (default role: owner)
//	adminctl set-password <username>
//	adminctl disable <username>
//	adminctl enable <username>
//
// The password is read from the terminal without echo (or from the first line
// of stdin when it is not a terminal) — never from argv, which would leak into
// the process list and shell history.
package main

import (
	"bufio"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"strings"
	"syscall"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"golang.org/x/term"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "adminctl:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) < 2 {
		return errors.New("usage: adminctl create-user <username> [owner|operator|viewer] | set-password <username> | disable <username> | enable <username>")
	}
	cmd, username := args[0], args[1]

	cfg := config.Load()
	db, err := sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("open database: %w", err)
	}
	defer db.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}

	// Redis is needed to end a changed/disabled admin's live sessions.
	var rdb *redis.Client
	if opts, err := redis.ParseURL(cfg.RedisURL); err == nil {
		rdb = redis.NewClient(opts)
		defer rdb.Close()
	}
	svc := service.NewAdminAuthService(repository.NewAdminRepository(db), rdb, cfg)

	switch cmd {
	case "create-user":
		role := service.AdminRoleOwner
		if len(args) > 2 {
			role = args[2]
		}
		pw, err := readNewPassword()
		if err != nil {
			return err
		}
		admin, err := svc.CreateAdmin(ctx, username, pw, role)
		if err != nil {
			return describe(err)
		}
		fmt.Printf("created %s (%s)\n", admin.Username, admin.Role)
	case "set-password":
		pw, err := readNewPassword()
		if err != nil {
			return err
		}
		if err := svc.SetPassword(ctx, username, pw); err != nil {
			return describe(err)
		}
		fmt.Printf("password updated for %s; their sessions were ended\n", username)
	case "disable":
		if err := svc.SetDisabled(ctx, username, true); err != nil {
			return describe(err)
		}
		fmt.Printf("%s disabled; their sessions were ended\n", username)
	case "enable":
		if err := svc.SetDisabled(ctx, username, false); err != nil {
			return describe(err)
		}
		fmt.Printf("%s enabled\n", username)
	default:
		return fmt.Errorf("unknown command %q", cmd)
	}
	return nil
}

func describe(err error) error {
	switch {
	case errors.Is(err, service.ErrAdminInvalidUsername):
		return errors.New("username must be 3-32 chars: lowercase letter first, then letters, digits, _ . -")
	case errors.Is(err, service.ErrAdminInvalidRole):
		return errors.New("role must be owner, operator or viewer")
	case errors.Is(err, service.ErrAdminWeakPassword):
		return fmt.Errorf("password must be %d-72 characters", config.AdminPasswordMinLength)
	case errors.Is(err, service.ErrAdminUsernameTaken):
		return errors.New("that username already exists")
	case errors.Is(err, service.ErrAdminNotFound):
		return errors.New("no such admin")
	}
	return err
}

func readNewPassword() (string, error) {
	first, err := readPassword("Password: ")
	if err != nil {
		return "", err
	}
	if term.IsTerminal(int(syscall.Stdin)) {
		second, err := readPassword("Repeat password: ")
		if err != nil {
			return "", err
		}
		if first != second {
			return "", errors.New("passwords do not match")
		}
	}
	return first, nil
}

func readPassword(prompt string) (string, error) {
	if term.IsTerminal(int(syscall.Stdin)) {
		fmt.Fprint(os.Stderr, prompt)
		b, err := term.ReadPassword(int(syscall.Stdin))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			return "", fmt.Errorf("read password: %w", err)
		}
		return string(b), nil
	}
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && line == "" {
		return "", fmt.Errorf("read password from stdin: %w", err)
	}
	return strings.TrimRight(line, "\r\n"), nil
}
