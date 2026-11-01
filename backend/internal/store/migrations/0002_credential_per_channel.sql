-- Satu kredensial aktif per card instance per kanal (temuan review backend I2, SDD §4.2).
CREATE UNIQUE INDEX credentials_one_active_per_channel ON credentials (card_instance_id, channel) WHERE status = 'ACTIVE';
