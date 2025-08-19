import 'dart:async';
import 'dart:js_interop';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_google_street_view/src/web/convert.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_maps/google_maps.dart' show MapsEventListener;
import 'package:google_maps/google_maps_streetview.dart' as gmaps;
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

class FlutterGoogleStreetViewWebPlugin {
  // Static registrar storage
  static Registrar? _registrar;

  // Static plugin registration for method channel
  static void registerWith(Registrar registrar) {
    _registrar = registrar;

    final MethodChannel channel = MethodChannel(
      'flutter_google_street_view',
      const StandardMethodCodec(),
      registrar,
    );

    final FlutterGoogleStreetViewWebPlugin instance =
        FlutterGoogleStreetViewWebPlugin._();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  // Static instance management
  static final Map<int, StreetViewInstance> _instances = {};
  static int _nextInstanceId = 0;

  // Instance properties
  late final int viewId;
  late final Widget htmlWidget;
  late final StreetViewInstance _streetViewInstance;

  // Private constructor for static registration
  FlutterGoogleStreetViewWebPlugin._();

  // Constructor for widget instances
  FlutterGoogleStreetViewWebPlugin._instance(
      this.viewId, Map<String, dynamic> options) {
    _streetViewInstance = StreetViewInstance(viewId, options);
    _instances[viewId] = _streetViewInstance;

    // For Flutter web, we create a widget that displays the status
    htmlWidget = _StreetViewWebWidget(
      viewType: 'street-view-$viewId',
      streetViewInstance: _streetViewInstance,
    );

    // Initialize the street view instance
    _streetViewInstance.initialize(options);
  }

  // Static factory method expected by the state class
  static FlutterGoogleStreetViewWebPlugin init(Map<String, dynamic> options) {
    final viewId = _nextInstanceId++;
    return FlutterGoogleStreetViewWebPlugin._instance(viewId, options);
  }

  // Method channel handler for static instance
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'createStreetView':
        return _createStreetView(call.arguments);
      case 'disposeStreetView':
        return _disposeStreetView(call.arguments);
      default:
        // Forward to specific instance
        final instanceId = call.arguments['instanceId'] as int?;
        if (instanceId != null && _instances.containsKey(instanceId)) {
          return _instances[instanceId]!.handleMethodCall(call);
        }
        throw PlatformException(
          code: 'not_found',
          message: 'Street View instance not found',
        );
    }
  }

  static Future<int> _createStreetView(Map<String, dynamic> args) async {
    final instanceId = _nextInstanceId++;
    final instance = StreetViewInstance(instanceId, args);
    _instances[instanceId] = instance;
    await instance.initialize(args);
    return instanceId;
  }

  static Future<void> _disposeStreetView(Map<String, dynamic> args) async {
    final instanceId = args['instanceId'] as int;
    final instance = _instances.remove(instanceId);
    instance?.dispose();
  }

  // Instance methods expected by the state class
  void dispose() {
    _streetViewInstance.dispose();
    _instances.remove(viewId);
  }

  Future<void> updateOptions(Map<String, dynamic> options) async {
    return _streetViewInstance
        .handleMethodCall(MethodCall('setOptions', options));
  }
}

class StreetViewInstance {
  final int instanceId;
  late final web.HTMLDivElement containerDiv;
  late final MethodChannel methodChannel;
  gmaps.StreetViewPanorama? streetViewPanorama;

  // Event listeners
  MapsEventListener? _statusListener;
  MapsEventListener? _povListener;
  MapsEventListener? _zoomListener;
  MapsEventListener? _closeListener;

  // Animation state
  Timer? _animationTimer;
  DateTime? _animationStartTime;

  // Control states
  bool _isInitialized = false;
  Completer<Map<String, dynamic>>? _readyCompleter;

  StreetViewInstance(this.instanceId, Map<String, dynamic> initialArgs) {
    containerDiv = web.document.createElement('div') as web.HTMLDivElement
      ..id = 'street-view-$instanceId'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#f0f0f0'
      ..style.zIndex = '1';

    // Register the HTML element as a platform view immediately
    ui_web.platformViewRegistry.registerViewFactory(
      'street-view-$instanceId',
      (int viewId) => containerDiv,
    );

    methodChannel = MethodChannel(
      'flutter_google_street_view_$instanceId',
      const StandardMethodCodec(),
      FlutterGoogleStreetViewWebPlugin._registrar,
    );

    // Register method channel handler for this instance
    methodChannel.setMethodCallHandler(handleMethodCall);
  }

