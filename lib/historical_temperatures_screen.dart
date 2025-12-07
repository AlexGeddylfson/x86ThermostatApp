import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

class HistoricalTemperaturesScreen extends StatefulWidget {
  final String? selectedDeviceId;
  
  const HistoricalTemperaturesScreen({Key? key, this.selectedDeviceId}) : super(key: key);
  
  @override
  _HistoricalTemperaturesScreenState createState() => _HistoricalTemperaturesScreenState();
}

class _HistoricalTemperaturesScreenState extends State<HistoricalTemperaturesScreen> {
  List<Map<String, dynamic>> temperatureData = [];
  Map<String, Map<String, dynamic>> deviceInfo = {};
  bool isRefreshing = false;
  bool isLoadingData = false;
  late String serverApiUrl;
  String? selectedDeviceFilter;
  List<String> availableDevices = [];
  String selectedTimeRange = '24h';
  
  final Map<String, Color> deviceColors = {};
  final List<Color> colorPalette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.indigo,
    Colors.lime,
  ];

  @override
  void initState() {
    super.initState();
    selectedDeviceFilter = widget.selectedDeviceId;
    _loadData();
  }

  @override
  void didUpdateWidget(HistoricalTemperaturesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    await fetchTemperatureData();
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

  Future<void> fetchTemperatureData() async {
    if (serverApiUrl.isEmpty) {
      return;
    }

    setState(() {
      isLoadingData = true;
    });

    // Calculate hours based on selected time range
    int hours;
    switch (selectedTimeRange) {
      case '24h':
        hours = 24;
        break;
      case '7d':
        hours = 24 * 7;
        break;
      case '30d':
        hours = 24 * 30;
        break;
      default:
        hours = 24;
    }

    final url = Uri.parse('$serverApiUrl/api/sensor_data?hours=$hours');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          temperatureData = data.cast<Map<String, dynamic>>();
          temperatureData.forEach((data) {
            data['formattedTimestamp'] = _formatTimestamp(data['timestamp']);
          });

          availableDevices = temperatureData
              .map((d) => d['device_id'] as String)
              .toSet()
              .toList();
          availableDevices.sort();
          
          _assignDeviceColors();
          isLoadingData = false;
        });
      } else {
        throw Exception('Failed to load temperature data');
      }
    } catch (error) {
      print('Error fetching temperature data: $error');
      setState(() {
        isLoadingData = false;
      });
    }
  }
  
  void _assignDeviceColors() {
    deviceColors.clear();
    for (int i = 0; i < availableDevices.length; i++) {
      deviceColors[availableDevices[i]] = colorPalette[i % colorPalette.length];
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final DateFormat inputFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
      final DateTime dateTime = inputFormat.parse(timestamp, true).toUtc();
      final DateTime localDateTime = dateTime.toLocal();
      final DateFormat outputFormat = DateFormat.yMMMMd().add_jm();
      return outputFormat.format(localDateTime);
    } catch (e) {
      print('Error formatting timestamp: $e');
      return 'Invalid Timestamp';
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      isRefreshing = true;
    });
    await _loadDeviceInfo();
    await fetchTemperatureData();
    setState(() {
      isRefreshing = false;
    });
  }

  List<Map<String, dynamic>> get filteredData {
    // Filter by device if selected
    if (selectedDeviceFilter == null) {
      return temperatureData;
    }
    return temperatureData
        .where((d) => d['device_id'] == selectedDeviceFilter)
        .toList();
  }

  Widget _buildTimeButton(String timeRange) {
    final isSelected = selectedTimeRange == timeRange;
    return InkWell(
      onTap: isLoadingData ? null : () {
        setState(() {
          selectedTimeRange = timeRange;
        });
        fetchTemperatureData(); // Fetch new data for the selected range
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : (isLoadingData ? Colors.grey[300] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          timeRange,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  Widget _buildTemperatureChart() {
    if (isLoadingData) {
      return Container(
        height: 250,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading data...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (temperatureData.isEmpty) {
      return Container(
        height: 250,
        child: Center(
          child: Text(
            'No data to display',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    Map<String, List<FlSpot>> deviceSpots = {};
    Map<String, List<DateTime>> deviceTimestamps = {};
    DateTime now = DateTime.now();
    
    DateTime startTime;
    switch (selectedTimeRange) {
      case '24h':
        startTime = now.subtract(Duration(hours: 24));
        break;
      case '7d':
        startTime = now.subtract(Duration(days: 7));
        break;
      case '30d':
        startTime = now.subtract(Duration(days: 30));
        break;
      default:
        startTime = now.subtract(Duration(hours: 24));
    }
    
    for (var data in filteredData) {
      try {
        final DateFormat inputFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
        final DateTime timestamp = inputFormat.parse(data['timestamp'], true).toUtc();
        final double temperature = (data['temperature'] as num).toDouble();
        final String deviceId = data['device_id'];
        
        if (!deviceSpots.containsKey(deviceId)) {
          deviceSpots[deviceId] = [];
          deviceTimestamps[deviceId] = [];
        }
        
        final double x = timestamp.difference(startTime).inMinutes.toDouble();
        deviceSpots[deviceId]!.add(FlSpot(x, temperature));
        deviceTimestamps[deviceId]!.add(timestamp);
      } catch (e) {
        print('Error processing data point: $e');
      }
    }
    
    DateTime earliestTime = startTime;
    DateTime latestTime = now;
    
    if (deviceSpots.isEmpty) {
      return Container(
        height: 250,
        child: Center(
          child: Text(
            'No data available for selected time range',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    deviceSpots.forEach((key, spots) {
      spots.sort((a, b) => a.x.compareTo(b.x));
    });
    
    double minTemp = double.infinity;
    double maxTemp = double.negativeInfinity;
    
    deviceSpots.values.forEach((spots) {
      spots.forEach((spot) {
        if (spot.y < minTemp) minTemp = spot.y;
        if (spot.y > maxTemp) maxTemp = spot.y;
      });
    });
    
    double tempRange = maxTemp - minTemp;
    minTemp -= tempRange * 0.1;
    maxTemp += tempRange * 0.1;
    
    List<LineChartBarData> lineBarsData = [];
    
    deviceSpots.forEach((deviceId, spots) {
      if (spots.isNotEmpty) {
        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: deviceColors[deviceId] ?? Colors.grey,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: spots.length < 50),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    });
    
    String getTimeLabel(double minutes) {
      final time = startTime.add(Duration(minutes: minutes.toInt()));
      switch (selectedTimeRange) {
        case '24h':
          return DateFormat('HH:mm').format(time);
        case '7d':
          return DateFormat('MM/dd').format(time);
        case '30d':
          return DateFormat('MM/dd').format(time);
        default:
          return DateFormat('HH:mm').format(time);
      }
    }
    
    double getInterval() {
      final totalMinutes = latestTime.difference(earliestTime).inMinutes.toDouble();
      return totalMinutes / 5;
    }
    
    double maxX = latestTime.difference(earliestTime).inMinutes.toDouble();
    
    return Container(
      height: 250,
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Temperature History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTimeButton('24h'),
                  SizedBox(width: 4),
                  _buildTimeButton('7d'),
                  SizedBox(width: 4),
                  _buildTimeButton('30d'),
                ],
              ),
            ],
          ),
          SizedBox(height: 8),
          if (selectedDeviceFilter == null && deviceSpots.length > 1)
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: deviceSpots.keys.map((deviceId) {
                final info = deviceInfo[deviceId];
                final deviceName = info?['device_name'] ?? deviceId;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: deviceColors[deviceId],
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      deviceName,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                );
              }).toList(),
            ),
          if (selectedDeviceFilter == null && deviceSpots.length > 1)
            SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: (maxTemp - minTemp) / 5,
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toStringAsFixed(0)}°F',
                          style: TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: getInterval(),
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            getTimeLabel(value),
                            style: TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                minX: 0,
                maxX: maxX,
                minY: minTemp,
                maxY: maxTemp,
                lineBarsData: lineBarsData,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final deviceId = deviceSpots.keys.elementAt(
                          lineBarsData.indexWhere((bar) => bar.spots == spot.bar.spots)
                        );
                        final info = deviceInfo[deviceId];
                        final deviceName = info?['device_name'] ?? deviceId;
                        return LineTooltipItem(
                          '$deviceName\n${spot.y.toStringAsFixed(1)}°F',
                          TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (availableDevices.length > 1)
            Padding(
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
          _buildTemperatureChart(),
          Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: filteredData.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thermostat_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No temperature data available'),
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
                        final data = filteredData[index];
                        final deviceId = data['device_id'];
                        final temperature = data['temperature'].toString();
                        final humidity = data['humidity']?.toString() ?? 'N/A';
                        final formattedTimestamp = data['formattedTimestamp'];

                        final info = deviceInfo[deviceId];
                        final deviceName = info?['device_name'] ?? deviceId;
                        final deviceType = info?['device_type'] ?? 'Unknown';
                        final location = info?['location'] ?? '';

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

                        return Card(
                          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            leading: Icon(icon, color: iconColor, size: 32),
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
                                Text(
                                  '$temperature°F  •  $humidity% humidity',
                                  style: TextStyle(fontSize: 14),
                                ),
                                Text(
                                  formattedTimestamp,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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