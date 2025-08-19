import 'package:flutter/material.dart';
import 'package:flutter_google_street_view/src/web/plugin.dart';

/// Platform-agnostic interface for Flutter Google Street View Plugin
class FlutterGoogleStreetViewPlugin {
  late final int viewId;
  late final Widget htmlWidget;
  late final FlutterGoogleStreetViewWebPlugin _webPlugin;

  FlutterGoogleStreetViewPlugin._(this._webPlugin) {
    viewId = _webPlugin.viewId;
    htmlWidget = _webPlugin.htmlWidget;
  }

  /// Creates a new instance of the plugin with the given options
  static FlutterGoogleStreetViewPlugin init(Map<String, dynamic> options) {
    final webPlugin = FlutterGoogleStreetViewWebPlugin.init(options);
    return FlutterGoogleStreetViewPlugin._(webPlugin);
  }

  /// Disposes of this plugin instance
  void dispose() {
    _webPlugin.dispose();
  }

  /// Updates the options for this street view
  Future<void> updateOptions(Map<String, dynamic> options) async {
    return _webPlugin.updateOptions(options);
  }
}
