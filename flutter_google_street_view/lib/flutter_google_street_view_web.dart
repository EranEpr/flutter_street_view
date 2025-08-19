library flutter_google_street_view_web;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_google_street_view/src/web/plugin.dart';

/// Web plugin registrant for FlutterGoogleStreetView
class FlutterGoogleStreetViewPlugin {
  /// Registers this plugin with the Flutter Web plugin registrar
  static void registerWith(Registrar registrar) {
    FlutterGoogleStreetViewWebPlugin.registerWith(registrar);
  }
}
