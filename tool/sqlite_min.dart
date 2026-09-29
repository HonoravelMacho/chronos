// CHRONOS — binding SQLite mínimo (dart:ffi puro) para o daemon headless.
//
// Por que não package:sqlite3? O `dart compile exe` não embute native
// assets, e o .so carregado via DynamicLibrary.open é RTLD_LOCAL
// (invisível ao fallback de lookup do package). Aqui abrimos o .so que
// viaja junto em /opt/chronos/lib (ou o do sistema) e chamamos direto.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';

import 'package:ffi/ffi.dart';

const _row = 100;
const _done = 101;
const _transient = -1;

/// Banco SQLite via FFI direto. SQL do daemon é simples (SELECT/UPDATE/INSERT).
class MiniDb {
  MiniDb._(this._lib, this._db);

  final DynamicLibrary _lib;
  final Pointer<Void> _db;
  bool _closed = false;

  late final int Function(Pointer<Void>) _close = _lib
      .lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('sqlite3_close_v2');
  late final int Function(
      Pointer<Void>, Pointer<Utf8>, Pointer<Void>, Pointer<Void>,
      Pointer<Pointer<Utf8>>) _exec = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>,
          Pointer<Void>, Pointer<Pointer<Utf8>>),
      int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>,
          Pointer<Void>, Pointer<Pointer<Utf8>>)>('sqlite3_exec');
  late final void Function(Pointer<Void>) _free = _lib
      .lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('sqlite3_free');

  String _err() {
    final p = _lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)>('sqlite3_errmsg')(_db);
    return p.toDartString();
  }

  static MiniDb open(String path, DynamicLibrary lib) {
    final dbOut = calloc<Pointer<Void>>();
    final openFn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Pointer<Void>>, Int32,
            Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Pointer<Void>>, int,
            Pointer<Utf8>)>('sqlite3_open_v2');
    final pathPtr = path.toNativeUtf8();
    try {
      // READWRITE(0x2) | CREATE(0x4) = 6
      final rc = openFn(pathPtr, dbOut, 6, nullptr);
      final db = dbOut.value;
      if (rc != 0 || db == nullptr) {
        throw StateError('sqlite open rc=$rc');
      }
      return MiniDb._(lib, db);
    } finally {
      calloc.free(pathPtr);
      calloc.free(dbOut);
    }
  }

  void setBusyTimeout(int ms) {
    // O .so enxuto não exporta sqlite3_busy_timeout — PRAGMA equivale.
    execute('PRAGMA busy_timeout = $ms');
  }

  void _bind(Pointer<Void> stmt, int i, Object? v) {
    int rc;
    if (v == null) {
      rc = _lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>(
          'sqlite3_bind_null')(stmt, i);
    } else if (v is int) {
      rc = _lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32, Int64),
          int Function(Pointer<Void>, int, int)>(
          'sqlite3_bind_int64')(stmt, i, v);
    } else {
      final t = v.toString().toNativeUtf8();
      try {
        rc = _lib.lookupFunction<
            Int32 Function(
                Pointer<Void>, Int32, Pointer<Utf8>, Int32, Int64),
            int Function(
                Pointer<Void>, int, Pointer<Utf8>, int, int)>(
            'sqlite3_bind_text')(stmt, i, t, -1, _transient);
      } finally {
        calloc.free(t);
      }
    }
    if (rc != 0) throw StateError(_err());
  }

  List<Map<String, Object?>> query(String sql, [List<Object?> args = const []]) {
    final stmtOut = calloc<Pointer<Void>>();
    final sqlPtr = sql.toNativeUtf8();
    try {
      final prep = _lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32,
              Pointer<Pointer<Void>>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>, int,
              Pointer<Pointer<Void>>, Pointer<Utf8>)>(
          'sqlite3_prepare_v2');
      var rc = prep(_db, sqlPtr, -1, stmtOut, nullptr);
      if (rc != 0) throw StateError(_err());
      final stmt = stmtOut.value;
      try {
        for (var i = 0; i < args.length; i++) {
          _bind(stmt, i + 1, args[i]);
        }
        final step = _lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('sqlite3_step');
        final colCount = _lib.lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('sqlite3_column_count');
        final colName = _lib.lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Int32),
            Pointer<Utf8> Function(Pointer<Void>, int)>(
            'sqlite3_column_name');
        final colType = _lib.lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)>('sqlite3_column_type');
        final colText = _lib.lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Int32),
            Pointer<Utf8> Function(Pointer<Void>, int)>(
            'sqlite3_column_text');
        final colInt = _lib.lookupFunction<
            Int64 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)>('sqlite3_column_int64');
        final out = <Map<String, Object?>>[];
        for (;;) {
          rc = step(stmt);
          if (rc == _done) break;
          if (rc != _row) throw StateError(_err());
          final n = colCount(stmt);
          final row = <String, Object?>{};
          for (var c = 0; c < n; c++) {
            final name = colName(stmt, c).toDartString();
            final t = colType(stmt, c);
            row[name] = t == 4 // BLOB: mostra como texto quando possível
                ? colText(stmt, c).toDartString()
                : t == 1
                    ? colInt(stmt, c)
                    : t == 5
                        ? null
                        : colText(stmt, c).toDartString();
          }
          out.add(row);
        }
        return out;
      } finally {
        _lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('sqlite3_finalize')(stmt);
      }
    } finally {
      calloc.free(sqlPtr);
      calloc.free(stmtOut);
    }
  }

  void execute(String sql, [List<Object?> args = const []]) {
    if (args.isEmpty) {
      final sqlPtr = sql.toNativeUtf8();
      final errOut = calloc<Pointer<Utf8>>();
      try {
        final rc = _exec(_db, sqlPtr, nullptr, nullptr, errOut);
        if (rc != 0) {
          final msg = errOut.value == nullptr
              ? _err()
              : errOut.value.toDartString();
          throw StateError(msg);
        }
      } finally {
        if (errOut.value != nullptr) _free(errOut.value.cast<Void>());
        calloc.free(errOut);
        calloc.free(sqlPtr);
      }
      return;
    }
    // Com args: prepara + step único (sem linhas).
    final rows = query(sql, args);
    if (rows.isNotEmpty) throw StateError('execute retornou linhas');
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _close(_db);
    }
  }
}
