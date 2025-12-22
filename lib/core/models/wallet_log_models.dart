/// Supporting data models for wallet connection logging
///
/// These models capture specific information about deep links,
/// WalletConnect URIs, and other connection-related data.
library;

/// Information about a deep link dispatch attempt
///
/// Captures the strategy used and whether the launch was successful.
class DeepLinkDispatchInfo {
  /// Name of the strategy used (e.g., "wc:// universal scheme")
  final String strategyName;

  /// The URI scheme used (e.g., "wc", "metamask")
  final String scheme;

  /// Whether the deep link was successfully launched
  final bool launched;

  /// Package name of the target app (Android only)
  final String? packageName;

  /// Intent scheme used (Android only)
  final String? intentScheme;

  /// Exception message if launch failed
  final String? exception;

  /// Strategy index in the fallback sequence
  final int? strategyIndex;

  /// Total number of strategies attempted
  final int? totalStrategies;

  const DeepLinkDispatchInfo({
    required this.strategyName,
    required this.scheme,
    required this.launched,
    this.packageName,
    this.intentScheme,
    this.exception,
    this.strategyIndex,
    this.totalStrategies,
  });

  /// Convert to a map for logging
  Map<String, dynamic> toMap() {
    return {
      'strategy': strategyName,
      'scheme': scheme,
      'launched': launched,
      if (packageName != null) 'packageName': packageName,
      if (intentScheme != null) 'intentScheme': intentScheme,
      if (exception != null) 'exception': exception,
      if (strategyIndex != null) 'strategyIndex': strategyIndex,
      if (totalStrategies != null) 'totalStrategies': totalStrategies,
    };
  }

  @override
  String toString() => 'DeepLinkDispatch($strategyName, launched: $launched)';
}

/// Information about a deep link return (callback from wallet)
///
/// This is the critical data for debugging deep link connection issues.
/// Captures all details about the URI that the wallet app sent back.
class DeepLinkReturnInfo {
  /// The URI scheme (e.g., "wip", "metamask")
  final String scheme;

  /// The URI host
  final String host;

  /// The URI path
  final String path;

  /// Query parameters from the URI
  final Map<String, String> queryParams;

  /// Raw URI string (for debugging)
  final String rawUri;

  /// Timestamp when this return was received
  final DateTime receivedAt;

  /// Source app that sent this callback (if available)
  final String? sourceApp;

  const DeepLinkReturnInfo({
    required this.scheme,
    required this.host,
    required this.path,
    required this.queryParams,
    required this.rawUri,
    required this.receivedAt,
    this.sourceApp,
  });

  /// Create from a URI
  factory DeepLinkReturnInfo.fromUri(Uri uri, {String? sourceApp}) {
    return DeepLinkReturnInfo(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
      queryParams: uri.queryParameters,
      rawUri: uri.toString(),
      receivedAt: DateTime.now(),
      sourceApp: sourceApp,
    );
  }

  /// Convert to a map for logging
  Map<String, dynamic> toMap() {
    return {
      'scheme': scheme,
      'host': host,
      'path': path,
      'queryParams': queryParams,
      'rawUri': _redactUri(rawUri),
      'receivedAt': receivedAt.toIso8601String(),
      if (sourceApp != null) 'sourceApp': sourceApp,
    };
  }

  /// Redact sensitive parts of the URI for logging
  String _redactUri(String uri) {
    // Redact symKey if present
    final symKeyPattern = RegExp(r'symKey=[^&]+');
    var redacted = uri.replaceAll(symKeyPattern, 'symKey=[REDACTED]');

    // If URI is very long, truncate middle
    if (redacted.length > 200) {
      return '${redacted.substring(0, 80)}...[${redacted.length - 160} chars]...${redacted.substring(redacted.length - 80)}';
    }

    return redacted;
  }

  @override
  String toString() => 'DeepLinkReturn($scheme://$host$path)';
}

/// Information about a WalletConnect URI
///
/// Security-redacted version of the WC URI for logging.
/// Does NOT include the symKey or full URI.
class WcUriInfo {
  /// Relay protocol (e.g., "irn")
  final String relayProtocol;

  /// WC protocol version (e.g., "2")
  final String version;

  /// Expiry timestamp (when the URI becomes invalid)
  final DateTime? expiryTime;

  /// Total length of the original URI
  final int uriLength;

  /// Methods requested in the URI
  final List<String> methods;

  /// Topic hash (redacted)
  final String topicHash;

  const WcUriInfo({
    required this.relayProtocol,
    required this.version,
    this.expiryTime,
    required this.uriLength,
    required this.methods,
    required this.topicHash,
  });

