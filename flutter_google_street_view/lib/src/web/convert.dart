import 'dart:core';
import 'dart:js_interop';

import 'package:google_maps/google_maps.dart' as gmaps;
import 'package:google_maps/google_maps_streetview.dart' as gmaps;

/// Convert StreetViewPanoramaOptions to StreetViewPanoramaOptions of gmap
Future<gmaps.StreetViewPanoramaOptions> toStreetViewPanoramaOptions(
    Map<String, dynamic> arg,
    {gmaps.StreetViewPanorama? current}) async {
  final result = gmaps.StreetViewPanoramaOptions();

  // Handle position/pano directly without service call
  if (arg['panoId'] != null) {
    result.pano = arg['panoId'];
  } else if (arg['position'] != null) {
    final position = arg['position'] as List;
    result.position = gmaps.LatLng(position[0], position[1]);
  }

  // Set all the UI options
  result.showRoadLabels = arg['streetNamesEnabled'] as bool? ?? true;
  result.clickToGo = arg['clickToGo'] as bool? ?? true;
  result.zoomControl = arg['zoomControl'] as bool? ?? true;
  result.addressControl = arg['addressControl'] as bool? ?? true;
  result.addressControlOptions = toStreetViewAddressControlOptions(arg);
  result.disableDefaultUI = arg['disableDefaultUI'] as bool? ?? false;
  result.disableDoubleClickZoom =
      arg['disableDoubleClickZoom'] as bool? ?? false;
  result.enableCloseButton = arg['enableCloseButton'] as bool? ?? false;
  result.fullscreenControl = arg['fullscreenControl'] as bool? ?? false;
  result.fullscreenControlOptions = toFullscreenControlOptions(arg);
  result.linksControl = arg['linksControl'] as bool? ?? true;
  result.motionTracking = arg['motionTracking'] as bool? ?? false;
  result.motionTrackingControl = arg['motionTrackingControl'] as bool? ?? false;
  result.motionTrackingControlOptions = toMotionTrackingControlOptions(arg);
  result.scrollwheel = arg['scrollwheel'] as bool? ?? true;
  result.panControl = arg['panControl'] as bool? ?? false;
  result.panControlOptions = toPanControlOptions(arg);
  result.zoomControlOptions = toZoomControlOptions(arg);
  result.visible = arg['visible'] as bool? ?? true;

  final currentPov = current?.pov;
  result.pov = gmaps.StreetViewPov()
    ..heading = arg['bearing'] ?? currentPov?.heading ?? 0
    ..pitch = arg['tilt'] ?? currentPov?.pitch ?? 0;
  result.zoom = arg['zoom'] as double?;

  return result;
}

gmaps.StreetViewSource toStreetSource(Map<String, dynamic> arg) {
  final source = arg['source'];
  return source == "outdoor"
      ? gmaps.StreetViewSource.OUTDOOR
      : gmaps.StreetViewSource.DEFAULT;
}

gmaps.StreetViewAddressControlOptions? toStreetViewAddressControlOptions(
    dynamic arg) {
  final pos = arg is Map ? arg["addressControlOptions"] : arg;
  return gmaps.StreetViewAddressControlOptions()
    ..position = toControlPosition(pos);
}

gmaps.FullscreenControlOptions? toFullscreenControlOptions(dynamic arg) {
  final pos = arg is Map ? arg["fullscreenControlOptions"] : arg;
  return gmaps.FullscreenControlOptions()..position = toControlPosition(pos);
}

gmaps.MotionTrackingControlOptions? toMotionTrackingControlOptions(
    dynamic arg) {
  final pos = arg is Map ? arg["motionTrackingControlOptions"] : arg;
  return gmaps.MotionTrackingControlOptions()
    ..position = toControlPosition(pos);
}

gmaps.PanControlOptions? toPanControlOptions(dynamic arg) {
  final pos = arg is Map ? arg["panControlOptions"] : arg;
  return gmaps.PanControlOptions()..position = toControlPosition(pos);
}

gmaps.ZoomControlOptions? toZoomControlOptions(dynamic arg) {
  final pos = arg is Map ? arg["zoomControlOptions"] : arg;
  return gmaps.ZoomControlOptions()..position = toControlPosition(pos);
}

gmaps.ControlPosition? toControlPosition(String? position) {
  return position == "bottom_center"
      ? gmaps.ControlPosition.BOTTOM_CENTER
      : position == "bottom_left"
          ? gmaps.ControlPosition.BOTTOM_LEFT
          : position == "bottom_right"
              ? gmaps.ControlPosition.BOTTOM_RIGHT
              : position == "left_bottom"
                  ? gmaps.ControlPosition.LEFT_BOTTOM
                  : position == "left_center"
                      ? gmaps.ControlPosition.LEFT_CENTER
                      : position == "left_top"
                          ? gmaps.ControlPosition.LEFT_TOP
                          : position == "right_bottom"
                              ? gmaps.ControlPosition.RIGHT_BOTTOM
                              : position == "right_center"
                                  ? gmaps.ControlPosition.RIGHT_CENTER
                                  : position == "right_top"
                                      ? gmaps.ControlPosition.RIGHT_TOP
                                      : position == "top_center"
                                          ? gmaps.ControlPosition.TOP_CENTER
                                          : position == "top_left"
                                              ? gmaps.ControlPosition.TOP_LEFT
                                              : position == "top_right"
                                                  ? gmaps
                                                      .ControlPosition.TOP_RIGHT
                                                  : null;
}

Map<String, dynamic> streetViewPanoramaLocationToJson(
    gmaps.StreetViewPanorama panorama) {
  final links = panorama.links.toDart;
  return linkToJson(links)
    ..["panoId"] = panorama.pano
    ..addAll(positionToJson(panorama.position));
}

Map<String, dynamic> streetViewPanoramaCameraToJson(
        gmaps.StreetViewPanorama panorama) =>
    {
      "bearing": panorama.pov.heading,
      "tilt": panorama.pov.pitch,
      "zoom": panorama.zoom
    };

Map<String, dynamic> positionToJson(gmaps.LatLng? position) => {
      "position": (position != null ? [position.lat, position.lng] : null)
    };

Map<String, dynamic> linkToJson(List<gmaps.StreetViewLink?>? links) {
  List links1 = [];
  if (links != null) {
    links.forEach((l) {
      if (l != null) links1.add([l.pano, l.heading]);
    });
  }
  return {"links": links1};
}

class NoStreetViewException implements Exception {
  final gmaps.StreetViewPanoramaOptions options;
  final String errorMsg;

  NoStreetViewException({required this.options, required this.errorMsg});
}