  Future<void> initialize(Map<String, dynamic> options) async {
    print('Initializing Street View for instance $instanceId');
    print('Container div ID: ${containerDiv.id}');

    // Check if Google Maps API is available
    if (!_isGoogleMapsApiLoaded()) {
      final errorMsg =
          'Google Maps JavaScript API not loaded. Please add the API script to your index.html';
      print('Error: $errorMsg');
      containerDiv.innerText = errorMsg;
      methodChannel.invokeMethod("error", {"message": errorMsg});
      return;
    }

    try {
      // Create the Street View panorama directly in our container
      // Don't add to document body - keep it contained within our div
      containerDiv.style.position = 'relative';
      containerDiv.style.width = '100%';
      containerDiv.style.height = '100%';
      containerDiv.style.overflow = 'hidden';

      print('Container div prepared for Street View');

      // Convert Flutter options to Google Maps options
      print('Converting options: $options');
      final gmapsOptions = await toStreetViewPanoramaOptions(options);
      print('Google Maps options created successfully');
      print('Position set: ${gmapsOptions.position != null}');
      print('PanoId: ${gmapsOptions.pano}');

      // Create the Street View panorama
      print('Creating Street View panorama...');
      streetViewPanorama = gmaps.StreetViewPanorama(containerDiv, gmapsOptions);
      print('Street View panorama created successfully');

      // Ensure Street View stays within container bounds after creation
      containerDiv.style.position = 'relative';
      containerDiv.style.overflow = 'hidden';
      containerDiv.style.width = '100%';
      containerDiv.style.height = '100%';
      containerDiv.style.maxWidth = '100%';
      containerDiv.style.maxHeight = '100%';
      containerDiv.style.border = 'none';
      containerDiv.style.outline = 'none';

      // Apply additional containment to any nested Street View elements
      final streetViewElements =
          containerDiv.querySelectorAll('[class*="gm-"]');
      for (int i = 0; i < streetViewElements.length; i++) {
        final element = streetViewElements.item(i);
        if (element is web.HTMLElement) {
          element.style.maxWidth = '100%';
          element.style.maxHeight = '100%';
          element.style.overflow = 'hidden';
        }
      }

      // Find any child elements that might be escaping and constrain them
      final children = containerDiv.children;
      for (int i = 0; i < children.length; i++) {
        final child = children.item(i);
        if (child is web.HTMLElement) {
          child.style.width = '100%';
          child.style.height = '100%';
          child.style.position = 'relative';
          child.style.overflow = 'hidden';
        }
      }

      // Set up event listeners
      _setupEventListeners();

      _isInitialized = true;

      // Complete any waiting requests
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete(_getInstanceState());
        _readyCompleter = null;
      }

      print('Street View initialized successfully for instance $instanceId');
    } catch (e, stackTrace) {
      print('Error initializing Street View: $e');
      print('Error type: ${e.runtimeType}');
      print('Stack trace: $stackTrace');

      // Add error message to the container
      containerDiv.innerText =
          'Street View Error: ${e.toString()}\n\nPlease ensure Google Maps API is loaded in your index.html';

      // Notify about the error
      final errorMsg = e is NoStreetViewException ? e.errorMsg : e.toString();
      methodChannel.invokeMethod("error", {"message": errorMsg});
    }
  }

  bool _isGoogleMapsApiLoaded() {
    try {
      // Try to create a simple Street View object to check if API is loaded
      final testDiv = web.document.createElement('div') as web.HTMLDivElement;
      final testOptions = gmaps.StreetViewPanoramaOptions()..visible = false;
      gmaps.StreetViewPanorama(testDiv, testOptions);
      return true;
    } catch (e) {
      print('Google Maps API not available: $e');
      return false;
    }
  }

  void _setupEventListeners() {
    _clearEventListeners();

    try {
      _statusListener = streetViewPanorama?.addListener(
          "status_changed",
          () {
            // Only fire events if Street View is initialized and has valid data
            if (_isInitialized && streetViewPanorama?.position != null) {
              try {
                final locationData = _getCurrentLocation();
                methodChannel.invokeMethod("pano#onChange", locationData);
              } catch (e) {
                print('Error invoking pano#onChange: $e');
              }
            }
          }.toJS);

      _povListener = streetViewPanorama?.addListener(
          "pov_changed",
          () {
            // Only fire events if Street View is initialized
            if (_isInitialized) {
              try {
                final cameraData = _getCurrentCamera();
                methodChannel.invokeMethod("camera#onChange", cameraData);
              } catch (e) {
                print('Error invoking camera#onChange: $e');
              }
            }
          }.toJS);

      _zoomListener = streetViewPanorama?.addListener(
          "zoom_changed",
          () {
            // Only fire events if Street View is initialized
            if (_isInitialized) {
              try {
                final cameraData = _getCurrentCamera();
                methodChannel.invokeMethod("camera#onChange", cameraData);
              } catch (e) {
                print('Error invoking camera#onChange: $e');
              }
            }
          }.toJS);

      _closeListener = streetViewPanorama?.addListener(
          "closeclick",
          () {
            try {
              methodChannel.invokeMethod("onCloseClicked", true);
            } catch (e) {
              print('Error invoking onCloseClicked: $e');
            }
          }.toJS);

      print('Event listeners set up successfully for instance $instanceId');
    } catch (e) {
      print('Error setting up event listeners: $e');
    }
  }

  void _clearEventListeners() {
    _statusListener?.remove();
    _povListener?.remove();
    _zoomListener?.remove();
    _closeListener?.remove();

    _statusListener = null;
    _povListener = null;
    _zoomListener = null;
    _closeListener = null;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    print(
        'StreetViewInstance $instanceId received method call: ${call.method}');
    final args = call.arguments as Map<String, dynamic>? ?? {};

    // Remove the 'streetView#' prefix if present
    final methodName = call.method.startsWith('streetView#')
        ? call.method.substring('streetView#'.length)
        : call.method;

    switch (methodName) {
      case 'waitForStreetView':
        print(
            'waitForStreetView called for instance $instanceId, initialized: $_isInitialized');
        if (_isInitialized) {
          return _getInstanceState();
        } else {
          _readyCompleter = Completer<Map<String, dynamic>>();
          return _readyCompleter!.future;
        }

      case 'updatePosition':
        return _updatePosition(args);

      case 'animateCamera':
        return _animateCamera(args);

      case 'getLocation':
        return _getCurrentLocation();

      case 'getCamera':
        return _getCurrentCamera();

      case 'getPanoramaCamera':
        return _getCurrentCamera();

      case 'setOptions':
        return _setOptions(args);

      default:
        print('Unhandled method call: ${call.method} (parsed: $methodName)');
        throw PlatformException(
          code: 'unimplemented',
          message:
              'Method ${call.method} not implemented for instance $instanceId',
        );
    }
  }

  Map<String, dynamic> _getInstanceState() {
    return <String, dynamic>{
      'instanceId': instanceId,
      'isInitialized': _isInitialized,
      'location': _getCurrentLocation(),
      'camera': _getCurrentCamera(),
    };
  }

  Future<void> _updatePosition(Map<String, dynamic> args) async {
    try {
      final options = await toStreetViewPanoramaOptions(args);
      streetViewPanorama?.options = options;
    } catch (e) {
      final errorMsg = e is NoStreetViewException ? e.errorMsg : e.toString();
      methodChannel.invokeMethod("error", {"message": errorMsg});
    }
  }

  Future<void> _animateCamera(Map<String, dynamic> args) async {
    final currentPov = streetViewPanorama?.pov;
    final currentZoom = streetViewPanorama?.zoom;

    final targetHeading =
        (args['heading'] as num?)?.toDouble() ?? currentPov?.heading ?? 0.0;
    final targetPitch =
        (args['pitch'] as num?)?.toDouble() ?? currentPov?.pitch ?? 0.0;
    final targetZoom = (args['zoom'] as num?)?.toDouble() ?? currentZoom;
    final duration = args['duration'] as int? ?? 1000;

    _animationTimer?.cancel();
    _animationStartTime = DateTime.now();

    final startHeading = currentPov?.heading ?? 0.0;
    final startPitch = currentPov?.pitch ?? 0.0;
    final startZoom = currentZoom;

    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(_animationStartTime!);
      final progress = min(elapsed.inMilliseconds / duration, 1.0);

      final currentHeading =
          startHeading + (targetHeading - startHeading) * progress;
      final currentPitch = startPitch + (targetPitch - startPitch) * progress;
      final currentZoomValue = (startZoom ?? 0.0) +
          ((targetZoom ?? 0.0) - (startZoom ?? 0.0)) * progress;

      final newPov = gmaps.StreetViewPov()
        ..heading = currentHeading
        ..pitch = currentPitch;

      streetViewPanorama?.pov = newPov;
      streetViewPanorama?.zoom = currentZoomValue;

      if (progress >= 1.0) {
        timer.cancel();
        _animationTimer = null;
      }
    });
  }

  Future<void> _setOptions(Map<String, dynamic> args) async {
    final options = gmaps.StreetViewPanoramaOptions();

    if (args['showRoadLabels'] != null) {
      options.showRoadLabels = args['showRoadLabels'] as bool;
    }
    if (args['clickToGo'] != null) {
      options.clickToGo = args['clickToGo'] as bool;
    }
    if (args['zoomControl'] != null) {
      options.zoomControl = args['zoomControl'] as bool;
    }
    if (args['addressControl'] != null) {
      options.addressControl = args['addressControl'] as bool;
    }
    if (args['linksControl'] != null) {
      options.linksControl = args['linksControl'] as bool;
    }
    if (args['visible'] != null) {
      options.visible = args['visible'] as bool;
    }

    streetViewPanorama?.options = options;
  }

  Map<String, dynamic> _getCurrentLocation() {
    try {
      final position = streetViewPanorama?.position;
      final pano = streetViewPanorama?.pano;

      // Only return data if we have a valid position
      if (position?.lat != null && position?.lng != null) {
        return <String, dynamic>{
          'position': <double>[
            position!.lat.toDouble(),
            position.lng.toDouble()
          ], // Return as array, not object
          'panoId': pano ?? '',
          'links': <dynamic>[], // Empty links for now
        };
      } else {
        // Return default Tampa location if no valid position
        return <String, dynamic>{
          'position': <double>[27.508837, -82.717738], // Return as array
          'panoId': '',
          'links': <dynamic>[],
        };
      }
    } catch (e) {
      print('Error getting current location: $e');
      return <String, dynamic>{
        'position': <double>[
          27.508837,
          -82.717738
        ], // Default Tampa location as array
        'panoId': '',
        'links': <dynamic>[],
      };
    }
  }

  Map<String, dynamic> _getCurrentCamera() {
    try {
      final pov = streetViewPanorama?.pov;
      final zoom = streetViewPanorama?.zoom;

      return <String, dynamic>{
        'bearing': pov?.heading ?? 0.0, // Use 'bearing' instead of 'heading'
        'tilt': pov?.pitch ?? 0.0, // Use 'tilt' instead of 'pitch'
        'zoom': zoom ?? 1.0,
      };
    } catch (e) {
      print('Error getting current camera: $e');
      return <String, dynamic>{
        'bearing': 0.0, // Use 'bearing' instead of 'heading'
        'tilt': 0.0, // Use 'tilt' instead of 'pitch'
        'zoom': 1.0,
      };
    }
  }

  void dispose() {
    _animationTimer?.cancel();
    _clearEventListeners();
    containerDiv.remove();
  }
}