  /// Parse from a WC URI string
  ///
  /// URI format: wc:{topic}@{version}?relay-protocol={protocol}&symKey={key}&expiryTimestamp={expiry}
  factory WcUriInfo.fromUri(String wcUri) {
    try {
      final uri = Uri.parse(wcUri);

      // Extract version from path (format: topic@version)
      final pathParts = uri.path.split('@');
      final topic = pathParts.isNotEmpty ? pathParts[0] : '';
      final version = pathParts.length > 1 ? pathParts[1] : '2';

      // Parse query parameters
      final relayProtocol = uri.queryParameters['relay-protocol'] ?? 'irn';

      // Parse expiry timestamp
      DateTime? expiryTime;
      final expiryStr = uri.queryParameters['expiryTimestamp'];
      if (expiryStr != null) {
        final expirySeconds = int.tryParse(expiryStr);
        if (expirySeconds != null) {
          expiryTime = DateTime.fromMillisecondsSinceEpoch(expirySeconds * 1000);
        }
      }

      // Parse methods if present
      final methodsStr = uri.queryParameters['methods'] ?? '';
      final methods =
          methodsStr.isNotEmpty
              ? methodsStr.split(',').map((m) => m.trim()).toList()
              : <String>[];

      // Create redacted topic hash
      final topicHash =
          topic.length > 10
              ? '${topic.substring(0, 6)}...${topic.substring(topic.length - 4)}'
              : topic;

      return WcUriInfo(
        relayProtocol: relayProtocol,
        version: version,
        expiryTime: expiryTime,
        uriLength: wcUri.length,
        methods: methods,
        topicHash: topicHash,
      );
    } catch (e) {
      // If parsing fails, return minimal info
      return WcUriInfo(
        relayProtocol: 'unknown',
        version: 'unknown',
        uriLength: wcUri.length,
        methods: [],
        topicHash: 'parse_error',
      );
    }
  }

  /// Convert to a map for logging
  Map<String, dynamic> toMap() {
    return {
      'relayProtocol': relayProtocol,
      'version': version,
      if (expiryTime != null) 'expiryTime': expiryTime!.toIso8601String(),
      'uriLength': uriLength,
      if (methods.isNotEmpty) 'methods': methods,
      'topicHash': topicHash,
    };
  }

  @override
  String toString() => 'WcUri(v$version, $relayProtocol, ${uriLength}chars)';
}

/// Relay event information for logging
class RelayEventInfo {
  /// Event type (connect, disconnect, error)
  final String eventType;

  /// Relay URL
  final String? relayUrl;

  /// Error code if applicable
  final String? errorCode;

  /// Error message if applicable
  final String? errorMessage;

  /// Whether this is a reconnection attempt
  final bool isReconnection;

  /// Connection attempt number
  final int? attemptNumber;

  /// Timestamp of the event
  final DateTime timestamp;

  const RelayEventInfo({
    required this.eventType,
    this.relayUrl,
    this.errorCode,
    this.errorMessage,
    this.isReconnection = false,
    this.attemptNumber,
    required this.timestamp,
  });

  /// Convert to a map for logging
  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      if (relayUrl != null) 'relayUrl': relayUrl,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (isReconnection) 'isReconnection': isReconnection,
      if (attemptNumber != null) 'attemptNumber': attemptNumber,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Session event information for logging
class SessionEventInfo {
  /// Event type (connect, delete, update, event)
  final String eventType;

  /// Session topic (redacted)
  final String? topicHash;

  /// Peer wallet name
  final String? peerName;

  /// Namespace keys (e.g., ["eip155"])
  final List<String>? namespaces;

  /// Number of accounts in session
  final int? accountCount;

  /// Chain ID if applicable
  final int? chainId;

  /// Timestamp of the event
  final DateTime timestamp;

  /// Additional event-specific data
  final Map<String, dynamic>? extra;

  const SessionEventInfo({
    required this.eventType,
    this.topicHash,
    this.peerName,
    this.namespaces,
    this.accountCount,
    this.chainId,
    required this.timestamp,
    this.extra,
  });

  /// Convert to a map for logging
  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      if (topicHash != null) 'topicHash': topicHash,
      if (peerName != null) 'peerName': peerName,
      if (namespaces != null) 'namespaces': namespaces,
      if (accountCount != null) 'accountCount': accountCount,
      if (chainId != null) 'chainId': chainId,
      'timestamp': timestamp.toIso8601String(),
      if (extra != null) ...extra!,
    };
  }
}

/// Approval timeout diagnostics
///
/// Comprehensive information logged when approval times out.
class ApprovalTimeoutDiagnostics {
  /// Connection ID for correlation
  final String connectionId;

  /// Wallet type being connected
  final String walletType;

  /// Current relay state
  final String relayState;

  /// Current session state
  final String sessionState;

  /// Current app lifecycle state
  final String? lifecycleState;

  /// Whether relay is reconnecting
  final bool isReconnecting;

  /// Whether deep link was successfully dispatched
  final bool deepLinkDispatched;

  /// Whether any deep link return was received
  final bool deepLinkReturnReceived;

  /// Elapsed time since connection started (ms)
  final int elapsedMs;

  /// Timeout duration (ms)
  final int timeoutMs;

  /// Any pending relay errors
  final String? pendingRelayError;

  const ApprovalTimeoutDiagnostics({
    required this.connectionId,
    required this.walletType,
    required this.relayState,
    required this.sessionState,
    this.lifecycleState,
    required this.isReconnecting,
    required this.deepLinkDispatched,
    required this.deepLinkReturnReceived,
    required this.elapsedMs,
    required this.timeoutMs,
    this.pendingRelayError,
  });

  /// Convert to a map for logging
  Map<String, dynamic> toMap() {
    return {
      'connectionId': connectionId,
      'walletType': walletType,
      'relayState': relayState,
      'sessionState': sessionState,
      if (lifecycleState != null) 'lifecycleState': lifecycleState,
      'isReconnecting': isReconnecting,
      'deepLinkDispatched': deepLinkDispatched,
      'deepLinkReturnReceived': deepLinkReturnReceived,
      'elapsedMs': elapsedMs,
      'timeoutMs': timeoutMs,
      if (pendingRelayError != null) 'pendingRelayError': pendingRelayError,
    };
  }
}
