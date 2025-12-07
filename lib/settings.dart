import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'device_config_screen.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TextEditingController serverApiUrlController = TextEditingController();
  List<Map<String, dynamic>> devices = [];
  bool darkModeSwitchValue = false;
  bool isLoading = true;
  bool hasReordered = false; // Track if user has reordered devices

  @override
  void initState() {
    super.initState();
    serverApiUrlController.text = AppConfig.serverApiUrl;
    darkModeSwitchValue = MyApp.currentThemeMode == ThemeMode.dark;
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.serverApiUrl}api/devices')
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<Map<String, dynamic>> fetchedDevices = 
            List<Map<String, dynamic>>.from(data['devices'] ?? []);
        
        // Load saved order from SharedPreferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        List<String>? savedOrder = prefs.getStringList('deviceOrder');
        
        if (savedOrder != null && savedOrder.isNotEmpty) {
          // Reorder devices based on saved order
          List<Map<String, dynamic>> orderedDevices = [];
          
          // Add devices in saved order
          for (String deviceId in savedOrder) {
            var device = fetchedDevices.firstWhere(
              (d) => d['device_id'] == deviceId,
              orElse: () => {},
            );
            if (device.isNotEmpty) {
              orderedDevices.add(device);
            }
          }
          
          // Add any new devices not in saved order
          for (var device in fetchedDevices) {
            if (!savedOrder.contains(device['device_id'])) {
              orderedDevices.add(device);
            }
          }
          
          fetchedDevices = orderedDevices;
        } else {
          // Default sort if no saved order
          fetchedDevices.sort((a, b) {
            const typeOrder = {
              'Thermostat': 1,
              'HybridThermo': 2,
              'HybridProbe': 3,
              'Probe': 4,
              'Server': 5,
            };
            
            int orderA = typeOrder[a['device_type']] ?? 6;
            int orderB = typeOrder[b['device_type']] ?? 6;
            
            if (orderA != orderB) return orderA.compareTo(orderB);
            return (a['device_name'] ?? a['device_id']).compareTo(
                b['device_name'] ?? b['device_id']);
          });
        }
        
        setState(() {
          devices = fetchedDevices;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading devices: $e');
      setState(() {
        isLoading = false;
      });
      _showErrorSnackBar('Failed to load devices from server');
    }
  }

  Future<void> _saveDeviceOrder() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> deviceOrder = devices
        .where((d) => d['is_active'] == true)
        .map((d) => d['device_id'] as String)
        .toList();
    await prefs.setStringList('deviceOrder', deviceOrder);
    
    setState(() {
      hasReordered = false;
    });
    
    _showSuccessSnackBar('Device order saved');
  }

  Future<void> _resetDeviceOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Device Order'),
        content: Text('This will reset devices to the default order (by type, then name). Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('deviceOrder');
      
      setState(() {
        hasReordered = false;
      });
      
      await _loadDevices();
      _showSuccessSnackBar('Device order reset to default');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDevices,
            tooltip: 'Refresh devices',
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildServerSection(),
                  SizedBox(height: 24),
                  _buildDevicesSection(),
                  SizedBox(height: 24),
                  _buildAppearanceSection(),
                  SizedBox(height: 24),
                  _buildActionsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildServerSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            TextField(
              controller: serverApiUrlController,
              decoration: InputDecoration(
                labelText: 'Server API URL',
                hintText: 'http://192.168.1.100:5000/',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _testConnection,
                    icon: Icon(Icons.network_check),
                    label: Text('Test Connection'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showHealthCheckDialog,
                    icon: Icon(Icons.monitor_heart),
                    label: Text('Health Check'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Registered Devices (${devices.length})',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasReordered)
                      Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Chip(
                          label: Text('Unsaved', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.orange.withOpacity(0.2),
                          avatar: Icon(Icons.warning, size: 14, color: Colors.orange),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    IconButton(
                      icon: Icon(Icons.info_outline),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Device Management'),
                            content: Text(
                              'Devices register themselves automatically when they boot up. '
                              'Use the Edit button to configure device names, locations, and settings.\n\n'
                              'Drag and drop devices to reorder them - the order will be reflected on the home screen.'
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      tooltip: 'About device management',
                      padding: EdgeInsets.all(8),
                      constraints: BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8),
            if (devices.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasReordered)
                    TextButton.icon(
                      onPressed: _saveDeviceOrder,
                      icon: Icon(Icons.save, size: 18),
                      label: Text('Save Order'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _resetDeviceOrder,
                    icon: Icon(Icons.restore, size: 18),
                    label: Text('Reset Order'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange,
                    ),
                  ),
                ],
              ),
            SizedBox(height: 12),
            if (devices.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.device_unknown, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('No devices found'),
                      SizedBox(height: 4),
                      Text(
                        'Devices will appear here after they boot up and register with the server',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      TextButton(
                        onPressed: _loadDevices,
                        child: Text('Refresh'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: devices.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final device = devices.removeAt(oldIndex);
                    devices.insert(newIndex, device);
                    hasReordered = true;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildDeviceTile(devices[index], index);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(Map<String, dynamic> device, int index) {
    final deviceId = device['device_id'] ?? '';
    final deviceType = device['device_type'] ?? 'Unknown';
    final deviceName = device['device_name'] ?? deviceId;
    final location = device['location'] ?? '';
    final isActive = device['is_active'] ?? true;
    final lastSeen = device['last_seen'];

    IconData icon;
    Color iconColor;
    
    switch (deviceType) {
      case 'Thermostat':
        icon = Icons.thermostat;
        iconColor = Colors.orange;
        break;
      case 'HybridThermo':
        icon = Icons.hub;
        iconColor = Colors.deepOrange;
        break;
      case 'Probe':
        icon = Icons.sensors;
        iconColor = Colors.blue;
        break;
      case 'HybridProbe':
        icon = Icons.router;
        iconColor = Colors.lightBlue;
        break;
      default:
        icon = Icons.device_unknown;
        iconColor = Colors.grey;
    }

    // Determine online status
    bool isOnline = false;
    String statusText = 'Offline';
    Color statusColor = Colors.red;
    
    if (lastSeen != null) {
      try {
        final lastSeenDate = DateTime.parse(lastSeen.toString());
        final now = DateTime.now();
        final difference = now.difference(lastSeenDate);
        
        if (difference.inMinutes < 2) {
          isOnline = true;
          statusText = 'Online';
          statusColor = Colors.green;
        } else {
          statusText = 'Last seen ${_formatTimeSince(difference)}';
          statusColor = Colors.orange;
        }
      } catch (e) {
        // If parsing fails, assume offline
      }
    }

    return Card(
      key: ValueKey(deviceId), // Required for ReorderableListView
      margin: EdgeInsets.only(bottom: 8),
      elevation: isActive ? 2 : 0,
      color: isActive ? null : Colors.grey[300],
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_handle, color: Colors.grey),
            SizedBox(width: 8),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Icon(icon, color: iconColor, size: 36),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ],
            ),
          ],
        ),
        title: Text(
          deviceName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isActive ? null : Colors.grey[600],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: $deviceType'),
            if (location.isNotEmpty) Text('Location: $location'),
            Text('ID: $deviceId', style: TextStyle(fontSize: 11)),
            Row(
              children: [
                Icon(
                  isOnline ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: statusColor,
                ),
                SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (!isActive)
              Text(
                'Inactive',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'configure',
              child: Row(
                children: [
                  Icon(Icons.settings, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Configure'),
                ],
              ),
            ),
            if (isActive)
              PopupMenuItem(
                value: 'deactivate',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Deactivate'),
                  ],
                ),
              ),
            if (!isActive)
              PopupMenuItem(
                value: 'activate',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Activate'),
                  ],
                ),
              ),
          ],
          onSelected: (value) async {
            switch (value) {
              case 'configure':
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    // FIX 1: Pass the devices list (State variable)
                    builder: (context) => DeviceConfigScreen(
                      device: device,
                      serverUrl: AppConfig.serverApiUrl,
                      allDevices: devices, 
                    ),
                  ),
                );
                _loadDevices();
                break;
              case 'deactivate':
                await _deactivateDevice(deviceId);
                break;
              case 'activate':
                await _activateDevice(device);
                break;
            }
          },
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              // FIX 2: Pass the devices list (State variable)
              builder: (context) => DeviceConfigScreen(
                device: device,
                serverUrl: AppConfig.serverApiUrl,
                allDevices: devices,
              ),
            ),
          );
          _loadDevices();
        },
      ),
    );
  }

  String _formatTimeSince(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ago';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ago';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }

  Widget _buildAppearanceSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              title: Text('Dark Mode'),
              value: darkModeSwitchValue,
              onChanged: (value) {
                setState(() {
                  darkModeSwitchValue = value;
                  MyApp.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _saveSettings,
          icon: Icon(Icons.save),
          label: Text('Save Settings'),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.all(16),
          ),
        ),
        SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _clearAndReinitializeApp,
          icon: Icon(Icons.restart_alt, color: Colors.red),
          label: Text('Clear and Reinitialize App', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.all(16),
            side: BorderSide(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Future<void> _showHealthCheckDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _HealthCheckDialog(
        serverUrl: serverApiUrlController.text.trim(),
        devices: devices,
      ),
    );
  }

  Future<void> _testConnection() async {
    try {
      final url = serverApiUrlController.text.trim();
      final response = await http.get(
        Uri.parse('$url/api/health'),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Connection successful!');
      } else {
        _showErrorSnackBar('Connection failed: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Connection failed: $e');
    }
  }

  Future<void> _deactivateDevice(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deactivate Device'),
        content: Text('Are you sure you want to deactivate this device? Historical data will be preserved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await http.delete(
          Uri.parse('${AppConfig.serverApiUrl}api/devices/$deviceId'),
        );

        if (response.statusCode == 200) {
          _showSuccessSnackBar('Device deactivated');
          _loadDevices();
        } else {
          _showErrorSnackBar('Failed to deactivate device');
        }
      } catch (e) {
        _showErrorSnackBar('Error deactivating device: $e');
      }
    }
  }

  Future<void> _activateDevice(Map<String, dynamic> device) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.serverApiUrl}api/devices/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'device_id': device['device_id'],
          'device_type': device['device_type'],
          'device_name': device['device_name'] ?? device['device_id'],
          'location': device['location'] ?? '',
          'is_active': true,
        }),
      );

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Device activated');
        _loadDevices();
      } else {
        _showErrorSnackBar('Failed to activate device');
      }
    } catch (e) {
      _showErrorSnackBar('Error activating device: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      
      String serverUrl = serverApiUrlController.text.trim();
      if (!serverUrl.endsWith('/')) {
        serverUrl = '$serverUrl/';
      }
      
      prefs.setString('serverApiUrl', serverUrl);
      prefs.setBool('darkMode', darkModeSwitchValue);

      AppConfig.serverApiUrl = serverUrl;

      // Save device order if changed
      if (hasReordered) {
        await _saveDeviceOrder();
      }

      _showSuccessSnackBar('Settings saved successfully');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackBar('Error saving settings: $e');
    }
  }

  Future<void> _clearAndReinitializeApp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear All Data'),
        content: Text('This will clear all app data and restart the initial setup. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Clear and Restart'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      prefs.setBool('initialSetupComplete', false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MyApp()),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ============================================================================
// HEALTH CHECK DIALOG
// ============================================================================

class _HealthCheckDialog extends StatefulWidget {
  final String serverUrl;
  final List<Map<String, dynamic>> devices;

  const _HealthCheckDialog({
    required this.serverUrl,
    required this.devices,
  });

  @override
  _HealthCheckDialogState createState() => _HealthCheckDialogState();
}

class _HealthCheckDialogState extends State<_HealthCheckDialog> {
  bool _isChecking = true;
  Map<String, dynamic> _results = <String, dynamic>{};
  
  @override
  void initState() {
    super.initState();
    _runHealthCheck();
  }

  Future<void> _runHealthCheck() async {
    setState(() {
      _isChecking = true;
      _results = <String, dynamic>{};
    });

    Map<String, dynamic> results = <String, dynamic>{
      'server': <String, dynamic>{'status': 'checking', 'message': 'Connecting...', 'latency': null},
      'database': <String, dynamic>{'status': 'checking', 'message': 'Testing...', 'count': null},
      'devices': <String, dynamic>{},
    };

    setState(() => _results = results);

    // 1. Check Server Health
    await _checkServerHealth(results);
    
    // 2. Check Database
    await _checkDatabase(results);
    
    // 3. Check Each Device
    await _checkDevices(results);
    
    setState(() {
      _isChecking = false;
      _results = results;
    });
  }

  Future<void> _checkServerHealth(Map<String, dynamic> results) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final response = await http.get(
        Uri.parse('${widget.serverUrl}/api/health'),
      ).timeout(Duration(seconds: 5));
      
      stopwatch.stop();
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          results['server'] = <String, dynamic>{
            'status': 'online',
            'message': data['status'] ?? 'Server is healthy',
            'latency': stopwatch.elapsedMilliseconds,
            'version': data['version'],
            'uptime': data['uptime'],
          };
        });
      } else {
        setState(() {
          results['server'] = <String, dynamic>{
            'status': 'error',
            'message': 'HTTP ${response.statusCode}',
            'latency': stopwatch.elapsedMilliseconds,
          };
        });
      }
    } catch (e) {
      stopwatch.stop();
      setState(() {
        results['server'] = <String, dynamic>{
          'status': 'offline',
          'message': 'Connection failed: ${e.toString().split(':').first}',
          'latency': null,
        };
      });
    }
  }

  Future<void> _checkDatabase(Map<String, dynamic> results) async {
    if (results['server']?['status'] != 'online') {
      setState(() {
        results['database'] = <String, dynamic>{
          'status': 'skipped',
          'message': 'Server offline',
          'count': null,
        };
      });
      return;
    }

    try {
      // Check sensor data count
      final sensorResponse = await http.get(
        Uri.parse('${widget.serverUrl}/api/sensor_data?limit=1'),
      ).timeout(Duration(seconds: 5));
      
      // Check mode data count
      final modeResponse = await http.get(
        Uri.parse('${widget.serverUrl}/api/modes?limit=1'),
      ).timeout(Duration(seconds: 5));
      
      if (sensorResponse.statusCode == 200 && modeResponse.statusCode == 200) {
        final sensorData = json.decode(sensorResponse.body) as List;
        final modeData = json.decode(modeResponse.body) as List;
        
        setState(() {
          results['database'] = <String, dynamic>{
            'status': 'online',
            'message': 'Database accessible',
            'sensorReadings': sensorData.length > 0 ? 'Data available' : 'No data',
            'modeHistory': modeData.length > 0 ? 'Data available' : 'No data',
          };
        });
      } else {
        setState(() {
          results['database'] = <String, dynamic>{
            'status': 'error',
            'message': 'Database query failed',
            'count': null,
          };
        });
      }
    } catch (e) {
      setState(() {
        results['database'] = <String, dynamic>{
          'status': 'error',
          'message': 'Database error',
          'count': null,
        };
      });
    }
  }

  Future<void> _checkDevices(Map<String, dynamic> results) async {
    final activeDevices = widget.devices.where((d) => d['is_active'] == true).toList();
    
    // Initialize devices map properly
    final devicesMap = results['devices'] as Map<String, dynamic>;
    
    for (var device in activeDevices) {
      final deviceId = device['device_id'];
      final ipAddress = device['ip_address'];
      
      if (ipAddress == null || ipAddress.isEmpty) {
        setState(() {
          devicesMap[deviceId] = <String, dynamic>{
            'status': 'unknown',
            'message': 'No IP address',
            'name': device['device_name'] ?? deviceId,
            'type': device['device_type'],
          };
        });
        continue;
      }

      final apiUrl = 'http://$ipAddress:5001';
      final stopwatch = Stopwatch()..start();
      
      try {
        final response = await http.get(
          Uri.parse('$apiUrl/api/status'),
        ).timeout(Duration(seconds: 3));
        
        stopwatch.stop();
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          setState(() {
            devicesMap[deviceId] = <String, dynamic>{
              'status': 'online',
              'message': 'Responding',
              'latency': stopwatch.elapsedMilliseconds,
              'name': device['device_name'] ?? deviceId,
              'type': device['device_type'],
              'temperature': data['temperature'],
              'humidity': data['humidity'],
              'state': data['state'],
            };
          });
        } else {
          setState(() {
            devicesMap[deviceId] = <String, dynamic>{
              'status': 'error',
              'message': 'HTTP ${response.statusCode}',
              'latency': stopwatch.elapsedMilliseconds,
              'name': device['device_name'] ?? deviceId,
              'type': device['device_type'],
            };
          });
        }
      } catch (e) {
        stopwatch.stop();
        setState(() {
          devicesMap[deviceId] = <String, dynamic>{
            'status': 'offline',
            'message': 'Unreachable',
            'latency': null,
            'name': device['device_name'] ?? deviceId,
            'type': device['device_type'],
          };
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.red;
      case 'error':
        return Colors.orange;
      case 'checking':
        return Colors.blue;
      case 'skipped':
      case 'unknown':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'online':
        return Icons.check_circle;
      case 'offline':
        return Icons.cancel;
      case 'error':
        return Icons.error;
      case 'checking':
        return Icons.hourglass_empty;
      case 'skipped':
      case 'unknown':
        return Icons.help_outline;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverStatus = _results['server'] as Map<String, dynamic>?;
    final databaseStatus = _results['database'] as Map<String, dynamic>?;
    final deviceStatuses = (_results['devices'] as Map?) ?? <String, dynamic>{};

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.monitor_heart, size: 28),
          SizedBox(width: 12),
          Expanded(child: Text('Health Check')),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(maxHeight: 500),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Server Status
              _buildStatusCard(
                title: 'Server',
                status: serverStatus?['status'] ?? 'checking',
                message: serverStatus?['message'] ?? 'Checking...',
                details: serverStatus?['latency'] != null
                    ? 'Latency: ${serverStatus?['latency']}ms'
                    : null,
              ),
              SizedBox(height: 12),
              
              // Database Status
              _buildStatusCard(
                title: 'Database',
                status: databaseStatus?['status'] ?? 'checking',
                message: databaseStatus?['message'] ?? 'Checking...',
                details: databaseStatus?['sensorReadings'] != null
                    ? 'Sensor: ${databaseStatus?['sensorReadings']}\nModes: ${databaseStatus?['modeHistory']}'
                    : null,
              ),
              SizedBox(height: 12),
              
              // Devices Section
              Text(
                'Devices (${deviceStatuses.length})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              
              if (deviceStatuses.isEmpty && !_isChecking)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text('No active devices found'),
                    ),
                  ),
                )
              else
                ...deviceStatuses.entries.map((entry) {
                  final deviceData = entry.value as Map;
                  return _buildDeviceStatusCard(
                    name: deviceData['name']?.toString() ?? entry.key.toString(),
                    type: deviceData['type']?.toString() ?? 'Unknown',
                    status: deviceData['status']?.toString() ?? 'unknown',
                    message: deviceData['message']?.toString() ?? '',
                    latency: deviceData['latency'] as int?,
                    temperature: deviceData['temperature'] != null 
                        ? (deviceData['temperature'] as num).toDouble() 
                        : null,
                    humidity: deviceData['humidity'] != null 
                        ? (deviceData['humidity'] as num).toDouble() 
                        : null,
                    state: deviceData['state']?.toString(),
                  );
                }).toList(),
            ],
          ),
        ),
      ),
      actions: [
        if (_isChecking)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        TextButton.icon(
          onPressed: _isChecking ? null : _runHealthCheck,
          icon: Icon(Icons.refresh),
          label: Text('Re-check'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String status,
    required String message,
    String? details,
  }) {
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                    ),
                  ),
                  if (details != null) ...[
                    SizedBox(height: 4),
                    Text(
                      details,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusCard({
    required String name,
    required String type,
    required String status,
    required String message,
    int? latency,
    double? temperature,
    double? humidity,
    String? state,
  }) {
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '$type - $message',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                    ),
                  ),
                  if (status == 'online' && temperature != null) ...[
                    SizedBox(height: 4),
                    Text(
                      '${temperature.toStringAsFixed(1)}°F • ${humidity?.toStringAsFixed(0) ?? 'N/A'}% • $state',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  if (latency != null) ...[
                    SizedBox(height: 2),
                    Text(
                      'Latency: ${latency}ms',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}