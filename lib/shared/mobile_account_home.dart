import 'package:flutter/material.dart';
import '../Customer/screens/home/customer_root_nav_screen.dart';
import '../Provider/screens/profile/my_profile_screen.dart';
import 'mobile_auth_service.dart';

Widget mobileAccountHome(MobileAccountRole role) => switch (role) {
  MobileAccountRole.customer => const CustomerRootNavScreen(),
  MobileAccountRole.provider => const MyProfileScreen(),
};
