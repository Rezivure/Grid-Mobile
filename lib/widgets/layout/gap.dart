
import 'package:flutter/cupertino.dart';

class Gap extends SizedBox {

  static const Gap biggest = Gap(height: 24, width: 24);
  static const Gap bigger = Gap(height: 20, width: 20);
  static const Gap big = Gap(height: 16, width: 16);
  static const Gap normal = Gap(height: 12, width: 12);
  static const Gap small = Gap(height: 8, width: 8);
  static const Gap smaller = Gap(height: 6, width: 6);
  static const Gap smallest = Gap(height: 4, width: 4);

  const Gap({super.key, super.height, super.width});

  Widget get w => Gap(width: width);
  Widget get h => Gap(height: height);

}
