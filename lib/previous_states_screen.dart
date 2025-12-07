import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreviousStatesScreen extends StatefulWidget {
  final String? selectedDeviceId;
  
  const PreviousStatesScreen({Key? key, this.selectedDeviceId}) : super(key: key);
  
  @override
  _PreviousStatesScreenState createState() => _PreviousStatesScreenState();
}

class _PreviousStatesScreenState extends State<PreviousStatesScreen> {
  List<Map<String, dynamic>> modeUpdates = [];
  Map<String, Map<String, dynamic>> deviceInfo = {};
  bool isRefreshing = false;
  late String serverApiUrl;
  String? selectedDeviceFilter;
  List<String> availableDevices = [];

  @override
  void initState() {
    super.initState();
    // Initialize filter from widget parameter if provided
    selectedDeviceFilter = widget.selectedDeviceId;
    _loadData();
  }

  @override
  void didUpdateWidget(PreviousStatesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update filter if the selectedDeviceId parameter changed
    if (widget.selectedDeviceId != oldWidget.selectedDeviceId) {
      setState(() {
        selectedDeviceFilter = widget.selectedDeviceId;
      });
    }
  }

  Future<void> _loadServerApiUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      serverApiUrl = prefs.getString('serverApiUrl') ?? '';
    });
  }

  Future<void> _loadData() async {
    await _loadServerApiUrl();
    await _loadDeviceInfo();
    await fetchModeUpdates();
  }

  Future<void> _loadDeviceInfo() async {
    if (serverApiUrl.isEmpty) return;

    try {
      final response = await http.get(Uri.parse('$serverApiUrl/api/devices'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final devices = data['devices'] as List;
        
        setState(() {
          deviceInfo = {
            for (var device in devices)
              device['device_id']: {
                'device_name': device['device_name'] ?? device['device_id'],
                'device_type': device['device_type'] ?? 'Unknown',
                'location': device['location'] ?? '',
              }
          };
        });
      }
    } catch (e) {
      print('Error loading device info: $e');
    }
  }

  Future<void> fetchModeUpdates() async {
    if (serverApiUrl.isEmpty) {
      return;
    }

    final url = Uri.parse('$serverApiUrl/api/modes');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          modeUpdates = data.cast<Map<String, dynamic>>();
          modeUpdates.forEach((update) {
            update['formattedTimestamp'] = _formatTimestamp(update['timestamp']);
          });

          // Extract unique devices for filter
          availableDevices = modeUpdates
              .map((d) => d['device_id'] as String)
              .toSet()
              .toList();
          availableDevices.sort();
        });
      } else {
        throw Exception('Failed to load mode updates');
      }
    } catch (error) {
      print('Error fetching mode updates: $error');
    }
  }

  String _formatTimestamp(String timestamp) {
    print('Received timestamp: $timestamp');
    try {
      // Input format: "Wed, 29 Oct 2025 21:02:25 GMT"
      
      // 1. Define the exact format string, escaping 'GMT' as a literal.
      final DateFormat inputFormat = DateFormat('EEE, dd MMM yyyy HH:mm:ss \'GMT\'');
      
      // 2. Parse the string, and explicitly set the parsed time to be UTC (isUtc: true).
      final DateTime utcDateTime = inputFormat.parse(timestamp, true); 
      
      // 3. Convert the UTC time to the user's local time.
      final DateTime localDateTime = utcDateTime.toLocal();
      
      // 4. Format the local time. (e.g., "October 29, 2025 5:02 PM")
      final DateFormat outputFormat = DateFormat.yMMMMd().add_jm();
      return outputFormat.format(localDateTime);
    } catch (e) {
      print('Error formatting timestamp: $e');
      print(timestamp);
      return 'Invalid Timestamp';
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      isRefreshing = true;
    });
    await _loadDeviceInfo();
    await fetchModeUpdates();
    setState(() {
      isRefreshing = false;
    });
  }

  List<Map<String, dynamic>> get filteredData {
    if (selectedDeviceFilter == null) {
      return modeUpdates;
    }
    return modeUpdates
        .where((d) => d['device_id'] == selectedDeviceFilter)
        .toList();
  }

  Color _getModeColor(String mode) {
    switch (mode.toLowerCase()) {
      case 'cooling':
        return Colors.blue;
      case 'heating':
        return Colors.orange;
      case 'emergency_heat':
        return Colors.red;
      case 'fan_only':
        return Colors.green;
      case 'sensor_failure':
        return Colors.deepPurple;
      case 'off':
      case 'between_states':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getModeIcon(String mode) {
    switch (mode.toLowerCase()) {
      case 'cooling':
        return Icons.ac_unit;
      case 'heating':
      case 'emergency_heat':
        return Icons.local_fire_department;
      case 'fan_only':
        return Icons.air;
      case 'sensor_failure':
        return Icons.sensors_off;
      case 'off':
      case 'between_states':
        return Icons.power_settings_new;
      default:
        return Icons.thermostat;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (availableDevices.length > 1)
            Padding(
              // Add right padding only to dropdown to avoid FAB
              padding: EdgeInsets.only(left: 8, right: 80, top: 8, bottom: 8),
              child: DropdownButtonFormField<String>(
                value: selectedDeviceFilter,
                decoration: InputDecoration(
                  labelText: 'Filter by Device',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text('All Devices'),
                  ),
                  ...availableDevices.map((device) {
                    final info = deviceInfo[device];
                    final displayName = info?['device_name'] ?? device;
                    return DropdownMenuItem(
                      value: device,
                      child: Text(displayName),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedDeviceFilter = value;
                  });
                },
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: filteredData.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No state history available'),
                          SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _refreshData,
                            child: Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredData.length,
                      itemBuilder: (context, index) {
                        final update = filteredData[index];
                        final deviceId = update['device_id'];
                        final mode = update['mode'].toString();
                        final formattedMode = mode.replaceAll('_', ' ');
                        final formattedTimestamp = update['formattedTimestamp'];

                        // Get device metadata
                        final info = deviceInfo[deviceId];
                        final deviceName = info?['device_name'] ?? deviceId;
                        final deviceType = info?['device_type'] ?? 'Unknown';
                        final location = info?['location'] ?? '';

                        final modeColor = _getModeColor(mode);
                        final modeIcon = _getModeIcon(mode);

                        IconData deviceIcon;
                        Color deviceIconColor;
                        
                        switch (deviceType) {
                          case 'Thermostat':
                            deviceIcon = Icons.thermostat;
                            deviceIconColor = Colors.orange;
                            break;
                          case 'HybridThermo':
                            deviceIcon = Icons.hub;
                            deviceIconColor = Colors.deepOrange;
                            break;
                          default:
                            deviceIcon = Icons.thermostat_outlined;
                            deviceIconColor = Colors.grey;
                        }

                        return Card(
                          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            leading: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(deviceIcon, color: deviceIconColor, size: 40),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: modeColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(modeIcon, size: 16, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              deviceName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (location.isNotEmpty)
                                  Text(
                                    location,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: modeColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        formattedMode.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: modeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  formattedTimestamp,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}