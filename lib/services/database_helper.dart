// database_helper.dart - Local caching database for offline support
// Add to your Flutter project: lib/services/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('thermostat_cache.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Device configuration cache
    await db.execute('''
      CREATE TABLE device_config (
        device_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        api_url TEXT NOT NULL,
        device_type TEXT NOT NULL,
        location TEXT,
        set_temperature REAL,
        current_mode TEXT,
        last_sync INTEGER,
        is_online INTEGER DEFAULT 1
      )
    ''');

    // Sensor data cache (last 100 readings per device)
    await db.execute('''
      CREATE TABLE sensor_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        temperature REAL,
        humidity REAL,
        timestamp INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (device_id) REFERENCES device_config(device_id)
      )
    ''');

    // Create index for faster queries
    await db.execute('''
      CREATE INDEX idx_sensor_data_device_time 
      ON sensor_data(device_id, timestamp DESC)
    ''');

    // Mode updates queue (for when offline)
    await db.execute('''
      CREATE TABLE pending_updates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        update_type TEXT NOT NULL,
        update_data TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    // App settings
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns if needed
      await db.execute('ALTER TABLE device_config ADD COLUMN location TEXT');
    }
  }

  // ===== DEVICE CONFIG METHODS =====

  Future<int> cacheDeviceConfig(Map<String, dynamic> config) async {
    final db = await database;
    return await db.insert(
      'device_config',
      config,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCachedDeviceConfig(String deviceId) async {
    final db = await database;
    final results = await db.query(
      'device_config',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllCachedDevices() async {
    final db = await database;
    return await db.query('device_config', orderBy: 'display_name ASC');
  }

  Future<int> updateDeviceConfig(String deviceId, Map<String, dynamic> updates) async {
    final db = await database;
    return await db.update(
      'device_config',
      updates,
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<int> deleteDeviceConfig(String deviceId) async {
    final db = await database;
    // Also delete associated data
    await db.delete('sensor_data', where: 'device_id = ?', whereArgs: [deviceId]);
    await db.delete('pending_updates', where: 'device_id = ?', whereArgs: [deviceId]);
    return await db.delete('device_config', where: 'device_id = ?', whereArgs: [deviceId]);
  }

  // ===== SENSOR DATA METHODS =====

  Future<int> cacheSensorReading(String deviceId, double? temp, double? humidity) async {
    final db = await database;
    
    // First, insert new reading
    final id = await db.insert('sensor_data', {
      'device_id': deviceId,
      'temperature': temp,
      'humidity': humidity,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'synced': 1, // Mark as synced since we got it from server
    });

    // Keep only last 100 readings per device
    await db.delete(
      'sensor_data',
      where: '''device_id = ? AND id NOT IN (
        SELECT id FROM sensor_data 
        WHERE device_id = ? 
        ORDER BY timestamp DESC 
        LIMIT 100
      )''',
      whereArgs: [deviceId, deviceId],
    );

    return id;
  }

  Future<List<Map<String, dynamic>>> getRecentReadings(String deviceId, int limit) async {
    final db = await database;
    return await db.query(
      'sensor_data',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getLastReading(String deviceId) async {
    final db = await database;
    final results = await db.query(
      'sensor_data',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ===== PENDING UPDATES METHODS =====

  Future<int> addPendingUpdate(String deviceId, String updateType, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('pending_updates', {
      'device_id': deviceId,
      'update_type': updateType,
      'update_data': jsonEncode(data),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingUpdates() async {
    final db = await database;
    return await db.query(
      'pending_updates',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> markUpdateSynced(int id) async {
    final db = await database;
    return await db.update(
      'pending_updates',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteOldPendingUpdates() async {
    final db = await database;
    // Delete synced updates older than 24 hours
    final cutoff = DateTime.now().subtract(Duration(hours: 24)).millisecondsSinceEpoch;
    return await db.delete(
      'pending_updates',
      where: 'synced = 1 AND timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  // ===== DEVICE STATUS METHODS =====

  Future<void> updateDeviceStatus(String deviceId, bool isOnline) async {
    final db = await database;
    await db.update(
      'device_config',
      {
        'is_online': isOnline ? 1 : 0,
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<bool> isDeviceOnline(String deviceId) async {
    final db = await database;
    final results = await db.query(
      'device_config',
      columns: ['is_online', 'last_sync'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    
    if (results.isEmpty) return false;
    
    final isOnline = results.first['is_online'] == 1;
    final lastSync = results.first['last_sync'] as int?;
    
    // Consider offline if last sync was more than 5 minutes ago
    if (lastSync != null) {
      final age = DateTime.now().millisecondsSinceEpoch - lastSync;
      if (age > 300000) return false; // 5 minutes
    }
    
    return isOnline;
  }

  // ===== APP SETTINGS METHODS =====

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return results.isNotEmpty ? results.first['value'] as String? : null;
  }

  // ===== STATISTICS =====

  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;
    
    final deviceCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM device_config')
    );
    
    final sensorDataCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sensor_data')
    );
    
    final pendingCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM pending_updates WHERE synced = 0')
    );
    
    return {
      'devices': deviceCount ?? 0,
      'sensor_readings': sensorDataCount ?? 0,
      'pending_updates': pendingCount ?? 0,
    };
  }

  // ===== MAINTENANCE =====

  Future<void> cleanup() async {
    final db = await database;
    
    // Delete old sensor data (keep last 100 per device)
    await db.execute('''
      DELETE FROM sensor_data 
      WHERE id NOT IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY timestamp DESC) as rn 
          FROM sensor_data
        ) WHERE rn <= 100
      )
    ''');
    
    // Delete old synced updates
    await deleteOldPendingUpdates();
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'thermostat_cache.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }
}
