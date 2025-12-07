import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

Future<void> setUpInitialSettingsDialog(BuildContext context) async {
  TextEditingController serverApiUrlController = TextEditingController();
  List<Map<String, dynamic>> devices = [];
  bool isDarkMode = true;
  bool isSearching = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          String formatApiUrl(String apiUrl) {
            if (!(apiUrl.startsWith('http://') || apiUrl.startsWith('https://'))) {
              if (!apiUrl.contains(':')) {
                apiUrl = 'http://$apiUrl:5000';
              } else {
                apiUrl = 'http://$apiUrl';
              }
            }
            if (!apiUrl.endsWith('/')) {
              apiUrl = '$apiUrl/';
            }
            return apiUrl;
          }

          Future<void> fetchDevicesFromServer(String serverUrl) async {
            setState(() {
              isSearching = true;
              devices.clear();
            });

            try {
              serverUrl = formatApiUrl(serverUrl);
              
              // Test server connection first
              final healthResponse = await http.get(
                Uri.parse('${serverUrl}api/health')
              ).timeout(Duration(seconds: 5));
              
              if (healthResponse.statusCode != 200) {
                throw Exception('Server health check failed');
              }

              // Fetch registered devices
              final response = await http.get(
                Uri.parse('${serverUrl}api/devices')
              ).timeout(Duration(seconds: 10));
              
              if (response.statusCode == 200) {
                final data = json.decode(response.body);
                final List<dynamic> devicesList = data['devices'] ?? [];

                for (var device in devicesList) {
                  // Only include active devices
                  if (device['is_active'] != true) continue;

                  devices.add({
                    'device_id': device['device_id'] ?? '',
                    'device_type': device['device_type'] ?? 'Unknown',
                    'device_name': device['device_name'] ?? device['device_id'],
                    'location': device['location'] ?? '',
                    'ip_address': device['ip_address'] ?? '',
                  });
                }

                // Sort devices: Thermostats first, then probes
                devices.sort((a, b) {
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
                  return (a['device_name'] as String).compareTo(b['device_name'] as String);
                });

                setState(() {
                  isSearching = false;
                });
              } else {
                throw Exception('Failed to fetch devices: ${response.statusCode}');
              }
            } catch (e) {
              setState(() {
                isSearching = false;
              });
              _showError(context, 'Error: ${e.toString()}');
            }
          }

          return Theme(
            data: isDarkMode 
              ? ThemeData(
                  brightness: Brightness.dark,
                  primarySwatch: Colors.blue,
                )
              : ThemeData(
                  brightness: Brightness.light,
                  primarySwatch: Colors.blue,
                ),
            child: AlertDialog(
              title: Text('Welcome to Thermostat Controller'),
              content: SingleChildScrollView(
              child: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Let\'s get started by connecting to your server',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: serverApiUrlController,
                      decoration: InputDecoration(
                        labelText: 'Server IP Address/Hostname',
                        hintText: 'e.g., 192.168.1.100 or server.local',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.dns),
                      ),
                      enabled: !isSearching,
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: isSearching ? null : () async {
                        if (serverApiUrlController.text.trim().isEmpty) {
                          _showError(context, 'Please enter a server address');
                          return;
                        }
                        await fetchDevicesFromServer(serverApiUrlController.text.trim());
                      },
                      icon: isSearching 
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(Icons.search),
                      label: Text(isSearching ? 'Discovering...' : 'Discover Devices'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 48),
                      ),
                    ),
                    SizedBox(height: 24),
                    if (devices.isNotEmpty) ...[
                      Text(
                        'Found ${devices.length} device(s):',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Container(
                        constraints: BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: devices.length,
                          itemBuilder: (context, index) => _buildDeviceCard(devices[index]),
                        ),
                      ),
                    ] else if (!isSearching) ...[
                      Card(
                        color: Colors.blue[50],
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue, size: 32),
                              SizedBox(height: 8),
                              Text(
                                'No devices found yet',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Make sure your thermostats and probes are powered on. '
                                'They will automatically register with the server when they boot up.',
                                style: TextStyle(fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 16),
                    Divider(),
                    SizedBox(height: 8),
                    Text('Appearance:'),
                    SwitchListTile(
                      title: Text('Dark Mode'),
                      value: isDarkMode,
                      onChanged: (value) {
                        setState(() {
                          isDarkMode = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: devices.isEmpty
                    ? null
                    : () async {
                        await saveInitialSettings(
                          serverApiUrlController.text.trim(),
                          devices,
                          isDarkMode,
                        );
                        Navigator.pop(context);
                      },
                child: Text('Continue'),
              ),
            ],
            ),
          );
        },
      );
    },
  );
}

Widget _buildDeviceCard(Map<String, dynamic> device) {
  IconData icon;
  Color iconColor;
  
  switch (device['device_type']) {
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
    margin: EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(icon, color: iconColor, size: 32),
      title: Text(
        device['device_name'],
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type: ${device['device_type']}'),
          if (device['location'].isNotEmpty)
            Text('Location: ${device['location']}'),
        ],
      ),
      dense: true,
    ),
  );
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      duration: Duration(seconds: 3),
    ),
  );
}

Future<void> saveInitialSettings(
  String serverApiUrl,
  List<Map<String, dynamic>> devices,
  bool isDarkMode,
) async {
  try {
    serverApiUrl = serverApiUrl.trim();
    if (!(serverApiUrl.startsWith('http://') || serverApiUrl.startsWith('https://'))) {
      if (!serverApiUrl.contains(':')) {
        serverApiUrl = 'http://$serverApiUrl:5000';
      } else {
        serverApiUrl = 'http://$serverApiUrl';
      }
    }
    if (!serverApiUrl.endsWith('/')) {
      serverApiUrl = '$serverApiUrl/';
    }

    AppConfig.serverApiUrl = serverApiUrl;
    AppConfig.numberOfSensors = devices.length;

    // Store device info for backward compatibility with existing code
    AppConfig.apiUrlList = devices.map<String>((device) {
      final ip = device['ip_address'] ?? '';
      return ip.isNotEmpty ? 'http://$ip:5001' : '';
    }).toList();
    AppConfig.displayNameList = devices.map<String>((device) => device['device_name'] ?? '').toList();
    AppConfig.deviceTypeList = devices.map<String>((device) => device['device_type'] ?? 'Unknown').toList();
    AppConfig.deviceLocationList = devices.map<String>((device) => device['location'] ?? '').toList();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool('initialSetupComplete', true);
    prefs.setString('serverApiUrl', AppConfig.serverApiUrl);
    prefs.setInt('numberOfSensors', AppConfig.numberOfSensors);
    prefs.setBool('darkMode', isDarkMode);

    for (int index = 0; index < AppConfig.numberOfSensors; index++) {
      prefs.setString('apiUrl$index', AppConfig.apiUrlList[index]);
      prefs.setString('displayName$index', AppConfig.displayNameList[index]);
      prefs.setString('deviceType$index', AppConfig.deviceTypeList[index]);
      prefs.setString('deviceLocation$index', AppConfig.deviceLocationList[index]);
    }

    // Set theme mode
    MyApp.setThemeMode(isDarkMode ? ThemeMode.dark : ThemeMode.light);

    print('Initial setup saved successfully');
    print('Server: $serverApiUrl');
    print('Devices: ${devices.length}');
  } catch (e) {
    print('Error saving initial settings: $e');
  }
}