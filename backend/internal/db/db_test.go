package db

import (
	"strings"
	"testing"
)

func TestMigrationsOrdered(t *testing.T) {
	migs, err := Migrations()
	if err != nil {
		t.Fatal(err)
	}
	if len(migs) < 2 {
		t.Fatalf("expected at least 2 migrations, got %d", len(migs))
	}
	if migs[0].Version != "001_init" {
		t.Fatalf("first migration must stay 001_init (recorded in prod), got %s", migs[0].Version)
	}
	for i := 1; i < len(migs); i++ {
		if migs[i-1].Version >= migs[i].Version {
			t.Fatalf("migrations out of order: %s >= %s", migs[i-1].Version, migs[i].Version)
		}
		if strings.TrimSpace(migs[i].SQL) == "" {
			t.Fatalf("empty migration %s", migs[i].Version)
		}
	}
}
