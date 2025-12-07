// UPDATED main.dart with Phase 6 integration

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // For ScrollDirection
import 'package:http/http.dart' as http;
import 'services/database_helper.dart';
import 'services/sync_manager.dart';

// --- Existing App Code (Preserved & Updated) ---

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // Imported for Timer

import 'initial_setup.dart';
import 'settings.dart';
import 'historical_temperatures_screen.dart';
import 'previous_states_screen.dart';
///import 'ai_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  static ThemeMode currentThemeMode = ThemeMode.dark;
  static Function(ThemeMode)? onThemeModeChanged;

  static void setThemeMode(ThemeMode mode) {
    currentThemeMode = mode;
    if (onThemeModeChanged != null) {
      onThemeModeChanged!(mode);
    }
  }

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    MyApp.onThemeModeChanged = (mode) {
      if (mounted) {  // Check if widget is still mounted
        setState(() {
          MyApp.currentThemeMode = mode;
        });
      }
    };
    _loadSavedThemeModeIfNeeded();
  }

  Future<void> _loadSavedThemeModeIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final setupComplete = prefs.getBool('initialSetupComplete') ?? false;
    
    // Only load saved theme if initial setup is complete
    // Otherwise, the initial setup dialog will set it
    if (setupComplete) {
      final savedDarkMode = prefs.getBool('darkMode') ?? true; // Default to dark mode
      if (mounted) {  // Check if widget is still mounted
        setState(() {
          MyApp.currentThemeMode = savedDarkMode ? ThemeMode.dark : ThemeMode.light;
        });
      }
    }
  }

  @override
  void dispose() {
    MyApp.onThemeModeChanged = null;  // Clear the callback to prevent leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
      ),
      themeMode: MyApp.currentThemeMode,
      home: FutureBuilder<bool>(
        future: checkInitialSetupComplete(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else {
            if (snapshot.data == true) {
              return HomePage();
            } else {
              return InitialSetupPage();
            }
          }
        },
      ),
    );
  }

  Future<bool> checkInitialSetupComplete() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('initialSetupComplete') ?? false;
  }
}

class InitialSetupPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await setUpInitialSettingsDialog(context);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    });

    return Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class AppConfig {
  static String serverApiUrl = '';
  static int numberOfSensors = 0;
  static String deviceId = ""; 
  static List<String> apiUrlList = [];
  static List<String> displayNameList = [];
  static List<String> deviceTypeList = []; // New: track device types
  static List<String> deviceLocationList = []; // New: track locations

  static Future<void> initializeApiUrlList() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    numberOfSensors = prefs.getInt('numberOfSensors') ?? 0;
    serverApiUrl = prefs.getString('serverApiUrl') ?? '';

    apiUrlList = List.generate(
      numberOfSensors,
      (index) => prefs.getString('apiUrl$index') ?? '',
    );

    displayNameList = List.generate(
      numberOfSensors,
      (index) => prefs.getString('displayName$index') ?? 'Sensor $index',
    );

    deviceTypeList = List.generate(
      numberOfSensors,
      (index) => prefs.getString('deviceType$index') ?? 'Unknown',
    );

    deviceLocationList = List.generate(
      numberOfSensors,
      (index) => prefs.getString('deviceLocation$index') ?? '',
    );
  }

  static Future<void> sendNameUpdate(int index, String newName) async {
    if (index >= apiUrlList.length) return;

try {
  final apiUrl = apiUrlList[index];
  final response = await http.post(
    Uri.parse('$apiUrl/api/deviceid'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'device_id': newName}),
  );

  if (response.statusCode == 200) {
    print('Device ID sent successfully!');
  } else {
    print('Server responded with ${response.statusCode}');
  }
} catch (e) {
  print('Error sending device id: $e');
}}

  // New: Fetch devices from server with type information
  static Future<List<Map<String, dynamic>>> fetchDevicesFromServer() async {
    if (serverApiUrl.isEmpty) return [];

    try {
      final response = await http.get(Uri.parse('$serverApiUrl/api/devices'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['devices'] != null) {
          return List<Map<String, dynamic>>.from(data['devices']);
        }
      }
    } catch (e) {
      print('Error fetching devices from server: $e');
    }
    return [];
  }

  // New: Get devices by type
  static Future<List<Map<String, dynamic>>> fetchDevicesByType(String type) async {
    if (serverApiUrl.isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse('$serverApiUrl/api/devices/by-type/$type')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['devices'] != null) {
          return List<Map<String, dynamic>>.from(data['devices']);
        }
      }
    } catch (e) {
      print('Error fetching devices by type: $e');
    }
    return [];
  }
}

// MODIFIED: DeviceData must be mutable for in-place updates
class DeviceData {
  final String deviceId;
  final String deviceType;
  final String displayName;
  final String location;
  final String apiUrl;
  // Make properties that change at runtime nullable and non-final
  double? temperature;
  double? humidity;
  double? setTemperature;
  String? currentState;
  bool emergencyStop;
  bool fanMode;
  int cooldownRemainingSeconds;
  int estimatedTimeToTargetSeconds;

  DeviceData({
    required this.deviceId,
    required this.deviceType,
    required this.displayName,
    required this.location,
    required this.apiUrl,
    this.temperature,
    this.humidity,
    this.setTemperature,
    this.currentState,
    this.emergencyStop = false,
    this.fanMode = false,
    this.cooldownRemainingSeconds = 0,
    this.estimatedTimeToTargetSeconds = 0,
  });

  bool get isThermostat => 
    deviceType == 'Thermostat' || deviceType == 'HybridThermo';
  
  bool get isProbe => 
    deviceType == 'Probe' || deviceType == 'HybridProbe';

