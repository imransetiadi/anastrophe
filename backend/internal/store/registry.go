package store

import (
	"bytes"
	"context"
	"errors"
	"regexp"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// PhysicalCard adalah satu baris registri gedung: hanya HMAC per gedung, tidak pernah identitas
// kartu atau kontak mentah (CLAUDE.md aturan 6; FR-52).
type PhysicalCard struct {
	CardHMAC    []byte // 32 B
	ContactHMAC []byte // 32 B, atau nil bila registri tidak memuat kontak
	ZonesBitmap uint64
}

var (
	// ErrSiteUnsupported: gedung belum punya satu pun kartu aktif di registri (ENR-SITE-UNSUPPORTED).
	ErrSiteUnsupported = errors.New("store: gedung belum punya registri kartu")
	// ErrNotRegistered: tidak ada kartu ACTIVE dengan HMAC itu; kartu REMOVED dijawab sama.
	ErrNotRegistered = errors.New("store: kartu tidak terdaftar")
	// ErrDuplicateEnrollment: perangkat ini sudah memegang card instance aktif untuk kartu itu.
	ErrDuplicateEnrollment = errors.New("store: kartu sudah ada di perangkat ini")
	// ErrPendingLimit: kartu sudah punya MaxPendingPerCard permintaan perangkat tambahan yang menunggu
	// operator (ENR-PENDING-LIMIT, ADR-0047).
	ErrPendingLimit = errors.New("store: terlalu banyak permintaan menunggu untuk kartu ini")
	// ErrNotPending: card instance tidak berstatus PENDING_APPROVAL.
	ErrNotPending = errors.New("store: card instance tidak menunggu persetujuan")
	// ErrInvalidOperator: nama operator kosong atau di luar [A-Za-z0-9._-]{1,64}.
	ErrInvalidOperator = errors.New("store: nama operator tidak valid")

	errInvalidHMAC = errors.New("store: HMAC registri harus 32 byte")
	operatorName   = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
)

// UpsertPhysicalCards menambah atau memperbarui kartu registri gedung dalam satu transaksi, lalu
// mencatat audit registry.imported yang hanya berisi jumlah.
func (s *Store) UpsertPhysicalCards(ctx context.Context, siteID, operator string, cards []PhysicalCard, rejected int, at time.Time) (added, updated int, err error) {
	if !operatorName.MatchString(operator) {
		return 0, 0, ErrInvalidOperator
	}
	if !looksLikeUUID(siteID) {
		return 0, 0, ErrNotFound
	}
	for _, c := range cards {
		if len(c.CardHMAC) != 32 || (c.ContactHMAC != nil && len(c.ContactHMAC) != 32) {
			return 0, 0, errInvalidHMAC
		}
	}
	// Urutan kunci baris tetap (menurut HMAC) agar impor bersamaan dengan kartu bertumpuk tidak
	// saling deadlock (review registri minor 10).
	sorted := slices.Clone(cards)
	slices.SortFunc(sorted, func(a, b PhysicalCard) int { return bytes.Compare(a.CardHMAC, b.CardHMAC) })
	err = pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		added, updated = 0, 0
		var site string
		if err := tx.QueryRow(ctx, `SELECT id::text FROM sites WHERE id = $1`, siteID).Scan(&site); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNotFound
			}
			return err
		}
		for _, c := range sorted {
			var inserted bool
			err := tx.QueryRow(ctx, `
				INSERT INTO physical_cards (id, site_id, card_id_hmac, holder_contact_hmac, zones_bitmap)
				VALUES ($1, $2, $3, $4, $5)
				ON CONFLICT (site_id, card_id_hmac) DO UPDATE
				SET holder_contact_hmac = EXCLUDED.holder_contact_hmac, zones_bitmap = EXCLUDED.zones_bitmap,
				    status = 'ACTIVE', updated_at = now()
				RETURNING xmax = 0`, newUUID(), site, c.CardHMAC, c.ContactHMAC, int64(c.ZonesBitmap)).Scan(&inserted)
			if err != nil {
				return err
			}
			if inserted {
				added++
			} else {
				updated++
			}
		}
		return (&Tx{tx: tx}).AppendAudit(ctx, AuditEvent{
			SiteID: site, Actor: "operator:" + operator, Action: "registry.imported", Subject: "site:" + site,
			Data: map[string]any{"added": added, "updated": updated, "rejected": rejected}, At: at,
		})
	})
	if err != nil {
		return 0, 0, err
	}
	return added, updated, nil
}

