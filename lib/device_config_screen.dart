import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DeviceConfigScreen extends StatefulWidget {
  final Map<String, dynamic> device;
  final String serverUrl;
  // **NEW: List of all devices for local duplicate name checking**
  final List<Map<String, dynamic>> allDevices; 

  const DeviceConfigScreen({
    Key? key,
    required this.device,
    required this.serverUrl,
    required this.allDevices, // **NEW REQUIRED FIELD**
  }) : super(key: key);

  @override
  _DeviceConfigScreenState createState() => _DeviceConfigScreenState();
}

class _DeviceConfigScreenState extends State<DeviceConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _deviceNameController;
  late TextEditingController _locationController;
  
  late String _originalDeviceName;
  late final String _currentDeviceId; // Holds the unique ID of the device being configured
  
  // Thermostat-specific configuration
  Map<String, dynamic>? thermostatConfig;
  bool isLoadingConfig = true;
  
  late TextEditingController _coolingOffsetController;
  late TextEditingController _heatingOffsetController;
  late TextEditingController _tempThresholdController;
  // REMOVED: _maxSafeTempController - MaxSafeTemperature is deprecated
  late TextEditingController _compressorMinOffController;
  late TextEditingController _emergencyHeatDelayController;
  late TextEditingController _sensorPollIntervalController;
  late TextEditingController _defaultTempController;

  @override
  void initState() {
    super.initState();
    _originalDeviceName = widget.device['device_name'] ?? widget.device['device_id'];
    _currentDeviceId = widget.device['device_id'] as String; // Initialized here
    
    _deviceNameController = TextEditingController(text: _originalDeviceName);
    _locationController = TextEditingController(
      text: widget.device['location'] ?? ''
    );
    
    _coolingOffsetController = TextEditingController();
    _heatingOffsetController = TextEditingController();
    _tempThresholdController = TextEditingController();
    // REMOVED: _maxSafeTempController initialization - deprecated
    _compressorMinOffController = TextEditingController();
    _emergencyHeatDelayController = TextEditingController();
    _sensorPollIntervalController = TextEditingController();
    _defaultTempController = TextEditingController();
    
    if (_isThermostat()) {
      _loadThermostatConfig();
    } else {
      isLoadingConfig = false;
    }
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _locationController.dispose();
    _coolingOffsetController.dispose();
    _heatingOffsetController.dispose();
    _tempThresholdController.dispose();
    // REMOVED: _maxSafeTempController.dispose() - deprecated
    _compressorMinOffController.dispose();
    _emergencyHeatDelayController.dispose();
    _sensorPollIntervalController.dispose();
    _defaultTempController.dispose();
    super.dispose();
  }

  bool _isThermostat() {
    final type = widget.device['device_type'];
    return type == 'Thermostat' || type == 'HybridThermo';
  }

  // **NEW: Synchronous function to check for duplicate names locally**
  bool _isNameDuplicate(String newName) {
    // If the name hasn't changed, no need to check for duplicates
    if (newName.trim().toLowerCase() == _originalDeviceName.toLowerCase()) {
      return false;
    }

    // Use the list provided by the parent widget for checking
    for (var device in widget.allDevices) {
      // Skip the current device being edited
      if (device['device_id'] != _currentDeviceId) {
        final existingName = device['device_name']?.toString() ?? '';
        
        // Check for case-insensitive match
        if (existingName.trim().toLowerCase() == newName.trim().toLowerCase()) {
          return true; // Duplicate found!
        }
      }
    }
    
    return false; // No duplicate found
  }

  Future<void> _loadThermostatConfig() async {
    if (widget.device['ip_address'] == null || widget.device['ip_address'].isEmpty) {
      setState(() {
        isLoadingConfig = false;
      });
      _showErrorSnackBar('Device IP address not available - cannot load configuration');
      return;
    }

    setState(() {
      isLoadingConfig = true;
    });

    try {
      final deviceApiUrl = 'http://${widget.device['ip_address']}:5001';
      final response = await http.get(
        Uri.parse('$deviceApiUrl/api/config'),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final config = json.decode(response.body);
        setState(() {
          thermostatConfig = config;
          _coolingOffsetController.text = (config['cooling_offset'] ?? 0.5).toString();
          _heatingOffsetController.text = (config['heating_offset'] ?? 0.5).toString();
          _tempThresholdController.text = (config['temperature_threshold'] ?? 1.3).toString();
          // REMOVED: max_safe_temperature loading - deprecated
          _compressorMinOffController.text = (config['compressor_min_off_minutes'] ?? 3).toString();
          _emergencyHeatDelayController.text = (config['emergency_heat_delay_seconds'] ?? 1800).toString();
          _sensorPollIntervalController.text = (config['sensor_poll_interval_seconds'] ?? 10).toString();
          _defaultTempController.text = (config['default_user_set_temperature'] ?? 72.0).toString();
          isLoadingConfig = false;
        });
        _showSuccessSnackBar('Configuration loaded successfully');
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading thermostat config: $e');
      setState(() {
        isLoadingConfig = false;
      });
      _showErrorSnackBar('Failed to load configuration: $e');
    }
  }

  Future<void> _saveBasicInfo() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final newName = _deviceNameController.text.trim();
    final newLocation = _locationController.text.trim();
    final oldDeviceId = widget.device['device_id'];
    
    // Check if name changed
    final nameChanged = newName != _originalDeviceName;
    
    if (nameChanged) {
      
      // *** NEW DUPLICATE NAME CHECK INTEGRATION - NOW LOCAL ***
      if (_isNameDuplicate(newName)) {
        _showErrorSnackBar('The name "$newName" is already in use by another device. Please choose a different name.');
        return; // STOP: Do not proceed with the server update
      }
      // ***************************************************

      // Name changed - send to device only
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Name Change'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You are about to change the device name from:'),
              SizedBox(height: 8),
              Text(
                '"$_originalDeviceName"',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('to:'),
              SizedBox(height: 4),
              Text(
                '"$newName"',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              SizedBox(height: 12),
              Text(
                'This will update:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('• Device configuration'),
              Text('• Server database records'),
              Text('• All historical data associations'),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This cannot be undone',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: Text('Confirm'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Updating device name...'),
              SizedBox(height: 8),
              Text(
                'The device will update itself and notify the server',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

      try {
        if (widget.device['ip_address'] == null || widget.device['ip_address'].isEmpty) {
          Navigator.pop(context); // Close loading dialog
          _showErrorSnackBar('Device IP address not available');
          return;
        }

        // Send name change request to device
        final deviceApiUrl = 'http://${widget.device['ip_address']}:5001';
        final deviceResponse = await http.post(
          Uri.parse('$deviceApiUrl/api/deviceid'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'device_id': newName}),
        ).timeout(Duration(seconds: 10));

        Navigator.pop(context); // Close loading dialog

        if (deviceResponse.statusCode == 200) {
          final result = json.decode(deviceResponse.body);
          final localUpdate = result['local_update'] ?? false;
          final serverMigration = result['server_migration'] ?? false;
          final serverError = result['server_error'];
          final tablesUpdated = result['tables_updated'] ?? 0;

          _originalDeviceName = newName;

          // Show detailed results
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(
                    localUpdate && serverMigration ? Icons.check_circle : Icons.warning,
                    color: localUpdate && serverMigration ? Colors.green : Colors.orange,
                  ),
                  SizedBox(width: 8),
                  Text(localUpdate && serverMigration ? 'Success' : 'Partial Update'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (localUpdate && serverMigration) ...[
                    Text('Device name successfully updated to:'),
                    SizedBox(height: 8),
                    Text(
                      newName,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 16),
                    if (tablesUpdated > 0)
                      Text(
                        'Updated $tablesUpdated database table${tablesUpdated != 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                  ] else ...[
                    Text(
                      'Name update completed with warnings:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                  ],
                  
                  // Device update status
                  Row(
                    children: [
                      Icon(
                        localUpdate ? Icons.check_circle : Icons.error,
                        color: localUpdate ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Device Configuration',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            Text(
                              localUpdate ? 'Updated successfully' : 'Failed to update',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  
                  // Server migration status
                  Row(
                    children: [
                      Icon(
                        serverMigration ? Icons.check_circle : Icons.error,
                        color: serverMigration ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Server Database Migration',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            Text(
                              serverMigration 
                                  ? 'All tables updated'
                                  : 'Migration failed',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  if (serverError != null) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Server error: $serverError',
                        style: TextStyle(fontSize: 11, color: Colors.red[900]),
                      ),
                    ),
                  ],
                  
                  if (!serverMigration && localUpdate) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Device updated locally. The device will retry server migration on next heartbeat.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK'),
                ),
              ],
            ),
          );
          
          // Update location if it also changed
          if (newLocation != widget.device['location']) {
            await _updateLocationOnly(newName, newLocation);
          }
          
        } else {
          _showErrorSnackBar('Device returned status: ${deviceResponse.statusCode}');
        }
      } catch (e) {
        Navigator.pop(context); // Close loading dialog
        _showErrorSnackBar('Error communicating with device: $e');
      }
    } else {
      // Name didn't change, just update location if needed
      if (newLocation != widget.device['location']) {
        await _updateLocationOnly(oldDeviceId, newLocation);
      } else {
        _showSuccessSnackBar('No changes to save');
      }
    }
  }

  Future<void> _updateLocationOnly(String deviceId, String location) async {
    try {
      final response = await http.put(
        Uri.parse('${widget.serverUrl}api/devices/$deviceId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'device_type': widget.device['device_type'],
          'device_name': deviceId,
          'location': location,
        }),
      );

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Location updated successfully');
      } else {
        _showErrorSnackBar('Failed to update location');
      }
    } catch (e) {
      _showErrorSnackBar('Error updating location: $e');
    }
  }

  Future<void> _saveThermostatConfig() async {
    if (widget.device['ip_address'] == null || widget.device['ip_address'].isEmpty) {
      _showErrorSnackBar('Device IP address not available');
      return;
    }

    try {
      final deviceApiUrl = 'http://${widget.device['ip_address']}:5001';
      final configUpdates = {
        'cooling_offset': double.tryParse(_coolingOffsetController.text) ?? 0.5,
        'heating_offset': double.tryParse(_heatingOffsetController.text) ?? 0.5,
        'temperature_threshold': double.tryParse(_tempThresholdController.text) ?? 1.3,
        // REMOVED: max_safe_temperature - deprecated and no longer enforced
        'compressor_min_off_minutes': int.tryParse(_compressorMinOffController.text) ?? 3,
        'emergency_heat_delay_seconds': int.tryParse(_emergencyHeatDelayController.text) ?? 1800,
        'sensor_poll_interval_seconds': int.tryParse(_sensorPollIntervalController.text) ?? 10,
        'default_user_set_temperature': double.tryParse(_defaultTempController.text) ?? 72.0,
      };

      final response = await http.post(
        Uri.parse('$deviceApiUrl/api/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(configUpdates),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Thermostat configuration saved successfully');
      } else {
        _showErrorSnackBar('Failed to save thermostat configuration');
      }
    } catch (e) {
      _showErrorSnackBar('Error saving configuration: $e');
    }
  }

  void _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset to Defaults'),
        content: Text('This will reset all thermostat settings to their default values. Are you sure?'),
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
      setState(() {
        _coolingOffsetController.text = '0.5';
        _heatingOffsetController.text = '0.5';
        _tempThresholdController.text = '1.3';
        // REMOVED: max_safe_temperature reset - deprecated
        _compressorMinOffController.text = '3';
        _emergencyHeatDelayController.text = '1800';
        _sensorPollIntervalController.text = '10';
        _defaultTempController.text = '72.0';
      });
      _showSuccessSnackBar('Values reset to defaults (not saved yet)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configure Device'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: () async {
              await _saveBasicInfo();
              if (_isThermostat() && !isLoadingConfig) {
                await _saveThermostatConfig();
              }
            },
          ),
        ],
      ),
      body: isLoadingConfig
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBasicInfoSection(),
                    if (_isThermostat()) ...[
                      SizedBox(height: 24),
                      Divider(),
                      SizedBox(height: 24),
                      _buildThermostatConfigSection(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBasicInfoSection() {
    IconData icon;
    Color iconColor;
    
    switch (widget.device['device_type']) {
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

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 48, color: iconColor),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Basic Information',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Device ID: ${widget.device['device_id']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'Type: ${widget.device['device_type']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextFormField(
              controller: _deviceNameController,
              decoration: InputDecoration(
                labelText: 'Device Name',
                hintText: 'e.g., Living Room Thermostat',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
                helperText: 'Changing this will update the device ID everywhere',
                helperMaxLines: 2,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a device name';
                }
                if (value.trim().length < 3) {
                  return 'Name must be at least 3 characters';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: 'Location',
                hintText: 'e.g., Second Floor, Master Bedroom',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
            if (widget.device['ip_address'] != null && widget.device['ip_address'].isNotEmpty) ...[
              SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.network_check, color: Colors.green),
                title: Text('IP Address'),
                subtitle: Text(widget.device['ip_address']),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThermostatConfigSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thermostat Configuration',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Advanced settings for temperature control',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (thermostatConfig != null) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Configuration loaded from device. Edit values below and tap Save.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 16),
            
            // Temperature Settings
            ExpansionTile(
              title: Text('Temperature Settings'),
              leading: Icon(Icons.thermostat, color: Colors.orange),
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _coolingOffsetController,
                        decoration: InputDecoration(
                          labelText: 'Cooling Offset (°F)',
                          helperText: 'Temperature drop before stopping cooling',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _heatingOffsetController,
                        decoration: InputDecoration(
                          labelText: 'Heating Offset (°F)',
                          helperText: 'Temperature rise before stopping heating',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _tempThresholdController,
                        decoration: InputDecoration(
                          labelText: 'Temperature Threshold (°F)',
                          helperText: 'Difference needed to trigger heating/cooling',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                      SizedBox(height: 12),
                      // REMOVED: Max Safe Temperature field - deprecated feature
                      // This setting is no longer enforced to prevent AC shutdown on hot days
                      TextFormField(
                        controller: _defaultTempController,
                        decoration: InputDecoration(
                          labelText: 'Default Set Temperature (°F)',
                          helperText: 'Initial temperature on startup',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Timing Settings
            ExpansionTile(
              title: Text('Timing Settings'),
              leading: Icon(Icons.timer, color: Colors.blue),
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _compressorMinOffController,
                        decoration: InputDecoration(
                          labelText: 'Compressor Min Off Time (minutes)',
                          helperText: 'Minimum time between compressor cycles',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _emergencyHeatDelayController,
                        decoration: InputDecoration(
                          labelText: 'Emergency Heat Delay (seconds)',
                          helperText: 'Time before activating emergency heat',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _sensorPollIntervalController,
                        decoration: InputDecoration(
                          labelText: 'Sensor Poll Interval (seconds)',
                          helperText: 'How often to read temperature sensor',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loadThermostatConfig,
                    icon: Icon(Icons.refresh),
                    label: Text('Reload Configuration'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 48),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetToDefaults,
                    icon: Icon(Icons.restore),
                    label: Text('Reset to Defaults'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(double.infinity, 48),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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