  // NEW: Update method for in-place modification
  void updateData({
    required double? temperature,
    required double? humidity,
    required double? setTemperature,
    required String? currentState,
    required bool emergencyStop,
    required bool fanMode,
    required int cooldownRemainingSeconds,
    required int estimatedTimeToTargetSeconds,
  }) {
    this.temperature = temperature;
    this.humidity = humidity;
    this.setTemperature = setTemperature;
    this.currentState = currentState;
    this.emergencyStop = emergencyStop;
    this.fanMode = fanMode;
    this.cooldownRemainingSeconds = cooldownRemainingSeconds;
    this.estimatedTimeToTargetSeconds = estimatedTimeToTargetSeconds;
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SyncManager _syncManager = SyncManager.instance;
  
  late TabController _tabController;
  List<DeviceData> devices = [];
  bool isLoading = true;
  Timer? _refreshTimer;
  // Map to hold GlobalKeys for active DeviceCardStates
  final Map<String, GlobalKey<_DeviceCardState>> _cardKeys = {};

  // Constants for the aspect ratios (used in landscape mode)
  // With responsive UI scaling, we can use more balanced ratios
  static const double kThermostatAspectRatio = 1.5;   // Balanced for thermostat controls
  static const double kProbeAspectRatio = 2.5;        // Wider for compact probes
  
  // Track scroll position to hide/show bottom nav
  bool _showBottomNav = true; // Start visible, hide after 5 seconds
  ScrollController? _scrollController;
  Timer? _navHideTimer;
  
  // Track selected device for history filtering
  String? _selectedDeviceIdForHistory;
  String? _selectedDeviceIdForStates;

  // --- MERGED initState() ---
  @override
  void initState() {
    super.initState();
    
    // Add app lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize scroll controller for auto-hiding nav
    _scrollController = ScrollController();
    _scrollController!.addListener(_onScroll);
    
    // 1. Sync & Database setup
    _loadCachedData();
    _syncManager.startPeriodicSync();
    _syncManager.onDeviceStatusChanged = (deviceId, isOnline) {
      setState(() {
        // Update UI when device status changes
      });
    };

    // 2. Tab & Timer setup
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_forcePendingUpdates);
    _tabController.addListener(() {
      // Show nav when switching away from Home tab
      if (_tabController.index != 0 && !_showBottomNav) {
        setState(() => _showBottomNav = true);
        _cancelNavHideTimer();
      } else if (_tabController.index == 0) {
        // Start auto-hide timer when switching back to Home tab
        _startNavHideTimer();
        // Clear device filters when leaving History/States tabs
        if (_selectedDeviceIdForHistory != null) {
          setState(() => _selectedDeviceIdForHistory = null);
        }
        if (_selectedDeviceIdForStates != null) {
          setState(() => _selectedDeviceIdForStates = null);
        }
      }
      
      // Clear device filter when manually switching away from History tab
      if (_tabController.index != 1 && _selectedDeviceIdForHistory != null) {
        setState(() => _selectedDeviceIdForHistory = null);
      }
      
      // Clear device filter when manually switching away from States tab
      if (_tabController.index != 2 && _selectedDeviceIdForStates != null) {
        setState(() => _selectedDeviceIdForStates = null);
      }
    });
    
    // Start auto-hide timer for initial Home tab view (hide after 5 seconds)
    _startNavHideTimer();
    
    // Start the 10-second periodic timer
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10), 
      // Changed to call the background version
      (Timer t) => _fetchDevicesData(isBackgroundRefresh: true)
    );
    
    _loadData();
  }
  // --- END MERGED initState() ---

  void _onScroll() {
    // Only hide nav on Home tab (index 0)
    if (_tabController.index != 0) {
      if (!_showBottomNav) setState(() => _showBottomNav = true);
      _cancelNavHideTimer(); // Cancel timer on other tabs
      return;
    }
    
    // Cancel existing timer when user scrolls
    _cancelNavHideTimer();
    
    // Show nav when scrolling down the list, hide (after timer) when scrolling up, hide immediately at top
    if (_scrollController!.position.pixels <= 50) {
      // At top of list, hide nav immediately
      if (_showBottomNav) setState(() => _showBottomNav = false);
    } else if (_scrollController!.position.userScrollDirection == ScrollDirection.reverse) {
      // Scrolling down the list (viewing more cards below), show nav
      if (!_showBottomNav) setState(() => _showBottomNav = true);
    } else if (_scrollController!.position.userScrollDirection == ScrollDirection.forward) {
      // Scrolling up the list (going back up), start timer to hide after 5 seconds
      if (_showBottomNav) _startNavHideTimer();
    }
  }

  void _startNavHideTimer() {
    _navHideTimer = Timer(Duration(seconds: 5), () {
      if (_tabController.index == 0 && _showBottomNav) {
        setState(() => _showBottomNav = false);
      }
    });
  }

  void _cancelNavHideTimer() {
    _navHideTimer?.cancel();
    _navHideTimer = null;
  }

  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - refresh data immediately
      print('App resumed - refreshing device data');
      _fetchDevicesData(isBackgroundRefresh: false);
    }
  }

  // --- MERGED dispose() ---
  @override
  void dispose() {
    // Remove app lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // 1. Timer and Tab cleanup
    _refreshTimer?.cancel(); 
    _navHideTimer?.cancel();
    _tabController.removeListener(_forcePendingUpdates); // Remove listener
    _tabController.dispose();
    
    // 2. Scroll controller cleanup
    _scrollController?.removeListener(_onScroll);
    _scrollController?.dispose();
    
    // 3. Sync cleanup
    _syncManager.stopPeriodicSync();
    
    super.dispose();
  }
  // --- END MERGED dispose() ---

  void _navigateToHistory(String deviceId) {
    setState(() {
      _selectedDeviceIdForHistory = deviceId;
      _tabController.animateTo(1); // Navigate to History tab (index 1)
    });
  }

  void _navigateToStates(String deviceId) {
    setState(() {
      _selectedDeviceIdForStates = deviceId;
      _tabController.animateTo(2); // Navigate to States tab (index 2)
    });
  }

  Future<void> _loadCachedData() async {
    final cachedDevices = await _dbHelper.getAllCachedDevices();

    setState(() {
      // Update UI with cached data
    });

    for (var device in cachedDevices) {
      _syncManager.fetchAndCacheDeviceData(
        device['device_id'],
        device['api_url'],
      );
    }
  }

  Future<void> setTemperature(String deviceId, double temp) async {
    final deviceConfig = await _dbHelper.getCachedDeviceConfig(deviceId);
    if (deviceConfig == null) return;

    final apiUrl = deviceConfig['api_url'] as String;

    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/api/set_temp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'temperature': temp}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        await _dbHelper.updateDeviceConfig(deviceId, {
          'set_temperature': temp,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Temperature set to ${temp.toStringAsFixed(1)}°F')),
        );
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      await _syncManager.queueTemperatureChange(deviceId, temp);
      await _dbHelper.updateDeviceConfig(deviceId, {
        'set_temperature': temp,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline: Will sync when connection restored'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _forcePendingUpdates() {
    if (_tabController.indexIsChanging) {
      for (var key in _cardKeys.values) {
        key.currentState?.forceUpdate();
      }
    }
  }

  Future<void> _loadData() async {
    // Only call setState for the initial load
    setState(() {
      isLoading = true;
    });
    await AppConfig.initializeApiUrlList();
    await _fetchDevicesData(isBackgroundRefresh: false);
  }
  
  // MODIFIED: Added isBackgroundRefresh flag and device ordering support
  Future<void> _fetchDevicesData({bool isBackgroundRefresh = false}) async {
    // Show loading indicator only for initial load/manual refresh
    if (!isBackgroundRefresh) {
      setState(() {
        isLoading = true;
        _cardKeys.clear(); // Clear keys before fetching new device list
      });
    }

    // 1. Fetch data from server WITH CACHE FALLBACK
    final serverDevices = await _syncManager.fetchDevicesWithCache(AppConfig.serverApiUrl);
    
    // Load saved device order
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedOrder = prefs.getStringList('deviceOrder');
    
    // List to hold newly created DeviceData objects for comparison/initial load
    List<DeviceData> newlyFetchedDevices = [];
    
    // 2. Process fetched data
    for (var deviceInfo in serverDevices) {
      if (!deviceInfo['is_active']) continue; 

      final deviceId = deviceInfo['device_id'] ?? '';
      final deviceType = deviceInfo['device_type'] ?? 'Unknown';
      final deviceName = deviceInfo['device_name'] ?? deviceId;
      final location = deviceInfo['location'] ?? '';
      
      String apiUrl = '';
      if (deviceInfo['ip_address'] != null && deviceInfo['ip_address'].isNotEmpty) {
        apiUrl = 'http://${deviceInfo['ip_address']}:5001';
      }

      Map<String, dynamic>? statusData;
      if (apiUrl.isNotEmpty) {
        statusData = await _fetchDeviceStatus(apiUrl);
      }

      // Create a temporary object for the fetched data
      newlyFetchedDevices.add(DeviceData(
        deviceId: deviceId,
        deviceType: deviceType,
        displayName: deviceName,
        location: location,
        apiUrl: apiUrl,
        temperature: statusData?['temperature']?.toDouble() ?? 
                    deviceInfo['last_temperature']?.toDouble(),
        humidity: statusData?['humidity']?.toDouble() ??
                 deviceInfo['last_humidity']?.toDouble(),
        setTemperature: statusData?['set_temperature']?.toDouble(),
        currentState: statusData?['state'],
        emergencyStop: statusData?['emergency_stop'] ?? false,
        fanMode: statusData?['fan_mode'] ?? false,
        cooldownRemainingSeconds: statusData?['cooldown_remaining_seconds']?.toInt() ?? 0,
        estimatedTimeToTargetSeconds: statusData?['estimated_time_to_target_seconds']?.toInt() ?? 0,
      ));
    }
    
    // 3. Update internal state based on refresh type

    if (isBackgroundRefresh) {
      // Background Refresh: Update existing objects
      
      // Create a map of existing devices for quick lookup
      final Map<String, DeviceData> existingDevicesMap = 
        {for (var device in devices) device.deviceId: device};
        
      for (var newDeviceData in newlyFetchedDevices) {
        if (existingDevicesMap.containsKey(newDeviceData.deviceId)) {
          // Found existing device, update its properties in place
          final existingDevice = existingDevicesMap[newDeviceData.deviceId]!;
          
          // Check if this device has a pending temperature change
          final key = _cardKeys[existingDevice.deviceId];
          final hasPendingChange = key?.currentState?.hasPendingTemperatureChange ?? false;
          
          existingDevice.updateData(
            temperature: newDeviceData.temperature,
            humidity: newDeviceData.humidity,
            // Only update setTemperature if user is not actively changing it
            setTemperature: hasPendingChange ? existingDevice.setTemperature : newDeviceData.setTemperature,
            currentState: newDeviceData.currentState,
            emergencyStop: newDeviceData.emergencyStop,
            fanMode: newDeviceData.fanMode,
            cooldownRemainingSeconds: newDeviceData.cooldownRemainingSeconds,
            estimatedTimeToTargetSeconds: newDeviceData.estimatedTimeToTargetSeconds,
          );
          
          // CRUCIAL: Call the new sync method after updating the data
          // BUT only if there's no pending temperature change
          if (key != null && key.currentState != null) {
            // Only sync timers if user is not actively changing temperature
            if (!hasPendingChange) {
              key.currentState!.syncTimers(); // Calls setState internally
            }
          }
        } else {
          // New device discovered since last full refresh, add it
          devices.add(newDeviceData);
        }
      }
      
      // Remove any devices that are no longer in the fetched list (e.g., went offline)
      final Set<String> fetchedIds = newlyFetchedDevices.map((d) => d.deviceId).toSet();
      devices.removeWhere((device) => !fetchedIds.contains(device.deviceId));

      // NOTE: We don't call setState on HomePage here. The syncTimers() call handles the redraw.
      
    } else {
      // Initial Load / Manual Pull-to-Refresh: Replace and sort
      
      // Apply saved order if available
      if (savedOrder != null && savedOrder.isNotEmpty) {
        List<DeviceData> orderedDevices = [];
        
        // Add devices in saved order
        for (String deviceId in savedOrder) {
          var device = newlyFetchedDevices.firstWhere(
            (d) => d.deviceId == deviceId,
            orElse: () => DeviceData(
              deviceId: '',
              deviceType: '',
              displayName: '',
              location: '',
              apiUrl: '',
            ),
          );
          if (device.deviceId.isNotEmpty) {
            orderedDevices.add(device);
          }
        }
        
        // Add any new devices not in saved order
        for (var device in newlyFetchedDevices) {
          if (!savedOrder.contains(device.deviceId)) {
            orderedDevices.add(device);
          }
        }
        
        newlyFetchedDevices = orderedDevices;
      } else {
        // Default sort if no saved order
        newlyFetchedDevices.sort((a, b) {
          const typeOrder = {
            'Thermostat': 1,
            'HybridThermo': 2,
            'HybridProbe': 3,
            'Probe': 4,
            'Server': 5,
            'Unknown': 6,
          };
          
          int orderA = typeOrder[a.deviceType] ?? 6;
          int orderB = typeOrder[b.deviceType] ?? 6;
          
          if (orderA != orderB) return orderA.compareTo(orderB);
          return a.displayName.compareTo(b.displayName);
        });
      }

      setState(() {
        devices = newlyFetchedDevices;
        isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchDeviceStatus(String apiUrl) async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/status'),
        headers: {'Accept': 'application/json'},
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Error fetching status from $apiUrl: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Remove title completely
        toolbarHeight: 0, // Hide the app bar but keep the system status bar
        elevation: 0,
      ),
      // Floating action button for settings in top right (all tabs)
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          _forcePendingUpdates(); 
          
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SettingsPage()),
          );
          if (result == true) {
            // Manual refresh after settings change
            _fetchDevicesData(isBackgroundRefresh: false);
          }
        },
        child: Icon(Icons.settings),
        tooltip: 'Settings',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      // Move TabBar to bottom with animation
      bottomNavigationBar: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        height: _showBottomNav ? null : 0,
        child: _showBottomNav 
          ? Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 8,
              child: TabBar(
                controller: _tabController,
                tabs: [
                  Tab(icon: Icon(Icons.home), text: 'Home'),
                  Tab(icon: Icon(Icons.show_chart), text: 'History'),
                  Tab(icon: Icon(Icons.access_time), text: 'States'),
                ],
              ),
            )
          : SizedBox.shrink(),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHomeTab(),
          // Remove right padding - FAB only shows on Home tab
          HistoricalTemperaturesScreen(selectedDeviceId: _selectedDeviceIdForHistory),
          PreviousStatesScreen(selectedDeviceId: _selectedDeviceIdForStates),
          ///AIScreen(),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.device_unknown, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No devices found'),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _fetchDevicesData(isBackgroundRefresh: false),
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Detect orientation
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          // LANDSCAPE: Two-column grid layout
          return _buildLandscapeLayout();
        } else {
          // PORTRAIT: Single-column list layout
          return _buildPortraitLayout();
        }
      },
    );
  }

  // Portrait layout - single column list (original behavior)
  Widget _buildPortraitLayout() {
    return RefreshIndicator(
      onRefresh: () => _fetchDevicesData(isBackgroundRefresh: false),
      child: ListView.builder(
        controller: _scrollController, // Add scroll controller
        padding: EdgeInsets.all(8),
        itemCount: devices.length,
        itemBuilder: (context, index) {
          final device = devices[index];
          
          // Reuse existing key or create new one if needed
          final key = _cardKeys.putIfAbsent(
            device.deviceId,
            () => GlobalKey<_DeviceCardState>(),
          );
          
          return DeviceCard(
            key: key,
            device: device,
            onRefresh: () => _fetchDevicesData(isBackgroundRefresh: true),
            onNavigateToHistory: _navigateToHistory,
            onNavigateToStates: _navigateToStates,
          );
        },
      ),
    );
  }

  // Landscape layout - two-column grid grouped by type
  Widget _buildLandscapeLayout() {
    // Filter devices into groups
    final thermostats = devices.where((d) => d.isThermostat).toList();
    final probes = devices.where((d) => d.isProbe).toList();

    return RefreshIndicator(
      onRefresh: () => _fetchDevicesData(isBackgroundRefresh: false),
      child: ListView(
        controller: _scrollController, // Add scroll controller
        padding: EdgeInsets.only(top: 8, left: 4, right: 4, bottom: 8),
        children: [
          // Thermostat Grid (More compact)
          if (thermostats.isNotEmpty)
            _buildDeviceGrid(
              context, 
              thermostats, 
              'Thermostats', 
              kThermostatAspectRatio,
            ),
            
          // Separator between groups
          if (thermostats.isNotEmpty && probes.isNotEmpty) 
            SizedBox(height: 24),
            
          // Probe Grid (Very compact)
          if (probes.isNotEmpty)
            _buildDeviceGrid(
              context, 
              probes, 
              'Probes', 
              kProbeAspectRatio,
            ),
        ],
      ),
    );
  }

  // Helper function to build a GridView for a specific device type
  Widget _buildDeviceGrid(
    BuildContext context, 
    List<DeviceData> devices, 
    String title, 
    double aspectRatio,
  ) {
    // Calculate better column count based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1000 ? 3 : 2; // 3 columns on tablets
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 8.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        GridView.builder(
          primary: false, 
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(), // Disable grid scrolling
          itemCount: devices.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
          ),
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          itemBuilder: (context, index) {
            final device = devices[index];
            
            // Reuse existing key or create new one if needed
            final key = _cardKeys.putIfAbsent(
              device.deviceId,
              () => GlobalKey<_DeviceCardState>(),
            );
            
            return DeviceCard(
              key: key,
              device: device,
              onRefresh: () => _fetchDevicesData(isBackgroundRefresh: true),
              onNavigateToHistory: _navigateToHistory,
              onNavigateToStates: _navigateToStates,
            );
          },
        ),
      ],
    );
  }
}


