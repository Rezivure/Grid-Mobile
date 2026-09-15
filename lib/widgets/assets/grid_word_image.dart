import 'package:flutter/rendering.dart';

class GridWordImage extends AssetImage {
  static const GridWordImage darkMode = GridWordImage._("assets/brand/02-wordmark/grid-wordmark-white-1800.png");
  static const GridWordImage lightMode = GridWordImage._("assets/brand/02-wordmark/grid-wordmark-ink-1800.png");

  const GridWordImage._(super.assetName);
}