// AbandonedEnrollmentTTL: PROVISIONING tanpa kredensial yang melewati batas ini (sejak masuk
// PROVISIONING atau terakhir dilanjutkan) menjadi ABANDONED (ADR-0034).
const AbandonedEnrollmentTTL = 15 * time.Minute

// MaxPendingPerCard: permintaan perangkat tambahan yang boleh menunggu operator per kartu fisik, sama
// dengan default batas anggota (FR-36, ADR-0015). Perangkat yang sudah menunggu tetap bisa melanjutkan
// permintaannya (ADR-0034); permintaan yang ditolak operator tidak dihitung.
const MaxPendingPerCard = 4

// CardEnrollment adalah hasil enrolment kartu. Resumed = instance perangkat yang belum selesai
// dilanjutkan, bukan dibuat baru (ADR-0034).
type CardEnrollment struct {
	ID      string
	Status  string
	Resumed bool
	// Channels: kanal kebijakan gedung (ADR-0049), diisi handler di transaksi enrolment; nil = semua.
	Channels []string
}

// StartCardEnrollment memulai atau melanjutkan enrolment untuk kartu fisik yang cocok dengan
// registri gedung (SDD §8.4.1), dalam transaksi sendiri.
func (s *Store) StartCardEnrollment(ctx context.Context, deviceID, siteID string, cardHMAC []byte, at time.Time) (id, status string, err error) {
	r, err := s.EnrollCard(ctx, deviceID, siteID, cardHMAC, at)
	return r.ID, r.Status, err
}

// EnrollCard seperti StartCardEnrollment, dan melaporkan apakah instance yang ada dilanjutkan.
func (s *Store) EnrollCard(ctx context.Context, deviceID, siteID string, cardHMAC []byte, at time.Time) (CardEnrollment, error) {
	var r CardEnrollment
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var err error
		r, err = (&Tx{tx: tx}).EnrollCard(ctx, deviceID, siteID, cardHMAC, at)
		return err
	})
	if err != nil {
		return CardEnrollment{}, err
	}
	return r, nil
}

// StartCardEnrollment adalah EnrollCard tanpa penanda Resumed.
func (t *Tx) StartCardEnrollment(ctx context.Context, deviceID, siteID string, cardHMAC []byte, at time.Time) (string, string, error) {
	r, err := t.EnrollCard(ctx, deviceID, siteID, cardHMAC, at)
	return r.ID, r.Status, err
}

// EnrollCard: perangkat pertama mendapat PROVISIONING; perangkat lain untuk kartu yang sama mendapat
// PENDING_APPROVAL sampai akun dan keanggotaan ada (ADR-0032). Instance PROVISIONING/PENDING_APPROVAL
// milik perangkat yang sama dilanjutkan, sedangkan ACTIVE/SUSPENDED menjadi duplikat (ADR-0034). Kunci
// diambil berurutan (perangkat, lalu kartu) sehingga enrolment bersamaan tersusun tanpa deadlock.
//
// Audit ditahan sampai akhir (ADR-0051): kunci rantai audit tidak dipegang selama menunggu baris instance,
// yang bisa dipegang sapuan per jam yang sedang menunggu kunci rantai yang sama.
func (t *Tx) EnrollCard(ctx context.Context, deviceID, siteID string, cardHMAC []byte, at time.Time) (CardEnrollment, error) {
	return withDeferredAudits(ctx, t, func() (CardEnrollment, error) {
		return t.enrollCard(ctx, deviceID, siteID, cardHMAC, at, true)
	})
}

