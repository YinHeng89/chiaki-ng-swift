#!/usr/bin/env python3
"""Schema contract tests; synthetic blobs here are not real encrypted credentials."""
import pathlib
import sqlite3
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]

class ProfileSchemaTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.addCleanup(self.db.close)
        self.db.execute('PRAGMA foreign_keys = ON')
        for migration in sorted((ROOT / 'Sources/ChiakiPersistence/Resources/Migrations').glob('*.sql')):
            self.db.executescript(migration.read_text())

    def profile(self, identity='p', account=b'12345678', method='account_id'):
        self.db.execute('INSERT INTO profiles(id,display_name,auth_method,psn_account_id) VALUES(?,?,?,?)',
                        (identity, 'Example', method, account))

    def console(self, identity='c'):
        self.db.execute('INSERT INTO consoles(id,name,generation) VALUES(?,?,?)', (identity, 'Console', 'ps5'))

    def link(self, identity, profile, console):
        self.db.execute('INSERT INTO registrations(id,profile_id,console_id,encrypted_credentials,key_version) VALUES(?,?,?,?,1)',
                        (identity, profile, console, b'synthetic-envelope'))

    def test_saved_profiles_require_eight_byte_identity(self):
        for account in (None, b'', b'1234567', '12345678'):
            with self.assertRaises(sqlite3.IntegrityError):
                self.profile(account=account, method='npsso')
        self.profile(method='npsso')

    def test_many_to_many_and_profile_deletion(self):
        self.profile('p1'); self.profile('p2')
        self.console('c1'); self.console('c2')
        self.link('r1', 'p1', 'c1'); self.link('r2', 'p2', 'c1'); self.link('r3', 'p1', 'c2')
        with self.assertRaises(sqlite3.IntegrityError):
            self.link('duplicate', 'p1', 'c1')
        self.db.execute("DELETE FROM profiles WHERE id='p1'")
        self.assertEqual(self.db.execute('SELECT count(*) FROM consoles').fetchone()[0], 2)
        self.assertEqual(self.db.execute('SELECT count(*) FROM registrations').fetchone()[0], 1)
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_separate_token_kinds_and_cascade(self):
        self.profile(method='npsso')
        for kind in ('remote_play', 'mobile_sso'):
            self.db.execute('INSERT INTO profile_tokens(profile_id,credential_kind,encrypted_tokens,key_version,expires_at) VALUES(?,?,?,1,?)',
                            ('p', kind, b'synthetic-envelope', 1789603200000))
        self.assertEqual(self.db.execute('SELECT count(*) FROM profile_tokens').fetchone()[0], 2)
        self.db.execute("DELETE FROM profiles WHERE id='p'")
        self.assertEqual(self.db.execute('SELECT count(*) FROM profile_tokens').fetchone()[0], 0)

    def test_failed_credentials_transaction_rolls_back_profile(self):
        with self.assertRaises(sqlite3.IntegrityError):
            with self.db:
                self.profile(method='npsso')
                self.db.execute("INSERT INTO profile_tokens(profile_id,credential_kind,encrypted_tokens,key_version,expires_at) VALUES('p','remote_play',NULL,1,'2026-09-17')")
        self.assertEqual(self.db.execute('SELECT count(*) FROM profiles').fetchone()[0], 0)

    def test_one_console_connects_at_launch_and_pins_stay_encrypted(self):
        self.console('c1'); self.console('c2')
        self.db.execute("UPDATE consoles SET connect_at_launch=1 WHERE id='c1'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE consoles SET connect_at_launch=1 WHERE id='c2'")
        self.profile()
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE consoles SET encrypted_login_pin='1234',login_pin_profile_id='p' WHERE id='c2'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE consoles SET encrypted_login_pin=? WHERE id='c2'", (b'synthetic-envelope',))
        self.db.execute("UPDATE consoles SET encrypted_login_pin=?,login_pin_profile_id='p' WHERE id='c2'",
                        (b'synthetic-envelope',))
        self.db.execute("DELETE FROM profiles WHERE id='p'")
        self.assertEqual(self.db.execute("SELECT encrypted_login_pin,login_pin_profile_id FROM consoles WHERE id='c2'").fetchone(),
                         (None, None))

    def test_losing_the_last_registration_releases_launch_and_pin(self):
        self.profile('p1'); self.profile('p2')
        self.console('c1')
        self.link('r1', 'p1', 'c1'); self.link('r2', 'p2', 'c1')
        self.db.execute("UPDATE consoles SET connect_at_launch=1,encrypted_login_pin=?,login_pin_profile_id='p1' WHERE id='c1'",
                        (b'synthetic-envelope',))
        self.db.execute("DELETE FROM registrations WHERE id='r1'")
        self.assertEqual(self.db.execute("SELECT connect_at_launch,encrypted_login_pin FROM consoles").fetchone(), (1, None))
        self.db.execute("DELETE FROM profiles WHERE id='p2'")
        self.assertEqual(self.db.execute("SELECT connect_at_launch FROM consoles").fetchone(), (0,))

    def test_token_dates_are_nullable_whole_milliseconds(self):
        columns = ('access_obtained_at_ms', 'refresh_obtained_at_ms', 'refresh_expires_at_ms')
        declared = {row[1]: row for row in self.db.execute('PRAGMA table_info(profile_tokens)')}
        for column in columns:
            self.assertEqual(declared[column][2:5], ('INTEGER', 0, None))
        self.profile(method='npsso')
        self.db.execute("INSERT INTO profile_tokens(profile_id,credential_kind,encrypted_tokens,key_version,expires_at) VALUES('p','remote_play',?,1,1789603200000)",
                        (b'synthetic-envelope',))
        self.assertEqual(self.db.execute(f"SELECT {','.join(columns)} FROM profile_tokens").fetchone(), (None,) * 3)
        for column in columns:
            self.db.execute(f'UPDATE profile_tokens SET {column}=?', ('1760000000123',))
            self.assertEqual(self.db.execute(f'SELECT {column},typeof({column}) FROM profile_tokens').fetchone(),
                             (1760000000123, 'integer'))
            for refused in ('soon', 1.5, b'synthetic'):
                with self.assertRaises(sqlite3.IntegrityError):
                    self.db.execute(f'UPDATE profile_tokens SET {column}=?', (refused,))
            self.db.execute(f'UPDATE profile_tokens SET {column}=NULL')

    def test_the_dates_migration_adds_only_columns(self):
        migration = ROOT / 'Sources/ChiakiPersistence/Resources/Migrations/010_credential_dates.sql'
        statements = [line for line in migration.read_text().split(';') if line.strip()]
        self.assertEqual(len(statements), 5)
        for statement in statements:
            self.assertRegex(' '.join(statement.split()), r'^ALTER TABLE profile_(npsso|tokens) ADD COLUMN \w+_at_ms INTEGER CHECK')

    def test_sign_in_dates_have_one_home(self):
        columns = [row[1] for row in self.db.execute('PRAGMA table_info(profile_npsso)')]
        self.assertEqual(columns, ['profile_id', 'encrypted_value', 'key_version', 'acquired_at', 'validated_at',
                                   'expires_at', 'expiry_source'])
        schema = self.db.execute("SELECT sql FROM sqlite_master WHERE name='profile_npsso'").fetchone()[0]
        self.assertNotIn('core_', schema)
        self.profile(method='npsso')
        insert = 'INSERT INTO profile_npsso VALUES(?,?,1,100,100,?,?)'
        for expires, source in ((None, 'cookie'), (5.0, 'unknown'), (5.0, 'estimated'), (None, 'token_response'),
                                (5.0, 'sony_response')):
            with self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(insert, ('p', b'synthetic-envelope', expires, source))
        self.db.execute(insert, ('p', b'synthetic-envelope', 5.0, 'token_response'))

    def test_folding_the_core_dates_keeps_what_each_side_knew(self):
        migrations = sorted((ROOT / 'Sources/ChiakiPersistence/Resources/Migrations').glob('*.sql'))
        self.assertEqual([path.name[:3] for path in migrations], [f'{number:03}' for number in (*range(1, 18), 19)])
        cases = [
            ((100.5, None, 'unknown', None, None), (100.5, None, 'unknown')),
            ((100.5, 90000.25, 'cookie', None, None), (100.5, 90000.25, 'cookie')),
            ((100.5, 90000.25, 'cookie', 1760000000123, 1765000000456), (100.5, 90000.25, 'cookie')),
            ((100.5, 90000.25, 'sony_response', 100500, 90000250), (100.5, 90000.25, 'sony_response')),
            ((100.5, None, 'unknown', 1760000000123, 1765000000456), (1760000000.123, 1765000000.456, 'sony_response')),
            ((100.5, None, 'unknown', None, 1765000000456), (100.5, 1765000000.456, 'sony_response')),
            ((100.5, None, 'unknown', 1760000000123, None), (1760000000.123, None, 'unknown')),
            ((100.5004, None, 'unknown', 100500, None), (100.5004, None, 'unknown')),
        ]
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.execute('PRAGMA foreign_keys = ON')
        for migration in migrations[:10]:
            db.executescript(migration.read_text())
        for index, (before, _) in enumerate(cases):
            db.execute("INSERT INTO profiles(id,display_name,auth_method,psn_account_id) VALUES(?,'Example','npsso',?)",
                       (f'p{index}', bytes([index + 1]) * 8))
            db.execute('INSERT INTO profile_npsso VALUES(?,?,1,?,77.125,?,?,?,?)',
                       (f'p{index}', b'synthetic-envelope-%d' % index, *before))
            db.execute("INSERT INTO profile_tokens(profile_id,credential_kind,encrypted_tokens,key_version,expires_at,access_obtained_at_ms) VALUES(?,'remote_play',?,1,'2026-09-17T00:00:00Z',1760000001001)",
                       (f'p{index}', b'synthetic-envelope'))
        untouched = ('SELECT profile_id,encrypted_value,key_version,validated_at FROM profile_npsso ORDER BY profile_id',
                     'SELECT * FROM profiles ORDER BY id', 'SELECT * FROM profile_tokens ORDER BY profile_id')
        kept = [db.execute(query).fetchall() for query in untouched]
        db.executescript(migrations[10].read_text())
        self.assertEqual([db.execute(query).fetchall() for query in untouched], kept)
        self.assertEqual(db.execute('SELECT acquired_at,expires_at,expiry_source FROM profile_npsso ORDER BY profile_id').fetchall(),
                         [after for _, after in cases])
        self.assertEqual(len(db.execute('PRAGMA table_info(profile_npsso)').fetchall()), 7)
        self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])
        self.assertEqual(db.execute('PRAGMA integrity_check').fetchall(), [('ok',)])

    def test_token_response_expiry_replaces_the_old_source_name(self):
        migrations = sorted((ROOT / 'Sources/ChiakiPersistence/Resources/Migrations').glob('*.sql'))
        upgrade = ROOT / 'Sources/ChiakiPersistence/Resources/Migrations/019_token_response_expiry.sql'
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.execute('PRAGMA foreign_keys = ON')
        for migration in migrations:
            if migration.name < '018':
                db.executescript(migration.read_text())
        cases = [
            ('p0', 1760000000123, 1790000000456, 'sony_response'),
            ('p1', 1760000000124, 1790000000457, 'cookie'),
            ('p2', 1760000000125, None, 'unknown'),
        ]
        for index, (profile, acquired, expires, source) in enumerate(cases):
            db.execute("INSERT INTO profiles(id,display_name,auth_method,psn_account_id) VALUES(?,'Example','npsso',?)",
                       (profile, bytes([index + 1]) * 8))
            db.execute('INSERT INTO profile_npsso VALUES(?,?,1,?,?,?,?)',
                       (profile, b'synthetic-envelope-%d' % index, acquired, acquired + 1, expires, source))
        kept = db.execute('SELECT profile_id,encrypted_value,key_version,acquired_at,validated_at,expires_at '
                          'FROM profile_npsso ORDER BY profile_id').fetchall()
        db.executescript(upgrade.read_text())
        self.assertEqual(db.execute('SELECT profile_id,encrypted_value,key_version,acquired_at,validated_at,expires_at '
                                    'FROM profile_npsso ORDER BY profile_id').fetchall(), kept)
        self.assertEqual(db.execute('SELECT expiry_source FROM profile_npsso ORDER BY profile_id').fetchall(),
                         [('token_response',), ('cookie',), ('unknown',)])
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute("UPDATE profile_npsso SET expiry_source='sony_response' WHERE profile_id='p0'")
        db.execute("DELETE FROM profiles WHERE id='p0'")
        self.assertEqual(db.execute('SELECT count(*) FROM profile_npsso').fetchone(), (2,))
        self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])
        self.assertEqual(db.execute('PRAGMA integrity_check').fetchall(), [('ok',)])

if __name__ == '__main__':
    unittest.main()
