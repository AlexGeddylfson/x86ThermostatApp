// sync_manager.dart - Enhanced with better offline support
// Add to your Flutter project: lib/services/sync_manager.dart

import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'database_helper.dart';

class SyncManager {
  static final SyncManager instance = SyncManager._init();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  
  Timer? _syncTimer;
  Timer? _statusTimer;
  bool _isSyncing = false;
  bool _serverAvailable = true;
  
  // Callbacks for UI updates
  Function(String deviceId, bool isOnline)? onDeviceStatusChanged;
  Function(int pendingCount)? onPendingCountChanged;
  Function(bool serverAvailable)? onServerStatusChanged;

  SyncManager._init();

  // Start periodic sync (every 30 seconds)
  void startPeriodicSync() {
    stopPeriodicSync(); // Stop any existing timer
    
    _syncTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      syncPendingUpdates();
    });
    
    // Also check device status every 10 seconds
    _statusTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      checkAllDeviceStatus();
    });
    
    print('[SyncManager] Periodic sync started');
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _statusTimer?.cancel();
    _statusTimer = null;
    print('[SyncManager] Periodic sync stopped');
  }

  // Sync pending updates to server
  Future<void> syncPendingUpdates() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    try {
      final pending = await _dbHelper.getPendingUpdates();
      
      if (pending.isEmpty) {
        return;
      }
      
      print('[SyncManager] Syncing ${pending.length} pending updates');
      
      int successCount = 0;
      for (var update in pending) {
        try {
          final deviceId = update['device_id'] as String;
          final updateType = update['update_type'] as String;
          final updateData = jsonDecode(update['update_data'] as String);
          
          // Get device config to find API URL
          final deviceConfig = await _dbHelper.getCachedDeviceConfig(deviceId);
          if (deviceConfig == null) {
            print('[SyncManager] Device config not found for $deviceId');
            continue;
          }
          
          final apiUrl = deviceConfig['api_url'] as String;
          
          // Send update based on type
          bool success = false;
          switch (updateType) {
            case 'set_temperature':
              success = await _sendTemperatureUpdate(apiUrl, deviceId, updateData);
              break;
            case 'set_mode':
              success = await _sendModeUpdate(apiUrl, deviceId, updateData);
              break;
            case 'config_update':
              success = await _sendConfigUpdate(apiUrl, deviceId, updateData);
              break;
          }
          
          if (success) {
            await _dbHelper.markUpdateSynced(update['id'] as int);
            successCount++;
            print('[SyncManager] Synced update ${update['id']} for device $deviceId');
          }
        } catch (e) {
          print('[SyncManager] Failed to sync update ${update['id']}: $e');
        }
      }
      
      if (successCount > 0) {
        print('[SyncManager] Successfully synced $successCount/${pending.length} updates');
        onPendingCountChanged?.call(pending.length - successCount);
      }
      
      // Cleanup old synced updates
      await _dbHelper.deleteOldPendingUpdates();
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _sendTemperatureUpdate(String apiUrl, String deviceId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/set_temperature'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('[SyncManager] Temperature update failed: $e');
      return false;
    }
  }

  Future<bool> _sendModeUpdate(String apiUrl, String deviceId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/set_mode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('[SyncManager] Mode update failed: $e');
      return false;
    }
  }

  Future<bool> _sendConfigUpdate(String apiUrl, String deviceId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/config/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('[SyncManager] Config update failed: $e');
      return false;
    }
  }

  // NEW: Fetch and cache devices from server with fallback to cache
  Future<List<Map<String, dynamic>>> fetchDevicesWithCache(String serverUrl) async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/devices'),
      ).timeout(Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final devices = List<Map<String, dynamic>>.from(data['devices'] ?? []);
        
        // Cache each device
        for (var device in devices) {
          final deviceId = device['device_id'];
          final apiUrl = device['ip_address'] != null && device['ip_address'].isNotEmpty
              ? 'http://${device['ip_address']}:5001'
              : '';
          
          await _dbHelper.cacheDeviceConfig({
            'device_id': deviceId,
            'display_name': device['device_name'] ?? deviceId,
            'api_url': apiUrl,
            'device_type': device['device_type'] ?? 'Unknown',
            'location': device['location'] ?? '',
            'set_temperature': device['set_temperature'],
            'current_mode': null,
            'last_sync': DateTime.now().millisecondsSinceEpoch,
            'is_online': 1,
          });
        }
        
        // Update server status
        if (!_serverAvailable) {
          _serverAvailable = true;
          onServerStatusChanged?.call(true);
          print('[SyncManager] Server connection restored');
        }
        
        return devices;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('[SyncManager] Failed to fetch devices from server: $e');
      
      // Update server status
      if (_serverAvailable) {
        _serverAvailable = false;
        onServerStatusChanged?.call(false);
        print('[SyncManager] Server unavailable - using cached data');
      }
      
      // Fallback to cached devices
      final cachedDevices = await _dbHelper.getAllCachedDevices();
      return cachedDevices.map((device) => {
        'device_id': device['device_id'],
        'device_name': device['display_name'],
        'device_type': device['device_type'],
        'location': device['location'],
        'ip_address': device['api_url']?.toString().replaceAll('http://', '').replaceAll(':5001', ''),
        'is_active': device['is_online'] == 1,
        'last_seen': null,
      }).toList();
    }
  }

  // Fetch and cache data from server
  Future<bool> fetchAndCacheDeviceData(String deviceId, String apiUrl) async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/status'),
      ).timeout(Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Cache the reading
        await _dbHelper.cacheSensorReading(
          deviceId,
          data['temperature']?.toDouble(),
          data['humidity']?.toDouble(),
        );
        
        // Update device config with latest data
        await _dbHelper.updateDeviceConfig(deviceId, {
          'set_temperature': data['set_temperature']?.toDouble(),
          'current_mode': data['state']?.toString(),
          'last_sync': DateTime.now().millisecondsSinceEpoch,
        });
        
        // Update online status
        await _dbHelper.updateDeviceStatus(deviceId, true);
        onDeviceStatusChanged?.call(deviceId, true);
        
        return true;
      } else {
        await _dbHelper.updateDeviceStatus(deviceId, false);
        onDeviceStatusChanged?.call(deviceId, false);
        return false;
      }
    } catch (e) {
      print('[SyncManager] Failed to fetch data for $deviceId: $e');
      await _dbHelper.updateDeviceStatus(deviceId, false);
      onDeviceStatusChanged?.call(deviceId, false);
      return false;
    }
  }

  // Check status of all devices
  Future<void> checkAllDeviceStatus() async {
    try {
      final devices = await _dbHelper.getAllCachedDevices();
      
      for (var device in devices) {
        final deviceId = device['device_id'] as String;
        final apiUrl = device['api_url'] as String;
        
        if (apiUrl.isEmpty) continue;
        
        // Don't block on each device
        fetchAndCacheDeviceData(deviceId, apiUrl).then((_) {
          // Status updated
        });
      }
    } catch (e) {
      print('[SyncManager] Error checking device status: $e');
    }
  }

  // Get pending update count
  Future<int> getPendingCount() async {
    final pending = await _dbHelper.getPendingUpdates();
    return pending.length;
  }

  // Force immediate sync
  Future<void> forceSyncNow() async {
    print('[SyncManager] Force sync requested');
    await syncPendingUpdates();
    await checkAllDeviceStatus();
  }

  // Check if server is available
  bool isServerAvailable() => _serverAvailable;
}

// Extension for easier use in widgets
extension SyncManagerContext on SyncManager {
  // Queue a temperature change
  Future<void> queueTemperatureChange(String deviceId, double temperature) async {
    await _dbHelper.addPendingUpdate(
      deviceId,
      'set_temperature',
      {'temperature': temperature},
    );
    
    // Also update local cache immediately
    await _dbHelper.updateDeviceConfig(deviceId, {
      'set_temperature': temperature,
    });
    
    // Try immediate sync
    syncPendingUpdates();
  }

  // Queue a mode change
  Future<void> queueModeChange(String deviceId, String mode) async {
    await _dbHelper.addPendingUpdate(
      deviceId,
      'set_mode',
      {'mode': mode},
    );
    
    // Try immediate sync
    syncPendingUpdates();
  }

  // Queue a config update
  Future<void> queueConfigUpdate(String deviceId, Map<String, dynamic> config) async {
    await _dbHelper.addPendingUpdate(
      deviceId,
      'config_update',
      config,
    );
    
    // Try immediate sync
    syncPendingUpdates();
  }
}