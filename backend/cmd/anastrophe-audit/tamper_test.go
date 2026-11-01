package main

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// tamperSecondRow meniru DBA yang mematikan trigger lalu mengubah baris (khusus test).
func tamperSecondRow(ctx context.Context, dsn string) error {
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	if _, err := conn.Exec(ctx, `ALTER TABLE audit_events DISABLE TRIGGER USER`); err != nil {
		return err
	}
	_, err = conn.Exec(ctx, `UPDATE audit_events SET actor = 'device:palsu' WHERE seq = 2`)
	return err
}