// --- START: DeviceCard Refactored to StatefulWidget ---
class DeviceCard extends StatefulWidget {
  final DeviceData device;
  // Change onRefresh signature to match the new background refresh logic
  final Function() onRefresh; 
  final Function(String deviceId)? onNavigateToHistory;
  final Function(String deviceId)? onNavigateToStates;

  const DeviceCard({
    Key? key, // Key is required for GlobalKey usage
    required this.device,
    required this.onRefresh,
    this.onNavigateToHistory,
    this.onNavigateToStates,
  }) : super(key: key);

  @override
  _DeviceCardState createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  // Local state for pending temperature change and the debouncing timer
  late double _targetTemperature;
  Timer? _temperatureTimer;
  // State to track if the change was an increase (1.0), decrease (-1.0), or none (0.0)
  double _lastDeltaColor = 0.0; 
  // Flag to track if user is actively modifying temperature (not just the timer)
  bool _isUserModifyingTemperature = false;
  
  // Cooldown timer state
  Timer? _cooldownCountdownTimer;
  int _localCooldownSeconds = 0;
  DateTime? _lastCooldownUpdate;

  // Estimated time to target timer state
  Timer? _estimatedTimeCountdownTimer;
  int _localEstimatedTimeSeconds = 0;
  DateTime? _lastEstimatedTimeUpdate;

