import 'package:flutter/rendering.dart';

class GridImage extends AssetImage {
  static const GridImage darkMode = GridImage._("assets/brand/01-logos/grid-symbol-color-dark-1024.png");
  static const GridImage lightMode = GridImage._("assets/brand/01-logos/grid-symbol-color-1024.png");

  const GridImage._(super.assetName);
}
