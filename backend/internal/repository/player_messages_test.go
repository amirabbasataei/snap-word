package repository_test

import (
	"context"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/testutil"
)

const (
	msgUserA = "eeeeeeee-0000-4000-8000-00000000000a"
	msgUserB = "eeeeeeee-0000-4000-8000-00000000000b"
	msgMatch = "eeeeeeee-0000-4000-8000-0000000000f1"
)

func TestGrantWelcomePremium(t *testing.T) {
	db := testutil.NewPostgres(t)
	repo := repository.NewUserRepository(db)
	ctx := context.Background()
	if _, err := db.Exec(`INSERT INTO users (id, phone) VALUES ($1, '09120000011')`, msgUserA); err != nil {
		t.Fatal(err)
	}

	if err := repo.GrantWelcomePremium(ctx, msgUserA, config.WelcomeCampaignID, config.WelcomePremiumDays); err != nil {
		t.Fatal(err)
	}
	until, err := repo.GetPremiumUntil(ctx, msgUserA)
	if err != nil || until == nil {
		t.Fatalf("premium_until = %v, %v", until, err)
	}
	if d := time.Until(*until); d < 6*24*time.Hour+23*time.Hour || d > 7*24*time.Hour+time.Minute {
		t.Fatalf("premium lasts %v, want ~7 days", d)
	}
	perks, _ := repo.GetPerks(ctx, []string{msgUserA})
	if !perks[msgUserA].Premium {
		t.Fatal("the user should be premium now")
	}

	// The gift message is visible in the player's inbox, once.
	inbox := repository.NewInboxRepository(db)
	msgs, err := inbox.ListUnread(ctx, msgUserA)
	if err != nil || len(msgs) != 1 || msgs[0].Route != "/profile" {
		t.Fatalf("inbox = %+v, %v", msgs, err)
	}

	// A repeat keeps the message single and the counters honest.
	if err := repo.GrantWelcomePremium(ctx, msgUserA, config.WelcomeCampaignID, config.WelcomePremiumDays); err != nil {
		t.Fatal(err)
	}
	if msgs, _ = inbox.ListUnread(ctx, msgUserA); len(msgs) != 1 {
		t.Fatalf("repeat grant duplicated the message: %+v", msgs)
	}
	var delivered int
	if err := db.QueryRow(`SELECT inapp_delivered FROM notification_campaigns WHERE id = $1`, config.WelcomeCampaignID).Scan(&delivered); err != nil || delivered != 1 {
		t.Fatalf("inapp_delivered = %d, %v", delivered, err)
	}
}

func TestPlayerMessagesStoreAndAdminList(t *testing.T) {
	db := testutil.NewPostgres(t)
	ctx := context.Background()
	for _, u := range []struct{ id, phone, name string }{{msgUserA, "09120000011", "ali"}, {msgUserB, "09120000012", "sara"}} {
		if _, err := db.Exec(`INSERT INTO users (id, phone, username) VALUES ($1, $2, $3)`, u.id, u.phone, u.name); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`INSERT INTO matches (id, mode, status) VALUES ($1, 'classic', 'finished')`, msgMatch); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{msgUserA, msgUserB} {
		if _, err := db.Exec(`INSERT INTO match_players (match_id, user_id) VALUES ($1, $2)`, msgMatch, id); err != nil {
			t.Fatal(err)
		}
	}

	store := repository.NewPlayerMessageRepository(db)
	for _, m := range []repository.PlayerMessage{
		{MatchID: msgMatch, SenderID: msgUserA, Kind: repository.MessageKindPreset, TauntID: "hurry_up", Text: "زود باش!"},
		{MatchID: msgMatch, SenderID: msgUserA, Kind: repository.MessageKindCustom, Text: "سلام رفیق"},
		{SenderID: msgUserB, Kind: repository.MessageKindCustom, Text: "بدون مسابقه"},
	} {
		if err := store.Insert(ctx, m); err != nil {
			t.Fatal(err)
		}
	}

	admin := repository.NewAdminRepository(db)
	list := func(p repository.AdminMessageListParams) ([]repository.AdminMessageRow, int) {
		t.Helper()
		p.Page, p.PageSize = 1, 25
		rows, total, err := admin.ListMessages(ctx, p)
		if err != nil {
			t.Fatal(err)
		}
		return rows, total
	}

	if rows, total := list(repository.AdminMessageListParams{}); total != 3 || len(rows) != 3 {
		t.Fatalf("all = %d / %d", total, len(rows))
	}
	rows, total := list(repository.AdminMessageListParams{Kind: repository.MessageKindCustom, Query: "ali"})
	if total != 1 || rows[0].Text != "سلام رفیق" || rows[0].SenderName != "ali" || rows[0].OpponentName != "sara" || rows[0].MatchID != msgMatch {
		t.Fatalf("custom by ali = %+v (%d)", rows, total)
	}
	if _, total = list(repository.AdminMessageListParams{Query: msgMatch}); total != 2 {
		t.Fatalf("by match id = %d, want 2", total)
	}
	if rows, total = list(repository.AdminMessageListParams{Query: "رفیق"}); total != 1 {
		t.Fatalf("by text = %d, want 1", total)
	}
	if rows, _ = list(repository.AdminMessageListParams{Query: msgUserB}); rows[0].OpponentID != "" {
		t.Fatalf("a message without a match has no opponent: %+v", rows[0])
	}
	if _, total = list(repository.AdminMessageListParams{From: time.Now().Add(time.Hour)}); total != 0 {
		t.Fatalf("future range = %d", total)
	}
}