// errInstanceChanged: instance yang hendak dilanjutkan berubah status di tengah transaksi (mis. sapuan
// menandainya ABANDONED) dua kali berturut-turut.
var errInstanceChanged = errors.New("store: instance berubah saat dilanjutkan")

func (t *Tx) enrollCard(ctx context.Context, deviceID, siteID string, cardHMAC []byte, at time.Time, retry bool) (CardEnrollment, error) {
	if !looksLikeUUID(deviceID) || !looksLikeUUID(siteID) {
		return CardEnrollment{}, ErrNotFound
	}
	if len(cardHMAC) != 32 {
		return CardEnrollment{}, errInvalidHMAC
	}
	if err := ensureDevice(ctx, t.tx, deviceID); err != nil {
		return CardEnrollment{}, err
	}
	device, _, err := lockDevice(ctx, t.tx, deviceID)
	if err != nil {
		return CardEnrollment{}, err
	}
	var site string
	var hasCards bool
	err = t.tx.QueryRow(ctx, `
		SELECT s.id::text, EXISTS (SELECT 1 FROM physical_cards pc WHERE pc.site_id = s.id AND pc.status = 'ACTIVE')
		FROM sites s WHERE s.id = $1`, siteID).Scan(&site, &hasCards)
	if errors.Is(err, pgx.ErrNoRows) {
		return CardEnrollment{}, ErrNotFound
	}
	if err != nil {
		return CardEnrollment{}, err
	}
	var card string
	err = t.tx.QueryRow(ctx, `SELECT id::text FROM physical_cards WHERE site_id = $1 AND card_id_hmac = $2 AND status = 'ACTIVE' FOR UPDATE`, site, cardHMAC).Scan(&card)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return CardEnrollment{}, err
	}
	if _, err := t.abandonStale(ctx, at, device, card, ""); err != nil {
		return CardEnrollment{}, err
	}
	var active int
	if err := t.tx.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1 AND status = ANY($2)`, device, activeStatuses).Scan(&active); err != nil {
		return CardEnrollment{}, err
	}
	others := false
	pending := 0 // permintaan perangkat lain untuk kartu ini yang menunggu operator
	if card != "" {
		rows, err := t.tx.Query(ctx, `SELECT id::text, device_id::text, status FROM card_instances WHERE physical_card_id = $1 AND status = ANY($2)`, card, activeStatuses)
		if err != nil {
			return CardEnrollment{}, err
		}
		type holder struct{ id, device, status string }
		holders, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (holder, error) {
			var h holder
			err := row.Scan(&h.id, &h.device, &h.status)
			return h, err
		})
		if err != nil {
			return CardEnrollment{}, err
		}
		for _, h := range holders {
			if h.device != device {
				others = true
				if h.status == "PENDING_APPROVAL" {
					pending++
				}
				continue
			}
			if h.status != "PROVISIONING" && h.status != "PENDING_APPROVAL" {
				return CardEnrollment{}, ErrDuplicateEnrollment
			}
			// Melanjutkan PROVISIONING memperpanjang batas waktu terbengkalai. PENDING_APPROVAL hanya dikunci, agar
			// langkah sesudah enrolment di transaksi yang sama (rahasia enrolment, ADR-0040) tidak menunggu baris
			// ini sambil memegang kunci rantai audit (ADR-0051).
			// Dijaga status (review akhir undangan M4): sapuan atau operator bisa mengubah instance setelah
			// dibaca; bila begitu, enrolment diulang sekali.
			var tag pgconn.CommandTag
			if h.status == "PROVISIONING" {
				tag, err = t.tx.Exec(ctx, `UPDATE card_instances SET status_changed_at = $2 WHERE id = $1 AND status = 'PROVISIONING'`, h.id, at)
			} else {
				tag, err = t.tx.Exec(ctx, `SELECT 1 FROM card_instances WHERE id = $1 AND status = 'PENDING_APPROVAL' FOR UPDATE`, h.id)
			}
			if err != nil {
				return CardEnrollment{}, err
			}
			if tag.RowsAffected() != 1 {
				if retry {
					return t.enrollCard(ctx, deviceID, siteID, cardHMAC, at, false)
				}
				return CardEnrollment{}, errInstanceChanged
			}
			return CardEnrollment{ID: h.id, Status: h.status, Resumed: true}, nil
		}
	}
	// Review minor 1: perangkat penuh tidak membedakan kartu terdaftar dan tidak dikenal.
	if active >= MaxActiveCardsPerDevice {
		return CardEnrollment{}, ErrCardLimit
	}
	if !hasCards {
		return CardEnrollment{}, ErrSiteUnsupported
	}
	if card == "" {
		return CardEnrollment{}, ErrNotRegistered
	}
	status := "PROVISIONING"
	if others {
		status = "PENDING_APPROVAL"
		// Review akhir #2 (ADR-0047): baris kartu terkunci FOR UPDATE, jadi hitungan ini atomik.
		if pending >= MaxPendingPerCard {
			return CardEnrollment{}, ErrPendingLimit
		}
	}
	id := newUUID()
	if _, err := t.tx.Exec(ctx, `INSERT INTO card_instances (id, device_id, site_id, physical_card_id, status, status_changed_at) VALUES ($1, $2, $3, $4, $5, $6)`,
		id, device, site, card, status, at); err != nil {
		return CardEnrollment{}, err
	}
	err = t.AppendAudit(ctx, AuditEvent{
		SiteID: site, Actor: "device:" + device, Action: "enrollment.started", Subject: "card_instance:" + id,
		Data: map[string]any{"status": status}, At: at,
	})
	if err != nil {
		return CardEnrollment{}, err
	}
	return CardEnrollment{ID: id, Status: status}, nil
}

// AbandonStaleEnrollments menandai semua PROVISIONING tanpa kredensial yang terbengkalai sebagai
// ABANDONED (sapuan berkala API, ADR-0034).
func (s *Store) AbandonStaleEnrollments(ctx context.Context, at time.Time) (int, error) {
	var n int
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var err error
		t := &Tx{tx: tx}
		// ADR-0051: audit ditulis sesudah semua baris terkunci, berurutan per rantai.
		n, err = withDeferredAudits(ctx, t, func() (int, error) { return t.abandonStale(ctx, at, "", "", "") })
		return err
	})
	return n, err
}

// abandonStale menandai PROVISIONING tanpa kredensial yang melewati AbandonedEnrollmentTTL sebagai
// ABANDONED, untuk perangkat, kartu, atau undangan tertentu (semuanya kosong = semua), dengan audit per
// instance.
// Baris yang sedang dikunci transaksi lain (mis. penerbitan kredensial) dilewati agar tidak deadlock.
func (t *Tx) abandonStale(ctx context.Context, at time.Time, device, card, invitation string) (int, error) {
	var deviceParam, cardParam, invitationParam any
	if device != "" {
		deviceParam = device
	}
	if card != "" {
		cardParam = card
	}
	if invitation != "" {
		invitationParam = invitation
	}
	rows, err := t.tx.Query(ctx, `
		UPDATE card_instances ci SET status = 'ABANDONED', status_changed_at = $1
		WHERE ci.id IN (
			SELECT x.id FROM card_instances x
			WHERE x.status = 'PROVISIONING' AND x.status_changed_at < $2
			  AND (($3::uuid IS NULL AND $4::uuid IS NULL AND $5::uuid IS NULL)
			       OR x.device_id = $3::uuid OR x.physical_card_id = $4::uuid OR x.invitation_id = $5::uuid)
			  AND NOT EXISTS (SELECT 1 FROM credentials c WHERE c.card_instance_id = x.id)
			ORDER BY x.id
			FOR UPDATE OF x SKIP LOCKED)
		RETURNING ci.id::text, ci.site_id::text`, at, at.Add(-AbandonedEnrollmentTTL), deviceParam, cardParam, invitationParam)
	if err != nil {
		return 0, err
	}
	type abandoned struct{ id, site string }
	list, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (abandoned, error) {
		var a abandoned
		err := row.Scan(&a.id, &a.site)
		return a, err
	})
	if err != nil {
		return 0, err
	}
	for _, a := range list {
		if err := t.AppendAudit(ctx, AuditEvent{SiteID: a.site, Actor: "system", Action: "enrollment.abandoned", Subject: "card_instance:" + a.id, At: at}); err != nil {
			return 0, err
		}
	}
	return len(list), nil
}

// DecideEnrollment: operator menyetujui (PROVISIONING) atau menolak (REJECTED) card instance
// PENDING_APPROVAL (ADR-0032), dengan audit enrollment.approved atau enrollment.rejected.
func (s *Store) DecideEnrollment(ctx context.Context, cardInstanceID string, approve bool, operator string, at time.Time) error {
	if !operatorName.MatchString(operator) {
		return ErrInvalidOperator
	}
	if !looksLikeUUID(cardInstanceID) {
		return ErrNotFound
	}
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var id, site, status string
		err := tx.QueryRow(ctx, `SELECT id::text, site_id::text, status FROM card_instances WHERE id = $1 FOR UPDATE`, cardInstanceID).Scan(&id, &site, &status)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if status != "PENDING_APPROVAL" {
			return ErrNotPending
		}
		next, action := "REJECTED", "enrollment.rejected"
		if approve {
			next, action = "PROVISIONING", "enrollment.approved"
		}
		if _, err := tx.Exec(ctx, `UPDATE card_instances SET status = $2, status_changed_at = $3 WHERE id = $1`, id, next, at); err != nil {
			return err
		}
		return (&Tx{tx: tx}).AppendAudit(ctx, AuditEvent{
			SiteID: site, Actor: "operator:" + operator, Action: action, Subject: "card_instance:" + id, At: at,
		})
	})
}

// ensureDevice membuat baris perangkat app yang belum terdaftar di dalam transaksi enrolment (ADR-0045).
// device_id dibuat app (UUID v4 acak); enrolment yang ditolak me-rollback transaksi sehingga tidak ada
// baris perangkat yang tertinggal. Baris dari enrolment yang berhasil tidak dibatasi jumlah kartu
// terdaftar: satu identitas kartu dengan device_id acak bisa terus membuat permintaan menunggu, jadi
// jumlahnya per kartu dibatasi MaxPendingPerCard (review akhir #2, ADR-0047).
func ensureDevice(ctx context.Context, tx pgx.Tx, deviceID string) error {
	_, err := tx.Exec(ctx, `INSERT INTO devices (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`, deviceID)
	return err
}

// lockDevice mengunci baris perangkat dan menghitung card instance aktifnya (FR-15).
func lockDevice(ctx context.Context, tx pgx.Tx, deviceID string) (device string, active int, err error) {
	if err := tx.QueryRow(ctx, `SELECT id::text FROM devices WHERE id = $1 FOR UPDATE`, deviceID).Scan(&device); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", 0, ErrNotFound
		}
		return "", 0, err
	}
	err = tx.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1 AND status = ANY($2)`, device, activeStatuses).Scan(&active)
	return device, active, err
}

// applyCardZones: kartu terdaftar menentukan zona (FR-52). Nama zona diambil dari daftar zona
// gedung untuk bit yang menyala; bitmap 0 tidak membuka zona apa pun (fail-closed).
func (e *Enrollment) applyCardZones(names []string, bitmap uint64) {
	e.ZonesBitmap = bitmap
	e.Zones = []string{}
	for i, name := range names {
		if i < 64 && bitmap&(1<<uint(i)) != 0 {
			e.Zones = append(e.Zones, name)
		}
	}
}

// SiteZoneNames mengembalikan nama zona gedung dari sites.policy; indeks = nomor bit zona.
func (s *Store) SiteZoneNames(ctx context.Context, siteID string) ([]string, error) {
	if !looksLikeUUID(siteID) {
		return nil, ErrNotFound
	}
	var names []string
	err := s.pool.QueryRow(ctx, `SELECT `+zonesSQL("policy")+` FROM sites WHERE id = $1`, siteID).Scan(&names)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return names, err
}