// Simple widget wrapper for the street view HTML element
class _StreetViewWebWidget extends StatefulWidget {
  final String viewType;
  final StreetViewInstance streetViewInstance;

  const _StreetViewWebWidget({
    required this.viewType,
    required this.streetViewInstance,
  });

  @override
  State<_StreetViewWebWidget> createState() => _StreetViewWebWidgetState();
}

class _StreetViewWebWidgetState extends State<_StreetViewWebWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: _WebStreetViewContainer(
        streetViewInstance: widget.streetViewInstance,
      ),
    );
  }
}

// Widget that directly manages the HTML element
class _WebStreetViewContainer extends StatefulWidget {
  final StreetViewInstance streetViewInstance;

  const _WebStreetViewContainer({
    required this.streetViewInstance,
  });

  @override
  State<_WebStreetViewContainer> createState() =>
      _WebStreetViewContainerState();
}

class _WebStreetViewContainerState extends State<_WebStreetViewContainer> {
  late StreamSubscription? _statusSubscription;
  String _status = 'Initializing Street View...';

  @override
  void initState() {
    super.initState();
    // The container div is already created in StreetViewInstance
    // We just need to ensure it's properly styled and ready
    widget.streetViewInstance.containerDiv.style.width = '100%';
    widget.streetViewInstance.containerDiv.style.height = '100%';
    widget.streetViewInstance.containerDiv.style.display = 'block';

    // Listen for status changes
    _listenToStreetView();
  }

  void _listenToStreetView() {
    // Check if Street View is initialized
    Timer.periodic(Duration(milliseconds: 1000), (timer) {
      if (mounted) {
        if (widget.streetViewInstance._isInitialized) {
          setState(() {
            _status = 'Street View Initialized ✅';
          });
          timer.cancel();
        } else if (widget.streetViewInstance.streetViewPanorama != null) {
          setState(() {
            _status = 'Street View Loading... ⏳';
          });
        } else {
          setState(() {
            _status = 'Initializing Street View... 🔄';
          });
        }

        // Auto-cancel after 30 seconds to prevent infinite polling
        if (timer.tick > 30) {
          setState(() {
            _status = 'Street View initialization timeout ❌';
          });
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.streetViewInstance._isInitialized) {
      // Use HtmlElementView to display the actual Street View
      return HtmlElementView(
        viewType: 'street-view-${widget.streetViewInstance.instanceId}',
      );
    }

    // Show loading indicator while initializing
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              _status,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
