part of '../connections.dart';

class ConnectionsTotals {
  ConnectionsTotals({
    required this.upload,
    required this.download,
    required this.memory,
    required this.connectionsIn,
    required this.connectionsOut,
    required this.count,
  });

  static final ConnectionsTotals zero = ConnectionsTotals(
    upload: BigInt.zero,
    download: BigInt.zero,
    memory: BigInt.zero,
    connectionsIn: 0,
    connectionsOut: 0,
    count: 0,
  );

  final BigInt upload;
  final BigInt download;
  final BigInt memory;
  final int connectionsIn;
  final int connectionsOut;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is ConnectionsTotals &&
      upload == other.upload &&
      download == other.download &&
      memory == other.memory &&
      connectionsIn == other.connectionsIn &&
      connectionsOut == other.connectionsOut &&
      count == other.count;

  @override
  int get hashCode => Object.hash(
    upload,
    download,
    memory,
    connectionsIn,
    connectionsOut,
    count,
  );
}

class RowBytes {
  const RowBytes(this.upload, this.download);

  static final RowBytes zero = RowBytes(BigInt.zero, BigInt.zero);

  final BigInt upload;
  final BigInt download;

  @override
  bool operator ==(Object other) =>
      other is RowBytes && upload == other.upload && download == other.download;

  @override
  int get hashCode => Object.hash(upload, download);
}

class RowSpeeds {
  const RowSpeeds(this.upload, this.download);

  static final RowSpeeds zero = RowSpeeds(BigInt.zero, BigInt.zero);

  final BigInt upload;
  final BigInt download;

  @override
  bool operator ==(Object other) =>
      other is RowSpeeds &&
      upload == other.upload &&
      download == other.download;

  @override
  int get hashCode => Object.hash(upload, download);
}

/// Stable connection fields. Volatile counters update through per-row
/// notifiers so tiles do not rebuild when only traffic changes.
class ConnectionRow {
  ConnectionRow({
    required this.id,
    required this.host,
    required this.network,
    required this.connType,
    required this.process,
    required this.processPath,
    required this.rule,
    required this.rulePayload,
    required this.chains,
    required this.connectionLogs,
    required this.start,
    required this.sourceIp,
    required this.sourcePort,
    required this.destinationIp,
    required this.destinationPort,
    required this.inboundIp,
    required this.inboundPort,
    required this.inboundName,
    required this.dnsMode,
    required this.uid,
    required this.specialProxy,
    required this.specialRules,
    required this.remoteDestination,
    required this.sniffHost,
    required this.isClosed,
    required RowBytes initialBytes,
    required RowSpeeds initialSpeeds,
  }) : bytes = ValueNotifier<RowBytes>(initialBytes),
       speeds = ValueNotifier<RowSpeeds>(initialSpeeds);

  factory ConnectionRow.fromConnection(rust.Connection connection) {
    final host = connection.host.isNotEmpty
        ? connection.host
        : '${connection.destinationIp}:${connection.destinationPort}';
    return ConnectionRow(
      id: connection.id,
      host: host,
      network: connection.network,
      connType: connection.connType,
      process: connection.process,
      processPath: connection.processPath,
      rule: connection.rule,
      rulePayload: connection.rulePayload,
      chains: List<String>.unmodifiable(connection.chains),
      connectionLogs: List<String>.unmodifiable(connection.connectionLogs),
      start: DateTime.tryParse(connection.start),
      sourceIp: connection.sourceIp,
      sourcePort: connection.sourcePort,
      destinationIp: connection.destinationIp,
      destinationPort: connection.destinationPort,
      inboundIp: connection.inboundIp,
      inboundPort: connection.inboundPort,
      inboundName: connection.inboundName,
      dnsMode: connection.dnsMode,
      uid: connection.uid,
      specialProxy: connection.specialProxy,
      specialRules: connection.specialRules,
      remoteDestination: connection.remoteDestination,
      sniffHost: connection.sniffHost,
      isClosed: connection.isClosed,
      initialBytes: RowBytes(connection.upload, connection.download),
      initialSpeeds: RowSpeeds(
        connection.uploadSpeed,
        connection.downloadSpeed,
      ),
    );
  }

