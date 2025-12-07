# Thermostat App

A Flutter-based mobile application for controlling and monitoring networked thermostats and temperature probes. Companion app for the [x86Thermostat server](https://github.com/AlexGeddylfson/x86Thermostat).

## Quick Start

Download the appropriate version from [Releases](../../releases) and run it. As long as your server and thermostats are configured and running, the app will guide you through initial setup.

## Features

### Device Management
- **Automatic Device Discovery** - Finds all thermostats and probes registered with your server
- **Multi-Device Support** - Control multiple thermostats and monitor temperature probes from a single interface
- **Device Configuration** - Rename devices, set locations, and configure thermostat settings
- **Advanced Thermostat Settings** - Adjust temperature offsets, thresholds, compressor timing, and sensor poll intervals

### Temperature Control
- **Real-Time Monitoring** - Live temperature and humidity readings from all devices
- **Target Temperature Adjustment** - Simple slider interface to set desired temperature
- **Mode Control** - Switch between cooling, heating, emergency heat, and fan-only modes
- **Emergency Stop** - Immediately disable all HVAC operations
- **Cooldown Management** - Visual indicator showing remaining compressor cooldown time

### Data Visualization
- **Temperature History Graph** - Interactive charts with multiple time ranges (24h, 7d, 30d)
- **Multi-Device Graphing** - Compare temperatures across multiple devices simultaneously
- **State History** - View previous 20+ thermostat state changes with timestamps
- **Time-Based Filtering** - Filter historical data by device and time range

### User Experience
- **Long-Press Features** - Hold thermostat/probe icons to view current state details
- **Tap for History** - Tap device icons to jump directly to temperature history
- **Dark/Light Mode** - Choose your preferred theme
- **Pull to Refresh** - Update data on any screen with a simple pull-down gesture
- **Offline Support** - Local caching with automatic sync when connection is restored

### System Information
- **Sensor Failure Detection** - Automatic alerts when temperature sensors malfunction
- **Network Status** - Visual indicators for device connectivity
- **Estimated Time to Target** - Shows how long until target temperature is reached

## Screenshots

### Main Interface
The main screen displays all connected devices with real-time status. Long-press any thermostat icon to view detailed state information. Tap to view temperature history for that specific device.

<img src="https://github.com/AlexGeddylfson/x86ThermostatApp/blob/main/Screenshot_20251207_012243.jpg" width="300">

### Previous States
View the last 20+ state changes across all devices, filterable by device. Shows mode transitions (cooling, heating, emergency heat, etc.) with precise timestamps.

<img src="https://github.com/AlexGeddylfson/x86ThermostatApp/blob/main/Screenshot_20251207_012306.jpg" width="300">

### Temperature History
Interactive graph showing historical temperature data with multiple time ranges (24 hours, 7 days, 30 days), multi-device comparison with color-coded lines, detailed list view with humidity readings, and touch-to-view specific data points.

<img src="https://github.com/AlexGeddylfson/x86ThermostatApp/blob/main/Screenshot_20251207_012259.jpg" width="300">


## Supported Platforms

- **Android** - APK and App Bundle builds
- **Web** - Progressive Web App
- **Windows** - (requires Windows to build)
- **Linux** - (requires Linux to build)

## Requirements

- Thermostat system running (see [x86Thermostat](https://github.com/AlexGeddylfson/x86Thermostat))
- Network connectivity to server
- Compatible thermostat hardware (Raspberry Pi or x86-based)

## Initial Setup

On first launch, the app will guide you through:
1. Entering your server's IP address or hostname
2. Discovering available devices
3. Selecting theme preference

All configuration is saved locally for future use.

## Building from Source

### Android/Web (from macOS, Windows, or Linux)
```bash
# Get dependencies
flutter pub get

# Build for Android
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Build for Web
flutter build web --release
# Output: build/web/
```

### Platform-Specific Builds
Windows builds require Windows, macOS builds require macOS, etc. Each platform requires its respective toolchain.

## Related Projects

- [x86Thermostat](https://github.com/AlexGeddylfson/x86Thermostat) - Main server implementation (C#)
- Thermostat hardware implementations (Raspberry Pi, x86)

## License

[Include your license here]