  @override
  void initState() {
    super.initState();
    // Initialize local target temperature from device data
    _targetTemperature = widget.device.setTemperature ?? 70.0;
    
    // Only initialize timers for thermostats (not probes)
    if (widget.device.isThermostat) {
      // Initialize cooldown timer
      _initializeCooldownTimer();
      // Initialize estimated time timer
      _initializeEstimatedTimeTimer();
    }
  }

  // Public getter to check if user has pending temperature changes
  bool get hasPendingTemperatureChange => _isUserModifyingTemperature || (_temperatureTimer?.isActive ?? false);

  // Public method to force the update immediately (called by HomePage before navigation)
  void forceUpdate() {
    if (_temperatureTimer?.isActive == true) {
      _temperatureTimer?.cancel();
      _isUserModifyingTemperature = false;
      _sendTemperatureUpdate(_targetTemperature);
    }
  }
  
  // NEW PUBLIC METHOD: Called by HomePage after a background data update
  void syncTimers() {
    // 1. Sync setpoint display if no local change is pending and user is not actively modifying
    if (!_isUserModifyingTemperature && _temperatureTimer?.isActive != true) {
      _targetTemperature = widget.device.setTemperature ?? 70.0;
      _lastDeltaColor = 0.0; 
    }
    
    // 2. Re-run timer initialization logic based on latest data (only for thermostats)
    if (widget.device.isThermostat) {
      _syncCooldownWithServer();
      _syncEstimatedTimeWithServer();
    }
    
    // 3. Force a UI redraw to reflect all changes
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep setpoint sync here for when the widget is rebuilt with a new key 
    // (like during a full manual refresh)
    
    // If the server confirmed a setpoint change AND we are not locally pending or actively modifying
    if (widget.device.setTemperature != oldWidget.device.setTemperature && 
        !_isUserModifyingTemperature && 
        _temperatureTimer?.isActive != true) {
      // The parent gave us a confirmed temperature, sync local state
      _targetTemperature = widget.device.setTemperature ?? 70.0;
      _lastDeltaColor = 0.0; 
    }
    
    // NOTE: Timer sync logic is now in syncTimers(), which is called by HomePage 
    // during a background refresh. We don't need to duplicate it here.
  }

