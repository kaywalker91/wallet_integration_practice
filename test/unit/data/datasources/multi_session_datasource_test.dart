import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wallet_integration_practice/core/constants/app_constants.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/data/datasources/local/multi_session_datasource.dart';
import 'package:wallet_integration_practice/data/models/multi_session_model.dart';
import 'package:wallet_integration_practice/data/models/persisted_session_model.dart';
import 'package:wallet_integration_practice/data/models/phantom_session_model.dart';
import 'package:wallet_integration_practice/domain/entities/multi_session_state.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late MultiSessionDataSourceImpl dataSource;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    dataSource = MultiSessionDataSourceImpl(secureStorage: mockStorage);
  });

  // Test helpers
  PersistedSessionModel createTestWcSession({
    String walletType = 'metaMask',
    String address = '0x1234567890abcdef',
    int chainId = 1,
    DateTime? expiresAt,
  }) {
    return PersistedSessionModel(
      walletType: walletType,
      sessionTopic: 'test-topic-${DateTime.now().millisecondsSinceEpoch}',
      address: address,
      chainId: chainId,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      lastUsedAt: DateTime.now(),
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
    );
  }

  PhantomSessionModel createTestPhantomSession({
    String address = 'PhantomAddress123',
    String cluster = 'mainnet-beta',
    DateTime? expiresAt,
  }) {
    return PhantomSessionModel(
      dappPrivateKeyBase64: 'dappPrivateKey',
      dappPublicKeyBase64: 'dappPublicKey',
      phantomPublicKeyBase64: 'phantomPublicKey',
      session: 'phantomSessionToken',
      connectedAddress: address,
      cluster: cluster,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      lastUsedAt: DateTime.now(),
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
    );
  }

  group('getAllSessions', () {
    test('returns empty state when no data stored', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      final result = await dataSource.getAllSessions();

      expect(result.isEmpty, true);
      expect(result.count, 0);
    });

    test('returns stored sessions when data exists', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
        activeWalletId: 'metamask_0x123',
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      final result = await dataSource.getAllSessions();

      expect(result.isNotEmpty, true);
      expect(result.count, 1);
      expect(result.activeWalletId, 'metamask_0x123');
    });

    test('returns empty state on parse error', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'invalid json{{{');

      final result = await dataSource.getAllSessions();

      expect(result.isEmpty, true);
    });

    test('returns empty state on storage exception', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenThrow(Exception('Storage error'));

      final result = await dataSource.getAllSessions();

      expect(result.isEmpty, true);
    });
  });

  group('saveWalletConnectSession', () {
    test('saves session successfully', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await dataSource.saveWalletConnectSession(
        walletId: 'metamask_0x123',
        session: createTestWcSession(),
      );

      verify(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).called(1);
    });

    test('throws StorageException on save error', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenThrow(Exception('Write failed'));

      expect(
        () => dataSource.saveWalletConnectSession(
          walletId: 'metamask_0x123',
          session: createTestWcSession(),
        ),
        throwsA(isA<StorageException>()),
      );
    });

    test('adds session to existing sessions', () async {
      final existingState = MultiSessionStateModel(
        sessions: {
          'metamask_0x111': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x111',
            session: createTestWcSession(address: '0x111'),
          ),
        },
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(existingState.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      await dataSource.saveWalletConnectSession(
        walletId: 'metamask_0x222',
        session: createTestWcSession(address: '0x222'),
      );

      expect(savedValue, isNotNull);
      final savedState = MultiSessionStateModel.fromJson(
        jsonDecode(savedValue!) as Map<String, dynamic>,
      );
      expect(savedState.count, 2);
    });
  });

  group('savePhantomSession', () {
    test('saves Phantom session successfully', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await dataSource.savePhantomSession(
        walletId: 'phantom_abc123',
        session: createTestPhantomSession(),
      );

      verify(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).called(1);
    });

    test('throws StorageException on save error', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenThrow(Exception('Write failed'));

      expect(
        () => dataSource.savePhantomSession(
          walletId: 'phantom_abc123',
          session: createTestPhantomSession(),
        ),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('getSession', () {
    test('returns session when found', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      final result = await dataSource.getSession('metamask_0x123');

      expect(result, isNotNull);
      expect(result!.walletId, 'metamask_0x123');
    });

    test('returns null when session not found', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      final result = await dataSource.getSession('nonexistent');

      expect(result, isNull);
    });

    test('returns null when storage read fails (getAllSessions gracefully handles errors)', () async {
      // Note: getAllSessions catches exceptions and returns empty state,
      // so getSession returns null instead of throwing
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => throw Exception('Read failed'));

      final result = await dataSource.getSession('metamask_0x123');

      expect(result, isNull);
    });
  });

  group('removeSession', () {
    test('removes session successfully', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
          'metamask_0x456': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x456',
            session: createTestWcSession(address: '0x456'),
          ),
        },
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      await dataSource.removeSession('metamask_0x123');

      expect(savedValue, isNotNull);
      final savedState = MultiSessionStateModel.fromJson(
        jsonDecode(savedValue!) as Map<String, dynamic>,
      );
      expect(savedState.count, 1);
      expect(savedState.getSession('metamask_0x123'), isNull);
      expect(savedState.getSession('metamask_0x456'), isNotNull);
    });

    test('clears activeWalletId when active session removed', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
        activeWalletId: 'metamask_0x123',
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      await dataSource.removeSession('metamask_0x123');

      final savedState = MultiSessionStateModel.fromJson(
        jsonDecode(savedValue!) as Map<String, dynamic>,
      );
      expect(savedState.activeWalletId, isNull);
    });

    test('throws StorageException on error', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenThrow(Exception('Write failed'));

      expect(
        () => dataSource.removeSession('metamask_0x123'),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('clearAllSessions', () {
    test('deletes storage key successfully', () async {
      when(() => mockStorage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      await dataSource.clearAllSessions();

      verify(() => mockStorage.delete(key: any(named: 'key'))).called(1);
    });

    test('throws StorageException on error', () async {
      when(() => mockStorage.delete(key: any(named: 'key')))
          .thenThrow(Exception('Delete failed'));

      expect(
        () => dataSource.clearAllSessions(),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('setActiveWalletId', () {
    test('sets active wallet ID successfully', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      await dataSource.setActiveWalletId('metamask_0x123');

      final savedState = MultiSessionStateModel.fromJson(
        jsonDecode(savedValue!) as Map<String, dynamic>,
      );
      expect(savedState.activeWalletId, 'metamask_0x123');
    });

    test('clears active wallet ID when null provided', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
        activeWalletId: 'metamask_0x123',
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      await dataSource.setActiveWalletId(null);

      final savedState = MultiSessionStateModel.fromJson(
        jsonDecode(savedValue!) as Map<String, dynamic>,
      );
      expect(savedState.activeWalletId, isNull);
    });
  });

  group('getActiveWalletId', () {
    test('returns active wallet ID when set', () async {
      final state = MultiSessionStateModel(
        sessions: {},
        activeWalletId: 'metamask_0x123',
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      final result = await dataSource.getActiveWalletId();

      expect(result, 'metamask_0x123');
    });

    test('returns null when no active wallet', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      final result = await dataSource.getActiveWalletId();

      expect(result, isNull);
    });

    test('returns null on error (non-critical)', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenThrow(Exception('Read failed'));

      final result = await dataSource.getActiveWalletId();

      expect(result, isNull);
    });
  });

  group('updateSessionLastUsed', () {
    test('updates last used timestamp', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      await dataSource.updateSessionLastUsed('metamask_0x123');

      expect(savedValue, isNotNull);
      verify(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).called(1);
    });

    test('does nothing when session not found', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      await dataSource.updateSessionLastUsed('nonexistent');

      verifyNever(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ));
    });

    test('does not throw on error (non-critical)', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenThrow(Exception('Read failed'));

      // Should not throw
      await dataSource.updateSessionLastUsed('metamask_0x123');
    });
  });

  group('removeExpiredSessions', () {
    test('removes expired sessions and returns count', () async {
      final now = DateTime.now();
      final expiredSession = createTestWcSession(
        address: '0x111',
        expiresAt: now.subtract(const Duration(days: 1)),
      );
      final validSession = createTestWcSession(
        address: '0x222',
        expiresAt: now.add(const Duration(days: 7)),
      );

      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x111': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x111',
            session: expiredSession,
          ),
          'metamask_0x222': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x222',
            session: validSession,
          ),
        },
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      final result = await dataSource.removeExpiredSessions();

      expect(result, 1);
      final savedState = MultiSessionStateModel.fromJson(
        jsonDecode(savedValue!) as Map<String, dynamic>,
      );
      expect(savedState.count, 1);
      expect(savedState.getSession('metamask_0x222'), isNotNull);
    });

    test('returns 0 when no expired sessions', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      final result = await dataSource.removeExpiredSessions();

      expect(result, 0);
      verifyNever(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ));
    });

    test('clears activeWalletId when active session expired', () async {
      final expiredSession = createTestWcSession(
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: expiredSession,
          ),
        },
        activeWalletId: 'metamask_0x123',
      );

      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      String? savedValue;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        savedValue = invocation.namedArguments[const Symbol('value')] as String;
      });

      await dataSource.removeExpiredSessions();

      final savedState = MultiSessionStateModel.fromJson(
        jsonDecode(savedValue!) as Map<String, dynamic>,
      );
      expect(savedState.activeWalletId, isNull);
    });

    test('returns 0 on error (non-critical)', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenThrow(Exception('Read failed'));

      final result = await dataSource.removeExpiredSessions();

      expect(result, 0);
    });
  });

  group('migrateLegacySessions', () {
    const multiSessionStorageKey = 'multi_wallet_sessions_v1';

    test('returns false when multi-session data already exists', () async {
      final state = MultiSessionStateModel(
        sessions: {
          'metamask_0x123': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'metamask_0x123',
            session: createTestWcSession(),
          ),
        },
      );

      when(() => mockStorage.read(key: multiSessionStorageKey))
          .thenAnswer((_) async => jsonEncode(state.toJson()));

      final result = await dataSource.migrateLegacySessions();

      expect(result, false);
    });

    test('migrates legacy WalletConnect session', () async {
      final legacySession = createTestWcSession();

      // Multi-session storage is empty
      when(() => mockStorage.read(key: multiSessionStorageKey))
          .thenAnswer((_) async => null);
      // Legacy WC session exists
      when(() => mockStorage.read(key: AppConstants.persistedSessionKey))
          .thenAnswer((_) async => jsonEncode(legacySession.toJson()));
      // No Phantom session
      when(() => mockStorage.read(key: AppConstants.phantomSessionKey))
          .thenAnswer((_) async => null);

      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final result = await dataSource.migrateLegacySessions();

      expect(result, true);
      verify(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).called(greaterThan(0));
    });

    test('migrates legacy Phantom session', () async {
      final legacyPhantomSession = createTestPhantomSession();

      // Multi-session storage is empty
      when(() => mockStorage.read(key: multiSessionStorageKey))
          .thenAnswer((_) async => null);
      // No WC session
      when(() => mockStorage.read(key: AppConstants.persistedSessionKey))
          .thenAnswer((_) async => null);
      // Phantom session exists
      when(() => mockStorage.read(key: AppConstants.phantomSessionKey))
          .thenAnswer((_) async => jsonEncode(legacyPhantomSession.toJson()));

      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final result = await dataSource.migrateLegacySessions();

      expect(result, true);
    });

    test('skips expired legacy sessions', () async {
      final expiredSession = createTestWcSession(
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      // Multi-session storage is empty
      when(() => mockStorage.read(key: multiSessionStorageKey))
          .thenAnswer((_) async => null);
      // Legacy WC session is expired
      when(() => mockStorage.read(key: AppConstants.persistedSessionKey))
          .thenAnswer((_) async => jsonEncode(expiredSession.toJson()));
      // No Phantom session
      when(() => mockStorage.read(key: AppConstants.phantomSessionKey))
          .thenAnswer((_) async => null);

      final result = await dataSource.migrateLegacySessions();

      expect(result, false);
    });

    test('returns false on migration error', () async {
      when(() => mockStorage.read(key: multiSessionStorageKey))
          .thenThrow(Exception('Migration failed'));

      final result = await dataSource.migrateLegacySessions();

      expect(result, false);
    });

    test('handles corrupt legacy data gracefully', () async {
      // Multi-session storage is empty
      when(() => mockStorage.read(key: multiSessionStorageKey))
          .thenAnswer((_) async => null);
      // Corrupt WC session
      when(() => mockStorage.read(key: AppConstants.persistedSessionKey))
          .thenAnswer((_) async => 'invalid json{{{');
      // No Phantom session
      when(() => mockStorage.read(key: AppConstants.phantomSessionKey))
          .thenAnswer((_) async => null);

      final result = await dataSource.migrateLegacySessions();

      expect(result, false);
    });
  });

  group('MultiSessionStateModel', () {
    test('fromJson handles missing fields gracefully', () {
      final json = <String, dynamic>{
        'sessions': <String, dynamic>{},
      };

      final state = MultiSessionStateModel.fromJson(json);

      expect(state.isEmpty, true);
      expect(state.activeWalletId, isNull);
    });

    test('fromJson skips corrupted session entries', () {
      final validSession = createTestWcSession();
      final json = <String, dynamic>{
        'sessions': {
          'valid_session': MultiSessionEntryModel.fromWalletConnect(
            walletId: 'valid_session',
            session: validSession,
          ).toJson(),
          'corrupted_session': {'invalid': 'data'},
        },
      };

      final state = MultiSessionStateModel.fromJson(json);

      expect(state.count, 1);
      expect(state.getSession('valid_session'), isNotNull);
      expect(state.getSession('corrupted_session'), isNull);
    });

    test('addSession adds new session', () {
      const state = MultiSessionStateModel();
      final entry = MultiSessionEntryModel.fromWalletConnect(
        walletId: 'metamask_0x123',
        session: createTestWcSession(),
      );

      final newState = state.addSession(entry);

      expect(newState.count, 1);
      expect(newState.getSession('metamask_0x123'), isNotNull);
    });

    test('addSession updates existing session', () {
      final entry1 = MultiSessionEntryModel.fromWalletConnect(
        walletId: 'metamask_0x123',
        session: createTestWcSession(chainId: 1),
      );
      var state = const MultiSessionStateModel().addSession(entry1);

      final entry2 = MultiSessionEntryModel.fromWalletConnect(
        walletId: 'metamask_0x123',
        session: createTestWcSession(chainId: 137),
      );
      state = state.addSession(entry2);

      expect(state.count, 1);
    });

    test('removeSession removes existing session', () {
      final entry = MultiSessionEntryModel.fromWalletConnect(
        walletId: 'metamask_0x123',
        session: createTestWcSession(),
      );
      var state = const MultiSessionStateModel().addSession(entry);

      state = state.removeSession('metamask_0x123');

      expect(state.isEmpty, true);
    });

    test('setActiveWallet sets active wallet ID', () {
      const state = MultiSessionStateModel();

      final newState = state.setActiveWallet('metamask_0x123');

      expect(newState.activeWalletId, 'metamask_0x123');
    });

    test('sessionList returns all sessions as list', () {
      final entry1 = MultiSessionEntryModel.fromWalletConnect(
        walletId: 'metamask_0x123',
        session: createTestWcSession(),
      );
      final entry2 = MultiSessionEntryModel.fromPhantom(
        walletId: 'phantom_abc',
        session: createTestPhantomSession(),
      );

      final state = const MultiSessionStateModel()
          .addSession(entry1)
          .addSession(entry2);

      expect(state.sessionList.length, 2);
    });
  });

  group('MultiSessionEntryModel', () {
    test('fromWalletConnect creates correct entry', () {
      final session = createTestWcSession();
      final entry = MultiSessionEntryModel.fromWalletConnect(
        walletId: 'metamask_0x123',
        session: session,
      );

      expect(entry.walletId, 'metamask_0x123');
      expect(entry.sessionType, SessionType.walletConnect);
      expect(entry.walletConnectSession, isNotNull);
      expect(entry.phantomSession, isNull);
    });

    test('fromPhantom creates correct entry', () {
      final session = createTestPhantomSession();
      final entry = MultiSessionEntryModel.fromPhantom(
        walletId: 'phantom_abc',
        session: session,
      );

      expect(entry.walletId, 'phantom_abc');
      expect(entry.sessionType, SessionType.phantom);
      expect(entry.phantomSession, isNotNull);
      expect(entry.walletConnectSession, isNull);
    });

    test('toJson and fromJson roundtrip works', () {
      final session = createTestWcSession();
      final entry = MultiSessionEntryModel.fromWalletConnect(
        walletId: 'metamask_0x123',
        session: session,
      );

      final json = entry.toJson();
      final restored = MultiSessionEntryModel.fromJson(json);

      expect(restored.walletId, entry.walletId);
      expect(restored.sessionType, entry.sessionType);
    });

    test('copyWithLastUsed updates lastUsedAt', () {
      final session = createTestPhantomSession();
      final entry = MultiSessionEntryModel.fromPhantom(
        walletId: 'phantom_abc',
        session: session,
      );
      final newTime = DateTime.now().add(const Duration(hours: 1));

      final updated = entry.copyWithLastUsed(newTime);

      expect(updated.lastUsedAt, newTime);
      expect(updated.walletId, entry.walletId);
    });
  });

  group('WalletIdGenerator', () {
    test('generates correct wallet ID', () {
      final walletId = WalletIdGenerator.generate('MetaMask', '0xABC123');

      expect(walletId, 'metamask_0xabc123');
    });

    test('normalizes spaces in wallet type', () {
      final walletId =
          WalletIdGenerator.generate('Trust Wallet', '0xABC123');

      expect(walletId, 'trustwallet_0xabc123');
    });

    test('lowercases address', () {
      final walletId =
          WalletIdGenerator.generate('phantom', 'ABCDEFG123456');

      expect(walletId, 'phantom_abcdefg123456');
    });
  });
}
