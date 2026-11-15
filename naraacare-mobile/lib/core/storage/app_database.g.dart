// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $OutboxItemsTable extends OutboxItems
    with TableInfo<$OutboxItemsTable, OutboxItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _clientEntryIdMeta = const VerificationMeta(
    'clientEntryId',
  );
  @override
  late final GeneratedColumn<String> clientEntryId = GeneratedColumn<String>(
    'client_entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _resourceMeta = const VerificationMeta(
    'resource',
  );
  @override
  late final GeneratedColumn<String> resource = GeneratedColumn<String>(
    'resource',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ifMatchVersionMeta = const VerificationMeta(
    'ifMatchVersion',
  );
  @override
  late final GeneratedColumn<int> ifMatchVersion = GeneratedColumn<int>(
    'if_match_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientEntryId,
    resource,
    method,
    path,
    body,
    ifMatchVersion,
    attempts,
    lastErrorCode,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('client_entry_id')) {
      context.handle(
        _clientEntryIdMeta,
        clientEntryId.isAcceptableOrUnknown(
          data['client_entry_id']!,
          _clientEntryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientEntryIdMeta);
    }
    if (data.containsKey('resource')) {
      context.handle(
        _resourceMeta,
        resource.isAcceptableOrUnknown(data['resource']!, _resourceMeta),
      );
    } else if (isInserting) {
      context.missing(_resourceMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('if_match_version')) {
      context.handle(
        _ifMatchVersionMeta,
        ifMatchVersion.isAcceptableOrUnknown(
          data['if_match_version']!,
          _ifMatchVersionMeta,
        ),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      clientEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_entry_id'],
      )!,
      resource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      ifMatchVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}if_match_version'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxItemsTable createAlias(String alias) {
    return $OutboxItemsTable(attachedDatabase, alias);
  }
}

class OutboxItem extends DataClass implements Insertable<OutboxItem> {
  final int id;

  /// UUIDv7 the server uses to make the create idempotent.
  final String clientEntryId;

  /// e.g. `hydration_intake`; items of one resource are sent in order.
  final String resource;
  final String method;
  final String path;
  final String? body;
  final int? ifMatchVersion;
  final int attempts;

  /// Error code of the last failed attempt (never a message or payload).
  final String? lastErrorCode;
  final DateTime createdAt;
  const OutboxItem({
    required this.id,
    required this.clientEntryId,
    required this.resource,
    required this.method,
    required this.path,
    this.body,
    this.ifMatchVersion,
    required this.attempts,
    this.lastErrorCode,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['client_entry_id'] = Variable<String>(clientEntryId);
    map['resource'] = Variable<String>(resource);
    map['method'] = Variable<String>(method);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    if (!nullToAbsent || ifMatchVersion != null) {
      map['if_match_version'] = Variable<int>(ifMatchVersion);
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxItemsCompanion toCompanion(bool nullToAbsent) {
    return OutboxItemsCompanion(
      id: Value(id),
      clientEntryId: Value(clientEntryId),
      resource: Value(resource),
      method: Value(method),
      path: Value(path),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      ifMatchVersion: ifMatchVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(ifMatchVersion),
      attempts: Value(attempts),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxItem(
      id: serializer.fromJson<int>(json['id']),
      clientEntryId: serializer.fromJson<String>(json['clientEntryId']),
      resource: serializer.fromJson<String>(json['resource']),
      method: serializer.fromJson<String>(json['method']),
      path: serializer.fromJson<String>(json['path']),
      body: serializer.fromJson<String?>(json['body']),
      ifMatchVersion: serializer.fromJson<int?>(json['ifMatchVersion']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'clientEntryId': serializer.toJson<String>(clientEntryId),
      'resource': serializer.toJson<String>(resource),
      'method': serializer.toJson<String>(method),
      'path': serializer.toJson<String>(path),
      'body': serializer.toJson<String?>(body),
      'ifMatchVersion': serializer.toJson<int?>(ifMatchVersion),
      'attempts': serializer.toJson<int>(attempts),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxItem copyWith({
    int? id,
    String? clientEntryId,
    String? resource,
    String? method,
    String? path,
    Value<String?> body = const Value.absent(),
    Value<int?> ifMatchVersion = const Value.absent(),
    int? attempts,
    Value<String?> lastErrorCode = const Value.absent(),
    DateTime? createdAt,
  }) => OutboxItem(
    id: id ?? this.id,
    clientEntryId: clientEntryId ?? this.clientEntryId,
    resource: resource ?? this.resource,
    method: method ?? this.method,
    path: path ?? this.path,
    body: body.present ? body.value : this.body,
    ifMatchVersion: ifMatchVersion.present
        ? ifMatchVersion.value
        : this.ifMatchVersion,
    attempts: attempts ?? this.attempts,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxItem copyWithCompanion(OutboxItemsCompanion data) {
    return OutboxItem(
      id: data.id.present ? data.id.value : this.id,
      clientEntryId: data.clientEntryId.present
          ? data.clientEntryId.value
          : this.clientEntryId,
      resource: data.resource.present ? data.resource.value : this.resource,
      method: data.method.present ? data.method.value : this.method,
      path: data.path.present ? data.path.value : this.path,
      body: data.body.present ? data.body.value : this.body,
      ifMatchVersion: data.ifMatchVersion.present
          ? data.ifMatchVersion.value
          : this.ifMatchVersion,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxItem(')
          ..write('id: $id, ')
          ..write('clientEntryId: $clientEntryId, ')
          ..write('resource: $resource, ')
          ..write('method: $method, ')
          ..write('path: $path, ')
          ..write('body: $body, ')
          ..write('ifMatchVersion: $ifMatchVersion, ')
          ..write('attempts: $attempts, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientEntryId,
    resource,
    method,
    path,
    body,
    ifMatchVersion,
    attempts,
    lastErrorCode,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxItem &&
          other.id == this.id &&
          other.clientEntryId == this.clientEntryId &&
          other.resource == this.resource &&
          other.method == this.method &&
          other.path == this.path &&
          other.body == this.body &&
          other.ifMatchVersion == this.ifMatchVersion &&
          other.attempts == this.attempts &&
          other.lastErrorCode == this.lastErrorCode &&
          other.createdAt == this.createdAt);
}

class OutboxItemsCompanion extends UpdateCompanion<OutboxItem> {
  final Value<int> id;
  final Value<String> clientEntryId;
  final Value<String> resource;
  final Value<String> method;
  final Value<String> path;
  final Value<String?> body;
  final Value<int?> ifMatchVersion;
  final Value<int> attempts;
  final Value<String?> lastErrorCode;
  final Value<DateTime> createdAt;
  const OutboxItemsCompanion({
    this.id = const Value.absent(),
    this.clientEntryId = const Value.absent(),
    this.resource = const Value.absent(),
    this.method = const Value.absent(),
    this.path = const Value.absent(),
    this.body = const Value.absent(),
    this.ifMatchVersion = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxItemsCompanion.insert({
    this.id = const Value.absent(),
    required String clientEntryId,
    required String resource,
    required String method,
    required String path,
    this.body = const Value.absent(),
    this.ifMatchVersion = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    required DateTime createdAt,
  }) : clientEntryId = Value(clientEntryId),
       resource = Value(resource),
       method = Value(method),
       path = Value(path),
       createdAt = Value(createdAt);
  static Insertable<OutboxItem> custom({
    Expression<int>? id,
    Expression<String>? clientEntryId,
    Expression<String>? resource,
    Expression<String>? method,
    Expression<String>? path,
    Expression<String>? body,
    Expression<int>? ifMatchVersion,
    Expression<int>? attempts,
    Expression<String>? lastErrorCode,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientEntryId != null) 'client_entry_id': clientEntryId,
      if (resource != null) 'resource': resource,
      if (method != null) 'method': method,
      if (path != null) 'path': path,
      if (body != null) 'body': body,
      if (ifMatchVersion != null) 'if_match_version': ifMatchVersion,
      if (attempts != null) 'attempts': attempts,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OutboxItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? clientEntryId,
    Value<String>? resource,
    Value<String>? method,
    Value<String>? path,
    Value<String?>? body,
    Value<int?>? ifMatchVersion,
    Value<int>? attempts,
    Value<String?>? lastErrorCode,
    Value<DateTime>? createdAt,
  }) {
    return OutboxItemsCompanion(
      id: id ?? this.id,
      clientEntryId: clientEntryId ?? this.clientEntryId,
      resource: resource ?? this.resource,
      method: method ?? this.method,
      path: path ?? this.path,
      body: body ?? this.body,
      ifMatchVersion: ifMatchVersion ?? this.ifMatchVersion,
      attempts: attempts ?? this.attempts,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (clientEntryId.present) {
      map['client_entry_id'] = Variable<String>(clientEntryId.value);
    }
    if (resource.present) {
      map['resource'] = Variable<String>(resource.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (ifMatchVersion.present) {
      map['if_match_version'] = Variable<int>(ifMatchVersion.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxItemsCompanion(')
          ..write('id: $id, ')
          ..write('clientEntryId: $clientEntryId, ')
          ..write('resource: $resource, ')
          ..write('method: $method, ')
          ..write('path: $path, ')
          ..write('body: $body, ')
          ..write('ifMatchVersion: $ifMatchVersion, ')
          ..write('attempts: $attempts, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $LocalEntriesTable extends LocalEntries
    with TableInfo<$LocalEntriesTable, LocalEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientEntryIdMeta = const VerificationMeta(
    'clientEntryId',
  );
  @override
  late final GeneratedColumn<String> clientEntryId = GeneratedColumn<String>(
    'client_entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectionCodeMeta = const VerificationMeta(
    'rejectionCode',
  );
  @override
  late final GeneratedColumn<String> rejectionCode = GeneratedColumn<String>(
    'rejection_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientEntryId,
    kind,
    localDate,
    payload,
    state,
    serverId,
    version,
    rejectionCode,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_entry_id')) {
      context.handle(
        _clientEntryIdMeta,
        clientEntryId.isAcceptableOrUnknown(
          data['client_entry_id']!,
          _clientEntryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientEntryIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('rejection_code')) {
      context.handle(
        _rejectionCodeMeta,
        rejectionCode.isAcceptableOrUnknown(
          data['rejection_code']!,
          _rejectionCodeMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientEntryId};
  @override
  LocalEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalEntry(
      clientEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_entry_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      ),
      rejectionCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejection_code'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalEntriesTable createAlias(String alias) {
    return $LocalEntriesTable(attachedDatabase, alias);
  }
}

class LocalEntry extends DataClass implements Insertable<LocalEntry> {
  final String clientEntryId;

  /// hydration | meal | workout | sleep
  final String kind;

  /// Local calendar date (YYYY-MM-DD) in the user's time zone.
  final String localDate;
  final String payload;

  /// pending | synced | conflict | rejected
  final String state;
  final String? serverId;
  final int? version;
  final String? rejectionCode;
  final DateTime updatedAt;
  const LocalEntry({
    required this.clientEntryId,
    required this.kind,
    required this.localDate,
    required this.payload,
    required this.state,
    this.serverId,
    this.version,
    this.rejectionCode,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_entry_id'] = Variable<String>(clientEntryId);
    map['kind'] = Variable<String>(kind);
    map['local_date'] = Variable<String>(localDate);
    map['payload'] = Variable<String>(payload);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    if (!nullToAbsent || version != null) {
      map['version'] = Variable<int>(version);
    }
    if (!nullToAbsent || rejectionCode != null) {
      map['rejection_code'] = Variable<String>(rejectionCode);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalEntriesCompanion toCompanion(bool nullToAbsent) {
    return LocalEntriesCompanion(
      clientEntryId: Value(clientEntryId),
      kind: Value(kind),
      localDate: Value(localDate),
      payload: Value(payload),
      state: Value(state),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      version: version == null && nullToAbsent
          ? const Value.absent()
          : Value(version),
      rejectionCode: rejectionCode == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectionCode),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalEntry(
      clientEntryId: serializer.fromJson<String>(json['clientEntryId']),
      kind: serializer.fromJson<String>(json['kind']),
      localDate: serializer.fromJson<String>(json['localDate']),
      payload: serializer.fromJson<String>(json['payload']),
      state: serializer.fromJson<String>(json['state']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      version: serializer.fromJson<int?>(json['version']),
      rejectionCode: serializer.fromJson<String?>(json['rejectionCode']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientEntryId': serializer.toJson<String>(clientEntryId),
      'kind': serializer.toJson<String>(kind),
      'localDate': serializer.toJson<String>(localDate),
      'payload': serializer.toJson<String>(payload),
      'state': serializer.toJson<String>(state),
      'serverId': serializer.toJson<String?>(serverId),
      'version': serializer.toJson<int?>(version),
      'rejectionCode': serializer.toJson<String?>(rejectionCode),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalEntry copyWith({
    String? clientEntryId,
    String? kind,
    String? localDate,
    String? payload,
    String? state,
    Value<String?> serverId = const Value.absent(),
    Value<int?> version = const Value.absent(),
    Value<String?> rejectionCode = const Value.absent(),
    DateTime? updatedAt,
  }) => LocalEntry(
    clientEntryId: clientEntryId ?? this.clientEntryId,
    kind: kind ?? this.kind,
    localDate: localDate ?? this.localDate,
    payload: payload ?? this.payload,
    state: state ?? this.state,
    serverId: serverId.present ? serverId.value : this.serverId,
    version: version.present ? version.value : this.version,
    rejectionCode: rejectionCode.present
        ? rejectionCode.value
        : this.rejectionCode,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalEntry copyWithCompanion(LocalEntriesCompanion data) {
    return LocalEntry(
      clientEntryId: data.clientEntryId.present
          ? data.clientEntryId.value
          : this.clientEntryId,
      kind: data.kind.present ? data.kind.value : this.kind,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      payload: data.payload.present ? data.payload.value : this.payload,
      state: data.state.present ? data.state.value : this.state,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      version: data.version.present ? data.version.value : this.version,
      rejectionCode: data.rejectionCode.present
          ? data.rejectionCode.value
          : this.rejectionCode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalEntry(')
          ..write('clientEntryId: $clientEntryId, ')
          ..write('kind: $kind, ')
          ..write('localDate: $localDate, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('serverId: $serverId, ')
          ..write('version: $version, ')
          ..write('rejectionCode: $rejectionCode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientEntryId,
    kind,
    localDate,
    payload,
    state,
    serverId,
    version,
    rejectionCode,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalEntry &&
          other.clientEntryId == this.clientEntryId &&
          other.kind == this.kind &&
          other.localDate == this.localDate &&
          other.payload == this.payload &&
          other.state == this.state &&
          other.serverId == this.serverId &&
          other.version == this.version &&
          other.rejectionCode == this.rejectionCode &&
          other.updatedAt == this.updatedAt);
}

class LocalEntriesCompanion extends UpdateCompanion<LocalEntry> {
  final Value<String> clientEntryId;
  final Value<String> kind;
  final Value<String> localDate;
  final Value<String> payload;
  final Value<String> state;
  final Value<String?> serverId;
  final Value<int?> version;
  final Value<String?> rejectionCode;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalEntriesCompanion({
    this.clientEntryId = const Value.absent(),
    this.kind = const Value.absent(),
    this.localDate = const Value.absent(),
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    this.serverId = const Value.absent(),
    this.version = const Value.absent(),
    this.rejectionCode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalEntriesCompanion.insert({
    required String clientEntryId,
    required String kind,
    required String localDate,
    required String payload,
    required String state,
    this.serverId = const Value.absent(),
    this.version = const Value.absent(),
    this.rejectionCode = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : clientEntryId = Value(clientEntryId),
       kind = Value(kind),
       localDate = Value(localDate),
       payload = Value(payload),
       state = Value(state),
       updatedAt = Value(updatedAt);
  static Insertable<LocalEntry> custom({
    Expression<String>? clientEntryId,
    Expression<String>? kind,
    Expression<String>? localDate,
    Expression<String>? payload,
    Expression<String>? state,
    Expression<String>? serverId,
    Expression<int>? version,
    Expression<String>? rejectionCode,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientEntryId != null) 'client_entry_id': clientEntryId,
      if (kind != null) 'kind': kind,
      if (localDate != null) 'local_date': localDate,
      if (payload != null) 'payload': payload,
      if (state != null) 'state': state,
      if (serverId != null) 'server_id': serverId,
      if (version != null) 'version': version,
      if (rejectionCode != null) 'rejection_code': rejectionCode,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalEntriesCompanion copyWith({
    Value<String>? clientEntryId,
    Value<String>? kind,
    Value<String>? localDate,
    Value<String>? payload,
    Value<String>? state,
    Value<String?>? serverId,
    Value<int?>? version,
    Value<String?>? rejectionCode,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalEntriesCompanion(
      clientEntryId: clientEntryId ?? this.clientEntryId,
      kind: kind ?? this.kind,
      localDate: localDate ?? this.localDate,
      payload: payload ?? this.payload,
      state: state ?? this.state,
      serverId: serverId ?? this.serverId,
      version: version ?? this.version,
      rejectionCode: rejectionCode ?? this.rejectionCode,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientEntryId.present) {
      map['client_entry_id'] = Variable<String>(clientEntryId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rejectionCode.present) {
      map['rejection_code'] = Variable<String>(rejectionCode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalEntriesCompanion(')
          ..write('clientEntryId: $clientEntryId, ')
          ..write('kind: $kind, ')
          ..write('localDate: $localDate, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('serverId: $serverId, ')
          ..write('version: $version, ')
          ..write('rejectionCode: $rejectionCode, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedStatusTable extends CachedStatus
    with TableInfo<$CachedStatusTable, CachedStatusData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedStatusTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, json, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_status';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedStatusData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CachedStatusData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedStatusData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedStatusTable createAlias(String alias) {
    return $CachedStatusTable(attachedDatabase, alias);
  }
}

class CachedStatusData extends DataClass
    implements Insertable<CachedStatusData> {
  final String key;
  final String json;
  final DateTime updatedAt;
  const CachedStatusData({
    required this.key,
    required this.json,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['json'] = Variable<String>(json);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedStatusCompanion toCompanion(bool nullToAbsent) {
    return CachedStatusCompanion(
      key: Value(key),
      json: Value(json),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedStatusData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedStatusData(
      key: serializer.fromJson<String>(json['key']),
      json: serializer.fromJson<String>(json['json']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'json': serializer.toJson<String>(json),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedStatusData copyWith({String? key, String? json, DateTime? updatedAt}) =>
      CachedStatusData(
        key: key ?? this.key,
        json: json ?? this.json,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CachedStatusData copyWithCompanion(CachedStatusCompanion data) {
    return CachedStatusData(
      key: data.key.present ? data.key.value : this.key,
      json: data.json.present ? data.json.value : this.json,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedStatusData(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, json, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedStatusData &&
          other.key == this.key &&
          other.json == this.json &&
          other.updatedAt == this.updatedAt);
}

class CachedStatusCompanion extends UpdateCompanion<CachedStatusData> {
  final Value<String> key;
  final Value<String> json;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedStatusCompanion({
    this.key = const Value.absent(),
    this.json = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedStatusCompanion.insert({
    required String key,
    required String json,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       json = Value(json),
       updatedAt = Value(updatedAt);
  static Insertable<CachedStatusData> custom({
    Expression<String>? key,
    Expression<String>? json,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (json != null) 'json': json,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedStatusCompanion copyWith({
    Value<String>? key,
    Value<String>? json,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedStatusCompanion(
      key: key ?? this.key,
      json: json ?? this.json,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedStatusCompanion(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReferenceCacheTable extends ReferenceCache
    with TableInfo<$ReferenceCacheTable, ReferenceCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReferenceCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, etag, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reference_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReferenceCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    } else if (isInserting) {
      context.missing(_etagMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ReferenceCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReferenceCacheData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $ReferenceCacheTable createAlias(String alias) {
    return $ReferenceCacheTable(attachedDatabase, alias);
  }
}

class ReferenceCacheData extends DataClass
    implements Insertable<ReferenceCacheData> {
  final String key;
  final String etag;
  final String json;
  final DateTime fetchedAt;
  const ReferenceCacheData({
    required this.key,
    required this.etag,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['etag'] = Variable<String>(etag);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  ReferenceCacheCompanion toCompanion(bool nullToAbsent) {
    return ReferenceCacheCompanion(
      key: Value(key),
      etag: Value(etag),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory ReferenceCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReferenceCacheData(
      key: serializer.fromJson<String>(json['key']),
      etag: serializer.fromJson<String>(json['etag']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'etag': serializer.toJson<String>(etag),
      'json': serializer.toJson<String>(json),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  ReferenceCacheData copyWith({
    String? key,
    String? etag,
    String? json,
    DateTime? fetchedAt,
  }) => ReferenceCacheData(
    key: key ?? this.key,
    etag: etag ?? this.etag,
    json: json ?? this.json,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  ReferenceCacheData copyWithCompanion(ReferenceCacheCompanion data) {
    return ReferenceCacheData(
      key: data.key.present ? data.key.value : this.key,
      etag: data.etag.present ? data.etag.value : this.etag,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReferenceCacheData(')
          ..write('key: $key, ')
          ..write('etag: $etag, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, etag, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReferenceCacheData &&
          other.key == this.key &&
          other.etag == this.etag &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class ReferenceCacheCompanion extends UpdateCompanion<ReferenceCacheData> {
  final Value<String> key;
  final Value<String> etag;
  final Value<String> json;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const ReferenceCacheCompanion({
    this.key = const Value.absent(),
    this.etag = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReferenceCacheCompanion.insert({
    required String key,
    required String etag,
    required String json,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       etag = Value(etag),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<ReferenceCacheData> custom({
    Expression<String>? key,
    Expression<String>? etag,
    Expression<String>? json,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (etag != null) 'etag': etag,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReferenceCacheCompanion copyWith({
    Value<String>? key,
    Value<String>? etag,
    Value<String>? json,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return ReferenceCacheCompanion(
      key: key ?? this.key,
      etag: etag ?? this.etag,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReferenceCacheCompanion(')
          ..write('key: $key, ')
          ..write('etag: $etag, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String key;
  final String value;
  const SyncStateData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(key: Value(key), value: Value(value));
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncStateData copyWith({String? key, String? value}) =>
      SyncStateData(key: key ?? this.key, value: value ?? this.value);
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncStateData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $OutboxItemsTable outboxItems = $OutboxItemsTable(this);
  late final $LocalEntriesTable localEntries = $LocalEntriesTable(this);
  late final $CachedStatusTable cachedStatus = $CachedStatusTable(this);
  late final $ReferenceCacheTable referenceCache = $ReferenceCacheTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    outboxItems,
    localEntries,
    cachedStatus,
    referenceCache,
    syncState,
  ];
}

typedef $$OutboxItemsTableCreateCompanionBuilder =
    OutboxItemsCompanion Function({
      Value<int> id,
      required String clientEntryId,
      required String resource,
      required String method,
      required String path,
      Value<String?> body,
      Value<int?> ifMatchVersion,
      Value<int> attempts,
      Value<String?> lastErrorCode,
      required DateTime createdAt,
    });
typedef $$OutboxItemsTableUpdateCompanionBuilder =
    OutboxItemsCompanion Function({
      Value<int> id,
      Value<String> clientEntryId,
      Value<String> resource,
      Value<String> method,
      Value<String> path,
      Value<String?> body,
      Value<int?> ifMatchVersion,
      Value<int> attempts,
      Value<String?> lastErrorCode,
      Value<DateTime> createdAt,
    });

class $$OutboxItemsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxItemsTable> {
  $$OutboxItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientEntryId => $composableBuilder(
    column: $table.clientEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resource => $composableBuilder(
    column: $table.resource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ifMatchVersion => $composableBuilder(
    column: $table.ifMatchVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxItemsTable> {
  $$OutboxItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientEntryId => $composableBuilder(
    column: $table.clientEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resource => $composableBuilder(
    column: $table.resource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ifMatchVersion => $composableBuilder(
    column: $table.ifMatchVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxItemsTable> {
  $$OutboxItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientEntryId => $composableBuilder(
    column: $table.clientEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resource =>
      $composableBuilder(column: $table.resource, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get ifMatchVersion => $composableBuilder(
    column: $table.ifMatchVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxItemsTable,
          OutboxItem,
          $$OutboxItemsTableFilterComposer,
          $$OutboxItemsTableOrderingComposer,
          $$OutboxItemsTableAnnotationComposer,
          $$OutboxItemsTableCreateCompanionBuilder,
          $$OutboxItemsTableUpdateCompanionBuilder,
          (
            OutboxItem,
            BaseReferences<_$AppDatabase, $OutboxItemsTable, OutboxItem>,
          ),
          OutboxItem,
          PrefetchHooks Function()
        > {
  $$OutboxItemsTableTableManager(_$AppDatabase db, $OutboxItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> clientEntryId = const Value.absent(),
                Value<String> resource = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<int?> ifMatchVersion = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OutboxItemsCompanion(
                id: id,
                clientEntryId: clientEntryId,
                resource: resource,
                method: method,
                path: path,
                body: body,
                ifMatchVersion: ifMatchVersion,
                attempts: attempts,
                lastErrorCode: lastErrorCode,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String clientEntryId,
                required String resource,
                required String method,
                required String path,
                Value<String?> body = const Value.absent(),
                Value<int?> ifMatchVersion = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                required DateTime createdAt,
              }) => OutboxItemsCompanion.insert(
                id: id,
                clientEntryId: clientEntryId,
                resource: resource,
                method: method,
                path: path,
                body: body,
                ifMatchVersion: ifMatchVersion,
                attempts: attempts,
                lastErrorCode: lastErrorCode,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxItemsTable, OutboxItem>(table),
                  BaseReferences<_$AppDatabase, $OutboxItemsTable, OutboxItem>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxItemsTable,
      OutboxItem,
      $$OutboxItemsTableFilterComposer,
      $$OutboxItemsTableOrderingComposer,
      $$OutboxItemsTableAnnotationComposer,
      $$OutboxItemsTableCreateCompanionBuilder,
      $$OutboxItemsTableUpdateCompanionBuilder,
      (
        OutboxItem,
        BaseReferences<_$AppDatabase, $OutboxItemsTable, OutboxItem>,
      ),
      OutboxItem,
      PrefetchHooks Function()
    >;
typedef $$LocalEntriesTableCreateCompanionBuilder =
    LocalEntriesCompanion Function({
      required String clientEntryId,
      required String kind,
      required String localDate,
      required String payload,
      required String state,
      Value<String?> serverId,
      Value<int?> version,
      Value<String?> rejectionCode,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalEntriesTableUpdateCompanionBuilder =
    LocalEntriesCompanion Function({
      Value<String> clientEntryId,
      Value<String> kind,
      Value<String> localDate,
      Value<String> payload,
      Value<String> state,
      Value<String?> serverId,
      Value<int?> version,
      Value<String?> rejectionCode,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalEntriesTable> {
  $$LocalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientEntryId => $composableBuilder(
    column: $table.clientEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectionCode => $composableBuilder(
    column: $table.rejectionCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalEntriesTable> {
  $$LocalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientEntryId => $composableBuilder(
    column: $table.clientEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectionCode => $composableBuilder(
    column: $table.rejectionCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalEntriesTable> {
  $$LocalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientEntryId => $composableBuilder(
    column: $table.clientEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get rejectionCode => $composableBuilder(
    column: $table.rejectionCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalEntriesTable,
          LocalEntry,
          $$LocalEntriesTableFilterComposer,
          $$LocalEntriesTableOrderingComposer,
          $$LocalEntriesTableAnnotationComposer,
          $$LocalEntriesTableCreateCompanionBuilder,
          $$LocalEntriesTableUpdateCompanionBuilder,
          (
            LocalEntry,
            BaseReferences<_$AppDatabase, $LocalEntriesTable, LocalEntry>,
          ),
          LocalEntry,
          PrefetchHooks Function()
        > {
  $$LocalEntriesTableTableManager(_$AppDatabase db, $LocalEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clientEntryId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<int?> version = const Value.absent(),
                Value<String?> rejectionCode = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalEntriesCompanion(
                clientEntryId: clientEntryId,
                kind: kind,
                localDate: localDate,
                payload: payload,
                state: state,
                serverId: serverId,
                version: version,
                rejectionCode: rejectionCode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientEntryId,
                required String kind,
                required String localDate,
                required String payload,
                required String state,
                Value<String?> serverId = const Value.absent(),
                Value<int?> version = const Value.absent(),
                Value<String?> rejectionCode = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalEntriesCompanion.insert(
                clientEntryId: clientEntryId,
                kind: kind,
                localDate: localDate,
                payload: payload,
                state: state,
                serverId: serverId,
                version: version,
                rejectionCode: rejectionCode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalEntriesTable, LocalEntry>(table),
                  BaseReferences<_$AppDatabase, $LocalEntriesTable, LocalEntry>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalEntriesTable,
      LocalEntry,
      $$LocalEntriesTableFilterComposer,
      $$LocalEntriesTableOrderingComposer,
      $$LocalEntriesTableAnnotationComposer,
      $$LocalEntriesTableCreateCompanionBuilder,
      $$LocalEntriesTableUpdateCompanionBuilder,
      (
        LocalEntry,
        BaseReferences<_$AppDatabase, $LocalEntriesTable, LocalEntry>,
      ),
      LocalEntry,
      PrefetchHooks Function()
    >;
typedef $$CachedStatusTableCreateCompanionBuilder =
    CachedStatusCompanion Function({
      required String key,
      required String json,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedStatusTableUpdateCompanionBuilder =
    CachedStatusCompanion Function({
      Value<String> key,
      Value<String> json,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedStatusTableFilterComposer
    extends Composer<_$AppDatabase, $CachedStatusTable> {
  $$CachedStatusTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedStatusTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedStatusTable> {
  $$CachedStatusTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedStatusTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedStatusTable> {
  $$CachedStatusTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedStatusTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedStatusTable,
          CachedStatusData,
          $$CachedStatusTableFilterComposer,
          $$CachedStatusTableOrderingComposer,
          $$CachedStatusTableAnnotationComposer,
          $$CachedStatusTableCreateCompanionBuilder,
          $$CachedStatusTableUpdateCompanionBuilder,
          (
            CachedStatusData,
            BaseReferences<_$AppDatabase, $CachedStatusTable, CachedStatusData>,
          ),
          CachedStatusData,
          PrefetchHooks Function()
        > {
  $$CachedStatusTableTableManager(_$AppDatabase db, $CachedStatusTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedStatusTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedStatusTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedStatusTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedStatusCompanion(
                key: key,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String json,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedStatusCompanion.insert(
                key: key,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedStatusTable, CachedStatusData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedStatusTable,
                    CachedStatusData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedStatusTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedStatusTable,
      CachedStatusData,
      $$CachedStatusTableFilterComposer,
      $$CachedStatusTableOrderingComposer,
      $$CachedStatusTableAnnotationComposer,
      $$CachedStatusTableCreateCompanionBuilder,
      $$CachedStatusTableUpdateCompanionBuilder,
      (
        CachedStatusData,
        BaseReferences<_$AppDatabase, $CachedStatusTable, CachedStatusData>,
      ),
      CachedStatusData,
      PrefetchHooks Function()
    >;
typedef $$ReferenceCacheTableCreateCompanionBuilder =
    ReferenceCacheCompanion Function({
      required String key,
      required String etag,
      required String json,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$ReferenceCacheTableUpdateCompanionBuilder =
    ReferenceCacheCompanion Function({
      Value<String> key,
      Value<String> etag,
      Value<String> json,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$ReferenceCacheTableFilterComposer
    extends Composer<_$AppDatabase, $ReferenceCacheTable> {
  $$ReferenceCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReferenceCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $ReferenceCacheTable> {
  $$ReferenceCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReferenceCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReferenceCacheTable> {
  $$ReferenceCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$ReferenceCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReferenceCacheTable,
          ReferenceCacheData,
          $$ReferenceCacheTableFilterComposer,
          $$ReferenceCacheTableOrderingComposer,
          $$ReferenceCacheTableAnnotationComposer,
          $$ReferenceCacheTableCreateCompanionBuilder,
          $$ReferenceCacheTableUpdateCompanionBuilder,
          (
            ReferenceCacheData,
            BaseReferences<
              _$AppDatabase,
              $ReferenceCacheTable,
              ReferenceCacheData
            >,
          ),
          ReferenceCacheData,
          PrefetchHooks Function()
        > {
  $$ReferenceCacheTableTableManager(
    _$AppDatabase db,
    $ReferenceCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReferenceCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReferenceCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReferenceCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> etag = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReferenceCacheCompanion(
                key: key,
                etag: etag,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String etag,
                required String json,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReferenceCacheCompanion.insert(
                key: key,
                etag: etag,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReferenceCacheTable, ReferenceCacheData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReferenceCacheTable,
                    ReferenceCacheData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReferenceCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReferenceCacheTable,
      ReferenceCacheData,
      $$ReferenceCacheTableFilterComposer,
      $$ReferenceCacheTableOrderingComposer,
      $$ReferenceCacheTableAnnotationComposer,
      $$ReferenceCacheTableCreateCompanionBuilder,
      $$ReferenceCacheTableUpdateCompanionBuilder,
      (
        ReferenceCacheData,
        BaseReferences<_$AppDatabase, $ReferenceCacheTable, ReferenceCacheData>,
      ),
      ReferenceCacheData,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncStateData>(table),
                  BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$OutboxItemsTableTableManager get outboxItems =>
      $$OutboxItemsTableTableManager(_db, _db.outboxItems);
  $$LocalEntriesTableTableManager get localEntries =>
      $$LocalEntriesTableTableManager(_db, _db.localEntries);
  $$CachedStatusTableTableManager get cachedStatus =>
      $$CachedStatusTableTableManager(_db, _db.cachedStatus);
  $$ReferenceCacheTableTableManager get referenceCache =>
      $$ReferenceCacheTableTableManager(_db, _db.referenceCache);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