  factory ConnectionRow.detached(ConnectionRow source) => ConnectionRow(
    id: source.id,
    host: source.host,
    network: source.network,
    connType: source.connType,
    process: source.process,
    processPath: source.processPath,
    rule: source.rule,
    rulePayload: source.rulePayload,
    chains: source.chains,
    connectionLogs: source.connectionLogs,
    start: source.start,
    sourceIp: source.sourceIp,
    sourcePort: source.sourcePort,
    destinationIp: source.destinationIp,
    destinationPort: source.destinationPort,
    inboundIp: source.inboundIp,
    inboundPort: source.inboundPort,
    inboundName: source.inboundName,
    dnsMode: source.dnsMode,
    uid: source.uid,
    specialProxy: source.specialProxy,
    specialRules: source.specialRules,
    remoteDestination: source.remoteDestination,
    sniffHost: source.sniffHost,
    isClosed: source.isClosed,
    initialBytes: source.bytes.value,
    initialSpeeds: source.speeds.value,
  );

  final String id;
  final String host;
  final String network;
  final String connType;
  final String process;
  final String processPath;
  final String rule;
  final String rulePayload;
  final List<String> chains;
  final List<String> connectionLogs;
  final DateTime? start;
  final String sourceIp;
  final int sourcePort;
  final String destinationIp;
  final int destinationPort;
  final String inboundIp;
  final int inboundPort;
  final String inboundName;
  final String dnsMode;
  final int uid;
  final String specialProxy;
  final String specialRules;
  final String remoteDestination;
  final String sniffHost;
  final bool isClosed;
  final ValueNotifier<RowBytes> bytes;
  final ValueNotifier<RowSpeeds> speeds;
  bool _disposed = false;

  String get activeProxy => chains.isEmpty ? '' : chains.first;
  String get chainsLabel => chains.reversed.join(' → ');

  String get protocolLabel {
    if (connType.isEmpty && network.isEmpty) return '';
    if (connType.isEmpty) return network.toUpperCase();
    if (network.isEmpty) return connType;
    return '$connType(${network.toUpperCase()})';
  }

  void updateFromConnection(rust.Connection connection) {
    _updateCounters(
      upload: connection.upload,
      download: connection.download,
      uploadSpeed: connection.uploadSpeed,
      downloadSpeed: connection.downloadSpeed,
    );
  }

  void updateStats(rust.ConnectionStats stats) {
    _updateCounters(
      upload: stats.upload,
      download: stats.download,
      uploadSpeed: stats.uploadSpeed,
      downloadSpeed: stats.downloadSpeed,
    );
  }

  void _updateCounters({
    required BigInt upload,
    required BigInt download,
    required BigInt uploadSpeed,
    required BigInt downloadSpeed,
  }) {
    if (_disposed) return;
    final nextBytes = RowBytes(upload, download);
    if (bytes.value != nextBytes) bytes.value = nextBytes;
    final nextSpeeds = RowSpeeds(uploadSpeed, downloadSpeed);
    if (speeds.value != nextSpeeds) speeds.value = nextSpeeds;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bytes.dispose();
    speeds.dispose();
  }
}

enum ConnectionsTab { active, closed }

/// Stable process-group fields with separately observable traffic counters.
class ConnectionGroupSummary {
  ConnectionGroupSummary({
    required this.key,
    required this.label,
    required this.process,
    required this.processPath,
    required this.sourceIp,
    required int initialCount,
    required RowBytes initialBytes,
    required RowSpeeds initialSpeeds,
  }) : count = ValueNotifier<int>(initialCount),
       bytes = ValueNotifier<RowBytes>(initialBytes),
       speeds = ValueNotifier<RowSpeeds>(initialSpeeds);

  factory ConnectionGroupSummary.fromGroup(rust.ConnectionGroup group) {
    return ConnectionGroupSummary(
      key: group.key,
      label: group.label,
      process: group.process,
      processPath: group.processPath,
      sourceIp: group.sourceIp,
      initialCount: group.count,
      initialBytes: RowBytes(group.upload, group.download),
      initialSpeeds: RowSpeeds(group.uploadSpeed, group.downloadSpeed),
    );
  }

  final String key;
  final String label;
  final String process;
  final String processPath;
  final String sourceIp;
  final ValueNotifier<int> count;
  final ValueNotifier<RowBytes> bytes;
  final ValueNotifier<RowSpeeds> speeds;

  void dispose() {
    count.dispose();
    bytes.dispose();
    speeds.dispose();
  }
}