  @override
  void dispose() {
    _temperatureTimer?.cancel();
    _cooldownCountdownTimer?.cancel();
    _estimatedTimeCountdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Detect orientation for responsive sizing
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final scaleFactor = isLandscape ? 0.75 : 1.0; // Scale down 25% in landscape
    
    return Card(
      margin: EdgeInsets.symmetric(
        vertical: isLandscape ? 4 : 8, 
        horizontal: 4
      ),
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 12 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isLandscape, scaleFactor),
              // NEW: Sensor failure alert (only shows when in sensor failure mode)
              if (widget.device.isThermostat) _buildSensorFailureAlert(),
              SizedBox(height: isLandscape ? 8 : 12),
              _buildTemperatureDisplay(isLandscape, scaleFactor),
              if (widget.device.isThermostat) ...[
                SizedBox(height: isLandscape ? 10 : 16),
                _buildThermostatControls(context, isLandscape, scaleFactor),
              ],
            ],
          ),
        ),
      ),
    );
  }
  bool _isSensorFailure() {
  // A device is considered in sensor failure mode if it's a thermostat
  // and the temperature reading is unavailable (null).
  return widget.device.isThermostat && widget.device.temperature == null;
}

// FIX: Method to build the alert widget (Error at 1084)
Widget _buildSensorFailureAlert() {
  if (!_isSensorFailure()) return SizedBox.shrink();
  return Container(
    width: double.infinity,
    margin: EdgeInsets.all(12),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.deepPurple.shade50,
      border: Border.all(color: Colors.deepPurple, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.sensors_off, color: Colors.deepPurple, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thermostat Offline / Sensor Failure',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.deepPurple,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Temperature reading is unavailable. HVAC control is disabled to prevent damage.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        // Helper calls
        _buildTroubleshootingStep('1', 'Check if the device is powered on and connected to the network.'),
        _buildTroubleshootingStep('2', 'Verify the API URL is correct in the Settings menu.'),
        _buildTroubleshootingStep('3', 'Wait 30 seconds for the device to reconnect.'),
        SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: widget.onRefresh,
          icon: Icon(Icons.refresh, size: 16),
          label: Text('Check Again', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    ),
  );
}

// FIX: Helper method required by _buildSensorFailureAlert
Widget _buildTroubleshootingStep(String number, String text) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade100,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: Colors.deepPurple,
              ),
            ),
          ),
        ),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
// --- END: DeviceCard Refactored to StatefulWidget ---

  Widget _buildHeader(bool isLandscape, double scaleFactor) {
    IconData icon;
    Color iconColor;
    
    switch (widget.device.deviceType) {
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

    return Row(
      children: [
        InkWell(
          onTap: () {
            if (widget.onNavigateToHistory != null) {
              widget.onNavigateToHistory!(widget.device.deviceId);
            }
          },
          onLongPress: () {
            // Only navigate to states for thermostats
            if (widget.device.isThermostat && widget.onNavigateToStates != null) {
              widget.onNavigateToStates!(widget.device.deviceId);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.all(4 * scaleFactor),
            child: Icon(icon, size: 32 * scaleFactor, color: iconColor),
          ),
        ),
        SizedBox(width: 12 * scaleFactor),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.device.displayName,
                style: TextStyle(
                  fontSize: 20 * scaleFactor,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.device.location.isNotEmpty)
                Text(
                  widget.device.location,
                  style: TextStyle(
                    fontSize: 14 * scaleFactor,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                widget.device.deviceType,
                style: TextStyle(
                  fontSize: 12 * scaleFactor,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        // Settings icon in landscape mode
        if (isLandscape && widget.device.apiUrl.isNotEmpty)
          IconButton(
            icon: Icon(Icons.settings),
            iconSize: 24 * scaleFactor,
            onPressed: () => _showDeviceSettings(context),
            tooltip: 'Device Settings',
            padding: EdgeInsets.all(8 * scaleFactor),
            constraints: BoxConstraints(),
          ),
      ],
    );
  }

  Widget _buildTemperatureDisplay(bool isLandscape, double scaleFactor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildTempInfo(
          'Current',
          widget.device.temperature,
          Colors.blue,
          isLandscape,
          scaleFactor,
        ),
        if (widget.device.humidity != null)
          _buildTempInfo(
            'Humidity',
            widget.device.humidity,
            Colors.green,
            isLandscape,
            scaleFactor,
            suffix: '%',
          ),
        if (widget.device.isThermostat && widget.device.setTemperature != null)
          _buildTempInfo(
            'Target',
            widget.device.setTemperature,
            Colors.orange,
            isLandscape,
            scaleFactor,
          ),
      ],
    );
  }

  Widget _buildTempInfo(String label, double? value, Color color, bool isLandscape, double scaleFactor, {String suffix = '°F'}) {
    final isSensorFailure = _isSensorFailure();
    final bool isTemperature = label == 'Current' || label == 'Target';
    
    return Column(
      children: [
        // Add sensor offline indicator for current temperature when in sensor failure
        if (label == 'Current' && isSensorFailure)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            margin: EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sensors_off, color: Colors.deepPurple, size: 12),
                SizedBox(width: 4),
                Text(
                  'OFFLINE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12 * scaleFactor,
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: 4 * scaleFactor),
        Text(
          // Show "--" for temperature values when sensor failed, otherwise normal
          (isSensorFailure && isTemperature) 
              ? '--$suffix' 
              : (value != null ? '${value.toStringAsFixed(1)}$suffix' : 'N/A'),
          style: TextStyle(
            fontSize: 24 * scaleFactor,
            fontWeight: FontWeight.bold,
            color: (isSensorFailure && isTemperature) ? Colors.grey : color,
          ),
        ),
      ],
    );
  }

  Widget _buildThermostatControls(BuildContext context, bool isLandscape, double scaleFactor) {
    // Display the local pending temperature, or the device's confirmed temperature
    final displayTemp = _targetTemperature;
    final displayTempString = displayTemp.toStringAsFixed(0); // Display as full degrees
    
    // Check if the timer is active to show a pending state
    final isPending = _temperatureTimer?.isActive == true;

    // Determine the color based on the last change direction
    Color pendingColor;
    if (_lastDeltaColor > 0) {
      pendingColor = Colors.red; // Increasing
    } else if (_lastDeltaColor < 0) {
      pendingColor = Colors.blue; // Decreasing
    } else {
      pendingColor = Colors.redAccent; // Default 
    }

    // If not pending, use the default theme text color
    final defaultTextColor = Theme.of(context).textTheme.headlineLarge?.color ?? Theme.of(context).primaryColor;

    return Column(
      children: [
        if (widget.device.currentState != null)
          Padding(
            padding: EdgeInsets.only(bottom: isLandscape ? 8 : 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getStateIcon(widget.device.currentState!),
                  color: _getStateColor(widget.device.currentState!),
                  size: isLandscape ? 20 : 24,
                ),
                SizedBox(width: isLandscape ? 6 : 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'State: ${widget.device.currentState}',
                      style: TextStyle(
                        fontSize: 16 * scaleFactor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_localCooldownSeconds > 0 &&
                        (widget.device.currentState == 'Fan Only' || 
                         widget.device.currentState == 'Between States'))
                      Text(
                        _formatCooldownTime(_localCooldownSeconds),
                        style: TextStyle(
                          fontSize: 12 * scaleFactor,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if ((widget.device.currentState == 'Cooling' || 
                         widget.device.currentState == 'Heating' ||
                         widget.device.currentState == 'Emergency Heat'))
                      Text(
                        _localEstimatedTimeSeconds > 0 
                          ? _formatEstimatedTime(_localEstimatedTimeSeconds)
                          : 'Calculating...',
                        style: TextStyle(
                          fontSize: 12 * scaleFactor,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          
        // --- Combined Setpoint Control ---
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Minus Button (-1 degree)
            IconButton(
              onPressed: _isSensorFailure() ? null : () => _adjustTemperature(-1.0),
              icon: Icon(Icons.remove_circle_outline, size: 38 * scaleFactor),
              color: Colors.blue, // Always blue for decrease button
              tooltip: 'Lower by 1°F',
            ),
            
            // Current Setpoint Display (Tap to open direct entry dialog)
            GestureDetector(
              onTap: _isSensorFailure() ? null : () => _showSetTemperatureDialog(context), 
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16 * scaleFactor),
                child: Column(
                  children: [
                    Text(
                      'SETPOINT', 
                      style: TextStyle(
                        fontSize: 12 * scaleFactor, 
                        // Use the derived pending color or the theme's secondary text color
                        color: isPending 
                            ? pendingColor 
                            : Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7) ?? Colors.grey
                      )
                    ),
                    Text(
                      '$displayTempString°F',
                      style: TextStyle(
                        fontSize: 38 * scaleFactor,
                        fontWeight: FontWeight.bold,
                        // Use the derived pending color or the theme's default text color
                        color: isPending 
                            ? pendingColor 
                            : defaultTextColor,
                      ),
                    ),
                    if (isPending)
                      Text(
                        '(Pending...)',
                        style: TextStyle(fontSize: 10 * scaleFactor, color: pendingColor),
                      ),
                  ],
                ),
              ),
            ),
            
            // Plus Button (+1 degree)
            IconButton(
              onPressed: _isSensorFailure() ? null : () => _adjustTemperature(1.0),
              icon: Icon(Icons.add_circle_outline, size: 38 * scaleFactor),
              color: Colors.red, // Always red for increase button
              tooltip: 'Raise by 1°F',
            ),
          ],
        ),
        SizedBox(height: isLandscape ? 10 : 16),
        // ----------------------------------

        // --- Device Settings Button (Portrait only) ---
        if (!isLandscape)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.device.apiUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showDeviceSettings(context),
                  icon: Icon(Icons.settings),
                  label: Text('Device Settings'),
                ),
            ],
          ),
      ],
    );
  }

  IconData _getStateIcon(String state) {
    switch (state.toLowerCase()) {
      case 'cooling':
        return Icons.ac_unit;
      case 'heating':
      case 'emergency heat':
        return Icons.local_fire_department;
      case 'fan only':
        return Icons.air;
      case 'sensor failure':
        return Icons.sensors_off;
      default:
        return Icons.power_settings_new;
    }
  }

  Color _getStateColor(String state) {
    switch (state.toLowerCase()) {
      case 'cooling':
        return Colors.blue;
      case 'heating':
        return Colors.orange;
      case 'emergency heat':
        return Colors.red;
      case 'fan only':
        return Colors.green;
      case 'sensor failure':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  String _formatCooldownTime(int seconds) {
    if (seconds <= 0) return '';
    
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    
    if (minutes > 0) {
      return 'Cooldown: ${minutes}m ${remainingSeconds}s remaining';
    } else {
      return 'Cooldown: ${remainingSeconds}s remaining';
    }
  }

  // Cooldown timer management methods
  void _initializeCooldownTimer() {
    // Check if the current cooldown value is different from the previous local state 
    // before re-starting the timer, but this initial call is just for setup.
    // We only rely on _syncCooldownWithServer() for updates.
    _localCooldownSeconds = widget.device.cooldownRemainingSeconds;
    _lastCooldownUpdate = DateTime.now();
    _startCooldownCountdown();
  }

  // MODIFIED: This method is now called by syncTimers() to re-sync with external data
  void _syncCooldownWithServer() {
    // Only re-sync and restart if the server provided a new, positive cooldown time
    // OR if the current state requires a cooldown display but the local timer is inactive
    if (widget.device.cooldownRemainingSeconds > 0 || 
        (widget.device.currentState == 'Between States' || widget.device.currentState == 'Fan Only')) {
      // Check if the external data has actually provided a NEW value
      if (_localCooldownSeconds != widget.device.cooldownRemainingSeconds) {
        _localCooldownSeconds = widget.device.cooldownRemainingSeconds;
        _lastCooldownUpdate = DateTime.now();
        _startCooldownCountdown();
      } else if (_cooldownCountdownTimer == null && _localCooldownSeconds > 0) {
        // If the timer died locally but the data still shows a countdown is needed
        _startCooldownCountdown();
      }
    } else {
      // Server is sending 0, or state doesn't require it, ensure local timer is cancelled
      _cooldownCountdownTimer?.cancel();
      _cooldownCountdownTimer = null;
      _localCooldownSeconds = 0;
    }
  }

  void _startCooldownCountdown() {
    // Cancel any existing timer
    _cooldownCountdownTimer?.cancel();
    
    // Only start countdown if there's time remaining
    if (_localCooldownSeconds <= 0) {
      return;
    }
    
    // Start a periodic timer that ticks every second
    _cooldownCountdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      // NOTE: We rely on the internal Timer to call setState, so we don't need syncTimers here.
      setState(() { 
        if (_localCooldownSeconds > 0) {
          _localCooldownSeconds--;
        } else {
          // Timer expired, cancel it
          timer.cancel();
          _cooldownCountdownTimer = null;
          // Trigger background refresh when cooldown completes
          widget.onRefresh();
        }
      });
    });
  }

  // Estimated time to target timer management methods
  void _initializeEstimatedTimeTimer() {
    _localEstimatedTimeSeconds = widget.device.estimatedTimeToTargetSeconds;
    _lastEstimatedTimeUpdate = DateTime.now();
    
    // Debug logging
    print('Estimated Time Init: ${_localEstimatedTimeSeconds}s for state ${widget.device.currentState}');
    
    _startEstimatedTimeCountdown();
  }

  // MODIFIED: This method is now called by syncTimers() to re-sync with external data
  void _syncEstimatedTimeWithServer() {
    // Only re-sync and restart if the server provided a new, positive estimated time
    if (widget.device.estimatedTimeToTargetSeconds > 0) {
      // Check if the external data has actually provided a NEW value
      if (_localEstimatedTimeSeconds != widget.device.estimatedTimeToTargetSeconds) {
        _localEstimatedTimeSeconds = widget.device.estimatedTimeToTargetSeconds;
        _lastEstimatedTimeUpdate = DateTime.now();
        _startEstimatedTimeCountdown();
      } else if (_estimatedTimeCountdownTimer == null && _localEstimatedTimeSeconds > 0) {
        // If the timer died locally but the data still shows a countdown is needed
        _startEstimatedTimeCountdown();
      }
    } else {
      // Server is sending 0, ensure local timer is cancelled
      _estimatedTimeCountdownTimer?.cancel();
      _estimatedTimeCountdownTimer = null;
      _localEstimatedTimeSeconds = 0;
    }
  }

  void _startEstimatedTimeCountdown() {
    // Cancel any existing timer
    _estimatedTimeCountdownTimer?.cancel();
    
    // Only start countdown if there's time remaining
    if (_localEstimatedTimeSeconds <= 0) {
      return;
    }
    
    // Start a periodic timer that ticks every second
    _estimatedTimeCountdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_localEstimatedTimeSeconds > 0) {
          _localEstimatedTimeSeconds--;
        } else {
          // Timer expired, cancel it
          timer.cancel();
          _estimatedTimeCountdownTimer = null;
          // Trigger background refresh when estimated time completes
          widget.onRefresh();
        }
      });
    });
  }

  String _formatEstimatedTime(int seconds) {
    if (seconds <= 0) return '';
    
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    
    if (minutes > 0) {
      return '~${minutes}m ${remainingSeconds}s remaining';
    } else {
      return '~${remainingSeconds}s remaining';
    }
  }

  void _adjustTemperature(double delta) {
    if (widget.device.apiUrl.isEmpty) return;

    setState(() {
      // Mark that user is actively modifying temperature
      _isUserModifyingTemperature = true;
      
      // 1. Adjust local state in full degree increments (delta is now always 1.0 or -1.0)
      double newTemp = _targetTemperature + delta;

      // Sanity checks: keep temperature between 32 and 100
      if (newTemp < 32.0) newTemp = 32.0;
      if (newTemp > 100.0) newTemp = 100.0;
      
      // Update the color state based on the direction of change
      _lastDeltaColor = delta;

      // Ensure the temperature is stored as a full degree (important since the delta is 1.0)
      _targetTemperature = newTemp.roundToDouble();

      // 2. Cancel existing timer
      _temperatureTimer?.cancel();

      // 3. Start a new 4-second timer
      _temperatureTimer = Timer(Duration(seconds: 4), () {
        // Clear the modification flag when timer completes
        _isUserModifyingTemperature = false;
        _sendTemperatureUpdate(_targetTemperature);
      });
    });
  }
  
  Future<void> _sendTemperatureUpdate(double newTemp) async {
    final apiUrl = widget.device.apiUrl;
    if (apiUrl.isEmpty) return;
    
    // Check if a change actually occurred before sending (prevents unnecessary API calls on forceUpdate)
    if (newTemp == widget.device.setTemperature && _temperatureTimer == null) {
        return;
    }

    // Set state immediately to show that the update is being processed
    setState(() {
      // Clear the modification flag, timer reference and the color reference immediately
      _isUserModifyingTemperature = false;
      _temperatureTimer = null; 
      _lastDeltaColor = 0.0;
    });

    bool thermostatSuccess = false;
    bool serverSuccess = false;

    try {
      // 1. Send to the thermostat (port 5001)
      final thermostatResponse = await http.post(
        Uri.parse('$apiUrl/api/set_temperature'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'temperature': newTemp}),
      );

      thermostatSuccess = thermostatResponse.statusCode == 200;

      // 2. Also send to the server to persist in database (port 5000)
      if (AppConfig.serverApiUrl.isNotEmpty && widget.device.deviceId.isNotEmpty) {
        final deviceId = widget.device.deviceId;
        try {
          final serverResponse = await http.post(
            Uri.parse('${AppConfig.serverApiUrl}/api/device/$deviceId/set_temperature'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'temperature': newTemp}),
          );
          
          serverSuccess = serverResponse.statusCode == 200;
          
          if (!serverSuccess) {
            print('Warning: Server update failed with status ${serverResponse.statusCode}');
          }
        } catch (serverError) {
          print('Warning: Failed to update server: $serverError');
        }
      }

      if (thermostatSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              serverSuccess 
                ? 'Temperature set to ${newTemp.toStringAsFixed(0)}°F (saved to server)'
                : 'Temperature set to ${newTemp.toStringAsFixed(0)}°F (local only)'
            ),
            backgroundColor: serverSuccess ? Colors.green : Colors.orange,
          ),
        );
        
        // Trigger immediate background refresh
        widget.onRefresh();
        
        // Also trigger a second refresh after a delay to ensure the thermostat
        // has fully processed the change and the server has the latest state
        Future.delayed(Duration(milliseconds: 1000), () {
          if (mounted) {
            widget.onRefresh();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set temperature. Server status: ${thermostatResponse.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set temperature: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showSetTemperatureDialog(BuildContext context) async {
    // Mark that user is modifying temperature
    setState(() {
      _isUserModifyingTemperature = true;
    });
    
    // Force update of current target temp from the device data before editing manually
    if (_temperatureTimer?.isActive != true) {
        _targetTemperature = widget.device.setTemperature ?? _targetTemperature;
    }

    final controller = TextEditingController(
      text: _targetTemperature.toStringAsFixed(0),
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Temperature'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Target Temperature (°F) - Full Degrees Only',
            suffixText: '°F',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Clear modification flag if user cancels
              setState(() {
                _isUserModifyingTemperature = false;
              });
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final rawTemp = double.tryParse(controller.text);
              if (rawTemp != null && widget.device.apiUrl.isNotEmpty) {
                // Ensure it's a full degree
                final temp = rawTemp.roundToDouble();

                // 1. Update local state
                setState(() {
                  _targetTemperature = temp;
                  _temperatureTimer?.cancel(); // Cancel any running timer
                  // When setting manually, we don't know the direction, so use neutral color
                  _lastDeltaColor = 0.0; 
                });

                // 2. Send the update immediately (will clear modification flag)
                Navigator.pop(context);
                await _sendTemperatureUpdate(temp);
                
              }
            },
            child: Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showDeviceSettings(BuildContext context) {
    // NEW: Force update before navigating to device settings
    forceUpdate();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSettingsScreen(device: widget.device),
      ),
    ).then((_) => widget.onRefresh());
  }
}

class DeviceSettingsScreen extends StatefulWidget {
  final DeviceData device;
  
  // FIX: Add the onRefresh callback
  final VoidCallback? onRefresh; 

  const DeviceSettingsScreen({
    Key? key,
    required this.device,
    // FIX: Add to constructor
    this.onRefresh, 
  }) : super(key: key);

  @override
  _DeviceSettingsScreenState createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  bool emergencyStop = false;
  bool fanMode = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    emergencyStop = widget.device.emergencyStop;
    fanMode = widget.device.fanMode;
    isLoading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.device.displayName} Settings'),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: Text('Emergency Stop'),
                  subtitle: Text('Stop all HVAC operations'),
                  value: emergencyStop,
                  onChanged: widget.device.isThermostat
                      ? (value) => _toggleEmergencyStop(value)
                      : null,
                ),
                SwitchListTile(
                  title: Text('Fan Mode'),
                  subtitle: Text('Run fan continuously'),
                  value: fanMode,
                  onChanged: (widget.device.isThermostat && !_isSensorFailure())
                      ? (value) => _toggleFanMode(value)
                      : null,
                ),
              ],
            ),
    );
  }

  Future<void> _toggleEmergencyStop(bool value) async {
    try {
      final response = await http.post(
        Uri.parse('${widget.device.apiUrl}/api/emergency_stop'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'enable': value}),
      );

      if (response.statusCode == 200) {
        setState(() {
          emergencyStop = value;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency stop ${value ? 'enabled' : 'disabled'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to toggle emergency stop'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleFanMode(bool value) async {
    try {
      final response = await http.post(
        Uri.parse('${widget.device.apiUrl}/api/fan_mode'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'enabled': value}),
      );

      if (response.statusCode == 200) {
        setState(() {
          fanMode = value;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fan mode ${value ? 'enabled' : 'disabled'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to toggle fan mode'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =====================================================
  // SENSOR FAILURE HELPER METHODS
  // =====================================================
  
  bool _isSensorFailure() {
    final currentState = widget.device.currentState?.toLowerCase() ?? '';
    return currentState == 'sensor failure';
  }

  Widget _buildSensorFailureAlert() {
    if (!_isSensorFailure()) return SizedBox.shrink();
    
    return Container(
      width: double.infinity,
      margin: EdgeInsets.all(12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        border: Border.all(color: Colors.deepPurple, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.sensors_off, color: Colors.deepPurple, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SENSOR FAILURE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'System in safe OFF mode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.deepPurple.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Divider(color: Colors.deepPurple.shade200, height: 1),
          SizedBox(height: 8),
          Text(
            'Temperature sensor is not responding. All heating/cooling has been disabled for safety.',
            style: TextStyle(fontSize: 11, color: Colors.black87),
          ),
          SizedBox(height: 8),
          ExpansionTile(
            title: Text(
              'Troubleshooting Steps',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.deepPurple,
              ),
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(left: 12, top: 4),
            children: [
              _buildTroubleshootingStep('1', 'Check DHT22 sensor wiring'),
              _buildTroubleshootingStep('2', 'Verify sensor power connection'),
              _buildTroubleshootingStep('3', 'Check if pigpio daemon is running'),
              _buildTroubleshootingStep('4', 'Restart the thermostat service'),
              _buildTroubleshootingStep('5', 'Replace sensor if problem persists'),
            ],
          ),
          SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: widget.onRefresh,
            icon: Icon(Icons.refresh, size: 16),
            label: Text('Check Again', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTroubleshootingStep(String number, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.deepPurple,
                ),
              ),
            ),
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// Ensure the file ends cleanly without any extra braces or content.